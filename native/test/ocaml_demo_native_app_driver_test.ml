module Native = Ocaml_demo_native

let require condition message =
  if not condition then failwith message
;;

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

let count_occurrences text ~substring =
  let text_length = String.length text in
  let substring_length = String.length substring in
  let rec loop index count =
    if substring_length = 0 || index + substring_length > text_length
    then count
    else if String.sub text index substring_length = substring
    then loop (index + substring_length) (count + 1)
    else loop (index + 1) count
  in
  loop 0 0
;;

let counter graph =
  let count, set_count = Native.state graph ~key:"count" 0 in
  Native.vstack
    [ Native.text (string_of_int count)
    ; Native.button "Increment" ~on_click:(set_count (count + 1))
    ]
;;

let test_event_rerenders_component_state () =
  let app = Native.App.create counter in
  let before = Native.App.render_json app in
  require (contains before ~substring:{|"text":"0"|}) "initial render should show count 0";
  Native.App.dispatch_click app 1;
  let after = Native.App.render_json app in
  require (contains after ~substring:{|"text":"1"|}) "click should rerender count 1"
;;

let scoped_counter key graph =
  Native.scope graph ~key (fun graph ->
    let count, set_count = Native.state graph ~key:"count" 0 in
    Native.button (key ^ ":" ^ string_of_int count) ~on_click:(set_count (count + 1)))
;;

let test_scoped_state_is_independent () =
  let app =
    Native.App.create (fun graph ->
      Native.vstack [ scoped_counter "a" graph; scoped_counter "b" graph ])
  in
  let before = Native.App.render_json app in
  require (contains before ~substring:{|"text":"a:0"|}) "initial render should show a:0";
  require (contains before ~substring:{|"text":"b:0"|}) "initial render should show b:0";
  Native.App.dispatch_click app 1;
  let after = Native.App.render_json app in
  require (contains after ~substring:{|"text":"a:1"|}) "first scoped counter should update";
  require (contains after ~substring:{|"text":"b:0"|}) "second scoped counter should not update"
;;

let test_change_event_updates_component_state () =
  let component graph =
    let value, set_value = Native.state graph ~key:"value" "" in
    Native.text_field ~text:value ~placeholder:"Search" ~on_change:set_value ()
  in
  let app = Native.App.create component in
  let before = Native.App.render_json app in
  require (contains before ~substring:{|"text":""|}) "initial field should be empty";
  Native.App.dispatch_change app 1 ~text:"tasks";
  let after = Native.App.render_json app in
  require (contains after ~substring:{|"text":"tasks"|}) "change should rerender text"
;;

let test_derived_reuses_cached_value_until_input_changes () =
  let computations = ref 0 in
  let component graph =
    let value, set_value = Native.Graph.state graph ~key:"value" 1 in
    let tick, set_tick = Native.Graph.state graph ~key:"tick" 0 in
    let doubled =
      Native.Graph.derived graph ~key:"doubled" ~input:value ~f:(fun value ->
        incr computations;
        value * 2)
    in
    Native.vstack
      [ Native.text (Printf.sprintf "%d:%d" doubled tick)
      ; Native.button "Increment value" ~on_click:(set_value (value + 1))
      ; Native.button "Rerender" ~on_click:(set_tick (tick + 1))
      ]
  in
  let app = Native.App.create component in
  let before = Native.App.render_json app in
  require (contains before ~substring:{|"text":"2:0"|}) "initial derived value should render";
  require (!computations = 1) "derived should compute initial value once";
  Native.App.dispatch_click app 2;
  let after_unrelated = Native.App.render_json app in
  require
    (contains after_unrelated ~substring:{|"text":"2:1"|})
    "unrelated state should rerender";
  require (!computations = 1) "derived should not recompute when input is unchanged";
  Native.App.dispatch_click app 1;
  let after_input_change = Native.App.render_json app in
  require
    (contains after_input_change ~substring:{|"text":"4:1"|})
    "input state should update derived value";
  require (!computations = 2) "derived should recompute after input changes"
;;

let test_subscription_starts_once_updates_and_cancels_when_unused () =
  let starts = ref 0 in
  let cancels = ref 0 in
  let emit_value = ref (fun (_value : int) -> ()) in
  let component graph =
    let show, set_show = Native.Graph.state graph ~key:"show" true in
    let tick, set_tick = Native.Graph.state graph ~key:"tick" 0 in
    let children =
      if show
      then (
        let value =
          Native.Graph.subscribe graph ~key:"external" ~default:0 (fun ~emit ->
            incr starts;
            emit_value := emit;
            fun () -> incr cancels)
        in
        [ Native.text (Printf.sprintf "value:%d tick:%d" value tick)
        ; Native.button "Hide" ~on_click:(set_show false)
        ; Native.button "Rerender" ~on_click:(set_tick (tick + 1))
        ])
      else [ Native.text "hidden" ]
    in
    Native.vstack children
  in
  let app = Native.App.create component in
  let before = Native.App.render_json app in
  require
    (contains before ~substring:{|"text":"value:0 tick:0"|})
    "subscription default should render";
  require (!starts = 1) "subscription should start on first render";
  (!emit_value) 2;
  let after_emit = Native.App.render_json app in
  require
    (contains after_emit ~substring:{|"text":"value:2 tick:0"|})
    "subscription emit should update rendered value";
  Native.App.dispatch_click app 2;
  let after_unrelated = Native.App.render_json app in
  require
    (contains after_unrelated ~substring:{|"text":"value:2 tick:1"|})
    "unrelated rerender should keep subscription value";
  require (!starts = 1) "subscription should not restart across rerenders";
  require (!cancels = 0) "active subscription should not be canceled";
  Native.App.dispatch_click app 1;
  let after_hide = Native.App.render_json app in
  require (contains after_hide ~substring:{|"text":"hidden"|}) "hidden branch should render";
  require (!cancels = 1) "subscription should cancel when component stops using it";
  (!emit_value) 3;
  let after_stale_emit = Native.App.render_json app in
  require
    (not (contains after_stale_emit ~substring:"value:3"))
    "stale subscription emit should not revive canceled subscription"
;;

let test_state_update_during_render_triggers_follow_up_render () =
  let component graph =
    let value, set_value = Native.Graph.state graph ~key:"value" "initial" in
    let (_ : unit) =
      Native.Graph.subscribe graph ~key:"load" ~default:() (fun ~emit:_ ->
        set_value "loaded" ();
        fun () -> ())
    in
    Native.text value
  in
  let app = Native.App.create component in
  let rendered = Native.App.render_json app in
  require
    (contains rendered ~substring:{|"text":"loaded"|})
    "state updates during render should trigger a follow-up render"
;;

let test_render_json_declares_schema_version_once_at_root () =
  let app =
    Native.App.create (fun _graph ->
      Native.vstack [ Native.text "first"; Native.hstack [ Native.text "second" ] ])
  in
  let rendered = Native.App.render_json app in
  require
    (contains rendered ~substring:{|"schemaVersion":1|})
    "render JSON should declare the bridge schema version";
  require
    (count_occurrences rendered ~substring:{|"schemaVersion":1|} = 1)
    "schema version should appear once on the root node, not on every nested node"
;;

let test_render_json_escapes_all_ascii_control_characters () =
  let control_text = String.init 32 Char.chr in
  let app = Native.App.create (fun _graph -> Native.text control_text) in
  let rendered = Native.App.render_json app in
  List.iter
    (fun code ->
       let escaped =
         match code with
         | 8 -> "\\b"
         | 9 -> "\\t"
         | 10 -> "\\n"
         | 12 -> "\\f"
         | 13 -> "\\r"
         | code -> Printf.sprintf "\\u%04x" code
       in
       require
         (contains rendered ~substring:escaped)
         (Printf.sprintf "ASCII control character %d should render as %s" code escaped))
    (List.init 32 Fun.id);
  String.iter
    (fun character ->
       require
         (Char.code character >= 32)
         "render JSON should not contain raw ASCII control characters")
    rendered
;;

let () =
  test_event_rerenders_component_state ();
  test_scoped_state_is_independent ();
  test_change_event_updates_component_state ();
  test_derived_reuses_cached_value_until_input_changes ();
  test_subscription_starts_once_updates_and_cancels_when_unused ();
  test_state_update_during_render_triggers_follow_up_render ();
  test_render_json_declares_schema_version_once_at_root ();
  test_render_json_escapes_all_ascii_control_characters ()
