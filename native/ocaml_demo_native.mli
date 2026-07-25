module Action : sig
  type t = unit -> unit

  val ignore : t
  val of_thunk : (unit -> unit) -> t
  val many : t list -> t
end

type graph

module Graph : sig
  val state
    :  ?equal:('a -> 'a -> bool)
    -> graph
    -> key:string
    -> 'a
    -> 'a * ('a -> Action.t)

  val scope : graph -> key:string -> (graph -> 'a) -> 'a

  val derived
    :  ?equal:('input -> 'input -> bool)
    -> graph
    -> key:string
    -> input:'input
    -> f:('input -> 'result)
    -> 'result

  val subscribe
    :  ?equal:('a -> 'a -> bool)
    -> graph
    -> key:string
    -> default:'a
    -> (emit:('a -> unit) -> unit -> unit)
    -> 'a
end

module Component : sig
  val state
    :  ?equal:('a -> 'a -> bool)
    -> graph
    -> key:string
    -> 'a
    -> 'a * ('a -> Action.t)

  val scope : graph -> key:string -> (graph -> 'a) -> 'a
end

val state
  :  ?equal:('a -> 'a -> bool)
  -> graph
  -> key:string
  -> 'a
  -> 'a * ('a -> Action.t)

val scope : graph -> key:string -> (graph -> 'a) -> 'a

type edge_insets =
  { top : float
  ; start : float
  ; bottom : float
  ; end_ : float
  }

type frame =
  { width : float option
  ; height : float option
  }

type toolbar_item =
  { id : string
  ; title : string
  ; on_click : Action.t
  }

type node

val text : string -> node
val button : ?is_enabled:bool -> string -> on_click:Action.t -> node

val text_field
  :  ?placeholder:string
  -> text:string
  -> on_change:(string -> Action.t)
  -> unit
  -> node

val vstack : ?spacing:float -> node list -> node
val hstack : ?spacing:float -> node list -> node
val scroll_view : node -> node
val list : 'a list -> key:('a -> string) -> row:('a -> node) -> node
val navigation_stack : node list -> node
val image : string -> node
val custom_view : ?key:string -> kind:string -> unit -> node
val padding : ?insets:edge_insets -> node -> node
val frame : ?width:float -> ?height:float -> node -> node
val searchable : text:string -> on_change:(string -> Action.t) -> node -> node
val toolbar_item : id:string -> title:string -> on_click:Action.t -> toolbar_item
val toolbar : toolbar_item list -> node -> node

val sheet
  :  is_presented:bool
  -> content:node
  -> ?on_dismiss:Action.t
  -> node
  -> node

module Bridge : sig
  type t

  val render : schedule_event:(Action.t -> unit) -> node -> t
  val json : t -> string
  val dispatch_click : t -> int -> unit
  val dispatch_change : t -> int -> text:string -> unit
end

module App_driver : sig
  type ('result, 'rendered) t

  val create
    :  (graph -> 'result)
    -> render:(schedule_event:(Action.t -> unit) -> 'result -> 'rendered)
    -> update:
         ('rendered -> schedule_event:(Action.t -> unit) -> 'result -> 'rendered)
    -> ('result, 'rendered) t

  val flush : ('result, 'rendered) t -> unit
  val flush_and_render : ('result, 'rendered) t -> unit
  val schedule_event : ('result, 'rendered) t -> Action.t -> unit
  val schedule_event_and_render : ('result, 'rendered) t -> Action.t -> unit
  val rendered : ('result, 'rendered) t -> 'rendered option
end

module App : sig
  type t

  val create : (graph -> node) -> t
  val render_json : t -> string
  val dispatch_click : t -> int -> unit
  val dispatch_change : t -> int -> text:string -> unit
end
