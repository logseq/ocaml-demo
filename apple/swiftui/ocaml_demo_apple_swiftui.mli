module Apple = Ocaml_demo_apple

type application_delegate = nativeint
type application = nativeint
type launch_options = nativeint
type controller
type window

module Backend : Apple.Renderer.Backend
module Renderer : module type of Apple.Renderer.Make (Backend)
module App : module type of Apple.App.Make (Backend)

module Http : sig
  type request =
    { method_ : string
    ; url : string
    ; authorization : string option
    ; body : string
    ; timeout_seconds : float
    }

  val send_json : request -> (string, string) Result.t Apple.Action.t
end

val run_application
  :  (application_delegate -> application -> launch_options -> bool)
  -> unit

val run_on_main : (unit -> unit) -> unit

val run_on_main_when_scroll_idle : (unit -> unit) -> unit

val run_on_main_after_rendered_frame : (unit -> unit) -> unit

val controller : Backend.view -> controller
val update_controller : controller -> Backend.view -> unit
val release_controller : controller -> unit
val window : Backend.view -> window
val release_window : window -> unit
