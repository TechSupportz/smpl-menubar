# Website action counts

Only the website sends analytics. The macOS app remains offline.

## Private dashboard verification plan

Before implementing the dashboard, verify these failure cases end to end:
missing, forged, expired, wrong-issuer and wrong-audience Access JWTs must not
return a page or data; missing server configuration must fail closed; neither
page HTML nor data errors may expose the analytics API token; the public landing
page and event routes must remain public. Access must protect `/analytics` and
its data subpath. Empty results must show zero; query errors must show an error
rather than zero. Totals must equal the daily rows, filters must use an allowlist,
and refresh must recover from a failed request. Check desktop and mobile overflow.

Before implementation, the failure cases to verify are:

- A download must still redirect if analytics is unavailable or throws.
- HEAD requests must not increment the download count.
- A successful clipboard copy records one event; a failed copy records none.
- A blocked analytics request must not change the successful copy feedback.
- Cross-origin copy events and unsupported HTTP methods must be rejected.
- Events must contain only a fixed action name, with no visitor identifiers,
  IP addresses, user agents, referrers, command text, or cookies.

## Storage and querying

The `ANALYTICS` binding writes to Cloudflare Workers Analytics Engine dataset
`smpl_menubar_actions`. `blob1` is either `download` or `brew_copy`. Cloudflare
adds the event timestamp. No analytics SDK or browser storage is used.

After deploying with `cd site && pnpm deploy`, the dataset is created on its
first event. These events are separate from Cloudflare Web Analytics.
Use the Analytics Engine SQL API with an Account Analytics Read token:

```sql
SELECT blob1 AS action, SUM(_sample_interval) AS actions
FROM smpl_menubar_actions
WHERE timestamp >= NOW() - INTERVAL '30' DAY
GROUP BY action
```

`SUM(_sample_interval)` accounts for Cloudflare sampling. Results are action
estimates, not unique users or confirmed installs. Download requests include
repeat visits, direct links and bots. Copies can be missed if requests are
blocked, and manually selecting/copying the command is not measured.
Analytics Engine has finite retention; these are not permanent lifetime totals.

Reference: https://developers.cloudflare.com/analytics/analytics-engine/get-started/

## Repeatable verification

From `site/`, build and validate the Worker bindings without deploying:

```sh
pnpm build
WRANGLER_LOG_PATH=/tmp/smpl-analytics-wrangler.log pnpm exec wrangler deploy --dry-run --outdir /tmp/smpl-analytics-dry-run
```

The browser E2E runner uses the built page and production Worker through a local
HTTP adapter, with a simulated GitHub release and an in-memory analytics sink.
It checks actual browser clicks and clipboard behavior, request rejection, and
failure handling. It does not prove production Cloudflare ingestion.

Install the browser runner outside the project to avoid adding app dependencies:

```sh
npm install --prefix /tmp/smpl-site-e2e playwright@1.65.0
PLAYWRIGHT_MODULE=/tmp/smpl-site-e2e/node_modules/playwright/index.mjs BROWSER_CHANNEL=chrome node scripts/verify-analytics.mjs
```

This uses installed Google Chrome with an isolated temporary browser profile.
Alternatively, install Playwright Chromium and omit `BROWSER_CHANNEL`.
Artifacts are `/tmp/smpl-site-analytics-e2e/report.json` and `copied.png`;
override the output directory with `ARTIFACT_DIR`. The runner does not send
events to production.

## Private dashboard

Open https://smpl-menubar.tnitish.com/analytics and sign in with the identity
allowed by the existing Cloudflare Access "Allow Me" policy. Access application
`04cbe875-e1d3-45f0-b257-c7ad311f6ac1` protects this path and its descendants.
The Worker also verifies Access JWT signatures, issuer, audience and expiry so
alternate Worker hostnames cannot bypass authorization. Responses are not cached.

The page provides 7/30/90 calendar-day ranges in UTC, two totals, a daily chart,
daily counts, refresh and sign-out. Zero-filled rows and totals come from the
same query. Errors show unavailable values rather than misleading zero counts.

`ACCESS_AUD` is a public configuration value in Wrangler; `ANALYTICS_READ_TOKEN`
is a Worker secret. Its API token is named "smpl.menubar dashboard read analytics"
and is restricted to Account Analytics Read on this account. It is not a CLI
OAuth token and must never appear in client code. Future deployments must preserve
this secret. Rotate it through the Cloudflare API token settings and Worker secrets.

The deployment was performed with `cf` using a temporary migrated config at
`/tmp/smpl-cf-deploy`. Regenerate that configuration from the current Wrangler
config and copy the current Worker modules and built `dist` before deploying;
do not redeploy an old copy. The repository's build tooling was not migrated.

To repeat the local dashboard E2E checks after building:

```sh
PLAYWRIGHT_MODULE=/tmp/smpl-site-e2e/node_modules/playwright/index.mjs BROWSER_CHANNEL=chrome node scripts/verify-dashboard.mjs
```

Output: `/tmp/smpl-dashboard-e2e/report.json`, `desktop.png`, and `mobile.png`.
JWT keys and SQL responses are simulated locally. Live checks separately verify
Access sign-in redirects and the dedicated token's actual query access; a live
owner browser sign-in still needs the owner's identity-provider session.
