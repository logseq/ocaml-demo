(lang dune 3.17)
(using melange 0.1)

(name ocaml_demo)

(package
 (name ocaml_demo)
 (synopsis "Shared OCaml logic with native and web platform UIs")
 (depends
  (ocaml (>= 5.1.0))
  dune
  melange
  datascript_ocaml
  datascript-ocaml-native
  datascript-ocaml-melange
  (yojson :with-test)))
