# ocaml-demo

`ocaml-demo` keeps journal, outliner, and task state transitions in one
DataScript-backed OCaml model while each platform owns only its UI.

```text
examples/shared/ocaml_demo_model.ml
                 |
       +---------+---------+
       |                   |
 shared JSON RPC       direct typed calls
       |                   |
 iOS / Android /       Web: OCaml + Melange
 macOS SwiftUI              + React
```

The native apps expose one C function:

```c
const char *ocaml_demo_call(const char *request_json);
```

iOS and macOS compile the SwiftUI source natively. Skip Lite transpiles the same
SwiftUI source to Kotlin/Compose for Android. Web UI and event handling are
written in OCaml and compiled to React calls by Melange.

## Repository Layout

- `examples/shared/`: the only business model, shared JSON implementation, RPC,
  and OCaml tests.
- `mobile/`: one SwiftUI source for iOS, Android, and macOS plus the C ABI.
- `web/demo/`: OCaml React UI compiled by Melange.
- `scripts/`: OCaml 5.5 cross-toolchain, native app, and architecture checks.
- `docs/`: current architecture and platform build instructions.

Native apps persist the DataScript storage protocol to SQLite. The browser uses
the same OCaml model and persists it through SQLite-Wasm OPFS. Dependencies are
resolved from their upstream GitHub repositories; source code is not vendored.

Platform code must not define business actions or duplicate state transitions.

## Checks

```sh
opam exec -- dune build @shared-platform-check
opam exec -- dune runtest
swift test --disable-keychain --package-path mobile
```

## Build Applications

```sh
scripts/build-mobile-ios-simulator.sh
scripts/build-android-native.sh
scripts/build-desktop-macos.sh
opam exec -- dune build @web-demo
```

iOS and Android target compilers are built directly from the official stable
OCaml 5.5 release and do not require target opam switches.
