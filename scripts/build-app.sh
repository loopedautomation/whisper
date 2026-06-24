#!/usr/bin/env bash
# Builds Looped Whisper as a proper macOS .app via Xcode (xcodebuild), then
# codesigns it. Building with Xcode (rather than `swift build` + hand-assembly)
# is required so SwiftPM dependency resource bundles (KeyboardShortcuts, etc.)
# are embedded into Contents/Resources where `Bundle.module` can find them —
# otherwise the app traps (EXC_BREAKPOINT) the moment that code runs.
set -euo pipefail

CONFIG_ARG="${1:-release}"
case "$CONFIG_ARG" in
    debug) CONFIGURATION="Debug" ;;
    *)     CONFIGURATION="Release" ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXEC_NAME="LoopedWhisper"
APP="$ROOT/build/LoopedWhisper.app"
DERIVED="$ROOT/build/DerivedData"

# 1. App icon (generate .icns from the source PNG so xcodebuild can embed it).
if [[ -f "$ROOT/Resources/AppIcon.png" ]]; then
    "$ROOT/scripts/make-icon.sh" >/dev/null || true
fi

# 2. Generate the Xcode project from project.yml.
echo "▶ Generating Xcode project…"
( cd "$ROOT" && xcodegen generate --quiet )

# 3. Build (without signing — we sign separately below so the same logic works
#    for the local self-signed identity and the CI Developer ID).
echo "▶ Building ($CONFIGURATION) with xcodebuild…"
xcodebuild \
    -project "$ROOT/LoopedWhisper.xcodeproj" \
    -scheme LoopedWhisper \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO \
    build | (xcbeautify 2>/dev/null || cat) | tail -5

BUILT_APP="$DERIVED/Build/Products/$CONFIGURATION/LoopedWhisper.app"
[[ -d "$BUILT_APP" ]] || { echo "✗ Build product not found at $BUILT_APP"; exit 1; }

echo "▶ Staging $APP …"
rm -rf "$APP"
mkdir -p "$ROOT/build"
cp -R "$BUILT_APP" "$APP"

# 4. Version is single-sourced from package.json (managed by changesets).
if [[ -f "$ROOT/package.json" ]]; then
    VERSION="$(python3 -c "import json;print(json.load(open('$ROOT/package.json'))['version'])")"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
    echo "▶ Version $VERSION (from package.json)"
fi

# 5. Codesign. Hardened runtime + audio-input entitlement (required for the mic
#    prompt). Use a STABLE identity if available (WHISPER_SIGN_ID or
#    scripts/dev-cert.sh) so TCC grants persist; fall back to ad-hoc.
SIGN_ID="${WHISPER_SIGN_ID:-Looped Whisper Dev}"
SIGN_FLAGS=()
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
    IDENTITY="$SIGN_ID"
    echo "▶ Codesigning with stable identity: $IDENTITY"
    # Notarization REQUIRES a secure timestamp (Developer ID only).
    if [[ "$IDENTITY" == *"Developer ID"* ]]; then
        SIGN_FLAGS+=(--timestamp)
        echo "  (adding secure timestamp for notarization)"
    fi
else
    IDENTITY="-"
    echo "▶ Codesigning (ad-hoc — run scripts/dev-cert.sh for persistent permissions)"
fi

# Sign nested resource bundles first, then the app (inside-out).
shopt -s nullglob
for nested in "$APP/Contents/Resources/"*.bundle; do
    codesign --force --sign "$IDENTITY" ${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"} "$nested"
done
shopt -u nullglob
codesign --force --sign "$IDENTITY" \
    --options runtime \
    ${SIGN_FLAGS[@]+"${SIGN_FLAGS[@]}"} \
    --entitlements "$ROOT/Resources/LoopedWhisper.entitlements" \
    "$APP"

echo "✓ Built $APP"
echo "  Run with: open \"$APP\"   (or: \"$APP/Contents/MacOS/$EXEC_NAME\" for logs)"
