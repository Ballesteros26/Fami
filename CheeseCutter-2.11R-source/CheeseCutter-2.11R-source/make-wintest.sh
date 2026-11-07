#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")"
target="${1:-test}"
case "$target" in
	all|gui|ct2util|test|verify|verify-privacy|clean|toolchain-info)
		;;
	*)
		echo "Unsupported Windows target: $target" >&2
		echo "Supported targets: all gui ct2util test verify verify-privacy clean toolchain-info" >&2
		exit 2
		;;
esac

for tool in make.exe cl.exe rc.exe lib.exe; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		echo "$tool is unavailable; initialise MSYS2 UCRT64 and the Microsoft x64 developer environment." >&2
		exit 1
	fi
done

python=python3
if ! command -v "$python" >/dev/null 2>&1; then
	python=python
fi
if ! command -v "$python" >/dev/null 2>&1; then
	echo "Python 3 is unavailable in PATH." >&2
	exit 1
fi

exec make.exe -f Makefile.win "PYTHON=$python" "$target"
