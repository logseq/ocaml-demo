let () =
  let demo_id =
    match Sys.argv with
    | [| _; demo_id |] -> demo_id
    | _ -> "counter"
  in
  let app = Ocaml_demo_android.App.create (Android_demo_components.component_by_id demo_id) in
  print_endline (Ocaml_demo_android.App.render_json app)
;;
