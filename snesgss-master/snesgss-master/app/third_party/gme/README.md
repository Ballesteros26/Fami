# Game_Music_Emu 0.6.0 (SPC only)

Copied from the original editor's `legacy/src/gme`. Copyright (C) 2003-2006 Shay
Green, licensed under the GNU Lesser General Public License 2.1 or later
(see the headers of each file).

`blargg_config.h` limits the build to the SPC emulator (`GME_TYPE_LIST`).

Local changes:

- `gme.cpp`, `gme_identify_extension`: replaced a cast used as an lvalue
  (a Borland C++ extension) with a plain pointer assignment.
- `Spc_Emu.h`: added `spc()`, giving the editor the emulated SPC700's RAM
  and registers, to move a playing preview onto a newer compile.
