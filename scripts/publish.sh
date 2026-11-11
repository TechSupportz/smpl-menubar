#!/bin/bash
# Local Mac release orchestration. Explicit commands mutate GitHub. Never commits to this
# repository; publish/tap commit and push only the cask in the Homebrew tap.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=TechSupportz/smpl-menubar
TAP=TechSupportz/homebrew-tap
CASK=Casks/smpl-menubar.rb
fail() { echo "Error: $*" >&2; exit 1; }
usage() {
  echo 'Usage: scripts/publish.sh draft VERSION [BUILD_NUMBER]'
  echo '       scripts/publish.sh publish VERSION'
  echo '       scripts/publish.sh tap VERSION'
  echo 'draft builds/notarizes, then creates a GitHub draft at the pushed HEAD.'
  echo 'publish verifies that draft, makes it public, then updates the tap.'
  echo 'tap updates the Homebrew tap to an already published release (e.g. to retry).'
}
[[ ${1:-} != --help && ${1:-} != -h ]] || { usage; exit 0; }
[[ $# -ge 2 && $# -le 3 ]] || { usage >&2; exit 1; }
MODE=$1 VERSION=$2 BUILD=${3:-1}
[[ "$MODE" == draft || "$MODE" == publish || "$MODE" == tap ]] || fail 'Choose draft, publish or tap'
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Use a numeric X.Y.Z version'
[[ "$BUILD" =~ ^[1-9][0-9]*$ ]] || fail 'Build number must be positive'
[[ "$MODE" == draft || $# -eq 2 ]] || fail "$MODE takes no build number"
for TOOL in git gh python3 ditto codesign xcrun spctl shasum; do
  command -v "$TOOL" >/dev/null || fail "Missing command: $TOOL"
done
TAG="v$VERSION" OUT="$PWD/dist/$VERSION"
ZIP="smpl-menubar-$VERSION-universal.zip"
DMG="smpl-menubar-$VERSION-universal.dmg"
ORIGIN=$(git remote get-url origin)
case "$ORIGIN" in
  https://github.com/TechSupportz/smpl-menubar|https://github.com/TechSupportz/smpl-menubar.git|git@github.com:TechSupportz/smpl-menubar.git) ;;
  *) fail "Unexpected origin: $ORIGIN" ;;
esac
gh auth status --hostname github.com >/dev/null
WORK=$(mktemp -d "${TMPDIR:-/tmp}/smpl-publish.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
# A checksum alone is insufficient: inspect the actual archived app.
verify_bundle() {
  local archive=$1 destination=$2
  mkdir -p "$destination"
  ditto -x -k "$archive" "$destination"
  local app="$destination/smpl.menubar.app"
  codesign --verify --deep --strict "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute --verbose=2 "$app"
}
# Points the tap's cask at the public release, after checking the generated cask's version and
# checksum against the ZIP users actually download. Never moves the tap to an older version.
update_tap() {
  local cask="$OUT/smpl-menubar.rb" tap="$WORK/tap" sha current
  [[ -f "$cask" ]] || fail "No generated cask at $cask"
  [[ $(gh release view "$TAG" --repo "$REPO" --json isDraft --jq .isDraft) == false ]] || fail "$TAG is not published"
  grep -qx "  version \"$VERSION\"" "$cask" || fail 'Generated cask has the wrong version'
  gh release download "$TAG" --repo "$REPO" --dir "$WORK/tap-zip" --pattern "$ZIP"
  sha=$(shasum -a 256 "$WORK/tap-zip/$ZIP" | awk '{print $1}')
  grep -qx "  sha256 \"$sha\"" "$cask" || fail 'Cask checksum does not match the published ZIP'
  gh repo clone "$TAP" "$tap" -- --quiet
  current=$(sed -n 's/^  version "\(.*\)"$/\1/p' "$tap/$CASK")
  if [[ -n "$current" && "$current" != "$VERSION" ]] &&
     [[ $(printf '%s\n' "$current" "$VERSION" | sort -V | tail -1) == "$current" ]]; then
    fail "Tap already has newer $current"
  fi
  cp "$cask" "$tap/$CASK"
  if git -C "$tap" diff --quiet; then echo "Tap already on $VERSION"; return; fi
  # By path: `--cask` only takes cask names, not files.
  if command -v brew >/dev/null; then brew style "$tap/$CASK"; fi
  git -C "$tap" add "$CASK"
  git -C "$tap" commit --quiet -m "🍺 Update smpl.menubar to $VERSION"
  git -C "$tap" push --quiet origin HEAD
  echo "Tap updated: brew upgrade --cask smpl-menubar now installs $VERSION"
}
if [[ "$MODE" == draft ]]; then
  [[ -z $(git status --porcelain --untracked-files=normal) ]] || fail 'Commit intended changes first; checkout must be clean'
  : "${SIGN_ID:?Set SIGN_ID to your full Developer ID Application identity}"
  export SIGN_ID
  export NOTARY_PROFILE=${NOTARY_PROFILE:-smpl-notary}
  HEAD=$(git rev-parse HEAD)
  # Check the exact commit on GitHub, without pushing a branch automatically.
  REMOTE_HEAD=$(gh api "repos/$REPO/commits/$HEAD" --jq .sha)
  [[ "$REMOTE_HEAD" == "$HEAD" ]] || fail 'Push the intended commit first'
  [[ ! -e "$OUT" ]] || fail "Output exists: $OUT; do not reuse a previous build"
  # The API list call must succeed; auth/network failures must not mean absent.
  gh api --paginate "repos/$REPO/releases?per_page=100" --jq '.[].tag_name' > "$WORK/releases"
  if python3 - "$WORK/releases" "$TAG" <<'PY'
import sys
sys.exit(0 if sys.argv[2] in open(sys.argv[1]).read().splitlines() else 1)
PY
  then fail "Release $TAG already exists"; fi
  git ls-remote --tags origin "refs/tags/$TAG" > "$WORK/tags"
  [[ ! -s "$WORK/tags" ]] || fail "Remote tag $TAG already exists"
  ./scripts/release.sh "$VERSION" "$BUILD" 2>&1 | tee "$WORK/build.log"
  [[ $(git rev-parse HEAD) == "$HEAD" && -z $(git status --porcelain --untracked-files=normal) ]] || fail 'Checkout changed during build; discard this candidate'
  cp "$WORK/build.log" "$OUT/build.log"
  python3 - "$OUT/notarization.json" <<'PY'
import json, sys
if json.load(open(sys.argv[1])).get('status') != 'Accepted': sys.exit('Notarization not accepted')
PY
  verify_bundle "$OUT/$ZIP" "$WORK/extracted" > "$OUT/publish-verification.txt" 2>&1
  scripts/verify-dmg.sh "$OUT/$DMG" "$WORK/extracted/smpl.menubar.app" >> "$OUT/publish-verification.txt" 2>&1
  python3 - "$OUT" "$VERSION" "$HEAD" "$ZIP" <<'PY'
import hashlib, json, pathlib, sys
out, version, commit, archive = sys.argv[1:]
p = pathlib.Path(out)
files = [archive, 'smpl-menubar-'+version+'-universal.dmg', 'SHA256SUMS', 'smpl-menubar.rb']
data = dict(version=version, commit=commit, assets={f: hashlib.sha256((p/f).read_bytes()).hexdigest() for f in files})
(p/'publish-manifest.json').write_text(json.dumps(data, indent=2)+'\n')
PY
  gh release create "$TAG" "$OUT/$ZIP" "$OUT/$DMG" "$OUT/SHA256SUMS" "$OUT/smpl-menubar.rb" \
    --repo "$REPO" --target "$HEAD" --draft --title "smpl.menubar $VERSION" --generate-notes
  echo "Draft created. Review notes and smoke-test before: scripts/publish.sh publish $VERSION"
elif [[ "$MODE" == publish ]]; then
  [[ -f "$OUT/publish-manifest.json" ]] || fail 'No candidate manifest; create a draft with this script first'
  gh release view "$TAG" --repo "$REPO" --json isDraft,targetCommitish,tagName > "$WORK/release.json"
  HEAD=$(python3 - "$OUT" "$VERSION" "$WORK/release.json" <<'PY'
import hashlib, json, pathlib, re, sys
p = pathlib.Path(sys.argv[1]); version = sys.argv[2]
m = json.loads((p/'publish-manifest.json').read_text()); r = json.load(open(sys.argv[3]))
if not (m['version'] == version and re.fullmatch('[0-9a-f]{40}', m['commit'])): sys.exit('Invalid provenance')
if not (r['isDraft'] and r['tagName'] == 'v'+version): sys.exit('Release is not the expected draft')
if not (r['targetCommitish'] == m['commit']): sys.exit('Draft target changed')
expected = {'smpl-menubar-'+version+'-universal.zip', 'smpl-menubar-'+version+'-universal.dmg', 'SHA256SUMS', 'smpl-menubar.rb'}
if not (set(m['assets']) == expected): sys.exit('Invalid asset list')
for name, digest in m['assets'].items():
    if not (hashlib.sha256((p/name).read_bytes()).hexdigest() == digest): sys.exit('Local asset changed: '+name)
print(m['commit'])
PY
  )
  # A draft may already have a tag; resolve annotated/lightweight tags to commit.
  git ls-remote --tags origin "refs/tags/$TAG" "refs/tags/$TAG^{}" > "$WORK/tags"
  if [[ -s "$WORK/tags" ]]; then
    TAG_HEAD=$(tail -1 "$WORK/tags" | awk '{print $1}')
    [[ "$TAG_HEAD" == "$HEAD" ]] || fail 'Remote tag points to another commit'
  fi
  gh release download "$TAG" --repo "$REPO" --dir "$WORK/download" \
    --pattern "$ZIP" --pattern "$DMG" --pattern SHA256SUMS --pattern smpl-menubar.rb
  python3 - "$OUT/publish-manifest.json" "$WORK/download" <<'PY'
import hashlib, json, pathlib, sys
m = json.load(open(sys.argv[1])); p = pathlib.Path(sys.argv[2])
for name, digest in m['assets'].items():
    if not (hashlib.sha256((p/name).read_bytes()).hexdigest() == digest): sys.exit('Uploaded asset differs: '+name)
PY
  verify_bundle "$WORK/download/$ZIP" "$WORK/extracted" > "$OUT/publish-verification.txt" 2>&1
  scripts/verify-dmg.sh "$WORK/download/$DMG" "$WORK/extracted/smpl.menubar.app" >> "$OUT/publish-verification.txt" 2>&1
  gh release edit "$TAG" --repo "$REPO" --draft=false
  echo "Published https://github.com/$REPO/releases/tag/$TAG"
fi
[[ "$MODE" == draft ]] || update_tap
