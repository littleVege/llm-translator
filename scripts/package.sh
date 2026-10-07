#!/bin/bash
# Builds the release binary and wraps it into dist/LLM Translator.app.
# Set CODESIGN_IDENTITY to a real identity for a stable signature
# (avoids re-granting Accessibility after every rebuild); defaults to ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="LLM Translator"
BUNDLE="dist/$APP_NAME.app"

# Regenerate the app icon from icon.png when it is missing or out of date.
if [ -f icon.png ] && { [ ! -f Support/AppIcon.icns ] || [ icon.png -nt Support/AppIcon.icns ]; }; then
	echo "Generating AppIcon.icns from icon.png"
	ICONSET="$(mktemp -d)/AppIcon.iconset"
	mkdir -p "$ICONSET"
	sips -z 16   16   icon.png --out "$ICONSET/icon_16x16.png"      >/dev/null
	sips -z 32   32   icon.png --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
	sips -z 32   32   icon.png --out "$ICONSET/icon_32x32.png"      >/dev/null
	sips -z 64   64   icon.png --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
	sips -z 128  128  icon.png --out "$ICONSET/icon_128x128.png"    >/dev/null
	sips -z 256  256  icon.png --out "$ICONSET/icon_128x128@2x.png" >/dev/null
	sips -z 256  256  icon.png --out "$ICONSET/icon_256x256.png"    >/dev/null
	sips -z 512  512  icon.png --out "$ICONSET/icon_256x256@2x.png" >/dev/null
	sips -z 512  512  icon.png --out "$ICONSET/icon_512x512.png"    >/dev/null
	sips -z 1024 1024 icon.png --out "$ICONSET/icon_512x512@2x.png" >/dev/null
	iconutil -c icns "$ICONSET" -o Support/AppIcon.icns
	rm -rf "$(dirname "$ICONSET")"
fi

swift build -c release

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp .build/release/LLMTranslator "$BUNDLE/Contents/MacOS/"
cp Support/Info.plist "$BUNDLE/Contents/"
[ -f Support/AppIcon.icns ] && cp Support/AppIcon.icns "$BUNDLE/Contents/Resources/"

codesign --force --sign "${CODESIGN_IDENTITY:--}" "$BUNDLE"

echo "Built $BUNDLE"
