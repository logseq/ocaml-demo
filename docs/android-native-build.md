# Android OCaml Core

The Android app uses the same architecture as iOS:

```text
SwiftUI source
  -> Skip Lite
  -> Kotlin / Compose
  -> SkipFFI / JNA
  -> ocaml_demo_call
  -> shared OCaml reducer
```

The native library is built with the cross-compilation support included in the
official OCaml compiler repository. No Android opam fork or target opam switch
is required.

## Requirements

- OCaml 5.5.0 source release
- Android SDK
- Android NDK
- Git and a C build toolchain

The bootstrap script builds matching host and Android compilers from the OCaml
5.5.0 tag. Android targets include the minimum API level in the compiler
triplet, such as `aarch64-linux-android21`.

## Build

From the repository root:

```sh
scripts/build-android-native.sh
```

The first run downloads and builds OCaml 5.5.0. Later builds reuse the
toolchain under `_build/android-toolchain`.

The default output is:

```text
mobile/Android/app/src/main/jniLibs/arm64-v8a/libocaml_demo_core.so
```

Build the APK:

```sh
cd mobile/Android
gradle :app:assembleDebug --console=plain
```

The Skip Gradle plugin writes the APK to:

```text
mobile/.build/Android/app/outputs/apk/debug/app-debug.apk
```

## Other targets

The scripts support the `arm64-v8a` and `x86_64` Android ABIs:

```sh
OCAML_DEMO_ANDROID_ABI=x86_64 scripts/build-android-native.sh
```

The API level defaults to 21 and can be changed with:

```sh
OCAML_DEMO_ANDROID_API_LEVEL=24 scripts/build-android-native.sh
```

The OCaml version defaults to the stable 5.5.0 release:

```sh
OCAML_DEMO_ANDROID_OCAML_VERSION=5.5.0 scripts/build-android-native.sh
```

## Emulator verification

Start an ARM64 emulator, build the native library and APK, then run:

```sh
scripts/test-mobile-android-emulator.sh
```

The test installs the APK, launches `OCaml Demo`, taps the generated Compose
counter button, and verifies that the shared OCaml reducer changes the displayed
value from `0` to `1`.
