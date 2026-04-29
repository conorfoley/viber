import { defineConfig } from "wxt";

export default defineConfig({
  modules: ["@wxt-dev/module-svelte"],
  outDir: "output",
  runner: {
    disabled: true,
  },
  manifest: {
    name: "Viber Accessibility Agent",
    description: "Control web pages with natural language via the Viber AI agent.",
    permissions: ["activeTab", "scripting", "storage", "tabs"],
    host_permissions: ["http://localhost:4100/*"],
    icons: {
      16: "icons/icon-16.png",
      48: "icons/icon-48.png",
      128: "icons/icon-128.png",
    },
    action: {
      default_title: "Viber Agent",
      default_icon: {
        16: "icons/icon-16.png",
        48: "icons/icon-48.png",
        128: "icons/icon-128.png",
      },
    },
  },
});
