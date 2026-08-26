#!/bin/sh
# One-command release. Ships whatever version is in Resources/Info.plist:
#   pre-flight → build → sign → notarize+staple app → DMG (notarize+staple) →
#   Sparkle zip → GitHub Release → regenerate the appcast (pointing at the
#   GitHub asset) → deploy to zayco.it → post-flight.
#
# The pre- and post-flight checks all exist for the same reason: this script
# used to assume a manual step had happened and said NOTHING when it had not.
# Every one of them has actually fired in anger. Prefer failing loudly over
# trusting whoever is running it.
#
# Prereqs: vendor/Sparkle (tools/fetch-sparkle.sh), Developer ID cert,
# notarytool keychain profile "lidawake-notary", gh authed as zayco-it,
# and ~/projects/zayco-site checked out (for the appcast + deploy).
#
# Notarization can take a while — run this in the background.
set -eu
cd "$(dirname "$0")/.."

# The git tag must match what actually ships. Refuse a dirty tree — this is exactly
# what silently made the v1.0.2 tag point at the 1.0.1 commit (changes never committed).
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERROR: uncommitted changes — commit them first so the tag matches the build." >&2
  exit 1
fi

IDENTITY="Developer ID Application: zaYco s. r. o. (FXNTJBLQ2F)"
NOTARY="lidawake-notary"
REPO="zayco-it/lidawake"
APP="build/lidawake.app"
DIST="dist"
SITE="$HOME/projects/zayco-site"
TAP="$HOME/projects/homebrew-tap"
CASK="$TAP/Casks/lidawake.rb"

VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
TAG="v$VER"
echo "==== releasing lidawake $VER ($TAG) ===="

# ---------------------------------------------------------------------------
# PRE-FLIGHT. Every check here exists because the script once assumed a manual
# step had happened and said nothing when it had not. Fail loudly, never warn.
# ---------------------------------------------------------------------------

# 1. CHANGELOG. This file is READ for both the GitHub release notes and
#    Sparkle's what's-new panel. With no entry for $VER the awk below silently
#    picks up the PREVIOUS version's section, and every user sees the wrong
#    release notes in the update dialog. Nearly shipped 1.2.0's notes as 1.3.0.
if ! grep -q "^## \[$VER\]" CHANGELOG.md; then
  echo "ERROR: CHANGELOG.md has no '## [$VER]' section." >&2
  echo "       The release notes and Sparkle's what's-new panel are built from" >&2
  echo "       the top section of that file — without an entry you would ship" >&2
  echo "       the previous version's notes. Add it, commit, re-run." >&2
  exit 1
fi
if [ "$(awk '/^## \[/{print; exit}' CHANGELOG.md)" != "$(grep -m1 "^## \[$VER\]" CHANGELOG.md)" ]; then
  echo "ERROR: the '## [$VER]' section is not at the top of CHANGELOG.md." >&2
  echo "       The notes are taken from the FIRST section, so they would come" >&2
  echo "       from a different release. Move it up, commit, re-run." >&2
  exit 1
fi

# 2. main must be pushed. The tag alone carries its objects, but the branch is
#    left behind — so the public repo can show source that predates the release
#    it is serving. That is how a README with a claim we had already corrected
#    stayed live while the release fixing it went out. Push first, and do it
#    BEFORE the slow notarization so a failure here costs seconds, not minutes.
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$BRANCH" != "main" ]; then
  echo "ERROR: on branch '$BRANCH', not main. Releases are cut from main." >&2
  exit 1
fi
git fetch origin --quiet
if [ -n "$(git log --oneline origin/main..main)" ]; then
  echo "== pushing main (unpushed commits would leave the tag ahead of the branch) =="
  git log --oneline origin/main..main | sed 's/^/   /'
  git push origin main
fi

# 3. The Homebrew cask lives in another repo, so this script cannot push it —
#    but it can refuse to call the release finished. Checked again at the end,
#    where the DMG checksum exists; this early check catches "forgot entirely"
#    before spending two minutes on notarization.
if [ ! -f "$CASK" ]; then
  echo "ERROR: no cask at $CASK — cannot verify the tap is in step." >&2
  exit 1
fi
CASK_VER="$(sed -n 's/^  version "\(.*\)"$/\1/p' "$CASK")"
if [ "$CASK_VER" != "$VER" ]; then
  echo "NOTE: cask is at $CASK_VER, releasing $VER — it will be checked again at the end." >&2
fi

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

echo "== checksum the DMG (published so users can verify the download) =="
SHA="$DIST/lidawake-$VER.dmg.sha256"
( cd "$DIST" && shasum -a 256 "lidawake-$VER.dmg" ) | tee "$SHA"
DMG_SHA="$(awk '{print $1}' "$SHA")"

echo "== zip the stapled app (Sparkle update artifact) =="
ZIP="$DIST/lidawake-$VER.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "== GitHub Release $TAG =="
git tag -a "$TAG" -m "lidawake $VER" 2>/dev/null || true
git push origin "$TAG"
NOTES="$(awk '/^## \[/{c++; next} c==1{print} c==2{exit}' CHANGELOG.md)"
printf '%s\n\nRequires an Apple Silicon Mac, macOS 13 (Ventura) or later.\n\nSHA-256 (DMG): `%s`\n' "$NOTES" "$DMG_SHA" \
  | gh release create "$TAG" "$DMG" "$ZIP" "$SHA" --repo "$REPO" --title "lidawake $VER" --notes-file -

echo "== regenerate the appcast (points at the GitHub asset) + deploy =="
APC="$(mktemp -d)"
cp "$ZIP" "$APC/"
# Release notes from the CHANGELOG's top section. Sparkle embeds "<zip-basename>.html"
# as the update's notes — the "what's new" panel. (The auto-download checkbox is hidden
# separately, via SUAllowsAutomaticUpdates=false in Info.plist.)
{
  echo "<h2>lidawake $VER</h2><ul>"
  awk '/^## \[/{c++; next} c==1{print} c==2{exit}' CHANGELOG.md | sed -n 's/^- \(.*\)/<li>\1<\/li>/p'
  echo "</ul>"
} | sed 's/\*\*\([^*]*\)\*\*/<strong>\1<\/strong>/g' > "$APC/lidawake-$VER.html"
vendor/Sparkle/bin/generate_appcast \
  --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" "$APC" >/dev/null
mkdir -p "$SITE/public/lidawake"
cp "$APC/appcast.xml" "$SITE/public/lidawake/appcast.xml"
cp "$APC/appcast.xml" "$DIST/appcast.xml"
cp "$DMG" "$SITE/public/lidawake/lidawake.dmg"   # stable-named download for the product page
( cd "$SITE/public/lidawake" && shasum -a 256 lidawake.dmg > lidawake.dmg.sha256 )   # checksum matching the stable filename
rm -rf "$APC"
( cd "$SITE" && ./deploy.sh )

# ---------------------------------------------------------------------------
# POST-FLIGHT. Verify what is actually live rather than what we believe we did.
# ---------------------------------------------------------------------------

echo "== verify the site serves the DMG we just built =="
SERVED_SHA="$(curl -fsS https://zayco.it/lidawake/lidawake.dmg | shasum -a 256 | awk '{print $1}')"
if [ "$SERVED_SHA" != "$DMG_SHA" ]; then
  echo "ERROR: zayco.it serves a different DMG than the one just released." >&2
  echo "       built:  $DMG_SHA" >&2
  echo "       served: $SERVED_SHA" >&2
  exit 1
fi
echo "   ok — $DMG_SHA"

echo "== verify the product page advertises $VER =="
# softwareVersion in the SoftwareApplication JSON-LD is derived from the appcast
# at build time (see src/pages/lidawake/index.astro). This confirms the derivation
# actually reached the deployed page, rather than trusting that it did.
LIVE_VER="$(curl -fsS https://zayco.it/lidawake/ | sed -n 's/.*"softwareVersion":"\([^"]*\)".*/\1/p')"
if [ "$LIVE_VER" != "$VER" ]; then
  echo "ERROR: the live product page advertises softwareVersion '$LIVE_VER', not '$VER'." >&2
  echo "       It is derived from public/lidawake/appcast.xml at build time —" >&2
  echo "       check that the appcast copy and the deploy both succeeded." >&2
  exit 1
fi
echo "   ok — $LIVE_VER"

echo "== verify the Homebrew cask is in step =="
# The tap is a separate repo, so this script cannot push it. It can refuse to
# call the release finished. The cask sat on 1.1.9 through the whole of 1.2.0 —
# tap users were two releases behind and never got the hang watchdog.
CASK_VER="$(sed -n 's/^  version "\(.*\)"$/\1/p' "$CASK")"
CASK_SHA="$(sed -n 's/^  sha256 "\(.*\)"$/\1/p' "$CASK")"
if [ "$CASK_VER" != "$VER" ] || [ "$CASK_SHA" != "$DMG_SHA" ]; then
  echo "" >&2
  echo "###########################################################" >&2
  echo "#  RELEASED, BUT THE HOMEBREW CASK IS STALE               #" >&2
  echo "###########################################################" >&2
  echo "" >&2
  echo "  $CASK" >&2
  echo "    version is  $CASK_VER   -> set to  $VER" >&2
  echo "    sha256 is   $CASK_SHA" >&2
  echo "    sha256 want $DMG_SHA" >&2
  echo "" >&2
  echo "  brew users stay on $CASK_VER until this is committed and pushed." >&2
  echo "" >&2
  exit 1
fi
echo "   ok — cask $CASK_VER / $CASK_SHA"

echo "==== DONE: $VER released — DMG on GitHub, appcast live at https://zayco.it/lidawake/appcast.xml ===="
