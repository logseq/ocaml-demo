module Action = struct
  type t = unit -> unit

  let ignore () = ()
  let of_thunk f = f

  let many actions () =
    List.iter (fun action -> action ()) actions
  ;;
end

type graph =
  { cells : (string, cell) Hashtbl.t
  ; derived_cells : (string, derived_cell) Hashtbl.t
  ; subscriptions : (string, subscription) Hashtbl.t
  ; mutable path : string list
  ; invalidate : unit -> unit
  ; generation : int
  }

and cell =
  { mutable value : Obj.t
  ; equal : Obj.t -> Obj.t -> bool
  }

and derived_cell =
  { mutable input : Obj.t
  ; input_equal : Obj.t -> Obj.t -> bool
  ; mutable derived_value : Obj.t
  }

and subscription =
  { mutable subscription_value : Obj.t
  ; subscription_equal : Obj.t -> Obj.t -> bool
  ; mutable cancel : unit -> unit
  ; mutable canceled : bool
  ; mutable last_seen_generation : int
  }

let full_key graph key =
  String.concat "/" (List.rev (key :: graph.path))
;;

module Graph = struct
  let state ?(equal = ( = )) graph ~key initial =
    let key = full_key graph key in
    let initial_value = Obj.repr initial in
    let equal_obj left right = equal (Obj.obj left) (Obj.obj right) in
    let cell =
      match Hashtbl.find_opt graph.cells key with
      | Some cell -> cell
      | None ->
        let cell = { value = initial_value; equal = equal_obj } in
        Hashtbl.add graph.cells key cell;
        cell
    in
    let set next () =
      let next_value = Obj.repr next in
      if not (cell.equal cell.value next_value)
      then (
        cell.value <- next_value;
        graph.invalidate ())
    in
    Obj.obj cell.value, set
  ;;

  let scope graph ~key f =
    let old_path = graph.path in
      graph.path <- key :: graph.path;
      Fun.protect ~finally:(fun () -> graph.path <- old_path) (fun () -> f graph)
  ;;

  let derived ?(equal = ( = )) graph ~key ~input ~f =
    let key = full_key graph key in
    let input_value = Obj.repr input in
    let input_equal left right = equal (Obj.obj left) (Obj.obj right) in
    match Hashtbl.find_opt graph.derived_cells key with
    | Some cell when cell.input_equal cell.input input_value ->
      Obj.obj cell.derived_value
    | Some cell ->
      let next_value = f input in
      cell.input <- input_value;
      cell.derived_value <- Obj.repr next_value;
      next_value
    | None ->
      let derived_value = f input in
      let cell =
        { input = input_value; input_equal; derived_value = Obj.repr derived_value }
      in
      Hashtbl.add graph.derived_cells key cell;
      derived_value
  ;;

  let subscribe ?(equal = ( = )) graph ~key ~default start =
    let key = full_key graph key in
    let equal_obj left right = equal (Obj.obj left) (Obj.obj right) in
    match Hashtbl.find_opt graph.subscriptions key with
    | Some subscription ->
      subscription.last_seen_generation <- graph.generation;
      Obj.obj subscription.subscription_value
    | None ->
      let subscription =
        { subscription_value = Obj.repr default
        ; subscription_equal = equal_obj
        ; cancel = (fun () -> ())
        ; canceled = false
        ; last_seen_generation = graph.generation
        }
      in
      let emit next =
        if not subscription.canceled
        then (
          let next_value = Obj.repr next in
          if not (subscription.subscription_equal subscription.subscription_value next_value)
          then (
            subscription.subscription_value <- next_value;
            graph.invalidate ()))
      in
      subscription.cancel <- start ~emit;
      Hashtbl.add graph.subscriptions key subscription;
      Obj.obj subscription.subscription_value
  ;;
end

module Component = struct
  let state = Graph.state
  let scope = Graph.scope
end

let state = Graph.state
let scope = Graph.scope

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

type node =
  | Text of string
  | Button of
      { title : string
      ; is_enabled : bool
      ; on_click : Action.t
      }
  | Text_field of
      { text : string
      ; placeholder : string option
      ; on_change : string -> Action.t
      }
  | Stack of
      { axis : [ `Vertical | `Horizontal ]
      ; spacing : float option
      ; children : node list
      }
  | Scroll_view of node
  | List of keyed_node list
  | Navigation_stack of node list
  | Image of string
  | Custom_view of
      { key : string option
      ; kind : string
      }
  | Modified of modifier * node

and keyed_node =
  { key : string
  ; node : node
  }

and modifier =
  | Padding of edge_insets
  | Frame of frame
  | Searchable of
      { text : string
      ; on_change : string -> Action.t
      }
  | Toolbar of toolbar_item list
  | Sheet of
      { is_presented : bool
      ; content : node
      ; on_dismiss : Action.t option
      }

let text value = Text value
let button ?(is_enabled = true) title ~on_click = Button { title; is_enabled; on_click }

let text_field ?placeholder ~text ~on_change () =
  Text_field { text; placeholder; on_change }
;;

let vstack ?spacing children = Stack { axis = `Vertical; spacing; children }
let hstack ?spacing children = Stack { axis = `Horizontal; spacing; children }
let scroll_view child = Scroll_view child
let navigation_stack children = Navigation_stack children
let image name = Image name
let custom_view ?key ~kind () = Custom_view { key; kind }

let list rows ~key ~row =
  let seen = Hashtbl.create (List.length rows) in
  List
    (List.map
       (fun value ->
         let key = key value in
         if Hashtbl.mem seen key
         then failwith ("duplicate native list key: " ^ key);
         Hashtbl.add seen key ();
         { key; node = row value })
       rows)
;;

let default_insets = { top = 8.; start = 8.; bottom = 8.; end_ = 8. }
let padding ?(insets = default_insets) node = Modified (Padding insets, node)
let frame ?width ?height node = Modified (Frame { width; height }, node)
let searchable ~text ~on_change node = Modified (Searchable { text; on_change }, node)
let toolbar_item ~id ~title ~on_click = { id; title; on_click }
let toolbar items node = Modified (Toolbar items, node)

let sheet ~is_presented ~content ?on_dismiss node =
  Modified (Sheet { is_presented; content; on_dismiss }, node)
;;

module Bridge = struct
  type event_handler =
    | Click of Action.t
    | Change of (string -> Action.t)

  type t =
    { json : string
    ; schedule_event : Action.t -> unit
    ; handlers : (int, event_handler) Hashtbl.t
    }

  let json t = t.json

  let escape_json value =
    let buffer = Buffer.create (String.length value) in
    String.iter
      (function
        | '"' -> Buffer.add_string buffer "\\\""
        | '\\' -> Buffer.add_string buffer "\\\\"
        | '\b' -> Buffer.add_string buffer "\\b"
        | '\012' -> Buffer.add_string buffer "\\f"
        | '\n' -> Buffer.add_string buffer "\\n"
        | '\r' -> Buffer.add_string buffer "\\r"
        | '\t' -> Buffer.add_string buffer "\\t"
        | char when Char.code char < 32 ->
          Printf.bprintf buffer "\\u%04x" (Char.code char)
        | char -> Buffer.add_char buffer char)
      value;
    Buffer.contents buffer
  ;;

  let string value = Printf.sprintf "\"%s\"" (escape_json value)
  let field name value = Printf.sprintf "\"%s\":%s" name value
  let object_ fields = Printf.sprintf "{%s}" (String.concat "," fields)
  let array values = Printf.sprintf "[%s]" (String.concat "," values)
  let bool value = if value then "true" else "false"

  let float value =
    let value = string_of_float value in
    if String.ends_with ~suffix:"." value then value ^ "0" else value
  ;;

  let option_float = function
    | None -> "null"
    | Some value -> float value
  ;;

  let rec unwrap_modifiers = function
    | Modified (modifier, node) ->
      let node, modifiers = unwrap_modifiers node in
      node, modifier :: modifiers
    | node -> node, []
  ;;

  let render ~schedule_event node =
    let next_event_id = ref 0 in
    let handlers = Hashtbl.create 16 in
    let register handler =
      incr next_event_id;
      let id = !next_event_id in
      Hashtbl.replace handlers id handler;
      id
    in
    let rec render_node ?(is_root = false) node =
      let node, modifiers = unwrap_modifiers node in
      let modifier_field = field "modifiers" (array (List.map render_modifier modifiers)) in
      let node_object fields =
        let fields =
          if is_root then field "schemaVersion" "1" :: fields else fields
        in
        object_ fields
      in
      match node with
      | Text value ->
        node_object
          [ field "type" (string "text"); field "text" (string value); modifier_field ]
      | Button { title; is_enabled; on_click } ->
        let event_id = if is_enabled then Some (register (Click on_click)) else None in
        node_object
          [ field "type" (string "button")
          ; field "text" (string title)
          ; field "enabled" (bool is_enabled)
          ; field
              "eventId"
              (match event_id with
               | None -> "null"
               | Some event_id -> string_of_int event_id)
          ; modifier_field
          ]
      | Text_field { text; placeholder; on_change } ->
        let event_id = register (Change on_change) in
        node_object
          [ field "type" (string "textField")
          ; field "text" (string text)
          ; field
              "placeholder"
              (match placeholder with
               | None -> "null"
               | Some value -> string value)
          ; field "eventId" (string_of_int event_id)
          ; modifier_field
          ]
      | Stack { axis; spacing; children } ->
        node_object
          [ field
              "type"
              (string
                 (match axis with
                  | `Vertical -> "vstack"
                  | `Horizontal -> "hstack"))
          ; field "spacing" (option_float spacing)
          ; field "children" (array (List.map render_node children))
          ; modifier_field
          ]
      | Scroll_view child ->
        node_object
          [ field "type" (string "scrollView")
          ; field "child" (render_node child)
          ; modifier_field
          ]
      | List rows ->
        node_object
          [ field "type" (string "list")
          ; field
              "rows"
              (array
                 (List.map
                    (fun { key; node } ->
                      object_ [ field "key" (string key); field "node" (render_node node) ])
                    rows))
          ; modifier_field
          ]
      | Navigation_stack children ->
        node_object
          [ field "type" (string "navigationStack")
          ; field "children" (array (List.map render_node children))
          ; modifier_field
          ]
      | Image name ->
        node_object
          [ field "type" (string "image"); field "name" (string name); modifier_field ]
      | Custom_view { key; kind } ->
        node_object
          [ field "type" (string "customView")
          ; field "kind" (string kind)
          ; field
              "key"
              (match key with
               | None -> "null"
               | Some value -> string value)
          ; modifier_field
          ]
      | Modified _ -> assert false
    and render_modifier = function
      | Padding { top; start; bottom; end_ } ->
        object_
          [ field "type" (string "padding")
          ; field "top" (float top)
          ; field "start" (float start)
          ; field "bottom" (float bottom)
          ; field "end" (float end_)
          ]
      | Frame { width; height } ->
        object_
          [ field "type" (string "frame")
          ; field "width" (option_float width)
          ; field "height" (option_float height)
          ]
      | Searchable { text; on_change } ->
        let event_id = register (Change on_change) in
        object_
          [ field "type" (string "searchable")
          ; field "text" (string text)
          ; field "eventId" (string_of_int event_id)
          ]
      | Toolbar items ->
        object_
          [ field "type" (string "toolbar")
          ; field
              "items"
              (array
                 (List.map
                    (fun { id; title; on_click } ->
                      let event_id = register (Click on_click) in
                      object_
                        [ field "id" (string id)
                        ; field "title" (string title)
                        ; field "eventId" (string_of_int event_id)
                        ])
                    items))
          ]
      | Sheet { is_presented; content; on_dismiss } ->
        object_
          [ field "type" (string "sheet")
          ; field "isPresented" (bool is_presented)
          ; field "content" (render_node content)
          ; field
              "dismissEventId"
              (match on_dismiss with
               | None -> "null"
               | Some action -> register (Click action) |> string_of_int)
          ]
    in
    { json = render_node ~is_root:true node; schedule_event; handlers }
  ;;

  let dispatch_click t id =
    match Hashtbl.find_opt t.handlers id with
    | Some (Click action) -> t.schedule_event action
    | Some (Change _) | None -> ()
  ;;

  let dispatch_change t id ~text =
    match Hashtbl.find_opt t.handlers id with
    | Some (Change action) -> t.schedule_event (action text)
    | Some (Click _) | None -> ()
  ;;
end

module App_driver = struct
  type ('result, 'rendered) t =
    { cells : (string, cell) Hashtbl.t
    ; derived_cells : (string, derived_cell) Hashtbl.t
    ; subscriptions : (string, subscription) Hashtbl.t
    ; component : graph -> 'result
    ; mutable rendered : 'rendered option
    ; render : schedule_event:(Action.t -> unit) -> 'result -> 'rendered
    ; update : 'rendered -> schedule_event:(Action.t -> unit) -> 'result -> 'rendered
    ; mutable dirty : bool
    ; mutable generation : int
    }

  let create component ~render ~update =
    { cells = Hashtbl.create 16
    ; derived_cells = Hashtbl.create 16
    ; subscriptions = Hashtbl.create 16
    ; component
    ; rendered = None
    ; render
    ; update
    ; dirty = true
    ; generation = 0
    }
  ;;

  let rendered t = t.rendered

  let graph t =
    { cells = t.cells
    ; derived_cells = t.derived_cells
    ; subscriptions = t.subscriptions
    ; path = []
    ; invalidate = (fun () -> t.dirty <- true)
    ; generation = t.generation
    }
  ;;

  let cleanup_unused_subscriptions t =
    let unused = ref [] in
    Hashtbl.iter
      (fun key subscription ->
        if subscription.last_seen_generation <> t.generation then unused := key :: !unused)
      t.subscriptions;
    List.iter
      (fun key ->
        match Hashtbl.find_opt t.subscriptions key with
        | None -> ()
        | Some subscription ->
          subscription.canceled <- true;
          subscription.cancel ();
          Hashtbl.remove t.subscriptions key)
      !unused
  ;;

  let render_current_result t ~schedule_event =
    t.dirty <- false;
    t.generation <- t.generation + 1;
    let result = t.component (graph t) in
    t.rendered
    <- Some
         (match t.rendered with
          | None -> t.render ~schedule_event result
          | Some rendered -> t.update rendered ~schedule_event result);
    cleanup_unused_subscriptions t;
  ;;

  let rec flush t =
    if t.dirty
    then (
      render_current_result t ~schedule_event:(fun action -> action ());
      flush t)
  ;;

  let rec flush_and_render t =
    render_current_result t ~schedule_event:(schedule_event_and_render t);
    if t.dirty then flush_and_render t

  and schedule_event_and_render t action =
    action ();
    if t.dirty then flush_and_render t
  ;;

  let schedule_event _t action = action ()
end

module App = struct
  type t = (node, Bridge.t) App_driver.t

  let create component =
    App_driver.create
      component
      ~render:(fun ~schedule_event node -> Bridge.render ~schedule_event node)
      ~update:(fun _bridge ~schedule_event node -> Bridge.render ~schedule_event node)
  ;;

  let render_json t =
    App_driver.flush t;
    match App_driver.rendered t with
    | Some bridge -> Bridge.json bridge
    | None -> ""
  ;;

  let dispatch_click t event_id =
    match App_driver.rendered t with
    | Some bridge -> Bridge.dispatch_click bridge event_id
    | None -> ()
  ;;

  let dispatch_change t event_id ~text =
    match App_driver.rendered t with
    | Some bridge -> Bridge.dispatch_change bridge event_id ~text
    | None -> ()
  ;;
end
