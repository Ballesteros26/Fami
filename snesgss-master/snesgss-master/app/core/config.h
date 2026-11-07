// snesgss.cfg reader, same format and rules as the original: "Key=value"
// lines, the key is found anywhere in a line, the last match wins, and
// integers accept C prefixes (0x.., 0..).
#pragma once

#include <string>

namespace gss {

class Config {
public:
	bool load(const std::string& path);  // false if the file can't be read
	int get_int(const char* name, int def) const;
	std::string get_string(const char* name, const std::string& def) const;

private:
	std::string text_;
};

struct AppConfig {
	int sample_rate = 44100;
	int buffer_size = 2048;
	int buffer_count = 8;
	int midi_input_device = 0;
	int page_step = 16;
	int auto_step = 1;
	std::string font_name = "Courier New";
	int font_size = 10;

	void read(const Config& c);
};

}  // namespace gss
