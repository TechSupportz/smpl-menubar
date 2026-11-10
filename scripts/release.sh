#!/bin/bash
# Build locally; never installs, launches, creates tags, or creates releases.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${1:?Usage: scripts/release.sh VERSION [BUILD_NUMBER]}
BUILD_NUMBER=${2:-1}
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Use a numeric X.Y.Z version' >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { echo 'Build number must be positive' >&2; exit 1; }
SIGN_ID=${SIGN_ID:--}
if [[ "$SIGN_ID" != '-' && "$SIGN_ID" != 'Developer ID Application: '* ]]; then
  echo 'Use a full Developer ID Application identity, or - for local ad-hoc previews.' >&2
  exit 1
fi
if [[ -n "${NOTARY_PROFILE:-}" && "$SIGN_ID" == '-' ]]; then
  echo 'Notarization requires Developer ID Application signing.' >&2; exit 1
fi
OUT="$PWD/dist/$VERSION"
[[ ! -e "$OUT" ]] || { echo "Output already exists: $OUT" >&2; exit 1; }
mkdir -p "$OUT"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/smpl-release.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
export MACOSX_DEPLOYMENT_TARGET=27.0
export CLANG_MODULE_CACHE_PATH="$WORK/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$WORK/module-cache"
for ARCH in arm64 x86_64; do
  swift build -c release --arch "$ARCH" --scratch-path "$WORK/build-$ARCH"
  BIN=$(swift build -c release --arch "$ARCH" --scratch-path "$WORK/build-$ARCH" --show-bin-path)
  cp "$BIN/SmplMenubar" "$WORK/SmplMenubar-$ARCH"
done
APP="$OUT/smpl.menubar.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$WORK/SmplMenubar-arm64" "$WORK/SmplMenubar-x86_64" -output "$APP/Contents/MacOS/SmplMenubar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx \
  --minimum-deployment-target 27.0 --app-icon AppIcon --output-partial-info-plist "$WORK/icon.plist"
# Keep asset compiler metadata (including icon keys) in the final bundle.
python3 - "$APP/Contents/Info.plist" "$WORK/icon.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as f: info = plistlib.load(f)
with open(sys.argv[2], 'rb') as f: info.update(plistlib.load(f))
with open(sys.argv[1], 'wb') as f: plistlib.dump(info, f)
PY
if [[ "$SIGN_ID" == '-' ]]; then
  codesign --force --sign - "$APP"
else
  codesign --force --sign "$SIGN_ID" --options runtime --timestamp "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP" 2> "$OUT/signature-check.txt"
ARCHS=$(lipo -archs "$APP/Contents/MacOS/SmplMenubar")
[[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]] || { echo "Missing architecture: $ARCHS" >&2; exit 1; }
lipo -info "$APP/Contents/MacOS/SmplMenubar" > "$OUT/architectures.txt"
ZIP="$OUT/smpl-menubar-$VERSION-universal.zip"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  ditto -c -k --keepParent "$APP" "$WORK/notarize.zip"
  xcrun notarytool submit "$WORK/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$OUT/notarization.json"
  python3 - "$OUT/notarization.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f: result = json.load(f)
if result.get('status') != 'Accepted': sys.exit('Notarization was not accepted; inspect notarization.json')
PY
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP" > "$OUT/stapler-check.txt" 2>&1
  spctl --assess --type execute --verbose=2 "$APP" > "$OUT/gatekeeper-check.txt" 2>&1
fi
# Archive AFTER stapling; checksum exactly the bytes users download.
ditto -c -k --keepParent "$APP" "$ZIP"
(cd "$OUT" && shasum -a 256 "$(basename "$ZIP")" > SHA256SUMS)
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
sed -e "s/@VERSION@/$VERSION/g" -e "s/@SHA256@/$SHA/g" packaging/smpl-menubar.rb.in > "$OUT/smpl-menubar.rb"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo 'Developer ID signed, notarized and stapled' > "$OUT/distribution-status.txt"
else
  echo 'PREVIEW ONLY: not notarized; do not publish as the supported Homebrew release' > "$OUT/distribution-status.txt"
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  scripts/dmg.sh "$APP" "$VERSION" "$OUT"
  cat "$OUT/DMG-SHA256SUMS" >> "$OUT/SHA256SUMS"
fi
echo "Artifacts: $OUT"
