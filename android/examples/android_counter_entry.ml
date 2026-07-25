let apps : (string, Ocaml_demo_android.App.t) Hashtbl.t = Hashtbl.create 3

let app_for demo_id =
  let demo_id = Android_demo_components.normalize_id demo_id in
  match Hashtbl.find_opt apps demo_id with
  | Some app -> app
  | None ->
    let app = Ocaml_demo_android.App.create (Android_demo_components.component_by_id demo_id) in
    Hashtbl.replace apps demo_id app;
    app
;;

let render demo_id = Ocaml_demo_android.App.render_json (app_for demo_id)

let dispatch_click demo_id event_id =
  Ocaml_demo_android.App.dispatch_click (app_for demo_id) event_id
;;

let dispatch_change demo_id event_id text =
  Ocaml_demo_android.App.dispatch_change (app_for demo_id) event_id ~text
;;

let () =
  Callback.register "ocaml_demo_android_render" render;
  Callback.register "ocaml_demo_android_dispatch_click" dispatch_click;
  Callback.register "ocaml_demo_android_dispatch_change" dispatch_change
;;
