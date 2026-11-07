#include "gsm_io.h"

#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <vector>

#include "song.h"
#include "text_writer.h"

namespace gss {

namespace {

const char* const NOTE_NAMES[12] = {"C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"};

// Room after the text so the parser can over-read, as the original did,
// without leaving the buffer. Reads past the end see zero bytes.
constexpr size_t PAD = 1024;

// The original parser: a tag search that starts where the previous search
// matched and wraps around the whole text. Characters are compared as
// signed chars, as Borland C++ did, so bytes >= 0x80 count as control
// characters and end a value.
class GssParser {
public:
	GssParser(const char* data, size_t size) : buf_(size + PAD, 0), size_((int)size)
	{
		if (size) std::memcpy(buf_.data(), data, size);
	}

	const char* text() const { return buf_.data(); }
	int size() const { return size_; }

	// Position after the tag, or -1.
	int find_tag(const std::string& tag) { return seek(tag) ? ptr_ + (int)tag.size() : -1; }

	std::string load_str(const std::string& tag)
	{
		std::string str;
		if (!seek(tag)) return str;
		const signed char* t = (const signed char*)&buf_[ptr_ + tag.size()];
		while (*t >= 32 && str.size() < 1023) str += (char)*t++;
		return str;
	}

	int load_int(const std::string& tag)
	{
		if (!seek(tag)) return 0;
		const char* t = &buf_[ptr_ + tag.size()];
		int n = 0, sign = 1;
		for (;; ++t) {
			char c = *t;
			if (c == '-') {
				sign = -1;
				continue;
			}
			if (c < '0' || c > '9') break;
			n = n * 10 + (c - '0');
		}
		return n * sign;
	}

	// Empty if the tag is missing or has no data.
	std::vector<int16_t> load_short_data(const std::string& tag)
	{
		std::vector<int16_t> data;
		if (!seek(tag)) return data;
		const signed char* t = (const signed char*)&buf_[ptr_ + tag.size()];
		while (*t > 32) {
			int n = hex(t[0]) << 12;
			n |= hex(t[1]) << 8;
			n |= hex(t[2]) << 4;
			n |= hex(t[3]);
			t += 4;
			data.push_back((int16_t)(uint16_t)n);
		}
		return data;
	}

private:
	static int hex(signed char n)
	{
		if (n >= '0' && n <= '9') return n - '0';
		if (n >= 'a' && n <= 'f') return n - 'a' + 10;
		if (n >= 'A' && n <= 'F') return n - 'A' + 10;
		return -1;
	}

	bool seek(const std::string& tag)
	{
		const size_t len = tag.size();
		for (int size = size_; size; --size) {
			if (!std::memcmp(&buf_[ptr_], tag.data(), len)) return true;
			if (++ptr_ >= size_) ptr_ = 0;
		}
		return false;
	}

	std::vector<char> buf_;
	int size_;
	int ptr_ = 0;
};

int parse_num_len(const char* text, int len, int def)
{
	int num = 0;
	while (len) {
		int c = *text++;
		if (c == '.') return def;
		if (!(c >= '0' && c <= '9')) return -1;
		num = num * 10 + (c - '0');
		--len;
	}
	return num;
}

void parse_instrument_data(GssParser& p, int id, Instrument& ins)
{
	const std::string n = "Instrument" + std::to_string(id);

	ins.name = p.load_str(n + "Name=");

	ins.env_ar = p.load_int(n + "EnvAR=");
	ins.env_dr = p.load_int(n + "EnvDR=");
	ins.env_sl = p.load_int(n + "EnvSL=");
	ins.env_sr = p.load_int(n + "EnvSR=");

	ins.length = p.load_int(n + "Length=");

	ins.loop_start = p.load_int(n + "LoopStart=");
	ins.loop_end = p.load_int(n + "LoopEnd=");
	ins.loop_enable = p.load_int(n + "LoopEnable=") != 0;

	ins.source_length = p.load_int(n + "SourceLength=");
	ins.source_rate = p.load_int(n + "SourceRate=");
	ins.source_volume = p.load_int(n + "SourceVolume=");

	ins.wav_loop_start = p.load_int(n + "WavLoopStart=");
	ins.wav_loop_end = p.load_int(n + "WavLoopEnd=");

	ins.eq_low = p.load_int(n + "EQLow=");
	ins.eq_mid = p.load_int(n + "EQMid=");
	ins.eq_high = p.load_int(n + "EQHigh=");
	ins.resample_type = p.load_int(n + "ResampleType=");
	ins.downsample_factor = p.load_int(n + "DownsampleFactor=");
	ins.ramp_enable = p.load_int(n + "RampEnable=") != 0;
	ins.loop_unroll = p.load_int(n + "LoopUnroll=") != 0;

	ins.source = p.load_short_data(n + "SourceData=");

	// Keep the invariant that a present source covers every length field,
	// so nothing downstream reads past it.
	if (!ins.source.empty()) {
		size_t need = 16;
		if (ins.source_length > 0 && (size_t)ins.source_length > need) need = ins.source_length;
		if (ins.length > 0 && (size_t)ins.length > need) need = ins.length;
		if (ins.source.size() < need) ins.source.resize(need, 0);
	}
}

void write_instrument_data(TextWriter& w, int id, const Instrument& ins)
{
	w.printf("Instrument%iName=", id);
	w.str(ins.name);
	w.printf("\n");

	w.printf("Instrument%iEnvAR=%i\n", id, ins.env_ar);
	w.printf("Instrument%iEnvDR=%i\n", id, ins.env_dr);
	w.printf("Instrument%iEnvSL=%i\n", id, ins.env_sl);
	w.printf("Instrument%iEnvSR=%i\n", id, ins.env_sr);

	w.printf("Instrument%iLength=%i\n", id, ins.length);

	w.printf("Instrument%iLoopStart=%i\n", id, ins.loop_start);
	w.printf("Instrument%iLoopEnd=%i\n", id, ins.loop_end);
	w.printf("Instrument%iLoopEnable=%i\n", id, ins.loop_enable ? 1 : 0);

	w.printf("Instrument%iSourceLength=%i\n", id, ins.source_length);
	w.printf("Instrument%iSourceRate=%i\n", id, ins.source_rate);
	w.printf("Instrument%iSourceVolume=%i\n", id, ins.source_volume);

	w.printf("Instrument%iWavLoopStart=%i\n", id, ins.wav_loop_start);
	w.printf("Instrument%iWavLoopEnd=%i\n", id, ins.wav_loop_end);

	w.printf("Instrument%iEQLow=%i\n", id, ins.eq_low);
	w.printf("Instrument%iEQMid=%i\n", id, ins.eq_mid);
	w.printf("Instrument%iEQHigh=%i\n", id, ins.eq_high);
	w.printf("Instrument%iResampleType=%i\n", id, ins.resample_type);
	w.printf("Instrument%iDownsampleFactor=%i\n", id, ins.downsample_factor);
	w.printf("Instrument%iRampEnable=%i\n", id, ins.ramp_enable ? 1 : 0);
	w.printf("Instrument%iLoopUnroll=%i\n", id, ins.loop_unroll ? 1 : 0);

	w.printf("Instrument%iSourceData=", id);

	if (ins.has_source()) {
		static const char digits[] = "0123456789abcdef";
		std::string hex;
		const int n = ins.source_length < (int)ins.source.size() ? ins.source_length : (int)ins.source.size();
		hex.reserve(n > 0 ? n * 4 : 0);
		for (int i = 0; i < n; ++i) {
			const uint16_t v = (uint16_t)ins.source[i];
			hex += digits[v >> 12];
			hex += digits[(v >> 8) & 15];
			hex += digits[(v >> 4) & 15];
			hex += digits[v & 15];
		}
		w.str(hex);
	}

	w.printf("\n\n");
}

}  // namespace

bool parse_module(const char* data, size_t size, Module& out)
{
	GssParser p(data, size);
	const char* text = p.text();

	if (p.find_tag(PROJECT_SIGNATURE) < 0) return false;

	const bool ex_vol = p.find_tag(EX_VOL_SIGNATURE) >= 0;

	Module m;

	for (int ins = 0; ins < MAX_INSTRUMENTS; ++ins) parse_instrument_data(p, ins, m.instruments[ins]);

	for (int song = 0; song < MAX_SONGS; ++song) {
		const std::string n = "Song" + std::to_string(song);
		Song& s = m.songs[song];
		s.name = p.load_str(n + "Name=");
		s.length = p.load_int(n + "Length=");
		s.loop_start = p.load_int(n + "LoopStart=");
		s.measure = p.load_int(n + "Measure=");
		s.effect = p.load_int(n + "Effect=") != 0;
	}

	for (int song = 0; song < MAX_SONGS; ++song) {
		int ptr = p.find_tag("[Song" + std::to_string(song) + "]");
		if (ptr < 0) continue;

		while (ptr < (int)size)
			if (text[ptr++] == '\n') break;

		Song& s = m.songs[song];

		while (true) {
			const int row = parse_num_len(text + ptr, 4, 0);
			if (row < 0) break;

			Row& r = s.row_mut(row);
			r.marker = text[ptr + 4] != ' ';
			r.speed = parse_num_len(text + ptr + 5, 2, 0);
			ptr += 7;

			for (int chn = 0; chn < CHANNELS; ++chn) {
				NoteField& nf = r.chn[chn];

				if (text[ptr] != '.') {
					if (text[ptr] == '-') {
						nf.note = 1;
					} else {
						int note;
						switch (text[ptr]) {
						case 'C': note = 0; break;
						case 'D': note = 2; break;
						case 'E': note = 4; break;
						case 'F': note = 5; break;
						case 'G': note = 7; break;
						case 'A': note = 9; break;
						case 'B': note = 11; break;
						default: note = -1;
						}
						if (text[ptr + 1] == '#') ++note;
						nf.note = (uint8_t)(note + (text[ptr + 2] - '0') * 12 + 2);
					}
				}
				ptr += 3;

				nf.instrument = (uint8_t)parse_num_len(text + ptr, 2, 0);
				ptr += 2;

				if (ex_vol) {
					nf.volume = (uint8_t)parse_num_len(text + ptr, 2, 255);
					ptr += 2;
				}

				nf.effect = (text[ptr] == '.') ? 0 : (uint8_t)text[ptr];
				ptr += 1;

				nf.value = (uint8_t)parse_num_len(text + ptr, 2, 255);

				if (!ex_vol) {
					if (nf.effect == 'V') {  // old volume command becomes the volume column
						nf.volume = nf.value;
						nf.effect = 0;
						nf.value = 255;
					}
					if (nf.effect == 'M') nf.effect = 'V';  // modulation was renamed vibrato
				}
				ptr += 2;
			}

			std::string name;
			while (ptr < (int)size) {
				if ((signed char)text[ptr] < ' ') break;
				name += text[ptr];
				++ptr;
			}
			r.name = name;

			while (ptr < (int)size) {
				if ((signed char)text[ptr] >= ' ') break;
				++ptr;
			}
		}
	}

	out = std::move(m);
	return true;
}

std::string format_module(const Module& m)
{
	TextWriter w;

	w.printf("%s\n\n", PROJECT_SIGNATURE);
	w.printf("%s\n\n", EX_VOL_SIGNATURE);

	for (int ins = 0; ins < MAX_INSTRUMENTS; ++ins) write_instrument_data(w, ins, m.instruments[ins]);

	for (int song = 0; song < MAX_SONGS; ++song) {
		const Song& s = m.songs[song];
		w.printf("Song%iName=", song);
		w.str(s.name);
		w.printf("\n");
		w.printf("Song%iLength=%i\n", song, s.length);
		w.printf("Song%iLoopStart=%i\n", song, s.loop_start);
		w.printf("Song%iMeasure=%i\n\n", song, s.measure);
		w.printf("Song%iEffect=%i\n\n", song, s.effect ? 1 : 0);
	}

	for (int song = 0; song < MAX_SONGS; ++song) {
		const Song& s = m.songs[song];
		w.printf("[Song%i]\n", song);

		for (int row = 0; s.allocated() && row < MAX_ROWS; ++row) {
			if (row_is_empty(s, row, true)) continue;

			const Row& r = s.row(row);
			w.printf("%4.4i%c", row, r.marker ? '*' : ' ');

			if (r.speed) w.printf("%2.2i", r.speed);
			else w.printf("..");

			for (const NoteField& n : r.chn) {
				switch (n.note) {
				case 0: w.printf("..."); break;
				case 1: w.printf("---"); break;
				default: w.printf("%s%i", NOTE_NAMES[(n.note - 2) % 12], (n.note - 2) / 12);
				}

				if (n.instrument) w.printf("%2.2i", n.instrument);
				else w.printf("..");

				if (n.volume == 255) w.printf("..");
				else w.printf("%2.2i", n.volume);

				w.printf("%c", n.effect ? n.effect : '.');

				if (n.value == 255) w.printf("..");
				else w.printf("%2.2i", n.value);
			}

			w.str(r.name);
			w.printf("\n");
		}

		w.printf("\n");
	}

	return w.take();
}

bool parse_instrument(const char* data, size_t size, Instrument& ins)
{
	GssParser p(data, size);
	if (p.find_tag(INSTRUMENT_SIGNATURE) < 0) return false;
	Instrument parsed;
	parse_instrument_data(p, 0, parsed);
	ins = std::move(parsed);
	return true;
}

std::string format_instrument(const Instrument& ins)
{
	TextWriter w;
	w.printf("%s\n\n", INSTRUMENT_SIGNATURE);
	write_instrument_data(w, 0, ins);
	return w.take();
}

bool read_file(const std::string& path, std::string& out)
{
	std::ifstream f(std::filesystem::u8path(path), std::ios::binary);
	if (!f) return false;
	out.assign(std::istreambuf_iterator<char>(f), std::istreambuf_iterator<char>());
	return !f.bad();
}

bool write_file(const std::string& path, const std::string& data)
{
	std::ofstream f(std::filesystem::u8path(path), std::ios::binary | std::ios::trunc);
	if (!f) return false;
	f.write(data.data(), (std::streamsize)data.size());
	f.close();
	return !f.fail();
}

bool load_module(const std::string& path, Module& m)
{
	std::string text;
	return read_file(path, text) && parse_module(text.data(), text.size(), m);
}

bool save_module(const std::string& path, const Module& m) { return write_file(path, format_module(m)); }

bool load_instrument(const std::string& path, Instrument& ins)
{
	std::string text;
	return read_file(path, text) && parse_instrument(text.data(), text.size(), ins);
}

bool save_instrument(const std::string& path, const Instrument& ins) { return write_file(path, format_instrument(ins)); }

}  // namespace gss
