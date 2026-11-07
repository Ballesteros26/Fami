#!/usr/bin/env python3
"""Generate CheeseCutter desktop icons from the canonical 2048 PNG source."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile

SCRIPT_VERSION = 1
DEFAULT_SOURCE_PATH = "icons/cc2048.png"
DEFAULT_OUTPUT_ROOT = "build/desktop-icons"
REQUIRED_SOURCE_SIZE = 2048

MACOS_ICONSET_FILES = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]
WINDOWS_ICON_SIZES = [16, 24, 32, 48, 64, 128, 256]
LINUX_ICON_SIZES = [16, 24, 32, 48, 64, 128, 256, 512]
PLATFORMS = ["macos", "windows", "linux"]


class IconGenerationError(Exception):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate desktop icons from icons/cc2048.png."
    )
    parser.add_argument("--source", default=DEFAULT_SOURCE_PATH)
    parser.add_argument("--output", default=DEFAULT_OUTPUT_ROOT)
    parser.add_argument(
        "--platform",
        choices=PLATFORMS + ["all"],
        default="all",
        help="platform icon set to generate or verify",
    )
    parser.add_argument(
        "--verify",
        action="store_true",
        help="verify generated outputs after generation",
    )
    return parser.parse_args()


def selected_platforms(platform: str) -> list[str]:
    return PLATFORMS[:] if platform == "all" else [platform]


def relpath(path: Path, base: Path) -> str:
    try:
        return path.resolve().relative_to(base.resolve()).as_posix()
    except ValueError as error:
        raise IconGenerationError(
            f"{path} is outside the project tree; manifest paths must be relative"
        ) from error


def png_dimensions(path: Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        header = handle.read(24)
    if len(header) < 24 or not header.startswith(b"\x89PNG\r\n\x1a\n"):
        raise IconGenerationError(f"{path} is not a PNG file")
    return struct.unpack(">II", header[16:24])


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_source(source: Path) -> tuple[int, int, str]:
    if not source.is_file():
        raise IconGenerationError(f"Missing canonical icon source: {source}")
    width, height = png_dimensions(source)
    if width != REQUIRED_SOURCE_SIZE or height != REQUIRED_SOURCE_SIZE:
        raise IconGenerationError(
            "icons/cc2048.png must remain a 2048x2048 PNG. Changing the "
            "canonical dimensions requires an explicit project decision."
        )
    if width != height:
        raise IconGenerationError("Canonical desktop icon source must be square")
    return width, height, sha256(source)


def select_backend() -> str:
    if shutil.which("sips"):
        return "sips"
    try:
        import PIL.Image  # noqa: F401

        return "pillow"
    except Exception:
        pass
    if shutil.which("magick"):
        return "magick"
    if shutil.which("convert"):
        return "convert"
    raise IconGenerationError(
        "No resize backend found. Install sips, Pillow, ImageMagick magick, "
        "or ImageMagick convert."
    )


def atomic_output_path(output: Path) -> Path:
	output.parent.mkdir(parents=True, exist_ok=True)
	return output.with_name(f".{output.stem}.tmp{output.suffix}")


def render_png(source: Path, output: Path, size: int, backend: str) -> None:
    tmp = atomic_output_path(output)
    try:
        if backend == "sips":
            subprocess.run(
                [
                    "sips",
                    "-s",
                    "format",
                    "png",
                    "-z",
                    str(size),
                    str(size),
                    str(source),
                    "--out",
                    str(tmp),
                ],
                stdout=subprocess.DEVNULL,
                check=True,
            )
        elif backend == "pillow":
            from PIL import Image

            with Image.open(source) as image:
                resample = getattr(Image, "Resampling", Image).LANCZOS
                resized = image.resize((size, size), resample)
                resized.save(tmp, format="PNG")
        elif backend == "magick":
            subprocess.run(
                ["magick", str(source), "-resize", f"{size}x{size}", str(tmp)],
                stdout=subprocess.DEVNULL,
                check=True,
            )
        elif backend == "convert":
            subprocess.run(
                ["convert", str(source), "-resize", f"{size}x{size}", str(tmp)],
                stdout=subprocess.DEVNULL,
                check=True,
            )
        else:
            raise IconGenerationError(f"Unsupported resize backend: {backend}")

        actual = png_dimensions(tmp)
        if actual != (size, size):
            raise IconGenerationError(
                f"{output} expected {size}x{size}, got {actual[0]}x{actual[1]}"
            )
        os.replace(tmp, output)
    finally:
        if tmp.exists():
            tmp.unlink()


def generate_macos(source: Path, output_root: Path, backend: str) -> dict:
    iconset = output_root / "macos" / "ct.iconset"
    iconset.mkdir(parents=True, exist_ok=True)
    pngs = []
    for filename, size in MACOS_ICONSET_FILES:
        output = iconset / filename
        render_png(source, output, size, backend)
        pngs.append({"path": relpath(output, Path.cwd()), "size": size})

    icns = output_root / "macos" / "ct.icns"
    tmp = atomic_output_path(icns)
    try:
        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset), "-o", str(tmp)],
            stdout=subprocess.DEVNULL,
            check=True,
        )
        os.replace(tmp, icns)
    except FileNotFoundError as error:
        raise IconGenerationError("iconutil is required to generate macOS .icns") from error
    finally:
        if tmp.exists():
            tmp.unlink()
    return {
        "iconset": relpath(iconset, Path.cwd()),
        "icns": relpath(icns, Path.cwd()),
        "pngs": pngs,
    }


def write_ico(png_entries: list[tuple[int, Path]], output: Path) -> None:
    payloads = [(size, path.read_bytes()) for size, path in png_entries]
    offset = 6 + 16 * len(payloads)
    directory = []
    for size, payload in payloads:
        dimension = 0 if size == 256 else size
        directory.append(
            struct.pack(
                "<BBBBHHII",
                dimension,
                dimension,
                0,
                0,
                1,
                32,
                len(payload),
                offset,
            )
        )
        offset += len(payload)

    tmp = atomic_output_path(output)
    tmp.write_bytes(
        struct.pack("<HHH", 0, 1, len(payloads))
        + b"".join(directory)
        + b"".join(payload for _, payload in payloads)
    )
    os.replace(tmp, output)


def generate_windows(source: Path, output_root: Path, backend: str) -> dict:
    png_dir = output_root / "windows" / "png"
    png_dir.mkdir(parents=True, exist_ok=True)
    png_entries = []
    pngs = []
    for size in WINDOWS_ICON_SIZES:
        output = png_dir / f"icon_{size}.png"
        render_png(source, output, size, backend)
        png_entries.append((size, output))
        pngs.append({"path": relpath(output, Path.cwd()), "size": size})

    ico = output_root / "windows" / "cheesecutter.ico"
    write_ico(png_entries, ico)
    return {"ico": relpath(ico, Path.cwd()), "pngs": pngs}


def generate_linux(source: Path, output_root: Path, backend: str) -> dict:
    pngs = []
    for size in LINUX_ICON_SIZES:
        output = (
            output_root
            / "linux"
            / "hicolor"
            / f"{size}x{size}"
            / "apps"
            / "cheesecutter.png"
        )
        render_png(source, output, size, backend)
        pngs.append({"path": relpath(output, Path.cwd()), "size": size})
    return {"pngs": pngs}


def build_manifest(
    source: Path,
    output_root: Path,
    backend: str,
    source_width: int,
    source_height: int,
    source_sha: str,
    platforms: list[str],
    outputs: dict,
) -> dict:
    return {
        "script_version": SCRIPT_VERSION,
        "backend": backend,
        "source": {
            "path": relpath(source, Path.cwd()),
            "sha256": source_sha,
            "width": source_width,
            "height": source_height,
        },
        "output_root": relpath(output_root, Path.cwd()),
        "platforms": platforms,
        "sizes": {
            "macos": [{"filename": name, "size": size} for name, size in MACOS_ICONSET_FILES],
            "windows": WINDOWS_ICON_SIZES,
            "linux": LINUX_ICON_SIZES,
        },
        "outputs": outputs,
    }


def write_manifest(output_root: Path, manifest: dict) -> None:
    path = output_root / "icon-manifest.json"
    tmp = atomic_output_path(path)
    tmp.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    os.replace(tmp, path)


def verify_png(path: Path, size: int) -> None:
    width, height = png_dimensions(path)
    if (width, height) != (size, size):
        raise IconGenerationError(
            f"{path} expected {size}x{size}, got {width}x{height}"
        )


def verify_ico(path: Path, sizes: list[int]) -> None:
    data = path.read_bytes()
    if len(data) < 6:
        raise IconGenerationError(f"{path} is too short to be an ICO file")
    reserved, icon_type, count = struct.unpack("<HHH", data[:6])
    if reserved != 0 or icon_type != 1 or count != len(sizes):
        raise IconGenerationError(f"{path} has an invalid ICO header")
    entries = []
    for index, expected_size in enumerate(sizes):
        start = 6 + index * 16
        width, height, color_count, reserved_byte, planes, bit_count, length, offset = (
            struct.unpack("<BBBBHHII", data[start : start + 16])
        )
        expected_dimension = 0 if expected_size == 256 else expected_size
        if (width, height) != (expected_dimension, expected_dimension):
            raise IconGenerationError(f"{path} entry {index} has wrong dimensions")
        if color_count != 0 or reserved_byte != 0 or planes != 1 or bit_count != 32:
            raise IconGenerationError(f"{path} entry {index} has invalid metadata")
        if offset + length > len(data):
            raise IconGenerationError(f"{path} entry {index} payload is out of bounds")
        payload = data[offset : offset + length]
        if not payload.startswith(b"\x89PNG\r\n\x1a\n"):
            raise IconGenerationError(f"{path} entry {index} is not a PNG payload")
        entries.append((offset, length))
    expected_offset = 6 + 16 * len(sizes)
    for index, (offset, length) in enumerate(entries):
        if offset != expected_offset:
            raise IconGenerationError(f"{path} entry {index} offset is not contiguous")
        expected_offset += length
    if expected_offset != len(data):
        raise IconGenerationError(f"{path} has trailing data")


def verify_macos_icns(icns: Path) -> None:
    if not icns.is_file() or icns.stat().st_size == 0:
        raise IconGenerationError(f"{icns} was not generated")
    if not shutil.which("iconutil"):
        raise IconGenerationError("iconutil is required to verify macOS .icns")
    temp_dir = Path(tempfile.mkdtemp(prefix="cheesecutter-icns-verify.", dir="/tmp"))
    try:
        expanded = temp_dir / "ct.iconset"
        subprocess.run(
            ["iconutil", "-c", "iconset", "-o", str(expanded), str(icns)],
            stdout=subprocess.DEVNULL,
            check=True,
        )
        for filename, size in MACOS_ICONSET_FILES:
            verify_png(expanded / filename, size)
    finally:
        shutil.rmtree(temp_dir)


def verify_manifest(output_root: Path, platforms: list[str]) -> None:
    manifest_path = output_root / "icon-manifest.json"
    manifest = json.loads(manifest_path.read_text())
    if any(Path(value).is_absolute() for value in collect_paths(manifest)):
        raise IconGenerationError("Manifest contains an absolute path")
    if manifest["source"]["path"] != DEFAULT_SOURCE_PATH:
        raise IconGenerationError("Manifest source path is not the canonical relative path")
    if manifest["source"]["width"] != REQUIRED_SOURCE_SIZE or manifest["source"]["height"] != REQUIRED_SOURCE_SIZE:
        raise IconGenerationError("Manifest source dimensions do not match the contract")
    if sorted(manifest["platforms"]) != sorted(platforms):
        raise IconGenerationError("Manifest platform list does not match generated platforms")


def collect_paths(value) -> list[str]:
    if isinstance(value, dict):
        result = []
        for nested in value.values():
            result.extend(collect_paths(nested))
        return result
    if isinstance(value, list):
        result = []
        for nested in value:
            result.extend(collect_paths(nested))
        return result
    if isinstance(value, str) and ("/" in value or value.endswith(".png") or value.endswith(".icns") or value.endswith(".ico")):
        return [value]
    return []


def verify_outputs(output_root: Path, platforms: list[str]) -> None:
    verify_manifest(output_root, platforms)
    if "macos" in platforms:
        iconset = output_root / "macos" / "ct.iconset"
        for filename, size in MACOS_ICONSET_FILES:
            verify_png(iconset / filename, size)
        verify_macos_icns(output_root / "macos" / "ct.icns")
    if "windows" in platforms:
        png_dir = output_root / "windows" / "png"
        for size in WINDOWS_ICON_SIZES:
            verify_png(png_dir / f"icon_{size}.png", size)
        verify_ico(output_root / "windows" / "cheesecutter.ico", WINDOWS_ICON_SIZES)
    if "linux" in platforms:
        for size in LINUX_ICON_SIZES:
            verify_png(
                output_root
                / "linux"
                / "hicolor"
                / f"{size}x{size}"
                / "apps"
                / "cheesecutter.png",
                size,
            )


def main() -> int:
    args = parse_args()
    source = Path(args.source)
    output_root = Path(args.output)
    platforms = selected_platforms(args.platform)

    try:
        source_width, source_height, source_sha = validate_source(source)
        backend = select_backend()
        outputs = {}
        if "macos" in platforms:
            outputs["macos"] = generate_macos(source, output_root, backend)
        if "windows" in platforms:
            outputs["windows"] = generate_windows(source, output_root, backend)
        if "linux" in platforms:
            outputs["linux"] = generate_linux(source, output_root, backend)
        manifest = build_manifest(
            source,
            output_root,
            backend,
            source_width,
            source_height,
            source_sha,
            platforms,
            outputs,
        )
        write_manifest(output_root, manifest)
        if args.verify:
            verify_outputs(output_root, platforms)
    except (IconGenerationError, subprocess.CalledProcessError, OSError) as error:
        print(f"generate_desktop_icons.py: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
