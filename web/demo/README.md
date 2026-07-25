# OCaml React Demo

The Web UI, event handlers, and React element construction live in `main.ml`.
Melange compiles them to JavaScript. Counter, Todo, and Search actions call the
same `Ocaml_demo_model` used by every native application.

Build the Melange output:

```sh
npm run build
```

Run it in the browser:

```sh
cd web/demo
npm install
npm run dev
```

Run the Maestro browser test:

```sh
npm run test:maestro
```
