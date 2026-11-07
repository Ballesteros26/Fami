#include "compiler.h"

#include <cstring>

#include "driver.h"
#include "song.h"

namespace gss {

namespace {
constexpr int KEYOFF_GAP_DURATION = 2;  // frames between keyoff and keyon, prevents clicks
constexpr int MAX_SHORT_WAIT = 148;     // longest one-byte delay
constexpr int CHN_LIMIT = 65536;
}  // namespace

Compiler::Compiler()
{
	std::memset(mem_, 0, sizeof(mem_));
	std::memset(spc_, 0, sizeof(spc_));
	std::memset(chn_mem_, 0, sizeof(chn_mem_));
	std::memset(chn_pack_, 0, sizeof(chn_pack_));
	std::memset(seq_buf_, 0, sizeof(seq_buf_));
	for (int& r : renumber_) r = -1;
	stats_.driver_size = (int)spc700_size - 2;
}

int Compiler::samples_compile(Module& m, int adr, int one_sample)
{
	int& count = stats_.instruments_count;
	count = 0;

	if (one_sample < 0) {
		for (int ins = 0; ins < MAX_INSTRUMENTS; ++ins) {
			const Instrument& i = m.instruments[ins];
			if (i.has_source() && i.length >= 16) renumber_[ins] = count++;
			else renumber_[ins] = -1;  // no sample in this slot
		}
	} else {
		for (int ins = 0; ins < MAX_INSTRUMENTS; ++ins) renumber_[ins] = -1;
		renumber_[one_sample] = 0;
		count = 1;
	}

	int dir_ptr = adr;
	adr += 4 * count;  // dir size
	int adsr_ptr = adr;
	adr += 2 * count;  // adsr list size
	int size = adr - dir_ptr;

	for (int ins = 0; ins < MAX_INSTRUMENTS; ++ins) {
		if (renumber_[ins] < 0) continue;

		const Instrument& i = m.instruments[ins];
		const BrrSample brr = encoder_.encode(i);
		const int brr_size = (int)brr.data.size();
		const int sample_adr = adr;
		int sample_loop;
		int match = -1;

		if (one_sample < 0) {
			for (int prev = 0; prev < ins; ++prev) {
				if (brr_size_[prev] == brr_size && brr_adr_[prev] + brr_size <= 65536 &&
				    (brr_size == 0 || !std::memcmp(&mem_[brr_adr_[prev]], brr.data.data(), brr_size))) {
					match = prev;
					break;
				}
			}
		}

		if (match < 0) {  // new sample
			brr_adr_[ins] = sample_adr;
			brr_size_[ins] = brr_size;

			for (int b = 0; b < brr_size; ++b) {
				mem_[adr] = brr.data[b];
				++adr;
				if (adr >= 65536) return -1;
			}

			sample_loop = (brr.loop_block > 0) ? sample_adr + brr.loop_block * 9 : sample_adr;

			mem_[dir_ptr + 0] = sample_adr & 255;
			mem_[dir_ptr + 1] = (sample_adr >> 8) & 255;
			mem_[dir_ptr + 2] = sample_loop & 255;
			mem_[dir_ptr + 3] = (sample_loop >> 8) & 255;

			size += brr_size;
		} else {  // duplicate of an earlier sample, share its data
			sample_loop = (brr.loop_block > 0) ? brr_adr_[match] + brr.loop_block * 9 : brr_adr_[match];

			mem_[dir_ptr + 0] = brr_adr_[match] & 255;
			mem_[dir_ptr + 1] = (brr_adr_[match] >> 8) & 255;
			mem_[dir_ptr + 2] = sample_loop & 255;
			mem_[dir_ptr + 3] = (sample_loop >> 8) & 255;
		}

		dir_ptr += 4;

		mem_[adsr_ptr + 0] = (uint8_t)(0x80 | i.env_ar | (i.env_dr << 4));
		mem_[adsr_ptr + 1] = (uint8_t)(i.env_sr | (i.env_sl << 5));
		adsr_ptr += 2;
	}

	return size;
}

int Compiler::delay_compile(int adr, int delay)
{
	// A negative delay (a loop point keyoff right after a short row) is
	// emitted as one wrapped byte, as the original did.
	while (delay) {
		if (adr + 3 > CHN_LIMIT) {
			overflow_ = true;
			return adr;
		}
		if (delay < MAX_SHORT_WAIT * 2) {  // one or two one-byte delays
			if (delay >= MAX_SHORT_WAIT) {
				chn_mem_[adr++] = MAX_SHORT_WAIT;
				delay -= MAX_SHORT_WAIT;
			} else {
				chn_mem_[adr++] = (uint8_t)delay;
				delay = 0;
			}
		} else {  // long delay, 3 bytes
			if (delay >= 65535) {
				chn_mem_[adr++] = 246;
				chn_mem_[adr++] = 255;
				chn_mem_[adr++] = 255;
				delay -= 65535;
			} else {
				chn_mem_[adr++] = 246;
				chn_mem_[adr++] = delay & 255;
				chn_mem_[adr++] = (delay >> 8) & 255;
				delay = 0;
			}
		}
	}
	return adr;
}

int Compiler::channel_compile(const Song& s, int chn, int start_row, int compile_adr, int& play_adr)
{
	int adr = 0, loop_adr = 0;
	int speed = 20, speed_acc = 0;
	int ins_change = 0, ins_last = 1;
	int effect = 0, value = 0, effect_volume = 255;
	bool insert_gap = false, key_is_on = false, porta_active = false;

	play_adr = 0;

	int length = s.length;
	int loop_start = s.loop_start;

	// With the loop markers in their default positions, loop on the row after
	// the last non-empty one, so the song seems not to loop.
	if (!loop_start && length == MAX_ROWS - 1) {
		length = song_find_last_row(s) + 2;
		loop_start = length - 1;
	}

	if (length > MAX_ROWS) length = MAX_ROWS;

	auto emit = [&](int byte) {
		if (adr < CHN_LIMIT) chn_mem_[adr++] = (uint8_t)byte;
		else overflow_ = true;
	};

	for (int row = 0; row < length; ++row) {
		bool change = false;

		if (row == loop_start || row == start_row) {  // break ongoing delays at the start and loop points
			adr = delay_compile(adr, speed_acc);
			speed_acc = 0;
		}

		if (row == start_row) {
			play_adr = adr;
			if (row) {  // force an instrument change when starting mid-song
				ins_change = ins_last;
				change = true;
			}
		}

		if (row == loop_start) loop_adr = adr;

		const Row& r = s.row(row);
		if (r.speed) speed = r.speed;

		const NoteField& n = r.chn[chn];

		if (n.instrument) {
			ins_change = n.instrument;
			ins_last = ins_change;
		}

		if (n.effect && n.value != 255) {
			effect = n.effect;
			value = n.value;
			change = true;
		}

		if (n.volume != 255) {
			effect_volume = n.volume;
			change = true;
		}

		if (n.note) change = true;

		if (change) {
			// detect portamento early to avoid inserting the keyoff gap
			if (effect == 'P') porta_active = value != 0;

			// a note (not keyoff) with enough empty space before it gets a keyoff and a gap
			if (n.note > 1 && key_is_on && !porta_active && speed_acc >= KEYOFF_GAP_DURATION) {
				speed_acc -= KEYOFF_GAP_DURATION;
				insert_gap = true;
			} else {
				insert_gap = false;
			}

			adr = delay_compile(adr, speed_acc);
			speed_acc = 0;

			if (n.note == 1) {
				emit(245);  // keyoff
				key_is_on = false;
			}

			if (effect == 'T') {  // detune
				emit(249);
				emit(value);
				effect = 0;
			}
			if (effect == 'D') {  // slide down
				emit(250);
				emit(-value);
				effect = 0;
			}
			if (effect == 'U') {  // slide up
				emit(250);
				emit(value);
				effect = 0;
			}
			if (effect == 'P') {  // portamento
				emit(251);
				emit(value);
				effect = 0;
			}
			if (effect == 'V') {  // vibrato: decimal digits into nibbles, reversed
				emit(252);
				emit((value / 10 % 10) | ((value % 10) << 4));
				effect = 0;
			}
			if (effect == 'S') {  // pan: 0..50..99 to 0..128..255
				emit(248);
				emit(value * 256 / 100);
				effect = 0;
			}

			const bool new_note_keyoff = key_is_on && insert_gap && !porta_active;

			// volume goes here unless a new note follows a keyoff, then after the keyoff
			if ((n.note < 2 && !new_note_keyoff) && effect_volume != 255) {
				emit(247);
				emit((int)((float)effect_volume * 1.29f));  // 0..99 to 0..127
				effect_volume = 255;
			}

			if (n.note > 1) {
				if (new_note_keyoff) {
					emit(245);
					adr = delay_compile(adr, KEYOFF_GAP_DURATION);
					key_is_on = false;
				}

				if (ins_change) {
					emit(254);
					int ins = renumber_[ins_change - 1 < MAX_INSTRUMENTS ? ins_change - 1 : 0];
					// the first 9 sample dir entries are reserved for the BRR
					// streamer; entry 8 is the sync sample and always empty
					if (ins < 0) ins = 8;
					else ins += 9;
					emit(ins);
					ins_change = 0;
				}

				if (effect_volume != 255) {  // volume after the keyoff, prevents clicks
					emit(247);
					emit((int)((float)effect_volume * 1.29f));
					effect_volume = 255;
				}

				emit((n.note - 2) + 150);
				key_is_on = true;
			}
		}

		speed_acc += speed;
	}

	const NoteField& n = s.row(loop_start >= 0 && loop_start < MAX_ROWS ? loop_start : 0).chn[chn];

	// a new note at the loop point: keyoff with a gap at the end of the channel prevents a click
	if (n.note > 1) speed_acc -= KEYOFF_GAP_DURATION;

	adr = delay_compile(adr, speed_acc);

	if (n.note > 1) {
		emit(245);
		adr = delay_compile(adr, KEYOFF_GAP_DURATION);
	}

	play_adr += compile_adr;
	loop_adr += compile_adr;

	emit(255);
	emit(loop_adr & 255);
	emit((loop_adr >> 8) & 255);

	if (overflow_) return 0;

	const int size = adr;

	// compression: try every reference length, keep the smallest result
	int min_size = 65536;
	int best_ref_len = 64;

	for (int ref_len = 5; ref_len <= 64; ++ref_len) {
		int new_play_adr = play_adr;
		const int new_size = channel_compress(compile_adr, new_play_adr, loop_adr, size, ref_len);
		if (new_size < min_size) {
			min_size = new_size;
			best_ref_len = ref_len;
		}
	}

	const int packed = channel_compress(compile_adr, play_adr, loop_adr, size, best_ref_len);

	if (overflow_ || compile_adr + packed > 65536) {
		overflow_ = true;
		return 0;
	}

	std::memcpy(&mem_[compile_adr], chn_pack_, packed);
	return packed;
}

void Compiler::channel_compress_flush(int compile_adr)
{
	const int ref_len = seq_ptr_;
	seq_ptr_ = 0;

	if (!ref_len) return;

	int ref_off = -1;
	for (int i = 0; i < out_ptr_ - ref_len; ++i) {
		if (!std::memcmp(&chn_pack_[i], seq_buf_, ref_len)) {
			ref_off = compile_adr + i;
			break;
		}
	}

	if (out_ptr_ + (ref_len > 4 ? ref_len : 4) > CHN_LIMIT) {
		overflow_ = true;
		return;
	}

	if (ref_off < 0) {
		std::memcpy(&chn_pack_[out_ptr_], seq_buf_, ref_len);
		out_ptr_ += ref_len;
	} else {
		chn_pack_[out_ptr_++] = 253;
		chn_pack_[out_ptr_++] = ref_off & 255;
		chn_pack_[out_ptr_++] = (ref_off >> 8) & 255;
		chn_pack_[out_ptr_++] = (uint8_t)ref_len;
	}
}

int Compiler::channel_compress(int compile_adr, int& play_adr, int loop_adr, int src_size, int ref_max)
{
	std::memset(chn_pack_, 0, sizeof(chn_pack_));

	seq_ptr_ = 0;
	out_ptr_ = 0;

	int src_ptr = 0;
	int new_loop_adr = -1;
	int new_play_adr = -1;

	while (src_ptr < src_size) {
		if (new_loop_adr < 0 && src_ptr == loop_adr - compile_adr) {
			channel_compress_flush(compile_adr);
			new_loop_adr = compile_adr + out_ptr_;
		}

		if (new_play_adr < 0 && src_ptr == play_adr - compile_adr) {
			channel_compress_flush(compile_adr);
			new_play_adr = compile_adr + out_ptr_;
		}

		int len;
		switch (chn_mem_[src_ptr]) {
		case 247:
		case 248:
		case 249:
		case 250:
		case 251:
		case 252:
		case 254: len = 2; break;
		case 253: len = 4; break;
		case 246:
		case 255: len = 3; break;
		default: len = 1;
		}

		for (int i = 0; i < len; ++i) seq_buf_[seq_ptr_++] = chn_mem_[src_ptr++];

		if (seq_ptr_ >= ref_max) channel_compress_flush(compile_adr);
	}

	channel_compress_flush(compile_adr);

	if (new_play_adr < 0) new_play_adr = compile_adr;
	if (new_loop_adr < 0) new_loop_adr = compile_adr;

	if (out_ptr_ >= 2) {
		chn_pack_[out_ptr_ - 2] = new_loop_adr & 255;
		chn_pack_[out_ptr_ - 1] = (new_loop_adr >> 8) & 255;
	}

	play_adr = new_play_adr;
	return out_ptr_;
}

int Compiler::song_compile(Song& s_original, int start_row, int start_adr, bool mute)
{
	s_original.compiled_size = 0;

	if (start_row >= s_original.length) return 0;  // starting outside the song

	work_ = s_original;
	work_.allocate();
	Song& s = work_;

	song_clean_up(s);  // drop repeated instrument numbers and volumes

	// expand repeated sections
	for (int chn = 0; chn < CHANNELS; ++chn) {
		int section_start = 0, section_end = 0;
		bool repeat = false;
		int repeat_row = 0;

		for (int row = 0; row < MAX_ROWS; ++row) {
			if (s.row(row).marker) {
				section_start = section_end;
				section_end = row;
				repeat = false;
			}

			NoteField& n = s.row_mut(row).chn[chn];

			if (n.effect == 'R') {
				repeat = true;
				repeat_row = section_start;
			}

			if (repeat) {
				const NoteField m = s.row(repeat_row).chn[chn];
				n.note = m.note;
				n.instrument = m.instrument;
				n.effect = (m.effect != 'R') ? m.effect : 0;
				n.value = m.value;

				++repeat_row;
				if (repeat_row >= section_end) repeat_row = section_start;
			}
		}
	}

	// starting mid-song: carry the last instrument and volume into the start row
	if (start_row > 0) {
		for (int chn = 0; chn < CHANNELS; ++chn) {
			NoteField& n = s.row_mut(start_row).chn[chn];
			bool find_ins = true, find_vol = true;

			for (int row = start_row - 1; row >= 0; --row) {
				if (!find_ins && !find_vol) break;
				const NoteField& m = s.row(row).chn[chn];

				if (find_ins && m.instrument) {
					if (!n.instrument) n.instrument = m.instrument;
					find_ins = false;
				}
				if (find_vol && m.volume != 255) {
					if (n.volume == 255) n.volume = m.volume;
					find_vol = false;
				}
			}
		}
	}

	bool active[CHANNELS];
	int channels_all = 0;

	for (int chn = 0; chn < CHANNELS; ++chn) {
		active[chn] = !(channel_is_empty(s, chn) || (channel_mute[chn] && mute));
		if (all_channels) {
			if (!active[chn])  // a rest throughout, holding the channel's place
				for (int row = 0; row < MAX_ROWS; ++row) s.row_mut(row).chn[chn] = NoteField{};
			active[chn] = true;
		}
		if (active[chn]) ++channels_all;
	}

	// default instrument for the first note of each channel
	for (int chn = 0; chn < CHANNELS; ++chn) {
		for (int row = 0; row < MAX_ROWS; ++row) {
			NoteField& n = s.row_mut(row).chn[chn];
			if (n.note > 1) {
				if (!n.instrument) n.instrument = 1;
				break;
			}
		}
	}

	if (start_adr < 0 || start_adr + 1 + channels_all * 2 > 65536) return -1;

	int adr = start_adr + 1 + channels_all * 2;
	int channels_off = start_adr + 1;

	overflow_ = false;

	for (int chn = 0; chn < CHANNELS; ++chn) {
		if (!active[chn]) continue;

		int play_adr;
		const int chn_size = channel_compile(s, chn, start_row, adr, play_adr);
		if (overflow_) return -1;

		mem_[channels_off + 0] = play_adr & 255;
		mem_[channels_off + 1] = (play_adr >> 8) & 255;
		channels_off += 2;

		adr += chn_size;
	}

	mem_[start_adr] = (uint8_t)channels_all;

	s_original.compiled_size = adr - start_adr;
	return s_original.compiled_size;
}

int Compiler::effects_compile(Module& m, int start_adr)
{
	int effects_all = 0;
	for (const Song& s : m.songs)
		if (s.effect) ++effects_all;

	if (start_adr + 1 + effects_all * 2 > 65536) return -1;

	int adr = start_adr + 1 + effects_all * 2;
	mem_[start_adr] = (uint8_t)effects_all;
	int effects_off = start_adr + 1;

	for (Song& s : m.songs) {
		if (!s.effect) continue;
		if (song_is_empty(s)) continue;

		mem_[effects_off + 0] = adr & 255;
		mem_[effects_off + 1] = (adr >> 8) & 255;
		effects_off += 2;

		const int size = song_compile(s, 0, adr, false);
		if (size < 0) return -1;
		adr += size;
	}

	return adr - start_adr;
}

bool Compiler::spc_compile(Module& m, Song& s, int start_row, bool mute, bool effects, int one_sample, std::string* error)
{
	const int header_size = 2;  // extra length header used by sneslib
	const int code_adr = DRIVER_ADDRESS;

	stats_.music_size = 0;
	stats_.effects_size = 0;

	std::memcpy(&mem_[code_adr], spc700_data + header_size, spc700_size - header_size);

	const int sample_adr = code_adr + (int)spc700_size - header_size;

	if (update_samples_ || one_sample >= 0) {  // only recompile samples when needed
		std::memset(&mem_[sample_adr], 0, 65536 - sample_adr);

		update_samples_ = one_sample >= 0;
		stats_.instruments_size = samples_compile(m, sample_adr, one_sample);

		if (stats_.instruments_size < 0) {
			stats_.instruments_size = 0;
			update_samples_ = true;
			if (error) *error = "SPC700 memory overflow, too much sample data";
			return false;
		}
	}

	const int adsr_adr = sample_adr + 4 * stats_.instruments_count;
	const int effects_adr = sample_adr + stats_.instruments_size;

	if (effects) {
		stats_.effects_size = effects_compile(m, effects_adr);
		if (stats_.effects_size < 0) {
			stats_.effects_size = 0;
			if (error) *error = "SPC700 memory overflow, too much sound effects data";
			return false;
		}
	}

	const int music_adr = effects_adr + stats_.effects_size;

	stats_.music_size = song_compile(s, start_row, music_adr, mute);
	if (stats_.music_size < 0) {
		stats_.music_size = 0;
		if (error) *error = "SPC700 memory overflow, too much music data";
		return false;
	}

	if (!effects) {  // preview: skip the bra mainLoopInit, run the preinitialized driver
		mem_[0x204] = 0;
		mem_[0x205] = 0;
	}

	mem_[0x208] = (adsr_adr - 9 * 2) & 255;
	mem_[0x209] = ((adsr_adr - 9 * 2) >> 8) & 255;
	mem_[0x20a] = effects_adr & 255;
	mem_[0x20b] = (effects_adr >> 8) & 255;
	mem_[0x20c] = music_adr & 255;
	mem_[0x20d] = (music_adr >> 8) & 255;

	// .spc file
	std::memset(spc_, 0, sizeof(spc_));
	std::memcpy(spc_, "SNES-SPC700 Sound File Data v0.30", 32);
	spc_[0x21] = 26;
	spc_[0x22] = 26;
	spc_[0x23] = 27;  // no ID tag
	spc_[0x24] = 30;  // version minor
	spc_[0x25] = code_adr & 255;  // PC
	spc_[0x26] = code_adr >> 8;
	// A, X, Y, PSW, SP and the DSP registers stay zero
	std::memcpy(&spc_[0x100], mem_, sizeof(mem_));

	stats_.mem_top = music_adr;
	return true;
}

void Compiler::compile_all_songs(Module& m)
{
	stats_.music_largest = 0;

	for (Song& s : m.songs) {
		if (song_is_empty(s)) continue;
		song_compile(s, 0, stats_.mem_top, false);
		if (s.compiled_size > stats_.music_largest) stats_.music_largest = s.compiled_size;
	}
}

}  // namespace gss
