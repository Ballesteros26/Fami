// Command line mode: work on a project without opening a window.
//
//   snesgss project.gsm -e [dir]                         export, like the original snesgss.exe
//   snesgss project.gsm -spc <song number> <file.spc>    write a song as an .spc file
//   snesgss project.gsm -wav <song> <seconds> <file.wav> render a song to a .wav file
//   snesgss project.gsm -resave <file.gsm>               load and save again
#pragma once

namespace gss {

// True when the arguments ask for command line mode rather than the editor.
bool is_command_line(int argc, char** argv);

// Runs the command; returns the process exit code.
int run_command_line(int argc, char** argv);

}  // namespace gss
