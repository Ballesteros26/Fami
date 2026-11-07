// File > Export: spc700.bin, music_N.bin, sounds.asm and sounds.h.
#pragma once

#include <string>
#include <vector>

#include "compiler.h"
#include "model.h"

namespace gss {

struct OutputFile {
	std::string name;
	std::string data;
};

// What the original editor compiled right after opening a project. Exports
// are only byte-identical to the original when they follow this on a fresh
// Compiler, as the command line export did.
void compile_after_open(Module& m, Compiler& c);

// Compiles everything and returns the export files. Returns false and sets
// *error if the data does not fit in SPC700 memory.
bool export_all(Module& m, Compiler& c, std::vector<OutputFile>& files, std::string* error = nullptr);

// The .spc image of the last spc_compile().
OutputFile export_spc(const Compiler& c, const std::string& name);

// Writes files into dir, creating it if needed.
bool write_output_files(const std::string& dir, const std::vector<OutputFile>& files, std::string* error = nullptr);

// "My Song 2" -> "MY_SONG_2", used for the SFX_/MUS_ aliases.
std::string make_alias_name(const std::string& name);

}  // namespace gss
