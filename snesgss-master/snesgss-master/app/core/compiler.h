// Compiles a module into SPC700 RAM: driver, sample directory, ADSR list,
// BRR samples, sound effects and music, plus a playable .spc image.
//
// Ported from the original editor. Like the original, a Compiler keeps
// state between calls (ARAM contents, sample addresses, BRR encoder state)
// and only re-encodes samples after invalidate_samples(). Callers that need
// output identical to the original must follow the same call sequence; see
// export.h.
#pragma once

#include <cstdint>
#include <string>

#include "brr.h"
#include "model.h"

namespace gss {

constexpr int SPC_FILE_SIZE = 66048;
constexpr int DRIVER_ADDRESS = 0x200;
constexpr int BRR_STREAM_BUFFER_SIZE = 28 * 9 * 9 + 64;  // reserved at the top of ARAM by the driver

struct CompileStats {
	int instruments_size = 0;
	int effects_size = 0;
	int music_size = 0;
	int music_largest = 0;
	int mem_top = 0;  // first address after effects; music loads here
	int instruments_count = 0;
	int driver_size = 0;  // code size in ARAM, without the 2-byte header
};

class Compiler {
public:
	Compiler();

	// Samples are re-encoded on the next spc_compile().
	void invalidate_samples() { update_samples_ = true; }

	// Channel mute flags used when compiling with mute=true.
	bool channel_mute[CHANNELS] = {};

	// Compile all 8 channels, the muted and empty ones as rests, so music
	// channel N is always the song's channel N: a playing preview can then be
	// moved onto a newer compile (see live.h). Not for exports.
	bool all_channels = false;

	// Builds ARAM and the .spc image for song s starting at start_row.
	// effects=true compiles sound effects too (export); effects=false
	// patches the driver to start playing immediately (preview).
	// one_sample >= 0 encodes only that instrument (note preview).
	bool spc_compile(Module& m, Song& s, int start_row, bool mute, bool effects, int one_sample, std::string* error = nullptr);

	// Compiles a song at start_adr into ARAM. Returns its size; sets
	// s.compiled_size. -1 if it does not fit.
	int song_compile(Song& s, int start_row, int start_adr, bool mute);

	// Compiles every non-empty song at stats().mem_top to measure sizes.
	void compile_all_songs(Module& m);

	const uint8_t* aram() const { return mem_; }
	const uint8_t* spc_image() const { return spc_; }
	const CompileStats& stats() const { return stats_; }
	int instrument_brr_address(int ins) const { return brr_adr_[ins]; }
	int instrument_brr_size(int ins) const { return brr_size_[ins]; }

private:
	int samples_compile(Module& m, int adr, int one_sample);
	int effects_compile(Module& m, int start_adr);
	int channel_compile(const Song& s, int chn, int start_row, int compile_adr, int& play_adr);
	int channel_compress(int compile_adr, int& play_adr, int loop_adr, int src_size, int ref_max);
	void channel_compress_flush(int compile_adr);
	int delay_compile(int adr, int delay);

	uint8_t mem_[65536];
	uint8_t spc_[SPC_FILE_SIZE];
	uint8_t chn_mem_[65536 + 16];
	uint8_t chn_pack_[65536 + 16];
	uint8_t seq_buf_[256];
	int seq_ptr_ = 0;
	int out_ptr_ = 0;
	bool overflow_ = false;

	int renumber_[MAX_INSTRUMENTS];
	int brr_adr_[MAX_INSTRUMENTS] = {};
	int brr_size_[MAX_INSTRUMENTS] = {};
	bool update_samples_ = true;
	BrrEncoder encoder_;
	Song work_;
	CompileStats stats_;
};

}  // namespace gss
