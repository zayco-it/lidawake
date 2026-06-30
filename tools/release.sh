#!/bin/sh
# Build a signed release, package it for Sparkle, and (re)generate the appcast.
# Output -> dist/. Then: upload the .zip to GitHub Releases, and publish
# dist/appcast.xml at the SUFeedURL (https://zayco.it/lidawake/appcast.xml).
#
# Prereqs:
#   - vendor/Sparkle present            (tools/fetch-sparkle.sh)
#   - Sparkle EdDSA private key in keychain  (bin/generate_keys, one-time)
#   - Developer ID cert in keychain
#
# For a REAL release, set DOWNLOAD_URL_PREFIX to the GitHub Releases download
# base so the appcast's enclosure URLs point at the uploaded zip, e.g.:
#   DOWNLOAD_URL_PREFIX="https://github.com/<org>/lidawake/releases/download/v1.0.0/" tools/release.sh
set -eu
cd "$(dirname "$0")/.."

APP="build/lidawake.app"
DIST="dist"
GEN="vendor/Sparkle/bin/generate_appcast"

echo "== building signed release =="
SIGN=1 ./build.sh >/dev/null
echo "   built + signed."

VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ZIP="$DIST/lidawake-$VER.zip"

mkdir -p "$DIST"
echo "== packaging $APP -> $ZIP =="
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "== generating appcast (EdDSA-signs each archive with the keychain key) =="
if [ -n "${DOWNLOAD_URL_PREFIX:-}" ]; then
    "$GEN" --download-url-prefix "$DOWNLOAD_URL_PREFIX" "$DIST"
else
    "$GEN" "$DIST"
fi

echo ""
echo "dist/ now holds:"; ls -1 "$DIST"
echo ""
echo "Publish:"
echo "  1) Upload $ZIP to GitHub Releases (tag v$VER)."
echo "  2) Publish $DIST/appcast.xml at https://zayco.it/lidawake/appcast.xml (SUFeedURL)."
echo "  (Real release: re-run with DOWNLOAD_URL_PREFIX=<github release base>/ so enclosure URLs are correct.)"
