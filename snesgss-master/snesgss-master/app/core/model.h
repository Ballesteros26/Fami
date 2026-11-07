// SNES GSS project data model.
//
// Field encodings are kept exactly as in the original editor so the compiler
// can be ported line for line:
//   note        0 = empty, 1 = key off, 2..97 = C-0..B-7
//   instrument  0 = none, 1..99
//   effect      0 = none, otherwise an ASCII letter
//   value       0..99, 255 = empty
//   volume      0..99, 255 = empty
#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace gss {

constexpr int MAX_INSTRUMENTS = 99;
constexpr int MAX_SONGS = 99;
constexpr int MAX_ROWS = 10000;
constexpr int CHANNELS = 8;

constexpr int UPDATE_RATE_HZ = 160;  // quantization of music events in the driver
constexpr int DEFAULT_SPEED = 20;    // UPDATE_RATE_HZ/(120/60*4), 120 BPM

constexpr const char* VERSION_STR = "SNES GSS v1.51";

struct Instrument {
	// 16-bit mono source PCM. Empty means the slot has no sample. When not
	// empty it holds at least source_length (and length) samples.
	std::vector<int16_t> source;
	int source_length = 0;
	int source_rate = 0;
	int source_volume = 128;  // 0..255, 128 is unity

	int env_ar = 15;
	int env_dr = 7;
	int env_sl = 7;
	int env_sr = 0;

	int length = 0;

	int loop_start = 0;
	int loop_end = 0;  // last sample of the loop
	bool loop_enable = false;
	bool loop_unroll = false;

	int wav_loop_start = -1;
	int wav_loop_end = -1;

	int resample_type = 4;      // 0..4 = nearest, linear, cubic, sine, band-limited
	int downsample_factor = 0;  // 0..2 = 1x, 2x, 4x
	bool ramp_enable = false;

	int eq_low = 0;  // -64..64
	int eq_mid = 0;
	int eq_high = 0;

	std::string name = "none";

	bool has_source() const { return !source.empty(); }
};

struct NoteField {
	uint8_t note = 0;
	uint8_t instrument = 0;
	uint8_t effect = 0;
	uint8_t value = 255;
	uint8_t volume = 255;
};

struct Row {
	int speed = 0;  // 0 = no change
	bool marker = false;
	std::string name;
	NoteField chn[CHANNELS];
};

// A song stores its rows lazily: an untouched song has no row storage and
// reads back blank rows. Once written, it holds all MAX_ROWS rows.
class Song {
public:
	int length = MAX_ROWS - 1;  // end row
	int loop_start = 0;
	int measure = 4;
	bool effect = false;  // song is a sound effect
	int compiled_size = 0;  // set by the compiler, not saved
	std::string name = "untitled";

	const Row& row(int i) const { return rows_.empty() ? blank_row() : rows_[i]; }
	Row& row_mut(int i)
	{
		allocate();
		return rows_[i];
	}

	bool allocated() const { return !rows_.empty(); }
	void allocate()
	{
		if (rows_.empty()) rows_.resize(MAX_ROWS);
	}

	// All MAX_ROWS rows, allocating them. Used for whole-song swaps (undo).
	std::vector<Row>& rows()
	{
		allocate();
		return rows_;
	}

	// Every field zeroed, including value/volume (which are normally 255).
	// The original editor used memset() songs like this for previews.
	static Song zeroed();

private:
	static const Row& blank_row();
	std::vector<Row> rows_;
};

struct Module {
	Instrument instruments[MAX_INSTRUMENTS];
	Song songs[MAX_SONGS];
};

}  // namespace gss
