module Model = Ocaml_demo_model

let require condition message = if not condition then failwith message

let update_exn model action =
  match Model.update model action with
  | Ok model -> model
  | Error _ -> failwith "unexpected model update error"
;;

let test_counter () =
  let model = Model.initial in
  require (Model.count model = 0) "counter should start at zero";
  let model = update_exn model Model.Increment in
  require (Model.count model = 1) "increment should update the shared model";
  require (Model.revision model = 1) "a state change should revise the shared model";
  let model = update_exn model Model.Decrement in
  require (Model.count model = 0) "decrement should update the shared model";
  let model = update_exn model Model.Increment |> fun model ->
    update_exn model Model.Reset_counter
  in
  require (Model.count model = 0) "reset should clear the counter"
;;

let test_todos () =
  let model = update_exn Model.initial (Model.Set_todo_draft "Shared logic") in
  let model = update_exn model Model.Add_todo in
  require (Model.todo_draft model = "") "adding should clear the draft";
  let todo =
    match Model.todos model with
    | [ todo ] -> todo
    | _ -> failwith "adding should create exactly one todo"
  in
  require (todo.title = "Shared logic") "the shared model should retain the title";
  require (not todo.completed) "new todos should be active";
  let model = update_exn model (Model.Toggle_todo todo.id) in
  let toggled = List.hd (Model.todos model) in
  require toggled.completed "toggle should update completion";
  let model = update_exn model (Model.Delete_todo todo.id) in
  require (Model.todos model = []) "delete should remove the todo";
  require
    (Model.update model (Model.Toggle_todo todo.id) = Error (Model.Unknown_todo todo.id))
    "unknown todo IDs should be reported"
;;

let test_search () =
  let model = update_exn Model.initial (Model.Set_search_query "t") in
  require (Model.search_query model = "t") "query should live in the shared model";
  require
    (Model.search_results model = [ "Today"; "Tasks"; "Settings"; "Projects" ])
    "all platforms should use the same OCaml search results"
;;

let test_empty_todo_is_a_no_op () =
  let model = update_exn Model.initial Model.Add_todo in
  require (Model.todos model = []) "an empty draft should not add a todo";
  require (Model.revision model = 0) "a no-op should not change the revision"
;;

let () =
  test_counter ();
  test_todos ();
  test_search ();
  test_empty_todo_is_a_no_op ()
;;
