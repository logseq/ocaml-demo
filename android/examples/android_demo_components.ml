module Android = Ocaml_demo_android
module Model = Ocaml_demo_model

let action model set_model action =
  match Model.update model action with
  | Ok model -> set_model model
  | Error _ -> Android.Action.ignore
;;

let counter graph =
  let model, set_model = Android.state graph ~key:"demo-model" Model.initial in
  Android.vstack
    ~spacing:12.
    [ Android.text (Model.count model |> string_of_int)
    ; Android.button "Increment" ~on_click:(action model set_model Model.Increment)
    ]
  |> Android.padding
;;

let todo graph =
  let model, set_model = Android.state graph ~key:"demo-model" Model.initial in
  Android.vstack
    ~spacing:12.
    [ (Android.hstack
         ~spacing:8.
         [ Android.text_field
             ~text:(Model.todo_draft model)
             ~placeholder:"New task"
             ~on_change:(fun draft -> action model set_model (Model.Set_todo_draft draft))
             ()
           |> Android.frame ~width:260.
         ; Android.button "Add" ~on_click:(action model set_model Model.Add_todo)
         ]
       |> Android.frame ~width:360. ~height:44.)
    ; (Android.list
         (Model.todos model)
         ~key:(fun todo -> string_of_int todo.id)
         ~row:(fun todo -> Android.text todo.title)
       |> Android.frame ~width:360. ~height:620.)
    ]
  |> Android.padding
;;

let search graph =
  let model, set_model = Android.state graph ~key:"demo-model" Model.initial in
  Android.vstack
    ~spacing:12.
    [ (Android.text_field
         ~text:(Model.search_query model)
         ~placeholder:"Search"
         ~on_change:(fun query -> action model set_model (Model.Set_search_query query))
         ()
       |> Android.frame ~width:360. ~height:44.)
    ; (Android.list (Model.search_results model) ~key:(fun value -> value) ~row:Android.text
       |> Android.frame ~width:360. ~height:620.)
    ]
  |> Android.padding
;;

let metadata = [ "counter", "Counter"; "todo", "Todo"; "search", "Search" ]

let normalize_id = function
  | "todo" -> "todo"
  | "search" -> "search"
  | _ -> "counter"
;;

let component_by_id id =
  match normalize_id id with
  | "todo" -> todo
  | "search" -> search
  | _ -> counter
;;
