#!/usr/bin/env bash
#
# Builds Pocket.app and installs it to /Applications.
#   ./build.sh               build + install
#   ./build.sh --no-install  build only (output: build/Pocket.app)

set -e
cd "$(dirname "$0")"

APP="build/Pocket.app"
INSTALL=1
[ "$1" = "--no-install" ] && INSTALL=0

echo "Building Pocket (release)..."
swift build -c release

echo "Assembling $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Pocket" "$APP/Contents/MacOS/Pocket"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature so Gatekeeper and SMAppService (launch at login) accept the bundle.
codesign --force --sign - "$APP"

echo "Build successful: $APP"

if [ "$INSTALL" = 1 ]; then
    echo "Installing to /Applications..."
    pkill -x Pocket 2>/dev/null || true
    rm -rf /Applications/Pocket.app
    cp -R "$APP" /Applications/Pocket.app
    open /Applications/Pocket.app
    echo "Done. Pocket is running — press your hotkey (default ⌘Space) to open it."
fi
