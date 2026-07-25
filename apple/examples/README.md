# ocaml-demo Apple examples

These files are component examples.  They intentionally define graph components
that return `Ocaml_demo_apple.node`; the SwiftUI app delegate is responsible for
instantiating an Apple backend and mounting the component with
`Ocaml_demo_apple.App.Make`.

Examples:

- `counter.ml`
- `todo.ml`
- `searchable_list.ml`
- `navigation.ml`
- `ios_app.ml`
