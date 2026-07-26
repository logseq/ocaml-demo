open Datascript

type task =
  { id : int
  ; title : string
  ; completed : bool
  }

type block =
  { id : int
  ; content : string
  ; depth : int
  }

type journal =
  { id : int
  ; title : string
  }

type t =
  { mutable db : db
  }

type action =
  | Set_task_draft of string
  | Add_task
  | Toggle_task of int
  | Delete_task of int
  | Ensure_today of string
  | Select_journal of int
  | Set_block_content of int * string
  | Add_sibling_block of int
  | Indent_block of int
  | Outdent_block of int

type error =
  | Unknown_task of int
  | Unknown_journal of int
  | Unknown_block of int

let one ?unique ?value_type ?(indexed = false) () =
  { cardinality = One
  ; unique
  ; indexed
  ; is_component = false
  ; no_history = false
  ; doc = None
  ; value_type
  ; tuple_attrs = None
  ; tuple_types = None
  }
;;

let schema =
  [ "app/id", one ~unique:Identity ~value_type:StringType ~indexed:true ()
  ; "app/revision", one ~value_type:NumberType ()
  ; "app/task-draft", one ~value_type:StringType ()
  ; "app/selected-journal", one ~value_type:NumberType ()
  ; "journal/id", one ~unique:Identity ~value_type:NumberType ~indexed:true ()
  ; "journal/title", one ~value_type:StringType ()
  ; "journal/order", one ~value_type:NumberType ()
  ; "block/id", one ~unique:Identity ~value_type:NumberType ~indexed:true ()
  ; "block/content", one ~value_type:StringType ()
  ; "block/depth", one ~value_type:NumberType ()
  ; "block/order", one ~value_type:NumberType ()
  ; "block/journal", one ~value_type:NumberType ~indexed:true ()
  ; "block/task", one ~indexed:true ()
  ; "block/completed", one ()
  ]
;;

let app_ref = Lookup_ref ("app/id", String "state")
let block_ref id = Lookup_ref ("block/id", Int id)

let entity_attr_value db entity_ref attr =
  match entity db entity_ref with
  | None -> None
  | Some entity ->
    (match entity_attr entity attr with
     | Some (One_value value) -> Some value
     | _ -> None)
;;

let int_attr db entity_ref attr default =
  match entity_attr_value db entity_ref attr with
  | Some (Int value) -> value
  | _ -> default
;;

let string_attr db entity_ref attr default =
  match entity_attr_value db entity_ref attr with
  | Some (String value) -> value
  | _ -> default
;;

let bool_attr db entity_ref attr default =
  match entity_attr_value db entity_ref attr with
  | Some (Bool value) -> value
  | _ -> default
;;

let seed_blocks =
  [ "Welcome to the OCaml outliner"
  ; "Tap any block to edit it"
  ; "Indent and outdent with the controls"
  ]
;;

let initial_transactions =
  [ Add (Temp_id "app", "app/id", String "state")
  ; Add (Temp_id "app", "app/revision", Int 0)
  ; Add (Temp_id "app", "app/task-draft", String "")
  ; Add (Temp_id "app", "app/selected-journal", Int 1)
  ; Add (Temp_id "journal-1", "journal/id", Int 1)
  ; Add (Temp_id "journal-1", "journal/title", String "2026-07-25")
  ; Add (Temp_id "journal-1", "journal/order", Int 0)
  ; Add (Temp_id "journal-2", "journal/id", Int 2)
  ; Add (Temp_id "journal-2", "journal/title", String "2026-07-24")
  ; Add (Temp_id "journal-2", "journal/order", Int 1)
  ]
  @ List.concat
      (List.mapi
         (fun index content ->
           let id = index + 1 in
           let temp_id = "block-" ^ string_of_int id in
           [ Add (Temp_id temp_id, "block/id", Int id)
           ; Add (Temp_id temp_id, "block/content", String content)
           ; Add (Temp_id temp_id, "block/depth", Int 0)
           ; Add (Temp_id temp_id, "block/order", Int index)
           ; Add (Temp_id temp_id, "block/journal", Int 1)
           ])
         seed_blocks)
  @ [ Add (Temp_id "block-4", "block/id", Int 4)
    ; Add (Temp_id "block-4", "block/content", String "Yesterday's notes")
    ; Add (Temp_id "block-4", "block/depth", Int 0)
    ; Add (Temp_id "block-4", "block/order", Int 0)
    ; Add (Temp_id "block-4", "block/journal", Int 2)
    ]
;;

let create ?storage () =
  let db =
    match storage with
    | Some storage ->
      (match restore storage with
       | Some db -> db
       | None ->
         let report = transact (empty_db ~schema ~storage ()) initial_transactions in
         store ~storage report.db_after;
         report.db_after)
    | None -> (transact (empty_db ~schema ()) initial_transactions).db_after
  in
  { db }
;;

let revision model = int_attr model.db app_ref "app/revision" 0
let task_draft model = string_attr model.db app_ref "app/task-draft" ""
let selected_journal_id model = int_attr model.db app_ref "app/selected-journal" 1

let entity_ids_with_attr db attr =
  datoms db Aevt ~a:attr () |> List.of_seq
  |> List.filter_map (fun datom ->
    match datom.v with
    | Int id -> Some id
    | _ -> None)
;;

let tasks model =
  entity_ids_with_attr model.db "block/id"
  |> List.filter (fun id -> bool_attr model.db (block_ref id) "block/task" false)
  |> List.map (fun id ->
    let entity_ref = block_ref id in
    ( int_attr model.db entity_ref "block/order" id
    , { id
      ; title = string_attr model.db entity_ref "block/content" ""
      ; completed = bool_attr model.db entity_ref "block/completed" false
      } ))
  |> List.sort (fun (left, _) (right, _) -> Int.compare left right)
  |> List.map snd
;;

let journals model =
  entity_ids_with_attr model.db "journal/id"
  |> List.map (fun id ->
    let entity_ref = Lookup_ref ("journal/id", Int id) in
    ( int_attr model.db entity_ref "journal/order" id
    , { id; title = string_attr model.db entity_ref "journal/title" "" } ))
  |> List.sort (fun (left, _) (right, _) -> Int.compare left right)
  |> List.map snd
;;

let blocks model =
  entity_ids_with_attr model.db "block/id"
  |> List.filter (fun id ->
    int_attr model.db (block_ref id) "block/journal" 0 = selected_journal_id model)
  |> List.map (fun id ->
    let entity_ref = block_ref id in
    ( int_attr model.db entity_ref "block/order" id
    , { id
      ; content = string_attr model.db entity_ref "block/content" ""
      ; depth = int_attr model.db entity_ref "block/depth" 0
      } ))
  |> List.sort (fun (left, _) (right, _) -> Int.compare left right)
  |> List.map snd
;;

let commit model transactions =
  let next_revision = revision model + 1 in
  let report =
    transact model.db (transactions @ [ Add (app_ref, "app/revision", Int next_revision) ])
  in
  model.db <- report.db_after;
  match storage model.db with
  | Some storage -> store ~storage model.db
  | None -> ()
;;

let task_exists model id =
  bool_attr model.db (block_ref id) "block/task" false
;;

let block_exists model id =
  entity_attr_value model.db (block_ref id) "block/id" <> None
;;

let journal_exists model id =
  entity_attr_value model.db (Lookup_ref ("journal/id", Int id)) "journal/id" <> None
;;

let next_block_id model =
  List.fold_left
    max
    0
    (entity_ids_with_attr model.db "block/id")
  + 1
;;

let next_journal_id model =
  List.fold_left max 0 (entity_ids_with_attr model.db "journal/id") + 1
;;

let journal_id_by_title model title =
  List.find_map
    (fun (journal : journal) ->
      if String.equal journal.title title then Some journal.id else None)
    (journals model)
;;

let update_block_subtree_depth blocks index delta =
  let target : block = List.nth blocks index in
  let rec subtree acc (remaining : block list) =
    match remaining with
    | [] -> List.rev acc
    | block :: rest when block.id = target.id || block.depth > target.depth ->
      subtree
        (Add (block_ref block.id, "block/depth", Int (block.depth + delta)) :: acc)
        rest
    | _ -> List.rev acc
  in
  let rec drop count (values : block list) =
    if count = 0
    then values
    else
      match values with
      | [] -> []
      | _ :: rest -> drop (count - 1) rest
  in
  subtree [] (drop index blocks)
;;

let rec update model = function
  | Set_task_draft draft ->
    if String.equal draft (task_draft model)
    then Ok ()
    else (
      commit model [ Add (app_ref, "app/task-draft", String draft) ];
      Ok ())
  | Add_task ->
    let title = String.trim (task_draft model) in
    if String.equal title ""
    then Ok ()
    else (
      let id = next_block_id model in
      let order = List.length (blocks model) in
      let journal_id = selected_journal_id model in
      let temp_id = "block-" ^ string_of_int id in
      commit
        model
        [ Add (Temp_id temp_id, "block/id", Int id)
        ; Add (Temp_id temp_id, "block/content", String title)
        ; Add (Temp_id temp_id, "block/depth", Int 0)
        ; Add (Temp_id temp_id, "block/order", Int order)
        ; Add (Temp_id temp_id, "block/journal", Int journal_id)
        ; Add (Temp_id temp_id, "block/task", Bool true)
        ; Add (Temp_id temp_id, "block/completed", Bool false)
        ; Add (app_ref, "app/task-draft", String "")
        ];
      Ok ())
  | Toggle_task id ->
    if not (task_exists model id)
    then Error (Unknown_task id)
    else (
      let completed = bool_attr model.db (block_ref id) "block/completed" false in
      commit model [ Add (block_ref id, "block/completed", Bool (not completed)) ];
      Ok ())
  | Delete_task id ->
    if not (task_exists model id)
    then Error (Unknown_task id)
    else (
      commit model [ RetractEntity (block_ref id) ];
      Ok ())
  | Ensure_today date ->
    (match journal_id_by_title model date with
     | Some id -> update model (Select_journal id)
     | None ->
       let journal_id = next_journal_id model in
       let block_id = next_block_id model in
       let journal_temp = "journal-" ^ string_of_int journal_id in
       let block_temp = "block-" ^ string_of_int block_id in
       commit
         model
         [ Add (Temp_id journal_temp, "journal/id", Int journal_id)
         ; Add (Temp_id journal_temp, "journal/title", String date)
         ; Add (Temp_id journal_temp, "journal/order", Int (-journal_id))
         ; Add (Temp_id block_temp, "block/id", Int block_id)
         ; Add (Temp_id block_temp, "block/content", String "")
         ; Add (Temp_id block_temp, "block/depth", Int 0)
         ; Add (Temp_id block_temp, "block/order", Int 0)
         ; Add (Temp_id block_temp, "block/journal", Int journal_id)
         ; Add (app_ref, "app/selected-journal", Int journal_id)
         ];
       Ok ())
  | Select_journal id ->
    if not (journal_exists model id)
    then Error (Unknown_journal id)
    else if selected_journal_id model = id
    then Ok ()
    else (
      commit model [ Add (app_ref, "app/selected-journal", Int id) ];
      Ok ())
  | Set_block_content (id, content) ->
    if not (block_exists model id)
    then Error (Unknown_block id)
    else if String.equal content (string_attr model.db (block_ref id) "block/content" "")
    then Ok ()
    else (
      commit model [ Add (block_ref id, "block/content", String content) ];
      Ok ())
  | Add_sibling_block id ->
    let blocks = blocks model in
    (match List.find_index (fun (block : block) -> block.id = id) blocks with
     | None -> Error (Unknown_block id)
     | Some index ->
       let target = List.nth blocks index in
       let rec insertion_index position = function
         | (block : block) :: rest when block.depth > target.depth ->
           insertion_index (position + 1) rest
         | _ -> position
       in
       let following =
         List.filteri (fun position _ -> position > index) blocks
       in
       let insertion = insertion_index (index + 1) following in
       let shifted_orders =
         blocks
         |> List.mapi (fun position (block : block) ->
           if position < insertion
           then None
           else Some (Add (block_ref block.id, "block/order", Int (position + 1))))
         |> List.filter_map Fun.id
       in
       let new_id = next_block_id model in
       let temp_id = "block-" ^ string_of_int new_id in
       commit
         model
         (shifted_orders
          @ [ Add (Temp_id temp_id, "block/id", Int new_id)
            ; Add (Temp_id temp_id, "block/content", String "")
            ; Add (Temp_id temp_id, "block/depth", Int target.depth)
            ; Add (Temp_id temp_id, "block/order", Int insertion)
            ; Add
                ( Temp_id temp_id
                , "block/journal"
                , Int (selected_journal_id model) )
            ]);
       Ok ())
  | Indent_block id ->
    if not (block_exists model id)
    then Error (Unknown_block id)
    else (
      let blocks = blocks model in
      let index =
        List.find_index (fun (block : block) -> block.id = id) blocks
        |> Option.value ~default:0
      in
      if index = 0
      then Ok ()
      else (
        let block = List.nth blocks index in
        let previous = List.nth blocks (index - 1) in
        if previous.depth < block.depth
        then Ok ()
        else (
          commit model (update_block_subtree_depth blocks index 1);
          Ok ())))
  | Outdent_block id ->
    if not (block_exists model id)
    then Error (Unknown_block id)
    else (
      let blocks = blocks model in
      let index =
        List.find_index (fun (block : block) -> block.id = id) blocks
        |> Option.value ~default:0
      in
      let block = List.nth blocks index in
      if block.depth = 0
      then Ok ()
      else (
        commit model (update_block_subtree_depth blocks index (-1));
        Ok ()))
;;
