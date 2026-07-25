module Apple = Ocaml_demo_apple
module Model = Ocaml_demo_model

let action model set_model action =
  match Model.update model action with
  | Ok model -> set_model model
  | Error _ -> Apple.Action.ignore
;;

let component graph =
  let model, set_model = Apple.state graph ~key:"demo-model" Model.initial in
  Apple.vstack
    ~spacing:12.
    [ (Apple.text_field
         ~text:(Model.search_query model)
         ~placeholder:"Search"
         ~on_change:(fun query -> action model set_model (Model.Set_search_query query))
         ()
       |> Apple.frame ~width:360. ~height:44.)
    ; (Apple.list
         (Model.search_results model)
         ~key:(fun item -> item)
         ~row:Apple.text
       |> Apple.frame ~width:360. ~height:620.)
    ]
;;

let () = ignore component
