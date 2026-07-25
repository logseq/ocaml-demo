# Apple Native Build

The Apple package lives under `apple/` and exposes `ocaml_demo_apple`.

It uses the local OCaml graph runtime, SwiftUI backend, and OCaml 5.4.1 iOS
cross switches.

## Host Dependencies

```sh
cd ~/Codes/projects/ocaml-demo
opam switch create . 5.4.1
eval "$(opam env)"
opam repo add janestreet-bleeding https://github.com/janestreet/opam-repository.git --this-switch
opam repo add janestreet-bleeding-external \
  https://github.com/janestreet/opam-repository.git#external-packages \
  --this-switch
DUNE_WORKSPACE=$PWD/dune-workspace.basement-flags \
  opam install . --deps-only --with-test
```

## iOS Cross Switch

Use the 5.4.1 opam-cross-ios packages:

```sh
git clone https://github.com/tiensonqin/opam-cross-ios.git \
  ~/Codes/projects/opam-cross-ios
cd ~/Codes/projects/opam-cross-ios
```

Create a simulator switch:

```sh
opam switch create simulator-5.4.1 5.4.1
opam repo add ios-local file://$HOME/Codes/projects/opam-cross-ios --switch=simulator-5.4.1
opam repo add janestreet-bleeding https://github.com/janestreet/opam-repository.git --switch=simulator-5.4.1
opam repo add janestreet-bleeding-external \
  https://github.com/janestreet/opam-repository.git#external-packages \
  --switch=simulator-5.4.1
opam install --switch=simulator-5.4.1 conf-simulator-ios
ARCH=arm64 SUBARCH=arm64 PLATFORM=iPhoneSimulator \
  SDK=$(xcrun --sdk iphonesimulator --show-sdk-version) VER=17.0 \
  opam install --switch=simulator-5.4.1 conf-ios
opam install --switch=simulator-5.4.1 ocamlfind ocaml-ios
```

Create a physical-device switch:

```sh
opam switch create device-5.4.1 5.4.1
opam repo add ios-local file://$HOME/Codes/projects/opam-cross-ios --switch=device-5.4.1
opam repo add janestreet-bleeding https://github.com/janestreet/opam-repository.git --switch=device-5.4.1
opam repo add janestreet-bleeding-external \
  https://github.com/janestreet/opam-repository.git#external-packages \
  --switch=device-5.4.1
ARCH=arm64 SUBARCH=arm64 PLATFORM=iPhoneOS \
  SDK=$(xcrun --sdk iphoneos --show-sdk-version) VER=17.0 \
  opam install --switch=device-5.4.1 conf-ios
opam install --switch=device-5.4.1 ocamlfind ocaml-ios
```

The repository's Dune workspaces point at these switches:

```lisp
;; dune-workspace.simulator
(switch simulator-5.4.1)

;; dune-workspace.device
(switch device-5.4.1)
```

If you keep custom switch names, update the workspace files to match them.

No local iOS compiler patches or bootstrap step are needed for the current
5.4.1 flow.

Install the project build dependencies in each cross switch:

```sh
opam install --switch=simulator-5.4.1 . --deps-only --with-test
opam install --switch=device-5.4.1 . --deps-only --with-test
```

## Build The Demo App

```sh
IOS_TARGET=arm64-apple-ios17.0-simulator \
IOS_ARCH=arm64 \
IOS_SDKROOT=$(xcrun --sdk iphonesimulator --show-sdk-path) \
opam exec -- dune build apple/examples/OCamlDemoDemos.app \
  --workspace dune-workspace.simulator
```

For a physical device:

```sh
IOS_TARGET=arm64-apple-ios17.0 \
IOS_ARCH=arm64 \
IOS_SDKROOT=$(xcrun --sdk iphoneos --show-sdk-path) \
opam exec -- dune build apple/examples/OCamlDemoDemos.app \
  --workspace dune-workspace.device
```

The maintained Apple backend is SwiftUI.
