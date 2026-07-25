module Apple = Ocaml_demo_apple

let component _graph =
  Apple.navigation_stack
    [ Apple.list
        [ "Today"; "Tasks"; "Settings" ]
        ~key:(fun title -> title)
        ~row:(fun title -> Apple.text title)
    ]
;;

let () = ignore component
