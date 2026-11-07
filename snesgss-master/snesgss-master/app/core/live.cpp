#include "live.h"

#include <algorithm>
#include <cmath>

#include "compiler.h"
#include "driver.h"

namespace gss {

namespace {

// snes/spc700.asm: direct page variables, eight bytes each for the M_ ones
constexpr int D_ADSR_L = 0x04, D_ADSR_H = 0x05, D_KOF = 0x09;
constexpr int M_PTR_L = 0x48, M_PTR_H = 0x50, M_WAIT_L = 0x58, M_WAIT_H = 0x60;
constexpr int M_REF_LEN = 0xb8, M_REF_RET_L = 0xc0, M_REF_RET_H = 0xc8;
// and the pointers after the code's first instructions
constexpr int SAMPLE_ADSR_PTR = 0x208, MUSIC_DATA_PTR = 0x20c;
// the IPL ROM can be mapped over the top of RAM: leave it alone
constexpr int RAM_TOP = 0xffc0;

int word(const uint8_t* m, int adr) { return m[adr] | (m[(adr + 1) & 0xffff] << 8); }

}  // namespace

ChannelWalk walk_channel(const uint8_t* ram, int start)
{
	ChannelWalk w;
	DriverPlace at{start & 0xffff, 0, 0};
	double tick = 0;

	// readChannelByte: a byte, and the end of a reference returns
	auto read = [&]() {
		const int b = ram[at.ptr];
		at.ptr = (at.ptr + 1) & 0xffff;
		if (at.ref_len && --at.ref_len == 0) at.ptr = at.ret;
		return b;
	};
	// a place reading resumes at; false when it was read before: the loop
	auto resume = [&]() {
		const auto [it, added] = w.index.emplace(at.key(), (int)w.points.size());
		if (added) {
			w.points.push_back({tick, at});
			return true;
		}
		w.loop_point = it->second;
		w.loop_ticks = tick - w.points[(size_t)it->second].tick;
		return false;
	};

	resume();
	for (int guard = 0; guard < 1 << 20; ++guard) {
		const int c = read();
		if (c < 149 || c == 246) {  // a wait: short, or long with two bytes
			int wait = c;
			if (c == 246) {
				const int lo = read();
				wait = lo | (read() << 8);
			}
			tick += wait > 0 ? wait : 1;  // a wait of 0 still takes a tick
			if (!resume()) break;
		} else if (c < 245) {  // a note
			w.sounds = true;
		} else if (c == 253) {  // reference: plays len bytes at adr, then returns
			const int lo = read();
			const int hi = read();
			const int len = read();
			at.ret = at.ptr;
			at.ref_len = len;
			at.ptr = lo | (hi << 8);
		} else if (c == 255) {  // jump: the loop, read on at once
			const int lo = read();
			at.ptr = lo | (read() << 8);
			if (!resume()) break;
		} else if (c != 245) {  // 247..252, 254: one parameter (245 is a key off)
			read();
		}
	}
	return w;
}

bool ChannelWalk::time_of(const DriverPlace& place, int wait, double& tick) const
{
	const auto it = index.find(place.key());
	if (it == index.end()) return false;
	tick = points[(size_t)it->second].tick - wait;
	return true;
}

bool ChannelWalk::place_at(double tick, DriverPlace& place, int& wait) const
{
	if (points.empty()) return false;
	// past the end of the first pass: the same time in the loop
	const double loop_start = points[(size_t)loop_point].tick;
	if (loop_ticks > 0 && tick >= loop_start + loop_ticks) tick = loop_start + std::fmod(tick - loop_start, loop_ticks);

	const auto it = std::upper_bound(points.begin(), points.end(), tick, [](double t, const Point& p) { return t < p.tick; });
	if (it != points.end()) {
		place = it->place;
		wait = (int)std::ceil(it->tick - tick);
		return true;
	}
	// after the last point: round the loop to its start
	if (loop_ticks <= 0) return false;
	place = points[(size_t)loop_point].place;
	wait = (int)std::ceil(loop_start + loop_ticks - tick);
	return wait > 0;
}

LiveSong::LiveSong(const uint8_t* aram, int music_end, const SongTiming& t)
    : image(aram, aram + 65536), end(std::min(music_end, 65536)), timing(t)
{
	const int music = word(aram, MUSIC_DATA_PTR);
	if (aram[music] != CHANNELS) return;  // not all eight: no walks, not valid
	for (int c = 0; c < CHANNELS; ++c) walks.push_back(walk_channel(aram, word(aram, music + 1 + c * 2)));
}

bool LiveSong::same_as(const LiveSong& o) const
{
	const int last = std::max(end, o.end);
	return std::equal(image.begin() + DRIVER_ADDRESS, image.begin() + last, o.image.begin() + DRIVER_ADDRESS);
}

bool driver_idle(DriverIdle& idle)
{
	// commandDone: jsr updateBRRStreamerPos; lda T0OT; beq mainLoop;
	// jsr updateGlobalVolume; jsr updateMusicPlayer; bra mainLoop
	const unsigned char* code = spc700_data + 2;  // after the length header
	const int size = (int)spc700_size - 2;
	for (int i = 3; i + 11 <= size; ++i)
		if (code[i - 3] == 0x3f && code[i] == 0xe4 && code[i + 1] == 0xfd && code[i + 2] == 0xf0 && code[i + 4] == 0x3f &&
		    code[i + 7] == 0x3f && code[i + 10] == 0x2f) {
			const int adr = DRIVER_ADDRESS + i;
			idle.loop_lo = adr + 4 + (int8_t)code[i + 3];  // mainLoop
			idle.loop_hi = adr + 4;                        // the update calls
			idle.sub_lo = code[i - 2] | (code[i - 1] << 8);
			int end = idle.sub_lo - DRIVER_ADDRESS;  // its rts
			while (end >= 0 && end < size && code[end] != 0x6f) ++end;
			idle.sub_hi = DRIVER_ADDRESS + end + 1;
			return idle.loop_lo < idle.loop_hi && end < size;
		}
	return false;
}

bool live_patch(uint8_t* ram, const LiveSong& from, const LiveSong& to, double* tick)
{
	if (!from.valid() || !to.valid()) return false;

	// the song's time: from the first channel whose place is in its walk
	double old_tick = 0;
	bool found = false;
	for (int c = 0; c < CHANNELS && !found; ++c) {
		const DriverPlace place{ram[M_PTR_L + c] | (ram[M_PTR_H + c] << 8), ram[M_REF_LEN + c],
		                        ram[M_REF_RET_L + c] | (ram[M_REF_RET_H + c] << 8)};
		found = from.walks[(size_t)c].time_of(place, ram[M_WAIT_L + c] | (ram[M_WAIT_H + c] << 8), old_tick);
	}
	if (!found) return false;

	// the same row, as far into it as the new speed allows
	int row;
	double into;
	from.timing.locate(old_tick, row, into);
	if (into > 0) into = std::min(into, to.timing.speed(row) - 1.0);
	const double new_tick = to.timing.time_of(row, into);

	// where each channel goes; nothing is written unless all are found
	DriverPlace places[CHANNELS];
	int waits[CHANNELS];
	for (int c = 0; c < CHANNELS; ++c)
		if (!to.walks[(size_t)c].place_at(new_tick, places[c], waits[c])) return false;

	for (int adr = DRIVER_ADDRESS; adr < RAM_TOP; ++adr) ram[adr] = to.image[(size_t)adr];
	ram[D_ADSR_L] = to.image[SAMPLE_ADSR_PTR];  // the ADSR list moves with the samples
	ram[D_ADSR_H] = to.image[SAMPLE_ADSR_PTR + 1];

	for (int c = 0; c < CHANNELS; ++c) {
		ram[M_PTR_L + c] = places[c].ptr & 255;
		ram[M_PTR_H + c] = (places[c].ptr >> 8) & 255;
		ram[M_REF_LEN + c] = (uint8_t)places[c].ref_len;
		ram[M_REF_RET_L + c] = places[c].ret & 255;
		ram[M_REF_RET_H + c] = (places[c].ret >> 8) & 255;
		ram[M_WAIT_L + c] = waits[c] & 255;
		ram[M_WAIT_H + c] = (waits[c] >> 8) & 255;
		if (!to.walks[(size_t)c].sounds) ram[D_KOF] |= (uint8_t)(1 << c);  // a muted or emptied channel stops
	}
	if (tick) *tick = new_tick;
	return true;
}

}  // namespace gss
