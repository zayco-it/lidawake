#!/bin/sh
# Adopt the new icon everywhere. RUN THIS WITH T1.4 (the rename), not before —
# the icon is part of the relaunch package and shipping it early spends the
# "new name, new look" story on a point release.
#
# Everything it installs comes from design/icon.swift, the single generator, so
# the app icon, the menu-bar glyph and the site's PNG cannot drift apart. The
# old icon drifted precisely because the site's copy was a separate hand-export.
set -eu
cd "$(dirname "$0")/.."
SITE="${SITE:-$HOME/projects/zayco-site}"

echo "== regenerate everything from the one generator =="
swiftc -O design/icon.swift -o /tmp/lidawake-icon -framework AppKit
/tmp/lidawake-icon design

echo "== app icon =="
iconutil -c icns design/iconset -o Resources/lidawake.icns

echo "== menu-bar template assets =="
mkdir -p Resources/MenuBar
cp design/menubar-template/*.png Resources/MenuBar/

echo "== site favicon / nav mark / JSON-LD logo =="
cp design/site-icon-512.png "$SITE/public/lidawake/icon.png"

cat <<'NOTE'

Still manual — one code change in Sources/App/main.swift, updateIcon():

    replace   NSImage(systemSymbolName: "laptopcomputer", ...)
    with      the bundled template, so the menu bar carries OUR mark:

        let name = armed ? "lidawake-menubar-on" : "lidawake-menubar"
        let img  = NSImage(named: name)          // add Resources/MenuBar to the bundle in build.sh
        img?.isTemplate = true                    // template in BOTH states
        button.image = img

    Note the armed state is now a shape difference (the light), not a colour
    difference, so it stays a template either way and keeps adapting to light,
    dark and tinted menu bars. The old code turned template OFF when armed to
    paint it blue, which is why it looked wrong on a tinted menu bar.

Then: bump the version, add a CHANGELOG entry, and release.sh does the rest.
NOTE
