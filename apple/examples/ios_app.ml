module Swiftui = Ocaml_demo_apple_swiftui
module App = Swiftui.App

let mounted_apps = ref []
let window = ref None

let install_root_window _app_delegate _application _launch_options =
  let app = App.create Ocaml_demo_apple_examples.Ios_demo_app.component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render a root view"
  in
  window := Some (Swiftui.window root);
  mounted_apps := [ app ];
  true
;;

let main () = Swiftui.run_application install_root_window

let () = main ()
