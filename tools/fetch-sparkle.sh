#!/bin/sh
# Fetch the pinned Sparkle binary release into vendor/ (git-ignored), so the
# open-source repo stays clean (no large binary committed) yet builds stay
# reproducible. Run once after a fresh clone. Needs curl + tar with xz support.
set -eu

VER="2.9.3"
SHA="74a07da821f92b79310009954c0e15f350173374a3abe39095b4fc5096916be6"
URL="https://github.com/sparkle-project/Sparkle/releases/download/${VER}/Sparkle-${VER}.tar.xz"

cd "$(dirname "$0")/.."
mkdir -p vendor
TARBALL="vendor/Sparkle-${VER}.tar.xz"

if [ ! -f "$TARBALL" ]; then
    echo "Downloading Sparkle ${VER}…"
    curl -L --fail -o "$TARBALL" "$URL"
fi

echo "Verifying checksum…"
echo "${SHA}  ${TARBALL}" | shasum -a 256 -c -

rm -rf vendor/Sparkle && mkdir -p vendor/Sparkle
tar -xf "$TARBALL" -C vendor/Sparkle
echo "Sparkle ${VER} ready in vendor/Sparkle (Sparkle.framework + bin/ tools)."
