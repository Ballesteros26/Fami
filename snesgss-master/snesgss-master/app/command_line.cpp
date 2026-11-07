#include "command_line.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <string>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#endif

#include "compiler.h"
#include "export.h"
#include "gsm_io.h"
#include "spc_player.h"

namespace gss {

namespace {

int usage()
{
	std::fprintf(stderr,
	             "usage: snesgss [project.gsm]                                   open the editor\n"
	             "       snesgss project.gsm -e [export dir]                     export\n"
	             "       snesgss project.gsm -spc <song number> <file.spc>       write a song as an SPC file\n"
	             "       snesgss project.gsm -wav <song> <seconds> <file.wav>    render a song to a WAV file\n"
	             "       snesgss project.gsm -resave <file.gsm>                  load and save again\n");
	return 2;
}

#ifdef _WIN32
// The editor is a GUI program on Windows; reuse the console it was started
// from, if any, so messages reach it.
void attach_console()
{
	if (AttachConsole(ATTACH_PARENT_PROCESS)) {
		FILE* f;
		freopen_s(&f, "CONOUT$", "w", stdout);
		freopen_s(&f, "CONOUT$", "w", stderr);
	}
}
#endif

}  // namespace

bool is_command_line(int argc, char** argv)
{
	if (argc > 1 && (std::strcmp(argv[1], "-h") == 0 || std::strcmp(argv[1], "--help") == 0)) return true;
	return argc > 2 && argv[2][0] == '-';
}

int run_command_line(int argc, char** argv)
{
#ifdef _WIN32
	attach_console();
#endif

	if (argc < 3) return usage();


	const std::string path = argv[1];
	const std::string cmd = argv[2];

	static Module module;  // large, keep it off the stack
	if (!load_module(path, module)) {
		std::fprintf(stderr, "%s: can't open module\n", path.c_str());
		return 1;
	}

	Compiler compiler;
	std::string error;

	if (cmd == "-e" || cmd == "-E") {
		std::string dir;
		if (argc > 3) dir = argv[3];
		else dir = std::filesystem::u8path(path).parent_path().u8string();

		compile_after_open(module, compiler);

		std::vector<OutputFile> files;
		if (!export_all(module, compiler, files, &error) || !write_output_files(dir, files, &error)) {
			std::fprintf(stderr, "%s: %s\n", path.c_str(), error.c_str());
			return 1;
		}
		return 0;
	}

	if (cmd == "-spc" && argc > 4) {
		const int song = std::atoi(argv[3]) - 1;
		if (song < 0 || song >= MAX_SONGS) return usage();

		compile_after_open(module, compiler);
		if (!compiler.spc_compile(module, module.songs[song], 0, false, false, -1, &error)) {
			std::fprintf(stderr, "%s: %s\n", path.c_str(), error.c_str());
			return 1;
		}
		const OutputFile f = export_spc(compiler, "");
		return write_file(argv[4], f.data) ? 0 : 1;
	}

	if (cmd == "-wav" && argc > 5) {
		const int song = std::atoi(argv[3]) - 1;
		const int seconds = std::atoi(argv[4]);
		if (song < 0 || song >= MAX_SONGS || seconds <= 0) return usage();

		compile_after_open(module, compiler);
		if (!compiler.spc_compile(module, module.songs[song], 0, false, false, -1, &error)) {
			std::fprintf(stderr, "%s: %s\n", path.c_str(), error.c_str());
			return 1;
		}

		const int rate = 44100;
		SpcPlayer player(rate);
		if (!player.play(compiler.spc_image(), SPC_FILE_SIZE)) {
			std::fprintf(stderr, "%s: the emulator rejected the SPC image\n", path.c_str());
			return 1;
		}

		std::vector<int16_t> pcm((size_t)rate * seconds * 2);
		for (size_t pos = 0; pos < pcm.size(); pos += 2048) {
			const size_t n = pcm.size() - pos < 2048 ? pcm.size() - pos : 2048;
			player.render(&pcm[pos], (int)n / 2);
		}

		std::string wav = "RIFF";
		auto u32 = [&](uint32_t v) { for (int i = 0; i < 4; ++i) wav += (char)((v >> (8 * i)) & 255); };
		auto u16 = [&](uint16_t v) { wav += (char)(v & 255); wav += (char)(v >> 8); };
		const uint32_t bytes = (uint32_t)(pcm.size() * 2);
		u32(36 + bytes);
		wav += "WAVEfmt ";
		u32(16); u16(1); u16(2); u32(rate); u32(rate * 4); u16(4); u16(16);
		wav += "data";
		u32(bytes);
		for (int16_t v : pcm) u16((uint16_t)v);
		return write_file(argv[5], wav) ? 0 : 1;
	}

	if (cmd == "-resave" && argc > 3) return save_module(argv[3], module) ? 0 : 1;

	return usage();
}

}  // namespace gss
