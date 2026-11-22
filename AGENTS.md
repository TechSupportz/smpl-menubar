# smpl.menubar

A macOS 27 menu bar app (Swift 6, AppKit plus SwiftUI for Arrange) that hides menu bar items by flipping the same switches System Settings uses, so hidden items really leave the bar. `site/` is its landing page.

## Vocabulary

Use these words in code, comments and commit messages.

- **The dot** is our own status item: Visible sits right of it, Hidden and Buried left of it. **The divider**, our second item, separates Hidden from Buried while Buried is revealed and Hidden has something on screen (`Model.hasHidden`).
- **Sections**, most to least visible: **Visible**, **Hidden** (revealed by resting the pointer on the bar), **Buried** (revealed by clicking the dot), **Disabled** (never shown). Buried's stored raw value is `alwaysHidden`; keep it so saved arrangements carry over.
- **Arrange** is the window where items are dragged between sections. Top to bottom in a column is right to left in the bar, starting from the clock (Visible), the dot (Hidden) or the divider (Buried).
- **Modules** are Control Center's own items (Wi‑Fi, Sound, Focus), keyed `module:<name>`; UI copy calls them **system items**. They have no Disabled state: dropping one there takes it out of the menu bar and back to Add System Item.
- **Managed** items are the apps and modules this app switched off. Apps the user switched off in System Settings are left alone until dragged out of Disabled, which hands them to this app.

## System state this app writes

None of this is public API, and all of it needs Full Disk Access. Each store's doc comment has the details; these rules bind every change:

- **App switches** (`ControlCenterList`): change only `isAllowed`, write back everything else exactly as read, and refuse a write that doesn't decode to the same number of entries. The first backup in `~/Library/Application Support/smpl-menubar` is never overwritten; the Disabled migration reads it.
- **Module switches** (`ControlCenterModules`): stored per host, so read and write with `kCFPreferencesCurrentHost`. Save a module's own shown value before hiding it, so showing it again restores it.
- **Menu bar order** (`MenuBarLayout`): items only take a new position when they reappear, so positions are written before a reveal, and a reorder hides and shows the items already on screen that moved (`Model.reseat`).
- **Owner IDs**: switches are keyed by the app's bundle ID, but menu bar items can belong to a helper. Layout keys, running checks and open-menu checks resolve through `Model.itemOwners`, and module menus belong to `com.apple.controlcenter`.
- **Writes are expensive.** Each switch flip makes MenuBarAgent rebuild the affected items, which drops frames across the whole system. Write only when what's on screen changes (`Model.setShown`) or to retry a failed write (`writePending`); keep timers and refreshes read-only otherwise.
- Writes are read back to confirm. App switches and the layout left of the dot also retry once against a fresh copy if another writer replaced the list mid-write.
- Anything about to be switched off is marked managed before the write, so a write that only partly lands is still undone at quit. Quitting switches every managed item back on except Disabled ones, and keeps `managed` so the next launch hides them again.

## Build and verify

- `./build.sh --run` builds, installs to `/Applications`, signs and launches. macOS 27 only shows status items for apps in `/Applications`, so `swift run` won't show the dot. Keep the signing identity stable (`SIGN_ID`, default Apple Development) so the build keeps its Full Disk Access grant.
- `build.sh` stops the running app with `pkill`, which skips quit-restore, so items it hid stay off until the new build launches. Pass `--run`, or quit the app first.
- There is no test target, by design: the failures here come from real pointer geometry and system cost. Check a change with `swift build`, then by using the installed app in the real menu bar. Testing hides your own menu bar items; leave the real Control Center and MenuBarAgent preferences in place rather than resetting them.

## Releases

Releases run locally through `scripts/publish.sh` (`bump`, commit and push, `draft`, `publish`). Publishing triggers `.github/workflows/homebrew-tap.yml`, which updates the tap. Keep `dist/VERSION/` between `draft` and `publish`. Read [docs/homebrew-release.md](docs/homebrew-release.md) before release, signing or cask work.

## Writing

Comments and UI copy are short and plain, written for the person using the app: say what happens, and why when it isn't obvious. Record observed macOS behaviour in the doc comment of the code that relies on it.

## Site

`site/` is Astro on Cloudflare Workers, using pnpm. Only the website collects analytics; the app stays offline, as the README promises. `pnpm dev` skips the Worker, so routes and Access checks need the Worker-backed checks in [docs/site-analytics.md](docs/site-analytics.md). Read it before changing events, the `/analytics` dashboard or deployment.

## Plans

`plans/` is gitignored and holds handoff plans from the `improve` skill, indexed in `plans/README.md`.
