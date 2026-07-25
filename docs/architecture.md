# Architecture

`ocaml-demo` keeps business state and actions in a shared OCaml reducer.
Platform UI remains native and owns presentation-only state.

```text
                         +-> iOS SwiftUI
SwiftUI / Skip Lite UI --+
                         +-> Android Kotlin / Compose
                                  |
                         one JSON request/response
                                  |
                           C ABI / JNA or JNI
                                  |
                         shared OCaml reducer

Web / Desktop ----------------> shared OCaml reducer
                              (direct typed calls)
```

## Shared Runtime

`examples/shared/ocaml_demo_model.ml` currently owns:

- The immutable Counter, Todo, and Search state.
- Typed actions and validation.
- Stable Todo identifiers.
- Search filtering.
- A revision number that lets clients observe state changes.

It has no UI, JSON, C, Swift, Kotlin, or platform dependency. Web and Desktop
call it directly. Mobile uses a thin RPC adapter because an FFI cannot carry
OCaml values safely across the language boundary.

## Mobile Boundary

Mobile exposes exactly one operation:

```c
const char *ocaml_demo_call(const char *request_json);
```

The versioned JSON envelope supports:

- `snapshot`: read one screen projection.
- `dispatch`: apply a typed action and return the updated projection.

Errors are structured and use the same response envelope. The C wrapper owns
OCaml runtime initialization and serializes access to the current process-local
model.

This coarse boundary keeps FFI code small. It trades some JSON encoding work for
an API that is stable, easy to test, and independent of the number of domain
actions. UI trees, closures, and platform widget identifiers never cross it.

## UI Ownership

`mobile/Sources/OCamlDemo/` is the UI source of truth:

- iOS compiles it as SwiftUI.
- Skip Lite transpiles it to Kotlin/Compose for Android.
- Views decode OCaml snapshots and send actions; they do not implement domain
  transitions.

Platform-only concerns such as focus, navigation presentation, animation, and
temporary text editing may remain in SwiftUI/Compose. Persisted or business
meaningful state belongs in OCaml.

## Platform Integration

iOS links the cross-compiled OCaml object into the application and calls
`ocaml_demo_call` through the C ABI.

Android loads `libocaml_demo_core.so` and binds the same symbol from generated
Kotlin through SkipFFI/JNA. The library is built with the official OCaml 5.5.0
`make crossopt` flow and the Android NDK.

The older `ocaml_demo_native`, `ocaml_demo_android`, and `ocaml_demo_apple`
UI-tree APIs are kept for compatibility and experiments. New shared application
behavior should be added to the pure reducer rather than those rendering
bridges.
