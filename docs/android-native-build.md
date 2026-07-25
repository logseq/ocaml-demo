# Android Native Build

> Legacy UI-tree build path. The current mobile architecture uses Skip Lite
> SwiftUI/Compose with the single `ocaml_demo_call` API. Cross-compiling and
> packaging `libocaml_demo_core.so` for that app is currently deferred.

The Android demo loads:

```text
android/_build/android/jniLibs/arm64-v8a/libocaml_demo_android_counter.so
```

That shared library contains:

- the OCaml runtime
- the local OCaml graph runtime built for Android
- the OCaml Android demo entrypoint
- JNI functions from `android/jni/ocaml_demo_android_jni.c`

## Cross Compiler

Use the Logseq Android cross-compiler fork:

```sh
git clone git@github.com:logseq/opam-cross-android.git \
  ~/Codes/projects/opam-cross-android
cd ~/Codes/projects/opam-cross-android
git checkout logseq/ocaml-android-5.2.1
```

The branch installs Android PIC runtime aliases needed by `ocamlopt -shared`.

Create or reuse an OCaml 5.2.1 switch for this repository:

```sh
cd ~/Codes/projects/ocaml-demo
opam switch create . 5.2.1
eval "$(opam env)"
opam repo add android-local file://$HOME/Codes/projects/opam-cross-android --this-switch
opam repo add janestreet-bleeding https://github.com/janestreet/opam-repository.git --this-switch
opam repo add janestreet-bleeding-external \
  https://github.com/janestreet/opam-repository.git#external-packages \
  --this-switch
opam install conf-android ocaml-android ocamlfind dune
```

Install host dependencies, then build the Jane runtime packages into the Android
target sysroot:

```sh
DUNE_WORKSPACE=$PWD/dune-workspace.basement-flags \
  opam install . --deps-only --with-test

scripts/bootstrap-android-jane.sh --clean
```

The bootstrap script builds target copies of the small runtime packages needed
by the Android cross switch.

## Build The Native Library

```sh
scripts/build-android-native.sh
```

The script builds:

```sh
dune build -x android android/examples/android_counter_entry.so
```

and copies the result to Gradle's `jniLibs` input.

To use a non-local switch:

```sh
OCAML_DEMO_OPAM_SWITCH=/path/to/switch scripts/build-android-native.sh
```

## Build And Run The APK

```sh
cd android
rtk proxy ./gradlew :app:assembleDebug
```

Confirm the APK contains the native library:

```sh
unzip -l app/build/outputs/apk/debug/app-debug.apk | rg libocaml_demo_android_counter
```

Run the emulator smoke test:

```sh
cd ..
scripts/test-android-emulator.sh
```

Expected result:

```text
Verified Android demo parity tabs and native click dispatch: 0 -> 1
```

The smoke test installs the APK, verifies the Android `Counter`, `Todo`, and
`Search` tabs, and confirms that tapping `Increment` updates OCaml state through
JNI.

## Notes

The debug `.so` is currently large because it is unstripped and includes the
OCaml runtime and local graph packages. Release-size work should strip symbols
and consider package/linker pruning separately from correctness.
