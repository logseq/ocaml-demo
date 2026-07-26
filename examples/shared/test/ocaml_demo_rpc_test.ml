let require condition message = if not condition then failwith message

let call session json =
  Ocaml_demo_rpc.Session.call session (Yojson.Safe.to_string json)
  |> Yojson.Safe.from_string
;;

let member name json = Yojson.Safe.Util.member name json
let result json = member "result" json

let require_success json =
  require
    (member "ok" json = `Bool true)
    ("RPC call should succeed: " ^ Yojson.Safe.to_string json)
;;

let snapshot session screen =
  call
    session
    (`Assoc
      [ "apiVersion", `Int 1
      ; "method", `String "snapshot"
      ; "params", `Assoc [ "screen", `String screen ]
      ])
;;

let dispatch session ~screen ~action ?payload () =
  let params =
    [ "screen", `String screen; "action", `String action ]
    @
    match payload with
    | None -> []
    | Some payload -> [ "payload", `String payload ]
  in
  call
    session
    (`Assoc
      [ "apiVersion", `Int 1
      ; "method", `String "dispatch"
      ; "params", `Assoc params
      ])
;;

let test_tasks_use_one_call_api () =
  let session = Ocaml_demo_rpc.Session.create () in
  ignore (dispatch session ~screen:"tasks" ~action:"setDraft" ~payload:"One API" ());
  let added = dispatch session ~screen:"tasks" ~action:"add" () in
  require_success added;
  let items = member "items" (result added) |> Yojson.Safe.Util.to_list in
  let task =
    match items with
    | [ task ] -> task
    | _ -> failwith "task dispatch should return one item"
  in
  require (member "title" task = `String "One API") "OCaml should own task state";
  require
    (member "screen" (result added) = `String "tasks")
    "the response should identify the Tasks screen"
;;

let test_outliner_rpc_edits_and_indents () =
  let session = Ocaml_demo_rpc.Session.create () in
  let journal_snapshot = snapshot session "journal" in
  require_success journal_snapshot;
  let journals =
    member "journals" (result journal_snapshot) |> Yojson.Safe.Util.to_list
  in
  require (List.length journals >= 2) "the home snapshot should list journals";
  let initial = snapshot session "outliner" in
  require_success initial;
  let blocks = member "blocks" (result initial) |> Yojson.Safe.Util.to_list in
  let second = List.nth blocks 1 in
  let id = member "id" second |> Yojson.Safe.Util.to_int in
  let payload =
    `Assoc [ "id", `Int id; "content", `String "中文 block 🚀" ]
    |> Yojson.Safe.to_string
  in
  let edited =
    dispatch session ~screen:"outliner" ~action:"setContent" ~payload ()
  in
  require_success edited;
  let indent_payload = `Assoc [ "id", `Int id ] |> Yojson.Safe.to_string in
  let indented =
    dispatch session ~screen:"outliner" ~action:"indent" ~payload:indent_payload ()
  in
  require_success indented;
  let changed =
    member "blocks" (result indented) |> Yojson.Safe.Util.to_list |> fun blocks ->
    List.nth blocks 1
  in
  require
    (member "content" changed = `String "中文 block 🚀")
    "UTF-8 block content should be returned";
  require (member "depth" changed = `Int 1) "indent should be returned";
  let outdented =
    dispatch session ~screen:"outliner" ~action:"outdent" ~payload:indent_payload ()
  in
  require_success outdented;
  let restored =
    member "blocks" (result outdented) |> Yojson.Safe.Util.to_list |> fun blocks ->
    List.nth blocks 1
  in
  require
    (member "depth" restored = `Int 0)
    "outdent should be returned in the same RPC response";
  let inserted =
    dispatch
      session
      ~screen:"outliner"
      ~action:"insertSibling"
      ~payload:indent_payload
      ()
  in
  require_success inserted;
  require
    (member "blocks" (result inserted)
     |> Yojson.Safe.Util.to_list
     |> List.length
     = List.length blocks + 1)
    "insertSibling should return the new block";
  let inserted_blocks =
    member "blocks" (result inserted) |> Yojson.Safe.Util.to_list
  in
  let empty = List.nth inserted_blocks 2 in
  let empty_id = member "id" empty |> Yojson.Safe.Util.to_int in
  let delete_payload =
    `Assoc [ "id", `Int empty_id ] |> Yojson.Safe.to_string
  in
  let deleted =
    dispatch
      session
      ~screen:"outliner"
      ~action:"deleteBlock"
      ~payload:delete_payload
      ()
  in
  require_success deleted;
  require
    (member "blocks" (result deleted)
     |> Yojson.Safe.Util.to_list
     |> List.length
     = List.length blocks)
    "deleteBlock should return the previous block list"
;;

let test_rpc_creates_missing_today () =
  let session = Ocaml_demo_rpc.Session.create () in
  let ensured =
    dispatch
      session
      ~screen:"journal"
      ~action:"ensureToday"
      ~payload:"2099-12-31"
      ()
  in
  require_success ensured;
  let journal_count =
    member "journals" (result ensured) |> Yojson.Safe.Util.to_list |> List.length
  in
  ignore
    (dispatch
       session
       ~screen:"journal"
       ~action:"ensureToday"
       ~payload:"2099-12-31"
       ());
  let current = snapshot session "journal" in
  require
    (member "journals" (result current)
     |> Yojson.Safe.Util.to_list
     |> List.length
     = journal_count)
    "ensureToday should be idempotent"
;;

let test_unknown_screens_are_rejected () =
  let session = Ocaml_demo_rpc.Session.create () in
  List.iter
    (fun screen ->
      let response = snapshot session screen in
      require
        (member "code" (member "error" response) = `String "unknown_screen")
        ("unknown screen should be rejected: " ^ screen))
    [ "settings"; "profile"; "archive" ]
;;

let test_protocol_errors_are_structured () =
  let session = Ocaml_demo_rpc.Session.create () in
  let malformed =
    Ocaml_demo_rpc.Session.call session "not json" |> Yojson.Safe.from_string
  in
  require
    (member "code" (member "error" malformed) = `String "invalid_json")
    "malformed JSON should use a stable error code";
  let unknown = dispatch session ~screen:"tasks" ~action:"explode" () in
  require
    (member "code" (member "error" unknown) = `String "unknown_action")
    "unknown actions should be explicit"
;;

let () =
  test_tasks_use_one_call_api ();
  test_outliner_rpc_edits_and_indents ();
  test_rpc_creates_missing_today ();
  test_unknown_screens_are_rejected ();
  test_protocol_errors_are_structured ()
;;
