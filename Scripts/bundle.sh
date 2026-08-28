#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP="$ROOT/build/LoudOrNot.app"
BUNDLE_ID="com.cmorss.loudornot"

swift build -c "$CONFIG" --package-path "$ROOT"
BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/LoudOrNot" "$APP/Contents/MacOS/LoudOrNot"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Prefer the stable self-signed identity, which keeps the microphone permission
# across rebuilds. Fall back to ad-hoc so the build still works without it.
IDENTITY_NAME="Loud or Not Local Signing"
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY_NAME"; then
    SIGNER="$IDENTITY_NAME"
else
    SIGNER="-"
    echo "No signing identity found; using an ad-hoc signature."
    echo "Run 'make identity' to stop macOS asking for the microphone after every build."
fi

codesign --force --sign "$SIGNER" --identifier "$BUNDLE_ID" "$APP"

echo "Built $APP"
