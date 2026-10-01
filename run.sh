#!/usr/bin/env bash
# Launch from source: godot --path .   (extra args are forwarded, e.g. ./run.sh -- --debug)
cd "$(dirname "$0")"
GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null 2>&1 && [ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
  GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
fi
exec "$GODOT" --path . "$@"
