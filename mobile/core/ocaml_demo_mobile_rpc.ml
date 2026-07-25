module Model = Ocaml_demo_model
module Json = Ocaml_demo_json

let json_response ~ok ~result ~error =
  Json.to_string
    (`Assoc
      [ "apiVersion", `Int 1
      ; "ok", `Bool ok
      ; "result", result
      ; "error", error
      ])
;;

let success result = json_response ~ok:true ~result ~error:`Null

let failure ~code ~message =
  json_response
    ~ok:false
    ~result:`Null
    ~error:(`Assoc [ "code", `String code; "message", `String message ])
;;

let assoc_field name fields = List.assoc_opt name fields

let required_string name fields =
  match assoc_field name fields with
  | Some (`String value) -> Ok value
  | Some _ -> Error ("field must be a string: " ^ name)
  | None -> Error ("missing field: " ^ name)
;;

let optional_string name fields =
  match assoc_field name fields with
  | Some (`String value) -> Ok (Some value)
  | Some `Null | None -> Ok None
  | Some _ -> Error ("field must be a string: " ^ name)
;;

let model_json model ~screen =
  let common =
    [ "revision", `Int (Model.revision model); "screen", `String screen ]
  in
  let screen_fields =
    match screen with
    | "counter" -> Ok [ "count", `Int (Model.count model) ]
    | "todo" ->
      let todo_json (todo : Model.todo) =
        `Assoc
          [ "id", `Int todo.id
          ; "title", `String todo.title
          ; "completed", `Bool todo.completed
          ]
      in
      Ok
        [ "draft", `String (Model.todo_draft model)
        ; "items", `List (List.map todo_json (Model.todos model))
        ]
    | "search" ->
      Ok
        [ "query", `String (Model.search_query model)
        ; "results", `List (List.map (fun value -> `String value) (Model.search_results model))
        ]
    | _ -> Error ("unknown screen: " ^ screen)
  in
  match screen_fields with
  | Ok fields -> Ok (`Assoc (common @ fields))
  | Error message -> Error message
;;

let action_for_request ~screen ~action ~payload =
  let required_payload () =
    match payload with
    | Some payload -> Ok payload
    | None -> Error ("action requires payload: " ^ action)
  in
  let todo_id () =
    match required_payload () with
    | Error error -> Error error
    | Ok payload ->
      (match int_of_string_opt payload with
       | Some id -> Ok id
       | None -> Error ("todo ID must be an integer: " ^ payload))
  in
  match screen, action with
  | "counter", "increment" -> Ok Model.Increment
  | "counter", "decrement" -> Ok Model.Decrement
  | "counter", "reset" -> Ok Model.Reset_counter
  | "todo", "setDraft" ->
    Result.map (fun payload -> Model.Set_todo_draft payload) (required_payload ())
  | "todo", "add" -> Ok Model.Add_todo
  | "todo", "toggle" -> Result.map (fun id -> Model.Toggle_todo id) (todo_id ())
  | "todo", "delete" -> Result.map (fun id -> Model.Delete_todo id) (todo_id ())
  | "search", "setQuery" ->
    Result.map (fun payload -> Model.Set_search_query payload) (required_payload ())
  | ("counter" | "todo" | "search"), _ -> Error ("unknown action: " ^ action)
  | _ -> Error ("unknown screen: " ^ screen)
;;

module Session = struct
  type t =
    { mutable model : Model.t
    }

  let create () = { model = Model.initial }

  let snapshot session ~screen =
    match model_json session.model ~screen with
    | Ok json -> success json
    | Error message -> failure ~code:"unknown_screen" ~message
  ;;

  let dispatch session params =
    match required_string "screen" params, required_string "action" params with
    | Error message, _ | _, Error message -> failure ~code:"invalid_params" ~message
    | Ok screen, Ok action ->
      (match optional_string "payload" params with
       | Error message -> failure ~code:"invalid_params" ~message
       | Ok payload ->
         (match action_for_request ~screen ~action ~payload with
          | Error message ->
            let code =
              if String.starts_with ~prefix:"unknown action" message
              then "unknown_action"
              else if String.starts_with ~prefix:"unknown screen" message
              then "unknown_screen"
              else "invalid_params"
            in
            failure ~code ~message
          | Ok action ->
            (match Model.update session.model action with
             | Error (Model.Unknown_todo id) ->
               failure
                 ~code:"unknown_todo"
                 ~message:(Printf.sprintf "unknown todo: %d" id)
             | Ok model ->
               session.model <- model;
               snapshot session ~screen)))
  ;;

  let route session request =
    match request with
    | `Assoc fields ->
      (match assoc_field "apiVersion" fields with
       | Some (`Int 1) ->
         (match required_string "method" fields with
          | Error message -> failure ~code:"invalid_request" ~message
          | Ok method_name ->
            (match assoc_field "params" fields with
             | Some (`Assoc params) ->
               (match method_name with
                | "snapshot" ->
                  (match required_string "screen" params with
                   | Ok screen -> snapshot session ~screen
                   | Error message -> failure ~code:"invalid_params" ~message)
                | "dispatch" -> dispatch session params
                | _ ->
                  failure
                    ~code:"unknown_method"
                    ~message:("unknown method: " ^ method_name))
             | Some _ -> failure ~code:"invalid_request" ~message:"params must be an object"
             | None -> failure ~code:"invalid_request" ~message:"missing field: params"))
       | Some (`Int _) ->
         failure
           ~code:"unsupported_version"
           ~message:"only API version 1 is supported"
       | Some _ ->
         failure ~code:"invalid_request" ~message:"apiVersion must be an integer"
       | None -> failure ~code:"invalid_request" ~message:"missing field: apiVersion")
    | _ -> failure ~code:"invalid_request" ~message:"request must be an object"
  ;;

  let call session request =
    match Json.from_string request with
    | Ok json -> route session json
    | Error _ ->
      failure ~code:"invalid_json" ~message:"request must be valid JSON"
  ;;
end
