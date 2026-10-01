#!/usr/bin/env bash
# Usage: tools/release.sh <major.minor.patch> "Short release note"
# Bumps the version everywhere (VERSION file -> shown in the main menu, macOS bundle version), commits everything and
# creates the git tag vX.Y.Z. Run from anywhere; it works inside this project folder's repository.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ $# -lt 1 ]; then echo "usage: tools/release.sh X.Y.Z [note]" >&2; exit 1; fi
VER="$1"; NOTE="${2:-Release $1}"
if ! [[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "version must look like 1.2.3" >&2; exit 1; fi
echo "$VER" > VERSION
sed -i.bak -E "s/^application\/short_version=.*/application\/short_version=\"$VER\"/; s/^application\/version=.*/application\/version=\"$VER\"/" export_presets.cfg
rm -f export_presets.cfg.bak
git add -A .
git -C .. add -A .
git -C .. commit -q -m "v$VER: $NOTE

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
git -C .. tag -a "v$VER" -m "v$VER: $NOTE"
echo "committed and tagged v$VER (the game shows it in the main menu after the next ./export.sh or ./run.sh)"
