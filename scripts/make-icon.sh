#!/usr/bin/env bash
# Generates Resources/AppIcon.icns from a 1024x1024 source PNG.
# Source: Resources/AppIcon.png  →  Output: Resources/AppIcon.icns
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Resources/AppIcon.png"
ICNS="$ROOT/Resources/AppIcon.icns"

if [[ ! -f "$SRC" ]]; then
    echo "✗ No source icon at $SRC"
    echo "  Save your 1024x1024 PNG there, then run: ./scripts/make-icon.sh"
    exit 1
fi

WORK="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$WORK"

# macOS iconset sizes (point size @1x and @2x).
gen() { sips -z "$2" "$2" "$SRC" --out "$WORK/icon_${1}.png" >/dev/null; }
gen 16x16        16
gen 16x16@2x     32
gen 32x32        32
gen 32x32@2x     64
gen 128x128     128
gen 128x128@2x  256
gen 256x256     256
gen 256x256@2x  512
gen 512x512     512
gen 512x512@2x 1024

iconutil -c icns "$WORK" -o "$ICNS"
echo "✓ Wrote $ICNS"
