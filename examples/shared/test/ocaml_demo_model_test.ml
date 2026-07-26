module Model = Ocaml_demo_model

let require condition message = if not condition then failwith message

let update_exn model action =
  match Model.update model action with
  | Ok () -> ()
  | Error _ -> failwith "unexpected model update error"
;;

let with_sqlite name test =
  let path = Filename.temp_file name ".sqlite" in
  Sys.remove path;
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists path then Sys.remove path)
    (fun () -> test path)
;;

let open_model path =
  let session = Datascript_sqlite.open_session path in
  let model = Model.create ~storage:(Datascript_sqlite.storage session) () in
  session, model
;;

let test_tasks_persist_to_sqlite () =
  with_sqlite "ocaml-demo-tasks" (fun path ->
    let session, model = open_model path in
    update_exn model (Model.Set_task_draft "Persist shared OCaml state");
    update_exn model Model.Add_task;
    let task =
      match Model.tasks model with
      | [ task ] -> task
      | _ -> failwith "adding should create exactly one task"
    in
    require (task.title = "Persist shared OCaml state") "task title should be stored";
    require (not task.completed) "new tasks should be active";
    require
      (List.exists
         (fun (block : Model.block) ->
           block.id = task.id && block.content = task.title)
         (Model.blocks model))
      "a task should be backed by the same block entity";
    update_exn model (Model.Toggle_task task.id);
    Datascript_sqlite.close session;
    let reopened_session, reopened = open_model path in
    let restored = List.hd (Model.tasks reopened) in
    require restored.completed "task completion should survive reopening SQLite";
    update_exn reopened (Model.Delete_task restored.id);
    require (Model.tasks reopened = []) "delete should remove the task";
    Datascript_sqlite.close reopened_session)
;;

let test_empty_task_is_a_no_op () =
  let model = Model.create () in
  update_exn model Model.Add_task;
  require (Model.tasks model = []) "an empty draft should not add a task";
  require (Model.revision model = 0) "a no-op should not change the revision"
;;

let test_outliner_edit_indent_and_outdent () =
  let model = Model.create () in
  require (List.length (Model.journals model) >= 2) "the home screen should list journals";
  let blocks = Model.blocks model in
  require (List.length blocks >= 3) "the outliner should contain useful demo blocks";
  let first = List.nth blocks 0 in
  let second = List.nth blocks 1 in
  update_exn model (Model.Set_block_content (second.id, "Edited in shared OCaml"));
  update_exn model (Model.Indent_block second.id);
  let edited = List.nth (Model.blocks model) 1 in
  require (edited.content = "Edited in shared OCaml") "block editing should update content";
  require (edited.depth = first.depth + 1) "indent should nest under the previous block";
  update_exn model (Model.Outdent_block second.id);
  let outdented = List.nth (Model.blocks model) 1 in
  require (outdented.depth = first.depth) "outdent should restore the parent level"
;;

let test_indent_and_outdent_move_the_whole_subtree () =
  let model = Model.create () in
  let initial = Model.blocks model in
  let parent = List.nth initial 1 in
  let child = List.nth initial 2 in
  update_exn model (Model.Indent_block parent.id);
  update_exn model (Model.Indent_block child.id);
  update_exn model (Model.Indent_block child.id);
  let nested = Model.blocks model in
  require ((List.nth nested 1).depth = 1) "the parent should be indented";
  require ((List.nth nested 2).depth = 2) "the child should remain nested";
  update_exn model (Model.Outdent_block parent.id);
  let outdented = Model.blocks model in
  require ((List.nth outdented 1).depth = 0) "outdent should move the parent";
  require ((List.nth outdented 2).depth = 1) "outdent should move its child";
  update_exn model (Model.Indent_block parent.id);
  let restored = Model.blocks model in
  require ((List.nth restored 1).depth = 1) "indent should move the parent";
  require ((List.nth restored 2).depth = 2) "indent should move its child"
;;

let test_enter_adds_sibling_after_subtree () =
  let model = Model.create () in
  let initial = Model.blocks model in
  let parent = List.nth initial 1 in
  let child = List.nth initial 2 in
  update_exn model (Model.Indent_block parent.id);
  update_exn model (Model.Indent_block child.id);
  update_exn model (Model.Indent_block child.id);
  update_exn model (Model.Add_sibling_block parent.id);
  let blocks = Model.blocks model in
  require (List.length blocks = List.length initial + 1) "Enter should add one block";
  let sibling = List.nth blocks 3 in
  require (sibling.content = "") "the new sibling should be empty";
  require (sibling.depth = 1) "the new block should have its sibling's depth";
  require
    ((List.nth blocks 2).id = child.id)
    "the new sibling should be inserted after the current block's subtree"
;;

let test_each_journal_has_its_own_outliner () =
  let model = Model.create () in
  let first = List.nth (Model.journals model) 0 in
  let second = List.nth (Model.journals model) 1 in
  let first_content = (List.hd (Model.blocks model)).content in
  update_exn model (Model.Select_journal second.id);
  let second_block = List.hd (Model.blocks model) in
  update_exn model (Model.Set_block_content (second_block.id, "Second journal"));
  update_exn model (Model.Select_journal first.id);
  require
    ((List.hd (Model.blocks model)).content = first_content)
    "editing one journal must not change another journal";
  update_exn model (Model.Select_journal second.id);
  require
    ((List.hd (Model.blocks model)).content = "Second journal")
    "selecting a journal should restore its own outliner"
;;

let test_missing_today_creates_journal_and_first_block () =
  let model = Model.create () in
  let before = List.length (Model.journals model) in
  update_exn model (Model.Ensure_today "2099-12-31");
  require
    (List.length (Model.journals model) = before + 1)
    "a missing date should create a journal page";
  let blocks = Model.blocks model in
  require (List.length blocks = 1) "a new journal should contain its first block";
  require ((List.hd blocks).content = "") "the first block should be editable and empty";
  update_exn model (Model.Ensure_today "2099-12-31");
  require
    (List.length (Model.journals model) = before + 1)
    "ensuring the same date must not create duplicates"
;;

let test_outliner_boundaries_are_no_ops () =
  let model = Model.create () in
  let first = List.hd (Model.blocks model) in
  update_exn model (Model.Indent_block first.id);
  require
    ((List.hd (Model.blocks model)).depth = 0)
    "the first block cannot be indented";
  let revision = Model.revision model in
  update_exn model (Model.Outdent_block first.id);
  require (Model.revision model = revision) "outdenting a root block should be a no-op"
;;

let test_outliner_persists_to_sqlite () =
  with_sqlite "ocaml-demo-outliner" (fun path ->
    let session, model = open_model path in
    let second = List.nth (Model.blocks model) 1 in
    update_exn model (Model.Set_block_content (second.id, "本地存储 🚀"));
    update_exn model (Model.Indent_block second.id);
    Datascript_sqlite.close session;
    let reopened_session, reopened = open_model path in
    let restored = List.nth (Model.blocks reopened) 1 in
    require (restored.content = "本地存储 🚀") "UTF-8 block content should survive reopening";
    require (restored.depth = 1) "block indentation should survive reopening";
    Datascript_sqlite.close reopened_session)
;;

let test_unknown_entities_are_reported () =
  let model = Model.create () in
  require
    (Model.update model (Model.Toggle_task 404) = Error (Model.Unknown_task 404))
    "unknown task IDs should be reported";
  require
    (Model.update model (Model.Indent_block 404) = Error (Model.Unknown_block 404))
    "unknown block IDs should be reported"
;;

let () =
  test_tasks_persist_to_sqlite ();
  test_empty_task_is_a_no_op ();
  test_outliner_edit_indent_and_outdent ();
  test_indent_and_outdent_move_the_whole_subtree ();
  test_enter_adds_sibling_after_subtree ();
  test_each_journal_has_its_own_outliner ();
  test_missing_today_creates_journal_and_first_block ();
  test_outliner_boundaries_are_no_ops ();
  test_outliner_persists_to_sqlite ();
  test_unknown_entities_are_reported ()
;;
