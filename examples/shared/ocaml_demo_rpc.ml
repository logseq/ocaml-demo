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

let task_json (task : Model.task) =
  `Assoc
    [ "id", `Int task.id
    ; "title", `String task.title
    ; "completed", `Bool task.completed
    ]
;;

let block_json (block : Model.block) =
  `Assoc
    [ "id", `Int block.id
    ; "content", `String block.content
    ; "depth", `Int block.depth
    ]
;;

let journal_json (journal : Model.journal) =
  `Assoc [ "id", `Int journal.id; "title", `String journal.title ]
;;

let model_json model ~screen =
  let common =
    [ "revision", `Int (Model.revision model); "screen", `String screen ]
  in
  match screen with
  | "journal" ->
    Ok
      (`Assoc
        (common
         @ [ "selectedJournalId", `Int (Model.selected_journal_id model)
           ; "journals", `List (List.map journal_json (Model.journals model))
           ]))
  | "tasks" ->
    Ok
      (`Assoc
        (common
         @ [ "draft", `String (Model.task_draft model)
           ; "items", `List (List.map task_json (Model.tasks model))
           ]))
  | "outliner" ->
    Ok
      (`Assoc
        (common @ [ "blocks", `List (List.map block_json (Model.blocks model)) ]))
  | _ -> Error ("unknown screen: " ^ screen)
;;

let required_payload action = function
  | Some payload -> Ok payload
  | None -> Error ("action requires payload: " ^ action)
;;

let entity_id action payload =
  match required_payload action payload with
  | Error error -> Error error
  | Ok payload ->
    (match int_of_string_opt payload with
     | Some id -> Ok id
     | None -> Error ("entity ID must be an integer: " ^ payload))
;;

let outliner_payload action payload =
  match required_payload action payload with
  | Error error -> Error error
  | Ok payload ->
    (match Json.from_string payload with
     | Ok (`Assoc fields) ->
       (match assoc_field "id" fields with
        | Some (`Int id) -> Ok (id, assoc_field "content" fields)
        | _ -> Error "outliner payload requires an integer id")
     | _ -> Error "outliner payload must be a JSON object")
;;

let action_for_request ~screen ~action ~payload =
  match screen, action with
  | "journal", "ensureToday" ->
    Result.map (fun date -> Model.Ensure_today date) (required_payload action payload)
  | "journal", "open" ->
    Result.map (fun id -> Model.Select_journal id) (entity_id action payload)
  | "tasks", "setDraft" ->
    Result.map (fun value -> Model.Set_task_draft value) (required_payload action payload)
  | "tasks", "add" -> Ok Model.Add_task
  | "tasks", "toggle" ->
    Result.map (fun id -> Model.Toggle_task id) (entity_id action payload)
  | "tasks", "delete" ->
    Result.map (fun id -> Model.Delete_task id) (entity_id action payload)
  | "outliner", "setContent" ->
    (match outliner_payload action payload with
     | Ok (id, Some (`String content)) -> Ok (Model.Set_block_content (id, content))
     | Ok _ -> Error "setContent payload requires string content"
     | Error error -> Error error)
  | "outliner", "insertSibling" ->
    Result.map
      (fun (id, _) -> Model.Add_sibling_block id)
      (outliner_payload action payload)
  | "outliner", "deleteBlock" ->
    Result.map
      (fun (id, _) -> Model.Delete_block id)
      (outliner_payload action payload)
  | "outliner", "indent" ->
    Result.map (fun (id, _) -> Model.Indent_block id) (outliner_payload action payload)
  | "outliner", "outdent" ->
    Result.map (fun (id, _) -> Model.Outdent_block id) (outliner_payload action payload)
  | ("journal" | "tasks" | "outliner"), _ -> Error ("unknown action: " ^ action)
  | _ -> Error ("unknown screen: " ^ screen)
;;

module Session = struct
  type t =
    { model : Model.t
    }

  let create ?storage () = { model = Model.create ?storage () }

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
          | Ok model_action ->
            (match Model.update session.model model_action with
             | Error (Model.Unknown_task id) ->
               failure
                 ~code:"unknown_task"
                 ~message:(Printf.sprintf "unknown task: %d" id)
             | Error (Model.Unknown_journal id) ->
               failure
                 ~code:"unknown_journal"
                 ~message:(Printf.sprintf "unknown journal: %d" id)
             | Error (Model.Unknown_block id) ->
               failure
                 ~code:"unknown_block"
                 ~message:(Printf.sprintf "unknown block: %d" id)
             | Ok () -> snapshot session ~screen)))
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
