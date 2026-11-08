#!/bin/sh
# Builds smpl menubar and installs it to /Applications (macOS 27 only shows status items
# for apps there). Usage: ./build.sh [--run]
set -e
cd "$(dirname "$0")"
swift build -c release
APP="/Applications/smpl menubar.app"
pkill -x SmplMenubar 2>/dev/null && sleep 0.5 || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/SmplMenubar "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
codesign --force --sign "${SIGN_ID:-Apple Development}" "$APP"
echo "Installed $APP"
[ "$1" = "--run" ] && open "$APP"
exit 0
