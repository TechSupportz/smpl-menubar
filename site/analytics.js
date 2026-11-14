import { createRemoteJWKSet, jwtVerify } from "jose";

const ACCOUNT = "8ef5f0769d30e76799982b88b435da03";
const ISSUER = "https://tnitish.cloudflareaccess.com";
const keys = createRemoteJWKSet(new URL(`${ISSUER}/cdn-cgi/access/certs`));
const headers = { "Cache-Control": "private, no-store", "X-Robots-Tag": "noindex, nofollow", "X-Content-Type-Options": "nosniff" };

export async function analytics(request, env) {
  if (!env.ACCESS_AUD) return new Response("Dashboard unavailable", { status: 503, headers });
  try {
    await jwtVerify(request.headers.get("Cf-Access-Jwt-Assertion") || "", keys, {
      issuer: ISSUER, audience: env.ACCESS_AUD, algorithms: ["RS256"], requiredClaims: ["exp", "iat", "sub"],
    });
  } catch {
    return new Response("Sign in through Cloudflare Access", { status: 403, headers });
  }
  if (request.method !== "GET") return new Response(null, { status: 405, headers: { ...headers, Allow: "GET" } });
  const url = new URL(request.url);
  if (url.pathname === "/analytics/data") {
    const days = Number(url.searchParams.get("days") || 30);
    if (![7, 30, 90].includes(days)) return Response.json({ error: "Choose 7, 30 or 90 days" }, { status: 400, headers });
    if (!env.ANALYTICS_READ_TOKEN) return Response.json({ error: "Analytics unavailable" }, { status: 503, headers });
    try {
      // Fixed query, with an allowlisted range; never accept SQL from the client.
      const sql = `SELECT toDate(timestamp) AS day, blob1 AS action, SUM(_sample_interval) AS actions
        FROM smpl_menubar_actions WHERE timestamp >= toStartOfDay(NOW()) - INTERVAL '${days - 1}' DAY
        AND blob1 IN ('download', 'brew_copy') GROUP BY day, action ORDER BY day FORMAT JSON`;
      const result = await fetch(`https://api.cloudflare.com/client/v4/accounts/${ACCOUNT}/analytics_engine/sql`, {
        method: "POST", headers: { Authorization: `Bearer ${env.ANALYTICS_READ_TOKEN}` }, body: sql,
      });
      if (!result.ok) throw new Error("Analytics query failed");
      const payload = await result.json();
      if (!Array.isArray(payload.data)) throw new Error("Invalid analytics response");
      const today = new Date().toISOString().slice(0, 10);
      const rows = Array.from({ length: days }, (_, i) => {
        const date = new Date(`${today}T00:00:00Z`);
        date.setUTCDate(date.getUTCDate() - days + 1 + i);
        return { day: date.toISOString().slice(0, 10), download: 0, brew_copy: 0 };
      });
      for (const entry of payload.data) {
        const row = rows.find(row => row.day === entry.day);
        const value = Number(entry.actions);
        if (!["download", "brew_copy"].includes(entry.action) || !Number.isFinite(value) || value < 0) throw new Error("Invalid row");
        if (row) row[entry.action] += value;
      }
      const totals = rows.reduce((sum, row) => ({ download: sum.download + row.download, brew_copy: sum.brew_copy + row.brew_copy }), { download: 0, brew_copy: 0 });
      return Response.json({ days, rows, totals, updatedAt: new Date().toISOString() }, { headers });
    } catch {
      return Response.json({ error: "Couldn’t load analytics. Try refreshing." }, { status: 502, headers });
    }
  }
  if (!["/analytics", "/analytics/", "/analytics/index.html"].includes(url.pathname)) return new Response("Not found", { status: 404, headers });
  const response = await env.ASSETS.fetch(new Request(new URL("/analytics/", request.url), request));
  const protectedResponse = new Response(response.body, response);
  for (const [name, value] of Object.entries(headers)) protectedResponse.headers.set(name, value);
  return protectedResponse;
}
