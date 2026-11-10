#!/bin/bash
set -euo pipefail
DMG=${1:?Usage: scripts/verify-dmg.sh DMG REFERENCE_APP}
APP=${2:?}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/smpl-dmg-verify.XXXXXX")
trap 'hdiutil detach "$WORK/mount" >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT
codesign --verify --strict --verbose=2 "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
hdiutil verify "$DMG"
mkdir "$WORK/mount"
hdiutil attach -readonly -nobrowse -mountpoint "$WORK/mount" "$DMG"
[[ $(readlink "$WORK/mount/Applications") == /Applications ]]
[[ -f "$WORK/mount/.DS_Store" && -f "$WORK/mount/.background/install.png" ]]
diff -qr "$APP" "$WORK/mount/smpl.menubar.app"
codesign --verify --deep --strict --verbose=2 "$WORK/mount/smpl.menubar.app"
xcrun stapler validate "$WORK/mount/smpl.menubar.app"
spctl --assess --type execute --verbose=2 "$WORK/mount/smpl.menubar.app"
echo 'PASS: image, layout files, Applications link, exact app contents, signatures, tickets and Gatekeeper'
