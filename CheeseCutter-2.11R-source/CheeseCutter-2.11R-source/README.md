# CheeseCutter 2.11R — Hypercut

CheeseCutter is a cross-platform C64 music editor for composing SID music with
three voices, Sequences, Instruments and programmable Wave, Pulse and Filter
tables.

Hypercut is a major desktop editing, arrangement, audio, Help and export
update. The embedded C64 music driver remains unchanged. See [NEWS](NEWS) for
the complete CheeseCutter 2.11R change list.

## Main capabilities

- An interactive Track Overview combines a song Timeline with three
  colour-coded voice lanes.
- Mouse and keyboard range editing is available in the F6 pattern editor,
  Instruments and program tables.
- Instrument pointers provide direct navigation to Wave, Pulse and Filter
  table positions.
- The GUI file browser loads and saves Songs and Instruments and exports SID
  and PRG files.
- A three-voice oscilloscope shares one mute state with the keyboard voice
  controls.
- Runtime audio settings include sample-rate, buffer, interpolation and
  PAL/NTSC session controls.
- Contextual three-line Quick Help and topic-based F12 Help cover the active
  editor context.
- Four interface colour themes and platform-specific desktop application icons
  are included.

## Packages and getting started

The CheeseCutter 2.11R binary release provides:

- Windows x64: extract the Windows package and run `ccutter.exe`.
- macOS arm64: extract the macOS package and open `CheeseCutter.app`.

The source archive is distributed separately. Linux source-build documentation
is included, but no Linux binary package is provided for this release.

## Basic editor navigation

- Use the mouse to focus fields, tables, Timeline positions and Sequence data.
- F5 opens the Track editor.
- F6 opens the Sequence editor.
- F7 opens the Instrument editor.
- F12 opens detailed Help for the current context.
- The bottom controls provide Fullscreen, themes, Load, Save, Keyjam, Audio
  Settings and contextual Help.

## Building from source

General dependencies and build guidance are in [INSTALL](INSTALL).

- macOS: [Makefile.mac](Makefile.mac)
- Windows: [arch/Windows/BUILD.md](arch/Windows/BUILD.md)
- Linux source build: [release/linux/BUILD.md](release/linux/BUILD.md)

The maintained source includes ACME Crossassembler 0.93.

## Licence

CheeseCutter is licensed under the GNU General Public License. See
[LICENSE.md](LICENSE.md) for details.

Upstream project:
https://github.com/theyamo/CheeseCutter

## Credits

Original CheeseCutter programming by abaddon, 2009-2017.

Mac OS X and D2 port by Ruk, 2013.

reSID engine by Dag Lem and A. Lankila.

Parts of the reSID interface (`sid.cpp`) by Cadaver / CovertBitops.

ACME Crossassembler by Marco Baye.

SDL by the SDL team.

Derelict:
http://www.dsource.org/projects/derelict

Special thanks to Vent/Triad, Blackspawn, Mr Ammo, Scarzix/Offence,
SuperNoise, Wisdom/Crescent and the forgotten ones.
