// BRR encoding, ported from BRRtools 3.0 (Bregalad, Kode54) as embedded in
// the original editor.
//
// The encoder deliberately keeps its predictor state (p1/p2 and the loop
// point history) between calls, like the original did with globals: the
// output for one instrument depends on the instruments encoded before it.
// Byte-identical exports depend on preserving that, so reset() is only
// called where the original process would have started fresh.
#pragma once

#include <cstdint>
#include <vector>

#include "model.h"

namespace gss {

struct BrrSample {
	std::vector<uint8_t> data;  // 9-byte blocks
	int loop_block = -1;        // loop point in blocks, -1 if not looped
};

class BrrEncoder {
public:
	void reset();

	// Full pipeline for an instrument: EQ, downsample, loop alignment or
	// unroll, volume, ramp, encode. Returns an empty sample if the
	// instrument is shorter than one block.
	BrrSample encode(const Instrument& ins);

	// Exposed for tests.
	static std::vector<int16_t> resample(const std::vector<int16_t>& samples, int out_length, char type);

private:
	double mash(unsigned shift, uint8_t filter, const int16_t pcm[16], bool write, bool is_end_point);
	void block_mash(const int16_t pcm[16], bool is_loop_point, bool is_end_point);

	int16_t p1_ = 0, p2_ = 0;
	uint8_t filter_at_loop_ = 0;
	int16_t p1_at_loop_ = 0, p2_at_loop_ = 0;
	uint8_t brr_[9] = {};
};

// Volume scale for Instrument::source_volume (128 is unity).
float volume_scale(int vol);

// Size in bytes the encoder will produce, without encoding.
int brr_size_estimate(const Instrument& ins, bool loop_only);

}  // namespace gss
