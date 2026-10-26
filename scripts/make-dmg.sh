#!/bin/bash
# Builds dist/LLM-Translator.dmg — a drag-to-Applications disk image.
# The image also carries a short "How to Open.txt" explaining the Gatekeeper
# step, since the app is ad-hoc signed (not notarized).
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="LLM Translator"
BUNDLE="dist/$APP_NAME.app"
DMG="dist/LLM-Translator.dmg"
VOL_NAME="LLM Translator"

# Always build a fresh app bundle first.
bash ./scripts/package.sh

STAGE_ROOT="$(mktemp -d)"
STAGE="$STAGE_ROOT/vol"
mkdir -p "$STAGE"

cp -R "$BUNDLE" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/How to Open.txt" <<'TXT'
LLM Translator — how to install
===============================

1. Drag "LLM Translator.app" onto the Applications folder shown here.

2. First open (required once, because this app isn't notarized by Apple):

   Terminal way (fastest) — paste this line into the Terminal app and press Return:

       xattr -dr com.apple.quarantine "/Applications/LLM Translator.app"

   Then open LLM Translator from Applications normally.

   Menu way (no Terminal): double-click the app, click "Done" on the warning,
   open  System Settings > Privacy & Security , scroll down, click
   "Open Anyway", then confirm with Touch ID or your password.

3. The Settings window opens on first launch — pick your provider and paste
   your API key. See the README for details.

4. If Accessibility is already enabled but selected-text translation still
   requests permission after an update: quit LLM Translator, remove its old
   entry with the minus button in System Settings > Privacy & Security >
   Accessibility, then add /Applications/LLM Translator.app with the plus
   button, enable it, and reopen the app. Ad-hoc signed builds can change the
   identity saved with the old permission. Translate Clipboard works without
   Accessibility access while you resolve this.
TXT

rm -f "$DMG"
mkdir -p dist
hdiutil create \
	-volname "$VOL_NAME" \
	-srcfolder "$STAGE" \
	-fs HFS+ \
	-format UDZO \
	-ov \
	"$DMG" >/dev/null

rm -rf "$STAGE_ROOT"

SIZE="$(du -h "$DMG" | cut -f1 | tr -d '[:space:]')"
echo "Built $DMG ($SIZE)"
