// Build first. Browser E2E with the production Worker, built assets, test Access
// signing keys and a local SQL response. No production events or policy changes.
import { createServer } from "node:http";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { resolve, extname } from "node:path";
import assert from "node:assert/strict";
import { generateKeyPair, exportJWK, SignJWT } from "jose";
import worker from "../worker.js";
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || "playwright");
const out = process.env.ARTIFACT_DIR || "/tmp/smpl-dashboard-e2e";
await mkdir(out, { recursive: true });
const pair = await generateKeyPair("RS256");
const jwk = { ...await exportJWK(pair.publicKey), kid: "e2e", alg: "RS256", use: "sig" };
const issuer = "https://tnitish.cloudflareaccess.com", audience = "dashboard-e2e";
async function token(aud = audience, iss = issuer, expires = "1h") {
  return new SignJWT({}).setProtectedHeader({ alg: "RS256", kid: "e2e" }).setIssuer(iss).setAudience(aud).setSubject("test-owner").setIssuedAt().setExpirationTime(expires).sign(pair.privateKey);
}
let sqlFails = false, sqlEmpty = false, sqlCalls = 0;
const nativeFetch = globalThis.fetch;
globalThis.fetch = async (input, options) => {
  const url = String(input);
  if (url === `${issuer}/cdn-cgi/access/certs`) return Response.json({ keys: [jwk] });
  if (url.endsWith("/analytics_engine/sql")) {
    sqlCalls++;
    assert.equal(options.headers.Authorization, "Bearer e2e-server-secret");
    return Response.json({ data: sqlEmpty ? [] : [
      { day: new Date().toISOString().slice(0, 10), action: "download", actions: "3" },
      { day: new Date().toISOString().slice(0, 10), action: "brew_copy", actions: "2" },
    ] }, { status: sqlFails ? 500 : 200 });
  }
  return nativeFetch(input, options);
};
const env = { ACCESS_AUD: audience, ANALYTICS_READ_TOKEN: "e2e-server-secret", ASSETS: { async fetch(request) {
  const pathname = new URL(request.url).pathname;
  const path = resolve("dist", `.${pathname.endsWith("/") ? pathname + "index.html" : pathname}`);
  if (!path.startsWith(resolve("dist") + "/")) return new Response(null, { status: 404 });
  try { return new Response(await readFile(path), { headers: { "Content-Type": ({ ".html": "text/html", ".js": "application/javascript", ".css": "text/css", ".png": "image/png" })[extname(path)] || "application/octet-stream" } }); }
  catch { return new Response(null, { status: 404 }); }
} } };
const server = createServer(async (req, res) => {
  try {
    const response = await worker.fetch(new Request(`http://${req.headers.host}${req.url}`, { method: req.method, headers: req.headers }), env, {});
    res.writeHead(response.status, Object.fromEntries(response.headers)); res.end(Buffer.from(await response.arrayBuffer()));
  } catch (e) { res.writeHead(500); res.end(String(e)); }
});
await new Promise((ok, fail) => { server.once("error", fail); server.listen(0, "127.0.0.1", ok); });
const origin = `http://127.0.0.1:${server.address().port}`;
const checks = [];
let browser;
try {
  const valid = await token();
  for (const jwt of ["", "forged", await token("other-app"), await token(audience, "https://wrong.example"), await token(audience, issuer, Math.floor(Date.now() / 1000) - 60)]) {
    for (const path of ["/analytics", "/analytics/data", "/analytics/index.html"]) {
      const response = await nativeFetch(origin + path, { headers: { "Cf-Access-Jwt-Assertion": jwt } });
      assert.equal(response.status, 403); assert.equal(response.headers.get("cache-control"), "private, no-store");
    }
  }
  assert.equal(sqlCalls, 0);
  checks.push("Missing, forged, expired, wrong-audience and wrong-issuer JWTs denied before querying");
  const auth = { "Cf-Access-Jwt-Assertion": valid };
  const data = await (await nativeFetch(`${origin}/analytics/data`, { headers: auth })).json();
  assert.equal(data.rows.length, 30); assert.deepEqual(data.totals, { download: 3, brew_copy: 2 });
  assert.equal(data.rows.reduce((sum, row) => sum + row.download, 0), data.totals.download);
  assert.ok(!JSON.stringify(data).includes(env.ANALYTICS_READ_TOKEN));
  assert.equal((await nativeFetch(`${origin}/analytics/data?days=4`, { headers: auth })).status, 400);
  checks.push("Authorized query returns zero-filled daily rows and matching totals; range allowlist enforced");
  const aud = env.ACCESS_AUD; delete env.ACCESS_AUD;
  assert.equal((await nativeFetch(`${origin}/analytics`, { headers: auth })).status, 503); env.ACCESS_AUD = aud;
  const secret = env.ANALYTICS_READ_TOKEN; delete env.ANALYTICS_READ_TOKEN;
  assert.equal((await nativeFetch(`${origin}/analytics/data`, { headers: auth })).status, 503); env.ANALYTICS_READ_TOKEN = secret;
  assert.equal((await nativeFetch(`${origin}/`)).status, 200);
  assert.equal((await nativeFetch(`${origin}/events/brew-copy`, { method: "POST", headers: { Origin: origin } })).status, 204);
  checks.push("Missing configuration fails closed while landing page and event route remain public");
  browser = await chromium.launch({ headless: true, ...(process.env.BROWSER_CHANNEL ? { channel: process.env.BROWSER_CHANNEL } : {}) });
  const page = await browser.newPage({ extraHTTPHeaders: auth, viewport: { width: 1440, height: 900 } });
  await page.goto(`${origin}/analytics`);
  await page.waitForFunction(() => document.querySelector("#downloads").textContent === "3");
  assert.equal(await page.locator("#copies").textContent(), "2");
  await page.screenshot({ path: `${out}/desktop.png`, fullPage: true });
  for (const width of [390, 768, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), true);
  }
  await page.setViewportSize({ width: 390, height: 844 });
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  await page.screenshot({ path: `${out}/mobile.png`, fullPage: true });
  await page.selectOption("#range", "7");
  await page.waitForFunction(() => document.querySelector("#status").textContent.includes("7 calendar days"));
  assert.equal(await page.locator("#rows tr").count(), 7);
  // Rows are script-created: check headers and cells share edges and carry row styles.
  for (const width of [390, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    await page.evaluate(() => { document.querySelector("details").open = true; });
    const t = await page.evaluate(() => {
      const box = el => { const r = el.getBoundingClientRect(), s = getComputedStyle(el); return { left: r.left, right: r.right, align: s.textAlign, pad: s.paddingRight, border: s.borderBottomWidth }; };
      const ths = [...document.querySelectorAll("thead th")].map(box), tds = [...document.querySelectorAll("#rows tr:first-child td")].map(box);
      return { ths, tds };
    });
    t.ths.forEach((h, i) => { const c = t.tds[i]; assert.ok(Math.abs(h.left - c.left) < 1 && Math.abs(h.right - c.right) < 1, `col ${i} edges differ at ${width}px`); assert.equal(h.align, c.align); assert.equal(h.pad, c.pad); });
    assert.equal(t.tds[0].align, "left"); assert.equal(t.tds[1].align, "right"); assert.notEqual(t.tds[1].border, "0px");
    assert.equal(await page.evaluate(() => { const w = document.querySelector(".table-wrap"); return w.scrollWidth <= w.clientWidth; }), true, `table scrolls sideways at ${width}px`);
    await page.locator(".table-wrap").screenshot({ path: `${out}/table-${width}.png` });
  }
  sqlEmpty = true;
  await page.click("#refresh"); await page.waitForFunction(() => document.querySelector("#downloads").textContent === "0");
  assert.equal(await page.locator("#empty").isVisible(), true);
  sqlFails = true;
  await page.click("#refresh"); await page.waitForFunction(() => !document.querySelector("#error").hidden);
  assert.equal(await page.locator("#downloads").textContent(), "—");
  sqlFails = false; sqlEmpty = false;
  await page.click("#refresh"); await page.waitForFunction(() => document.querySelector("#downloads").textContent === "3");
  checks.push("Browser renders totals and chart; date filter, empty/error states and refresh recovery work without overflow at 390/768/1440px");
  await writeFile(`${out}/report.json`, JSON.stringify({ passed: true, checks, scope: "Production Worker and built assets over local HTTP; test-signed Access JWTs with simulated JWKS and SQL. Live Access and ingestion verified separately." }, null, 2));
  console.log(JSON.stringify({ passed: true, checks, artifact: out }));
} finally { await browser?.close(); await new Promise(ok => server.close(ok)); globalThis.fetch = nativeFetch; }
