#!/bin/sh
# Regenerate Resources/lidawake.icns AND the website's icon.png from
# tools/make-icon.swift — one generator, so the two cannot drift apart. The site
# copy was previously a separate hand-export and had already diverged.
# Run from anywhere; no admin needed. Requires Command Line Tools (swiftc, iconutil).
set -eu
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swiftc -O tools/make-icon.swift -o "$TMP/make-icon" -framework AppKit
SITE="${SITE:-$HOME/projects/zayco-site}"
"$TMP/make-icon" "$TMP/lidawake.iconset" "$TMP/preview.png" "$TMP/strip.png" "$TMP/site-icon.png"
iconutil -c icns "$TMP/lidawake.iconset" -o Resources/lidawake.icns
echo "Regenerated Resources/lidawake.icns"
if [ -d "$SITE/public/lidawake" ]; then
  cp "$TMP/site-icon.png" "$SITE/public/lidawake/icon.png"
  echo "Regenerated $SITE/public/lidawake/icon.png (favicon, nav mark, JSON-LD logo)"
else
  echo "NOTE: $SITE/public/lidawake not found — site icon.png NOT updated." >&2
fi
