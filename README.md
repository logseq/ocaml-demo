# ocaml-demo

`ocaml-demo` shares application state and business actions in OCaml while
keeping the UI native on every platform.

The iOS and Android application is named **OCaml Demo**.

```text
SwiftUI source
  -> iOS SwiftUI
  -> Skip Lite -> Android Kotlin / Compose
  -> one JSON RPC -> shared OCaml reducer

Web / Desktop
  -> direct calls -> shared OCaml reducer
```

The mobile boundary intentionally exposes one C function:

```c
const char *ocaml_demo_call(const char *request_json);
```

OCaml decodes the request, dispatches the typed action, and returns the updated
screen snapshot. UI structure and widget state do not cross the FFI boundary.

## Shared Logic

`examples/shared/ocaml_demo_model.ml` is the source of truth for the current
Counter, Todo, and Search examples. The model is a pure OCaml reducer and is
used by:

- iOS through the mobile JSON/C ABI adapter.
- Android's generated Compose UI through the same JSON API once the Android
  OCaml native library is packaged.
- Web and Desktop directly, without serializing through JSON.
- The existing Apple and Android example adapters.

The older OCaml UI-tree packages remain in the repository for compatibility
and experimentation, but they are no longer the application architecture.

## Repository Layout

- `examples/shared/`: platform-neutral OCaml model, actions, and tests.
- `mobile/`: Skip Lite SwiftUI app, the single mobile RPC, generated Android
  app shell, and iOS launcher.
- `native/`: shared `ocaml_demo_native` implementation.
- `src/`: Android OCaml facade.
- `android/`: legacy Gradle/Compose demo app.
- `android/examples/`: Android demo components, native entrypoint, and asset
  export helpers.
- `android/jni/`: Android JNI bridge into OCaml.
- `apple/`: Apple OCaml package, SwiftUI backend, and iOS/macOS examples.
- `web/demo/`: browser demo backed by the shared OCaml model.
- `scripts/`: Android and iOS bootstrap/build helpers.
- `docs/`: architecture and platform build notes.

## Checks

```sh
opam exec -- dune build @shared-platform-check
cd mobile && swift test --disable-keychain
```

Build the iOS Simulator app:

```sh
scripts/build-mobile-ios-simulator.sh
```

## Status

Working now:

- One shared OCaml reducer for Counter, Todo, and Search.
- One mobile JSON RPC and C ABI entry point.
- One SwiftUI source transpiled by Skip Lite to Kotlin/Compose.
- End-to-end iOS Simulator flow from SwiftUI through C ABI to OCaml.
- Web and Desktop adapters reuse the same reducer.

Deferred:

- Building and packaging the OCaml native library for Android. The generated
  Compose app shell builds, but it must not be launched without
  `libocaml_demo_core.so`.
