#!/usr/bin/env python3
"""Support the canonical deterministic native Windows build."""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import socket
import struct
import subprocess
import sys


EXPECTED_LDC_VERSION = "1.42.0"
EXPECTED_DMD_VERSION = "2.112.1"
EXPECTED_LLVM_VERSION = "21.1.8"
EXPECTED_TARGET = "x86_64-pc-windows-msvc"
EXPECTED_IMPORT_COUNT = 191
STATUS_FORMAT_VERSION = 1
SUPPORTED_TARGETS = (
    "all",
    "gui",
    "ct2util",
    "test",
    "verify",
    "verify-privacy",
    "clean",
    "toolchain-info",
)
STATUS_TOOL_FIELDS = (
    "LDC",
    "D_FRONTEND",
    "LLVM",
    "TARGET",
    "MSVC",
    "GNU_MAKE",
    "SDL2",
)
EXPECTED_IMPORT_TREE_SHA256 = (
    "205f5011511d1a870113007458b5c06b709e038be9090e9a87a41608f8044a96"
)
REQUIRED_IMPORT_FILES = """
core/atomic.d
core/attribute.d
core/bitop.d
core/builtins.d
core/checkedint.d
core/cpuid.d
core/demangle.d
core/exception.d
core/gc/config.d
core/gc/gcinterface.d
core/gc/registry.d
core/internal/abort.d
core/internal/array/appending.d
core/internal/array/arrayassign.d
core/internal/array/capacity.d
core/internal/array/casting.d
core/internal/array/comparison.d
core/internal/array/concatenation.d
core/internal/array/construction.d
core/internal/array/duplication.d
core/internal/array/equality.d
core/internal/array/utils.d
core/internal/atomic.d
core/internal/attributes.d
core/internal/cast_.d
core/internal/container/array.d
core/internal/container/common.d
core/internal/convert.d
core/internal/dassert.d
core/internal/destruction.d
core/internal/entrypoint.d
core/internal/execinfo.d
core/internal/gc/blockmeta.d
core/internal/gc/impl/proto/gc.d
core/internal/gc/proxy.d
core/internal/hash.d
core/internal/lifetime.d
core/internal/moving.d
core/internal/newaa.d
core/internal/parseoptions.d
core/internal/postblit.d
core/internal/spinlock.d
core/internal/string.d
core/internal/switch_.d
core/internal/traits.d
core/internal/util/math.d
core/lifetime.d
core/math.d
core/memory.d
core/runtime.d
core/stdc/config.d
core/stdc/ctype.d
core/stdc/errno.d
core/stdc/fenv.d
core/stdc/math.d
core/stdc/signal.d
core/stdc/stdarg.d
core/stdc/stddef.d
core/stdc/stdint.d
core/stdc/stdio.d
core/stdc/stdlib.d
core/stdc/string.d
core/stdc/time.d
core/stdc/wchar_.d
core/sync/condition.d
core/sync/exception.d
core/sync/mutex.d
core/sync/semaphore.d
core/sys/posix/config.d
core/sys/posix/endian.d
core/sys/posix/signal.d
core/sys/posix/stdlib.d
core/sys/posix/sys/types.d
core/sys/posix/sys/wait.d
core/sys/posix/time.d
core/sys/windows/basetsd.d
core/sys/windows/basetyps.d
core/sys/windows/bcrypt.d
core/sys/windows/dbghelp.d
core/sys/windows/dbghelp_types.d
core/sys/windows/dll.d
core/sys/windows/imagehlp.d
core/sys/windows/ntdef.d
core/sys/windows/sdkddkver.d
core/sys/windows/shellapi.d
core/sys/windows/stacktrace.d
core/sys/windows/stdc/time.d
core/sys/windows/subauth.d
core/sys/windows/threadaux.d
core/sys/windows/w32api.d
core/sys/windows/winbase.d
core/sys/windows/windef.d
core/sys/windows/winerror.d
core/sys/windows/wingdi.d
core/sys/windows/winnt.d
core/sys/windows/winreg.d
core/sys/windows/winsock2.d
core/sys/windows/winuser.d
core/sys/windows/winver.d
core/thread/context.d
core/thread/fiber/base.d
core/thread/fiber/package.d
core/thread/osthread.d
core/thread/package.d
core/thread/threadbase.d
core/thread/threadgroup.d
core/thread/types.d
core/time.d
core/vararg.d
etc/c/zlib.d
ldc/attributes.d
ldc/intrinsics.di
ldc/llvmasm.di
object.d
std/algorithm/comparison.d
std/algorithm/iteration.d
std/algorithm/mutation.d
std/algorithm/package.d
std/algorithm/searching.d
std/algorithm/setops.d
std/algorithm/sorting.d
std/array.d
std/ascii.d
std/bitmanip.d
std/checkedint.d
std/concurrency.d
std/container/dlist.d
std/container/util.d
std/conv.d
std/csv.d
std/datetime/date.d
std/datetime/interval.d
std/datetime/package.d
std/datetime/stopwatch.d
std/datetime/systime.d
std/datetime/timezone.d
std/digest/md.d
std/digest/package.d
std/digest/sha.d
std/encoding.d
std/exception.d
std/experimental/allocator/common.d
std/file.d
std/format/internal/floats.d
std/format/internal/read.d
std/format/internal/write.d
std/format/package.d
std/format/read.d
std/format/spec.d
std/format/write.d
std/functional.d
std/internal/attributes.d
std/internal/cstring.d
std/internal/digest/sha_SSSE3.d
std/internal/entropy.d
std/internal/memory.d
std/internal/unicode_comp.d
std/internal/unicode_decomp.d
std/internal/unicode_grapheme.d
std/internal/unicode_norm.d
std/internal/unicode_tables.d
std/internal/windows/advapi32.d
std/math/algebraic.d
std/math/constants.d
std/math/exponential.d
std/math/hardware.d
std/math/operations.d
std/math/package.d
std/math/remainder.d
std/math/rounding.d
std/math/traits.d
std/math/trigonometry.d
std/meta.d
std/path.d
std/process.d
std/random.d
std/range/interfaces.d
std/range/package.d
std/range/primitives.d
std/stdio.d
std/string.d
std/system.d
std/traits.d
std/typecons.d
std/uni/package.d
std/utf.d
std/uuid.d
std/variant.d
std/windows/registry.d
std/windows/syserror.d
std/zlib.d
""".strip().splitlines()
EXPECTED_RUNTIME_HASHES = {
    "phobos2-ldc.lib":
        "a4359ae50337cbfdfc8b17c9571af04ec4fe9843be7e87dfd849b7ff8a15fc56",
    "druntime-ldc.lib":
        "753004ad105849b046b741c1eb98e77061e7f3a872a277dd21535e43b7e3f34a",
    "ldc_rt.builtins.lib":
        "1ddf3a678f0c30abc4859ce9dae1307a325e78cd1ee46d4afbeeffa4f126908a",
}
EXPECTED_SDL_VERSION = "2.32.10"
EXPECTED_SDL_SHA256 = (
    "2e44d5bae9a97859eccde14ad4467df14bae7468594bba7fe8eb417f517ce31b"
)
IDENTITY_CHARACTERS = frozenset(
    b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
)


class WindowsBuildError(Exception):
    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def relative_path(value: str) -> Path:
    pure = PurePosixPath(value.replace("\\", "/"))
    if pure.is_absolute() or ".." in pure.parts or not pure.parts:
        raise WindowsBuildError("generated output path must be project-relative")
    return Path(*pure.parts)


def clean_root(value: str) -> Path:
    relative = relative_path(value)
    parts = relative.as_posix().split("/")
    if len(parts) < 2 or parts[0] != "build" or not parts[1].startswith("windows"):
        raise WindowsBuildError(
            "clean root must be a generated build/windows... directory"
        )
    project = Path.cwd().resolve()
    target = (project / relative).resolve()
    generated = (project / "build").resolve()
    if target == generated or generated not in target.parents:
        raise WindowsBuildError("refusing unsafe generated-root removal")
    if target.exists():
        shutil.rmtree(target)
    print("WINDOWS_CLEAN=PASS")
    return target


def run_capture(command: list[str]) -> str:
    result = subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
        errors="replace",
    )
    if result.returncode != 0:
        raise WindowsBuildError(
            f"{Path(command[0]).name} failed with exit code {result.returncode}"
        )
    return result.stdout + result.stderr


def discover_ldc() -> Path:
    candidates: list[Path] = []
    configured = os.environ.get("LDC2")
    if configured:
        candidates.append(Path(configured))
    discovered = shutil.which("ldc2.exe") or shutil.which("ldc2")
    if discovered:
        candidates.append(Path(discovered))

    roots: set[Path] = set()
    for tool in ("bash.exe", "bash", "make.exe", "make"):
        location = shutil.which(tool)
        if not location:
            continue
        path = Path(location).resolve()
        if path.parent.name.lower() == "bin":
            parent = path.parent.parent
            if parent.name.lower() in {"usr", "ucrt64"}:
                roots.add(parent.parent)
    for root in sorted(roots):
        candidates.extend(
            sorted(
                (root / "ucrt64" / "opt").glob(
                    "ldc2-1.42.0-windows-x64/bin/ldc2.exe"
                )
            )
        )

    seen: set[Path] = set()
    for candidate in candidates:
        try:
            resolved = candidate.resolve()
        except OSError:
            continue
        if resolved in seen or not resolved.is_file():
            continue
        seen.add(resolved)
        output = run_capture([str(resolved), "--version"])
        required = (
            f"LDC - the LLVM D compiler ({EXPECTED_LDC_VERSION}",
            f"based on DMD v{EXPECTED_DMD_VERSION}",
            f"LLVM {EXPECTED_LLVM_VERSION}",
            EXPECTED_TARGET,
        )
        if all(item in output for item in required):
            return resolved
    raise WindowsBuildError(
        "official LDC 1.42.0 x64 was not discoverable through the active "
        "tool environment"
    )


def ldc_root(ldc: Path) -> Path:
    return ldc.parent.parent


def runtime_libraries(ldc: Path) -> list[Path]:
    library_root = ldc_root(ldc) / "lib"
    libraries = [library_root / name for name in EXPECTED_RUNTIME_HASHES]
    for library in libraries:
        expected = EXPECTED_RUNTIME_HASHES[library.name]
        if not library.is_file() or sha256(library) != expected:
            raise WindowsBuildError(
                f"official static runtime identity mismatch: {library.name}"
            )
    return libraries


def import_tree_identity(root: Path) -> tuple[int, str]:
    files = sorted(path for path in root.rglob("*") if path.is_file())
    lines = [
        f"{sha256(path)}  {path.relative_to(root).as_posix()}\n"
        for path in files
    ]
    return len(files), hashlib.sha256("".join(lines).encode("utf-8")).hexdigest()


def stage_ldc(output_value: str) -> None:
    output = relative_path(output_value)
    ldc = discover_ldc()
    source = ldc_root(ldc) / "import"
    if not source.is_dir():
        raise WindowsBuildError("official LDC import tree is unavailable")
    selected = [(relative, source / relative)
                for relative in REQUIRED_IMPORT_FILES]
    missing = [relative for relative, path in selected if not path.is_file()]
    if missing:
        raise WindowsBuildError("official LDC required-import inventory is incomplete")
    count = len(selected)
    identity = hashlib.sha256(
        "".join(
            f"{sha256(path)}  {relative}\n"
            for relative, path in selected
        ).encode("utf-8")
    ).hexdigest()
    if count != EXPECTED_IMPORT_COUNT or identity != EXPECTED_IMPORT_TREE_SHA256:
        raise WindowsBuildError("official LDC import-tree identity mismatch")

    if output.exists():
        shutil.rmtree(output)
    for relative, path in selected:
        destination = output / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, destination)
    staged_count, staged_identity = import_tree_identity(output)
    if (staged_count, staged_identity) != (count, identity):
        raise WindowsBuildError("staged LDC import tree differs from its owner")

    config = output.parent / "ldc-empty.conf"
    config.write_text(
        '"default":\n'
        "{\n"
        "    switches = [];\n"
        "    post-switches = [];\n"
        "    lib-dirs = [];\n"
        "};\n",
        encoding="utf-8",
        newline="\n",
    )
    status = output.parent / "ldc-imports.status"
    status.write_text(
        "LDC_IMPORT_STAGE\n"
        f"LDC={EXPECTED_LDC_VERSION}\n"
        f"D_FRONTEND={EXPECTED_DMD_VERSION}\n"
        f"LLVM={EXPECTED_LLVM_VERSION}\n"
        f"TARGET={EXPECTED_TARGET}\n"
        f"FILES={staged_count}\n"
        f"TREE_SHA256={staged_identity}\n"
        "SOURCE=official-installed-interface-tree\n"
        "PATH_POLICY=project-relative-compiler-argument\n",
        encoding="utf-8",
        newline="\n",
    )
    print(
        f"LDC_IMPORT_STAGE=PASS FILES={staged_count} "
        f"TREE_SHA256={staged_identity}"
    )


def run_ldc(
        arguments: list[str],
        link_runtime: bool,
        working_directory: str | None,
) -> None:
    if arguments and arguments[0] == "--":
        arguments = arguments[1:]
    if not arguments:
        raise WindowsBuildError("ldc mode requires compiler arguments")
    ldc = discover_ldc()
    command = [str(ldc), *arguments]
    if link_runtime:
        command.extend(str(path) for path in runtime_libraries(ldc))
    cwd = relative_path(working_directory) if working_directory else None
    result = subprocess.run(command, cwd=cwd, check=False)
    if result.returncode != 0:
        raise WindowsBuildError(
            f"ldc2.exe failed with exit code {result.returncode}"
        )


def u16(data: bytes, offset: int) -> int:
    return struct.unpack_from("<H", data, offset)[0]


def u32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


class PeImage:
    def __init__(self, path: Path):
        self.path = path
        self.data = path.read_bytes()
        if self.data[:2] != b"MZ":
            raise WindowsBuildError(f"{path.name} is not a PE image")
        self.pe = u32(self.data, 0x3C)
        if self.data[self.pe:self.pe + 4] != b"PE\0\0":
            raise WindowsBuildError(f"{path.name} has no PE signature")
        self.coff = self.pe + 4
        self.machine = u16(self.data, self.coff)
        self.section_count = u16(self.data, self.coff + 2)
        self.optional_size = u16(self.data, self.coff + 16)
        self.optional = self.coff + 20
        self.magic = u16(self.data, self.optional)
        self.entry = u32(self.data, self.optional + 16)
        self.subsystem = u16(self.data, self.optional + 68)
        self.section_table = self.optional + self.optional_size
        self.sections: list[tuple[str, int, int, int]] = []
        for index in range(self.section_count):
            at = self.section_table + index * 40
            name = self.data[at:at + 8].rstrip(b"\0").decode("ascii")
            virtual_size = u32(self.data, at + 8)
            virtual_address = u32(self.data, at + 12)
            raw_size = u32(self.data, at + 16)
            raw_pointer = u32(self.data, at + 20)
            self.sections.append(
                (
                    name,
                    virtual_address,
                    max(virtual_size, raw_size),
                    raw_pointer,
                )
            )

    def directory(self, index: int) -> tuple[int, int]:
        base = self.optional + 112 + index * 8
        return u32(self.data, base), u32(self.data, base + 4)

    def file_offset(self, rva: int) -> int:
        for _, virtual_address, size, raw_pointer in self.sections:
            if virtual_address <= rva < virtual_address + size:
                return raw_pointer + rva - virtual_address
        raise WindowsBuildError(f"{self.path.name} has an invalid RVA")

    def c_string(self, rva: int) -> str:
        start = self.file_offset(rva)
        end = self.data.index(b"\0", start)
        return self.data[start:end].decode("ascii")

    def imports(self) -> list[str]:
        rva, _ = self.directory(1)
        if not rva:
            return []
        at = self.file_offset(rva)
        names = []
        while any(self.data[at:at + 20]):
            names.append(self.c_string(u32(self.data, at + 12)))
            at += 20
        return sorted(set(names), key=str.lower)

    def resource_leaves(
            self) -> dict[tuple[int | str, ...], tuple[int, str]]:
        resource_rva, _ = self.directory(2)
        if not resource_rva:
            return {}
        base = self.file_offset(resource_rva)
        leaves: dict[tuple[int | str, ...], tuple[int, str]] = {}

        def entry_name(raw: int) -> int | str:
            if not raw & 0x80000000:
                return raw
            at = base + (raw & 0x7FFFFFFF)
            length = u16(self.data, at)
            return self.data[at + 2:at + 2 + length * 2].decode("utf-16le")

        def walk(relative: int, key: tuple[int | str, ...]) -> None:
            directory = base + relative
            entries = u16(self.data, directory + 12) + u16(
                self.data, directory + 14
            )
            for index in range(entries):
                entry = directory + 16 + index * 8
                name = entry_name(u32(self.data, entry))
                target = u32(self.data, entry + 4)
                next_key = key + (name,)
                if target & 0x80000000:
                    walk(target & 0x7FFFFFFF, next_key)
                else:
                    leaf = base + target
                    payload_rva = u32(self.data, leaf)
                    payload_size = u32(self.data, leaf + 4)
                    payload_at = self.file_offset(payload_rva)
                    payload = self.data[payload_at:payload_at + payload_size]
                    leaves[next_key] = (
                        payload_size,
                        hashlib.sha256(payload).hexdigest(),
                    )

        walk(0, ())
        return leaves

    def exports(self) -> list[str]:
        export_rva, _ = self.directory(0)
        if not export_rva:
            return []
        export = self.file_offset(export_rva)
        name_count = u32(self.data, export + 24)
        names_rva = u32(self.data, export + 32)
        names_at = self.file_offset(names_rva)
        return sorted(
            self.c_string(u32(self.data, names_at + index * 4))
            for index in range(name_count)
        )


def discover_sdl() -> Path:
    candidates = []
    configured = os.environ.get("SDL2_DLL")
    if configured:
        candidates.append(Path(configured))
    discovered = shutil.which("SDL2.dll")
    if discovered:
        candidates.append(Path(discovered))
    for candidate in candidates:
        try:
            resolved = candidate.resolve()
        except OSError:
            continue
        if resolved.is_file() and sha256(resolved) == EXPECTED_SDL_SHA256:
            image = PeImage(resolved)
            if image.machine == 0x8664 and image.magic == 0x20B:
                return resolved
    raise WindowsBuildError(
        "verified SDL2 2.32.10 x64 runtime is not discoverable through "
        "the active tool environment"
    )


def prepare_sdl(output_value: str) -> None:
    output = relative_path(output_value)
    output.mkdir(parents=True, exist_ok=True)
    dll = discover_sdl()
    staged_dll = output / "SDL2.dll"
    shutil.copyfile(dll, staged_dll)
    exports = PeImage(staged_dll).exports()
    if len(exports) < 100 or len(exports) != len(set(exports)):
        raise WindowsBuildError("SDL2 export inventory is incomplete")
    definition = output / "SDL2.def"
    definition.write_text(
        "LIBRARY SDL2.dll\nEXPORTS\n"
        + "".join(f"    {name}\n" for name in exports),
        encoding="ascii",
        newline="\n",
    )

    librarian = shutil.which("lib.exe") or shutil.which("lib")
    if not librarian:
        raise WindowsBuildError(
            "Microsoft lib.exe is unavailable in the active x64 environment"
        )
    result = subprocess.run(
        [
            librarian,
            "/nologo",
            "/machine:x64",
            "/brepro",
            "/def:SDL2.def",
            "/out:SDL2.lib",
        ],
        cwd=output,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise WindowsBuildError(
            f"Microsoft lib.exe failed with exit code {result.returncode}"
        )
    import_library = output / "SDL2.lib"
    if not import_library.is_file():
        raise WindowsBuildError("Microsoft import library was not generated")
    export_object = output / "SDL2.exp"
    if export_object.exists():
        export_object.unlink()
    gnu_library = shutil.which("libSDL2.dll.a")
    if gnu_library and sha256(import_library) == sha256(Path(gnu_library)):
        raise WindowsBuildError("SDL2 import library is a renamed GNU archive")
    (output / "SDL2.status").write_text(
        "SDL2_IMPORT_LIBRARY\n"
        f"VERSION={EXPECTED_SDL_VERSION}\n"
        "ARCHITECTURE=x64\n"
        f"DLL_SHA256={sha256(staged_dll)}\n"
        f"EXPORTS={len(exports)}\n"
        "DEFINITION_OWNER=verified-dll-export-table\n"
        "LIBRARIAN=Microsoft-lib.exe\n"
        "DETERMINISTIC=/Brepro\n"
        f"IMPORT_LIBRARY_SHA256={sha256(import_library)}\n",
        encoding="utf-8",
        newline="\n",
    )
    print(
        f"SDL2_PREPARE=PASS VERSION={EXPECTED_SDL_VERSION} "
        f"EXPORTS={len(exports)} DLL_SHA256={sha256(staged_dll)} "
        f"IMPORT_LIBRARY_SHA256={sha256(import_library)}"
    )


def prepare_resource(
        template_value: str,
        icon_value: str,
        manifest_value: str,
        output_value: str,
) -> None:
    template = relative_path(template_value)
    icon = relative_path(icon_value)
    manifest_source = relative_path(manifest_value)
    output = relative_path(output_value)
    text = template.read_text(encoding="utf-8")
    if text.count("@ICON@") != 1 or text.count("@MANIFEST@") != 1:
        raise WindowsBuildError("Windows resource template markers are invalid")
    output.parent.mkdir(parents=True, exist_ok=True)
    staged_manifest = output.parent / manifest_source.name
    shutil.copyfile(manifest_source, staged_manifest)
    rendered = text.replace("@ICON@", icon.as_posix()).replace(
        "@MANIFEST@",
        f"generated/resources/{manifest_source.name}",
    )
    output.write_text(rendered, encoding="utf-8", newline="\n")
    print("WINDOWS_RESOURCE_INPUT=PASS")


def verify_pe(kind: str, file_value: str) -> None:
    path = relative_path(file_value)
    image = PeImage(path)
    if image.machine != 0x8664 or image.magic != 0x20B:
        raise WindowsBuildError(f"{path.name} is not PE32+ x64")
    expected_subsystem = 2 if kind == "gui" else 3
    if image.subsystem != expected_subsystem:
        raise WindowsBuildError(f"{path.name} has the wrong subsystem")
    if image.entry == 0:
        raise WindowsBuildError(f"{path.name} has no entry point")
    if b"RSDS" in image.data or re.search(rb"(?i)\.pdb(?:\x00|$)", image.data):
        raise WindowsBuildError(f"{path.name} contains a PDB reference")

    imports = image.imports()
    allowed = {"ADVAPI32.dll", "KERNEL32.dll", "SDL2.dll", "WS2_32.dll"}
    unexpected = [name for name in imports if name.upper() not in {
        item.upper() for item in allowed
    }]
    if unexpected:
        raise WindowsBuildError(
            f"{path.name} has unexpected runtime DLL imports"
        )
    if kind in {"gui", "test"} and not any(
            name.lower() == "sdl2.dll" for name in imports):
        raise WindowsBuildError(f"{path.name} does not import SDL2.dll")

    leaves = image.resource_leaves()
    resources = Counter(key[0] for key in leaves)
    if kind == "gui":
        if resources != Counter({3: 7, 14: 1, 24: 1}):
            raise WindowsBuildError(
                f"{path.name} has the wrong icon or manifest inventory"
            )
    elif resources:
        raise WindowsBuildError(f"{path.name} has unexpected resources")

    resource_summary = ",".join(
        f"{key}:{resources[key]}" for key in sorted(resources, key=str)
    ) or "none"
    print(
        f"PE_VERIFY=PASS KIND={kind} MACHINE=x64 "
        f"SUBSYSTEM={'GUI' if expected_subsystem == 2 else 'CONSOLE'} "
        f"IMPORTS={','.join(imports)} RESOURCES={resource_summary} PDB=0"
    )


def identity_occurrences(data: bytes, token: bytes) -> int:
    if not token:
        return 0
    haystack = data.lower()
    value = token.lower()
    offset = 0
    count = 0
    while True:
        found = haystack.find(value, offset)
        if found < 0:
            return count
        end = found + len(value)
        left = found == 0 or haystack[found - 1] not in IDENTITY_CHARACTERS
        right = end == len(haystack) or haystack[end] not in IDENTITY_CHARACTERS
        if left and right:
            count += 1
        offset = found + 1


def path_needles(value: str) -> list[bytes]:
    if not value:
        return []
    normalized = str(Path(value))
    variants = {normalized, normalized.replace("\\", "/")}
    return [os.fsencode(item) for item in variants if item]


def privacy_counts(root: Path) -> tuple[dict[str, int], dict[str, int]]:
    audited_suffixes = {
        ".o", ".obj", ".res", ".exe", ".dll", ".lib",
        ".txt", ".status", ".json",
    }
    files = sorted(
        path for path in root.rglob("*")
        if path.is_file() and path.suffix.lower() in audited_suffixes
    )
    data = b"\0".join(path.read_bytes() for path in files)
    ldc = discover_ldc()
    exact = {
        "compiler_path": path_needles(str(ldc_root(ldc))),
        "sdk_path": path_needles(
            os.environ.get("WindowsSdkDir")
            or os.environ.get("WindowsSDKDir", "")
        ),
        "profile_path": (
            path_needles(os.environ.get("USERPROFILE", ""))
            + path_needles(os.environ.get("HOME", ""))
        ),
        "checkout_path": path_needles(str(Path.cwd().resolve())),
        "temporary_path": (
            path_needles(os.environ.get("TEMP", ""))
            + path_needles(os.environ.get("TMP", ""))
        ),
    }
    prohibited = {
        category: sum(data.lower().count(value.lower()) for value in values)
        for category, values in exact.items()
    }
    host = socket.gethostname().encode("utf-8", errors="ignore")
    prohibited["host_token"] = identity_occurrences(data, host)
    accounts = {
        os.environ.get(name, "").encode("utf-8", errors="ignore")
        for name in ("USERNAME", "USER", "LOGNAME")
        if os.environ.get(name)
    }
    prohibited["account_token"] = sum(
        identity_occurrences(data, value) for value in accounts
    )
    prohibited["pdb_or_debug_path"] = len(
        re.findall(rb"(?i)[a-z]:\\[^\x00\r\n]{0,512}\.(?:pdb|ilk)", data)
    )
    prohibited["backup_path"] = len(
        re.findall(rb"(?i)[a-z]:\\[^\x00\r\n]{0,256}\\backups?\\", data)
    )
    prohibited["environment_expansion"] = len(
        re.findall(
            rb"(?i)%(?:userprofile|username|computername|temp|tmp|home|"
            rb"ldc_root|windowssdkdir|vcinstalldir)%|"
            rb"\$env:(?:userprofile|username|computername|temp|tmp|home|"
            rb"ldc_root|windowssdkdir|vcinstalldir)",
            data,
        )
    )
    prohibited["unique_machine_identifier"] = len(
        re.findall(
            rb"(?i)(?:machineguid|productid|serialnumber)\s*[:=]\s*"
            rb"[A-Za-z0-9{}-]{8,}",
            data,
        )
    )

    relative_imports = re.findall(
        rb"(?i)(?:build[\\/]windows[^\\/\x00\r\n]*[\\/])?"
        rb"generated[\\/]ldc-imports[\\/][^\x00\r\n]+?\.d",
        data,
    )
    absolute_d_paths = re.findall(
        rb"(?i)[a-z]:\\[^\x00\r\n]{1,512}?\.d", data
    )
    phobos = runtime_libraries(ldc)[0].read_bytes()
    vendor_paths = [value for value in absolute_d_paths if value in phobos]
    prohibited["unowned_absolute_d_path"] = len(absolute_d_paths) - len(
        vendor_paths
    )
    basenames = {
        match.group(1).lower()
        for match in re.finditer(
            rb"(?i)(?:^|[\\/])([A-Za-z_][A-Za-z0-9_.-]*\.d)"
            rb"(?=$|\x00)",
            data,
        )
    }
    permitted = {
        "relative_ldc_imports": len(relative_imports),
        "upstream_vendor_runtime_paths": len(vendor_paths),
        "module_basenames": len(basenames),
    }
    return prohibited, permitted


def verify_privacy(root_value: str, record_value: str | None) -> None:
    root = relative_path(root_value)
    prohibited, permitted = privacy_counts(root)
    total = sum(prohibited.values())
    lines = [
        "WINDOWS_PRIVACY_AUDIT",
        *(f"PROHIBITED_{key.upper()}={prohibited[key]}"
          for key in sorted(prohibited)),
        f"PROHIBITED_TOTAL={total}",
        *(f"PERMITTED_{key.upper()}={permitted[key]}"
          for key in sorted(permitted)),
        "PERMITTED_GENERIC_SYSTEM_IDENTIFIERS=not-private",
        f"RESULT={'PASS' if total == 0 else 'FAIL'}",
    ]
    if record_value:
        record = relative_path(record_value)
        record.parent.mkdir(parents=True, exist_ok=True)
        record.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    for line in lines:
        print(line)
    if total:
        raise WindowsBuildError("generated Windows artefacts contain private data")


def tool_versions() -> dict[str, str]:
    ldc_output = run_capture([str(discover_ldc()), "--version"])
    cl = shutil.which("cl.exe") or shutil.which("cl")
    if not cl:
        raise WindowsBuildError("Microsoft cl.exe is unavailable")
    cl_output = subprocess.run(
        [cl],
        check=False,
        capture_output=True,
        text=True,
        errors="replace",
    )
    msvc_match = re.search(
        r"Compiler Version ([0-9.]+) for x64",
        cl_output.stdout + cl_output.stderr,
        re.IGNORECASE,
    )
    if not msvc_match:
        raise WindowsBuildError("Microsoft x64 compiler version is unavailable")
    make = shutil.which("make.exe") or shutil.which("make")
    if not make:
        raise WindowsBuildError("GNU Make is unavailable")
    make_line = run_capture([make, "--version"]).splitlines()[0]
    return {
        "LDC": EXPECTED_LDC_VERSION,
        "D_FRONTEND": EXPECTED_DMD_VERSION,
        "LLVM": EXPECTED_LLVM_VERSION,
        "TARGET": EXPECTED_TARGET,
        "MSVC": msvc_match.group(1),
        "GNU_MAKE": make_line,
        "SDL2": EXPECTED_SDL_VERSION,
    }


def toolchain_info() -> None:
    versions = tool_versions()
    print("WINDOWS_TOOLCHAIN=PASS")
    for key, value in versions.items():
        print(f"{key}={value}")
    print("RESOURCE_COMPILER=Microsoft-rc.exe")
    print("LIBRARIAN=Microsoft-lib.exe")
    print("ASSEMBLER=ACME")


def read_key_value_record(path: Path) -> dict[str, str]:
    fields: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        fields[key] = value
    return fields


def render_status_record(facts: dict[str, object]) -> str:
    versions = facts["tool_versions"]
    privacy = facts["privacy"]
    if not isinstance(versions, dict) or not isinstance(privacy, dict):
        raise WindowsBuildError("status facts contain invalid mappings")
    verdict = "PASS"
    if int(facts["tests_failed"]) != 0 or \
            int(privacy["PROHIBITED_TOTAL"]) != 0 or \
            facts["deterministic_gui_match"] == "false":
        verdict = "FAIL"
    lines = [
        "CHEESECUTTER_WINDOWS_BUILD_STATUS",
        f"STATUS_FORMAT_VERSION={STATUS_FORMAT_VERSION}",
        "BUILD_OWNER=Makefile.win",
        f"VERIFICATION_VERDICT={verdict}",
        "",
        "TOOLS",
        *(f"{key}={versions[key]}" for key in STATUS_TOOL_FIELDS),
        "RESOURCE_COMPILER=Microsoft-rc.exe",
        "LIBRARIAN=Microsoft-lib.exe",
        "ASSEMBLER=ACME",
        "",
        "POLICY",
        "ARCHITECTURE=x64",
        f"SUPPORTED_TARGETS={' '.join(SUPPORTED_TARGETS)}",
        "GUI_OUTPUT=ccutter.exe",
        "GUI_SUBSYSTEM=WINDOWS",
        "GUI_ENTRY_POINT=wmainCRTStartup",
        "DETERMINISTIC_LINK=/Brepro",
        "CT2UTIL_OUTPUT=ct2util.exe",
        "CT2UTIL_SUBSYSTEM=CONSOLE",
        "TEST_SUBSYSTEM=CONSOLE",
        "CHEESECUTTER_CONSOLE_APPLICATION_TARGET=absent",
        "LDC_IMPORTS=generated-relative-stage",
        "STATIC_D_RUNTIME=yes",
        "RUNTIME_SAFETY=assertions-contracts-bounds-checks-enabled",
        "",
        "RESULTS",
        f"SOURCE_RELEASE_ENTRY_COUNT={facts['source_release_entry_count']}",
        f"GUI_SHA256={facts['gui_sha256']}",
        f"GUI_SIZE={facts['gui_size']}",
        f"CT2UTIL_SHA256={facts['ct2util_sha256']}",
        f"TEST_SHA256={facts['test_sha256']}",
        f"SETTLED_OUTPUT_SHA256={facts['settled_output_sha256']}",
        f"TESTS_PASSED={facts['tests_passed']}",
        f"TESTS_FAILED={facts['tests_failed']}",
        f"DETERMINISTIC_PEER_SHA256={facts['deterministic_peer_sha256']}",
        f"DETERMINISTIC_GUI_MATCH={facts['deterministic_gui_match']}",
        f"PROHIBITED_PRIVACY_FINDINGS={privacy['PROHIBITED_TOTAL']}",
        f"PERMITTED_MODULE_BASENAMES={privacy['PERMITTED_MODULE_BASENAMES']}",
        "PERMITTED_RELATIVE_LDC_IMPORTS="
            f"{privacy['PERMITTED_RELATIVE_LDC_IMPORTS']}",
        "PERMITTED_UPSTREAM_VENDOR_RUNTIME_PATHS="
            f"{privacy['PERMITTED_UPSTREAM_VENDOR_RUNTIME_PATHS']}",
        "PERMITTED_GENERIC_SYSTEM_IDENTIFIERS="
            f"{privacy['PERMITTED_GENERIC_SYSTEM_IDENTIFIERS']}",
    ]
    return "\n".join(lines) + "\n"


def write_status_record(path: Path, facts: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(render_status_record(facts).encode("utf-8"))


def write_status(root_value: str, peer_value: str | None) -> None:
    root = relative_path(root_value)
    info = root / "build-info"
    info.mkdir(parents=True, exist_ok=True)
    versions = tool_versions()
    binaries = {
        "GUI": root / "bin" / "ccutter.exe",
        "CT2UTIL": root / "bin" / "ct2util.exe",
        "TEST": root / "tests" / "permanent-tests.exe",
    }
    for label, path in binaries.items():
        if not path.is_file():
            raise WindowsBuildError(f"{label} output is missing")
    test_output = root / "tests" / "permanent-suite.txt"
    text = test_output.read_text(encoding="utf-8")
    summary = re.search(r"(?m)^(\d+) passed, (\d+) failed$", text)
    if not summary or summary.group(2) != "0":
        raise WindowsBuildError("permanent test status is not passing")
    privacy_path = root / "build-info" / "privacy-summary.txt"
    if not privacy_path.is_file():
        raise WindowsBuildError("privacy status is not passing")
    privacy = read_key_value_record(privacy_path)
    required_privacy_fields = (
        "PROHIBITED_TOTAL",
        "PERMITTED_MODULE_BASENAMES",
        "PERMITTED_RELATIVE_LDC_IMPORTS",
        "PERMITTED_UPSTREAM_VENDOR_RUNTIME_PATHS",
        "PERMITTED_GENERIC_SYSTEM_IDENTIFIERS",
        "RESULT",
    )
    if any(field not in privacy for field in required_privacy_fields) or \
            privacy["PROHIBITED_TOTAL"] != "0" or privacy["RESULT"] != "PASS":
        raise WindowsBuildError("privacy status is not passing")
    source_release_files = [
        line.strip()
        for line in Path("release/source-files.txt").read_text(
            encoding="utf-8"
        ).splitlines()
        if line.strip()
    ]

    peer_hash = "not-requested"
    deterministic = "not-requested"
    if peer_value:
        peer = relative_path(peer_value) / "bin" / "ccutter.exe"
        if not peer.is_file():
            raise WindowsBuildError("deterministic peer GUI is missing")
        peer_hash = sha256(peer)
        deterministic = str(peer_hash == sha256(binaries["GUI"])).lower()
        if deterministic != "true":
            raise WindowsBuildError("GUI deterministic peer differs")

    status = info / "WINDOWS_BUILD_STATUS.txt"
    facts: dict[str, object] = {
        "tool_versions": versions,
        "source_release_entry_count": len(source_release_files),
        "gui_sha256": sha256(binaries["GUI"]),
        "gui_size": binaries["GUI"].stat().st_size,
        "ct2util_sha256": sha256(binaries["CT2UTIL"]),
        "test_sha256": sha256(binaries["TEST"]),
        "settled_output_sha256": sha256(test_output),
        "tests_passed": int(summary.group(1)),
        "tests_failed": int(summary.group(2)),
        "deterministic_peer_sha256": peer_hash,
        "deterministic_gui_match": deterministic,
        "privacy": privacy,
    }
    write_status_record(status, facts)
    print(
        f"WINDOWS_BUILD_STATUS=PASS GUI_SHA256={sha256(binaries['GUI'])} "
        f"TESTS={summary.group(1)}/0 PRIVACY=0"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Prepare and verify the canonical native Windows build."
    )
    commands = parser.add_subparsers(dest="command", required=True)

    clean = commands.add_parser("clean")
    clean.add_argument("--root", required=True)

    stage = commands.add_parser("stage-ldc")
    stage.add_argument("--output", required=True)

    ldc = commands.add_parser("ldc")
    ldc.add_argument("--link-runtime", action="store_true")
    ldc.add_argument("--working-directory")
    ldc.add_argument("arguments", nargs=argparse.REMAINDER)

    sdl = commands.add_parser("prepare-sdl")
    sdl.add_argument("--output", required=True)

    resource = commands.add_parser("prepare-resource")
    resource.add_argument("--template", required=True)
    resource.add_argument("--icon", required=True)
    resource.add_argument("--manifest", required=True)
    resource.add_argument("--output", required=True)

    pe = commands.add_parser("verify-pe")
    pe.add_argument("--kind", choices=["gui", "ct2util", "test"],
                    required=True)
    pe.add_argument("--file", required=True)

    privacy = commands.add_parser("verify-privacy")
    privacy.add_argument("--root", required=True)
    privacy.add_argument("--record")

    commands.add_parser("toolchain-info")

    status = commands.add_parser("write-status")
    status.add_argument("--root", required=True)
    status.add_argument("--peer")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command == "clean":
            clean_root(args.root)
        elif args.command == "stage-ldc":
            stage_ldc(args.output)
        elif args.command == "ldc":
            run_ldc(
                args.arguments, args.link_runtime, args.working_directory
            )
        elif args.command == "prepare-sdl":
            prepare_sdl(args.output)
        elif args.command == "prepare-resource":
            prepare_resource(
                args.template, args.icon, args.manifest, args.output
            )
        elif args.command == "verify-pe":
            verify_pe(args.kind, args.file)
        elif args.command == "verify-privacy":
            verify_privacy(args.root, args.record)
        elif args.command == "toolchain-info":
            toolchain_info()
        elif args.command == "write-status":
            write_status(args.root, args.peer)
        else:
            raise WindowsBuildError("unknown Windows build command")
    except (WindowsBuildError, OSError, ValueError, struct.error) as error:
        print(f"windows_build_support.py: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
