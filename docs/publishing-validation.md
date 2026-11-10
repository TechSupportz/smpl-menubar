# Publishing failure cases (before implementation)

The publisher must reject invalid commands/versions, missing dependencies or
signing configuration, dirty or changing source trees, a wrong origin, an unpushed
HEAD, an existing version/tag/release, failed builds/notarization, and incomplete
artifacts. It must not reuse the earlier build from a dirty checkout.

Before publication, it must reject missing/corrupt provenance, changed local
artifacts, an absent/already-public draft, a changed target commit or remote tag,
missing or replaced uploaded assets, failed signature/ticket/Gatekeeper checks,
and GitHub/auth/network failures. A partial upload must remain a draft; it must
never overwrite release assets or move a tag. Publishing from a different local
commit is allowed only because the recorded source commit and assets are checked.

Validation uses an isolated end-to-end CLI fixture (temporary Git repository,
simulated GitHub and platform commands), with a transcript as an artifact. This
checks orchestration and failures without creating real GitHub releases or tags.
Real Apple signing/notarization and ZIP verification were independently exercised
with the existing release.sh pipeline; an actual GitHub draft/publication remains
untested until explicitly authorized.
