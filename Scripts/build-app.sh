#!/usr/bin/env bash
# Build wInstaller.app, a real macOS application bundle, from the SwiftPM
# executable target. macOS only.
#
# Usage: Scripts/build-app.sh [output-dir]
# Result: <output-dir>/wInstaller.app  (default output-dir: ./build)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$ROOT/build}"
APP="$OUT_DIR/wInstaller.app"
CONTENTS="$APP/Contents"
BIN_NAME="WInstallerApp"

echo "==> Building release binary"
swift build -c release --package-path "$ROOT"
BIN_PATH="$(swift build -c release --package-path "$ROOT" --show-bin-path)/$BIN_NAME"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_PATH" "$CONTENTS/MacOS/$BIN_NAME"
cp "$ROOT/Sources/WInstallerApp/Info.plist" "$CONTENTS/Info.plist"

# App icon: build the .icns if missing (needs the generated iconset).
if [[ ! -f "$ROOT/Assets/AppIcon.icns" ]]; then
	echo "==> Building AppIcon.icns"
	"$ROOT/Scripts/make-icns.sh" || echo "warning: could not build AppIcon.icns; app will use the default icon"
fi
if [[ -f "$ROOT/Assets/AppIcon.icns" ]]; then
	cp "$ROOT/Assets/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
fi

# PkgInfo (optional but conventional).
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Ad-hoc code sign so the app launches locally. Replace "-" with a Developer ID
# identity for distribution, then notarize.
if command -v codesign >/dev/null 2>&1; then
	echo "==> Ad-hoc signing"
	codesign --force --deep --sign - "$APP" || echo "warning: ad-hoc signing failed"
fi

echo "==> Done: $APP"
echo "    Open with: open \"$APP\""
