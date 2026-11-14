import { analytics } from "./analytics.js";

const REPO = "TechSupportz/smpl-menubar";
const FALLBACK = `https://github.com/${REPO}/releases/latest`;

function record(env, action) {
  try {
    env.ANALYTICS?.writeDataPoint({ blobs: [action] });
  } catch {
    // Analytics must never interrupt downloading or copying.
  }
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname === "/analytics" || url.pathname.startsWith("/analytics/")) return analytics(request, env);
    if (url.pathname === "/events/brew-copy") {
      const headers = { "Cache-Control": "no-store" };
      if (request.method !== "POST") {
        return new Response(null, { status: 405, headers: { ...headers, Allow: "POST" } });
      }
      if (request.headers.get("Origin") !== url.origin) {
        return new Response(null, { status: 403, headers });
      }
      record(env, "brew_copy");
      return new Response(null, { status: 204, headers });
    }
    if (url.pathname !== "/download") return env.ASSETS.fetch(request);
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response(null, { status: 405, headers: { Allow: "GET, HEAD" } });
    }
    if (request.method === "GET") record(env, "download");

    try {
      const res = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
        headers: { "User-Agent": "smpl-menubar-site", Accept: "application/vnd.github+json" },
        cf: { cacheTtl: 300, cacheEverything: true },
      });
      if (!res.ok) throw new Error(res.status);
      const release = await res.json();
      const dmg = release.assets?.find((a) => a.name.endsWith(".dmg"));
      return Response.redirect(dmg?.browser_download_url ?? FALLBACK, 302);
    } catch {
      return Response.redirect(FALLBACK, 302);
    }
  },
};
