type todo =
  { id : int
  ; title : string
  ; completed : bool
  }

type t =
  { revision : int
  ; count : int
  ; todo_draft : string
  ; todos : todo list
  ; next_todo_id : int
  ; search_query : string
  }

type action =
  | Increment
  | Decrement
  | Reset_counter
  | Set_todo_draft of string
  | Add_todo
  | Toggle_todo of int
  | Delete_todo of int
  | Set_search_query of string

type error =
  | Unknown_todo of int

let initial =
  { revision = 0
  ; count = 0
  ; todo_draft = ""
  ; todos = []
  ; next_todo_id = 1
  ; search_query = ""
  }
;;

let revised model = { model with revision = model.revision + 1 }

let update_todo todos id ~f =
  let found = ref false in
  let todos =
    List.map
      (fun todo ->
        if todo.id = id
        then (
          found := true;
          f todo)
        else todo)
      todos
  in
  if !found then Ok todos else Error (Unknown_todo id)
;;

let update model = function
  | Increment -> Ok (revised { model with count = model.count + 1 })
  | Decrement -> Ok (revised { model with count = model.count - 1 })
  | Reset_counter ->
    if model.count = 0 then Ok model else Ok (revised { model with count = 0 })
  | Set_todo_draft draft ->
    if draft = model.todo_draft
    then Ok model
    else Ok (revised { model with todo_draft = draft })
  | Add_todo ->
    if String.trim model.todo_draft = ""
    then Ok model
    else (
      let todo =
        { id = model.next_todo_id; title = model.todo_draft; completed = false }
      in
      Ok
        (revised
           { model with
             todo_draft = ""
           ; todos = todo :: model.todos
           ; next_todo_id = model.next_todo_id + 1
           }))
  | Toggle_todo id ->
    (match
       update_todo model.todos id ~f:(fun todo ->
         { todo with completed = not todo.completed })
     with
     | Error error -> Error error
     | Ok todos -> Ok (revised { model with todos }))
  | Delete_todo id ->
    if List.exists (fun todo -> todo.id = id) model.todos
    then
      Ok
        (revised
           { model with todos = List.filter (fun todo -> todo.id <> id) model.todos })
    else Error (Unknown_todo id)
  | Set_search_query query ->
    if query = model.search_query
    then Ok model
    else Ok (revised { model with search_query = query })
;;

let revision model = model.revision
let count model = model.count
let todo_draft model = model.todo_draft
let todos model = model.todos
let search_query model = model.search_query

let contains_case_insensitive text ~substring =
  let text = String.lowercase_ascii text in
  let substring = String.lowercase_ascii substring in
  let text_length = String.length text in
  let substring_length = String.length substring in
  let rec loop index =
    substring_length = 0
    || (index + substring_length <= text_length
        && (String.sub text index substring_length = substring || loop (index + 1)))
  in
  loop 0
;;

let all_search_items = [ "Today"; "Tasks"; "Settings"; "Archive"; "Projects" ]

let search_results model =
  List.filter
    (fun item -> contains_case_insensitive item ~substring:model.search_query)
    all_search_items
;;
