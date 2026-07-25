# Native SwiftUI backend

This backend is a SwiftUI implementation target for the OCaml
`Ocaml_demo_apple.Renderer.Backend` shape.

The boundary is intentionally generic:

- OCaml owns the graph state, node tree, reconciliation, and effects.
- The Apple renderer creates and patches backend view nodes from OCaml.
- SwiftUI observes those backend nodes and maps generic node kinds to native controls.
- SwiftUI sends event ids and optional text values back through a C callback.

SwiftUI is the maintained Apple renderer.

The Swift side does not contain app-specific UI. App UX should come from the OCaml node tree and backend styling conventions.

App authors should not edit this backend to build one screen. They should use
`Ocaml_demo_apple` primitives. If a native concept such as bottom tabs, sidebars, or
split navigation is missing, add it once to the shared OCaml API and implement
it in `ocaml_demo_apple.swiftui`.

The current Swift runtime exposes C symbols for:

- Creating/releasing generic backend nodes.
- Updating text, placeholder, spacing, children, event ids, searchable state, and sheets.
- Hosting a root node in a `UIHostingController`.

The OCaml `ocaml_demo_apple.swiftui` module implements
`Ocaml_demo_apple.Renderer.Backend` by calling these symbols. App targets that
instantiate it must also link the compiled Swift runtime object or archive.
