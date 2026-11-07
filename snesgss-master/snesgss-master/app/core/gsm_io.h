// .gsm project and .gsi instrument files.
//
// Both are line-based text written with CRLF line endings on every platform,
// matching what the original Windows editor produced. Loading accepts CRLF
// or LF.
#pragma once

#include <cstddef>
#include <string>

#include "model.h"

namespace gss {

constexpr const char* PROJECT_SIGNATURE = "[SNESGSS Module]";
constexpr const char* INSTRUMENT_SIGNATURE = "[SNESGSS Instrument]";
constexpr const char* EX_VOL_SIGNATURE = "[EX VOL]";

// Replaces m entirely. Returns false (and leaves m untouched) if the data is
// not a SNES GSS project.
bool parse_module(const char* data, size_t size, Module& m);
std::string format_module(const Module& m);

bool parse_instrument(const char* data, size_t size, Instrument& ins);
std::string format_instrument(const Instrument& ins);

bool read_file(const std::string& path, std::string& out);
bool write_file(const std::string& path, const std::string& data);

bool load_module(const std::string& path, Module& m);
bool save_module(const std::string& path, const Module& m);
bool load_instrument(const std::string& path, Instrument& ins);
bool save_instrument(const std::string& path, const Instrument& ins);

}  // namespace gss
