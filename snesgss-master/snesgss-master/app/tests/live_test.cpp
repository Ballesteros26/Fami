// Live updates: moving a playing preview onto a newer compile, with the
// driver running in the emulator.
#include <cmath>
#include <cstdio>
#include <cstring>
#include <functional>
#include <memory>
#include <vector>

#include "compiler.h"
#include "live.h"
#include "song.h"
#include "spc_player.h"

static int failures = 0;
#define CHECK(c)                                                                \
	do {                                                                        \
		if (!(c)) {                                                             \
			std::printf("%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #c); \
			++failures;                                                         \
		}                                                                       \
	} while (0)

using namespace gss;

constexpr int RATE = 32000;              // the SPC700's own rate, as the app plays it: a tick is 200 frames
constexpr double FRAMES_PER_TICK = 200;  // 32000 / 160

// A looped sine instrument, and a song looping over 64 rows with a C-4 on
// channel 1 every 4 rows (repeats the compiler compresses into references).
static void make_module(Module& m)
{
	Instrument& ins = m.instruments[0];
	ins.name = "sine";
	ins.source.resize(512);
	for (int i = 0; i < 512; ++i) ins.source[i] = (int16_t)(12000 * std::sin(2 * 3.14159265358979 * 4 * i / 512));
	ins.source_length = ins.length = 512;
	ins.source_rate = 8344;
	ins.loop_enable = true;
	ins.loop_start = 0;
	ins.loop_end = 511;

	Song& s = m.songs[0];
	s.length = 64;
	s.loop_start = 0;
	s.row_mut(0).speed = 20;
	for (int row = 0; row < 64; row += 4) {
		s.row_mut(row).chn[0].note = 50;
		s.row_mut(row).chn[0].instrument = 1;
	}
}

static LiveSong compile(Compiler& c, Module& m, Song& s)
{
	c.all_channels = true;
	std::string error;
	const bool ok = c.spc_compile(m, s, 0, true, false, -1, &error);
	c.all_channels = false;
	CHECK(ok);
	const LiveSong live(c.aram(), c.stats().mem_top + c.stats().music_size, SongTiming(s, 0));
	CHECK(live.valid());
	return live;
}

static void render(SpcPlayer& p, int frames)
{
	std::vector<int16_t> buf(2048);
	while (frames > 0) {
		const int n = frames < 1024 ? frames : 1024;
		p.render(buf.data(), n);
		frames -= n;
	}
}

static double rms(const std::vector<int16_t>& v)
{
	double s = 0;
	for (int16_t x : v) s += (double)x * x;
	return std::sqrt(s / (double)v.size());
}

static DriverIdle idle_of_driver()
{
	DriverIdle idle;
	CHECK(driver_idle(idle));
	return idle;
}
static const DriverIdle IDLE = idle_of_driver();
// A patch as the app queues it: render() makes it when the driver idles.
static bool queued_patch(SpcPlayer& p, const std::function<void(uint8_t* ram, long long frames)>& f)
{
	bool ran = false;
	p.queue_patch([&](uint8_t* ram, int pc, long long frames) {
		if (!IDLE.contains(pc)) return false;
		f(ram, frames);
		return ran = true;
	});
	render(p, 1024);  // well over a tick: the driver idles in it
	return ran;
}

// The song's time from the driver's state, by each channel: all agree.
static double driver_time(SpcPlayer& p, const LiveSong& song)
{
	double t = -1;
	bool agree = false;
	CHECK(queued_patch(p, [&](uint8_t* ram, long long) {
		agree = true;
		for (int c = 0; c < CHANNELS; ++c) {
			const DriverPlace place{ram[0x48 + c] | (ram[0x50 + c] << 8), ram[0xb8 + c], ram[0xc0 + c] | (ram[0xc8 + c] << 8)};
			double tick;
			if (!song.walks[(size_t)c].time_of(place, ram[0x58 + c] | (ram[0x60 + c] << 8), tick)) {
				agree = false;
				return;
			}
			if (c == 0) t = tick;
			else if (tick != t) agree = false;
		}
	}));
	CHECK(agree);
	return agree ? t : -1;
}

static void test_walk()
{
	auto m = std::make_unique<Module>();
	make_module(*m);
	Compiler c;
	const LiveSong song = compile(c, *m, m->songs[0]);
	CHECK(song.walks.size() == CHANNELS);  // all eight, the empty ones as rests

	for (int ch = 0; ch < CHANNELS; ++ch) {
		const ChannelWalk& w = song.walks[(size_t)ch];
		CHECK(w.loop_ticks == 64 * 20);  // the whole song loops
		CHECK(w.sounds == (ch == 0));
		CHECK(w.points.front().tick == 0);
	}

	// the data is compressed: channel 1 reads references
	const ChannelWalk& w0 = song.walks[0];
	bool in_reference = false;
	for (const ChannelWalk::Point& pt : w0.points) in_reference = in_reference || pt.place.ref_len > 0;
	CHECK(in_reference);

	// a place in the walk gives its time back, and a time its place
	DriverPlace place;
	int wait;
	CHECK(w0.place_at(250, place, wait));
	double t;
	CHECK(w0.time_of(place, wait, t));
	CHECK(t == 250);
	CHECK(w0.place_at(250 + 64 * 20 * 3, place, wait));  // three loops on: the same place
	CHECK(w0.time_of(place, wait, t));
	CHECK(t == 250);

	CHECK(IDLE.loop_lo == 0x022a && IDLE.loop_hi == 0x024d);  // mainLoop up to the frame's update calls
	CHECK(IDLE.sub_lo == 0x0714 && IDLE.sub_hi == 0x0728);    // updateBRRStreamerPos
}

static void test_live_patch()
{
	auto m = std::make_unique<Module>();
	make_module(*m);
	Compiler c;
	const LiveSong a = compile(c, *m, m->songs[0]);

	SpcPlayer p(RATE);
	CHECK(p.play(c.spc_image(), SPC_FILE_SIZE));
	render(p, 22400);  // 0.7 s: row 5 or so

	// the edit: channel 2 plays at rows 20 and 24, ahead of the song, and
	// from row 32 on rows are half as long
	Song& s = m->songs[0];
	s.row_mut(20).chn[1].note = 50;
	s.row_mut(20).chn[1].instrument = 1;
	s.row_mut(24).chn[1].note = 50;
	s.row_mut(32).speed = 10;
	const LiveSong b = compile(c, *m, s);
	const SongTiming& timing_b = b.timing;
	CHECK(!b.same_as(a));

	const double before = driver_time(p, a);
	CHECK(before > 90 && before < 135);

	double t_new = -1;
	long long frames_at = 0;
	bool moved = false;
	CHECK(queued_patch(p, [&](uint8_t* ram, long long frames) {
		frames_at = frames;
		moved = live_patch(ram, a, b, &t_new);
	}));
	CHECK(moved);
	CHECK(t_new > before && t_new < before + 8);  // the same place, a tick or so on: nothing changed before row 32

	// one second on, every channel (the new one too) is where song B says
	render(p, 32000);
	double now = driver_time(p, b);
	// at the time the place was read, which a queued read takes a little after its render
	double expected = t_new + (double)(p.frames_played() - frames_at) / FRAMES_PER_TICK;
	CHECK(now >= 0 && now <= expected && now >= expected - 1024 / FRAMES_PER_TICK - 1);

	// rows 21-23: channel 2's note joins channel 1's; the sound doubles
	auto level_at = [&](double tick) {
		now = driver_time(p, b);
		render(p, (int)((tick - now) * FRAMES_PER_TICK));
		std::vector<int16_t> buf(2 * 1024);
		p.render(buf.data(), 1024);
		return rms(buf);
	};
	const double one = level_at(timing_b.time_of(17, 10)), two = level_at(timing_b.time_of(21, 10));
	CHECK(two > one * 1.6);

	// past row 32, into the half-length rows: still in step
	render(p, (int)((timing_b.time_of(36, 0) - driver_time(p, b)) * FRAMES_PER_TICK));
	now = driver_time(p, b);
	int row;
	double into;
	timing_b.locate(now, row, into);
	CHECK(row >= 35 && row <= 37);

	// muting channel 1: keyed off at once
	c.channel_mute[0] = true;
	const LiveSong muted = compile(c, *m, s);
	c.channel_mute[0] = false;
	bool keyed_off = false;
	CHECK(queued_patch(p, [&](uint8_t* ram, long long) {
		keyed_off = live_patch(ram, b, muted) && (ram[0x09] & 1) != 0;
	}));
	CHECK(keyed_off);
}

int main()
{
	test_walk();
	test_live_patch();
	if (failures) {
		std::printf("live_test: %d check(s) failed\n", failures);
		return 1;
	}
	std::printf("live_test: all checks passed\n");
	return 0;
}
