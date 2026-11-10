#!/bin/bash
# Package an existing app; never builds, installs or launches it.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=${1:?Usage: scripts/dmg.sh APP VERSION OUTPUT_DIRECTORY}
VERSION=${2:?} OUT=${3:?}
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$APP" = /* && "$OUT" = /* ]] || { echo 'Use absolute paths' >&2; exit 1; }
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist") == "$VERSION" ]]
DMG="$OUT/smpl-menubar-$VERSION-universal.dmg"
[[ ! -e "$DMG" ]] || { echo "Already exists: $DMG" >&2; exit 1; }
: "${SIGN_ID:?Set a Developer ID Application identity}"
[[ "$SIGN_ID" == 'Developer ID Application: '* ]]
: "${NOTARY_PROFILE:?Set a notarization Keychain profile}"
codesign --verify --deep --strict "$APP"
xcrun stapler validate "$APP"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/smpl-dmg.XXXXXX")
MOUNT="$WORK/mount"
cleanup() { hdiutil detach "$MOUNT" >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT
mkdir -p "$WORK/root/.background" "$MOUNT" "$OUT"
ditto "$APP" "$WORK/root/smpl.menubar.app"
ln -s /Applications "$WORK/root/Applications"
swift scripts/dmg-background.swift "$WORK/root/.background/install.png"
hdiutil create -quiet -size 40m -fs HFS+ -volname 'smpl.menubar' -srcfolder "$WORK/root" -format UDRW "$WORK/layout.dmg"
hdiutil attach -quiet -nobrowse -mountpoint "$MOUNT" "$WORK/layout.dmg"
osascript - "$MOUNT" <<'APPLESCRIPT'
on run argv
  set folderPath to POSIX file (item 1 of argv) as alias
  tell application "Finder"
    open folderPath
    set w to container window of folderPath
    set current view of w to icon view
    set toolbar visible of w to false
    set statusbar visible of w to false
    set bounds of w to {160, 140, 880, 580}
    set opts to icon view options of w
    set arrangement of opts to not arranged
    set icon size of opts to 96
    set text size of opts to 14
    set background picture of opts to file ".background:install.png" of folderPath
    set position of item "smpl.menubar.app" of folderPath to {190, 224}
    set position of item "Applications" of folderPath to {530, 224}
    close w
    open folderPath
    update folderPath without registering applications
    delay 2
    close container window of folderPath
  end tell
end run
APPLESCRIPT
[[ -f "$MOUNT/.DS_Store" ]]
sync
hdiutil detach -quiet "$MOUNT"
hdiutil convert -quiet "$WORK/layout.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG"
codesign --sign "$SIGN_ID" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$OUT/dmg-notarization.json"
python3 - "$OUT/dmg-notarization.json" <<'PY'
import json,sys
if json.load(open(sys.argv[1])).get('status') != 'Accepted': sys.exit('DMG notarization rejected')
PY
xcrun stapler staple "$DMG"
scripts/verify-dmg.sh "$DMG" "$APP" > "$OUT/dmg-verification.txt" 2>&1
(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" > DMG-SHA256SUMS)
echo "$DMG"
