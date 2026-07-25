(lang dune 3.17)
(using melange 0.1)

(name ocaml_demo)

(package
 (name ocaml_demo_native)
 (synopsis "Shared native UI runtime for OCaml")
 (description
  "Platform-independent OCaml node tree, event bridge, and component runtime for native backends.")
 (depends
  (ocaml (>= 5.1.0))
  dune
  melange
  yojson))

(package
 (name ocaml_demo_android)
 (synopsis "Native Android UI backend for OCaml")
 (description
  "A Jetpack Compose backed native Android UI framework for OCaml.")
 (depends
  (ocaml (>= 5.1.0))
  dune
  ocaml_demo_native))

(package
 (name ocaml_demo_apple)
 (synopsis "Native Apple UI backend for OCaml")
 (description
  "A SwiftUI-like declarative native Apple UI framework for OCaml.")
 (depends
  (ocaml (>= 5.1.0))
  dune
  ocaml_demo_native))
