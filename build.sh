#!/bin/sh
# Build (and optionally sign) lidawake.app — menu-bar app + root helper daemon.
#
#   ./build.sh            compile only (linker applies an ad-hoc signature;
#                         good for a quick error check, NOT registrable)
#   SIGN=1 ./build.sh     also codesign with the Developer ID identity below —
#                         required for SMAppService daemon registration
#
# No admin rights needed to build. Signing uses the cert already in the login
# keychain; the FIRST sign may pop a keychain "codesign wants to use the private
# key" dialog — click "Always Allow".
set -eu

APP="lidawake"
HELPER="lidawake-helper"
BUILD="build"
BUNDLE="$BUILD/$APP.app"
IDENTITY="Developer ID Application: zaYco s. r. o. (FXNTJBLQ2F)"

SHARED="Sources/Shared/HelperProtocol.swift"
APP_SRCS="Sources/App/main.swift \
          Sources/App/HelperManager.swift \
          Sources/App/HelperClient.swift \
          Sources/App/WakeAssertionManager.swift \
          Sources/App/ThermalGuard.swift \
          Sources/App/PowerPolicy.swift \
          Sources/App/LidMonitor.swift \
          Sources/App/Settings.swift \
          Sources/App/Onboarding.swift \
          Sources/App/LicenseProvider.swift \
          Sources/App/LicenseController.swift \
          Sources/App/LicenseWindow.swift"
HELPER_SRCS="Sources/Helper/main.swift \
             Sources/Helper/HelperDelegate.swift \
             Sources/Helper/HelperImplementation.swift"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"
mkdir -p "$BUNDLE/Contents/Frameworks"
mkdir -p "$BUNDLE/Contents/Library/LaunchDaemons"

# ── App ──────────────────────────────────────────────────────────────────────
swiftc -O -target arm64-apple-macos13 -o "$BUNDLE/Contents/MacOS/$APP" \
    $SHARED $APP_SRCS \
    -F vendor/Sparkle -framework Sparkle \
    -framework AppKit -framework ServiceManagement -framework IOKit -framework SwiftUI \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
cp Resources/lidawake.icns "$BUNDLE/Contents/Resources/lidawake.icns"
# Sparkle auto-update framework (the rpath above points the app at ../Frameworks)
cp -R vendor/Sparkle/Sparkle.framework "$BUNDLE/Contents/Frameworks/Sparkle.framework"

# ── Helper (root daemon) ─────────────────────────────────────────────────────
# Embed Helper-Info.plist into the bare Mach-O so it carries CFBundleIdentifier
# it.zayco.lidawake.helper — used for both the code-signing identity and the
# requirement check the app enforces.
swiftc -O -target arm64-apple-macos13 -o "$BUNDLE/Contents/MacOS/$HELPER" \
    $SHARED $HELPER_SRCS \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist \
    -Xlinker Resources/Helper-Info.plist

cp "Resources/it.zayco.lidawake.helper.plist" \
   "$BUNDLE/Contents/Library/LaunchDaemons/it.zayco.lidawake.helper.plist"

echo "Built $BUNDLE"

# ── Sign (inner first, then outer) ───────────────────────────────────────────
if [ "${SIGN:-0}" = "1" ]; then
    # 1) Sparkle.framework — re-sign nested code inside-out with our Developer ID
    #    (the vendored framework ships with no Team → would fail notarization as-is).
    SP="$BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B"
    for item in \
        "$SP/XPCServices/Downloader.xpc" \
        "$SP/XPCServices/Installer.xpc" \
        "$SP/Updater.app" \
        "$SP/Autoupdate"; do
        codesign --force --options runtime --timestamp --sign "$IDENTITY" "$item"
    done
    codesign --force --options runtime --timestamp --sign "$IDENTITY" \
        "$BUNDLE/Contents/Frameworks/Sparkle.framework"

    # 2) Helper (inner), then 3) the app (outer — seals the framework + helper)
    codesign --force --options runtime --timestamp \
        -i it.zayco.lidawake.helper \
        --sign "$IDENTITY" \
        "$BUNDLE/Contents/MacOS/$HELPER"
    codesign --force --options runtime --timestamp \
        --sign "$IDENTITY" \
        "$BUNDLE"
    echo "Signed with: $IDENTITY"
    codesign --verify --strict --verbose=2 "$BUNDLE"
else
    echo "Unsigned build (compile check). Run 'SIGN=1 ./build.sh' to sign for SMAppService."
fi

echo "Run:  open $BUNDLE"
