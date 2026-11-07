# Building SNES GSS

The editor builds on Windows, Linux and macOS with CMake 3.16+ and a C++17
compiler. SDL3 and Dear ImGui are downloaded at configure time (pinned
versions, see `app/CMakeLists.txt`). The CMake project lives in `app/`;
run the commands below from the repository root. Build output goes in
`app/build/`, which is ignored by git.

```sh
cmake -S app -B app/build -DCMAKE_BUILD_TYPE=Release
cmake --build app/build --parallel
ctest --test-dir app/build --output-on-failure
```

On Linux, SDL needs the usual development packages (ALSA/PulseAudio, X11
and/or Wayland); the CI workflow lists them for Ubuntu.

## Windows

Cross-compile from Linux with MinGW-w64 (`g++-mingw-w64-x86-64-posix` on
Debian/Ubuntu; the posix thread model is needed for `std::mutex`). The
toolchain file must be given as an absolute path:

```sh
cmake -S app -B app/build-windows -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE="$PWD/app/cmake/mingw-w64.cmake"
cmake --build app/build-windows --parallel
ctest --test-dir app/build-windows --output-on-failure   # runs under Wine
```

The result, `app/build-windows/snesgss.exe`, links SDL and the MinGW runtime
statically and needs only DLLs that ship with Windows. It carries the
original editor's icon. A native MSVC build with the commands at the top
also works. The editor is a GUI program; in command line mode it writes to
the console it was started from.

## macOS

Build natively on a Mac (Xcode command line tools and CMake), with the
commands at the top. SDL is linked statically, so `app/build/snesgss.app`
needs nothing but macOS. `-DCMAKE_OSX_ARCHITECTURES=arm64` or `x86_64` picks
the architecture, and with it the oldest macOS the app runs on: 11 for arm64,
10.15 (Catalina) for x86_64. `-DCMAKE_OSX_DEPLOYMENT_TARGET` overrides that.
The app is unsigned: right-click it and
choose Open the first time, or run
`xattr -dr com.apple.quarantine snesgss.app`. Command line mode runs the
binary inside the bundle: `snesgss.app/Contents/MacOS/snesgss project.gsm -e`.

## Continuous integration

`.github/workflows/ci.yml` builds and tests Linux, Windows (cross-compiled,
tested under Wine) and macOS (arm64 and x86_64, natively), checks that the
Windows and macOS builds need only system libraries, and uploads each as an
artifact. Pushing a `v*` tag publishes them as a GitHub Release.

Options:

| Option | Default | |
|---|---|---|
| `SNESGSS_BUILD_APP` | ON | the SDL3 + Dear ImGui editor (`snesgss`) |
| `SNESGSS_BUILD_TESTS` | ON | importer and editor tests; golden export and round trip tests also need the app |
| `SNESGSS_USE_SYSTEM_SDL` | OFF | use an installed SDL3 instead of building it |
| `SNESGSS_SDL_DIR`, `SNESGSS_IMGUI_DIR` | | local source trees, for offline builds |

## Programs

- `snesgss [project.gsm]` - the editor.
- `snesgss project.gsm -e [dir]` - export without opening a window, as the
  original `snesgss.exe` did.
- `snesgss project.gsm -spc N file.spc` / `-wav N seconds file.wav` - write
  song N as an SPC file, or render it to a WAV file.
- `snesgss project.gsm -resave file.gsm` - load and save again.

Command line modes don't start SDL video or audio, so they run on servers
and in CI.

## Layout

| Directory | |
|---|---|
| `app/` | the SDL3 + Dear ImGui editor and its command line modes |
| `app/core/` | project model, `.gsm` I/O, BRR encoder, compiler, export, importers, song editor operations. No UI dependencies. |
| `app/audio/` | SPC playback through Game_Music_Emu |
| `app/third_party/gme/` | Game_Music_Emu 0.6.0, SPC only (LGPL 2.1) |
| `app/tests/` | tests; `app/tests/golden/` holds exports made by the original `snesgss.exe` |
| `legacy/` | the original editor, kept for reference: `snesgss.exe` (v1.43), its `snesgss.cfg`, the 2014 release archive `snesgss.zip`, and its Borland C++ Builder source in `legacy/src/` |

## Golden exports

Exports must stay byte-identical to the original editor's. `app/tests/golden/`
holds what `snesgss.exe project.gsm -e` produced for each test project;
regenerate them with `tools/make_golden.sh` (needs Wine). The
`app/tests/fixtures/coverage.gsm` project, built by
`tools/make_coverage_fixture.py`, exercises encoder paths the other projects
don't use (EQ, loop unrolling, every resampling mode).

## SPC700 driver

`app/core/spc700.h` is generated from the assembled `snes/spc700.asm`:

```sh
bass -o spc700.bin snes/spc700.asm
python3 tools/bin2h.py spc700.bin app/core/spc700.h
```

The driver size is no longer fixed; the compiler places the sample
directory after the driver, whatever its length.
