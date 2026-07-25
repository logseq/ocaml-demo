# React Demo

This demo renders the existing OCaml counter component through React. State and actions stay in OCaml through `Ocaml_demo_android.App`; React only renders the JSON node tree and sends events back to OCaml.

Build the generated Melange output:

```sh
opam exec -- dune build @web-demo
```

Run it in the browser:

```sh
cd web/demo
npm install
npm run build
npm run dev
```

`vite.config.js` maps Melange-generated package imports to `dist/node_modules`.
