# iOS Native Build

The iOS app uses native SwiftUI and calls the shared OCaml reducer through the
single JSON/C ABI function.

## Requirements

- macOS with Xcode and the iOS Simulator SDK
- Swift
- Git and Make

An iOS opam switch is not required.

## Build

From the repository root:

```sh
scripts/build-mobile-ios-simulator.sh
```

On the first build, `scripts/bootstrap-ios-ocaml.sh` clones the official OCaml
5.5 stable tag and builds an arm64 iOS Simulator compiler with `make crossopt`.
Later builds reuse the compiler under `_build/ios-toolchain`.

The build compiles the shared reducer and mobile RPC to a complete OCaml object,
compiles the C ABI adapter for the simulator, links both into the Swift package,
and creates:

```text
mobile/.build/OCamlDemo.app
```

The deployment target defaults to iOS 17.0. Override it with:

```sh
OCAML_DEMO_IOS_DEPLOYMENT_TARGET=18.0 \
  scripts/build-mobile-ios-simulator.sh
```

Run the toolchain integration check with:

```sh
scripts/test-ios-ocaml-toolchain.sh
```
