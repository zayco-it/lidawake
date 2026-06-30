#!/bin/sh
# Regenerate Resources/lidawake.icns from tools/make-icon.swift (the icon source).
# Run from anywhere; no admin needed. Requires Command Line Tools (swiftc, iconutil).
set -eu
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swiftc -O tools/make-icon.swift -o "$TMP/make-icon" -framework AppKit
"$TMP/make-icon" "$TMP/lidawake.iconset" "$TMP/preview.png" "$TMP/strip.png"
iconutil -c icns "$TMP/lidawake.iconset" -o Resources/lidawake.icns
echo "Regenerated Resources/lidawake.icns"
