const REPO = "TechSupportz/smpl-menubar";
const FALLBACK = `https://github.com/${REPO}/releases/latest`;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname !== "/download") return env.ASSETS.fetch(request);

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
