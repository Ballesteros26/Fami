#!/usr/bin/env python3
"""Create deterministic CheeseCutter source and Linux build-kit archives."""

from __future__ import annotations

import argparse
import hashlib
import os
import platform
import socket
import stat
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath


PROJECT_NAME = "CheeseCutter"
DEFAULT_RELEASE_LABEL = "2.11R"
RELEASE_NAME = f"{PROJECT_NAME}-{DEFAULT_RELEASE_LABEL}-Hypercut"
LINUX_KIT_TOP = f"{RELEASE_NAME}-linux-build-kit"
LINUX_KIT_ZIP_NAME = f"{LINUX_KIT_TOP}.zip"
MANIFEST_PATH = Path("release/source-files.txt")
SOURCE_MANIFEST_NAME = "SOURCE_MANIFEST.sha256"
FIXED_ZIP_TIMESTAMP = (2026, 7, 20, 0, 0, 0)
FILE_MODE = 0o644
EXECUTABLE_MODE = 0o755
PRIVACY_EXACT_VALUE = "exact-value"
PRIVACY_IDENTITY_TOKEN = "identity-token"

FORBIDDEN_PARTS = {
    ".git",
    "build",
    "CheeseCutter.app",
    "dist",
    "__MACOSX",
    "__pycache__",
    "docs",
}
FORBIDDEN_NAMES = {".DS_Store", "._.DS_Store", "_backup.ct"}
FORBIDDEN_SUFFIXES = {
    ".o",
    ".dmg",
    ".zip",
    ".log",
    ".tmp",
    ".swp",
    ".swo",
    ".pyc",
}
FORBIDDEN_EXACT_PATHS = {
    "ccutter",
    "ct2util",
    "src/c64/player.bin",
    "src/font/font-original-DO-NOT-USE.psf",
    "tunes/_backup.ct",
}


class ReleaseError(Exception):
    pass


def source_archive_names(release_label: str) -> tuple[str, str]:
    if (not release_label or release_label in {".", ".."} or
            "/" in release_label or "\\" in release_label):
        raise ReleaseError("invalid source release label")
    source_zip_name = f"{PROJECT_NAME}-{release_label}-source.zip"
    source_top = source_zip_name[:-len(".zip")]
    return source_zip_name, source_top


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as handle:
        tmp = Path(handle.name)
        handle.write(data)
    tmp.replace(path)


def normalize_relpath(raw: str) -> str:
    value = raw.strip()
    if not value:
        raise ReleaseError("empty manifest path")
    pure = PurePosixPath(value)
    if pure.is_absolute() or ".." in pure.parts:
        raise ReleaseError(f"manifest path escapes project root: {value}")
    if str(pure) != value:
        raise ReleaseError(f"manifest path is not normalized: {value}")
    return value


def path_is_forbidden(rel: str) -> bool:
    pure = PurePosixPath(rel)
    if rel in FORBIDDEN_EXACT_PATHS:
        return True
    if pure.name in FORBIDDEN_NAMES:
        return True
    if pure.suffix in FORBIDDEN_SUFFIXES:
        return True
    if any(part in FORBIDDEN_PARTS for part in pure.parts):
        return True
    if pure.name.startswith("._"):
        return True
    return False


def load_source_files(project_root: Path) -> list[str]:
    manifest = project_root / MANIFEST_PATH
    if not manifest.is_file():
        raise ReleaseError(f"missing source manifest: {MANIFEST_PATH}")
    entries = [normalize_relpath(line) for line in manifest.read_text().splitlines()
        if line.strip()]
    if entries != sorted(entries):
        raise ReleaseError("source manifest must be sorted")
    if len(entries) != len(set(entries)):
        raise ReleaseError("source manifest contains duplicates")
    for rel in entries:
        if path_is_forbidden(rel):
            raise ReleaseError(f"forbidden source manifest path: {rel}")
        path = project_root / rel
        if not path.is_file():
            raise ReleaseError(f"manifest file does not exist: {rel}")
        if path.is_symlink():
            target = os.readlink(path)
            target_path = Path(target)
            if target_path.is_absolute() or ".." in PurePosixPath(target).parts:
                raise ReleaseError(f"unsafe source symlink: {rel}")
    return entries


def identity_token_matches(data: bytes | str, token: bytes | str,
        case_insensitive: bool = False) -> bool:
    """Return whether token occurs with non-identifier boundaries."""
    if type(data) is not type(token):
        raise TypeError("identity token and scanned data must use the same type")
    if not token:
        return False
    comparable_data = data.lower() if case_insensitive else data
    comparable_token = token.lower() if case_insensitive else token

    def is_identity_character(value: int | str) -> bool:
        code = value if isinstance(value, int) else ord(value)
        return (ord("a") <= code <= ord("z") or
            ord("A") <= code <= ord("Z") or
            ord("0") <= code <= ord("9") or
            code in (ord("_"), ord("-")))

    offset = 0
    while True:
        index = comparable_data.find(comparable_token, offset)
        if index < 0:
            return False
        end = index + len(comparable_token)
        left_is_boundary = index == 0 or not is_identity_character(data[index - 1])
        right_is_boundary = end == len(data) or not is_identity_character(data[end])
        if left_is_boundary and right_is_boundary:
            return True
        offset = index + 1


def private_value_matches(data: bytes, needle: bytes, policy: str,
        case_insensitive: bool) -> bool:
    if policy == PRIVACY_EXACT_VALUE:
        if case_insensitive:
            return needle.lower() in data.lower()
        return needle in data
    if policy == PRIVACY_IDENTITY_TOKEN:
        return identity_token_matches(data, needle, case_insensitive)
    raise ReleaseError("unknown private-value matching policy")


def private_needles(project_root: Path) -> list[tuple[str, bytes, str, bool]]:
    windows_matching = platform.system() == "Windows"
    values: list[tuple[str, str, str, bool]] = []
    exact_paths: list[str] = []
    for category, key in (
        ("home path", "HOME"),
        ("profile path", "USERPROFILE"),
        ("working-directory path", "PWD"),
        ("temporary path", "TEMP"),
        ("temporary path", "TMP"),
        ("temporary path", "TMPDIR"),
        ("compiler installation path", "LDC_ROOT"),
        ("compiler installation path", "VCINSTALLDIR"),
        ("compiler installation path", "VCToolsInstallDir"),
        ("SDK installation path", "WindowsSdkDir"),
        ("SDK installation path", "WindowsSDKDir"),
    ):
        value = os.environ.get(key)
        if value:
            values.append((category, value, PRIVACY_EXACT_VALUE,
                windows_matching))
            if category in {"home path", "profile path"}:
                exact_paths.append(value)
    values.append(("checkout path", str(project_root.resolve()),
        PRIVACY_EXACT_VALUE, windows_matching))

    for key in ("USER", "LOGNAME", "USERNAME"):
        value = os.environ.get(key)
        if not value:
            continue
        comparison = value.lower() if windows_matching else value
        covered_by_profile = any(comparison in [
            part.lower() if windows_matching else part
            for part in path.replace("\\", "/").split("/")
        ] for path in exact_paths)
        if not covered_by_profile:
            values.append(("account identifier", value,
                PRIVACY_IDENTITY_TOKEN, windows_matching))

    host = socket.gethostname()
    if host:
        values.append(("host identifier", host, PRIVACY_IDENTITY_TOKEN,
            windows_matching))
    try:
        computer = subprocess.run(
            ["scutil", "--get", "ComputerName"],
            check=False,
            capture_output=True,
            text=True,
        ).stdout.strip()
        if computer:
            values.append(("host identifier", computer,
                PRIVACY_IDENTITY_TOKEN, windows_matching))
    except OSError:
        pass
    result: list[tuple[str, bytes, str, bool]] = []
    seen: set[tuple[str, str, str]] = set()
    for category, value, policy, case_insensitive in values:
        value = value.strip()
        if not value:
            continue
        comparable = value.lower() if case_insensitive else value
        key = (category, policy, comparable)
        if key not in seen:
            seen.add(key)
            result.append((category, value.encode("utf-8"), policy,
                case_insensitive))
    return result


def scan_private_values(project_root: Path, relpaths: list[str],
        extra_members: dict[str, bytes]) -> None:
    needles = private_needles(project_root)
    findings: dict[tuple[str, str, str], int] = {}

    def record(owner: str, category: str, location: str) -> None:
        key = (owner, category, location)
        findings[key] = findings.get(key, 0) + 1

    for rel in relpaths:
        rel_bytes = rel.encode("utf-8")
        for category, needle, policy, case_insensitive in needles:
            if private_value_matches(rel_bytes, needle, policy,
                    case_insensitive):
                record(rel, category, "member name")
        data = (project_root / rel).read_bytes()
        for category, needle, policy, case_insensitive in needles:
            if private_value_matches(data, needle, policy, case_insensitive):
                record(rel, category, "file data")
    for member, data in extra_members.items():
        member_bytes = member.encode("utf-8")
        for category, needle, policy, case_insensitive in needles:
            if private_value_matches(member_bytes, needle, policy,
                    case_insensitive):
                record(member, category, "member name")
            if private_value_matches(data, needle, policy, case_insensitive):
                record(member, category, "generated data")
    if findings:
        lines = [
            f"{owner}: {category} in {location} "
            f"({count} redacted finding{'s' if count != 1 else ''})"
            for (owner, category, location), count in sorted(findings.items())
        ]
        raise ReleaseError("private value found:\n" + "\n".join(lines))


def zip_info(member: str, mode: int) -> zipfile.ZipInfo:
    pure = PurePosixPath(member)
    if pure.is_absolute() or ".." in pure.parts:
        raise ReleaseError(f"unsafe ZIP member: {member}")
    if "__MACOSX" in pure.parts or pure.name == ".DS_Store" or pure.name.startswith("._"):
        raise ReleaseError(f"forbidden ZIP member: {member}")
    info = zipfile.ZipInfo(member, FIXED_ZIP_TIMESTAMP)
    info.create_system = 3
    info.external_attr = (mode & 0o777) << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    return info


def is_executable_source(rel: str, path: Path) -> bool:
    if rel in {"scripts/create_source_release.py", "scripts/generate_desktop_icons.py",
            "make-wintest.sh", "arch/makedmg.sh"}:
        return True
    return bool(path.stat().st_mode & stat.S_IXUSR)


def source_manifest(project_root: Path, relpaths: list[str]) -> bytes:
    lines = []
    for rel in relpaths:
        lines.append(f"{sha256_file(project_root / rel)}  {rel}")
    return ("\n".join(lines) + "\n").encode("utf-8")


def write_zip(path: Path, members: list[tuple[str, bytes, int]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as handle:
        tmp = Path(handle.name)
    try:
        with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED,
                compresslevel=9) as archive:
            archive.comment = b""
            for member, data, mode in sorted(members, key=lambda item: item[0]):
                archive.writestr(zip_info(member, mode), data)
        tmp.replace(path)
    finally:
        if tmp.exists():
            tmp.unlink()


def create_source_zip(project_root: Path, output: Path,
        release_label: str = DEFAULT_RELEASE_LABEL) -> Path:
    source_zip_name, source_top = source_archive_names(release_label)
    relpaths = load_source_files(project_root)
    manifest_data = source_manifest(project_root, relpaths)
    extra = {f"{source_top}/{SOURCE_MANIFEST_NAME}": manifest_data}
    scan_private_values(project_root, relpaths, extra)
    members: list[tuple[str, bytes, int]] = []
    for rel in relpaths:
        path = project_root / rel
        mode = EXECUTABLE_MODE if is_executable_source(rel, path) else FILE_MODE
        members.append((f"{source_top}/{rel}", path.read_bytes(), mode))
    members.append((f"{source_top}/{SOURCE_MANIFEST_NAME}", manifest_data, FILE_MODE))
    source_zip = output / source_zip_name
    write_zip(source_zip, members)
    return source_zip


def kit_readme(source_zip_name: str, source_sha: str, manifest_sha: str) -> bytes:
    return f"""# CheeseCutter Linux Build Kit

This build kit provides the canonical {RELEASE_NAME} source and public Linux
build instructions. Linux binary compatibility remains distribution-specific.

The source archive is frozen and identified by SHA-256:

- Source ZIP: {source_zip_name}
- Source ZIP SHA-256: {source_sha}
- Source manifest SHA-256: {manifest_sha}

Extract the source archive into a clean neutral directory and build it
unchanged. Keep generated build output outside the extracted source when
possible. No installer, signing identity, or publishing step is provided.

Inspect dependencies, privacy, ABI, and runtime behaviour before distributing
a Linux binary.
""".encode("utf-8")


def source_sha_text(source_zip_name: str, source_sha: str,
        manifest_sha: str) -> bytes:
    return f"""Release: {RELEASE_NAME}
Source ZIP: {source_zip_name}
Source ZIP SHA-256: {source_sha}
Source manifest SHA-256: {manifest_sha}
""".encode("utf-8")


def create_linux_kit(project_root: Path, output: Path,
        release_label: str = DEFAULT_RELEASE_LABEL) -> Path:
    source_zip_name, _ = source_archive_names(release_label)
    source_zip = output / source_zip_name
    if not source_zip.is_file():
        raise ReleaseError(f"missing canonical source ZIP: {source_zip}")
    # Verify and privacy-scan the source archive's uncompressed members.
    # Searching compressed bytes for short identity tokens has no token
    # semantics and can produce random false positives.
    verify_source_zip(project_root, output, release_label)
    source_data = source_zip.read_bytes()
    source_sha = sha256_bytes(source_data)
    manifest_sha = sha256_file(project_root / MANIFEST_PATH)
    members = [
        (f"{LINUX_KIT_TOP}/README.md",
            kit_readme(source_zip_name, source_sha, manifest_sha),
            FILE_MODE),
        (f"{LINUX_KIT_TOP}/SOURCE_SHA256.txt",
            source_sha_text(source_zip_name, source_sha, manifest_sha), FILE_MODE),
        (f"{LINUX_KIT_TOP}/source/{source_zip_name}", source_data, FILE_MODE),
        (f"{LINUX_KIT_TOP}/linux/BUILD.md",
            (project_root / "release/linux/BUILD.md").read_bytes(), FILE_MODE),
    ]
    scan_private_values(project_root, [], {
        member: data for member, data, _ in members
        if not member.endswith(f"/{source_zip_name}")
    })
    kit_zip = output / LINUX_KIT_ZIP_NAME
    write_zip(kit_zip, members)
    return kit_zip


def verify_zip_metadata(archive: zipfile.ZipFile) -> None:
    if archive.comment:
        raise ReleaseError("archive comment is not empty")
    names = archive.namelist()
    if names != sorted(names):
        raise ReleaseError("ZIP members are not sorted")
    if len(names) != len(set(names)):
        raise ReleaseError("ZIP has duplicate members")
    for info in archive.infolist():
        pure = PurePosixPath(info.filename)
        if pure.is_absolute() or ".." in pure.parts:
            raise ReleaseError(f"unsafe ZIP member: {info.filename}")
        if info.date_time != FIXED_ZIP_TIMESTAMP:
            raise ReleaseError(f"non-deterministic timestamp: {info.filename}")
        mode = (info.external_attr >> 16) & 0o777
        if mode not in {FILE_MODE, EXECUTABLE_MODE}:
            raise ReleaseError(f"unexpected mode {mode:o}: {info.filename}")
        if info.filename.endswith("/"):
            raise ReleaseError(f"directory entries are not stored: {info.filename}")
        if "__MACOSX" in pure.parts or pure.name == ".DS_Store" or pure.name.startswith("._"):
            raise ReleaseError(f"forbidden metadata member: {info.filename}")


def verify_source_zip(project_root: Path, output: Path,
        release_label: str = DEFAULT_RELEASE_LABEL) -> None:
    source_zip_name, source_top = source_archive_names(release_label)
    relpaths = load_source_files(project_root)
    expected = [f"{source_top}/{rel}" for rel in relpaths]
    expected.append(f"{source_top}/{SOURCE_MANIFEST_NAME}")
    source_zip = output / source_zip_name
    if not source_zip.is_file():
        raise ReleaseError(f"missing source ZIP: {source_zip}")
    with zipfile.ZipFile(source_zip) as archive:
        verify_zip_metadata(archive)
        names = archive.namelist()
        if sorted({name.split("/")[0] for name in names}) != [source_top]:
            raise ReleaseError("source ZIP must contain exactly one top-level directory")
        if names != sorted(expected):
            missing = sorted(set(expected) - set(names))
            extra = sorted(set(names) - set(expected))
            raise ReleaseError(f"source ZIP member mismatch; missing={missing} extra={extra}")
        manifest = archive.read(f"{source_top}/{SOURCE_MANIFEST_NAME}")
        if manifest != source_manifest(project_root, relpaths):
            raise ReleaseError("SOURCE_MANIFEST.sha256 content mismatch")
        generated_forbidden = [
            name for name in names
            if path_is_forbidden(str(PurePosixPath(name).relative_to(source_top)))
        ]
        if generated_forbidden:
            raise ReleaseError(f"forbidden source members: {generated_forbidden}")
        scan_private_values(project_root, [], {
            name: archive.read(name) for name in names
        })


def verify_linux_kit(project_root: Path, output: Path,
        release_label: str = DEFAULT_RELEASE_LABEL) -> None:
    source_zip_name, _ = source_archive_names(release_label)
    kit_zip = output / LINUX_KIT_ZIP_NAME
    source_zip = output / source_zip_name
    if not kit_zip.is_file():
        raise ReleaseError(f"missing Linux build kit: {kit_zip}")
    if not source_zip.is_file():
        raise ReleaseError(f"missing canonical source ZIP: {source_zip}")
    verify_source_zip(project_root, output, release_label)
    source_data = source_zip.read_bytes()
    source_sha = sha256_bytes(source_data)
    manifest_sha = sha256_file(project_root / MANIFEST_PATH)
    expected = sorted([
        f"{LINUX_KIT_TOP}/README.md",
        f"{LINUX_KIT_TOP}/SOURCE_SHA256.txt",
        f"{LINUX_KIT_TOP}/source/{source_zip_name}",
        f"{LINUX_KIT_TOP}/linux/BUILD.md",
    ])
    with zipfile.ZipFile(kit_zip) as archive:
        verify_zip_metadata(archive)
        names = archive.namelist()
        if sorted({name.split("/")[0] for name in names}) != [LINUX_KIT_TOP]:
            raise ReleaseError("Linux kit must contain exactly one top-level directory")
        if names != expected:
            raise ReleaseError("Linux kit member set mismatch")
        if archive.read(f"{LINUX_KIT_TOP}/source/{source_zip_name}") != source_data:
            raise ReleaseError("embedded source ZIP differs from canonical source ZIP")
        expected_sha = source_sha_text(source_zip_name, source_sha, manifest_sha)
        if archive.read(f"{LINUX_KIT_TOP}/SOURCE_SHA256.txt") != expected_sha:
            raise ReleaseError("SOURCE_SHA256.txt content mismatch")
        for name in names:
            rel = PurePosixPath(name).relative_to(LINUX_KIT_TOP)
            if len(rel.parts) == 1 and rel.name in {"ccutter", "ct2util"}:
                raise ReleaseError(f"Linux kit contains executable: {name}")
            if rel.parts and rel.parts[0] in {"macOS", "windows"}:
                raise ReleaseError(f"Linux kit contains unrelated platform folder: {name}")
        scan_private_values(project_root, [], {
            name: archive.read(name) for name in names
            if not name.endswith(f"/{source_zip_name}")
        })


def run(kind: str, project_root: Path, output: Path,
        release_label: str = DEFAULT_RELEASE_LABEL) -> None:
    project_root = project_root.resolve()
    output = (project_root / output).resolve() if not output.is_absolute() else output
    if not project_root.is_dir():
        raise ReleaseError(f"project root does not exist: {project_root}")
    if kind in {"source", "all"}:
        path = create_source_zip(project_root, output, release_label)
        print(f"source ZIP: {path}")
        print(f"source ZIP SHA-256: {sha256_file(path)}")
    if kind in {"linux-build-kit", "all"}:
        path = create_linux_kit(project_root, output, release_label)
        print(f"Linux build kit ZIP: {path}")
        print(f"Linux build kit SHA-256: {sha256_file(path)}")
    if kind in {"verify-source", "all"}:
        verify_source_zip(project_root, output, release_label)
        print("source ZIP verification passed")
    if kind in {"verify-linux-kit", "all"}:
        verify_linux_kit(project_root, output, release_label)
        print("Linux build kit verification passed")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create deterministic anonymous CheeseCutter source archives."
    )
    parser.add_argument("--project-root", default=".")
    parser.add_argument("--output", default="build/release")
    parser.add_argument("--release-label", default=DEFAULT_RELEASE_LABEL)
    parser.add_argument("--kind", choices=("source", "linux-build-kit", "all",
        "verify-source", "verify-linux-kit"), default="all")
    args = parser.parse_args()
    try:
        run(args.kind, Path(args.project_root), Path(args.output),
            args.release_label)
    except ReleaseError as error:
        print(f"create_source_release.py: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
