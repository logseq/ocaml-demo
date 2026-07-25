module Model = Ocaml_demo_model

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

external create_root : container -> root = "createRoot" [@@mel.module "react-dom/client"]
external render_root : root -> element -> unit = "render" [@@mel.send]
external get_element_by_id : string -> container = "getElementById" [@@mel.scope "document"]
external event_target : event -> event_target = "target" [@@mel.get]
external target_value : event_target -> string = "value" [@@mel.get]
external text : string -> element = "%identity"

type screen =
  | Counter
  | Todo
  | Search

let model = ref Model.initial
let screen = ref Counter
let root = create_root (get_element_by_id "root")

let element name children =
  create_element name Js.Nullable.null (Array.of_list children)
;;

let element_with_props name props children =
  create_element name (Js.Nullable.return props) (Array.of_list children)
;;

let update action =
  match Model.update !model action with
  | Ok next -> model := next
  | Error _ -> ()
;;

let rec render () =
  let button ?(disabled = false) label on_click =
    element_with_props
      "button"
      [%mel.obj { disabled; onClick = (fun _ -> on_click ()) }]
      [ text label ]
  in
  let input ~placeholder ~value ~on_change =
    element_with_props
      "input"
      [%mel.obj
        { onChange =
            (fun event -> on_change (target_value (event_target event)))
        ; placeholder
        ; value
        }]
      []
  in
  let dispatch action =
    update action;
    render ()
  in
  let counter =
    element
      "section"
      [ element "h2" [ text (string_of_int (Model.count !model)) ]
      ; element
          "div"
          [ button "Decrement" (fun () -> dispatch Model.Decrement)
          ; button "Increment" (fun () -> dispatch Model.Increment)
          ; button "Reset" (fun () -> dispatch Model.Reset_counter)
          ]
      ]
  in
  let todo =
    let todo_item (todo : Model.todo) =
      element_with_props
        "li"
        [%mel.obj { key = string_of_int todo.id }]
        [ button
            (if todo.completed then "✓" else "○")
            (fun () -> dispatch (Model.Toggle_todo todo.id))
        ; text todo.title
        ; button "Delete" (fun () -> dispatch (Model.Delete_todo todo.id))
        ]
    in
    element
      "section"
      [ element
          "div"
          [ input
              ~placeholder:"New task"
              ~value:(Model.todo_draft !model)
              ~on_change:(fun draft -> dispatch (Model.Set_todo_draft draft))
          ; button "Add" (fun () -> dispatch Model.Add_todo)
          ]
      ; element "ul" (List.map todo_item (Model.todos !model))
      ]
  in
  let search =
    element
      "section"
      [ input
          ~placeholder:"Search"
          ~value:(Model.search_query !model)
          ~on_change:(fun query -> dispatch (Model.Set_search_query query))
      ; element
          "ul"
          (List.map
             (fun result ->
               element_with_props "li" [%mel.obj { key = result }] [ text result ])
             (Model.search_results !model))
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
    | Counter -> counter
    | Todo -> todo
    | Search -> search
  in
  element
    "main"
    [ element "h1" [ text "OCaml Demo" ]
    ; element
        "nav"
        [ navigation_button Counter "Counter"
        ; navigation_button Todo "Todo"
        ; navigation_button Search "Search"
        ]
    ; current
    ]
  |> render_root root
;;

let () = render ()
