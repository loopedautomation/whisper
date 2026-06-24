#!/usr/bin/env bash
# Builds the Looped Whisper executable with SwiftPM and assembles a macOS .app
# bundle (with the LSUIElement Info.plist) so it runs as a menu-bar agent app.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXEC_NAME="LoopedWhisper"          # SwiftPM product / Mach-O binary name
BUNDLE_NAME="LoopedWhisper"        # .app filename (display name comes from Info.plist)
APP="$ROOT/build/$BUNDLE_NAME.app"

echo "▶ Building ($CONFIG)…"
swift build -c "$CONFIG" --package-path "$ROOT"

BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/$EXEC_NAME"

echo "▶ Assembling $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXEC_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Version is single-sourced from package.json (managed by changesets); stamp it
# into the bundle so the app reports the same version as the changelog.
if [[ -f "$ROOT/package.json" ]]; then
    VERSION="$(python3 -c "import json;print(json.load(open('$ROOT/package.json'))['version'])")"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
    echo "▶ Version $VERSION (from package.json)"
fi

# App icon: regenerate .icns from the source PNG if present, then bundle it.
if [[ -f "$ROOT/Resources/AppIcon.png" ]]; then
    "$ROOT/scripts/make-icon.sh" >/dev/null || true
fi
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
    echo "⚠ No Resources/AppIcon.png — bundling without a custom app icon."
fi

# Codesign so TCC permissions (mic, accessibility, input monitoring) and
# SMAppService behave. The audio-input entitlement is REQUIRED under the
# hardened runtime for the microphone request to appear at all.
#
# Use a STABLE signing identity if available (set WHISPER_SIGN_ID or run
# scripts/dev-cert.sh) so Accessibility / Input Monitoring grants persist across
# rebuilds. Falls back to ad-hoc (`-`), where grants must be re-done each build.
SIGN_ID="${WHISPER_SIGN_ID:-Looped Whisper Dev}"
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
    IDENTITY="$SIGN_ID"
    echo "▶ Codesigning with stable identity: $IDENTITY"
else
    IDENTITY="-"
    echo "▶ Codesigning (ad-hoc — run scripts/dev-cert.sh for persistent permissions)"
fi
codesign --force --deep --sign "$IDENTITY" \
    --options runtime \
    --entitlements "$ROOT/Resources/LoopedWhisper.entitlements" \
    "$APP"

echo "✓ Built $APP"
echo "  Run with: open \"$APP\"   (or: \"$APP/Contents/MacOS/$EXEC_NAME\" for logs)"
