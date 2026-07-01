#!/bin/sh
# One-command release. Ships whatever version is in Resources/Info.plist:
#   build → sign → notarize+staple app → DMG (notarize+staple) → Sparkle zip →
#   GitHub Release → regenerate the appcast (pointing at the GitHub asset) →
#   deploy the appcast to zayco.it.
#
# Prereqs: vendor/Sparkle (tools/fetch-sparkle.sh), Developer ID cert,
# notarytool keychain profile "lidawake-notary", gh authed as zayco-it,
# and ~/projects/zayco-site checked out (for the appcast + deploy).
#
# Notarization can take a while — run this in the background.
set -eu
cd "$(dirname "$0")/.."

IDENTITY="Developer ID Application: zaYco s. r. o. (FXNTJBLQ2F)"
NOTARY="lidawake-notary"
REPO="zayco-it/lidawake"
APP="build/lidawake.app"
DIST="dist"
SITE="$HOME/projects/zayco-site"

VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
TAG="v$VER"
echo "==== releasing lidawake $VER ($TAG) ===="

echo "== build + sign =="
SIGN=1 ./build.sh >/dev/null
mkdir -p "$DIST"

echo "== notarize + staple the app =="
ditto -c -k --keepParent "$APP" "$DIST/_app.zip"
xcrun notarytool submit "$DIST/_app.zip" --keychain-profile "$NOTARY" --wait
xcrun stapler staple "$APP"
spctl -a -vv "$APP"
rm -f "$DIST/_app.zip"

echo "== make + notarize + staple the DMG =="
./tools/make-dmg.sh >/dev/null
DMG="$DIST/lidawake-$VER.dmg"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY" --wait
xcrun stapler staple "$DMG"

echo "== zip the stapled app (Sparkle update artifact) =="
ZIP="$DIST/lidawake-$VER.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "== GitHub Release $TAG =="
git tag -a "$TAG" -m "lidawake $VER" 2>/dev/null || true
git push origin "$TAG"
NOTES="$(awk '/^## \[/{c++; next} c==1{print} c==2{exit}' CHANGELOG.md)"
printf '%s\n\nRequires an Apple Silicon Mac, macOS 13 (Ventura) or later.\n' "$NOTES" \
  | gh release create "$TAG" "$DMG" "$ZIP" --repo "$REPO" --title "lidawake $VER" --notes-file -

echo "== regenerate the appcast (points at the GitHub asset) + deploy =="
APC="$(mktemp -d)"
cp "$ZIP" "$APC/"
vendor/Sparkle/bin/generate_appcast \
  --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" "$APC" >/dev/null
mkdir -p "$SITE/public/lidawake"
cp "$APC/appcast.xml" "$SITE/public/lidawake/appcast.xml"
cp "$APC/appcast.xml" "$DIST/appcast.xml"
rm -rf "$APC"
( cd "$SITE" && ./deploy.sh )

echo "==== DONE: $VER released — DMG on GitHub, appcast live at https://zayco.it/lidawake/appcast.xml ===="
