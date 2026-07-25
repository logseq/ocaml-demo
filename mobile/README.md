# OCaml Demo

The mobile app has one SwiftUI source under `Sources/OCamlDemo`.

- iOS compiles the source as SwiftUI and links the OCaml core object directly.
- Skip Lite transpiles the same source to Kotlin/Compose for Android.
- Both platforms call one JSON API through `ocaml_demo_call`.
- Business state and transitions live in `examples/shared`.

Run the shared Swift and generated Kotlin tests:

```sh
swift test --disable-keychain
```

Build the iOS Simulator application from the repository root:

```sh
scripts/build-mobile-ios-simulator.sh
```

Build the OCaml Android library from the repository root:

```sh
scripts/build-android-native.sh
```

Then compile the Android app:

```sh
cd Android
gradle :app:assembleDebug --console=plain
```

The APK contains `libocaml_demo_core.so` and calls the same shared OCaml reducer
through SkipFFI/JNA.
