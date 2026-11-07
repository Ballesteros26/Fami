#include "config.h"

#include <cstdlib>
#include <cstring>
#include <sstream>

#include "gsm_io.h"

namespace gss {

bool Config::load(const std::string& path) { return read_file(path, text_); }

int Config::get_int(const char* name, int def) const
{
	const std::string param = std::string(name) + "=";
	std::istringstream in(text_);
	std::string line;
	int val = def;
	while (std::getline(in, line)) {
		const size_t at = line.find(param);
		if (at == std::string::npos) continue;
		// like sscanf(&line[strlen(param)], "%i"): parse after the key's length
		if (line.size() < param.size()) continue;
		const char* s = line.c_str() + param.size();
		char* end = nullptr;
		const long v = std::strtol(s, &end, 0);
		if (end != s) val = (int)v;
	}
	return val;
}

std::string Config::get_string(const char* name, const std::string& def) const
{
	const std::string param = std::string(name) + "=";
	std::istringstream in(text_);
	std::string line;
	while (std::getline(in, line)) {
		if (line.find(param) == std::string::npos || line.size() < param.size()) continue;
		std::string v = line.substr(param.size());
		while (!v.empty() && (v.back() == '\r' || v.back() == '\n')) v.pop_back();
		return v;  // the original returned the first match for strings
	}
	return def;
}

void AppConfig::read(const Config& c)
{
	sample_rate = c.get_int("WaveOutSampleRate", sample_rate);
	buffer_size = c.get_int("WaveOutBufferSize", buffer_size);
	buffer_count = c.get_int("WaveOutBufferCount", buffer_count);
	midi_input_device = c.get_int("MidiInputDeviceID", midi_input_device);
	page_step = c.get_int("SongPageStep", page_step);
	auto_step = c.get_int("SongAutoStep", auto_step);
	font_name = c.get_string("SongFontName", font_name);
	font_size = c.get_int("SongFontSize", font_size);

	if (sample_rate < 8000 || sample_rate > 192000) sample_rate = 44100;
	if (buffer_size < 64) buffer_size = 2048;
	if (page_step < 1) page_step = 16;
	if (auto_step < 0 || auto_step > 16) auto_step = 1;
	if (font_size < 6 || font_size > 72) font_size = 10;
}

}  // namespace gss
