#!/usr/bin/env bash
# Builds standalone executables for Windows, macOS and Linux (spec 25). Needs `godot` on PATH and the matching
# export templates installed (Editor -> Manage Export Templates).
set -euo pipefail
cd "$(dirname "$0")"

GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null 2>&1; then
  if [ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
    GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
  else
    echo "ERROR: godot not found on PATH (set GODOT=/path/to/godot)" >&2
    exit 1
  fi
fi
echo "Using $($GODOT --version)"

mkdir -p build/windows build/macos build/linux
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

fail=0
export_one() {
  local preset="$1" out="$2"
  echo "==> exporting $preset -> $out"
  if ! "$GODOT" --headless --path . --export-release "$preset" "$out"; then
    echo "ERROR: export of preset '$preset' failed (are the export templates installed?)" >&2
    fail=1
  fi
}

export_one "Windows" "build/windows/MedievalMadness.exe"
export_one "macOS" "build/macos/MedievalMadness.zip"
export_one "Linux" "build/linux/MedievalMadness.x86_64"

# unpack the macOS app next to the zip so it can be started directly
if [ -f build/macos/MedievalMadness.zip ]; then
  rm -rf "build/macos/Medieval Madness.app"
  unzip -q -o build/macos/MedievalMadness.zip -d build/macos
  echo "macOS app: build/macos/Medieval Madness.app"
fi

echo
echo "Sizes:"
for f in build/windows/MedievalMadness.exe build/macos/MedievalMadness.zip build/linux/MedievalMadness.x86_64; do
  if [ -f "$f" ]; then
    printf '  %-45s %s\n' "$f" "$(du -h "$f" | cut -f1)"
  else
    printf '  %-45s MISSING\n' "$f"
    fail=1
  fi
done
exit $fail
