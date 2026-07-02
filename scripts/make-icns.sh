#!/usr/bin/env bash
# Build Assets/AppIcon.icns from the generated iconset (macOS only — needs iconutil).
#
# Regenerate the PNGs first with:  python3 Assets/Icon/generate_icon.py
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICONSET="$ROOT/Assets/AppIcon.iconset"
OUT="$ROOT/Assets/AppIcon.icns"

if [[ ! -d "$ICONSET" ]]; then
	echo "error: $ICONSET not found. Run: python3 Assets/Icon/generate_icon.py" >&2
	exit 1
fi

if ! command -v iconutil >/dev/null 2>&1; then
	echo "error: iconutil not found (macOS only)." >&2
	exit 1
fi

iconutil -c icns "$ICONSET" -o "$OUT"
echo "Wrote $OUT"
