// Importers ported from the original editor's UI handlers in UnitMain.cpp.
//
// The parsing and arithmetic follow the original line for line. Two kinds of
// departure, each marked where it happens:
//   - Reads past the end of the input, out-of-bounds writes and other
//     undefined behaviour are made safe: truncated or malformed input
//     returns false with a message instead.
//   - Bugs that change the result on well-formed input are kept and marked
//     "LEGACY BUG:", to be fixed separately.
//
// UI side effects of the original handlers (redraws, undo reset, cursor
// reset, CompileAllSongs, UpdateSampleData) are the caller's job: after an
// instrument import, re-encode the BRR; after a song import, recompile.
#include "importers.h"

#include "brr.h"
#include "song.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
#include <map>
#include <vector>

namespace gss {

namespace {

using u8 = unsigned char;

// The original helpers. Results are built in unsigned arithmetic and
// converted to int32, which wraps the way Borland's int arithmetic did.
int rd_word_lh(const u8* d) { return d[0] + (d[1] << 8); }

int rd_dword_lh(const u8* d)
{
	return (int32_t)((uint32_t)d[0] | ((uint32_t)d[1] << 8) | ((uint32_t)d[2] << 16) | ((uint32_t)d[3] << 24));
}

void wr_word_lh(u8* d, int value)
{
	d[0] = value & 255;
	d[1] = (value >> 8) & 255;
}

void wr_dword_lh(u8* d, int value)
{
	d[0] = value & 255;
	d[1] = (value >> 8) & 255;
	d[2] = (value >> 16) & 255;
	d[3] = (value >> 24) & 255;
}

int rd_word_hl(const u8* d) { return (d[0] << 8) + d[1]; }

int rd_dword_hl(const u8* d)
{
	return (int32_t)(((uint32_t)d[0] << 24) | ((uint32_t)d[1] << 16) | ((uint32_t)d[2] << 8) | (uint32_t)d[3]);
}

// Bounds-checked view of the input file.
struct Bytes {
	const u8* p;
	long long size;

	explicit Bytes(const std::string& s) : p((const u8*)s.data()), size((long long)s.size()) {}

	bool has(long long off, long long n) const { return off >= 0 && n >= 0 && off <= size - n; }
	bool match(long long off, const char* tag) const
	{
		const long long n = (long long)std::strlen(tag);
		return has(off, n) && !std::memcmp(p + off, tag, (size_t)n);
	}
};

bool fail(std::string* out, const char* msg)
{
	if (out) *out = msg;
	return false;
}

bool ok(std::string* out)
{
	if (out) out->clear();
	return true;
}

// AnsiString::Trim: drop leading and trailing characters <= ' '.
std::string trim(const std::string& s)
{
	size_t a = 0, b = s.size();
	while (a < b && (u8)s[a] <= ' ') ++a;
	while (b > a && (u8)s[b - 1] <= ' ') --b;
	return s.substr(a, b - a);
}

// sprintf("%s", &data[off]): a C string, stopped at the end of the input
// instead of reading past it.
std::string c_string(const Bytes& b, long long off, long long max_len)
{
	std::string s;
	while (b.has(off, 1) && b.p[off] && (long long)s.size() < max_len) s += (char)b.p[off++];
	return s;
}

// ChangeFileExt(ExtractFileName(name), "").
std::string name_from_file_name(const std::string& file_name)
{
	std::string name = file_name;
	const size_t slash = name.find_last_of("/\\:");
	if (slash != std::string::npos) name = name.substr(slash + 1);
	const size_t dot = name.find_last_of('.');
	if (dot != std::string::npos) name = name.substr(0, dot);
	return name;
}

// InstrumentClear(). It leaves loop_unroll and ramp_enable (and the BRR
// address fields the model does not have) untouched, so this is not the
// same as assigning a default Instrument.
void instrument_clear(Instrument& ins)
{
	ins.source.clear();
	ins.source_length = 0;
	ins.source_rate = 0;
	ins.source_volume = 128;

	ins.env_ar = 15;
	ins.env_dr = 7;
	ins.env_sl = 7;
	ins.env_sr = 0;

	ins.length = 0;

	ins.loop_start = 0;
	ins.loop_end = 0;
	ins.loop_enable = false;

	ins.wav_loop_start = -1;
	ins.wav_loop_end = -1;

	ins.eq_low = 0;
	ins.eq_mid = 0;
	ins.eq_high = 0;

	ins.resample_type = 4;  // band
	ins.downsample_factor = 0;

	ins.name = "none";
}

// SongDataClear() zeroes the whole song and then sets value/volume 255,
// measure 4, length MAX_ROWS-1 and the name: exactly a default Song.
void song_data_clear(Song& s) { s = Song(); }

// gss_hex_to_byte(); the argument is a signed (Borland) char.
int hex_to_byte(int n)
{
	if (n >= '0' && n <= '9') return n - '0';
	if (n >= 'a' && n <= 'f') return n - 'a' + 10;
	if (n >= 'A' && n <= 'F') return n - 'A' + 10;
	return -1;
}

bool valid_song(int song) { return song >= 0 && song < MAX_SONGS; }

}  // namespace

// ---------------------------------------------------------------------------
// SpeedButtonImportWavClick

bool import_wav(const std::string& data, const std::string& file_name, Instrument& ins, std::string* error)
{
	const Bytes in(data);
	const u8* wave = in.p;
	const long long size = in.size;

	if (!in.match(0, "RIFF")) return fail(error, "RIFF chunk not found");
	if (!in.match(8, "WAVEfmt ")) return fail(error, "WAVEfmt chunk not found");
	if (!in.has(0, 36)) return fail(error, "WAV header is truncated");

	if (rd_word_lh(wave + 20) > 1) return fail(error, "Compressed files are not supported");

	const int channels = rd_word_lh(wave + 22);
	const int rate = rd_dword_lh(wave + 24);
	const int bits = rd_word_lh(wave + 34);

	// The original scans byte by byte for the "data" tag rather than walking
	// the chunk list.
	long long ptr = 36;
	while (ptr < size && !in.match(ptr, "data")) ++ptr;

	if (ptr >= size) return fail(error, "data chunk not found");
	if (!in.has(ptr + 4, 4)) return fail(error, "data chunk is truncated");

	const int length = rd_dword_lh(wave + ptr + 4);

	ptr += 8;

	// Zero bytes per sample or zero channels divided by zero in the original.
	if (bits / 8 == 0 || channels == 0) return fail(error, "Unsupported WAV format");

	const int samples = length / (bits / 8) / channels;

	// The original freed the instrument's source here, before this check,
	// and left the pointer dangling when it failed. The port leaves the
	// instrument unchanged on every failure instead.
	if (samples < 16) return fail(error, "Sample is too short");

	const bool known_bits = bits == 8 || bits == 16 || bits == 24 || bits == 32;
	if (known_bits && !in.has(ptr, (long long)samples * channels * (bits / 8)))
		return fail(error, "data chunk is truncated");

	// For a bit depth not listed below the original left the malloc'd
	// buffer uninitialized; here it reads back as silence.
	std::vector<int16_t> source((size_t)samples, 0);

	// Channels are summed in an int, which wraps on overflow as on Borland.
	auto average = [channels](uint32_t sum) { return (int32_t)sum / channels; };

	switch (bits) {
	case 8:
		for (int i = 0; i < samples; ++i) {
			uint32_t n = 0;
			for (int j = 0; j < channels; ++j) n += wave[ptr++];
			source[i] = (int16_t)((average(n) - 128) * 256);
		}
		break;

	case 16:
		for (int i = 0; i < samples; ++i) {
			uint32_t n = 0;
			for (int j = 0; j < channels; ++j) {
				// LEGACY BUG: the word is read unsigned and not sign-extended
				// before the channels are averaged, so a multi-channel file
				// mixes e.g. -1 (65535) and +1 into 32768 instead of 0.
				// Mono comes out right after the cast to short.
				n += (uint32_t)rd_word_lh(wave + ptr);
				ptr += 2;
			}
			source[i] = (int16_t)average(n);
		}
		break;

	case 24:
		for (int i = 0; i < samples; ++i) {
			uint32_t n = 0;
			for (int j = 0; j < channels; ++j) {
				// LEGACY BUG: like 16-bit, the 24-bit value is not
				// sign-extended before averaging; only mono is right.
				n += (uint32_t)(wave[ptr] + (wave[ptr + 1] << 8) + (wave[ptr + 2] << 16));
				ptr += 3;
			}
			source[i] = (int16_t)(average(n) / 256);
		}
		break;

	case 32:
		for (int i = 0; i < samples; ++i) {
			uint32_t n = 0;
			for (int j = 0; j < channels; ++j) {
				// LEGACY BUG: the signed 32-bit samples are summed in an int,
				// which overflows (wraps) for loud multi-channel samples.
				n += (uint32_t)rd_dword_lh(wave + ptr);
				ptr += 4;
			}
			source[i] = (int16_t)(average(n) / 65536);
		}
		break;
	}

	int wav_loop_start = -1;
	int wav_loop_end = -1;

	// LEGACY BUG: the smpl chunk is only looked for after the sample data,
	// so loop points in a smpl chunk placed before "data" are ignored.
	while (ptr < size) {
		if (in.match(ptr, "smpl")) {
			if (!in.has(ptr + 0x24, 4)) return fail(error, "smpl chunk is truncated");

			if (rd_dword_lh(wave + ptr + 0x24) > 0) {
				if (!in.has(ptr + 0x2c + 0x08, 8)) return fail(error, "smpl chunk is truncated");

				wav_loop_start = rd_dword_lh(wave + ptr + 0x2c + 0x08);
				wav_loop_end = rd_dword_lh(wave + ptr + 0x2c + 0x0c);
			}

			break;
		}

		++ptr;
	}

	ins.source = std::move(source);
	ins.source_length = samples;
	ins.source_rate = rate;

	ins.wav_loop_start = wav_loop_start;
	ins.wav_loop_end = wav_loop_end;

	ins.length = ins.source_length;

	if (ins.wav_loop_start >= 0) {
		ins.loop_start = ins.wav_loop_start;
		ins.loop_end = ins.wav_loop_end;

		if (ins.loop_start >= ins.length) ins.loop_start = ins.length - 1;
		if (ins.loop_end >= ins.length) ins.loop_end = ins.length - 1;
	} else {
		ins.loop_start = 0;
		ins.loop_end = ins.length - 1;
	}

	ins.name = name_from_file_name(file_name);

	return ok(error);
}

// ---------------------------------------------------------------------------
// MExtractSourceWaveClick

std::string export_source_wav(const Instrument& ins)
{
	u8 wave[44];

	const int size = 44 + ins.source_length * 2;

	std::memcpy(wave, "RIFF", 4);                     // riff signature
	wr_dword_lh(&wave[4], size - 8);                  // filesize-8
	std::memcpy(&wave[8], "WAVEfmt ", 8);             // format id
	wr_dword_lh(&wave[16], 16);                       // header size
	wr_word_lh(&wave[20], 1);                         // PCM
	wr_word_lh(&wave[22], 1);                         // mono
	wr_dword_lh(&wave[24], ins.source_rate);          // samplerate
	// LEGACY BUG: the byte rate should be source_rate*2 (16-bit mono); the
	// original writes the sample rate. Most readers ignore the field.
	wr_dword_lh(&wave[28], ins.source_rate);          // byterate
	// The original writes block align as a dword, spilling into the bits
	// field; the next write overwrites the spill (and its own spill is
	// overwritten by "data"), so the header comes out right.
	wr_dword_lh(&wave[32], 2);                        // channels*bytespersample
	wr_dword_lh(&wave[34], 16);                       // bits per sample
	std::memcpy(&wave[36], "data", 4);                // data id
	wr_dword_lh(&wave[40], ins.source_length * 2);    // data size in bytes

	std::string out((const char*)wave, sizeof(wave));

	// The original wrote source_length shorts straight from the source
	// pointer, crashing on a slot with no source. Missing samples are
	// written as silence instead.
	const int n = ins.source_length > 0 ? ins.source_length : 0;
	out.reserve(out.size() + (size_t)n * 2);
	for (int i = 0; i < n; ++i) {
		const int s = (size_t)i < ins.source.size() ? ins.source[i] : 0;
		out += (char)(s & 255);
		out += (char)((s >> 8) & 255);
	}

	return out;
}

// ---------------------------------------------------------------------------
// XM samples (not in the original): each XM instrument's sample, retuned so
// the XM's C-4 plays on the editor's C-4.

// The driver plays editor C-4 at 32000 Hz x 0x042c / 4096 (notePeriodTable
// in snes/spc700.asm); FastTracker 2 plays C-4 at 8363 Hz before a sample's
// relative note and finetune.
constexpr double DRIVER_C4_HZ = 32000.0 * 0x042c / 4096.0;  // 8343.75
constexpr double XM_C4_HZ = 8363.0;
constexpr double XM_RESAMPLE_ZEROS = 12;  // the sinc's zero crossings each side
constexpr double XM_PI = 3.14159265358979323846;
constexpr int BRR_SAFE_PEAK = 30720;  // see read_xm_samples()

struct XmSample {
	int slot;  // instrument slot, 0-based
	Instrument ins;
};

// Resamples by r (output frames per input frame) with a windowed sinc:
// out[j] is the input at j / r. With a loop (loop_len > 0) the input repeats
// it forever from loop_start, so a loop of loop_len * r frames in the output
// repeats seamlessly too. Before frame 0 is silence.
std::vector<int16_t> resample_looped(const std::vector<int16_t>& in, double r, int out_len, long long loop_start,
                                     long long loop_len)
{
	const double fc = std::min(1.0, r);  // the cutoff, below the output's Nyquist when shrinking
	const double reach = XM_RESAMPLE_ZEROS / fc;  // the kernel's half width, in input frames
	const long long n = (long long)in.size();
	auto at = [&](long long i) -> double {
		if (i < 0) return 0;
		if (loop_len > 0 && i >= loop_start + loop_len) i = loop_start + (i - loop_start) % loop_len;
		return i < n ? in[(size_t)i] : 0;
	};
	std::vector<int16_t> out((size_t)std::max(out_len, 0));
	for (int j = 0; j < out_len; ++j) {
		const double x = j / r;
		double sum = 0, weights = 0;
		for (long long i = (long long)std::floor(x - reach) + 1; i <= (long long)std::floor(x + reach); ++i) {
			const double t = x - i;
			const double sinc = t == 0 ? 1 : std::sin(XM_PI * fc * t) / (XM_PI * fc * t);
			const double w = 0.42 + 0.5 * std::cos(XM_PI * t / reach) + 0.08 * std::cos(2 * XM_PI * t / reach);  // Blackman
			sum += at(i) * sinc * w;
			weights += sinc * w;
		}
		out[(size_t)j] = (int16_t)std::clamp((int)std::lround(weights != 0 ? sum / weights : 0), -32768, 32767);
	}
	return out;
}

// Reads the instruments that follow the patterns. pp is the offset of the
// first instrument. Returns false (with *message set) on a malformed file.
bool read_xm_samples(const Bytes& in, long long pp, std::vector<XmSample>& out, std::string* message)
{
	const u8* xm = in.p;
	const char* truncated = "Module is truncated";
	const int instruments = rd_word_lh(&xm[60 + 12]);

	for (int k = 0; k < instruments && k < MAX_INSTRUMENTS; ++k) {
		if (!in.has(pp, 29)) return fail(message, truncated);
		const long long header_size = (unsigned)rd_dword_lh(&xm[pp]);
		const std::string ins_name = trim(c_string(in, pp + 4, 22));
		const int count = rd_word_lh(&xm[pp + 27]);
		if (header_size < 29) return fail(message, "Module has a malformed instrument");

		if (count == 0) {  // no samples: the slot is left as it is
			pp += header_size;
			continue;
		}

		if (!in.has(pp, 33 + 96)) return fail(message, truncated);
		const long long sample_header_size = (unsigned)rd_dword_lh(&xm[pp + 29]);
		const int keymap_c4 = xm[pp + 33 + 48];  // the sample the keymap plays for C-4
		if (sample_header_size < 40) return fail(message, "Module has a malformed sample");

		const long long headers = pp + header_size;
		long long data = headers + (long long)count * sample_header_size;
		const int pick = keymap_c4 < count ? keymap_c4 : 0;

		Instrument ins;
		bool have = false;

		for (int j = 0; j < count; ++j) {
			const long long h = headers + (long long)j * sample_header_size;
			if (!in.has(h, 40)) return fail(message, truncated);

			const long long bytes = (unsigned)rd_dword_lh(&xm[h]);
			long long loop_start = (unsigned)rd_dword_lh(&xm[h + 4]);
			long long loop_len = (unsigned)rd_dword_lh(&xm[h + 8]);
			const int volume = xm[h + 12];
			const int finetune = (signed char)xm[h + 13];
			const int type = xm[h + 14];
			const int relnote = (signed char)xm[h + 16];
			const bool wide = (type & 0x10) != 0;

			if (!in.has(data, bytes)) return fail(message, truncated);

			if (j == pick && bytes > 0) {
				// delta decoding
				const long long frames = wide ? bytes / 2 : bytes;
				if (frames > 16 * 1024 * 1024) return fail(message, "Module has a sample that is too long");
				std::vector<int16_t> pcm((size_t)frames);
				int acc = 0;
				for (long long i = 0; i < frames; ++i) {
					if (wide) {
						acc = (int16_t)(acc + (int16_t)rd_word_lh(&xm[data + i * 2]));
						pcm[(size_t)i] = (int16_t)acc;
					} else {
						acc = (int8_t)(acc + (int8_t)xm[data + i]);
						pcm[(size_t)i] = (int16_t)(acc * 256);
					}
				}

				if (wide) {
					loop_start /= 2;
					loop_len /= 2;
				}
				int loop_type = type & 3;
				if (loop_len <= 0 || loop_start >= frames) loop_type = 0;
				if (loop_type && loop_start + loop_len > frames) loop_len = frames - loop_start;

				int ls = 0, le = 0;
				if (loop_type == 1) {  // forward: the data after the loop never plays
					pcm.resize((size_t)(loop_start + loop_len));
					ls = (int)loop_start;
					le = (int)(loop_start + loop_len - 1);
				} else if (loop_type == 2) {  // ping-pong: unroll into a forward loop
					pcm.resize((size_t)(loop_start + loop_len));
					for (long long i = loop_start + loop_len - 2; i > loop_start; --i) pcm.push_back(pcm[(size_t)i]);
					ls = (int)loop_start;
					le = (int)pcm.size() - 1;
				}

				// retune: the XM's C-4 rate becomes the driver's C-4 rate
				const double rate = XM_C4_HZ * std::pow(2.0, (relnote + finetune / 128.0) / 12.0);
				const double ratio = DRIVER_C4_HZ / rate;
				bool unroll = false;
				if (loop_type) {
					// The loop must stay seamless, and should come out a whole
					// number of BRR blocks: the encoder resamples a loop that
					// isn't, without regard to its wrap, and a step there
					// repeats as a buzz. So its length is picked first: the
					// nearest multiple of 16 if that is within 0.5% (9 cents),
					// else the exact length, repeated by the encoder (Unroll)
					// up to a block boundary when that is affordable.
					const int loop = le - ls + 1;
					const double ideal = loop * ratio;
					const int blocks = std::max(16, (int)std::lround(ideal / 16) * 16);
					int n = blocks;
					if (std::fabs(blocks / ideal - 1) > 0.005) {
						const int exact = std::max(1, (int)std::lround(ideal));
						int copies = 1;
						while ((exact * copies) % 16) ++copies;
						if (exact * copies <= 16384) {
							n = exact;
							unroll = n % 16 != 0;
						}
					}
					if (n != loop || std::fabs(ratio - 1.0) > 0.001) {
						// resample by exactly n / loop, the loop repeating, and
						// start it a kernel's reach in, where the output repeats
						const double r = (double)n / loop;
						const int start = (int)std::ceil((ls + XM_RESAMPLE_ZEROS / std::min(1.0, r)) * r);
						pcm = resample_looped(pcm, r, start + n, ls, loop);
						ls = start;
						le = start + n - 1;
					}
				} else if (std::fabs(ratio - 1.0) > 0.001 && pcm.size() > 1) {
					const int len = (int)std::lround(pcm.size() * ratio);
					pcm = resample_looped(pcm, ratio, len > 1 ? len : 1, 0, 0);
				}

				// FT2 ramps a note in; the SNES starts it at full level, so a
				// sample that doesn't start at zero (many rest on a DC offset)
				// clicks at every note. Fade its first 2 ms in, short of a loop.
				int fade = std::min((int)pcm.size(), (int)std::lround(0.002 * DRIVER_C4_HZ));
				if (loop_type) fade = std::min(fade, ls);
				for (int i = 0; i < fade; ++i) pcm[(size_t)i] = (int16_t)(pcm[(size_t)i] * i / fade);

				// BRR decodes to 15 bits and wraps on overflow, and at its
				// coarsest range a sample can come out up to 2048 off: near
				// full scale (an 8-bit sample's -128 is -32768) that wraps,
				// and the encoder's prediction carries the damage through the
				// rest of the sample. Scale a sample that peaks above 15/16 of
				// full scale (30720) down to it: -0.56 dB at most.
				int peak = 0;
				for (int16_t v : pcm) peak = std::max(peak, std::abs((int)v));
				if (peak > BRR_SAFE_PEAK)
					for (int16_t& v : pcm) v = (int16_t)std::lround((double)v * BRR_SAFE_PEAK / peak);

				const int len = (int)pcm.size();
				ins.source = pcm;
				if (ins.source.size() < 16) ins.source.resize(16, 0);  // the model's minimum
				ins.source_length = len;
				ins.length = len;
				ins.source_rate = (int)std::lround(DRIVER_C4_HZ);
				ins.loop_enable = loop_type != 0;
				ins.loop_unroll = unroll;
				ins.loop_start = loop_type ? ls : 0;
				ins.loop_end = loop_type ? le : len - 1;
				ins.wav_loop_start = loop_type ? ls : -1;  // so "Loop from WAV" restores it
				ins.wav_loop_end = loop_type ? le : -1;
				ins.source_volume = (volume > 64 ? 64 : volume) * 2;  // 64 is full volume, 128 unity
				const std::string sample_name = trim(c_string(in, h + 18, 22));
				ins.name = !ins_name.empty() ? ins_name : !sample_name.empty() ? sample_name : "xm " + std::to_string(k + 1);
				have = true;
			}

			data += bytes;
		}

		if (have) out.push_back({k, std::move(ins)});
		pp = data;
	}
	return true;
}

// ---------------------------------------------------------------------------
// XM effects (not in the original), converted into the editor's volumes and
// effect column.
//
// The driver's pitch effects work in DSP pitch units (0x1000 plays a sample
// at 32 kHz) per 1/160 s tick, so FastTracker 2's semitone-based ones convert
// for the note that is playing. Volume and global volume changes, slides
// included, become row-by-row volumes, and pan slides row-by-row pans. The driver keeps a slide, portamento
// or vibrato going until it is set to 0, where an XM effect lasts a row, and a
// cell holds one effect: so each channel tracks what the driver was told,
// and each row sends the most important difference (portamento on a note
// row, a slide, portamento, vibrato, pan). One that doesn't fit waits for a
// later row.

// The driver's pitch for an editor note, fractions included: C-4 (50) is
// notePeriodTable[48], 0x042c.
double driver_pitch(double note) { return 0x042c * std::pow(2.0, (note - 50) / 12.0); }

// Pitch units per driver tick that move from note by semis over ticks.
double pitch_rate(double note, double semis, int ticks)
{
	return driver_pitch(note) * (std::pow(2.0, semis / 12.0) - 1.0) / ticks;
}

int effect_value(double v, int max)  // magnitude; a nonzero rate never rounds to 0
{
	return std::clamp((int)std::lround(std::fabs(v)), v != 0 ? 1 : 0, max);
}

struct XmCell {
	int note = 0, ins = 0, vol = 0, fx = 0, param = 0;
};

struct XmEnvelope {  // FT2's: up to 12 points of (tick, value 0..64)
	bool on = false;
	int points = 0, x[12] = {}, y[12] = {};
	int sustain = -1, loop_start = -1, loop_end = -1;  // point numbers, -1 if unused

	double value(int pos) const
	{
		if (points <= 0) return 64;
		if (pos <= x[0]) return y[0];
		for (int i = 1; i < points; ++i)
			if (pos < x[i])
				return x[i] > x[i - 1] ? y[i - 1] + (double)(y[i] - y[i - 1]) * (pos - x[i - 1]) / (x[i] - x[i - 1]) : y[i];
		return y[points - 1];
	}

	// One tick on: it holds at the sustain point until the key is released,
	// and goes from the loop end back to the loop start.
	void step(int& pos, bool key_on) const
	{
		if (points <= 0) return;
		if (key_on && sustain >= 0 && pos == x[sustain]) return;
		++pos;
		if (loop_end >= 0 && pos == x[loop_end]) pos = x[loop_start];
		if (pos > x[points - 1]) pos = x[points - 1];
	}
};

XmEnvelope read_xm_envelope(const u8* at, int points, int sustain, int loop_start, int loop_end, int type)
{
	XmEnvelope e;
	e.points = std::clamp(points, 0, 12);
	e.on = (type & 1) && e.points > 0;
	for (int i = 0; i < e.points; ++i) {
		e.x[i] = rd_word_lh(at + i * 4);
		e.y[i] = std::min(rd_word_lh(at + i * 4 + 2), 64);
	}
	if ((type & 2) && sustain < e.points) e.sustain = sustain;
	if ((type & 4) && loop_start <= loop_end && loop_end < e.points) {
		e.loop_start = loop_start;
		e.loop_end = loop_end;
	}
	return e;
}

struct XmDefaults {  // an instrument's; volume and pan from the sample its keymap plays for C-4
	int vol = 64, pan = 128;
	XmEnvelope vol_env, pan_env;
	int fadeout = 0;  // after a key off, the volume falls by this many 32768ths a tick
};

struct XmChannel {
	// FastTracker 2's state
	double note = 50;    // pitch in editor semitones, slides included
	double target = -1;  // tone portamento target
	int vol = 64, pan = 128;
	// effect memories (an effect with parameter 0 reuses the last)
	int up = 0, down = 0, fine_up = 0, fine_down = 0, xfine_up = 0, xfine_down = 0;
	int porta = 0, vib_speed = 0, vib_depth = 0, vol_slide = 0, fine_vol_up = 0, fine_vol_down = 0, pan_slide = 0;
	// the instrument's envelopes, played out row by row (with samples)
	int ins = 0;  // 1-based
	int env_pos = 0, pan_env_pos = 0, fade = 32768;
	bool key_on = false;
	bool silent = true;  // released to nothing and keyed off in the driver

	struct Driver {  // what the driver was told; it starts channels this way
		int slide = 0;  // signed
		int porta = 0, porta_param = 0;
		int vibrato = 0;  // the editor's V value
		int pan = 50;
		int volume = 99;
	} sent;
};

struct XmRow {  // song-wide, for one row
	int speed;   // FT2 ticks per row
	int bpm;
	int ticks;   // the row's length in driver ticks (its speed)
	int repeat;  // 1 + pattern delay
	int gvol;    // global volume 0..64, on the first tick
	int gvol_rate;  // and the change each tick after (Hxy)
};

void xm_convert_cell(const XmCell& c, const XmRow& r, const std::vector<XmDefaults>& defaults, bool samples,
                     XmChannel& ch, NoteField& f, std::map<std::string, int>& skipped)
{
	const int ticks = (r.speed - 1) * r.repeat;  // the ticks after the first, where slides happen
	const int fx = c.fx, p = c.param, px = p >> 4, py = p & 15, v = c.vol, vx = v & 15;
	const bool porta_row = fx == 0x3 || fx == 0x5 || v >= 0xf0;
	auto skip = [&](const char* what) { ++skipped[what]; };

	if (c.ins) {  // an instrument number resets the volume, pan and envelopes
		f.instrument = (uint8_t)c.ins;
		const XmDefaults d = c.ins <= (int)defaults.size() ? defaults[c.ins - 1] : XmDefaults{};
		ch.vol = samples ? 64 : d.vol;  // with samples, the volume is in the instrument
		ch.pan = d.pan;
		ch.ins = c.ins;
		ch.env_pos = ch.pan_env_pos = 0;
		ch.fade = 32768;
		ch.key_on = true;
	}
	// With samples, the instrument's volume envelope plays out in the volumes
	// and a key off releases it, where the driver's key off would cut the note
	// (FT2 cuts it too without an envelope). Without, the instruments are the
	// module's own.
	const XmDefaults* inst = samples && ch.ins > 0 && ch.ins <= (int)defaults.size() ? &defaults[ch.ins - 1] : nullptr;
	const bool vol_env = inst && inst->vol_env.on;
	const bool key_off = c.note == 97 || (fx == 0x14 && p < r.speed && !(c.note > 0 && c.note < 97));  // or Kxx at tick xx

	if (key_off) {
		if (vol_env) ch.key_on = false;
		else f.note = 1;
	} else if (c.note > 0 && c.note < 97) {
		// Without samples, notes go two octaves up, for samples prepared
		// the SNES GSS way (32 kHz, B +21 cents). With the XM's own samples,
		// retuned to the driver's C-4, they stay at their written octave.
		int note = c.note - 1 + (samples ? 0 : 24) + 2;
		note = std::clamp(note, 2, 2 + 12 * 8 - 1);
		f.note = (uint8_t)note;
		ch.target = note;
		if (!porta_row) {
			ch.note = note;
			ch.silent = false;
		}
	}

	bool explicit_vol = false, vibrato = false;
	int vol_rate = 0;   // volume slide, each tick after the first
	int cut_tick = -1;  // ECx: silent from tick x
	double slide = 0;   // semitones
	auto vol_slide = [&](int param) {
		if (param) ch.vol_slide = param;
		vol_rate += (ch.vol_slide >> 4) ? (ch.vol_slide >> 4) : -(ch.vol_slide & 15);
	};

	// volume column
	if (v >= 0x10 && v <= 0x50) {
		ch.vol = v - 0x10;
		explicit_vol = true;
	} else if (v >= 0x60 && v < 0x70) {
		vol_rate -= vx;
	} else if (v >= 0x70 && v < 0x80) {
		vol_rate += vx;
	} else if (v >= 0x80 && v < 0x90) {
		ch.vol -= vx;
	} else if (v >= 0x90 && v < 0xa0) {
		ch.vol += vx;
	} else if (v >= 0xa0 && v < 0xb0) {
		if (vx) ch.vib_speed = vx;
	} else if (v >= 0xb0 && v < 0xc0) {
		if (vx) ch.vib_depth = vx;
		vibrato = true;
	} else if (v >= 0xc0 && v < 0xd0) {
		ch.pan = vx << 4;
	} else if (v >= 0xd0 && v < 0xe0) {
		ch.pan -= vx * ticks;
	} else if (v >= 0xe0 && v < 0xf0) {
		ch.pan += vx * ticks;
	} else if (v >= 0xf0 && vx) {
		ch.porta = vx << 4;
	}

	// effect column
	switch (fx) {
	case 0x0: if (p) skip("arpeggio"); break;
	case 0x1: if (p) ch.up = p; slide += ch.up * ticks / 16.0; break;
	case 0x2: if (p) ch.down = p; slide -= ch.down * ticks / 16.0; break;
	case 0x3: if (p) ch.porta = p; break;
	case 0x4:
		if (px) ch.vib_speed = px;
		if (py) ch.vib_depth = py;
		vibrato = true;
		break;
	case 0x5: vol_slide(p); break;
	case 0x6: vol_slide(p); vibrato = true; break;
	case 0x7: skip("tremolo"); break;
	case 0x8: ch.pan = p; break;
	case 0x9: skip("sample offset"); break;
	case 0xa: vol_slide(p); break;
	case 0xc: ch.vol = std::min(p, 64); explicit_vol = true; break;
	case 0xe:
		switch (px) {
		case 0x1: if (py) ch.fine_up = py; slide += ch.fine_up / 16.0; break;
		case 0x2: if (py) ch.fine_down = py; slide -= ch.fine_down / 16.0; break;
		case 0x3: skip("glissando"); break;
		case 0x4: skip("vibrato waveform"); break;
		case 0x5: skip("finetune"); break;
		case 0x6: skip("pattern loop"); break;
		case 0x7: skip("tremolo waveform"); break;
		case 0x9: skip("retrigger"); break;
		case 0xa: if (py) ch.fine_vol_up = py; ch.vol += ch.fine_vol_up; break;
		case 0xb: if (py) ch.fine_vol_down = py; ch.vol -= ch.fine_vol_down; break;
		case 0xc:  // note cut at tick py
			if (!py) ch.vol = 0;
			else if (py < r.speed) cut_tick = py;
			break;
		case 0xd: if (py) skip("note delay"); break;  // the note plays at the start of the row
		case 0xe: break;                              // pattern delay, done for the row
		default: skip("other effects"); break;
		}
		break;
	case 0x14: break;  // Kxx: key off at tick xx, done above
	case 0x15: skip("envelope position"); break;
	case 0x19:  // Pxy: right x or left y a tick
		if (p) ch.pan_slide = p;
		ch.pan += ((ch.pan_slide >> 4) ? (ch.pan_slide >> 4) : -(ch.pan_slide & 15)) * ticks;
		break;
	case 0x1b: skip("retrigger"); break;
	case 0x1d: skip("tremor"); break;
	case 0x21:  // extra fine slides, a quarter of the fine ones
		if (px == 1) {
			if (py) ch.xfine_up = py;
			slide += ch.xfine_up / 64.0;
		} else if (px == 2) {
			if (py) ch.xfine_down = py;
			slide -= ch.xfine_down / 64.0;
		}
		break;
	case 0xb: case 0xd: case 0xf: case 0x10: case 0x11: break;  // song-wide, done for the row
	default: skip("other effects"); break;
	}

	// The row's level, tick by tick as FT2 plays it: the volume (set on the
	// first tick, slid on the others, cut by ECx), the envelope and fadeout,
	// and the global volume. The row gets their RMS, so a quick slide or a
	// short envelope keeps its loudness rather than collapsing to one end:
	// a note that a slide fades within its row still sounds. Then to the
	// editor's 0..99.
	ch.vol = std::clamp(ch.vol, 0, 64);
	const double pan_env = inst && inst->pan_env.on ? inst->pan_env.value(ch.pan_env_pos) : 32;
	const int row_ticks = r.speed * r.repeat;
	double energy = 0;
	int gvol = r.gvol;
	for (int t = 0; t < row_ticks; ++t) {
		if (t % r.speed) {  // the ticks slides work on
			ch.vol = std::clamp(ch.vol + vol_rate, 0, 64);
			gvol = std::clamp(gvol + r.gvol_rate, 0, 64);
		}
		if (t == cut_tick) ch.vol = 0;
		double env = 64, fade = 1;
		if (inst) {
			if (inst->vol_env.on) env = inst->vol_env.value(ch.env_pos);
			if (vol_env) fade = ch.fade / 32768.0;
			inst->vol_env.step(ch.env_pos, ch.key_on);
			inst->pan_env.step(ch.pan_env_pos, ch.key_on);
			if (vol_env && !ch.key_on) ch.fade = std::max(0, ch.fade - inst->fadeout);
		}
		const double level = ch.vol / 64.0 * gvol / 64.0 * env / 64.0 * fade;
		energy += level * level;
	}
	const int volume = (int)std::lround(std::sqrt(energy / row_ticks) * 99.0);
	if (!(vol_env && ch.silent) && (explicit_vol || volume != ch.sent.volume)) {
		f.volume = (uint8_t)volume;
		ch.sent.volume = volume;
	}

	// a release that ends in silence by the end of the row: the driver's key off
	if (vol_env && !ch.key_on && !ch.silent && f.note == 0 &&
	    (ch.fade == 0 || inst->vol_env.value(ch.env_pos) == 0)) {
		f.note = 1;
		ch.silent = true;
	}

	// pitch slides: the row's total, spread over the row
	int slide_rate = 0;
	if (slide != 0) {
		const double rate = pitch_rate(ch.note, slide, r.ticks);
		slide_rate = (rate < 0 ? -1 : 1) * effect_value(rate, 99);
		ch.note = std::clamp(ch.note + slide, 2.0, 97.0);
	}

	// tone portamento, at the rate of its first row
	int porta = 0;
	if (porta_row && ch.target >= 0) {
		const double step = ch.porta * ticks / 16.0;  // semitones this row
		const bool down = ch.target < ch.note;
		if (ch.sent.porta && ch.sent.porta_param == ch.porta) porta = ch.sent.porta;
		else porta = std::max(1, effect_value(pitch_rate(ch.note, down ? -step : step, r.ticks), 98));  // P99 is legato
		ch.note = down ? std::max(ch.target, ch.note - step) : std::min(ch.target, ch.note + step);
	}

	// vibrato: FT2 moves it on all but a row's first tick, 64 steps a cycle,
	// +-depth/8 semitone; the driver's goes 192 steps at 160 Hz, +-127*depth/16 units
	int vib = 0;
	if (vibrato && r.speed > 1) {
		const double hz = 0.4 * r.bpm * ch.vib_speed * (r.speed - 1) / r.speed / 64.0;
		const int speed = std::clamp((int)std::lround(hz * 192 / UPDATE_RATE_HZ), ch.vib_speed ? 1 : 0, 9);
		const double units = driver_pitch(ch.note) * (std::pow(2.0, ch.vib_depth / 8.0 / 12.0) - 1.0);
		const int depth = std::clamp((int)std::lround(units * 16 / 127), ch.vib_depth ? 1 : 0, 9);
		if (speed && depth) vib = speed * 10 + depth;
	}

	ch.pan = std::clamp(ch.pan, 0, 255);
	const int panned = std::clamp((int)std::lround(ch.pan + (pan_env - 32) * (128 - std::abs(ch.pan - 128)) / 32.0), 0, 255);
	const int pan = std::min(99, (int)std::lround(panned * 100 / 256.0));

	auto send = [&](char e, int value) {
		f.effect = (uint8_t)e;
		f.value = (uint8_t)value;
	};
	auto send_porta = [&] {
		send('P', porta);
		ch.sent.porta = porta;
		ch.sent.porta_param = ch.porta;
	};
	if (f.note >= 2 && porta != ch.sent.porta) {  // whether the note glides or plays
		send_porta();
	} else if (slide_rate != ch.sent.slide) {
		const int dir = slide_rate ? slide_rate : ch.sent.slide;
		send(dir > 0 ? 'U' : 'D', std::abs(slide_rate));
		ch.sent.slide = slide_rate;
	} else if (porta != ch.sent.porta) {
		send_porta();
	} else if (vib != ch.sent.vibrato) {
		send('V', vib);
		ch.sent.vibrato = vib;
	} else if (pan != ch.sent.pan) {
		send('S', pan);
		ch.sent.pan = pan;
	}
}

// Where the instruments start: after the patterns. -1 if the file ends first.
long long xm_instruments_offset(const Bytes& in, int header_size)
{
	long long pp = 60 + (long long)header_size;
	const int patterns = rd_word_lh(&in.p[60 + 10]);
	for (int ptn = 0; ptn < patterns; ++ptn) {
		if (!in.has(pp, 9)) return -1;
		pp += (long long)(unsigned)rd_dword_lh(&in.p[pp]) + rd_word_lh(&in.p[pp + 7]);
	}
	return pp;
}

// Each instrument's default volume and pan, read leniently: what can't be
// read keeps FT2's defaults, so the notes import works without them.
std::vector<XmDefaults> read_xm_defaults(const Bytes& in, long long pp)
{
	const u8* xm = in.p;
	std::vector<XmDefaults> out(rd_word_lh(&xm[60 + 12]));
	for (size_t k = 0; k < out.size() && pp >= 0; ++k) {
		if (!in.has(pp, 29)) break;
		const long long header_size = (unsigned)rd_dword_lh(&xm[pp]);
		const int count = rd_word_lh(&xm[pp + 27]);
		if (header_size < 29) break;
		if (!count) {
			pp += header_size;
			continue;
		}
		if (!in.has(pp, 33 + 96)) break;
		const long long sample_header_size = (unsigned)rd_dword_lh(&xm[pp + 29]);
		const int keymap_c4 = xm[pp + 33 + 48];
		if (sample_header_size < 40) break;
		const int pick = keymap_c4 < count ? keymap_c4 : 0;
		if (header_size >= 241 && in.has(pp, 241)) {
			const u8* i = &xm[pp];
			out[k].vol_env = read_xm_envelope(i + 129, i[225], i[227], i[228], i[229], i[233]);
			out[k].pan_env = read_xm_envelope(i + 177, i[226], i[230], i[231], i[232], i[234]);
			out[k].fadeout = rd_word_lh(i + 239);
		}
		const long long headers = pp + header_size;
		long long data = headers + (long long)count * sample_header_size;
		for (int j = 0; j < count; ++j) {
			const long long h = headers + (long long)j * sample_header_size;
			if (!in.has(h, 40)) return out;
			if (j == pick) {
				out[k].vol = std::min<int>(xm[h + 12], 64);
				out[k].pan = xm[h + 15];
			}
			data += (unsigned)rd_dword_lh(&xm[h]);
		}
		pp = data;
	}
	return out;
}

// ---------------------------------------------------------------------------
// ImportXM, called by MImportXMSongClick (song=true) and
// MImportXMSoundEffectsClick (song=false).

bool import_xm(const std::string& data, Module& m, int song_cur, bool as_songs, bool samples, std::string* message,
               XmImportInfo* info)
{
	if (info) *info = XmImportInfo{};
	const Bytes in(data);
	const u8* xm = in.p;
	const long long size = in.size;
	const bool song = !as_songs;

	if (song_cur < 0 || song_cur > MAX_SONGS) return fail(message, "Invalid song number");

	if (!in.match(0, "Extended Module: ")) return fail(message, "Not a module");
	if (!in.has(0, 80)) return fail(message, "Module is truncated");

	const int header_size = rd_dword_lh(&xm[60]);
	const int order_len = rd_word_lh(&xm[60 + 4]);
	const int order_loop = rd_word_lh(&xm[60 + 6]);
	const int channels = rd_word_lh(&xm[60 + 8]);
	int speed = rd_word_lh(&xm[60 + 16]);  // ticks per row
	int bpm = rd_word_lh(&xm[60 + 18]);    // ticks are 2.5/bpm seconds
	if (bpm < 32) bpm = 125;               // FT2's range is 32..255

	if (!order_len) return fail(message, "Module should have at least one order position");

	// The songs are built here and stored only when the whole file has been
	// read, so a malformed file changes nothing.
	std::vector<Song> out;
	Song* s = nullptr;
	int dst_row = 0, speed_prev = -1;
	long long pnam_off = -1;

	// Where each song goes: over a song in use with the same name, so a
	// second import of an XM replaces the first, else song_cur onwards.
	std::vector<int> slots, songs_replaced;
	std::vector<bool> song_taken(MAX_SONGS, false);
	int next_song = song_cur;
	auto place = [&](const std::string& name) -> int {
		if (!name.empty() && name != "untitled")
			for (int i = 0; i < MAX_SONGS; ++i)
				if (!song_taken[i] && song_used(m.songs[i]) && m.songs[i].name == name) {
					song_taken[i] = true;
					songs_replaced.push_back(i);
					return i;
				}
		while (next_song < MAX_SONGS && song_taken[next_song]) ++next_song;
		if (next_song >= MAX_SONGS) return -1;
		song_taken[next_song] = true;
		return next_song++;
	};

	if (song) {
		// xm[37]=0 then sprintf("%s",&xm[17]): at most the 20 name bytes.
		const std::string name = trim(c_string(in, 17, 20));
		const int slot = place(name);
		if (slot < 0) return fail(message, "There is no free song slot after the last song in use.");
		slots.push_back(slot);
		out.emplace_back();
		s = &out.back();
		s->name = name;

		dst_row = 0;
		speed_prev = -1;
	} else {
		for (long long pp = 0; pp < size - 4; ++pp) {
			if (!std::memcmp(&xm[pp], "PNAM", 4)) {
				pnam_off = pp + 8;
				break;
			}
		}
	}

	const char* truncated = "Module is truncated";

	const std::vector<XmDefaults> defaults = read_xm_defaults(in, xm_instruments_offset(in, header_size));
	std::vector<XmChannel> chs(CHANNELS);
	std::map<std::string, int> skipped;
	std::vector<XmCell> cells((size_t)channels);
	int gvol = 64, gvol_slide = 0;

	// Song: the orders are followed as Bxx and Dxx send them, each imported
	// once; going back to one already imported is where the song loops.
	std::vector<int> order_row((size_t)order_len, -1);
	int loop_row = -1;

	int ord = 0, start_row = 0;
	while (ord < order_len) {
		if (!song) {
			std::string name = Song().name;
			if (pnam_off >= 0) {
				// LEGACY BUG: pattern names are indexed by order position, not
				// by the pattern number at that position, and a 32-character
				// name with no terminator runs into the next one.
				name = trim(c_string(in, pnam_off + (long long)ord * 32, std::numeric_limits<long long>::max()));
			}
			// The original stopped at the end of the song list (one past it).
			const int slot = place(name);
			if (slot < 0) break;
			slots.push_back(slot);
			out.emplace_back();
			s = &out.back();
			s->name = name;

			dst_row = 0;
			speed_prev = -1;

			s->effect = true;
			for (XmChannel& c : chs) c.sent = {};  // each sound effect starts the driver's channels afresh
		} else {
			if (order_row[ord] >= 0) {
				loop_row = order_row[ord];
				break;
			}
			order_row[ord] = dst_row;
			if (ord == order_loop) s->loop_start = dst_row;
		}

		s->row_mut(dst_row).marker = true;

		long long pp = 60 + (long long)header_size;

		if (!in.has(60 + 20 + ord, 1)) return fail(message, truncated);
		const int ptn_num = xm[60 + 20 + ord];

		// LEGACY BUG: a pattern with packed size 0 (empty) has no data in the
		// file, but the importer decodes the following bytes as its rows.
		for (int ptn = 0; ptn < ptn_num; ++ptn) {
			if (!in.has(pp, 9)) return fail(message, truncated);
			pp += (long long)rd_dword_lh(&xm[pp]) + rd_word_lh(&xm[pp + 7]);
		}

		if (!in.has(pp, 7)) return fail(message, truncated);

		const int patlen = rd_word_lh(&xm[pp + 5]);
		pp += rd_dword_lh(&xm[pp]);

		int next = ord + 1, next_row = 0;

		for (int row = 0; row < patlen; ++row) {
			for (int chn = 0; chn < channels; ++chn) {
				int note, ins, vol, fx, param;

				if (!in.has(pp, 1)) return fail(message, truncated);

				if (xm[pp] & 0x80) {
					const int tag = xm[pp++];
					const int n = ((tag & 0x01) != 0) + ((tag & 0x02) != 0) + ((tag & 0x04) != 0) + ((tag & 0x08) != 0) + ((tag & 0x10) != 0);
					if (!in.has(pp, n)) return fail(message, truncated);

					if (tag & 0x01) note = xm[pp++]; else note = 0;
					if (tag & 0x02) ins = xm[pp++]; else ins = 0;
					if (tag & 0x04) vol = xm[pp++]; else vol = 0;
					if (tag & 0x08) fx = xm[pp++]; else fx = 0;
					if (tag & 0x10) param = xm[pp++]; else param = 0;
				} else {
					if (!in.has(pp, 5)) return fail(message, truncated);

					note = xm[pp++];
					ins = xm[pp++];
					vol = xm[pp++];
					fx = xm[pp++];
					param = xm[pp++];
				}

				cells[(size_t)chn] = {note, ins, vol, fx, param};
			}

			if (row < start_row) continue;  // a Dxx into this pattern skips these

			// song-wide effects
			int delay = 0, jump = -1, brk = -1;
			for (const XmCell& c : cells) {
				switch (c.fx) {
				case 0xb: jump = c.param; break;
				case 0xd: brk = (c.param >> 4) * 10 + (c.param & 15); break;
				case 0xe: if ((c.param >> 4) == 0xe) delay = c.param & 15; break;
				// F00, which stops the song, is ignored
				case 0xf: if (c.param) (c.param < 0x20 ? speed : bpm) = c.param; break;
				case 0x10: gvol = std::min(c.param, 64); break;
				}
			}
			const int spd = std::max(speed, 1);
			const int gvol_first = std::clamp(gvol, 0, 64);  // the row's first tick
			int gvol_rate = 0;
			for (const XmCell& c : cells) {
				if (c.fx != 0x11) continue;
				if (c.param) gvol_slide = c.param;
				gvol_rate += gvol_slide >> 4 ? (gvol_slide >> 4) : -(gvol_slide & 15);
			}
			gvol = std::clamp(gvol_first + gvol_rate * (spd - 1) * (1 + delay), 0, 64);

			// A row lasts speed*2.5/bpm seconds in FT2 and its speed/160 s in
			// the driver. (The original ignored the BPM and used speed*1.6,
			// playing songs at 125 BPM twice as fast.)
			XmRow r;
			r.speed = spd;
			r.bpm = bpm;
			r.repeat = 1 + delay;
			r.ticks = std::clamp((int)std::lround(spd * 2.5 * UPDATE_RATE_HZ / bpm * r.repeat), 1, 99);
			r.gvol = gvol_first;
			r.gvol_rate = gvol_rate;
			if (r.ticks != speed_prev) {
				speed_prev = r.ticks;
				s->row_mut(dst_row).speed = r.ticks;
			}

			for (int chn = 0; chn < channels && chn < CHANNELS; ++chn)
				xm_convert_cell(cells[(size_t)chn], r, defaults, samples, chs[(size_t)chn], s->row_mut(dst_row).chn[chn], skipped);

			++dst_row;

			if (dst_row >= MAX_ROWS) break;

			if (jump >= 0 || brk >= 0) {
				if (jump >= 0) next = jump;
				next_row = brk >= 0 ? brk : 0;
				break;
			}
		}

		if (song) {
			if (dst_row >= MAX_ROWS) break;
			ord = next;
			start_row = next_row;
		} else {
			// The original wrote this marker even when dst_row==MAX_ROWS,
			// one row past the end.
			if (dst_row < MAX_ROWS) s->row_mut(dst_row).marker = true;
			++ord;
		}
	}

	if (song) {
		if (loop_row >= 0) s->loop_start = loop_row;
		if (dst_row < MAX_ROWS) s->row_mut(dst_row).marker = true;  // unguarded in the original
		s->length = dst_row;
	}

	// the samples, after all the patterns
	std::vector<XmSample> imported;
	std::vector<int> ins_added, ins_replaced;
	if (samples) {
		const long long pp = xm_instruments_offset(in, header_size);
		if (pp < 0) return fail(message, truncated);
		if (!read_xm_samples(in, pp, imported, message)) return false;

		// An XM instrument with the name of one in the module (with a
		// sample) replaces it. The others go after the last slot in use (one
		// with a sample, or one a song that stays plays), so the songs
		// already in the module keep theirs: in XM order, a slot each if they
		// have a sample or the imported notes play them.
		std::vector<int> same_name(256, -1);
		std::vector<bool> ins_taken(MAX_INSTRUMENTS, false);
		for (const XmSample& x : imported)
			for (int i = 0; i < MAX_INSTRUMENTS; ++i)
				if (!ins_taken[i] && m.instruments[i].has_source() && m.instruments[i].name == x.ins.name) {
					same_name[(size_t)x.slot] = i;
					ins_taken[i] = true;
					break;
				}

		std::vector<bool> replaced(MAX_SONGS, false);
		for (int slot : slots) replaced[(size_t)slot] = true;
		int base = 0;
		for (int i = 0; i < MAX_INSTRUMENTS; ++i)
			if (m.instruments[i].has_source()) base = i + 1;
		for (int i = 0; i < MAX_SONGS; ++i) {
			const Song& t = m.songs[i];
			if (replaced[(size_t)i] || !t.allocated()) continue;
			for (int r = 0; r < MAX_ROWS; ++r)
				for (const NoteField& n : t.row(r).chn) base = std::max(base, (int)n.instrument);
		}

		std::vector<bool> needed(256, false);
		for (const XmSample& x : imported) needed[(size_t)x.slot] = true;
		for (const Song& t : out)
			if (t.allocated())
				for (int r = 0; r < MAX_ROWS; ++r)
					for (const NoteField& n : t.row(r).chn)
						if (n.instrument) needed[(size_t)n.instrument - 1] = true;

		std::vector<int> slot_of(256, -1);
		int next = base;
		for (size_t k = 0; k < needed.size(); ++k)
			if (needed[k]) slot_of[k] = same_name[k] >= 0 ? same_name[k] : next++;
		if (next > MAX_INSTRUMENTS) {
			const int free = MAX_INSTRUMENTS - base;
			const std::string error = "Not enough free instrument slots: the XM needs " + std::to_string(next - base) +
			                          ", and " + std::to_string(free) + (free == 1 ? " is" : " are") +
			                          " free after slot " + std::to_string(base) + ", the last in use.";
			return fail(message, error.c_str());
		}

		for (Song& t : out)
			if (t.allocated())
				for (int r = 0; r < MAX_ROWS; ++r)
					for (NoteField& n : t.row_mut(r).chn)
						if (n.instrument) n.instrument = (uint8_t)(slot_of[(size_t)n.instrument - 1] + 1);
		for (XmSample& x : imported) {
			(same_name[(size_t)x.slot] >= 0 ? ins_replaced : ins_added).push_back(slot_of[(size_t)x.slot]);
			x.slot = slot_of[(size_t)x.slot];
		}
	}

	// Each song was built from a cleared one (SongClear() in the original).
	for (size_t i = 0; i < out.size(); ++i) m.songs[slots[i]] = std::move(out[i]);
	for (XmSample& x : imported) {
		// A replaced instrument gets the XM's sample, loop and volume, and
		// keeps the settings the XM has no say in.
		Instrument& dst = m.instruments[x.slot];
		if (dst.has_source() && dst.name == x.ins.name) {
			x.ins.env_ar = dst.env_ar;
			x.ins.env_dr = dst.env_dr;
			x.ins.env_sl = dst.env_sl;
			x.ins.env_sr = dst.env_sr;
			x.ins.eq_low = dst.eq_low;
			x.ins.eq_mid = dst.eq_mid;
			x.ins.eq_high = dst.eq_high;
			x.ins.resample_type = dst.resample_type;
			x.ins.downsample_factor = dst.downsample_factor;
			x.ins.ramp_enable = dst.ramp_enable;
		}
		dst = std::move(x.ins);
	}
	if (info) {
		info->songs = slots;
		info->songs_replaced = songs_replaced;
		info->instruments = ins_added;
		info->instruments_replaced = ins_replaced;
		std::vector<std::pair<int, std::string>> list;
		for (const auto& [what, n] : skipped) list.push_back({-n, what});
		if (channels > CHANNELS) list.push_back({0, "channels 9 to " + std::to_string(channels)});
		std::sort(list.begin(), list.end());
		for (const auto& [n, what] : list) {
			if (!info->not_converted.empty()) info->not_converted += ", ";
			info->not_converted += n ? what + " (" + std::to_string(-n) + ")" : what;
		}
	}

	return ok(message);
}

// ---------------------------------------------------------------------------
// MImportMidiClick

bool import_midi(const std::string& data, Module& m, int song_cur, std::string* error)
{
	const Bytes in(data);
	const u8* midi = in.p;

	if (!valid_song(song_cur)) return fail(error, "Invalid song number");

	if (!in.match(0, "MThd") || !in.has(0, 14) || rd_dword_hl(midi + 4) != 6) return fail(error, "Not a MIDI file");

	const int tracks = rd_word_hl(midi + 10);
	const int division = rd_word_hl(midi + 12);

	// The original divided by it on the first event.
	if (!division) return fail(error, "Not a MIDI file");

	// From here on the original filled the song in place: on an error the
	// song keeps what was imported so far, as it did on its own
	// "MIDI track data not found" error.
	Song& s = m.songs[song_cur];

	song_data_clear(s);

	s.row_mut(0).speed = DEFAULT_SPEED;

	// The original indexed the rows without a range check. Events past the
	// last row are dropped.
	auto row_at = [&s](long long row) -> Row* { return row >= 0 && row < MAX_ROWS ? &s.row_mut((int)row) : nullptr; };

	const char* truncated = "MIDI file is truncated";

	// rd_var_length(), bounds-checked; the value wraps as a Borland int.
	auto var_length = [&in](long long& ptr, int& value) {
		if (!in.has(ptr, 1)) return false;
		uint32_t v = in.p[ptr++];
		if (v & 0x80) {
			v &= 0x7f;
			while (true) {
				if (!in.has(ptr, 1)) return false;
				const uint32_t n = in.p[ptr++];
				v = (v << 7) + (n & 0x7f);
				if (!(n & 0x80)) break;
			}
		}
		value = (int32_t)v;
		return true;
	};

	long long ptr = 14;

	for (int track = 0; track < tracks; ++track) {
		if (!in.match(ptr, "MTrk")) return fail(error, "MIDI track data not found");
		if (!in.has(ptr + 4, 4)) return fail(error, truncated);

		const int track_size = rd_dword_hl(midi + ptr + 4);

		ptr += 8;  // skip track header

		const long long track_end = ptr + track_size;

		long long time = 0;
		double bpm = 120;
		double prev_bpm = bpm;
		int prev_status = -1;
		bool first[8];

		for (int channel = 0; channel < 8; ++channel) first[channel] = true;

		while (ptr < track_end) {
			int delta;
			if (!var_length(ptr, delta)) return fail(error, truncated);

			time += delta;

			const long long row = time * 4 / division;  // not clear why 4, a quarter note, perhaps?

			if (!in.has(ptr, 1)) return fail(error, truncated);

			const int status = midi[ptr];
			int event_type, channel;

			if (status < 0x80 && prev_status >= 0) {  // running status check
				event_type = prev_status >> 4;
				channel = prev_status & 15;
			} else {
				event_type = status >> 4;
				channel = status & 15;

				++ptr;

				prev_status = status;
			}

			switch (event_type) {
			case 0x08: {  // note off
				ptr += 2;

				if (channel < 8) {
					if (Row* r = row_at(row))
						if (!r->chn[channel].note) r->chn[channel].note = 1;
				}
			} break;

			case 0x09: {  // note on
				if (!in.has(ptr, 2)) return fail(error, truncated);

				const int param1 = midi[ptr++];  // note
				const int param2 = midi[ptr++];  // velocity

				Row* r = row_at(row);

				if (channel < 8) {
					if (!param2) {  // zero velocity often used for keyoff
						if (r && !r->chn[channel].note) r->chn[channel].note = 1;
					} else {
						const int note = 2 + param1;

						if (note >= 2 && note < 2 + 96) {
							if (r) r->chn[channel].note = (uint8_t)note;

							if (first[channel]) {
								if (r) r->chn[channel].instrument = (uint8_t)(channel + 1);
								first[channel] = false;
							}
						}
					}
				}

				if (channel == 9 && param2 && r) {  // keyon on the drum channel
					switch (param1) {
					case 35:  // bass drums
					case 36:
						r->chn[7].note = 62;
						r->chn[7].instrument = 10;
						break;

					case 38:  // snares
					case 39:
					case 40:
						r->chn[7].note = 62;
						r->chn[7].instrument = 11;
						break;

					case 41:  // toms
					case 43:
					case 45:
					case 47:
					case 48:
					case 50:
						if (!r->chn[7].note) {  // lower priority than kick and snare
							r->chn[7].note = 62;
							r->chn[7].instrument = 12;
						}
						break;

					default:  // everything else, mostly hats
						r->chn[6].note = 62;
						r->chn[6].instrument = 13;
					}
				}
			} break;

			case 0x0a:  // note aftertouch
			case 0x0b:  // controller
			case 0x0e:  // pitch bend
				ptr += 2;
				break;

			case 0x0f: {  // meta event
				// LEGACY BUG: sysex events (F0/F7) land here too and are parsed
				// as meta events: their length byte is taken as the meta type
				// and the first data byte as the length, which desyncs the
				// rest of the track.
				if (!in.has(ptr, 1)) return fail(error, truncated);

				const int meta_event_type = midi[ptr++];

				if (meta_event_type == 0x51) {
					if (!in.has(ptr + 1, 3)) return fail(error, truncated);

					const double tempo = double((midi[ptr + 1] << 16) + (midi[ptr + 2] << 8) + midi[ptr + 3]);

					bpm = tempo != 0 ? 60000000.0 / tempo : std::numeric_limits<double>::infinity();
				}

				int len;
				if (!var_length(ptr, len)) return fail(error, truncated);

				// A negative length (a var-length over 4 bytes) could send the
				// original into an endless loop.
				if (len < 0) return fail(error, "MIDI file is malformed");

				ptr += len;
			} break;

			default:
				++ptr;
				break;
			}

			if (prev_bpm != bpm) {
				double speed = UPDATE_RATE_HZ / (bpm * (1.0 / 60.0) * 4);  // bpm*(1/60) is bpm to hz, 4 is a quarter note?

				if (speed < 1) speed = 1;
				if (speed > 99) speed = 99;

				if (Row* r = row_at(row)) r->speed = (int)speed;

				prev_bpm = bpm;
			}
		}
	}

	return ok(error);
}

// ---------------------------------------------------------------------------
// MImportFamiTrackerClick

bool import_famitracker_text(const std::string& data, int subsong, Module& m, int song_cur, std::string* error)
{
	const char export_id[] = "# FamiTracker text export";

	struct FtmRow {
		u8 chn_note[5];
		u8 chn_vol[5];
		u8 speed;
	};

	struct FtmPattern {
		FtmRow row[256];
		int length;
	};

	const Bytes in(data);
	const long long size = in.size;

	// Characters are signed, as in Borland C++, so bytes >= 0x80 compare
	// below ' '. Reads past the end, which the scanning loops do on
	// well-formed input (e.g. text[size] when a section is missing), see a
	// zero byte.
	auto at = [&in](long long i) -> int { return in.has(i, 1) ? (int)(signed char)in.p[i] : 0; };
	auto is_digit = [](int c) { return c >= '0' && c <= '9'; };

	if (!valid_song(song_cur)) return fail(error, "Invalid song number");

	// The original showed this message and then went on parsing the freed
	// buffer.
	if (!in.match(0, export_id)) return fail(error, "Not a FamiTracker text export file");

	const char* truncated = "FamiTracker text export is truncated";

	long long ptr = 0;

	for (int sub = 0; sub < subsong; ++sub) {
		while (ptr < size) {
			if (in.match(ptr, "TRACK")) {
				ptr += 5;
				break;
			}

			++ptr;
		}
	}

	// LEGACY BUG: the original's "Can't find TRACK section" and "Can't find
	// ORDER section" checks test ptr<0, which is never true. A sub song
	// number past the last track therefore finds nothing, and the import
	// "succeeds" by clearing the song to an empty one of length 0.

	int pattern_len = 0;

	while (ptr < size) {
		if (is_digit(at(ptr))) {
			while (true) {
				const int c = at(ptr++);

				if (!is_digit(c)) break;

				if (pattern_len <= 256) pattern_len = pattern_len * 10 + (c - '0');  // stop before int overflow
			}

			break;
		}

		++ptr;
	}

	// Patterns hold 256 rows; a longer one overflowed the original's array.
	if (pattern_len > 256) return fail(error, "Pattern length is out of range");

	while (ptr < size && !in.match(ptr, "ORDER")) ++ptr;

	std::vector<std::array<u8, 5>> order;

	while (true) {
		while (ptr < size && at(ptr) != ':' && at(ptr) >= ' ') ++ptr;

		if (at(ptr) != ':') break;

		ptr += 2;

		// The original's order table holds 256 positions.
		if (order.size() >= 256) return fail(error, "Too many order positions");

		std::array<u8, 5> o;

		for (int chn = 0; chn < 5; ++chn) {
			if (!in.has(ptr, 2)) return fail(error, truncated);

			// (hi<<4)|lo with ints: an invalid digit (-1) sets all high bits.
			o[chn] = (u8)(((uint32_t)hex_to_byte(at(ptr + 0)) << 4) | (uint32_t)hex_to_byte(at(ptr + 1)));

			if (chn < 4) ptr += 3; else ptr += 2;
		}

		order.push_back(o);

		while (ptr < size && at(ptr) < ' ') ++ptr;

		if (at(ptr) != 'O') break;
	}

	std::vector<FtmPattern> pattern(256);  // zeroed, like the original's memset

	int loop_pos = 0;

	while (ptr < size) {
		if (in.match(ptr, "TRACK")) break;

		if (!in.match(ptr, "PATTERN")) {
			++ptr;
			continue;
		}

		if (!in.has(ptr, 10)) return fail(error, truncated);

		const int ptn = hex_to_byte(at(ptr + 8)) * 16 + hex_to_byte(at(ptr + 9));

		// An invalid digit made a negative index in the original.
		if (ptn < 0) return fail(error, "Malformed pattern number");

		ptr += 10;

		pattern[ptn].length = 0;

		bool cut = false;

		for (int srow = 0; srow < pattern_len; ++srow) {
			while (ptr < size && at(ptr) < ' ') ++ptr;

			if (!in.match(ptr, "ROW")) break;

			FtmRow* row = &pattern[ptn].row[srow];

			for (int chn = 0; chn < 5; ++chn) {
				while (ptr < size && at(ptr) != ':') ++ptr;

				if (!in.has(ptr, 14)) return fail(error, truncated);

				int note = 0;

				switch (at(ptr + 2)) {
				case '-': note = 1; break;
				case 'C': note = 2; break;
				case 'D': note = 4; break;
				case 'E': note = 6; break;
				case 'F': note = 7; break;
				case 'G': note = 9; break;
				case 'A': note = 11; break;
				case 'B': note = 13; break;
				}

				if (note > 1) {
					if (at(ptr + 3) == '#') ++note;

					// LEGACY BUG: noise channel notes are written as "<hex>-#",
					// so noise pitches A..F are read as notes with octave '#'
					// and come out as garbage note numbers.
					note = note + (at(ptr + 4) - '0') * 12;
				}

				// LEGACY BUG: a volume column of 0 (silence) reads as "no volume".
				int vol = 0;

				if (at(ptr + 9) >= '0' && at(ptr + 9) <= '9') vol = at(ptr + 9) - '0';
				if (at(ptr + 9) >= 'A' && at(ptr + 9) <= 'F') vol = at(ptr + 9) - 'A' + 10;

				const int val = hex_to_byte(at(ptr + 12)) * 16 + hex_to_byte(at(ptr + 13));

				switch (at(ptr + 11)) {
				case 'B': cut = true; loop_pos = val; break;
				case 'C': cut = true; break;
				case 'D': if (!val) cut = true; break;
				// LEGACY BUG: Fxx values of 0x20 and up set the tempo, not the
				// speed, but are converted as a speed and wrap to 8 bits.
				case 'F': row->speed = (u8)(160 * val / 60); break;
				}

				row->chn_note[chn] = (u8)note;
				row->chn_vol[chn] = (u8)vol;

				ptr += 15;
			}

			++pattern[ptn].length;

			if (cut) break;
		}
	}

	// convert

	Song& s = m.songs[song_cur];

	const std::string temp = s.name;
	const bool sfx = s.effect;

	song_data_clear(s);

	s.name = temp;
	s.effect = sfx;

	int drow = 0;

	for (int pos = 0; pos < (int)order.size(); ++pos) {
		// The original wrote past the last row (into the next song) when
		// the orders added up to more than MAX_ROWS rows.
		if (drow >= MAX_ROWS) break;

		if (pos == loop_pos) s.loop_start = drow;

		s.row_mut(drow).marker = true;

		for (int srow = 0; srow < pattern[order[pos][0]].length && drow < MAX_ROWS; ++srow) {
			Row& d = s.row_mut(drow);

			for (int chn = 0; chn < 5; ++chn) {
				const FtmRow* row = &pattern[order[pos][chn]].row[srow];

				if (row->speed) d.speed = row->speed;

				d.chn[chn].note = row->chn_note[chn];

				if (row->chn_vol[chn]) d.chn[chn].volume = (uint8_t)(row->chn_vol[chn] * 99 / 15);
			}

			++drow;
		}
	}

	if (drow < MAX_ROWS) s.row_mut(drow).marker = true;
	s.length = drow;

	return ok(error);
}

std::vector<std::string> famitracker_track_names(const std::string& data)
{
	// TRACK <rows> <speed> <tempo> "<name>". Counted as the import counts
	// sub songs: every "TRACK" in the text.
	std::vector<std::string> names;
	size_t pos = 0;
	while ((pos = data.find("TRACK", pos)) != std::string::npos) {
		const size_t eol = std::min(data.find('\n', pos), data.size());
		std::string name;
		const size_t a = data.find('"', pos);
		if (a < eol) {
			const size_t b = data.find('"', a + 1);
			if (b < eol) name = data.substr(a + 1, b - a - 1);
		}
		names.push_back(name);
		pos += 5;
	}
	return names;
}

// ---------------------------------------------------------------------------
// MImportSPCBankClick

bool import_spc_bank(const std::string& data, Module& m, std::string* error)
{
	const Bytes in(data);
	constexpr int RECORDS = 64;
	constexpr int HEADER = 22;
	// Sanity limit for a record's length field, which sets how far the BRR
	// encoder reads into the (zero-padded) source.
	constexpr int MAX_LENGTH = 1 << 24;

	// Validate all 64 records first. The original read them with fread()
	// into a static buffer, so a short file repeated the last header and
	// left sample memory uninitialized; the port rejects it and changes
	// nothing.
	long long ptr = 0;

	for (int ins = 0; ins < RECORDS; ++ins) {
		if (!in.has(ptr, HEADER)) return fail(error, "SPC bank is truncated");

		const int source_length = rd_dword_lh(in.p + ptr);
		const int length = rd_dword_lh(in.p + ptr + 4);

		ptr += HEADER;

		if (source_length < 0 || (source_length && (length > MAX_LENGTH))) return fail(error, "SPC bank is malformed");
		if (!in.has(ptr, (long long)source_length * 2)) return fail(error, "SPC bank is truncated");

		ptr += (long long)source_length * 2;
	}

	for (int ins = 0; ins < MAX_INSTRUMENTS; ++ins) instrument_clear(m.instruments[ins]);

	ptr = 0;

	for (int ins = 0; ins < RECORDS; ++ins) {
		const u8* smph = in.p + ptr;
		Instrument& i = m.instruments[ins];

		ptr += HEADER;

		i.source_length = rd_dword_lh(&smph[0]);
		i.length = rd_dword_lh(&smph[4]);
		i.loop_start = rd_dword_lh(&smph[8]);
		i.loop_end = i.length - 1;
		i.source_rate = rd_word_lh(&smph[12]);
		i.env_ar = smph[14];
		i.env_dr = smph[15];
		i.env_sl = smph[16];
		i.env_sr = smph[17];
		i.loop_enable = smph[18] ? true : false;
		i.ramp_enable = (smph[18] & 2) ? true : false;

		int volume = smph[19];

		if (volume > 128) volume = 128 + (volume - 128) / 2;

		i.source_volume = volume;

		if (i.source_length) {
			// Keep the model invariant: the source covers source_length,
			// length and 16 samples (zero padded).
			int need = i.source_length;
			if (i.length > need) need = i.length;
			if (need < 16) need = 16;

			i.source.assign((size_t)need, 0);

			for (int n = 0; n < i.source_length; ++n) i.source[n] = (int16_t)rd_word_lh(in.p + ptr + n * 2);

			ptr += (long long)i.source_length * 2;

			i.name = "imported " + std::to_string(ins + 1);
		}
	}

	return ok(error);
}

}  // namespace gss
