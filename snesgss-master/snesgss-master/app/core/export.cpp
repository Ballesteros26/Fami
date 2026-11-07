#include "export.h"

#include <filesystem>

#include "gsm_io.h"
#include "song.h"
#include "text_writer.h"

namespace gss {

namespace {

std::string upper(const std::string& s)
{
	std::string r = s;
	for (char& c : r)
		if (c >= 'a' && c <= 'z') c = (char)(c - 32);
	return r;
}

std::string with_header(const uint8_t* data, int size)
{
	std::string out;
	out.reserve(size + 2);
	out += (char)(size & 255);
	out += (char)((size >> 8) & 255);
	out.append((const char*)data, size);
	return out;
}

}  // namespace

std::string make_alias_name(const std::string& name)
{
	std::string alias = name;
	for (char& ch : alias) {
		int c = (signed char)ch;
		if (c >= 'a' && c <= 'z') c -= 32;
		if (!((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))) c = '_';
		ch = (char)c;
	}
	return alias;
}

namespace {

// After compiling, the original ModuleOpen() refreshed the instrument panel
// for instrument 1. Assigning the trackbars and edit boxes fired their
// OnChange handlers whenever the shown value changed from the defaults left
// by clearing the module. Each handler wrote the control's (clamped) value
// back into the instrument and flagged the samples for re-encoding, so the
// export that followed encoded every sample a second time, starting from
// the encoder state the first pass left behind.
//
// Returns whether the handlers would have fired.
bool emulate_instrument_panel_refresh(Instrument& ins)
{
	bool fired = false;

	auto trackbar = [&](int& field, int shown, int max) {
		const int pos = field < 0 ? 0 : (field > max ? max : field);
		if (pos != shown) {
			field = pos;
			fired = true;
		}
	};
	trackbar(ins.env_ar, 15, 15);
	trackbar(ins.env_dr, 7, 7);
	trackbar(ins.env_sl, 7, 7);
	trackbar(ins.env_sr, 0, 31);
	trackbar(ins.source_volume, 128, 255);

	if (ins.length != 0) {  // EditLength clamps to the source length
		if (ins.length > ins.source_length) ins.length = ins.source_length;
		fired = true;
	}
	if (ins.loop_start != 0) fired = true;
	if (ins.loop_end != 0) fired = true;

	return fired;
}

}  // namespace

void compile_after_open(Module& m, Compiler& c)
{
	c.invalidate_samples();
	c.spc_compile(m, m.songs[0], 0, false, false, -1);
	c.compile_all_songs(m);

	if (emulate_instrument_panel_refresh(m.instruments[0])) c.invalidate_samples();
}

bool export_all(Module& m, Compiler& c, std::vector<OutputFile>& files, std::string* error)
{
	files.clear();

	// driver code, samples and sound effects in a single binary
	Song temp = Song::zeroed();
	if (!c.spc_compile(m, temp, 0, false, true, -1, error)) return false;

	const int spc700_size = c.stats().mem_top - DRIVER_ADDRESS;
	files.push_back({"spc700.bin", with_header(c.aram() + DRIVER_ADDRESS, spc700_size)});

	// every song in a separate binary, loaded after the sound effects
	int song_id = 1;
	for (Song& s : m.songs) {
		if (s.effect) continue;
		if (song_is_empty(s)) continue;

		const int size = c.song_compile(s, 0, c.stats().mem_top, false);
		if (size < 0) {
			if (error) *error = "SPC700 memory overflow, too much music data in \"" + s.name + "\"";
			return false;
		}

		files.push_back({"music_" + std::to_string(song_id) + ".bin", with_header(c.aram() + c.stats().mem_top, size)});
		++song_id;
	}

	// WLA DX resource inclusion file
	{
		TextWriter w;
		w.printf(";this file generated with SNES GSS tool\n\n");

		song_id = 0;
		for (const Song& s : m.songs) {
			if (song_is_empty(s) || !s.effect) continue;
			w.printf(".define SFX_%s\t%i\n", make_alias_name(s.name).c_str(), song_id);
			++song_id;
		}
		w.printf("\n");

		song_id = 0;
		for (const Song& s : m.songs) {
			if (song_is_empty(s) || s.effect) continue;
			w.printf(".define MUS_%s\t%i\n", make_alias_name(s.name).c_str(), song_id);
			++song_id;
		}
		w.printf("\n");

		w.printf(".section \".roDataSoundCode1\" superfree\n");
		w.printf("spc700_code_1:\t.incbin \"spc700.bin\" skip 0 read %i\n", spc700_size < 32768 ? spc700_size : 32768);
		if (spc700_size <= 32768) w.printf("spc700_code_2:\n");
		w.printf(".ends\n\n");

		if (spc700_size > 32768) {
			w.printf(".section \".roDataSoundCode2\" superfree\n");
			w.printf("spc700_code_2:\t.incbin \"spc700.bin\" skip 32768\n");
			w.printf(".ends\n\n");
		}

		song_id = 1;
		for (const Song& s : m.songs) {
			if (s.effect || song_is_empty(s)) continue;
			w.printf(".section \".roDataMusic%i\" superfree\n", song_id);
			w.printf("music_%i_data:\t.incbin \"music_%i.bin\"\n", song_id, song_id);
			w.printf(".ends\n\n");
			++song_id;
		}

		files.push_back({"sounds.asm", w.take()});
	}

	// C header with externs and metadata
	{
		int sounds_all = 0, songs_all = 0;
		for (const Song& s : m.songs) {
			if (song_is_empty(s)) continue;
			if (s.effect) ++sounds_all;
			else ++songs_all;
		}

		TextWriter w;
		w.printf("//this file generated with SNES GSS tool\n\n");
		w.printf("#define SOUND_EFFECTS_ALL\t%i\n\n", sounds_all);
		w.printf("#define MUSIC_ALL\t%i\n\n", songs_all);

		auto names = [&](bool effects, int all, const char* prefix, const char* alias_title, const char* name_title,
		                 const char* array) {
			w.printf("%s", alias_title);
			w.printf("enum {\n");
			int id = 0;
			for (const Song& s : m.songs) {
				if (song_is_empty(s) || s.effect != effects) continue;
				w.printf("\t%s_%s=%i", prefix, make_alias_name(s.name).c_str(), id);
				if (id < all - 1) w.printf(",\n");
				++id;
			}
			w.printf("\n};\n\n");

			w.printf("%s", name_title);
			w.printf("const char* const %s={\n", array);
			id = 0;
			for (const Song& s : m.songs) {
				if (song_is_empty(s) || s.effect != effects) continue;
				w.printf("\t\"%s\"", upper(s.name).c_str());
				if (id < all - 1) w.printf(",\t//%i\n", id);
				++id;
			}
			w.printf("\t//%i\n};\n\n", id - 1);
		};

		if (sounds_all)
			names(true, sounds_all, "SFX", "//sound effect aliases\n\n", "//sound effect names\n\n",
			      "soundEffectsNames[SOUND_EFFECTS_ALL]");
		if (songs_all)
			names(false, songs_all, "MUS", "//music effect aliases\n\n", "//music names\n\n", "musicNames[MUSIC_ALL]");

		w.printf("extern const unsigned char spc700_code_1[];\n");
		w.printf("extern const unsigned char spc700_code_2[];\n");

		song_id = 1;
		for (const Song& s : m.songs) {
			if (song_is_empty(s) || s.effect) continue;
			w.printf("extern const unsigned char music_%i_data[];\n", song_id);
			++song_id;
		}
		w.printf("\n");

		w.printf("const unsigned char* const musicData[MUSIC_ALL]={\n");
		song_id = 1;
		for (const Song& s : m.songs) {
			if (song_is_empty(s) || s.effect) continue;
			w.printf("\tmusic_%i_data", song_id);
			if (song_id < songs_all) w.printf(",\n");
			++song_id;
		}
		w.printf("\n};\n");

		files.push_back({"sounds.h", w.take()});
	}

	return true;
}

OutputFile export_spc(const Compiler& c, const std::string& name)
{
	return {name, std::string((const char*)c.spc_image(), SPC_FILE_SIZE)};
}

bool write_output_files(const std::string& dir, const std::vector<OutputFile>& files, std::string* error)
{
	namespace fs = std::filesystem;
	std::error_code ec;
	const fs::path base = dir.empty() ? fs::path(".") : fs::u8path(dir);
	fs::create_directories(base, ec);

	for (const OutputFile& f : files) {
		const fs::path p = base / f.name;
		if (!write_file(p.u8string(), f.data)) {
			if (error) *error = "Can't write " + p.u8string();
			return false;
		}
	}
	return true;
}

}  // namespace gss
