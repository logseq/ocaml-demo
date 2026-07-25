import { defineConfig } from "vite";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));
const generatedNodeModules = path.join(root, "dist", "node_modules");

export default defineConfig({
  build: {
    outDir: "site-dist",
  },
  resolve: {
    alias: {
      melange: path.join(generatedNodeModules, "melange"),
      "melange.js": path.join(generatedNodeModules, "melange.js"),
    },
  },
});
