import { defineConfig } from "vite";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));
const generatedNodeModules = path.join(root, "dist", "node_modules");

export default defineConfig({
  resolve: {
    alias: {
      ocaml_demo_android: path.join(generatedNodeModules, "ocaml_demo_android"),
      ocaml_demo_native: path.join(generatedNodeModules, "ocaml_demo_native"),
      melange: path.join(generatedNodeModules, "melange"),
      "melange.js": path.join(generatedNodeModules, "melange.js"),
    },
  },
});
