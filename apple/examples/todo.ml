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
    [ (Apple.hstack
         ~spacing:8.
         [ Apple.text_field
             ~text:(Model.todo_draft model)
             ~placeholder:"New task"
             ~on_change:(fun draft -> action model set_model (Model.Set_todo_draft draft))
             ()
           |> Apple.frame ~width:260.
        ; Apple.button "Add" ~on_click:(action model set_model Model.Add_todo)
        ]
       |> Apple.frame ~width:360. ~height:44.)
    ; (Apple.list
         (Model.todos model)
         ~key:(fun todo -> Int.to_string todo.id)
         ~row:(fun todo -> Apple.text todo.title)
       |> Apple.frame ~width:360. ~height:620.)
    ]
;;

let () = ignore component
