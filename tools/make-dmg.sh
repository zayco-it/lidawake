#!/bin/sh
# Build + sign a distributable DMG from the signed app in build/.
# Run this AFTER the app is notarized + stapled, so the app inside carries its
# ticket. Then notarize + staple the DMG itself (see the printed next step).
#
# Layout: the app + an "Applications" symlink, so users drag-to-install.
set -eu
cd "$(dirname "$0")/.."

IDENTITY="Developer ID Application: zaYco s. r. o. (FXNTJBLQ2F)"
APP="build/lidawake.app"
DIST="dist"
VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$DIST/lidawake-$VER.dmg"

STAGE="$(mktemp -d)"
mkdir -p "$DIST"
ditto "$APP" "$STAGE/lidawake.app"          # ditto preserves the stapled ticket + signature
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "lidawake" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

codesign --force --timestamp --sign "$IDENTITY" "$DMG"
echo "Built + signed $DMG ($(du -h "$DMG" | awk '{print $1}'))"
echo ""
echo "Next (notarize the DMG itself):"
echo "  xcrun notarytool submit \"$DMG\" --keychain-profile lidawake-notary --wait"
echo "  xcrun stapler staple \"$DMG\""
