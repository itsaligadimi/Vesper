#!/usr/bin/env bash
# Build Vesper.app on a Mac with Xcode or the Swift command-line tools.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$ROOT/.." && pwd)"
cd "$ROOT"

if ! command -v swift >/dev/null; then
  echo "Swift is not installed. Install Xcode or the Command Line Tools, then run this again." >&2
  exit 1
fi

echo "Compiling…"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="$BIN_DIR/Vesper"
if [[ ! -x "$BIN" ]]; then
  echo "Build finished without a Vesper binary at $BIN" >&2
  exit 1
fi

APP="$ROOT/dist/Vesper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Vesper"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
ICON="$ROOT/Support/AppIcon.icns"
if [[ ! -f "$ICON" && -f "$ROOT/Support/AppIcon.png" ]] && command -v iconutil >/dev/null && command -v sips >/dev/null; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ROOT/Support/AppIcon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$ROOT/Support/AppIcon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$ICON"
fi
if [[ -f "$ICON" ]]; then
  cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
fi

echo "Copying catalog (stills, thumbnails, and loops)…"
mkdir -p "$APP/Contents/Resources/catalog"
cp -R "$REPO/catalog/." "$APP/Contents/Resources/catalog/"

if command -v codesign >/dev/null; then
  codesign --force --deep --sign - "$APP" || true
fi

echo "Built $APP"
echo "Drag it to /Applications, then open it. The first launch may need a right-click → Open."
