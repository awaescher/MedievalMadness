#!/usr/bin/env bash
# Builds standalone executables for Windows, macOS and Linux (spec 25). Needs `godot` on PATH and the matching
# export templates installed (Editor -> Manage Export Templates).
set -euo pipefail
cd "$(dirname "$0")"

# every build gets a new patch number (1.10.0 -> 1.10.1 ...), shown in the menu and sent when joining online
IFS=. read -r V_MAJOR V_MINOR V_PATCH <<< "$(tr -d '[:space:]' < VERSION)"
# CI: MM_BUILD_NUMBER (e.g. GITHUB_RUN_NUMBER) replaces the local patch counter
if [ -n "${MM_BUILD_NUMBER:-}" ]; then V_PATCH=$((MM_BUILD_NUMBER - 1)); fi
echo "$V_MAJOR.$V_MINOR.$((V_PATCH + 1))" > VERSION
VER="$(cat VERSION)"
echo "Version $VER"
# the export presets carry the version too (macOS Finder shows it, also Windows file properties, iOS, Android)
sed -i.bak -E \
  -e "s/^(application\/(short_)?version=)\"[^\"]*\"/\1\"$VER\"/" \
  -e "s/^(version\/name=)\"[^\"]*\"/\1\"$VER\"/" \
  -e "s/^(version\/code=)[0-9]+/\1$((V_MAJOR * 10000 + V_MINOR * 100 + V_PATCH + 1))/" \
  -e "s/^(application\/(file|product)_version=)\"[^\"]*\"/\1\"$VER.0\"/" export_presets.cfg
rm -f export_presets.cfg.bak

# the in-game relay help (copy buttons) ships the relay spec and template as text files
mkdir -p assets/relay_help
cp relay/PROTOCOL.md assets/relay_help/spec.txt
cp relay/template/relay_node.mjs assets/relay_help/relay_node.txt
cp relay/template/check.mjs assets/relay_help/check.txt

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

mkdir -p build/windows build/macos build/linux build/windows-arm64 build/linux-arm64
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
export_one "Windows ARM" "build/windows-arm64/MedievalMadness.exe"
export_one "Linux ARM" "build/linux-arm64/MedievalMadness.arm64"

# optional: Xcode project for iOS (IOS=1 ./export.sh); the .ipa step of Godot needs the iOS platform component of Xcode
if [ "${IOS:-0}" = "1" ]; then
  mkdir -p build/ios
  echo "==> exporting iOS Xcode project -> build/ios"
  "$GODOT" --headless --path . --export-debug "iOS" build/ios/MedievalMadness.ipa || echo "(the Xcode project in build/ios is still usable; open MedievalMadness.xcodeproj)"
fi

# unpack the macOS app next to the zip so it can be started directly
if [ -f build/macos/MedievalMadness.zip ]; then
  rm -rf "build/macos/Medieval Madness.app"
  unzip -q -o build/macos/MedievalMadness.zip -d build/macos
  echo "macOS app: build/macos/Medieval Madness.app"
fi

# optional: a DEBUG macOS build that prints a script backtrace when the engine crashes (DEBUG=1 ./export.sh)
if [ "${DEBUG:-0}" = "1" ]; then
  mkdir -p build/macos-debug
  echo "==> exporting macOS debug build -> build/macos-debug"
  "$GODOT" --headless --path . --export-debug "macOS" build/macos-debug/MedievalMadness.zip && unzip -q -o build/macos-debug/MedievalMadness.zip -d build/macos-debug \
    && echo "run it from a terminal:  build/macos-debug/\"Medieval Madness.app\"/Contents/MacOS/\"Medieval Madness\" 2>&1 | tee crash.log"
fi

echo
echo "Sizes:"
for f in build/windows/MedievalMadness.exe build/macos/MedievalMadness.zip build/linux/MedievalMadness.x86_64 build/windows-arm64/MedievalMadness.exe build/linux-arm64/MedievalMadness.arm64; do
  if [ -f "$f" ]; then
    printf '  %-45s %s\n' "$f" "$(du -h "$f" | cut -f1)"
  else
    printf '  %-45s MISSING\n' "$f"
    fail=1
  fi
done
exit $fail
