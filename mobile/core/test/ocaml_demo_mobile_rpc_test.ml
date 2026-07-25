let require condition message = if not condition then failwith message

let call session json =
  Ocaml_demo_mobile_rpc.Session.call session (Yojson.Safe.to_string json)
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

let test_counter_uses_one_call_api () =
  let session = Ocaml_demo_mobile_rpc.Session.create () in
  let initial = snapshot session "counter" in
  require_success initial;
  require (member "count" (result initial) = `Int 0) "counter should start at zero";
  let incremented = dispatch session ~screen:"counter" ~action:"increment" () in
  require_success incremented;
  require (member "count" (result incremented) = `Int 1) "dispatch should update OCaml";
  require
    (member "revision" (result incremented) = `Int 1)
    "response should identify the new model revision"
;;

let test_todo_and_search_share_the_same_session_model () =
  let session = Ocaml_demo_mobile_rpc.Session.create () in
  ignore
    (dispatch
       session
       ~screen:"todo"
       ~action:"setDraft"
       ~payload:"One API"
       ());
  let added = dispatch session ~screen:"todo" ~action:"add" () in
  require_success added;
  let items = member "items" (result added) |> Yojson.Safe.Util.to_list in
  let todo =
    match items with
    | [ todo ] -> todo
    | _ -> failwith "todo dispatch should return one item"
  in
  require (member "title" todo = `String "One API") "OCaml should own todo state";
  let searched =
    dispatch session ~screen:"search" ~action:"setQuery" ~payload:"t" ()
  in
  require_success searched;
  require
    (member "results" (result searched)
     = `List [ `String "Today"; `String "Tasks"; `String "Settings"; `String "Projects" ])
    "OCaml should own search filtering";
  require
    (member "revision" (result searched) = `Int 3)
    "all screens should observe one shared model revision"
;;

let test_protocol_errors_are_structured () =
  let session = Ocaml_demo_mobile_rpc.Session.create () in
  let malformed =
    Ocaml_demo_mobile_rpc.Session.call session "not json" |> Yojson.Safe.from_string
  in
  require (member "ok" malformed = `Bool false) "malformed JSON should fail";
  require
    (member "code" (member "error" malformed) = `String "invalid_json")
    "malformed JSON should use a stable error code";
  let future =
    call
      session
      (`Assoc
        [ "apiVersion", `Int 2
        ; "method", `String "snapshot"
        ; "params", `Assoc [ "screen", `String "counter" ]
        ])
  in
  require
    (member "code" (member "error" future) = `String "unsupported_version")
    "future protocol versions should be rejected";
  let unknown = dispatch session ~screen:"counter" ~action:"explode" () in
  require
    (member "code" (member "error" unknown) = `String "unknown_action")
    "unknown actions should be explicit";
  let current = snapshot session "counter" in
  require
    (member "revision" (result current) = `Int 0)
    "invalid calls should not mutate the shared model"
;;

let test_json_strings_round_trip_through_ocaml () =
  let session = Ocaml_demo_mobile_rpc.Session.create () in
  let title = "Quote: \" Backslash: \\ Newline:\nUnicode: 你好 👋" in
  ignore (dispatch session ~screen:"todo" ~action:"setDraft" ~payload:title ());
  let added = dispatch session ~screen:"todo" ~action:"add" () in
  let items = member "items" (result added) |> Yojson.Safe.Util.to_list in
  let todo =
    match items with
    | [ todo ] -> todo
    | _ -> failwith "escaped todo dispatch should return one item"
  in
  require (member "title" todo = `String title) "JSON strings should round trip";
  let trailing =
    Ocaml_demo_mobile_rpc.Session.call
      session
      {|{"apiVersion":1,"method":"snapshot","params":{"screen":"counter"}} trailing|}
    |> Yojson.Safe.from_string
  in
  require
    (member "code" (member "error" trailing) = `String "invalid_json")
    "trailing JSON input should be rejected";
  let leading_zero =
    Ocaml_demo_mobile_rpc.Session.call
      session
      {|{"apiVersion":01,"method":"snapshot","params":{"screen":"counter"}}|}
    |> Yojson.Safe.from_string
  in
  require
    (member "code" (member "error" leading_zero) = `String "invalid_json")
    "invalid JSON numbers should be rejected"
;;

let () =
  test_counter_uses_one_call_api ();
  test_todo_and_search_share_the_same_session_model ();
  test_protocol_errors_are_structured ();
  test_json_strings_round_trip_through_ocaml ()
;;
