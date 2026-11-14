// Run after pnpm build. Uses a local HTTP adapter for the production Worker,
// built site assets, and an in-memory Analytics Engine sink (no live writes).
import { createServer } from "node:http";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { resolve, extname } from "node:path";
import assert from "node:assert/strict";
import worker from "../worker.js";

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || "playwright");
const output = resolve(process.env.ARTIFACT_DIR || "/tmp/smpl-site-analytics-e2e");
await mkdir(output, { recursive: true });
const events = [];
const checks = [];
let brokenAnalytics = false;
let brokenGitHub = false;
const nativeFetch = globalThis.fetch;
globalThis.fetch = (input, options) => {
  if (String(input) === "https://api.github.com/repos/TechSupportz/smpl-menubar/releases/latest") {
    return Promise.resolve(new Response(JSON.stringify({ assets: [
      { name: "smpl.dmg", browser_download_url: "https://example.com/smpl.dmg" },
    ] }), { status: brokenGitHub ? 503 : 200 }));
  }
  return nativeFetch(input, options);
};
const mime = { ".html": "text/html", ".js": "application/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png" };
const env = {
  ANALYTICS: { writeDataPoint(point) {
    if (brokenAnalytics) throw new Error("Simulated analytics outage");
    assert.deepEqual(Object.keys(point), ["blobs"]);
    assert.ok(["download", "brew_copy"].includes(point.blobs[0]));
    events.push(point);
  } },
  ASSETS: { async fetch(request) {
    const pathname = new URL(request.url).pathname;
    const file = resolve("dist", pathname === "/" ? "index.html" : `.${pathname}`);
    if (!file.startsWith(resolve("dist") + "/")) return new Response(null, { status: 404 });
    try {
      return new Response(await readFile(file), { headers: { "Content-Type": mime[extname(file)] || "application/octet-stream" } });
    } catch { return new Response(null, { status: 404 }); }
  } },
};
const server = createServer(async (req, res) => {
  try {
    const request = new Request(`http://${req.headers.host}${req.url}`, { method: req.method, headers: req.headers });
    const response = await worker.fetch(request, env, {});
    res.writeHead(response.status, Object.fromEntries(response.headers));
    res.end(Buffer.from(await response.arrayBuffer()));
  } catch (error) { res.writeHead(500); res.end(String(error)); }
});
await new Promise((resolve, reject) => {
  server.once("error", reject);
  server.listen(0, "127.0.0.1", resolve);
});
const origin = `http://127.0.0.1:${server.address().port}`;
let browser;
try {
  browser = await chromium.launch({ headless: true, ...(process.env.BROWSER_CHANNEL ? { channel: process.env.BROWSER_CHANNEL } : {}) });
  const context = await browser.newContext({ permissions: ["clipboard-read", "clipboard-write"] });
  const page = await context.newPage();
  await page.goto(origin);
  await page.locator("#copy").click();
  await page.waitForFunction(() => document.querySelector("#copy-status").textContent === "Copied");
  await assert.doesNotReject(async () => {
    for (let n = 0; n < 100 && events.length === 0; n++) await new Promise(r => setTimeout(r, 20));
    assert.equal(events.length, 1);
  });
  assert.equal(await page.evaluate(() => navigator.clipboard.readText()), "brew install --cask TechSupportz/tap/smpl-menubar");
  assert.deepEqual(events[0], { blobs: ["brew_copy"] });
  checks.push("Successful real clipboard copy records one fixed event");
  await page.screenshot({ path: `${output}/copied.png`, fullPage: true });

  await page.evaluate(() => Object.defineProperty(navigator.clipboard, "writeText", { configurable: true, value: () => Promise.reject(new Error("Denied")) }));
  await page.locator("#copy").click();
  await page.waitForFunction(() => document.querySelector("#copy-status").textContent === "Couldn’t copy");
  assert.equal(events.length, 1);
  checks.push("Denied clipboard copy records no event and shows fallback");

  await page.reload();
  await page.route("**/events/brew-copy", route => route.abort());
  await page.locator("#copy").click();
  await page.waitForFunction(() => document.querySelector("#copy-status").textContent === "Copied");
  assert.equal(events.length, 1);
  checks.push("Blocked analytics request preserves successful copy feedback");
  await page.unroute("**/events/brew-copy");

  // Exercise the actual download link; intercept only the external DMG.
  await page.route("https://example.com/smpl.dmg", route => route.fulfill({ contentType: "text/html", body: "Download target reached" }));
  await page.locator('a[href="/download"]').click();
  await page.waitForURL("https://example.com/smpl.dmg");
  assert.deepEqual(events[1], { blobs: ["download"] });
  checks.push("Download link records an event and redirects to release DMG");

  async function request(path, options = {}) {
    return nativeFetch(origin + path, { redirect: "manual", ...options });
  }
  assert.equal((await request("/download", { method: "HEAD" })).status, 302);
  assert.equal((await request("/download", { method: "POST" })).status, 405);
  assert.equal((await request("/events/brew-copy")).status, 405);
  assert.equal((await request("/events/brew-copy", { method: "POST", headers: { Origin: "https://other.example" } })).status, 403);
  assert.equal((await request("/events/brew-copy", { method: "POST" })).status, 403);
  assert.equal(events.length, 2);
  checks.push("HEAD, unsupported methods and cross-origin/missing-origin posts add no events");

  brokenAnalytics = true;
  assert.equal((await request("/download")).headers.get("location"), "https://example.com/smpl.dmg");
  assert.equal((await request("/events/brew-copy", { method: "POST", headers: { Origin: origin } })).status, 204);
  brokenGitHub = true;
  assert.equal((await request("/download")).headers.get("location"), "https://github.com/TechSupportz/smpl-menubar/releases/latest");
  checks.push("Analytics and GitHub outages preserve download redirects and copy endpoint");
  delete env.ANALYTICS;
  assert.equal((await request("/download")).status, 302);
  checks.push("Missing Analytics Engine binding leaves download usable");
  assert.deepEqual(await context.cookies(), []);
  checks.push("No cookies created; recorded payloads contain action names only");
  await writeFile(`${output}/report.json`, JSON.stringify({ passed: true, checks, events,
    scope: "Built site + production Worker through local HTTP adapter; Analytics Engine sink and GitHub release response simulated. Does not prove live Cloudflare ingestion." }, null, 2));
  console.log(JSON.stringify({ passed: true, checks: checks.length, artifact: output }));
} finally {
  await browser?.close();
  await new Promise(resolve => server.close(resolve));
  globalThis.fetch = nativeFetch;
}
