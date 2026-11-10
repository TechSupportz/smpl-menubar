# DMG failure cases and repeatable verification

Before implementation: reject an existing destination, invalid version, missing app,
wrong bundle version, broken app signature, non-Developer-ID signing configuration,
failed notarization, failed stapling, failed image verification, wrong Applications
link, changed app bytes, or missing Finder layout. Never rebuild a historical app,
overwrite published assets, launch the app, or change installed apps/preferences.

E2E: extract the published ZIP, verify its known SHA256, package that app, mount
the final read-only DMG, compare bundle contents to the ZIP extraction, verify both
signatures and tickets and Gatekeeper, inspect Finder layout, then detach. Keep
all command output, notarization JSON, checksums and provenance in dist/VERSION.
For future releases the publisher repeats verification on downloaded assets.

## v1.0.0 result

Real E2E passed using the published ZIP (SHA256
`124cb180b68be94bc31461f4dae5f1146d5c5f071f3a9423a5bab99fddd7c19a`).
Apple accepted the DMG; the downloaded public DMG was independently mounted and
verified again. Evidence is in `dist/1.0.0/`: `dmg-notarization.json`,
`dmg-verification.txt`, `downloaded-dmg-verification.txt`,
`download-verification.txt`, `dmg-provenance.json` and `dmg-failure-checks.txt`.
Invalid version, mismatched bundle version, missing app and existing destination
were exercised as failing CLI invocations. Original GitHub asset IDs, timestamps,
bytes and hashes and the release target/tag were checked unchanged.

Finder showed the custom background, arrow, app and Applications shortcut in the
intended positions. The current window reused a user's list view until switched
to icon view; hidden files were enabled, making `.background` visible. A subsequent
fresh-window screenshot failed with ScreenCaptureKit -3811. Fresh-mount automatic
window appearance is therefore not fully verified. No install, app launch, live
preference changes, Intel execution or fresh-machine Gatekeeper trial was done.
The full future draft/publish workflow was reviewed and syntax checked; only the
historical additive asset flow and real DMG verification were exercised live.
