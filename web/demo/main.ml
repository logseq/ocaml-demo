module App = Ocaml_demo_android.App

type renderer

external create_renderer
  :  string
  -> (unit -> string)
  -> (int -> unit)
  -> (int -> string -> unit)
  -> renderer
  = "createRenderer"
  [@@mel.module "./react_runtime.js"]

external render : renderer -> unit = "render" [@@mel.send]

let app = App.create (Android_demo_components.component_by_id "counter")

let renderer =
  create_renderer
    "root"
    (fun () -> App.render_json app)
    (fun event_id -> App.dispatch_click app event_id)
    (fun event_id text -> App.dispatch_change app event_id ~text)
;;

let () = render renderer
