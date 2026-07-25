let contains text ~substring =
  let text_length = String.length text in
  let substring_length = String.length substring in
  let rec loop index =
    if substring_length = 0
    then true
    else if index + substring_length > text_length
    then false
    else if String.sub text index substring_length = substring
    then true
    else loop (index + 1)
  in
  loop 0
;;

let assert_contains json substring =
  if not (contains json ~substring)
  then failwith (Printf.sprintf "expected JSON to contain %S, got: %s" substring json)
;;

let () =
  let open Ocaml_demo_android in
  let node =
    navigation_stack
      [ list
          [ "today"; "tasks"; "settings" ]
          ~key:(fun value -> value)
          ~row:(fun title -> text title)
        |> searchable ~text:"ta" ~on_change:(fun _ -> Action.ignore)
        |> toolbar
             [ toolbar_item ~id:"add" ~title:"Add" ~on_click:Action.ignore
             ; toolbar_item ~id:"done" ~title:"Done" ~on_click:Action.ignore
             ]
        |> sheet
             ~is_presented:true
             ~content:(vstack [ text "Details"; image "star" ])
             ~on_dismiss:Action.ignore
      ; custom_view ~key:"native-map" ~kind:"map" ()
      ]
  in
  let bridge = Bridge.render ~schedule_event:(fun action -> action ()) node in
  let json = Bridge.json bridge in
  List.iter
    (assert_contains json)
    [ "\"type\":\"navigationStack\""
    ; "\"type\":\"searchable\""
    ; "\"type\":\"toolbar\""
    ; "\"type\":\"sheet\""
    ; "\"type\":\"image\""
    ; "\"type\":\"customView\""
    ];
  print_endline json
;;
