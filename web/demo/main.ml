module Model = Ocaml_demo_model
module Json = Ocaml_demo_json

type element
type root
type container
type event
type event_target

external create_element
  :  string
  -> 'props Js.nullable
  -> element array
  -> element
  = "createElement"
  [@@mel.module "react"]

external create_leaf
  :  string
  -> 'props Js.nullable
  -> element
  = "createElement"
  [@@mel.module "react"]

external create_root : container -> root = "createRoot" [@@mel.module "react-dom/client"]
external render_root : root -> element -> unit = "render" [@@mel.send]
external get_element_by_id : string -> container = "getElementById" [@@mel.scope "document"]
external event_target : event -> event_target = "target" [@@mel.get]
external target_value : event_target -> string = "value" [@@mel.get]
external event_key : event -> string = "key" [@@mel.get]
external event_is_composing : event -> bool = "isComposing" [@@mel.get]
external prevent_default : event -> unit = "preventDefault" [@@mel.send]
external native_available : unit -> bool = "ocamlDemoNativeAvailable" [@@mel.scope "window"]
external post_native : string -> unit = "ocamlDemoPostNative" [@@mel.scope "window"]
external subscribe_native : (string -> unit) -> unit = "ocamlDemoSubscribe" [@@mel.scope "window"]
external today : unit -> string = "ocamlDemoToday" [@@mel.scope "window"]
external text : string -> element = "%identity"

type screen =
  | Journal
  | Tasks

let native_mode = native_available ()
let model =
  if native_mode
  then Model.create ()
  else Model.create ~storage:(Ocaml_demo_web_storage.storage ()) ()
;;
let screen = ref Journal
let journal_detail = ref false
let remote_journals : Model.journal list ref = ref []
let remote_blocks : Model.block list ref = ref []
let focused_block_id : int option ref = ref None
let pending_insert_ids : int list option ref = ref None
let root = create_root (get_element_by_id "root")

let element name children =
  create_element name Js.Nullable.null (Array.of_list children)
;;

let element_with_props name props children =
  create_element name (Js.Nullable.return props) (Array.of_list children)
;;

let assoc name fields = List.assoc_opt name fields

let journals_of_json = function
  | `List journals ->
    List.filter_map
      (function
        | `Assoc fields ->
          (match assoc "id" fields, assoc "title" fields with
           | Some (`Int id), Some (`String title) -> Some Model.{ id; title }
           | _ -> None)
        | _ -> None)
      journals
  | _ -> []
;;

let blocks_of_json = function
  | `List blocks ->
    List.filter_map
      (function
        | `Assoc fields ->
          (match
             assoc "id" fields, assoc "content" fields, assoc "depth" fields
           with
           | Some (`Int id), Some (`String content), Some (`Int depth) ->
             Some Model.{ id; content; depth }
           | _ -> None)
        | _ -> None)
      blocks
  | _ -> []
;;

let send action fields =
  post_native (Json.to_string (`Assoc (("action", `String action) :: fields)))
;;

let update action =
  match Model.update model action with
  | Ok () -> ()
  | Error _ -> ()
;;

let current_journals () =
  if native_mode then !remote_journals else Model.journals model
;;

let current_blocks () =
  if native_mode then !remote_blocks else Model.blocks model
;;

let rec render () =
  let button ?(disabled = false) ?class_name label on_click =
    match class_name with
    | None ->
      element_with_props
        "button"
        [%mel.obj { disabled; onClick = (fun _ -> on_click ()) }]
        [ text label ]
    | Some className ->
      element_with_props
        "button"
        [%mel.obj { className; disabled; onClick = (fun _ -> on_click ()) }]
        [ text label ]
  in
  let icon_button ~class_name ~title ~path on_click =
    let icon =
      element_with_props
        "svg"
        [%mel.obj
          { viewBox = "0 0 24 24"
          ; fill = "none"
          ; stroke = "currentColor"
          ; strokeWidth = "2"
          ; strokeLinecap = "round"
          ; strokeLinejoin = "round"
          }]
        [ create_leaf
            "path"
            (Js.Nullable.return [%mel.obj { d = path }])
        ]
    in
    element_with_props
      "button"
      [%mel.obj
        { className = class_name
        ; title
        ; onPointerDown = (fun event -> prevent_default event)
        ; onClick = (fun _ -> on_click ())
        }]
      [ icon ]
  in
  let input ~value ~auto_focus ~on_change ~on_focus ~on_enter =
    let activate_editor () = on_focus () in
    create_leaf
      "input"
      (Js.Nullable.return
         [%mel.obj
           { className = "block-content"
           ; autoFocus = auto_focus
           ; onChange =
               (fun event -> on_change (target_value (event_target event)))
           ; onClick = (fun _ -> activate_editor ())
           ; onFocus = (fun _ -> activate_editor ())
           ; onKeyDown =
               (fun event ->
                 if String.equal (event_key event) "Enter"
                    && not (event_is_composing event)
                 then (
                   prevent_default event;
                   on_enter ()))
           ; value
           }])
  in
  let dispatch action =
    update action;
    render ()
  in
  let tasks =
    let task_item (task : Model.task) =
      element_with_props
        "li"
        [%mel.obj { key = string_of_int task.id }]
        [ button
            (if task.completed then "Completed" else "Active")
            (fun () -> dispatch (Model.Toggle_task task.id))
        ; element "span" [ text task.title ]
        ; button "Delete" (fun () -> dispatch (Model.Delete_task task.id))
        ]
    in
    let draft_input =
      create_leaf
        "input"
        (Js.Nullable.return
           [%mel.obj
             { onChange =
                 (fun event ->
                   dispatch (Model.Set_task_draft (target_value (event_target event))))
             ; placeholder = "New task"
             ; value = Model.task_draft model
             }])
    in
    element
      "section"
      [ element "h2" [ text "Tasks" ]
      ; element "div" [ draft_input; button "Add" (fun () -> dispatch Model.Add_task) ]
      ; element "ul" (List.map task_item (Model.tasks model))
      ]
  in
  let dispatch_block action id content =
    if native_mode
    then
      let fields =
        [ "id", `Int id ]
        @
        match content with
        | None -> []
        | Some value -> [ "content", `String value ]
      in
      send action fields
    else (
      let model_action =
        match action, content with
        | "setContent", Some value -> Model.Set_block_content (id, value)
        | "indent", _ -> Model.Indent_block id
        | "outdent", _ -> Model.Outdent_block id
        | _ -> Model.Set_block_content (id, "")
      in
      dispatch model_action)
  in
  let insert_sibling id =
    let existing_ids = List.map (fun (block : Model.block) -> block.id) (current_blocks ()) in
    if native_mode
    then (
      pending_insert_ids := Some existing_ids;
      send "insertSibling" [ "id", `Int id ])
    else (
      update (Model.Add_sibling_block id);
      focused_block_id :=
        List.find_map
          (fun (block : Model.block) ->
            if List.mem block.id existing_ids then None else Some block.id)
          (current_blocks ());
      render ())
  in
  let outliner =
    let block_item (block : Model.block) =
      element_with_props
        "li"
        [%mel.obj
          { className = "block"
          ; key = string_of_int block.id
          ; style = [%mel.obj { marginLeft = string_of_int (block.depth * 22) ^ "px" }]
          }]
        ([ element "span" [ text "*" ]
         ; input
             ~value:block.content
             ~auto_focus:(!focused_block_id = Some block.id)
             ~on_change:(fun content ->
               dispatch_block "setContent" block.id (Some content))
             ~on_focus:(fun () ->
               if !focused_block_id <> Some block.id
               then (
                 focused_block_id := Some block.id;
                 render ()))
             ~on_enter:(fun () -> insert_sibling block.id)
         ]
         @
         [ element_with_props
             "div"
             [%mel.obj { className = "editor-toolbar" }]
             [ icon_button
                 ~class_name:"outdent-button"
                 ~title:"Outdent"
                 ~path:"M19 12H5 M11 18l-6-6 6-6"
                 (fun () -> dispatch_block "outdent" block.id None)
             ; icon_button
                 ~class_name:"indent-button"
                 ~title:"Indent"
                 ~path:"M5 12h14 M13 6l6 6-6 6"
                 (fun () -> dispatch_block "indent" block.id None)
             ]
         ])
    in
    element
      "section"
      [ button ~class_name:"back" "Back to Journals" (fun () ->
          if native_mode then send "showJournals" [] else journal_detail := false;
          render ())
      ; element "ul" (List.map block_item (current_blocks ()))
      ]
  in
  let journals =
    if !journal_detail
    then outliner
    else
      element
        "section"
        [ element "h2" [ text "Journals" ]
        ; element_with_props
            "div"
            [%mel.obj { className = "journals" }]
            (List.map
               (fun (journal : Model.journal) ->
                 button ~class_name:"journal" journal.title (fun () ->
                   if native_mode
                   then send "openJournal" [ "id", `Int journal.id ]
                   else (
                     update (Model.Select_journal journal.id);
                     journal_detail := true;
                     render ())))
               (current_journals ()))
        ]
  in
  let navigation_button target label =
    button
      ~disabled:(!screen = target)
      label
      (fun () ->
         screen := target;
         render ())
  in
  let current =
    match !screen with
    | Journal -> journals
    | Tasks -> tasks
  in
  let navigation =
    if native_mode
    then []
    else
      [ element
          "nav"
          [ navigation_button Journal "Journals"; navigation_button Tasks "Tasks" ]
      ]
  in
  element
    "main"
    ([ element "h1" [ text "OCaml Demo" ] ] @ navigation @ [ current ])
  |> render_root root
;;

let receive_snapshot payload =
  match Json.from_string payload with
  | Ok (`Assoc fields) ->
    (match assoc "screen" fields with
     | Some (`String "journal") ->
       remote_journals :=
         (match assoc "journals" fields with
          | Some json -> journals_of_json json
          | None -> []);
       journal_detail := false
     | Some (`String "outliner") ->
       let next_blocks =
         match assoc "blocks" fields with
         | Some json -> blocks_of_json json
         | None -> []
       in
       (match !pending_insert_ids with
        | Some existing_ids ->
          focused_block_id :=
            List.find_map
              (fun (block : Model.block) ->
                if List.mem block.id existing_ids then None else Some block.id)
              next_blocks;
          pending_insert_ids := None
        | None -> ());
       remote_blocks := next_blocks;
       journal_detail := true
     | _ -> ());
    render ()
  | _ -> ()
;;

let () =
  if native_mode
  then (
    subscribe_native receive_snapshot;
    send "ready" [])
  else (
    update (Model.Ensure_today (today ()));
    render ())
