import { defineConfig } from "astro/config";
import react from "@astrojs/react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  site: "https://smpl-menubar.tnitish.com",
  integrations: [react()],
  devToolbar: { enabled: false },
  vite: { plugins: [tailwindcss()] },
});
