module Apple = Ocaml_demo_apple
module Model = Ocaml_demo_model

let component graph =
  let model, set_model = Apple.state graph ~key:"demo-model" Model.initial in
  let increment =
    match Model.update model Model.Increment with
    | Ok model -> set_model model
    | Error _ -> Apple.Action.ignore
  in
  Apple.vstack
    [ Apple.text (Model.count model |> Int.to_string)
    ; Apple.button "Increment" ~on_click:increment
    ]
;;

let () = ignore component
