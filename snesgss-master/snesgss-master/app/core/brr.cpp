#include "brr.h"

#include <climits>
#include <cmath>
#include <cstdlib>
#include <cstring>

namespace gss {

namespace {

constexpr double PI_BRR = 3.14159265;  // BRRtools' own PI, not M_PI
constexpr double PI_EQ = 3.14159265358979323846;

// Out-of-range double to short goes through a 32-bit int, like x86 code does.
inline int16_t to_pcm(double v) { return (int16_t)(int)v; }

int brr_prediction(uint8_t filter, int16_t p1, int16_t p2)
{
	int p;
	switch (filter) {
	case 0:
		return 0;
	// Left shifts of possibly negative values are written as multiplications
	// (same bits, but defined behaviour in C++17).
	case 1:
		p = p1;
		p -= p1 >> 4;
		return p;
	case 2:
		p = p1 * 2;
		p += (-(p1 + p1 * 2)) >> 5;
		p -= p2;
		p += p2 >> 4;
		return p;
	case 3:
		p = p1 * 2;
		p += (-(p1 + p1 * 4 + p1 * 8)) >> 6;
		p -= p2;
		p += (p2 + p2 * 2) >> 4;
		return p;
	}
	return -1;
}

inline int clamp16(int n) { return ((int16_t)n != n) ? (int16_t)(0x7fff - (n >> 24)) : n; }

double sinc(double x)
{
	if (x == 0.0) return 1.0;
	return std::sin(PI_BRR * x) / (PI_BRR * x);
}

// 3 band EQ, (c) Neil C / Etanza Systems, public domain.
struct EqState {
	double lf, f1p0, f1p1, f1p2, f1p3;
	double hf, f2p0, f2p1, f2p2, f2p3;
	double sdm1, sdm2, sdm3;
	double lg, mg, hg;
};

void eq_init(EqState* es, int lowfreq, int highfreq, int mixfreq)
{
	std::memset(es, 0, sizeof(EqState));
	es->lg = 1.0;
	es->mg = 1.0;
	es->hg = 1.0;
	es->lf = 2 * std::sin(PI_EQ * ((double)lowfreq / (double)mixfreq));
	es->hf = 2 * std::sin(PI_EQ * ((double)highfreq / (double)mixfreq));
}

double eq_process(EqState* es, double sample)
{
	static const double vsa = (1.0 / 4294967295.0);  // denormal fix
	double l, m, h;

	es->f1p0 += (es->lf * (sample - es->f1p0)) + vsa;
	es->f1p1 += (es->lf * (es->f1p0 - es->f1p1));
	es->f1p2 += (es->lf * (es->f1p1 - es->f1p2));
	es->f1p3 += (es->lf * (es->f1p2 - es->f1p3));
	l = es->f1p3;

	es->f2p0 += (es->hf * (sample - es->f2p0)) + vsa;
	es->f2p1 += (es->hf * (es->f2p0 - es->f2p1));
	es->f2p2 += (es->hf * (es->f2p1 - es->f2p2));
	es->f2p3 += (es->hf * (es->f2p2 - es->f2p3));
	h = es->sdm3 - es->f2p3;

	m = es->sdm3 - (h + l);

	l *= es->lg;
	m *= es->mg;
	h *= es->hg;

	es->sdm3 = es->sdm2;
	es->sdm2 = es->sdm1;
	es->sdm1 = sample;

	return (l + m + h);
}

// Reads outside the buffer were undefined in the original; read them as silence.
inline int16_t at(const std::vector<int16_t>& v, int i) { return (i >= 0 && i < (int)v.size()) ? v[i] : 0; }

}  // namespace

float volume_scale(int vol)
{
	if (vol < 128) return 1.0f + (float)(vol - 128) / 128.0f;
	return 1.0f + (float)(vol - 128) / 64.0f;
}

void BrrEncoder::reset()
{
	p1_ = p2_ = 0;
	filter_at_loop_ = 0;
	p1_at_loop_ = p2_at_loop_ = 0;
	std::memset(brr_, 0, sizeof(brr_));
}

// Converts a block from PCM to BRR, returns the squared error between the
// original and encoded data. If is_end_point is set, the predictions at the
// loop point are also counted (depending on the filter at the loop).
double BrrEncoder::mash(unsigned shift, uint8_t filter, const int16_t pcm[16], bool write, bool is_end_point)
{
	const bool wrap_en = true;
	double d2 = 0.0;
	int16_t l1 = p1_;
	int16_t l2 = p2_;
	int step = 1 << shift;
	int vlin, d, da, dp, c;

	for (int i = 0; i < 16; ++i) {
		vlin = brr_prediction(filter, l1, l2) >> 1;
		d = (pcm[i] >> 1) - vlin;
		da = std::abs(d);
		if (wrap_en && da > 16384 && da < 32768) d = d - 32768 * (d >> 24);
		dp = d + (step << 2) + (step >> 2);
		c = 0;
		if (dp > 0) {
			if (step > 1) c = dp / (step / 2);
			else c = dp * 2;
			if (c > 15) c = 15;
		}
		c -= 8;
		dp = (c * (1 << shift)) >> 1;
		if (shift > 12) dp = (dp >> 14) & ~0x7FF;
		c &= 0x0f;

		l2 = l1;
		l1 = (int16_t)(clamp16(vlin + dp) * 2);

		d = pcm[i] - l1;
		d2 += (double)d * d;

		if (write) (brr_ + 1)[i >> 1] |= (i & 1) ? c : c << 4;
	}

	if (is_end_point) {
		switch (filter_at_loop_) {
		case 0:
			d2 /= 16.;
			break;
		case 1:
			d = l1 - p1_at_loop_;
			d2 += (double)d * d;
			d2 /= 17.;
			break;
		default:
			d = l1 - p1_at_loop_;
			d2 += (double)d * d;
			d = l2 - p2_at_loop_;
			d2 += (double)d * d;
			d2 /= 18.;
		}
	} else {
		d2 /= 16.;
	}

	if (write) {
		p1_ = l1;
		p2_ = l2;
		brr_[0] = (uint8_t)((shift << 4) | (filter << 2));
		if (is_end_point) brr_[0] |= 1;
	}
	return d2;
}

// Brute force over filters and shift amounts.
void BrrEncoder::block_mash(const int16_t pcm[16], bool is_loop_point, bool is_end_point)
{
	int smin = 0, kmin = 0;
	double dmin = (double)INT_MAX;

	for (int s = 0; s < 13; ++s)
		for (int k = 0; k < 4; ++k) {
			double d = mash(s, k, pcm, false, is_end_point);
			if (d < dmin) {
				kmin = k;
				dmin = d;
				smin = s;
			}
		}

	if (is_loop_point) {
		filter_at_loop_ = kmin;
		p1_at_loop_ = p1_;
		p2_at_loop_ = p2_;
	}
	mash(smin, kmin, pcm, true, is_end_point);
}

std::vector<int16_t> BrrEncoder::resample(const std::vector<int16_t>& in, int out_length, char type)
{
	const int samples_length = (int)in.size();
	const double ratio = (double)samples_length / (double)out_length;
	std::vector<int16_t> out(out_length > 0 ? out_length : 0);

	switch (type) {
	case 'n':
		for (int i = 0; i < out_length; ++i) out[i] = in[(int)std::floor(i * ratio)];
		break;

	case 'l':
		for (int i = 0; i < out_length; ++i) {
			int a = (int)(i * ratio);
			double b = i * ratio - a;
			if ((a + 1) == samples_length) out[i] = in[a];
			else out[i] = to_pcm((1 - b) * in[a] + b * in[a + 1]);
		}
		break;

	case 's':
		for (int i = 0; i < out_length; ++i) {
			int a = (int)(i * ratio);
			double b = i * ratio - a;
			double c = (1.0 - std::cos(b * PI_BRR)) / 2.0;
			if ((a + 1) == samples_length) out[i] = in[a];
			else out[i] = to_pcm((1 - c) * in[a] + c * in[a + 1]);
		}
		break;

	case 'c':
		for (int i = 0; i < out_length; ++i) {
			int a = (int)(i * ratio);
			short s0 = (a == 0) ? in[0] : in[a - 1];
			short s1 = in[a];
			short s2 = (a + 1 >= samples_length) ? in[samples_length - 1] : in[a + 1];
			short s3 = (a + 2 >= samples_length) ? in[samples_length - 1] : in[a + 2];
			double a0 = s3 - s2 - s0 + s1;
			double a1 = s0 - s1 - a0;
			double a2 = s2 - s0;
			double b = i * ratio - a;
			double b2 = b * b;
			double b3 = b2 * b;
			out[i] = to_pcm(b3 * a0 + b2 * a1 + b * a2 + s1);
		}
		break;

	case 'b': {
		const int FIR_ORDER = 15;
		std::vector<int16_t> filtered;
		const std::vector<int16_t>* src = &in;

		if (ratio > 1.0) {  // antialiasing pre-filter
			double fir_coefs[FIR_ORDER + 1];
			for (int k = 0; k <= FIR_ORDER; ++k) fir_coefs[k] = sinc(k / ratio) / ratio;

			filtered.resize(samples_length);
			for (int i = 0; i < samples_length; ++i) {
				double acc = in[i] * fir_coefs[0];
				for (int k = FIR_ORDER; k > 0; --k) {
					acc += fir_coefs[k] * ((i + k < samples_length) ? in[i + k] : in[samples_length - 1]);
					acc += fir_coefs[k] * ((i - k >= 0) ? in[i - k] : in[0]);
				}
				filtered[i] = to_pcm(acc);
			}
			src = &filtered;
		}

		const std::vector<int16_t>& s = *src;
		for (int i = 0; i < out_length; ++i) {
			double a = i * ratio;
			double acc = 0.0;
			for (int j = (int)a - FIR_ORDER; j <= (int)a + FIR_ORDER; ++j) {
				int16_t sample;
				if (j >= 0) sample = (j < samples_length) ? s[j] : s[samples_length - 1];
				else sample = s[0];
				acc += sample * sinc(a - j);
			}
			out[i] = to_pcm(acc);
		}
		break;
	}
	}

	return out;
}

BrrSample BrrEncoder::encode(const Instrument& ins)
{
	static const char resample_list[] = "nlcsb";
	BrrSample result;

	int src_length = ins.length;
	if (!ins.has_source() || src_length < 16) return result;  // shorter than one BRR block

	std::vector<int16_t> source(ins.source.begin(), ins.source.begin() + src_length);

	// EQ goes before any downsampling, as it is also meant to compensate for it
	if (ins.eq_low != 0 || ins.eq_mid != 0 || ins.eq_high != 0) {
		const double rate = ins.source_rate;
		const double band_low = rate / 50.0;   // 880 for 44100
		const double band_high = rate / 8.82;  // 5000 for 44100
		EqState eq;

		eq_init(&eq, (int)band_low, (int)band_high, (int)rate);
		eq.lg = (double)(64 + ins.eq_low) / 64.0f;
		eq.mg = (double)(64 + ins.eq_mid) / 64.0f;
		eq.hg = (double)(64 + ins.eq_high) / 64.0f;

		for (int i = 0; i < src_length; ++i) {
			double out_sample = eq_process(&eq, (double)source[i] / 32768.0) * 32768.0;
			if (out_sample < -32768) out_sample = -32768;
			if (out_sample > 32767) out_sample = 32767;
			source[i] = (int16_t)out_sample;
		}
	}

	const char resample_type = resample_list[(ins.resample_type >= 0 && ins.resample_type < 5) ? ins.resample_type : 4];

	int src_loop_start = ins.loop_start;
	int src_loop_end = ins.loop_end + 1;  // loop_end is the last sample of the loop

	float scale;
	switch (ins.downsample_factor) {
	case 1: scale = .5f; break;
	case 2: scale = .25f; break;
	default: scale = 1.0f;
	}

	if (scale != 1.0f) {
		int new_length = (int)(float(src_length) * scale);
		source = resample(source, new_length, resample_type);
		src_length = new_length;
		src_loop_start = (int)(float(src_loop_start) * scale);
		src_loop_end = (int)(float(src_loop_end) * scale);
	}

	// align the sample as required
	const bool loop_enable = ins.loop_enable;
	std::vector<int16_t> sample;
	int new_loop_start = 0;

	if (!loop_enable) {  // pad with zeroes to a 16 sample boundary
		sample.assign((src_length + 15) / 16 * 16, 0);
		for (int i = 0; i < src_length; ++i) sample[i] = source[i];
		result.loop_block = -1;
	} else if (!ins.loop_unroll) {  // resample the loop part: less memory, lower loop quality
		new_loop_start = (src_loop_start + 15) / 16 * 16;
		const int padding = new_loop_start - src_loop_start;
		const int loop_size = src_loop_end - src_loop_start;
		int new_loop_size = loop_size / 16 * 16;
		if ((loop_size & 15) >= 8) new_loop_size += 16;  // closest alignment, least detune

		sample.reserve(new_loop_start + new_loop_size > 0 ? new_loop_start + new_loop_size : 0);
		for (int i = 0; i < padding; ++i) sample.push_back(0);
		for (int i = 0; i < src_loop_start; ++i) sample.push_back(at(source, i));

		if (new_loop_size == loop_size) {
			for (int i = 0; i < new_loop_size; ++i) sample.push_back(at(source, src_loop_start + i));
		} else {
			std::vector<int16_t> temp(loop_size > 0 ? loop_size : 0);
			for (int i = 0; i < loop_size; ++i) temp[i] = at(source, src_loop_start + i);
			temp = resample(temp, new_loop_size, resample_type);
			for (int i = 0; i < new_loop_size; ++i) sample.push_back(temp[i]);
		}

		result.loop_block = new_loop_start / 16;
	} else {  // unroll the loop: best quality, more memory
		new_loop_start = (src_loop_start + 15) / 16 * 16;
		const int padding = new_loop_start - src_loop_start;
		const int loop_size = src_loop_end - src_loop_start;

		for (int i = 0; i < padding; ++i) sample.push_back(0);
		for (int i = 0; i < src_loop_start; ++i) sample.push_back(at(source, i));

		while (loop_size > 0) {
			for (int i = 0; i < loop_size; ++i) sample.push_back(at(source, src_loop_start + i));
			const int len = (int)sample.size();
			if (!(len & 15) || len >= 65536) break;
		}

		result.loop_block = new_loop_start / 16;
	}

	const int new_length = (int)sample.size();

	// apply volume
	const float volume = volume_scale(ins.source_volume);
	for (int i = 0; i < new_length; ++i) {
		int smp = (int)(((float)sample[i]) * volume);
		if (smp < -32768) smp = -32768;
		if (smp > 32767) smp = 32767;
		sample[i] = (int16_t)smp;
	}

	// smooth out the loop transition
	if (loop_enable && ins.ramp_enable && new_length >= 16) {
		int ptr = new_length - 16;
		float fade = 1.0f;
		float ramp = 0.0f;
		const float delta = ((float)at(sample, new_loop_start)) / 16.0f;

		for (int i = 0; i < 16; ++i) {
			float s = (float)sample[ptr];
			s = s * fade + ramp;
			fade -= 1.0f / 16.0f;
			ramp += delta;
			sample[ptr++] = (int16_t)(int)s;
		}
	}

	// convert to BRR
	const int blocks = new_length / 16;
	std::vector<uint8_t>& out = result.data;
	out.reserve((blocks + 1) * 9);

	// an initial silent block if the first sample block is not silent
	int sum = 0;
	for (int i = 0; i < 16; ++i) sum += at(sample, i);

	if (sum) {
		uint8_t block[9] = {};
		if (loop_enable) block[0] = 0x02;  // loop flag is always set for a looped sample
		out.insert(out.end(), block, block + 9);
	}

	if (blocks > 0) {
		// The original editor calls this once before encoding, and notes it
		// prevents clicks at the loop point. It writes the predictor state.
		block_mash(&sample[(blocks - 1) * 16], false, true);
	}

	for (int i = 0; i < blocks; ++i) {
		const bool loop_flag = loop_enable && (i == result.loop_block);
		const bool end_flag = (i == blocks - 1);

		std::memset(brr_, 0, 9);
		block_mash(&sample[i * 16], loop_flag, end_flag);

		if (loop_enable) brr_[0] |= 0x02;
		if (end_flag) brr_[0] |= 0x01;

		out.insert(out.end(), brr_, brr_ + 9);
	}

	if (sum && result.loop_block >= 0) ++result.loop_block;

	return result;
}

int brr_size_estimate(const Instrument& ins, bool loop_only)
{
	int brr_len, brr_loop_len, div;

	if (!ins.has_source()) return 0;

	switch (ins.downsample_factor) {
	case 1: div = 2; break;
	case 2: div = 4; break;
	default: div = 1;
	}

	if (!ins.loop_enable) {
		brr_len = (ins.length / div + 15) / 16 * 9;
		brr_loop_len = 0;
	} else {
		const int loop_start = ins.loop_start / div;
		const int loop_end = (ins.loop_end + 1) / div;
		const int loop_size = loop_end - loop_start;

		if (!ins.loop_unroll) {
			brr_loop_len = loop_size / 16 * 9;
			brr_len = (loop_start + 15) / 16 * 9 + brr_loop_len;
			if ((loop_size & 15) >= 8) brr_len += 9;
		} else {
			const int new_loop_start = (loop_start + 15) / 16 * 16;
			int loop_cnt = new_loop_start;
			while (loop_size > 0) {
				loop_cnt += loop_size;
				if (!(loop_cnt & 15) || loop_cnt >= 65536) break;
			}
			brr_loop_len = (loop_cnt - new_loop_start) / 16 * 9;
			brr_len = loop_cnt / 16 * 9;
		}
	}

	for (int i = 0; i < 16 && i < (int)ins.source.size(); ++i) {
		if (ins.source[i] != 0) {
			brr_len += 9;
			break;
		}
	}

	return loop_only ? brr_loop_len : brr_len;
}

}  // namespace gss
