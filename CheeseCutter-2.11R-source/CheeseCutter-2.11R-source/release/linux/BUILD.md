# Building CheeseCutter on Linux

The generic `Makefile` owns Linux builds. Linux package names vary by
distribution, so install the equivalent of these prerequisites:

- LDC (`ldc2`);
- C and C++ compilers;
- GNU Make;
- ACME-compatible assembler available as `acme`;
- SDL2 development headers and libraries;
- Python 3 when generating desktop icons.

## Build

Use a clean source tree and keep generated output out of the canonical source
archive. From the source directory:

```sh
make clean
make ccutter
make ct2util
```

`make all` builds the normal editor target. `make linux-icons` generates Linux
desktop icons when they are needed.

Successful builds produce:

- `./ccutter`
- `./ct2util`

The generic Makefile currently has no automated `test` target.

## Basic check

Run the editor from the build tree:

```sh
./ccutter
```

Confirm that the interface and audio initialise and that the application exits
normally. Linux binary-release verification remains distribution-specific.

## Troubleshooting

- Confirm `ldc2`, the C/C++ compilers, `make`, `acme`, and SDL2 development
  files are discoverable through the active build environment.
- Use `make clean` before rebuilding after changing compilers or SDL2 versions.
- Use `ldd ./ccutter` to inspect unresolved runtime-library dependencies.
