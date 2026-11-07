// Importer tests on synthetic files built in code. Expected values are worked
// out by hand from the original handlers in legacy/src/UnitMain.cpp.
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "importers.h"
#include "song.h"

using namespace gss;

static int failures = 0;

#define CHECK(cond)                                                       \
	do {                                                                  \
		if (!(cond)) {                                                    \
			std::printf("%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #cond); \
			++failures;                                                   \
		}                                                                 \
	} while (0)

#define CHECK_EQ(a, b)                                                                   \
	do {                                                                                 \
		const long long va_ = (long long)(a), vb_ = (long long)(b);                      \
		if (va_ != vb_) {                                                                \
			std::printf("%s:%d: CHECK_EQ failed: %s == %lld, expected %s == %lld\n", __FILE__, \
				__LINE__, #a, va_, #b, vb_);                                             \
			++failures;                                                                  \
		}                                                                                \
	} while (0)

#define CHECK_STR(a, b)                                                                              \
	do {                                                                                             \
		const std::string va_ = (a), vb_ = (b);                                                      \
		if (va_ != vb_) {                                                                            \
			std::printf("%s:%d: CHECK_STR failed: %s == \"%s\", expected \"%s\"\n", __FILE__, __LINE__, \
				#a, va_.c_str(), vb_.c_str());                                                       \
			++failures;                                                                              \
		}                                                                                            \
	} while (0)

// ---------------------------------------------------------------------------
// byte builders

static void u8(std::string& s, int v) { s += (char)(v & 255); }
static void le16(std::string& s, int v) { u8(s, v); u8(s, v >> 8); }
static void le32(std::string& s, int v) { le16(s, v); le16(s, v >> 16); }
static void be16(std::string& s, int v) { u8(s, v >> 8); u8(s, v); }
static void be32(std::string& s, int v) { be16(s, v >> 16); be16(s, v); }
static void bytes(std::string& s, std::initializer_list<int> l) { for (int v : l) u8(s, v); }

static void set_le16(std::string& s, size_t off, int v)
{
	s[off] = (char)(v & 255);
	s[off + 1] = (char)((v >> 8) & 255);
}

static void set_le32(std::string& s, size_t off, int v)
{
	for (int i = 0; i < 4; ++i) s[off + i] = (char)((v >> (8 * i)) & 255);
}

// A canonical RIFF/WAVE: fmt chunk, data chunk, optional trailing chunk.
static std::string make_wav(int channels, int rate, int bits, const std::string& pcm, const std::string& trailer = "")
{
	std::string w = "RIFF";
	le32(w, 0);
	w += "WAVEfmt ";
	le32(w, 16);
	le16(w, 1);
	le16(w, channels);
	le32(w, rate);
	le32(w, rate * channels * bits / 8);
	le16(w, channels * bits / 8);
	le16(w, bits);
	w += "data";
	le32(w, (int)pcm.size());
	w += pcm;
	w += trailer;
	set_le32(w, 4, (int)w.size() - 8);
	return w;
}

static std::string smpl_chunk(int loop_start, int loop_end)
{
	std::string c = "smpl";
	le32(c, 60);
	for (int i = 0; i < 7; ++i) le32(c, 0);  // manufacturer .. SMPTE offset
	le32(c, 1);                              // number of loops (+0x24)
	le32(c, 0);                              // sampler data
	le32(c, 0);                              // cue id (+0x2c)
	le32(c, 0);                              // type
	le32(c, loop_start);                     // +0x34
	le32(c, loop_end);                       // +0x38
	le32(c, 0);                              // fraction
	le32(c, 0);                              // play count
	return c;
}

// ---------------------------------------------------------------------------
// WAV

static void test_wav_16bit_stereo()
{
	std::string pcm;
	const int frames[][2] = {
		{1000, 3000},   // (1000+3000)/2 = 2000
		{-1, 1},        // LEGACY BUG: (65535+1)/2 = 32768 -> -32768
		{-100, -300},   // (65436+65236)/2 = 65336 -> -200
		{-1000, 500},   // LEGACY BUG: (64536+500)/2 = 32518
	};
	for (auto& f : frames) {
		le16(pcm, f[0]);
		le16(pcm, f[1]);
	}
	for (int i = 4; i < 20; ++i) {
		le16(pcm, 0);
		le16(pcm, 0);
	}

	const std::string wav = make_wav(2, 22050, 16, pcm, smpl_chunk(4, 30));

	Instrument ins;
	ins.env_ar = 3;
	ins.loop_enable = true;
	ins.source_volume = 77;

	std::string err = "stale";
	CHECK(import_wav(wav, "/some/dir/Bass Drum.v2.wav", ins, &err));
	CHECK_STR(err, "");

	CHECK_EQ(ins.source_length, 20);
	CHECK_EQ(ins.source.size(), 20);
	CHECK_EQ(ins.source_rate, 22050);
	CHECK_EQ(ins.length, 20);
	CHECK_EQ(ins.source[0], 2000);
	CHECK_EQ(ins.source[1], -32768);
	CHECK_EQ(ins.source[2], -200);
	CHECK_EQ(ins.source[3], 32518);
	CHECK_EQ(ins.source[19], 0);
	CHECK_EQ(ins.wav_loop_start, 4);
	CHECK_EQ(ins.wav_loop_end, 30);
	CHECK_EQ(ins.loop_start, 4);
	CHECK_EQ(ins.loop_end, 19);  // clamped to length-1
	CHECK_STR(ins.name, "Bass Drum.v2");

	// Untouched by the import.
	CHECK_EQ(ins.env_ar, 3);
	CHECK(ins.loop_enable);
	CHECK_EQ(ins.source_volume, 77);

	Instrument ins2;
	CHECK(import_wav(wav, "C:\\samples\\snare.WAV", ins2));
	CHECK_STR(ins2.name, "snare");
}

static void test_wav_8bit_mono()
{
	std::string pcm;
	bytes(pcm, {0, 128, 255, 64});
	for (int i = 4; i < 20; ++i) u8(pcm, 128);

	Instrument ins;
	ins.wav_loop_start = 5;  // reset by the import
	CHECK(import_wav(make_wav(1, 8000, 8, pcm), "kick", ins));

	CHECK_EQ(ins.source_length, 20);
	CHECK_EQ(ins.source_rate, 8000);
	CHECK_EQ(ins.source[0], -32768);
	CHECK_EQ(ins.source[1], 0);
	CHECK_EQ(ins.source[2], 32512);
	CHECK_EQ(ins.source[3], -16384);
	CHECK_EQ(ins.source[10], 0);
	CHECK_EQ(ins.wav_loop_start, -1);
	CHECK_EQ(ins.wav_loop_end, -1);
	CHECK_EQ(ins.loop_start, 0);
	CHECK_EQ(ins.loop_end, 19);
	CHECK_STR(ins.name, "kick");
}

static void test_wav_24_32bit_mono()
{
	std::string pcm24;
	bytes(pcm24, {0xfe, 0xff, 0xff});  // -2: 16777214/256 = 65535 -> -1
	bytes(pcm24, {0x00, 0x34, 0x12});  // 0x123400/256 = 0x1234
	for (int i = 2; i < 16; ++i) bytes(pcm24, {0, 0, 0});

	Instrument a;
	CHECK(import_wav(make_wav(1, 44100, 24, pcm24), "a.wav", a));
	CHECK_EQ(a.source_length, 16);
	CHECK_EQ(a.source[0], -1);
	CHECK_EQ(a.source[1], 0x1234);

	std::string pcm32;
	le32(pcm32, -65537);      // /65536 truncates toward zero: -1
	le32(pcm32, 0x7fffffff);  // 32767
	le32(pcm32, -65535);      // 0
	for (int i = 3; i < 16; ++i) le32(pcm32, 0);

	Instrument b;
	CHECK(import_wav(make_wav(1, 44100, 32, pcm32), "b.wav", b));
	CHECK_EQ(b.source[0], -1);
	CHECK_EQ(b.source[1], 32767);
	CHECK_EQ(b.source[2], 0);
}

static void test_wav_errors()
{
	std::string pcm;
	for (int i = 0; i < 20; ++i) le16(pcm, i * 100);
	const std::string wav = make_wav(1, 11025, 16, pcm, smpl_chunk(1, 2));

	Instrument before;
	before.name = "keep";
	before.source.assign(16, 7);
	before.source_length = 16;

	std::string err;

	// Every prefix of the file is either rejected or (once the sample data
	// is complete) imported; nothing crashes and a failure changes nothing.
	for (size_t n = 0; n < wav.size(); ++n) {
		Instrument ins = before;
		if (!import_wav(wav.substr(0, n), "x.wav", ins, &err)) {
			CHECK(!err.empty());
			CHECK_STR(ins.name, "keep");
			CHECK_EQ(ins.source.size(), 16);
			CHECK_EQ(ins.source[0], 7);
		}
	}

	Instrument ins = before;
	CHECK(!import_wav(wav.substr(0, 3), "x", ins, &err));
	CHECK_STR(err, "RIFF chunk not found");

	CHECK(!import_wav(wav.substr(0, wav.size() - 10), "x", ins, &err));  // smpl cut off
	CHECK_STR(err, "smpl chunk is truncated");

	CHECK(!import_wav(wav.substr(0, 60), "x", ins, &err));  // data cut off
	CHECK_STR(err, "data chunk is truncated");

	std::string bad = wav;
	bad[20] = 2;  // ADPCM
	CHECK(!import_wav(bad, "x", ins, &err));
	CHECK_STR(err, "Compressed files are not supported");

	std::string short_pcm;
	for (int i = 0; i < 10; ++i) le16(short_pcm, 0);
	CHECK(!import_wav(make_wav(1, 8000, 16, short_pcm), "x", ins, &err));
	CHECK_STR(err, "Sample is too short");

	CHECK(!import_wav(make_wav(0, 8000, 16, pcm), "x", ins, &err));  // divide by zero in the original
	CHECK(!import_wav(make_wav(1, 8000, 4, pcm), "x", ins, &err));

	CHECK_STR(ins.name, "keep");
	CHECK_EQ(ins.source_length, 16);
}

static void test_wav_round_trip()
{
	Instrument src;
	src.source_rate = 22050;
	src.source_length = 20;
	src.source.resize(20);
	for (int i = 0; i < 20; ++i) src.source[i] = (int16_t)(i * 1500 - 14000);
	src.name = "lead";

	const std::string wav = export_source_wav(src);
	CHECK_EQ(wav.size(), 44 + 40);
	CHECK(wav.compare(0, 4, "RIFF") == 0);
	CHECK_EQ((uint8_t)wav[4], 84 - 8);
	CHECK(wav.compare(8, 8, "WAVEfmt ") == 0);
	CHECK_EQ((uint8_t)wav[16], 16);
	CHECK_EQ((uint8_t)wav[20], 1);
	CHECK_EQ((uint8_t)wav[22], 1);
	CHECK_EQ((uint8_t)wav[24] | ((uint8_t)wav[25] << 8), 22050);
	CHECK_EQ((uint8_t)wav[28] | ((uint8_t)wav[29] << 8), 22050);  // LEGACY BUG: byte rate = sample rate
	CHECK_EQ((uint8_t)wav[32], 2);
	CHECK_EQ((uint8_t)wav[33], 0);
	CHECK_EQ((uint8_t)wav[34], 16);
	CHECK_EQ((uint8_t)wav[35], 0);
	CHECK(wav.compare(36, 4, "data") == 0);
	CHECK_EQ((uint8_t)wav[40], 40);

	Instrument dst;
	CHECK(import_wav(wav, "/tmp/lead.wav", dst));
	CHECK_EQ(dst.source_length, 20);
	CHECK_EQ(dst.source_rate, 22050);
	CHECK(dst.source == src.source);
	CHECK_EQ(dst.loop_start, 0);
	CHECK_EQ(dst.loop_end, 19);
	CHECK_STR(dst.name, "lead");

	// No source: the header plus silence (the original crashed here).
	Instrument none;
	none.source_length = 3;
	const std::string w2 = export_source_wav(none);
	CHECK_EQ(w2.size(), 50);
	CHECK(w2.substr(44) == std::string(6, '\0'));
}

// ---------------------------------------------------------------------------
// XM

static std::string xm_pattern(int rows, const std::string& packed)
{
	std::string p;
	le32(p, 9);
	u8(p, 0);
	le16(p, rows);
	le16(p, (int)packed.size());
	return p + packed;
}

static std::string make_xm(bool pnam)
{
	auto pad20 = [](std::string t) {
		t.resize(20, ' ');
		return t;
	};
	std::string x = "Extended Module: ";
	x += pad20("  My Song");
	u8(x, 0x1a);
	x += pad20("FastTracker v2.00");
	le16(x, 0x0104);
	le32(x, 276);  // header size
	le16(x, 3);    // song length (orders)
	le16(x, 1);    // restart position
	le16(x, 2);    // channels
	le16(x, 2);    // patterns
	le16(x, 0);    // instruments
	le16(x, 1);    // flags
	le16(x, 6);    // default tempo (ticks per row)
	le16(x, 125);  // default BPM
	std::string order(256, '\0');
	order[0] = 0;
	order[1] = 1;
	order[2] = 0;
	x += order;

	std::string p0;
	bytes(p0, {49, 1, 0x40, 0, 0});    // row 0 ch0: C-4, ins 1, vol 0x40
	bytes(p0, {0x99, 97, 0x0f, 3});    // row 0 ch1: key off, F03
	bytes(p0, {0x80});                 // row 1 ch0: empty
	bytes(p0, {0x82, 5});              // row 1 ch1: ins 5
	x += xm_pattern(2, p0);

	std::string p1;
	bytes(p1, {0x81, 96});             // row 0 ch0: B-7
	bytes(p1, {0x84, 0x10});           // row 0 ch1: vol 0x10
	x += xm_pattern(1, p1);

	if (pnam) {
		x += "PNAM";
		le32(x, 64);
		std::string n(64, '\0');
		n.replace(0, 4, "Kick");
		n.replace(32, 7, "Snare  ");
		x += n;
	}
	return x;
}

static void test_xm_song()
{
	Module m;
	m.songs[2].name = "old";
	m.songs[2].effect = true;

	std::string msg = "stale";
	CHECK(import_xm(make_xm(false), m, 2, false, false, &msg));
	CHECK_STR(msg, "");

	const Song& s = m.songs[2];
	CHECK_STR(s.name, "My Song");
	CHECK(!s.effect);
	CHECK_EQ(s.length, 5);
	CHECK_EQ(s.loop_start, 2);  // order 1 is the restart position

	CHECK(s.row(0).marker);
	CHECK(!s.row(1).marker);
	CHECK(s.row(2).marker);
	CHECK(s.row(3).marker);
	CHECK(!s.row(4).marker);
	CHECK(s.row(5).marker);

	CHECK_EQ(s.row(0).speed, 10);  // 19 from tempo 6, then F03: 3 ticks of 20 ms = 9.6/160 s
	CHECK_EQ(s.row(0).chn[0].note, 74);
	CHECK_EQ(s.row(0).chn[0].instrument, 1);
	CHECK_EQ(s.row(0).chn[0].volume, 74);  // volume column 0x40 is 48 of 64
	CHECK_EQ(s.row(0).chn[1].note, 1);
	CHECK_EQ(s.row(0).chn[1].volume, 255);
	CHECK_EQ(s.row(1).chn[1].instrument, 5);
	CHECK_EQ(s.row(1).chn[0].note, 0);
	CHECK_EQ(s.row(2).chn[0].note, 97);  // 96+25 clamped
	CHECK_EQ(s.row(2).chn[1].volume, 0);  // 0x10 is volume 0
	CHECK_EQ(s.row(2).speed, 0);
	CHECK_EQ(s.row(3).chn[0].note, 74);
	CHECK_EQ(s.row(3).speed, 0);  // speed unchanged since row 0
	CHECK_EQ(s.row(4).chn[1].instrument, 5);
}

// make_xm() with the header's speed and BPM and the F03 on row 0 replaced.
static std::string xm_tempo(int speed, int bpm, int fxx)
{
	std::string x = make_xm(false);
	x[76] = (char)speed;
	x[78] = (char)bpm;
	const size_t f = x.find(std::string("\x99\x61\x0f\x03", 4));
	x[f + 3] = (char)fxx;
	return x;
}

static void test_xm_tempo()
{
	auto first_speed = [](const std::string& x) {
		Module m;
		CHECK(import_xm(x, m, 0, false, false));
		return (int)m.songs[0].row(0).speed;
	};
	CHECK_EQ(first_speed(xm_tempo(6, 125, 0)), 19);    // F00 ignored; 6 x 20 ms = 19.2/160 s
	CHECK_EQ(first_speed(xm_tempo(8, 137, 0)), 23);    // 23.36
	CHECK_EQ(first_speed(xm_tempo(8, 0, 0)), 26);      // no BPM: 125
	CHECK_EQ(first_speed(xm_tempo(8, 125, 0x96)), 21);  // F96: 150 BPM, 21.33
	CHECK_EQ(first_speed(xm_tempo(31, 32, 0)), 99);    // clamped
	CHECK_EQ(first_speed(xm_tempo(1, 255, 0)), 2);     // 1.57

	// a BPM change carries into the following orders, with no new speed set
	Module m;
	CHECK(import_xm(xm_tempo(6, 125, 0x50), m, 0, false, false));
	CHECK_EQ(m.songs[0].row(0).speed, 30);  // F50: 80 BPM, 6 x 31.25 ms = 30/160 s
	CHECK_EQ(m.songs[0].row(2).speed, 0);
	CHECK_EQ(m.songs[0].row(3).speed, 0);
}

static void test_xm_effects()
{
	Module m;
	m.songs[96].name = "untouched";

	CHECK(import_xm(make_xm(true), m, 97, true, false));

	CHECK_STR(m.songs[96].name, "untouched");

	const Song& a = m.songs[97];
	CHECK_STR(a.name, "Kick");
	CHECK(a.effect);
	CHECK_EQ(a.length, MAX_ROWS - 1);
	CHECK_EQ(a.loop_start, 0);
	CHECK(a.row(0).marker);
	CHECK(a.row(2).marker);
	CHECK_EQ(a.row(0).speed, 10);
	CHECK_EQ(a.row(0).chn[0].note, 74);
	CHECK_EQ(a.row(1).chn[1].instrument, 5);

	const Song& b = m.songs[98];
	CHECK_STR(b.name, "Snare");
	CHECK(b.effect);
	CHECK(b.row(0).marker);
	CHECK(b.row(1).marker);
	CHECK_EQ(b.row(0).speed, 10);  // speed 3 carried over, speed_prev reset per song
	CHECK_EQ(b.row(0).chn[0].note, 97);
	CHECK_EQ(b.row(0).chn[1].volume, 0);
	// The third order would go to song 99, which does not exist.
}

// A 2-channel XM with no instruments, from unpacked cells.
struct XmC {
	int note = 0, ins = 0, vol = 0, fx = 0, param = 0;
};
using XmRows = std::vector<std::array<XmC, 2>>;

static std::string make_xm_fx(const std::vector<int>& orders, const std::vector<XmRows>& patterns, int speed = 6,
                              int bpm = 125)
{
	std::string x = "Extended Module: ";
	x += std::string(20, ' ');
	u8(x, 0x1a);
	x += std::string(20, ' ');
	le16(x, 0x0104);
	le32(x, 276);
	le16(x, (int)orders.size());
	le16(x, 0);  // restart position
	le16(x, 2);  // channels
	le16(x, (int)patterns.size());
	le16(x, 0);  // instruments
	le16(x, 1);
	le16(x, speed);
	le16(x, bpm);
	std::string order(256, '\0');
	for (size_t i = 0; i < orders.size(); ++i) order[i] = (char)orders[i];
	x += order;
	for (const XmRows& p : patterns) {
		std::string d;
		for (const auto& row : p)
			for (const XmC& c : row) bytes(d, {c.note, c.ins, c.vol, c.fx, c.param});
		x += xm_pattern((int)p.size(), d);
	}
	return x;
}

static Song import_fx(const XmRows& rows, XmImportInfo* info = nullptr)
{
	static Module m;
	m = Module{};
	CHECK(import_xm(make_xm_fx({0}, {rows}), m, 0, false, true, nullptr, info));
	return m.songs[0];
}

static void test_xm_fx_volume()
{
	// speed 6: slides run on 5 of a row's 6 ticks. A row gets the RMS of its
	// ticks' volumes (v of 64 is v*99/64), so a slide keeps its loudness.
	const Song s = import_fx({
		{{{49, 1, 0x30}, {49, 1, 0, 0xc, 0x20}}},        // volume column 32, C20
		{{{0, 0, 0, 0xa, 0x04}, {0, 0, 0x62}}},           // A04: -20; column 62: -10
		{{{0, 0, 0, 0xa, 0x00}, {0, 0, 0, 0xe, 0xa3}}},   // A00 again: 0; EA3: +3
		{{{0, 1}, {0, 0, 0, 0x10, 0x20}}},                // instrument: back to 64; G20: half
		{{{0, 0, 0, 0xe, 0xc0}, {0, 0, 0, 0xe, 0xc2}}},   // EC0: silent now; EC2: from tick 2
		{{{}, {}}},
	});
	CHECK_EQ(s.row(0).chn[0].volume, 50);
	CHECK_EQ(s.row(0).chn[1].volume, 50);
	CHECK_EQ(s.row(1).chn[0].volume, 36);  // 32, 28 ... 12: RMS 23
	CHECK_EQ(s.row(1).chn[1].volume, 42);  // 32, 30 ... 22: RMS 27.2
	CHECK_EQ(s.row(2).chn[0].volume, 9);   // 12, 8, 4, 0, 0, 0: RMS 6.1
	CHECK_EQ(s.row(2).chn[1].volume, 39);  // 25
	CHECK_EQ(s.row(3).chn[0].volume, 50);  // 64 at half global volume
	CHECK_EQ(s.row(3).chn[1].volume, 19);  // 25 at half
	CHECK_EQ(s.row(4).chn[0].volume, 0);
	CHECK_EQ(s.row(4).chn[1].volume, 11);  // 25 at half for 2 ticks, then 0: RMS 7.2
	CHECK_EQ(s.row(5).chn[1].volume, 0);
	CHECK_EQ(s.row(5).chn[0].volume, 255);
}

static void test_xm_fx_pitch()
{
	// C-4 at speed 6, 125 BPM: a row is 19 driver ticks, 1068 pitch units
	const Song s = import_fx({
		{{{49, 1, 0, 0x1, 0x08}, {49, 1, 0, 0x4, 0x48}}},  // 108: up 2.5 semitones a row; 448
		{{{0, 0, 0, 0x1, 0x00}, {0, 0, 0, 0x4, 0x00}}},    // the same again, from higher up; 400
		{{{}, {}}},                                         // the slide and vibrato stop
		{{{0, 0, 0, 0x2, 0x04}, {49, 0, 0xb4}}},           // 204: down 1.25 semitones; column V4
		{{{}, {}}},
		{{{49, 1}, {}}},
		{{{53, 0, 0, 0x3, 0x10}, {}}},                     // 310 to E-4
		{{{56, 0, 0, 0x3, 0x00}, {}}},                     // 300 on to G-4: rate kept
		{{{49, 1}, {}}},                                    // a plain note: portamento off
	});
	auto fx = [&](int row, int chn) { return std::string(1, (char)s.row(row).chn[chn].effect) + std::to_string(s.row(row).chn[chn].value); };
	CHECK_STR(fx(0, 0), "U9");   // 1068 x (2^(2.5/12) - 1) / 19 = 8.7
	CHECK_STR(fx(1, 0), "U10");  // from 1234 units
	CHECK_STR(fx(2, 0), "U0");
	CHECK_STR(fx(3, 0), "D5");   // from 1425 units: 5.2
	CHECK_STR(fx(4, 0), "D0");
	CHECK_STR(fx(6, 0), "P19");  // 5 semitones a row from C-4: 18.8
	CHECK_EQ(s.row(6).chn[0].note, 54);
	CHECK_EQ(s.row(7).chn[0].effect, 0);
	CHECK_STR(fx(8, 0), "P0");

	// vibrato: speed 4 is 2.6 Hz, the driver's 3; depth 8 is a semitone, 8
	CHECK_STR(fx(0, 1), "V38");
	CHECK_EQ(s.row(1).chn[1].effect, 0);  // unchanged
	CHECK_STR(fx(2, 1), "V0");
	CHECK_STR(fx(3, 1), "V34");
}

static void test_xm_fx_other()
{
	XmImportInfo info;
	const Song s = import_fx({
		{{{49, 1, 0, 0x8, 0x00}, {49, 1, 0xc4}}},      // 800 hard left; column P4
		{{{0, 0, 0, 0x8, 0xff}, {0, 2}}},              // 8FF; an instrument resets the pan
		{{{0, 0, 0, 0x14, 0x00}, {0, 0, 0, 0xe, 0xe2}}},  // K00 key off; EE2: the row lasts 3
		{{{0, 0, 0, 0x0, 0x37}, {0, 0, 0, 0x7, 0x44}}},   // arpeggio, tremolo: no equivalent
		{{{0, 0, 0, 0x7, 0x44}, {}}},
		{{{0, 0, 0xd2}, {0, 0, 0, 0x19, 0x40}}},     // column L2: left 10 a row; P40: right 20
	}, &info);
	auto fx = [&](int row, int chn) { return std::string(1, (char)s.row(row).chn[chn].effect) + std::to_string(s.row(row).chn[chn].value); };
	CHECK_STR(fx(0, 0), "S0");
	CHECK_STR(fx(0, 1), "S25");
	CHECK_STR(fx(1, 0), "S99");
	CHECK_STR(fx(1, 1), "S50");
	CHECK_EQ(s.row(2).chn[0].note, 1);
	CHECK_EQ(s.row(2).speed, 58);  // 19.2 x 3
	CHECK_EQ(s.row(3).speed, 19);
	CHECK_STR(fx(5, 0), "S96");  // 245 of 255
	CHECK_STR(fx(5, 1), "S58");  // 148
	CHECK_STR(info.not_converted, "tremolo (2), arpeggio (1)");
}

static void test_xm_fx_flow()
{
	// order 0 breaks (D02) into order 1 at row 2; order 1 jumps back to
	// itself (B01): the song is those rows, looping at order 1
	const XmRows p0 = {{{{49}, {}}}, {{{51}, {0, 0, 0, 0xd, 0x02}}}, {{{60}, {}}}, {{{60}, {}}}};
	const XmRows p1 = {{{{61}, {}}}, {{{62}, {}}}, {{{63}, {}}}, {{{64}, {0, 0, 0, 0xb, 0x01}}}};
	Module m;
	CHECK(import_xm(make_xm_fx({0, 1}, {p0, p1}), m, 0, false, true));
	const Song& s = m.songs[0];
	CHECK_EQ(s.length, 4);
	CHECK_EQ(s.loop_start, 2);
	CHECK_EQ(s.row(0).chn[0].note, 50);
	CHECK_EQ(s.row(1).chn[0].note, 52);
	CHECK_EQ(s.row(2).chn[0].note, 64);
	CHECK_EQ(s.row(3).chn[0].note, 65);
	CHECK(s.row(2).marker);
}

// make_xm_fx() rows with two instruments, each a 16-frame looped 8-bit
// sample: 1 with envelopes, 2 without.
static std::string make_xm_env(const XmRows& rows)
{
	std::string x = make_xm_fx({0}, {rows});
	x[60 + 12] = 2;  // instruments
	for (int k = 0; k < 2; ++k) {
		std::string h(263, '\0');
		h[0] = (char)263;
		h[1] = 1;
		h[27] = 1;   // one sample
		h[29] = 40;  // sample header size
		if (k == 0) {
			// volume: (0,64) (12,32) (24,32) (48,0), sustain at point 2; fadeout 4096
			const int vol[] = {0, 64, 12, 32, 24, 32, 48, 0};
			for (int i = 0; i < 8; ++i) set_le16(h, 129 + i * 2, vol[i]);
			const int pan[] = {0, 32, 6, 64};  // pan: from the centre to the right
			for (int i = 0; i < 4; ++i) set_le16(h, 177 + i * 2, pan[i]);
			h[225] = 4;  // volume points
			h[226] = 2;  // pan points
			h[227] = 2;  // volume sustain point
			h[233] = 3;  // volume envelope on, with sustain
			h[234] = 1;  // pan envelope on
			set_le16(h, 239, 4096);
		}
		x += h;
		std::string smp(40, '\0');
		smp[0] = 16;      // frames
		smp[8] = 16;      // loop length
		smp[12] = 64;     // volume
		smp[14] = 1;      // forward loop
		smp[15] = (char)128;
		x += smp;
		for (int i = 0; i < 16; ++i) x += (char)(i & 1 ? -40 : 40);  // delta-coded square wave
	}
	return x;
}

static void test_xm_envelopes()
{
	// speed 6: a row is 6 ticks
	XmRows rows(10, {XmC{}, XmC{}});
	rows[0] = {XmC{49, 1}, XmC{49, 2}};
	rows[6] = {XmC{97}, XmC{97}};  // key offs
	Module m;
	CHECK(import_xm(make_xm_env(rows), m, 0, false, true));
	const Song& s = m.songs[0];
	auto vol = [&](int row) { return (int)s.row(row).chn[0].volume; };

	// each row the RMS of its ticks
	CHECK_EQ(vol(0), 89);   // 64 falling to 50.7: 57.5
	CHECK_EQ(vol(1), 64);   // 48 to 34.7: 41.6
	CHECK_EQ(vol(2), 50);   // 32, held from the sustain point on
	CHECK_EQ(vol(3), 255);
	CHECK_EQ(vol(6), 33);   // the key off releases it, fading: 21.6...
	CHECK_EQ(s.row(6).chn[0].note, 0);  // ...and no key off for the driver yet
	CHECK_EQ(vol(7), 4);    // the fade's last 2 ticks
	CHECK_EQ(s.row(7).chn[0].note, 1);  // faded out by the row's end: now the key off
	CHECK_EQ(vol(8), 255);

	// the pan envelope: right by tick 6
	CHECK_EQ(s.row(0).chn[0].effect, 0);
	CHECK_EQ(s.row(1).chn[0].effect, 'S');
	CHECK_EQ(s.row(1).chn[0].value, 99);

	// no envelope: a key off cuts, as it does in FT2
	CHECK_EQ(s.row(6).chn[1].note, 1);
	CHECK_EQ(s.row(1).chn[1].volume, 255);

	// without samples the instruments are the module's own: no envelopes
	Module own;
	CHECK(import_xm(make_xm_env(rows), own, 0, false, false));
	CHECK_EQ(own.songs[0].row(6).chn[0].note, 1);
	CHECK_EQ(own.songs[0].row(1).chn[0].volume, 255);
}

// make_xm() plus three instruments: 1 "Sine" (8-bit, forward loop, finetune
// -5 so it needs no retune), 2 with no samples, 3 "Bass" (two samples, the
// keymap picks the second: 16-bit, ping-pong loop, relative note +12).
static const int8_t SINE[64] = {0, 12, 23, 33, 40, 45, 47, 45, 40, 33, 23, 12, 0, -12, -23, -33, -40, -45, -47, -45, -40, -33,
                                -23, -12, 0, 12, 23, 33, 40, 45, 47, 45, 40, 33, 23, 12, 0, -12, -23, -33, -40, -45, -47, -45,
                                -40, -33, -23, -12, 0, 12, 23, 33, 40, 45, 47, 45, 40, 33, 23, 12, 0, -12, -23, -33};

static std::string make_xm_with_samples()
{
	std::string x = make_xm(false);
	x[60 + 12] = 3;  // instruments

	auto instrument = [&](const char* name, int samples, int keymap_c4) {
		std::string h(samples ? 263 : 29, '\0');
		const uint32_t size = (uint32_t)h.size();
		std::memcpy(&h[0], &size, 4);
		std::memcpy(&h[4], name, std::strlen(name));
		h[27] = (char)samples;
		if (samples) {
			h[29] = 40;  // sample header size
			h[33 + 48] = (char)keymap_c4;
		}
		x += h;
	};
	auto sample = [&](uint32_t bytes, uint32_t loop_start, uint32_t loop_len, int vol, int finetune, int type, int relnote,
	                  const char* name) {
		std::string h(40, '\0');
		std::memcpy(&h[0], &bytes, 4);
		std::memcpy(&h[4], &loop_start, 4);
		std::memcpy(&h[8], &loop_len, 4);
		h[12] = (char)vol;
		h[13] = (char)finetune;
		h[14] = (char)type;
		h[16] = (char)relnote;
		std::memcpy(&h[18], name, std::strlen(name));
		x += h;
	};

	instrument("Sine", 1, 0);
	sample(64, 16, 32, 64, -5, 1, 0, "sine smp");
	int8_t prev = 0;
	for (int8_t v : SINE) {  // delta encoded
		x += (char)(int8_t)(v - prev);
		prev = v;
	}

	instrument("", 0, 0);

	instrument("Bass", 2, 1);
	sample(10, 0, 0, 64, 0, 0, 0, "unused");
	sample(200, 40, 80, 32, 0, 0x10 | 2, 12, "bass smp");
	x += std::string(10, '\x01');
	int16_t prev16 = 0;
	for (int i = 0; i < 100; ++i) {
		const int16_t v = (int16_t)(i * 300 - 15000);
		const int16_t d = (int16_t)(v - prev16);
		x += (char)(d & 255);
		x += (char)((d >> 8) & 255);
		prev16 = v;
	}
	return x;
}

static void test_xm_samples()
{
	// In use: slot 1 has a sample, song 2 plays slot 3. Song 1, which the
	// import replaces, doesn't count. So the XM's instruments start at slot 4.
	Module m;
	m.instruments[0].name = "Existing";
	m.instruments[0].source.assign(16, 100);
	m.instruments[1].name = "keep";
	m.songs[1].row_mut(5).chn[2].instrument = 3;
	m.songs[0].row_mut(5).chn[2].instrument = 40;
	std::string msg;
	XmImportInfo info;
	CHECK(import_xm(make_xm_with_samples(), m, 0, false, true, &msg, &info));
	CHECK_STR(msg, "");
	CHECK(info.instruments == std::vector<int>({3, 4}));  // slot 6 (5 here) is only played, empty
	CHECK(info.instruments_replaced.empty());
	CHECK(info.songs == std::vector<int>({0}));
	CHECK_STR(m.instruments[0].name, "Existing");  // the module's own, untouched
	CHECK_STR(m.instruments[1].name, "keep");
	CHECK(!m.instruments[2].has_source());
	CHECK_EQ(m.songs[1].row(5).chn[2].instrument, 3);

	// XM instruments 1 and 3 have samples, 5 is only played by the notes
	// (2 neither): they take slots 4, 5 and 6, and the notes follow
	CHECK_EQ(m.songs[0].row(0).chn[0].instrument, 4);
	CHECK_EQ(m.songs[0].row(1).chn[1].instrument, 6);
	CHECK_EQ(m.songs[0].row(3).chn[0].instrument, 4);
	CHECK(!m.instruments[5].has_source());

	// 1: forward loop, data after the loop dropped, no retune needed
	const Instrument& sine = m.instruments[3];
	CHECK_STR(sine.name, "Sine");
	CHECK_EQ(sine.source_length, 48);
	CHECK_EQ(sine.length, 48);
	CHECK(sine.loop_enable);
	CHECK_EQ(sine.loop_start, 16);
	CHECK_EQ(sine.loop_end, 47);
	CHECK_EQ(sine.wav_loop_start, 16);
	CHECK_EQ(sine.source_volume, 128);
	CHECK_EQ(sine.source_rate, 8344);
	bool exact = true;  // faded in over 2 ms, but only up to the loop: 16 frames; then the XM's samples
	for (int i = 0; i < 48; ++i) exact = exact && sine.source[i] == (i < 16 ? SINE[i] * 256 * i / 16 : SINE[i] * 256);
	CHECK(exact);
	CHECK_EQ(sine.source[0], 0);

	// 3: the keymap's sample; ping-pong unrolled (20 + 78 frames of loop), then
	// an octave down to the driver's C-4. The loop comes out 39 frames: 32 or
	// 48 would detune it, so it stays exact and the encoder repeats it (Unroll).
	// It starts a kernel's reach (12 zero crossings at half rate: 24 frames)
	// past the original's start, (20 + 24) / 2 = 22, where the output repeats.
	const Instrument& bass = m.instruments[4];
	CHECK_STR(bass.name, "Bass");
	CHECK_EQ(bass.source_length, 61);
	CHECK(bass.loop_enable);
	CHECK(bass.loop_unroll);
	CHECK_EQ(bass.loop_start, 22);
	CHECK_EQ(bass.loop_end, 60);
	CHECK_EQ(bass.source[21], bass.source[60]);  // seamless: the frame before the loop is its last
	CHECK(!sine.loop_unroll);  // 32 frames: whole blocks already
	CHECK_EQ(bass.source_volume, 64);

	// with samples, notes keep their written octave: XM C-4 is editor C-4
	CHECK_EQ(m.songs[0].row(0).chn[0].note, 50);
	Module legacy;
	CHECK(import_xm(make_xm_with_samples(), legacy, 0, false, false));
	CHECK_EQ(legacy.songs[0].row(0).chn[0].note, 74);  // notes only: two octaves up
	CHECK(!legacy.instruments[0].has_source());
	CHECK_EQ(legacy.songs[0].row(0).chn[0].instrument, 1);  // and the XM's own numbers

	// not enough room after the last slot in use: nothing changes
	Module full_slots;
	full_slots.instruments[97].source.assign(16, 100);
	full_slots.songs[0].name = "keep";
	CHECK(!import_xm(make_xm_with_samples(), full_slots, 0, false, true, &msg));
	CHECK_STR(msg, "Not enough free instrument slots: the XM needs 3, and 1 is free after slot 98, the last in use.");
	CHECK_STR(full_slots.songs[0].name, "keep");
	CHECK(!full_slots.instruments[98].has_source());

	// a file cut anywhere in the sample data changes nothing
	const std::string full = make_xm_with_samples();
	const size_t samples_start = make_xm(false).size();
	for (size_t n = samples_start; n < full.size(); ++n) {
		Module t;
		t.songs[0].name = "keep";
		t.instruments[0].name = "keep";
		if (import_xm(full.substr(0, n), t, 0, false, true, &msg)) {
			CHECK(false);
			break;
		}
		CHECK_STR(t.songs[0].name, "keep");
		CHECK_STR(t.instruments[0].name, "keep");
	}
}

static void test_xm_reimport()
{
	// first import: song 1, instruments 1 (Sine) and 2 (Bass), 3 left empty for XM instrument 5
	Module m;
	XmImportInfo a, b;
	CHECK(import_xm(make_xm_with_samples(), m, song_append_slot(m), false, true, nullptr, &a));
	CHECK(a.songs == std::vector<int>({0}));
	CHECK(a.songs_replaced.empty());
	CHECK(a.instruments == std::vector<int>({0, 1}));

	// changes in SNES GSS, and another song
	m.instruments[0].env_sr = 5;
	m.instruments[0].eq_low = 10;
	m.instruments[0].source_volume = 77;
	m.songs[1].name = "other";
	m.songs[1].row_mut(0).chn[0].note = 50;

	// again: the same song and instruments, by name, are replaced
	CHECK(import_xm(make_xm_with_samples(), m, song_append_slot(m), false, true, nullptr, &b));
	CHECK(b.songs == std::vector<int>({0}));
	CHECK(b.songs_replaced == std::vector<int>({0}));
	CHECK(b.instruments.empty());
	CHECK(b.instruments_replaced == std::vector<int>({0, 1}));
	CHECK_STR(m.songs[0].name, "My Song");
	CHECK_STR(m.songs[1].name, "other");
	CHECK_EQ(song_append_slot(m), 2);  // no song added
	CHECK(!m.instruments[3].has_source());  // nor an instrument
	CHECK_EQ(m.songs[0].row(0).chn[0].instrument, 1);
	CHECK_EQ(m.songs[0].row(1).chn[1].instrument, 3);  // the same empty slot as before
	CHECK_EQ(m.instruments[0].env_sr, 5);  // SNES GSS settings kept
	CHECK_EQ(m.instruments[0].eq_low, 10);
	CHECK_EQ(m.instruments[0].source_volume, 128);  // the XM's volume
	CHECK_EQ(m.instruments[0].source_length, 48);

	// sound effects: each pattern's song matched by name, the rest added
	Module fx;
	fx.songs[5].name = "Snare";
	XmImportInfo c;
	CHECK(import_xm(make_xm(true), fx, song_append_slot(fx), true, false, nullptr, &c));
	CHECK(c.songs == std::vector<int>({6, 5, 7}));  // Kick, Snare, unnamed
	CHECK(c.songs_replaced == std::vector<int>({5}));
	CHECK_STR(fx.songs[6].name, "Kick");
	CHECK(fx.songs[5].effect);

	// every song slot in use: a song with the same name can still be replaced
	Module full;
	for (int i = 0; i < MAX_SONGS; ++i) full.songs[i].name = "song " + std::to_string(i + 1);
	full.songs[40].name = "My Song";
	CHECK_EQ(song_append_slot(full), MAX_SONGS);
	XmImportInfo d;
	CHECK(import_xm(make_xm(false), full, song_append_slot(full), false, false, nullptr, &d));
	CHECK(d.songs == std::vector<int>({40}));
	full.songs[40].name = "renamed";
	std::string msg;
	CHECK(!import_xm(make_xm(false), full, song_append_slot(full), false, false, &msg));
	CHECK_STR(msg, "There is no free song slot after the last song in use.");
	CHECK_STR(full.songs[40].name, "renamed");
}

static void test_xm_errors()
{
	const std::string xm = make_xm(false);
	std::string msg;

	for (size_t n = 0; n < xm.size(); ++n) {
		Module m;
		m.songs[0].name = "keep";
		CHECK(!import_xm(xm.substr(0, n), m, 0, false, false, &msg));
		CHECK(!msg.empty());
		CHECK_STR(m.songs[0].name, "keep");
		CHECK(!m.songs[0].allocated());
	}

	Module m;
	CHECK(!import_xm("Extended Module", m, 0, false, false, &msg));
	CHECK_STR(msg, "Not a module");

	std::string no_orders = xm;
	no_orders[64] = 0;
	CHECK(!import_xm(no_orders, m, 0, false, false, &msg));
	CHECK_STR(msg, "Module should have at least one order position");

	CHECK(!import_xm(xm, m, MAX_SONGS, false, false, &msg));
}

// ---------------------------------------------------------------------------
// MIDI

static std::string midi_varlen(int v)
{
	std::string out;
	int buf = v & 0x7f;
	while ((v >>= 7) > 0) buf = (buf << 8) | 0x80 | (v & 0x7f);
	while (true) {
		u8(out, buf);
		if (buf & 0x80) buf >>= 8; else break;
	}
	return out;
}

static std::string mtrk(const std::string& events)
{
	std::string t = "MTrk";
	be32(t, (int)events.size());
	return t + events;
}

static std::string mthd(int format, int tracks, int division)
{
	std::string h = "MThd";
	be32(h, 6);
	be16(h, format);
	be16(h, tracks);
	be16(h, division);
	return h;
}

static void ev(std::string& t, int delta, std::initializer_list<int> l)
{
	t += midi_varlen(delta);
	bytes(t, l);
}

static std::string midi_format0()
{
	std::string t;
	ev(t, 0, {0xff, 0x51, 0x03, 0x06, 0x1a, 0x80});  // 400000 us = 150 BPM
	ev(t, 0, {0x90, 60, 100});                       // ch0 note on
	ev(t, 0, {0x99, 36, 100});                       // drum: bass drum
	ev(t, 24, {0x80, 60, 64});                       // row 1: note off
	ev(t, 24, {0x90, 62, 100});                      // row 2
	ev(t, 0, {64, 100});                             // running status: overwrites row 2
	ev(t, 24, {62, 0});                              // row 3: velocity 0 = key off
	ev(t, 0, {0x99, 42, 100});                       // hat
	ev(t, 0, {0x99, 45, 100});                       // tom
	ev(t, 0, {0xb0, 7, 100});                        // controller
	ev(t, 0, {0xc0, 5});                             // program change (one data byte)
	ev(t, 0, {0xff, 0x51, 0x03, 0x09, 0x27, 0xc0});  // 600000 us = 100 BPM at row 3
	ev(t, 0, {0xff, 0x2f, 0x00});
	return mthd(0, 1, 96) + mtrk(t);
}

static void test_midi_format0()
{
	Module m;
	m.songs[3].name = "old";
	m.songs[3].length = 10;

	std::string err = "stale";
	CHECK(import_midi(midi_format0(), m, 3, &err));
	CHECK_STR(err, "");

	const Song& s = m.songs[3];
	CHECK_STR(s.name, "untitled");  // SongClear
	CHECK_EQ(s.length, MAX_ROWS - 1);

	CHECK_EQ(s.row(0).speed, 16);  // 160/(150/60*4)
	CHECK_EQ(s.row(0).chn[0].note, 62);
	CHECK_EQ(s.row(0).chn[0].instrument, 1);
	CHECK_EQ(s.row(0).chn[7].note, 62);
	CHECK_EQ(s.row(0).chn[7].instrument, 10);

	CHECK_EQ(s.row(1).chn[0].note, 1);
	CHECK_EQ(s.row(2).chn[0].note, 66);
	CHECK_EQ(s.row(2).chn[0].instrument, 0);  // only the first note gets one

	CHECK_EQ(s.row(3).chn[0].note, 1);
	CHECK_EQ(s.row(3).chn[6].note, 62);
	CHECK_EQ(s.row(3).chn[6].instrument, 13);
	CHECK_EQ(s.row(3).chn[7].note, 62);
	CHECK_EQ(s.row(3).chn[7].instrument, 12);
	CHECK_EQ(s.row(3).speed, 24);  // 160/(100/60*4)
	CHECK_EQ(s.row(4).chn[0].note, 0);
}

static std::string midi_format1()
{
	std::string t0;
	ev(t0, 0, {0xff, 0x51, 0x03, 0x09, 0x27, 0xc0});  // 100 BPM
	ev(t0, 0, {0xff, 0x2f, 0x00});

	std::string t1;
	ev(t1, 0, {0xff, 0x03, 0x04, 'B', 'a', 's', 's'});  // track name
	ev(t1, 96, {0x91, 48, 90});                        // row 4, ch1
	ev(t1, 0, {0x99, 38, 90});                         // snare
	ev(t1, 0, {0x9a, 50, 90});                         // ch10: ignored
	ev(t1, 0, {0xff, 0x2f, 0x00});

	return mthd(1, 2, 96) + mtrk(t0) + mtrk(t1);
}

static void test_midi_format1()
{
	Module m;
	CHECK(import_midi(midi_format1(), m, 0));

	const Song& s = m.songs[0];
	CHECK_EQ(s.row(0).speed, 24);
	CHECK_EQ(s.row(4).speed, 0);  // track 1 starts at 120 BPM again, no change
	CHECK_EQ(s.row(4).chn[1].note, 50);
	CHECK_EQ(s.row(4).chn[1].instrument, 2);
	CHECK_EQ(s.row(4).chn[7].note, 62);
	CHECK_EQ(s.row(4).chn[7].instrument, 11);
	for (int c = 0; c < 8; ++c)
		if (c != 1 && c != 7) CHECK_EQ(s.row(4).chn[c].note, 0);
}

static void test_midi_errors()
{
	std::string err;
	Module m;

	CHECK(!import_midi("MThd", m, 0, &err));
	CHECK_STR(err, "Not a MIDI file");
	CHECK(!import_midi(mthd(0, 1, 0) + mtrk(""), m, 0, &err));

	// Header says two tracks, the file has one: the original kept what it
	// had imported.
	std::string t;
	ev(t, 0, {0x90, 60, 100});
	ev(t, 0, {0xff, 0x2f, 0x00});
	std::string partial = mthd(1, 2, 96) + mtrk(t);
	CHECK(!import_midi(partial, m, 5, &err));
	CHECK_STR(err, "MIDI track data not found");
	CHECK_EQ(m.songs[5].row(0).chn[0].note, 62);

	const std::string full = midi_format0();
	for (size_t n = 0; n + 3 < full.size(); ++n) {
		Module mm;
		const bool r = import_midi(full.substr(0, n), mm, 0, &err);
		CHECK(!r);
		CHECK(!err.empty());
	}
}

// ---------------------------------------------------------------------------
// FamiTracker text export

static const char* const FTM =
	"# FamiTracker text export 0.4.2\n"
	"\n"
	"# Song information\n"
	"TITLE           \"Test\"\n"
	"\n"
	"# Tracks\n"
	"\n"
	"TRACK  16   6 150 \"First\"\n"
	"COLUMNS : 1 1 1 1 1\n"
	"\n"
	"ORDER 00 : 00 00 00 00 00\n"
	"ORDER 01 : 01 00 00 00 00\n"
	"\n"
	"PATTERN 00\n"
	"ROW 00 : C-4 00 F ... : D#3 01 A ... : ... .. . ... : C-# .. . ... : ... .. . ...\n"
	"ROW 01 : --- .. . F06 : ... .. . B01 : ... .. . ... : ... .. . ... : ... .. . ...\n"
	"ROW 02 : E-1 .. . ... : ... .. . ... : ... .. . ... : ... .. . ... : ... .. . ...\n"
	"\n"
	"PATTERN 01\n"
	"ROW 00 : E-2 .. 5 ... : ... .. . ... : ... .. . ... : ... .. . ... : ... .. . ...\n"
	"ROW 01 : ... .. . C00 : ... .. . ... : ... .. . ... : ... .. . ... : ... .. . ...\n"
	"\n"
	"TRACK   8   3 150 \"Second\"\n"
	"COLUMNS : 1 1 1 1 1\n"
	"\n"
	"ORDER 00 : 00 00 00 00 00\n"
	"\n"
	"PATTERN 00\n"
	"ROW 00 : G-1 .. . ... : ... .. . ... : ... .. . ... : ... .. . ... : ... .. . ...\n"
	"\n"
	"# End of export\n";

static void test_ftm()
{
	Module m;
	m.songs[5].name = "Keep";
	m.songs[5].effect = true;
	m.songs[5].loop_start = 9;

	std::string err = "stale";
	CHECK(import_famitracker_text(FTM, 1, m, 5, &err));
	CHECK_STR(err, "");

	const Song& s = m.songs[5];
	CHECK_STR(s.name, "Keep");  // name and effect flag survive the clear
	CHECK(s.effect);
	CHECK_EQ(s.length, 4);
	CHECK_EQ(s.loop_start, 2);  // B01 on pattern 00 -> order 1 starts at row 2

	CHECK(s.row(0).marker);
	CHECK(!s.row(1).marker);
	CHECK(s.row(2).marker);
	CHECK(!s.row(3).marker);
	CHECK(s.row(4).marker);

	CHECK_EQ(s.row(0).speed, 0);
	CHECK_EQ(s.row(0).chn[0].note, 50);
	CHECK_EQ(s.row(0).chn[0].volume, 99);
	CHECK_EQ(s.row(0).chn[0].instrument, 0);
	CHECK_EQ(s.row(0).chn[1].note, 41);
	CHECK_EQ(s.row(0).chn[1].volume, 66);
	CHECK_EQ(s.row(0).chn[2].note, 0);
	CHECK_EQ(s.row(0).chn[2].volume, 255);
	CHECK_EQ(s.row(0).chn[3].note, 102);  // LEGACY BUG: noise "C-#" -> 2+('#'-'0')*12
	CHECK_EQ(s.row(0).chn[5].note, 0);

	CHECK_EQ(s.row(1).speed, 16);  // F06 -> 160*6/60
	CHECK_EQ(s.row(1).chn[0].note, 1);

	CHECK_EQ(s.row(2).chn[0].note, 30);
	CHECK_EQ(s.row(2).chn[0].volume, 33);  // 5*99/15
	CHECK_EQ(s.row(2).chn[1].note, 41);
	CHECK_EQ(s.row(2).speed, 0);

	CHECK_EQ(s.row(3).chn[0].note, 0);
	CHECK_EQ(s.row(3).speed, 16);  // from pattern 00 row 1 on the other channels
	CHECK_EQ(s.row(4).chn[0].note, 0);  // pattern 00 row 2 was cut by B01

	Module m2;
	CHECK(import_famitracker_text(FTM, 2, m2, 0, &err));
	const Song& t = m2.songs[0];
	CHECK_EQ(t.length, 1);
	CHECK_EQ(t.loop_start, 0);
	CHECK(t.row(0).marker);
	CHECK(t.row(1).marker);
	CHECK_EQ(t.row(0).chn[0].note, 21);
	CHECK_STR(t.name, "untitled");

	// LEGACY BUG: a sub song past the last track clears the song.
	Module m3;
	m3.songs[1].name = "n";
	m3.songs[1].row_mut(7).chn[0].note = 30;
	CHECK(import_famitracker_text(FTM, 3, m3, 1, &err));
	CHECK_EQ(m3.songs[1].length, 0);
	CHECK(m3.songs[1].row(0).marker);
	CHECK_EQ(m3.songs[1].row(7).chn[0].note, 0);
	CHECK_STR(m3.songs[1].name, "n");
}

static void test_ftm_track_names()
{
	const std::vector<std::string> names = famitracker_track_names(FTM);
	CHECK_EQ(names.size(), 2);
	CHECK_STR(names[0], "First");
	CHECK_STR(names[1], "Second");
	CHECK_EQ(famitracker_track_names("TRACK  64   6 150\n").size(), 1);  // no name
	CHECK_STR(famitracker_track_names("TRACK  64   6 150\n")[0], "");
	CHECK(famitracker_track_names("# FamiTracker text export\n").empty());
}

static void test_ftm_errors()
{
	std::string err;
	Module m;
	m.songs[0].name = "keep";
	m.songs[0].row_mut(0).chn[0].note = 40;

	CHECK(!import_famitracker_text("# FamiTracker", 1, m, 0, &err));
	CHECK_STR(err, "Not a FamiTracker text export file");

	const std::string text = FTM;
	const size_t cut = text.find("ROW 00 : G-1") + 15;
	CHECK(!import_famitracker_text(text.substr(0, cut), 2, m, 0, &err));
	CHECK_STR(err, "FamiTracker text export is truncated");

	CHECK_STR(m.songs[0].name, "keep");
	CHECK_EQ(m.songs[0].row(0).chn[0].note, 40);

	// No prefix crashes.
	for (size_t n = 0; n < text.size(); ++n) {
		Module mm;
		import_famitracker_text(text.substr(0, n), 1, mm, 0, &err);
	}
}

// ---------------------------------------------------------------------------
// SPC bank

static std::string bank_record(int source_length, int length, int loop_start, int rate, std::initializer_list<int> env,
	int flags, int volume, int first_sample)
{
	std::string r;
	le32(r, source_length);
	le32(r, length);
	le32(r, loop_start);
	le16(r, rate);
	for (int e : env) u8(r, e);
	u8(r, flags);
	u8(r, volume);
	le16(r, 0);  // pad to 22 bytes
	for (int i = 0; i < source_length; ++i) le16(r, first_sample + i * 100);
	return r;
}

static std::string make_bank()
{
	std::string b;
	b += bank_record(20, 18, 4, 32000, {10, 5, 3, 2}, 3, 200, -1000);
	b += bank_record(0, 5, 0, 16000, {1, 2, 3, 4}, 0, 100, 0);
	b += bank_record(4, 4, 0, 8000, {0, 0, 0, 0}, 1, 128, 1);
	for (int i = 3; i < 64; ++i) b += bank_record(0, 0, 0, 0, {0, 0, 0, 0}, 0, 0, 0);
	return b;
}

static void test_spc_bank()
{
	Module m;
	m.instruments[0].loop_unroll = true;
	m.instruments[70].name = "old";
	m.instruments[70].loop_unroll = true;
	m.instruments[70].ramp_enable = true;
	m.instruments[70].source.assign(32, 1);
	m.instruments[70].source_length = 32;
	m.instruments[70].env_ar = 1;

	std::string err = "stale";
	CHECK(import_spc_bank(make_bank(), m, &err));
	CHECK_STR(err, "");

	const Instrument& a = m.instruments[0];
	CHECK_EQ(a.source_length, 20);
	CHECK_EQ(a.source.size(), 20);
	CHECK_EQ(a.length, 18);
	CHECK_EQ(a.loop_start, 4);
	CHECK_EQ(a.loop_end, 17);
	CHECK_EQ(a.source_rate, 32000);
	CHECK_EQ(a.env_ar, 10);
	CHECK_EQ(a.env_dr, 5);
	CHECK_EQ(a.env_sl, 3);
	CHECK_EQ(a.env_sr, 2);
	CHECK(a.loop_enable);
	CHECK(a.ramp_enable);
	CHECK_EQ(a.source_volume, 164);  // 128+(200-128)/2
	CHECK_EQ(a.source[0], -1000);
	CHECK_EQ(a.source[19], 900);
	CHECK_STR(a.name, "imported 1");
	CHECK(a.loop_unroll);  // InstrumentClear leaves it alone
	CHECK_EQ(a.wav_loop_start, -1);

	const Instrument& b = m.instruments[1];
	CHECK(!b.has_source());
	CHECK_EQ(b.length, 5);
	CHECK_EQ(b.loop_end, 4);
	CHECK_EQ(b.source_rate, 16000);
	CHECK_EQ(b.env_sr, 4);
	CHECK(!b.loop_enable);
	CHECK_EQ(b.source_volume, 100);
	CHECK_STR(b.name, "none");

	const Instrument& c = m.instruments[2];
	CHECK_EQ(c.source_length, 4);
	CHECK_EQ(c.source.size(), 16);  // padded to the model minimum
	CHECK_EQ(c.source[3], 301);
	CHECK_EQ(c.source[4], 0);
	CHECK(c.loop_enable);
	CHECK(!c.ramp_enable);
	CHECK_STR(c.name, "imported 3");

	const Instrument& d = m.instruments[3];
	CHECK_EQ(d.length, 0);
	CHECK_EQ(d.loop_end, -1);
	CHECK_EQ(d.env_ar, 0);
	CHECK_EQ(d.source_volume, 0);

	const Instrument& e = m.instruments[70];  // beyond the 64 records: cleared
	CHECK(!e.has_source());
	CHECK_EQ(e.source_length, 0);
	CHECK_STR(e.name, "none");
	CHECK_EQ(e.env_ar, 15);
	CHECK(e.loop_unroll);
	CHECK(e.ramp_enable);
}

static void test_spc_bank_errors()
{
	const std::string bank = make_bank();
	std::string err;

	for (size_t n = 0; n < bank.size(); n += 7) {
		Module m;
		m.instruments[0].name = "keep";
		CHECK(!import_spc_bank(bank.substr(0, n), m, &err));
		CHECK_STR(err, "SPC bank is truncated");
		CHECK_STR(m.instruments[0].name, "keep");
	}

	Module m;
	std::string bad = bank;
	set_le32(bad, 0, -5);
	CHECK(!import_spc_bank(bad, m, &err));
	CHECK_STR(err, "SPC bank is malformed");
}

int main()
{
	test_wav_16bit_stereo();
	test_wav_8bit_mono();
	test_wav_24_32bit_mono();
	test_wav_errors();
	test_wav_round_trip();
	test_xm_song();
	test_xm_effects();
	test_xm_tempo();
	test_xm_fx_volume();
	test_xm_fx_pitch();
	test_xm_fx_other();
	test_xm_fx_flow();
	test_xm_envelopes();
	test_xm_reimport();
	test_xm_samples();
	test_xm_errors();
	test_midi_format0();
	test_midi_format1();
	test_midi_errors();
	test_ftm();
	test_ftm_track_names();
	test_ftm_errors();
	test_spc_bank();
	test_spc_bank_errors();

	if (failures) {
		std::printf("import_test: %d check(s) failed\n", failures);
		return 1;
	}
	std::printf("import_test: all checks passed\n");
	return 0;
}
