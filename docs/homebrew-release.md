# Homebrew distribution

Use [TechSupportz/homebrew-tap](https://github.com/TechSupportz/homebrew-tap),
with `Casks/smpl-menubar.rb` copied from the release output. The template in
`packaging/smpl-menubar.rb.in` is a draft, not an installable cask: the release
script fills in a real version and SHA-256. Homebrew's macOS 27 name is
`:golden_gate`. A ZIP avoids unnecessary DMG tooling.

## Why this route

A cask installs the prebuilt .app into /Applications. A source formula would
require a compatible Xcode toolchain and custom bundle installation/signing;
keep source builds available through build.sh instead.

Start in a personal tap. Official Homebrew submissions normally need a repository
at least 30 days old and 30 forks / 30 watchers / 75 stars; owner self-submissions
normally need 90 forks / 90 watchers / 225 stars (any one threshold). Exceptions
are discretionary. See the [acceptance policy](https://docs.brew.sh/Package-Acceptance-Policy).

Homebrew quarantines cask downloads by default. Developer ID Application signing
plus notarization and stapling is the supported public route; Full Disk Access
still needs the user's approval. Development/Distribution certificates do not
replace Developer ID for this purpose. Developer ID alone does not satisfy the
modern notarization requirement. See [Apple's distribution guidance](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Unsigned builds do not identify a trusted developer, and native Apple Silicon
code needs at least an ad-hoc signature. Ad-hoc signing supplies code integrity,
not developer identity or notarization; permission grants may need renewal across
updates. These builds can be blocked under quarantine. Users who trust them may
need System Settings → Privacy & Security → Open Anyway, where macOS permits it.
Do not remove quarantine in the cask or recommend disabling Gatekeeper. Official
macOS casks must pass Gatekeeper; a personal tap does not bypass it. See the
[Homebrew FAQ](https://docs.brew.sh/FAQ) and [Apple's override instructions](https://support.apple.com/en-gb/102445).

## One-time signing setup

Create a **Developer ID Application** certificate in the Apple developer account
and install it with its private key in the build Mac's keychain. Apple Development
and Apple Distribution are not substitutes for direct public distribution.
A full Xcode installation supporting the macOS 27 SDK and Icon Composer assets is
required; select it with `xcode-select`. The pipeline builds both arm64 and x86_64.

Store notarization credentials locally (not in Git):

```sh
xcrun notarytool store-credentials smpl-notary \
  --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
```

Enter an app-specific password when prompted. Alternatively, configure a
notarytool keychain profile using an App Store Connect API key. Do not put private
keys, exported certificates or passwords in this repository.

## Build and verify

```sh
SIGN_ID='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE=smpl-notary ./scripts/release.sh 1.0.0 1
```

The script builds in an isolated temporary directory, creates a universal bundle,
sets its version, compiles its icon, signs with hardened runtime and secure
timestamp, submits it to Apple, checks acceptance, staples the ticket, checks
Gatekeeper, and generates the final ZIP, SHA256SUMS and cask in `dist/1.0.0/`.
It does not touch /Applications or run the app. Output directories must be new;
choose a new version/build or move a failed output aside before retrying.

Without SIGN_ID / NOTARY_PROFILE it produces an ad-hoc-signed **preview only**.
Developer ID without NOTARY_PROFILE is also a preview, not a supported release.

Before publishing, extract the final ZIP on a clean macOS 27 machine, verify
`codesign --verify --deep --strict`, `xcrun stapler validate`, and
`spctl --assess --type execute --verbose=2`, then install in /Applications, launch,
grant Full Disk Access, arrange/hide/restore icons, quit and relaunch. Save the
command output and a screen recording as release QA evidence. Repeat on Intel
hardware if available; a universal Mach-O check alone does not prove Intel runtime
behavior. Never zap real settings merely to test packaging.

## Publish from this Mac

GitHub Actions supports macOS runners, but a hosted runner would also need an
Xcode/macOS SDK compatible with this project, an imported signing private key,
and notarization credentials. Local publishing keeps those in your Keychain.

Install the GitHub CLI (`brew install gh`) and sign in with `gh auth login` once.
After reviewing, committing and pushing the intended changes, run:

```sh
SIGN_ID='Developer ID Application: Nitish Thiyagarajan (Q5UAL6TUVS)' \
  ./scripts/publish.sh draft 1.0.1
```

Optional third argument is a positive build number (default 1).
`NOTARY_PROFILE` defaults to `smpl-notary`. This command requires a clean checkout,
checks that HEAD is on GitHub, refuses existing releases/tags/output directories,
builds and notarizes from source, rechecks the archived bundle, records the source
commit and checksums, then uploads the ZIP, SHA256SUMS and generated cask to a
**draft** release targeting that exact commit. Release notes are generated by
GitHub; edit them in the draft and smoke-test the app before continuing.

```sh
./scripts/publish.sh publish 1.0.1
```

This verifies the recorded candidate, draft target, any existing remote tag,
and downloaded asset hashes, then checks the downloaded app's signature,
notarization ticket and Gatekeeper acceptance before publishing. GitHub creates
the version tag at the draft target as part of its release flow if absent. The
script never creates commits, pushes branches, moves tags, overwrites assets, or
updates the tap. Neither command has been run against GitHub during setup.

Keep `dist/VERSION/`, including `publish-manifest.json`, between the two commands.
The earlier 1.0.0 candidate predates this provenance flow and cannot be published
with this wrapper; rebuild a fresh candidate from a clean, pushed commit.
If a build fails, move its output aside before retrying. If uploading fails, a
partial draft may remain: inspect it on GitHub and finish or remove that draft
manually before retrying. Never replace public ZIPs in place; use a new version.

After publication, copy `dist/VERSION/smpl-menubar.rb` into the tap's `Casks/`
directory. If needed for auditing on Homebrew 6+, first run
`brew trust --cask TechSupportz/tap/smpl-menubar`. Run
`brew style --cask Casks/smpl-menubar.rb` and
`brew audit --cask --online TechSupportz/tap/smpl-menubar`, then review and
commit/push the tap change. Each candidate regenerates both `version` and
`sha256`; no cross-repository token is needed. The public tap is `TechSupportz/homebrew-tap`;
Homebrew names it `TechSupportz/tap`.

## README Install snippet

Needs **macOS 27 or later**.

```sh
brew install --cask --appdir=/Applications TechSupportz/tap/smpl-menubar
open /Applications/smpl.menubar.app
```

Grant **Full Disk Access** in System Settings → Privacy & Security when prompted.
Update with `brew upgrade --cask smpl-menubar`.

Normal uninstall preserves settings and recovery backups. `brew uninstall --cask
--zap smpl-menubar` removes both: quit the app and restore any desired menu bar
state first. The cask never deletes Apple's shared preference files.
