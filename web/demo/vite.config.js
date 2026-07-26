import { defineConfig } from "vite";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));
const generatedNodeModules = path.join(root, "dist", "node_modules");

export default defineConfig({
  base: "./",
  server: {
    headers: {
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "require-corp",
    },
  },
  preview: {
    headers: {
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "require-corp",
    },
  },
  optimizeDeps: {
    exclude: ["@sqlite.org/sqlite-wasm"],
  },
  build: {
    outDir: "site-dist",
  },
  resolve: {
    alias: {
      melange: path.join(generatedNodeModules, "melange"),
      "melange.js": path.join(generatedNodeModules, "melange.js"),
      datascript_ocaml: path.join(generatedNodeModules, "datascript_ocaml"),
      "datascript_ocaml.types": path.join(generatedNodeModules, "datascript_ocaml.types"),
      "datascript-ocaml-melange": path.join(
        generatedNodeModules,
        "datascript-ocaml-melange",
      ),
      "datascript-ocaml-melange.storage": path.join(
        generatedNodeModules,
        "datascript-ocaml-melange.storage",
      ),
      "melange-edn-melange": path.join(
        generatedNodeModules,
        "melange-edn-melange",
      ),
      "melange-transit-melange": path.join(
        generatedNodeModules,
        "melange-transit-melange",
      ),
      persistent_sorted_set_ocaml: path.join(
        generatedNodeModules,
        "persistent_sorted_set_ocaml",
      ),
      "persistent_sorted_set_ocaml-melange": path.join(
        generatedNodeModules,
        "persistent_sorted_set_ocaml-melange",
      ),
    },
  },
});
