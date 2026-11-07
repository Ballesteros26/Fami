# Native Windows x64 build

The supported native Windows build uses official LDC 1.42.0 targeting the
Microsoft x64 ABI, Microsoft C++ Build Tools and Windows SDK, GNU Make, ACME,
and SDL2 2.32.10 development/runtime files.

Run from the project root in an MSYS2 UCRT64 shell whose Microsoft x64
developer environment is initialised. Required tools must be discoverable
through the active environment. No Git checkout or network access is needed.

Commands:

```sh
make -f Makefile.win clean
make -f Makefile.win test
make -f Makefile.win gui
make -f Makefile.win ct2util
make -f Makefile.win verify
make -f Makefile.win verify-privacy
make -f Makefile.win toolchain-info
```

`all` and `gui` produce the normal GUI-subsystem `ccutter.exe` application.
`ct2util.exe` is a console utility, and the permanent tests are console
programs. No maintained console variant of the CheeseCutter application is
built.

Generated objects, staged official LDC imports, resources, executables,
runtime files, tests, and public-safe build information remain under
`build/windows/`. `clean` removes only that generated root.

Official LDC interface files are verified and staged under a generated
project-relative import root. D compilation receives only that neutral
relative import path. The installed compiler and runtime libraries are not
copied into the project.

Windows links use Microsoft `/Brepro`. The GUI uses `/SUBSYSTEM:WINDOWS` and
`/ENTRY:wmainCRTStartup`; `ct2util.exe` and the tests retain normal console
startup. Assertions, contracts, bounds checks, exception behaviour, and the
accepted optimisation policy remain unchanged.

The SDL2 runtime is verified before staging. Its exports produce a genuine
deterministic MSCOFF import library using Microsoft `lib.exe`; a GNU import
archive is never renamed.

These commands create verification builds only. They do not create a public
release package or claim public release readiness. The GUI must still pass the
documented user verification step.
