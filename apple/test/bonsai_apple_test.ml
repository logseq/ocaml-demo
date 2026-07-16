module Apple = Bonsai_apple
module Backend = Apple.For_testing.Backend
module App = Apple.App.Make (Backend)

let require condition message = if not condition then failwith message

let contains text ~substring =
  let text_length = String.length text in
  let substring_length = String.length substring in
  let rec loop index =
    if index + substring_length > text_length
    then false
    else if String.sub text index substring_length = substring
    then true
    else loop (index + 1)
  in
  substring_length = 0 || loop 0
;;

let count_substrings text ~substring =
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

let substring_index text ~substring ~from =
  let text_length = String.length text in
  let substring_length = String.length substring in
  let rec loop index =
    if substring_length = 0
    then Some index
    else if index + substring_length > text_length
    then None
    else if String.sub text index substring_length = substring
    then Some index
    else loop (index + 1)
  in
  loop from
;;

let read_file path =
  let channel = open_in path in
  Fun.protect
    ~finally:(fun () -> close_in channel)
    (fun () ->
       let length = in_channel_length channel in
       really_input_string channel length)
;;

let swiftui_source_path = "../swiftui/BonsaiNativeSwiftUI.swift"
let swiftui_mac_source_path = "../swiftui/BonsaiNativeSwiftUIMac.swift"
let swiftui_backend_source_path = "../swiftui/bonsai_apple_swiftui.ml"
let swiftui_stubs_source_path = "../swiftui/bonsai_apple_swiftui_stubs.c"
let swiftui_dune_path = "../swiftui/dune"
let apple_source_path = "../src/bonsai_apple.ml"
let bootstrap_ios_script_path = "../../scripts/bootstrap-ios-jane.sh"

let test_navigation_value_links_keep_primary_tap_for_link () =
  let source = read_file swiftui_source_path in
  require
    (count_substrings
       source
       ~substring:"navigationLinkLabel(suppressRowActions: true)"
     >= 2)
    "both value-based and destination-based NavigationLink labels should suppress \
     nested row actions so the primary tap opens the link"
;;

let test_navigation_links_render_without_system_link_chrome () =
  let source = read_file swiftui_source_path in
  let value_link_start =
    match
      substring_index
        source
        ~substring:"NavigationLink(value: navigationValue)"
        ~from:0
    with
    | Some index -> index
    | None -> failwith "value-based NavigationLink branch not found"
  in
  let destination_link_start =
    match substring_index source ~substring:"NavigationLink {" ~from:value_link_start with
    | Some index -> index
    | None -> failwith "destination NavigationLink branch not found"
  in
  let first_plain_style =
    match substring_index source ~substring:".buttonStyle(.plain)" ~from:value_link_start with
    | Some index -> index
    | None -> failwith "value-based NavigationLink plain style not found"
  in
  let second_plain_style =
    match
      substring_index source ~substring:".buttonStyle(.plain)" ~from:destination_link_start
    with
    | Some index -> index
    | None -> failwith "destination NavigationLink plain style not found"
  in
  require
    (first_plain_style < destination_link_start)
    "value-based NavigationLink should use plain button style so inline links do not \
     show system link chrome";
  require
    (second_plain_style > destination_link_start)
    "destination NavigationLink should use plain button style so inline links do not \
     show system link chrome"
;;

let test_navigation_value_links_do_not_preempt_system_push () =
  let source = read_file swiftui_source_path in
  let value_link_start =
    match
      substring_index
        source
        ~substring:"if let navigationValue = node.navigationLinkValue"
        ~from:0
    with
    | Some index -> index
    | None -> failwith "value-based NavigationLink branch not found"
  in
  let destination_link_start =
    match
      substring_index
        source
        ~substring:"} else {\n        NavigationLink {"
        ~from:value_link_start
    with
    | Some index -> index
    | None -> failwith "destination NavigationLink branch not found"
  in
  let value_branch =
    String.sub source value_link_start (destination_link_start - value_link_start)
  in
  require
    (not (contains value_branch ~substring:"simultaneousGesture"))
    "value-based NavigationLink should let NavigationStack update path first so push/pop \
     and header transitions remain native"
;;

let test_compact_sidebar_uses_chatgpt_drawer () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"@State private var isCompactSidebarOpen = false")
    "compact sidebar should be a drawer that can stay open over the main page";
  require
    (contains source ~substring:"private func compactSidebarDrawerWidth")
    "compact sidebar should compute a drawer width that leaves the main page visible";
  require
    (contains source ~substring:"private func compactSidebarPeekWidth")
    "compact sidebar should reserve a visible main-page peek like ChatGPT";
  require
    (contains source ~substring:"compactSidebarMainCornerRadius")
    "compact sidebar should round the main page while the drawer is open";
  require
    (contains
       source
       ~substring:
         "RoundedRectangle(\n                cornerRadius: \
          compactSidebarMainCornerRadius(progress: progress),\n                style: \
          .continuous")
    "compact sidebar should use the same continuous corner curve as normal page \
     transitions";
  require
    (contains source ~substring:"48 * progress")
    "compact sidebar main page corner radius should match the larger system page \
     transition radius";
  require
    (contains source ~substring:"compactSidebarMainShadowOpacity")
    "compact sidebar should cast a shadow from the visible main page edge";
  require
    (contains
       source
       ~substring:"GeometryReader { proxy in\n        let screenSize = proxy.size")
    "compact drawer should measure the full screen, not the safe-area content rect";
  require
    (contains
       source
       ~substring:
         "}\n      .ignoresSafeArea(.container, edges: .all)\n    }\n  }\n\n  private var compactSidebarMainPage")
    "compact drawer geometry should ignore safe areas so the rounded main card starts \
     at the screen top";
  require
    (contains source ~substring:"DragGesture(minimumDistance: 16, coordinateSpace: .global)")
    "compact sidebar should support swipe-right from anywhere on the main page";
  require
    (contains source ~substring:".highPriorityGesture(")
    "compact sidebar root should receive horizontal open drags before nested content \
     gestures swallow them";
  require
    (contains source ~substring:"handleCompactSidebarDragChanged")
    "compact sidebar should update interactively during horizontal drags";
  require
    (contains source ~substring:".allowsHitTesting(!isCompactSidebarOpen)")
    "compact sidebar should disable main-page taps while the drawer is open";
  require
    (contains
       source
       ~substring:
         ".environment(\\.bonsaiSuppressNativeToolbar, isCompactSidebarOpen || \
          isCompactSidebarDragging)")
    "compact sidebar should hide main-page bottom toolbar while the drawer is open or \
     dragging";
  require
    (not (contains source ~substring:"preferredCompactColumn: $compactSidebarPreferredColumn"))
    "compact sidebar should not rely on split-view compact column selection for the \
     ChatGPT-style drawer";
  require
    (not (contains source ~substring:"NavigationLink(isActive: $isCompactSidebarMainPagePresented)"))
    "compact sidebar should not rely on a hidden deprecated NavigationLink to push on launch";
  require
    (count_substrings source ~substring:"performSidebarAction(action)" >= 2)
    "compact sidebar action taps should share the data-driven action helper";
  require
    (contains source ~substring:"selectSidebarActionRoute(selectedTab")
    "compact sidebar actions should select the route locally before the OCaml rerender";
  require
    (contains source ~substring:"node.selectedTabId = selectedTab")
    "compact sidebar route selection should update the selected route before pushing the \
     main page";
  require
    (count_substrings source ~substring:"closeCompactSidebarIfNeeded(action)" = 1)
    "compact sidebar action close policy should stay centralized"
;;

let test_compact_sidebar_keeps_drawer_drag_arbitration_local () =
  let source = read_file swiftui_source_path in
  require
    (not (contains source ~substring:"private var canSelectCompactSidebarItem"))
    "compact drawer should not keep the old tap lockout helper";
  require
    (contains source ~substring:"private enum DragAxis")
    "compact drawer should classify drag axis before opening the sidebar";
  require
    (not (contains source ~substring:"didContentHorizontalSwipeOwnCurrentDrag"))
    "row swipe ownership tracking should not be reintroduced"
;;

let test_compact_sidebar_uses_drawer_for_content_swipes () =
  let source = read_file swiftui_source_path in
  require
    (not (contains source ~substring:"bonsaiContentHorizontalSwipeActiveChanged"))
    "drawer swipe should rely on directional event gating instead of content swipe callbacks";
  require
    (contains source ~substring:"handleCompactSidebarDragEnded")
    "compact sidebar should finish right/left swipes through the drawer transition"
;;

let test_horizontal_swipe_ignores_disabled_directions () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"private func horizontalSwipeOffset")
    "horizontal swipe modifier should centralize directional offset gating";
  require
    (contains source ~substring:"guard node.horizontalSwipeRightEventId != nil else { return 0 }")
    "right swipe should not move row content when the right action is disabled";
  require
    (contains source ~substring:"guard node.horizontalSwipeLeftEventId != nil else { return 0 }")
    "left swipe should not move row content when the left action is disabled";
  require
    (contains source ~substring:"guard let eventId = horizontalSwipeEventId")
    "horizontal swipe should only haptic/send for an enabled direction"
;;

let test_native_list_uses_stable_node_identity () =
  let source = read_file swiftui_source_path in
  require
    (not
       (contains
          source
          ~substring:"ForEach(Array(node.children.enumerated()), id: \\.offset)"))
    "SwiftUI List rows should use the stable BonsaiNativeNode id, not the row offset, \
     so appending rows does not recycle every row identity";
  require
    (not (contains source ~substring:".id(index)"))
    "SwiftUI List scroll identifiers should use the stable node id instead of the row \
     offset";
  require
    (contains source ~substring:"proxy.scrollTo(targetID)")
    "focused-row scrolling should target the focused BonsaiNativeNode id"
;;

let test_list_virtualization_probe_does_not_log_per_row_events () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"list_update reason=")
    "list virtualization probe should keep summary update logs for device verification";
  require
    (contains source ~substring:"BONSAI_NATIVE_LIST_DEBUG")
    "list virtualization probe should be opt-in so row appear bookkeeping is not on the \
     scroll hot path by default";
  require
    (not (contains source ~substring:"appearedRowsByList"))
    "list virtualization probe should not retain a set of every row that has ever \
     appeared; that cost grows with scroll distance";
  require
    (not (contains source ~substring:"unique_appeared_rows"))
    "list virtualization probe logs should not require unbounded per-row history";
  require
    (not (contains source ~substring:"row_appear list="))
    "list virtualization probe should not log every row appear event because that makes \
     scrolling measurements noisy";
  require
    (not (contains source ~substring:"row_disappear list="))
    "list virtualization probe should not log every row disappear event because that \
     makes scrolling measurements noisy"
;;

let test_swiftui_library_builds_in_default_ios_context () =
  let source = read_file swiftui_dune_path in
  require
    (contains source ~substring:"default.ios")
    "dune -x ios uses the default.ios target context; bonsai_apple.swiftui must be \
     enabled there so iOS sysroot installs do not keep stale SwiftUI artifacts";
  require
    (contains source ~substring:"public_name bonsai_apple.swiftui")
    "the default.ios context coverage should apply to the public SwiftUI sublibrary"
;;

let test_lazy_list_renders_rows_in_testing_backend () =
  Backend.reset ();
  let app =
    App.create (fun _graph ->
      Apple.lazy_list ~length:3
        ~key:(fun index -> "row-" ^ string_of_int index)
        ~row:(fun index -> Apple.text ("Lazy " ^ string_of_int index))
        ())
  in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  let rendered = Backend.show root in
  require
    (contains rendered ~substring:"text=\"Lazy 0\"")
    "testing backend should materialize lazy list rows for assertions";
  require
    (contains rendered ~substring:"text=\"Lazy 2\"")
    "testing backend should render all lazy list rows"
;;

let test_lazy_list_patches_cached_rows () =
  Backend.reset ();
  let app =
    App.create (fun graph ->
      let count, set_count = Apple.state graph ~key:"count" 0 in
      Apple.vstack
        [
          Apple.lazy_list ~length:1 ~key:(fun _ -> "stable-row")
            ~row:(fun _ -> Apple.text ("Lazy " ^ string_of_int count))
            ();
          Apple.button "Increment" ~on_click:(set_count (count + 1));
        ])
  in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  require
    (String.equal (Backend.find_text_exn root ~path:[ 0; 0 ]) "Lazy 0")
    "initial lazy row should render state";
  Backend.click_exn root ~path:[ 1 ];
  require
    (String.equal (Backend.find_text_exn root ~path:[ 0; 0 ]) "Lazy 1")
    "cached lazy row should patch when state changes"
;;

let test_lazy_list_state_key_refreshes_cached_row () =
  Backend.reset ();
  let app =
    App.create (fun graph ->
      let collapsed, set_collapsed = Apple.state graph ~key:"collapsed" false in
      Apple.vstack
        [
          Apple.lazy_list ~length:1 ~key:(fun _ -> "stable-row")
            ~state_key:(fun _ ->
              Printf.sprintf "stable-row:collapsed=%b" collapsed)
            ~row:(fun _ ->
              Apple.text (if collapsed then "Collapsed" else "Expanded"))
            ();
          Apple.button "Toggle" ~on_click:(set_collapsed (not collapsed));
        ])
  in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  require
    (String.equal (Backend.find_text_exn root ~path:[ 0; 0 ]) "Expanded")
    "initial lazy row should render the open state";
  Backend.click_exn root ~path:[ 1 ];
  require
    (String.equal (Backend.find_text_exn root ~path:[ 0; 0 ]) "Collapsed")
    "cached lazy row should refresh when its state_key changes"
;;

let test_lazy_list_reorder_reuses_mounted_rows_by_key () =
  Backend.reset ();
  let rows = List.init 64 (fun index -> Printf.sprintf "row-%03d" index) in
  let moved_rows = List.nth rows 63 :: List.filteri (fun index _ -> index <> 63) rows in
  let app =
    App.create (fun graph ->
      let rows, set_rows = Apple.state graph ~key:"rows" rows in
      let row_at index =
        if index >= 0 && index < List.length rows then List.nth rows index else "missing"
      in
      Apple.vstack
        [
          Apple.lazy_list ~length:(List.length rows)
            ~key:(fun index -> row_at index)
            ~row:(fun index -> Apple.text (row_at index))
            ();
          Apple.button "Move" ~on_click:(set_rows moved_rows);
        ])
  in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  require
    (String.equal (Backend.find_text_exn root ~path:[ 0; 0 ]) "row-000")
    "initial first lazy row should render";
  let before = Backend.stats () in
  Backend.click_exn root ~path:[ 1 ];
  let after = Backend.stats () in
  let diff = Backend.diff_stats before after in
  require
    (String.equal (Backend.find_text_exn root ~path:[ 0; 0 ]) "row-063")
    "reordered first lazy row should render";
  require
    (diff.destroyed = 0)
    (Printf.sprintf
       "reordering lazy rows should move cached rows by key instead of destroying them; \
        destroyed=%d"
       diff.destroyed);
  require
    (diff.created = 0)
    (Printf.sprintf
       "reordering lazy rows should reuse mounted rows instead of remounting them; \
        created=%d"
       diff.created)
;;

let test_lazy_list_renderer_uses_indexed_keys () =
  let source = read_file apple_source_path in
  require
    (not (contains source ~substring:"duplicate Apple lazy_list key"))
    "lazy list construction should not eagerly scan every key; keys are validated only for \
     materialized rows";
  require
    (contains source ~substring:"let identity_keys = List.init length")
    "lazy list updates should publish a complete stable identity snapshot so SwiftUI \
     ForEach does not fall back to mutable row indices during diffing";
  require
    (contains source ~substring:"let build_lazy_row_index_by_key")
    "lazy list renderer should build one key-to-index map for cached rows instead of \
     scanning the full cache for each moved row";
  require
    (contains
       source
       ~substring:"find_lazy_row_by_key lazy_row_index_by_key t")
    "lazy list stale scans should reuse the indexed key lookup when distinguishing moved \
     rows from rows whose content or focus changed";
  require
    (not (contains source ~substring:"let find_lazy_row_by_key t ~target_index"))
    "lazy row key lookup should not repeatedly fold over the whole cache on the move hot \
     path";
  require
    (not
       (contains source
          ~substring:
            "if String.equal cached_key row_key\n                      then stale_indices\n                      else index :: stale_indices"))
    "lazy list stale scans should not destroy moved rows just because their index key \
     changed";
  require
    (contains source ~substring:"Hashtbl.remove t.lazy_rows cached_index")
    "lazy list renderer should move a cached row from its old index to its new index \
     instead of rebuilding it";
  require
    (contains
       source
       ~substring:"Hashtbl.replace t.lazy_rows cached_index")
    "lazy list renderer should keep the displaced row cached so adjacent moved rows are \
     reused instead of remounted";
  require
    (contains source ~substring:"~key:displaced.identity_key")
    "lazy list renderer should preserve the displaced row record and update the indexed \
     key lookup when rekeying moved rows";
  require
    (not (contains source ~substring:"if index >= length then None"))
    "lazy list focus handling should not scan every row key to find a focused row"
;;

let test_lazy_list_marks_moved_target_indices_order_changed () =
  let source = read_file apple_source_path in
  require
    (contains source ~substring:"let stale_indices, order_changed =")
    "lazy list stale scans should distinguish row order changes from content/state \
     invalidation";
  require
    (contains source
       ~substring:
         "| Some (_, moved) when String.equal moved.state_key row_state_key ->")
    "lazy list stale scans should treat a cached row moving to a new index as an order \
     change, not a stale row";
  require
    (contains source
       ~substring:
         "| Some (_, moved) when String.equal moved.state_key row_state_key ->\n\
        \                          stale_indices, true")
    "lazy list key moves with unchanged row state should only publish an order change \
     because SwiftUI can move stable row identities without refreshing every shifted row";
  require
    (contains source
       ~substring:
         "if order_changed || not (List.is_empty stale_indices) then")
    "lazy list order changes should still bump the native version so SwiftUI can clear \
     the local move preview"
;;

let test_lazy_list_focus_cache_renders_only_focused_row () =
  let source = read_file apple_source_path in
  require
    (contains source ~substring:"let lazy_list_focused_cache_radius = 0")
    "lazy list focus updates should pre-render only the focused row; rendering a radius \
     of neighbors makes Enter/Delete cost scale with retained visible rows instead of \
     the actual focus handoff"
;;

let test_swiftui_lazy_list_uses_native_row_provider () =
  let source = read_file swiftui_source_path in
  let backend_source = read_file swiftui_backend_source_path in
  let stubs_source = read_file swiftui_stubs_source_path in
  require
    (contains source ~substring:"lazyListProviderId")
    "SwiftUI backend should store a native lazy list provider id";
  require
    (contains source ~substring:"lazyListRowCount")
    "SwiftUI backend should store only the lazy list row count";
  require
    (not (contains source ~substring:"lazyListRowKeys"))
    "SwiftUI backend should not store every lazy row key because that scales with the \
     entire list";
  require
    (contains backend_source ~substring:"~cached_rows")
    "OCaml lazy-list updates should publish already rendered cached rows with the \
     structural row-count snapshot";
  require
    (contains stubs_source ~substring:"cached_row_pointers")
    "the C bridge should pass cached row node pointers to Swift instead of asking row \
     bodies to render them";
  require
    (not (contains source ~substring:"lazy_row_refresh_missing_callback"))
    "SwiftUI lazy list refreshes must read the cache published by OCaml updates instead \
     of rendering rows again from refresh callbacks";
  require
    (contains source ~substring:"releaseCachedRow(index: candidate")
    "SwiftUI lazy lists should release cached OCaml rows from retained-cache trimming, \
     not from every row disappear"
;;

let test_swiftui_lazy_list_defers_missing_visible_row_render () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"BonsaiNativeLazyListRowView(")
    "SwiftUI lazy lists should use a row wrapper so ForEach can stay lightweight";
  require
    (contains source ~substring:"private func renderRowIfNeeded()")
    "SwiftUI lazy list rows may render missing rows after appear, but not during body or \
     refresh";
  require
    (contains source ~substring:"if let child = displayedChild")
    "SwiftUI lazy list row bodies should only read existing row state/cache through the \
     displayed-child helper";
  require
    (contains source ~substring:"Color.clear\n          .frame(height: 44)")
    "SwiftUI lazy list rows should use a stable placeholder when a row was not included \
     in the latest published snapshot window";
  require
    (contains source ~substring:"DispatchQueue.main.async")
    "SwiftUI lazy list row cache reads should be deferred out of the body pass"
;;

let test_swiftui_lazy_list_uses_native_list_for_row_actions () =
  let source = read_file swiftui_source_path in
  require
    (not (contains source ~substring:"lazyScrollList(providerId: providerId, proxy: proxy)"))
    "lazy provider lists should not bypass native List, because ScrollView/LazyVStack \
     does not support native swipe delete or long-press row moves";
  require
    (not (contains source ~substring:"private func lazyScrollList"))
    "lazy provider lists should use the native List path with onDelete/onMove";
  require
    (contains source ~substring:"private func nativeList(_ proxy: ScrollViewProxy) -> some View")
    "lazy provider lists should retain the native List path";
  require
    (contains source ~substring:".onDelete { offsets in")
    "lazy provider native List rows should expose native swipe delete";
  require
    (contains source ~substring:".onMove { source, destination in")
    "lazy provider native List rows should expose native row move"
;;

let test_swiftui_lazy_list_rows_hide_native_separators_at_container () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:".equatable()\n    .listRowSeparator(.hidden)")
    "lazy list rows should hide native List separators on the row container so app rows \
     do not need per-row separator modifiers"
;;

let test_swiftui_native_list_disables_implicit_row_count_animation () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:".transaction { transaction in\n      transaction.animation = nil\n    }")
    "lazy provider native List should disable implicit row-count animations so append-only \
     load-more updates do not hitch active scrolling"
;;

let test_swiftui_lazy_list_move_updates_visible_order_immediately () =
  let source = read_file swiftui_source_path in
  require
    (not (contains source ~substring:"private struct BonsaiNativeLazyListMovePreview"))
    "lazy provider row moves should not keep a local SwiftUI preview because writing \
     view state from native List move callbacks can publish during view updates";
  require
    (not (contains source ~substring:"@State private var lazyListMovePreview"))
    "lazy provider row moves should not update local @State during List drag/drop";
  require
    (contains source ~substring:"ForEach(lazyListPositions())")
    "lazy provider List rows should use stable native-cached row identity so native \
     delete/reorder transactions do not reuse index-keyed cells after persisted order \
     changes";
  require
    (not
       (contains source
          ~substring:"ForEach(lazyListMoveSlots(providerId: providerId), id: \\.id)"))
    "drag preview rows should not switch ForEach identity because SwiftUI can hitch while \
     diffing key-backed slots";
  require
    (contains source ~substring:"let sourceIndex = position")
    "range-based rows should keep stable position mapping until the persisted OCaml model \
     publishes the new order";
  require
    (not (contains source ~substring:"lazyListMovePreview ="))
    "native onMove should not update local order before persistence succeeds";
  require
    (contains source ~substring:"private func commitLazyListMove(fromIndex: Int, toOffset: Int)")
    "lazy provider row moves should commit to OCaml through one focused helper";
  require
    (not
       (contains
          source
          ~substring:
            "DispatchQueue.main.async { [model] in\n\
            \      BonsaiNativeRenderedFrameScheduler.shared.runAfterRenderedFrame { [model] in"))
    "lazy provider row moves should not wait for a rendered-frame scheduler before \
     sending the OCaml move because that delays persist and visible order updates";
  require
    (contains source ~substring:"model.sendChange(eventId, text: text, deferOnMain: false)")
    "lazy provider row moves should update the data source before the native onMove \
     callback returns";
  require
    (contains source ~substring:"lazy_move_commit_scheduled")
    "lazy provider row moves should log the scheduled commit separately from the emit";
  require
    (contains source ~substring:"lazy_move_commit_emit")
    "lazy provider row moves should still log when the OCaml move is emitted";
  require
    (not (contains source ~substring:"await Task.yield()"))
    "lazy provider row moves should not rely on async executor yields";
  require
    (not (contains source ~substring:"Array(0..<node.lazyListRowCount)"))
    "lazy move preview must not allocate an array for every row in large journals"
;;

let test_swiftui_lazy_list_delete_leaves_native_delete_transaction () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"private func emitListChangeWithoutAnimation")
    "native list delete/move commits should share a no-animation emitter";
  require
    (contains source ~substring:"model.sendChange(eventId, text: text, deferOnMain: false)")
    "native list commits should synchronously mutate the OCaml model inside the List \
     callback so SwiftUI's native delete/reorder transaction sees the updated data source";
  require
    (contains source ~substring:"var transaction = Transaction()")
    "native list commits should create an explicit transaction";
  require
    (contains source ~substring:"transaction.animation = nil")
    "native list commits should disable implicit row animations around OCaml event \
     emission";
  require
    (contains source ~substring:"name: \"lazy_delete\"")
    "lazy list delete should use the no-animation emitter";
  require
    (contains source ~substring:"_event_emit_begin")
    "native list commits should log when event emission begins";
  require
    (contains source ~substring:"_event_emit_end")
    "native list commits should log when event emission ends";
  require
    (contains source ~substring:"if Thread.isMainThread {\n      emit()")
    "native list commits should emit immediately when SwiftUI calls onDelete/onMove on \
     the main thread"
;;

let test_swiftui_list_debug_perf_log_uses_swift_safe_interpolation () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"private func debugDouble(_ value: Double, digits: Int)")
    "debug list perf logs should format doubles with a narrow helper";
  require
    (not
       (contains
          source
          ~substring:
            "String(\n        format:\n          \"list_perf seconds=%.2f list=%@"))
    "debug list perf logs should not use one large String(format:) call with Swift Int \
     values because iOS 26 reports format-specifier mismatches"
;;

let test_swiftui_frame_probe_can_run_without_list_debug_bookkeeping () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"BONSAI_NATIVE_FRAME_DEBUG")
    "frame gap logging should have a frame-only mode so profiling can avoid per-row \
     list debug bookkeeping on the scroll hot path";
  require
    (contains source
       ~substring:
         "ProcessInfo.processInfo.environment[\"BONSAI_NATIVE_FRAME_DEBUG\"] == \"1\"")
    "frame-only mode should be enabled independently from BONSAI_NATIVE_LIST_DEBUG";
  require
    (contains source
       ~substring:
         "ProcessInfo.processInfo.environment[\"BONSAI_NATIVE_LIST_DEBUG\"] == \"1\"")
    "per-row list virtualization logs should remain separately gated"
;;

let test_swiftui_frame_probe_logs_slow_lazy_row_renders () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"func markLazyRowRender")
    "frame-only profiling should be able to attribute frame gaps to slow lazy row renders";
  require
    (contains source ~substring:"lazy_row_render_slow")
    "slow lazy row render logs should have a stable event name for scroll-phase diagnosis";
  require
    (contains source ~substring:"guard isEnabled && elapsedMs >= 4 else { return }")
    "slow lazy row render logging should be thresholded so frame-only profiling does not \
     log every row on the scroll hot path";
  require
    (contains source
       ~substring:"BonsaiNativeFrameProbe.shared.markLazyRowRender")
    "lazy row rendering should report slow rows to the frame probe without requiring full \
     list debug bookkeeping"
;;

let test_swiftui_frame_probe_reports_scroll_phase_row_lifecycle_counts () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"lazy_body=%d lazy_appear=%d lazy_disappear=%d")
    "frame-only reports should include lazy row lifecycle counts for scroll-phase \
     attribution";
  require
    (contains source ~substring:"media_create=%d media_destroy=%d")
    "frame-only reports should include media view lifecycle counts";
  require
    (contains source ~substring:"func markLazyRowBody")
    "lazy row body evaluations should be counted without enabling full list debug";
  require
    (contains source ~substring:"func markMediaViewCreated")
    "media view creation should be counted without enabling full list debug"
;;

let test_swiftui_host_model_is_only_observed_by_root_view () =
  let source = read_file swiftui_source_path in
  require
    (count_substrings source ~substring:"@ObservedObject var model: BonsaiNativeHostModel" = 1)
    "only the root SwiftUI view should observe BonsaiNativeHostModel; child rows use it as \
     an event dispatcher, otherwise every root update invalidates visible rows"
;;

let test_swiftui_lazy_list_row_is_equatable () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"BonsaiNativeLazyListRowView: View, Equatable")
    "lazy list rows should be Equatable so root updates do not recompute unchanged visible \
     row bodies";
  require
    (contains source ~substring:"static func ==")
    "lazy list row equality should compare stable row identity inputs";
  require
    (contains source ~substring:".equatable()")
    "lazy list rows should opt into SwiftUI EquatableView body skipping"
;;

let test_swiftui_lazy_list_visible_index_tracking_stays_off_scroll_hot_path () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"trackVisibleIndexAppear()")
    "lazy row appear should delegate visible-index tracking to a guarded helper";
  require
    (contains source ~substring:"trackVisibleIndexDisappear()")
    "lazy row disappear should delegate visible-index tracking to a guarded helper";
  require
    (contains source ~substring:"var visibleIndex: Int?")
    "visible-index bookkeeping should remember the row-local index currently registered \
     as visible";
  require
    (contains source ~substring:"var visibleKey: String?")
    "visible-index bookkeeping should also remember the stable row key so moved rows can \
     unregister their old mutable index";
  require
    (contains source ~substring:"owner.lazyListVisibleIndexCounts[visibleIndex] = nextCount")
    "visible-index bookkeeping should keep positions visible until the last overlapping \
     row view for that registered index disappears";
  require
    (contains source ~substring:".onChange(of: index)")
    "visible-index bookkeeping should move the visible registration when a stable row key \
     shifts to a different index";
  require
    (not
       (contains source
          ~substring:
            "if BonsaiNativeListVirtualizationProbe.shared.isDebugEnabled {\n\
            \      owner.lazyListVisibleIndices.insert(index)"))
    "visible-index bookkeeping must not be debug-only because stable row identity depends \
     on it during normal swipe and drag operations"
;;

let test_swiftui_lazy_list_keeps_slots_off_scroll_hot_path () =
  let source = read_file swiftui_source_path in
  require
    (not (contains source ~substring:"private struct BonsaiNativeLazyListMoveSlotCollection"))
    "lazy list should not use a key-backed slot collection for move preview because \
     SwiftUI repeatedly walks collection ids";
  require
    (not (contains source ~substring:"@State private var lazyListMoveSlots"))
    "lazy list should not keep a persistent slot array because SwiftUI repeatedly walks \
     collection ids";
  require
    (not (contains source ~substring:"lazyListMovePreview"))
    "lazy list should not keep a local move preview because native List can call move \
     callbacks during SwiftUI view updates"
;;

let test_swiftui_lazy_list_foreach_resolves_keys_only_for_visible_rows () =
  let source = read_file swiftui_source_path in
  let backend_source = read_file swiftui_backend_source_path in
  let stubs_source = read_file swiftui_stubs_source_path in
  require
    (contains source ~substring:"private struct BonsaiNativeLazyListPositions")
    "lazy lists should feed ForEach a lightweight random-access collection instead of \
     allocating a full row-position array";
  require
    (contains source ~substring:"ForEach(lazyListPositions())")
    "lazy lists should use native cached row identity instead of mutable index identity";
  require
    (not (contains source ~substring:"ForEach(slots)"))
    "lazy lists should not feed a key-backed slot collection to ForEach because SwiftUI \
     repeatedly walks all ids";
  require
    (not (contains source ~substring:"ForEach(lazyListMoveSlots"))
    "lazy lists should not feed a computed key-backed slot collection to ForEach during \
     drag preview";
  require
    (contains source
       ~substring:"id: bonsaiNativePublishedLazyRowKey(owner: owner, index: position)")
    "lazy row positions should read stable row keys from the published snapshot";
  require
    (not (contains source ~substring:"bonsaiNativeLazyRowIdentity"))
    "lazy row positions must not synchronously call OCaml while SwiftUI is diffing native \
     List rows";
  require
    (not (contains source ~substring:"return \"lazy-row-\\(index)\""))
    "SwiftUI ForEach identity must not fall back to mutable row indices";
  require
    (contains backend_source ~substring:"~identity_keys")
    "OCaml lazy-list publishes should push already cached row keys into the native \
     identity cache";
  require
    (contains stubs_source ~substring:"identity_key_values[index] = String_val")
    "the C bridge should pass native identity key updates without asking SwiftUI ForEach \
     to call OCaml";
  require
    (contains source
       ~substring:
         "targetID = AnyHashable(bonsaiNativePublishedLazyRowKey(owner: node, index: index))")
    "lazy focused-row scrolling should target the same native key hint identity as \
     ForEach, without resolving OCaml row keys during SwiftUI diffing"
;;

let test_swiftui_lazy_row_body_does_not_render_rows_synchronously () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"@State private var renderedChild")
    "lazy row view should hold rendered row nodes in row-local state";
  require
    (contains source ~substring:"if let child = displayedChild")
    "lazy row body may read existing state/cache through the displayed-child helper";
  require
    (not (contains source ~substring:"let renderedChild = cachedRenderedChild ?? renderRowIfNeeded()"))
    "lazy row body must not synchronously call OCaml row render while SwiftUI is \
     evaluating body";
  require
    (contains source ~substring:"private func refreshRow()")
    "lazy row views should refresh from cache when OCaml publishes changed rows";
  require
    (contains source ~substring:"loadRowIfNeeded()")
    "visible lazy rows may still request missing rows after appear"
;;

let test_swiftui_lazy_list_disappear_does_not_enqueue_release_work () =
  let source = read_file swiftui_source_path in
  require
    (not (contains source ~substring:"scheduleRelease()"))
    "lazy row disappear should not enqueue deferred release closures on the scroll hot \
     path; retained cache trimming owns provider release";
  require
    (not (contains source ~substring:"BonsaiNativeLazyRowDetachScheduler"))
    "lazy row detach scheduler should not exist when disappear no longer detaches rows";
  require
    (not (contains source ~substring:"releaseToken"))
    "lazy row state should not carry release tokens when disappear does not detach rows"
;;

let test_ios_bootstrap_prefers_checkout_sources_for_local_packages () =
  let source = read_file bootstrap_ios_script_path in
  require
    (contains source ~substring:"$repo_root/$package.opam")
    "iOS bootstrap should detect packages that live in the current checkout";
  require
    (contains source ~substring:"printf '%s\\n' \"$repo_root\"")
    "iOS bootstrap should build local packages from the current checkout so Swift assets \
     installed into ios-sysroot cannot lag behind source edits";
  require
    (contains source ~substring:"find \"$sources_dir\"")
    "iOS bootstrap should still fall back to opam switch sources for external packages"
;;

let test_swiftui_lazy_list_refreshes_visible_rows_after_provider_update () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"lazyListVersion")
    "SwiftUI lazy lists should publish a version each time OCaml updates the row provider";
  require
    (contains source ~substring:"lazyListInvalidatedIndices")
    "SwiftUI lazy lists should receive the exact stale row indices from the OCaml provider";
  require
    (contains source ~substring:"invalidatedIndexPointer")
    "the OCaml-to-Swift bridge should pass stale indices with lazy list row updates";
  require
    (contains source ~substring:"node.lazyListInvalidatedIndices.contains(sourceIndex)")
    "lazy row positions should mark only invalidated source indices for refresh";
  require
    (not (contains source ~substring:"version: node.lazyListVersion"))
    "SwiftUI lazy rows should not receive the global provider version because append-only \
     pagination should not re-evaluate every retained row body";
  require
    (not (contains source ~substring:"totalRows: node.lazyListRowCount"))
    "SwiftUI lazy rows should not receive the global row count because append-only \
     pagination should not re-evaluate every retained row body";
  require
    (not (contains source ~substring:".onChange(of: version)"))
    "SwiftUI lazy rows should not observe the global provider version; invalidated rows \
     should refresh through their own appear/load path";
  require
    (contains source
       ~substring:
         "refreshGeneration: node.lazyListInvalidatedIndices.contains(sourceIndex)")
    "SwiftUI lazy rows should receive a per-row refresh generation so only invalidated \
     rows refresh after provider updates";
  require
    (contains source
       ~substring:
         "key: position.id")
    "SwiftUI lazy row cache identity should use the stable key carried by the published \
     position snapshot";
  require
    (contains source ~substring:"var lazyListIdentityKeysByIndex: [String] = []")
    "SwiftUI lazy list positions should read row keys from an indexed snapshot instead \
     of dictionary lookups during List diffing";
  require
    (not (contains source ~substring:"key: \"\\(node.lazyListVersion):\\(index)\""))
    "global provider version should not be part of every row key because append-only \
     pagination should not invalidate all visible row caches";
  require
    (contains source ~substring:"let owner: BonsaiNativeNode")
    "SwiftUI lazy row wrappers should not observe the whole list owner";
  require
    (not (contains source ~substring:"@ObservedObject var owner: BonsaiNativeNode"))
    "list-level lazy list publishes should not invalidate every retained row wrapper";
  require
    (not (contains source ~substring:"@State private var child: BonsaiNativeNode?"))
    "SwiftUI lazy row wrappers should not store rendered child nodes in row-local state \
     because List cells are reused while scrolling";
  require
    (not (contains source ~substring:"@State private var isVisible"))
    "lazy row visibility should not be SwiftUI state because every List appear/disappear \
     would re-evaluate row bodies while scrolling";
  require
    (not (contains source ~substring:"@State private var releaseToken"))
    "lazy row release tokens should not be SwiftUI state because release scheduling is \
     not visual state";
  require
    (not (contains source ~substring:"@State private var focusedDisappearToken"))
    "focused-row disappear tokens should not be SwiftUI state because scroll lifecycle \
     bookkeeping should not invalidate row bodies";
  require
    (contains source ~substring:"private final class BonsaiNativeLazyListRowState")
    "non-visual lazy row lifecycle bookkeeping should live in a reference state holder";
  require
    (contains source ~substring:"private var cachedRenderedChild: BonsaiNativeNode?")
    "SwiftUI lazy row wrappers should read rendered child nodes from the owner row cache";
  require
    (contains source ~substring:"private var displayedChild: BonsaiNativeNode?")
    "SwiftUI lazy row wrappers should derive the displayed child through a helper that can \
     reject stale row-local state after native List reuses a cell";
  require
    (contains source ~substring:"guard renderedChildKey == key else { return cachedRenderedChild }")
    "row-local rendered children must be tied to the current stable row key so a focused \
     editor cannot leak into the reused add-block placeholder row";
  require
    (contains source ~substring:"@State private var renderedChildRefreshGeneration")
    "row-local rendered children must also be tied to the row state generation so the \
     previous focused editor cannot keep displaying after focus moves to another block";
  require
    (contains source ~substring:"renderedChildRefreshGeneration == refreshGeneration")
    "displayedChild should reject a row-local child rendered for an older focused/unfocused \
     state";
  require
    (contains source ~substring:"renderedChildRefreshGeneration = refreshGeneration")
    "loading or refreshing a lazy row should record the generation used for its displayed \
     child";
  require
    (contains source ~substring:".onChange(of: refreshGeneration)")
    "SwiftUI lazy rows should refresh when OCaml invalidates their own source index, even \
     if the row key is unchanged";
  require
    (contains source ~substring:"scheduleRefreshRow()")
    "invalidated visible rows should defer their row-provider refresh to the next main turn \
     so SwiftUI does not synchronously re-enter OCaml while publishing list rows";
  require
    (not (contains source ~substring:"if generation != 0 {\n        refreshRow()"))
    "provider invalidation should not call the OCaml row renderer directly from SwiftUI's \
     synchronous onChange/update dispatch path";
  require
    (contains source ~substring:"private func refreshRow()")
    "SwiftUI lazy rows should call the OCaml row provider again for visible cached rows";
  require
    (contains source ~substring:"let nextVersion = Int(version)")
    "SwiftUI lazy list provider updates should use the OCaml renderer's version instead \
     of bumping on every append";
  require
    (contains source
       ~substring:"if node.lazyListVersion != nextVersion")
    "SwiftUI lazy list provider updates should publish the OCaml renderer's version for \
     order-only changes as well as stale-row refreshes";
  require
    (not (contains source ~substring:"node.lazyListIdentityKeyByIndex.removeAll(keepingCapacity: true)"))
    "lazy list provider updates should not clear every native index-key cache entry \
     because SwiftUI may synchronously ask OCaml for visible row keys while an OCaml \
     action is still rendering";
  require
    (contains source ~substring:"var nextIdentityKeyByIndex = node.lazyListIdentityKeyByIndex")
    "lazy list provider updates should build the next identity map before exposing it to \
     SwiftUI";
  require
    (not (contains source ~substring:"nextIdentityKeyByIndex = [:]"))
    "a strict identity snapshot publish should not delete old out-of-range keys before \
     SwiftUI has diffed row removals";
  require
    (contains source
       ~substring:
         "nextIdentityKeyByIndex[index] = key")
    "lazy list provider updates should repopulate native row identity keys from the \
     OCaml publish payload before SwiftUI diffs rows";
  require
    (contains source ~substring:"nextIdentityKeysByIndex[index] = key")
    "lazy list provider updates should also populate the indexed row-key snapshot used \
     by ForEach";
  require
    (contains source ~substring:"node.lazyListIdentityKeyByIndex = nextIdentityKeyByIndex")
    "SwiftUI should see the next strict identity snapshot with a single dictionary \
     assignment";
  require
    (contains source
       ~substring:
         "nextIdentityKeyByIndex.reserveCapacity(max(nextIdentityKeyByIndex.count, Int(identityKeyCount)))")
    "lazy list provider updates should overlay the complete valid snapshot while keeping \
     old keys that SwiftUI may still need for removal diffs";
  require
    (contains source ~substring:"node.lazyListVisibleIndices.subtract(outOfRangeIndices)")
    "lazy list provider updates should keep invalidated visible row positions visible so \
     SwiftUI can resolve stable row keys during native delete/reorder diffs";
  require
    (not (contains source ~substring:"node.lazyListVisibleIndices.subtract(staleIndices)"))
    "invalidated rows should not be removed from visible-index tracking because that \
     makes native List fall back to index identity for the changed viewport";
  require
    (not (contains source ~substring:"node.lazyListVersion &+= 1"))
    "SwiftUI lazy list provider updates should not refresh visible rows for pure append \
     updates"
;;

let test_swiftui_lazy_list_content_cache_uses_stable_row_key () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"var lazyListRowsByKey: [String: BonsaiNativeNode] = [:]")
    "lazy row content cache should be indexed by stable row key as well as mutable row \
     index";
  require
    (contains source ~substring:"owner.lazyListRowsByKey[key]")
    "visible lazy rows should recover cached content by stable key after insert/delete \
     shifts their index";
  require
    (contains source ~substring:"owner.lazyListRowsByKey[resolvedKey] = rendered")
    "newly rendered lazy rows should populate the stable-key content cache";
  require
    (contains source ~substring:"node.lazyListRowsByKey[key] = row")
    "OCaml-published cached rows should populate the stable-key content cache";
  require
    (contains source ~substring:"removeLazyRowKeyCacheIfUnused")
    "row release should keep moved rows cached by key until the new snapshot can attach \
     them at their new index"
;;

let test_swiftui_lazy_list_structural_row_count_publishes_synchronously () =
  let source = read_file swiftui_source_path in
  require
    (not (contains source ~substring:"private func scheduleLazyListRowCountPublish"))
    "the old unguarded row-count scheduler should stay removed";
  require
    (contains source ~substring:"private func scheduleCoalescedStructuralLazyListRowCountPublish")
    "structural lazy row-count publishes should leave the strict snapshot installed and \
     coalesce SwiftUI's expensive row-count diff while the user is rapidly editing";
  require
    (contains source ~substring:"lazy_row_count_coalesced")
    "structural coalesced row-count publishes should be visible in performance logs";
  require
    (not
       (contains source ~substring:"coalescedStructuralLazyListRowCountPublishDelay"))
    "structural row-count coalescing must not use a timed debounce because that is \
     visible as slow Enter/Delete";
  require
    (contains source ~substring:"DispatchQueue.main.async(execute: workItem)")
    "structural row-count coalescing should only merge updates already queued for the \
     next main-loop turn";
  require
    (contains source ~substring:"!providerInvalidatedIndices.isEmpty")
    "only structural invalidation updates should use the coalesced row-count publish \
     path";
  require
    (contains source ~substring:"scheduleDeferredLazyListRowCountPublish(node, rowCount)")
    "pure large append/load-more updates should keep the scroll-idle deferral path"
;;

let test_swiftui_lazy_list_defers_append_row_count_while_scrolling () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"weak var lazyListScrollView: UIScrollView?")
    "lazy lists should keep a weak reference to their backing UIScrollView so append-only \
     row-count publishes can avoid the scroll hot path";
  require
    (contains source ~substring:"private let minDeferredLazyListAppendRowCount")
    "lazy lists should distinguish load-more sized appends from single-row outliner \
     edits";
  require
    (contains source ~substring:"private func shouldDeferLazyListRowCountPublish")
    "lazy list row-count updates should have an explicit guard for scroll-time deferral";
  require
    (contains source ~substring:"let appendDelta = rowCount - node.lazyListRowCount")
    "append deferral should be based on the actual row-count increase";
  require
    (contains source ~substring:"let isLargeAppend = appendDelta >= minDeferredLazyListAppendRowCount")
    "load-more appends should still be deferrable when the old add/load-more footer rows \
     are stale";
  require
    (contains source ~substring:"guard isLargeAppend else { return false }")
    "small structural appends from Add/Enter must publish immediately; only load-more \
     sized appends may wait for scroll idle";
  require
    (not (contains source ~substring:"guard isLargeAppend || providerInvalidatedIndices.isEmpty"))
    "pure one-row appends must not be deferred just because the backing UIScrollView is \
     still tracking a tap or keyboard interaction";
  require
    (contains source ~substring:"scrollView.isDragging || scrollView.isDecelerating || scrollView.isTracking")
    "pure append row-count publishes should be delayed while the backing UIScrollView is \
     actively scrolling";
  require
    (contains source
       ~substring:"if includeMountedLargeAppend && isLargeAppend && node.lazyListScrollView != nil")
    "load-more sized appends on an already mounted native List should defer row-count \
     publication until scroll idle";
  require
    (contains source
       ~substring:"BonsaiNativeScrollStressProbe.shared.isRunning(listID: node.id)")
    "scroll stress should exercise the same append row-count deferral path as manual \
     scrolling";
  require
    (contains source ~substring:"scheduleDeferredLazyListRowCountPublish")
    "deferred append row-count publishes should be scheduled for scroll idle rather than \
     dropped";
  require
    (contains source ~substring:"publishLazyListRowCount(")
    "non-deferred row-count updates should publish synchronously for delete, collapse, \
     move, and focus-related UI refreshes";
  require
    (contains source ~substring:"invalidatedCount: providerInvalidatedIndices.count")
    "non-deferred scheduled row-count updates should preserve invalidated-row refresh \
     metadata"
;;

let test_swiftui_lazy_list_publishes_deferred_appends_once_after_idle () =
  let source = read_file swiftui_source_path in
  require
    (not (contains source ~substring:"private let maxLazyListRowCountPublishStep"))
    "deferred append row-count publishes should not drip-feed tiny chunks because each \
     native List row-count write recalculates layout and causes frame gaps";
  require
    (not (contains source ~substring:"private func nextLazyListRowCountPublish"))
    "deferred append row-count publishes should not compute row-count steps";
  require
    (not (contains source ~substring:"private func publishLazyListRowCountStep"))
    "deferred append row-count publishes should not loop through step helpers";
  require
    (not (contains source ~substring:"private func scheduleNextLazyListRowCountChunk"))
    "deferred append row-count publishes should not schedule later chunks across rendered \
     frames";
  require
    (not (contains source ~substring:"private let lazyListRowCountChunkDelay"))
    "deferred append row-count publishes should not keep a chunk delay knob";
  require
    (contains source ~substring:"BonsaiNativeScrollIdleScheduler.shared.runWhenIdle")
    "deferred append row-count publishes should still wait for scroll idle";
  require
    (contains source ~substring:"publishDeferredLazyListRowCountIfReady")
    "deferred append row-count publishes should use one focused idle callback";
  require
    (contains source ~substring:"includeMountedLargeAppend: false")
    "the deferred-ready check should not treat the mounted large append itself as a \
     reason to reschedule forever";
  require
    (contains source ~substring:"applyLazyListRowCount(node, pendingRowCount, invalidatedCount: 0)")
    "the idle callback should publish the latest pending row count once so List only \
     recalculates its content size once per loaded journal";
  require
    (contains source ~substring:"lazy_row_count_deferred_publish")
    "deferred publish decisions should be logged for stress verification";
  require
    (not (contains source ~substring:"lazy_row_count_chunk_scheduled"))
    "stress logs should not contain chunk-specific row-count publishes"
;;

let test_swiftui_lazy_list_row_count_publish_disables_implicit_animation_at_write () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"var transaction = Transaction()")
    "lazy list row-count publishes should create an explicit transaction at the write \
     site";
  require
    (contains source ~substring:"transaction.animation = nil")
    "lazy list row-count publishes should disable implicit insertion animations at the \
     write site, not only on the outer List view";
  require
    (contains source ~substring:"withTransaction(transaction) {\n    node.lazyListRowCount = rowCount\n  }")
    "the row-count @Published write should happen inside the no-animation transaction"
;;

let test_swiftui_lazy_list_deferred_append_has_max_latency () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"maxDeferredLazyListRowCountPublishDelay")
    "deferred load-more row-count publishes should have a short maximum latency so \
     loaded rows do not wait seconds for scroll idle";
  require
    (contains source ~substring:"pendingLazyListRowCountDeadline")
    "lazy list nodes should remember the deadline for the current deferred row-count \
     publish";
  require
    (contains source
       ~substring:
         "DispatchQueue.main.asyncAfter(deadline: .now() + maxDeferredLazyListRowCountPublishDelay")
    "deferred row-count publish should schedule an independent max-latency timer instead \
     of only checking the deadline from the scroll-idle callback";
  require
    (contains source ~substring:"let exceededMaxDelay")
    "deferred row-count publish should compute whether the maximum delay has elapsed";
  require
    (contains source ~substring:"&& !exceededMaxDelay")
    "the idle deferral check should stop rescheduling once the maximum latency is reached"
;;

let test_swiftui_lazy_list_logs_row_count_publish_decisions () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"lazy_row_count_update")
    "lazy list row-count updates should log old/new counts so scroll hitches can be \
     correlated with load-more publishes";
  require
    (contains source ~substring:"lazy_row_count_deferred")
    "deferred lazy list row-count updates should have a stable log event";
  require
    (contains source ~substring:"lazy_row_count_published")
    "published lazy list row-count updates should have a stable log event";
  require
    (contains source ~substring:"invalidatedCount: providerInvalidatedIndices.count")
    "row-count update logs should distinguish pure append updates from structural \
     invalidations"
;;

let test_swiftui_lazy_list_emits_row_count_published_event () =
  let source = read_file swiftui_source_path in
  let backend_source = read_file swiftui_backend_source_path in
  let apple_source = read_file apple_source_path in
  require
    (contains apple_source ~substring:"?on_rows_published")
    "Apple.lazy_list should expose a row-count-published callback so apps can gate stale \
     load-more callbacks until native List actually receives appended rows";
  require
    (contains backend_source ~substring:"on_rows_published")
    "SwiftUI backend should carry the lazy-list row-count-published callback to the \
     native row-count setter";
  require
    (contains source ~substring:"lazyListRowsPublishedEventId")
    "SwiftUI nodes should store the row-count-published event id";
  require
    (contains source ~substring:"weak var hostModel: BonsaiNativeHostModel?")
    "SwiftUI lazy-list nodes should hold a weak host model reference for asynchronous \
     row-count publication";
  require
    (contains source ~substring:"node.hostModel?.sendChange(eventId, text: \"\")")
    "SwiftUI should emit the row-count-published event after applying a lazy list row \
     count";
  require
    (contains source ~substring:"invalidatedCount == 0")
    "SwiftUI should emit the row-count-published event only for pure append/load-more \
     row-count publishes, not for enter/delete/move structural invalidations";
  require
    (contains source ~substring:"applyLazyListRowCount(node, pendingRowCount")
    "deferred append publication should emit the callback after the real native row-count \
     write, not when the OCaml model receives Loaded_page"
;;

let test_swiftui_exposes_scroll_idle_main_dispatch () =
  let source = read_file swiftui_source_path in
  let stubs = read_file "../swiftui/bonsai_apple_swiftui_stubs.c" in
  let ml_source = read_file swiftui_backend_source_path in
  let mli_source = read_file "../swiftui/bonsai_apple_swiftui.mli" in
  require
    (contains source ~substring:"private final class BonsaiNativeScrollIdleScheduler")
    "SwiftUI bridge should have a scroll-idle scheduler for work that would otherwise \
     update lazy lists while scrolling";
  require
    (contains source ~substring:"func register(scrollView: UIScrollView)")
    "the scheduler should track registered lazy-list UIScrollViews";
  require
    (contains source ~substring:"scrollView.isDragging || scrollView.isDecelerating || scrollView.isTracking")
    "scroll-idle dispatch should wait for real user scroll gestures and deceleration";
  require
    (contains source ~substring:"BonsaiNativeScrollStressProbe.shared.isAnyRunning()")
    "scroll stress should exercise the same idle-dispatch path as manual scrolling";
  require
    (contains source ~substring:"bonsai_native_swiftui_run_on_main_when_scroll_idle")
    "Swift should expose a C entrypoint for OCaml callbacks that must wait until scroll \
     idle";
  require
    (contains stubs ~substring:"bonsai_apple_swiftui_run_on_main_when_scroll_idle")
    "C stubs should expose the scroll-idle main dispatch helper to OCaml";
  require
    (contains ml_source ~substring:"external run_on_main_when_scroll_idle")
    "OCaml SwiftUI backend should bind the scroll-idle main dispatch helper";
  require
    (contains mli_source ~substring:"val run_on_main_when_scroll_idle")
    "OCaml SwiftUI interface should expose the scroll-idle helper explicitly"
;;

let test_swiftui_exposes_rendered_frame_main_dispatch () =
  let source = read_file swiftui_source_path in
  let stubs = read_file "../swiftui/bonsai_apple_swiftui_stubs.c" in
  let ml_source = read_file swiftui_backend_source_path in
  let mli_source = read_file "../swiftui/bonsai_apple_swiftui.mli" in
  require
    (contains source
       ~substring:"bonsai_native_swiftui_run_on_main_after_rendered_frame")
    "Swift should expose a C entrypoint for OCaml callbacks that must wait until the \
     current UI update has presented";
  require
    (contains source
       ~substring:"BonsaiNativeRenderedFrameScheduler.shared.runAfterRenderedFrame")
    "rendered-frame main dispatch should share the CADisplayLink scheduler used by native \
     list move preview commits";
  require
    (contains stubs ~substring:"bonsai_apple_swiftui_run_on_main_after_rendered_frame")
    "C stubs should expose the rendered-frame main dispatch helper to OCaml";
  require
    (contains ml_source ~substring:"external run_on_main_after_rendered_frame")
    "OCaml SwiftUI backend should bind the rendered-frame main dispatch helper";
  require
    (contains mli_source ~substring:"val run_on_main_after_rendered_frame")
    "OCaml SwiftUI interface should expose the rendered-frame helper explicitly"
;;

let test_swiftui_mac_bridge_exports_lazy_list_symbols () =
  let source = read_file swiftui_mac_source_path in
  [
    "bonsai_native_swiftui_run_on_main_when_scroll_idle";
    "bonsai_native_swiftui_run_on_main_after_rendered_frame";
    "bonsai_native_swiftui_set_lazy_list_rows";
    "bonsai_native_swiftui_clear_lazy_list_rows";
    "bonsai_native_swiftui_set_lazy_list_rows_published_event";
    "bonsai_native_swiftui_register_lazy_list_callbacks";
    "bonsai_native_swiftui_set_list_focused_row_disappear_event";
  ]
  |> List.iter (fun symbol ->
         require
           (contains source ~substring:symbol)
           ("Mac SwiftUI bridge should export " ^ symbol
            ^ " because the shared OCaml stubs reference it during default dune build"))
;;

let test_swiftui_scroll_stress_pauses_at_end_for_deferred_appends () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"func isRunning(listID: UUID) -> Bool")
    "scroll stress should expose its active state to the lazy list row-count deferral \
     guard";
  require
    (contains source ~substring:"private func stop(listID: UUID)")
    "scroll stress should be able to pause when it reaches the currently loaded end";
  require
    (contains source ~substring:"nextOffset >= maxOffset && offsetDirection > 0")
    "scroll stress should stop only when forward scrolling reaches the current content \
     end, so deferred append row counts can publish during idle";
  require
    (contains source ~substring:"scroll_stress_idle_at_end")
    "the stress log should make append-idle pauses visible in scroll diagnostics"
;;

let test_swiftui_scroll_stress_does_not_restart_for_each_row_count_chunk () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"if node.pendingLazyListRowCount != nil { return }")
    "scroll stress should not restart after every bounded row-count chunk because that \
     adds artificial frame gaps to the load-more measurement";
  require
    (contains source ~substring:"startScrollStressCurrentRows()")
    "scroll stress should still resume when a normal non-chunked list size update \
     completes"
;;

let test_swiftui_lazy_list_retained_cache_stays_small () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"owner.lazyListVisibleIndices.count")
    "SwiftUI lazy list retained cache should scale with the number of visible rows";
  require
    (contains source ~substring:"min(384, max(128, visibleBudget * 8))")
    "SwiftUI lazy lists should keep enough nearby rows for fast scrolling while \
     preserving a bounded cache for very large lists";
  require
    (not (contains source ~substring:"let maxRetainedRows = 32"))
    "SwiftUI lazy list retained cache should not be almost the same size as one visible \
     screen on iPhone"
;;

let test_swiftui_lazy_list_logs_ui_row_lifecycle_counts () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"BonsaiNativeRowLifecycleProbeView(listID: listID)")
    "lazy row lifecycle logging should use a platform view probe attached to each row";
  require
    (contains source ~substring:"bonsaiNativeLifecycleProbeBackground")
    "lifecycle probes should only be attached when list debug logging is enabled";
  require
    (not (contains source ~substring:"BonsaiNativeLazyRowLifecycleToken"))
    "lazy row lifecycle logging should not use StateObject tokens because they change row \
     retention behavior";
  require
    (not (contains source ~substring:"BonsaiNativeMediaViewLifecycleToken"))
    "media lifecycle logging should not use StateObject tokens because they change media \
     retention behavior";
  require
    (contains source ~substring:"uiRowCreated(listID:")
    "lazy row wrappers should log creation so leaked SwiftUI/UI rows can be counted";
  require
    (contains source ~substring:"uiRowDestroyed(listID:")
    "lazy row wrappers should log destruction so retained UI rows can be distinguished \
     from retained OCaml provider rows";
  require
    (contains source ~substring:"ui_row_live=")
    "list_perf logs should include currently live SwiftUI row wrappers";
  require
    (contains source ~substring:"ui_row_created=")
    "list_perf logs should include cumulative SwiftUI row wrapper creation count";
  require
    (contains source ~substring:"ui_row_destroyed=")
    "list_perf logs should include cumulative SwiftUI row wrapper destruction count";
  require
    (contains source ~substring:"media_view_live=")
    "list_perf logs should include live media view count because WebKit/image rows can \
     leak separately from text rows";
  require
    (contains source ~substring:"body=")
    "list_perf logs should include lazy row body evaluation count so SwiftUI invalidation \
     can be separated from OCaml row rendering"
;;

let test_swiftui_lazy_list_uses_stable_row_keys_for_identity () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"bonsaiNativePublishedLazyRowKey(owner: owner, index: position)")
    "lazy provider lists should read already-published row keys from the native identity \
     cache";
  require
    (contains source ~substring:"let key: String")
    "lazy provider row views should carry the stable row key";
  require
    (contains source ~substring:"let resolvedKey = bonsaiNativeLazyRowKey(")
    "lazy provider row views may resolve stable OCaml row keys only when rendering a \
     missing visible row after appear";
  require
    (contains source ~substring:"node.lazyListRowKeyByIndex[index] = key")
    "lazy-list snapshot publication should store the stable row key with cached \
     content";
  require
    (contains source ~substring:"&& lhs.key == rhs.key")
    "lazy provider row equality should include the stable row key";
  require
    (not (contains source ~substring:"key: \"\\(index)\""))
    "lazy provider row cache keys should not be derived from the mutable row index"
;;

let test_swiftui_lazy_list_keeps_old_identity_keys_until_shrink_count_publishes () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"var nextIdentityKeyByIndex = node.lazyListIdentityKeyByIndex")
    "lazy list updates should build the next identity snapshot before publishing a \
     smaller row count";
  require
    (contains source ~substring:"node.lazyListIdentityKeyByIndex = nextIdentityKeyByIndex")
    "lazy list updates should publish identity keys atomically before the new row count \
     can make SwiftUI diff positions";
  require
    (not
       (contains source
          ~substring:
            "let staleIdentityKeyIndices = Set(node.lazyListIdentityKeyByIndex.keys.filter { index in\n    index < 0 || index >= rowCount\n  }).union(providerInvalidatedIndices)"))
    "shrinking a lazy list must not remove old out-of-range identity keys before \
     SwiftUI observes the smaller row count";
  require
    (not (contains source ~substring:"pruneOutOfRangeLazyListIdentityKeys("))
    "out-of-range identity keys should be left cached because they are small and a later \
     strict snapshot publish will overwrite them when the index becomes valid again"
;;

let test_swiftui_lazy_list_disappear_defers_detach_without_releasing_cache () =
  let source = read_file swiftui_source_path in
  require
    (not (contains source ~substring:"DispatchQueue.main.asyncAfter(deadline: .now() + 0.8)"))
    "lazy row disappear should not enqueue deferred detach work during scroll";
  require
    (not (contains source ~substring:"rowState.releaseToken"))
    "lazy row disappear should not carry release tokens after cache trimming owns release";
  require
    (contains source ~substring:"releaseCachedRow(index: candidate")
    "retained cache trimming should still release rows when the cache exceeds its budget"
;;

let test_swiftui_lazy_list_blurs_focused_row_after_disappear () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"listFocusedRowDisappearEventId")
    "SwiftUI lists should store a native event for the focused row leaving the viewport";
  require
    (contains source ~substring:"scheduleFocusedRowDisappear()")
    "lazy row disappear should schedule focused-row blur independently of cache release";
  require
    (contains source ~substring:"guard owner.listFocusedRowIndex == index else { return }")
    "only the focused lazy row should trigger the disappear event";
  require
    (contains source ~substring:"model.sendClick(owner.listFocusedRowDisappearEventId)")
    "focused lazy row disappearance should notify OCaml so editing exits when the row \
     leaves the visible viewport";
  require
    (contains source ~substring:"blurFocusedRowForUserScroll")
    "user scrolling the list should also blur the focused row because SwiftUI may keep \
     offscreen rows alive"
;;

let test_swiftui_lazy_list_scroll_blur_ignores_tap_jitter () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"DragGesture(minimumDistance: 12)")
    "list-level scroll blur should require real scroll movement so normal taps still \
     focus blocks and toggle collapse";
  require
    (contains source ~substring:"guard abs(translation.height) >= 12")
    "scroll blur should ignore small vertical tap jitter before sending Blur_block";
  require
    (contains source ~substring:"guard !node.lazyListVisibleIndices.contains(focusedIndex)")
    "list-level scroll blur should not close the editor while the focused lazy row is \
     still visible because keyboard and row-height movement can look like scroll";
  require
    (not (contains source ~substring:"DragGesture(minimumDistance: 2)"))
    "a two-point drag threshold is too low and can blur immediately after a row tap"
;;

let test_swiftui_lazy_list_setters_skip_unchanged_published_values () =
  let source = read_file swiftui_source_path in
  let backend_source = read_file swiftui_backend_source_path in
  require
    (contains source ~substring:"if !node.children.isEmpty {\n    node.children = []")
    "lazy list updates should not publish an unchanged empty children array on every \
     render";
  require
    (contains source ~substring:"if node.lazyListProviderId != providerId")
    "lazy list updates should not republish the same provider id";
  require
    (contains source
       ~substring:"if node.lazyListVersion != nextVersion")
    "lazy list updates should publish order-only version changes so move preview can be \
     cleared without invalidating rows";
  require
    (not
       (contains source
          ~substring:
            "if !providerInvalidatedIndices.isEmpty && node.lazyListVersion != nextVersion"))
    "lazy list updates should not require stale indices before publishing an order-only \
     version change";
  require
    (contains
       source
       ~substring:"if node.lazyListRowCount == rowCount {")
    "lazy list updates should not republish the same row count";
  require
    (contains source ~substring:"node.pendingLazyListRowCountDeadline = nil")
    "same-count lazy list updates should clear deferred publish state";
  require
    (contains source ~substring:"if node.listRefreshEventId != nextRefreshEventId")
    "list behavior updates should not republish unchanged refresh callbacks";
  require
    (contains source ~substring:"if node.listFocusedRowIndex != nextFocusedRowIndex")
    "focused row updates should not publish when focus did not change"
  ;
  require
    (contains backend_source ~substring:"let should_publish_lazy_list_rows")
    "SwiftUI backend should update the OCaml provider table every render but skip the \
     native lazy-list publish when row count, version, and stale indices did not change";
  require
    (contains backend_source
       ~substring:"if should_publish_lazy_list_rows view ~length ~version ~stale_indices")
    "unchanged lazy-list renders should not call the native setter because that clears \
     Swift row identity caches and causes scroll hitches"
;;

let test_swiftui_navigation_setter_skips_unchanged_published_values () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"if node.navigationPath != nextPath")
    "navigation stack updates should not republish an unchanged path on every render";
  require
    (contains source ~substring:"if node.navigationPathEventId != nextEventId")
    "navigation stack updates should not republish an unchanged path callback";
  require
    (contains source ~substring:"if node.navigationDestinationIds != nextDestinationIds")
    "navigation stack updates should not republish unchanged destination ids"
;;

let test_swiftui_change_events_defer_from_view_update_callbacks () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"deferOnMain: Bool = true")
    "SwiftUI event dispatch should share one main-thread-aware path";
  require
    (contains source ~substring:"if Thread.isMainThread && !deferOnMain")
    "native List commits need an explicit immediate path, while lifecycle/change events \
     should keep the default deferred path";
  require
    (contains source ~substring:"DispatchQueue.main.async(execute: performEmit)")
    "default SwiftUI event dispatch should hop to the next main-loop turn before calling \
     OCaml from view update callbacks"
;;

let test_swiftui_structural_text_edits_handoff_keyboard_until_next_focus () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"private final class BonsaiNativeKeyboardHandoff")
    "structural text edits should keep a native first responder while OCaml waits for \
     Persisted before publishing the next focused snapshot";
  require
    (contains source ~substring:"BonsaiNativeKeyboardHandoff.shared.retainKeyboard(from: self)")
    "delete-at-start should retain the keyboard before dispatching the structural OCaml \
     event";
  require
    (contains source ~substring:"BonsaiNativeKeyboardHandoff.shared.retainKeyboard(from: textField)")
    "Return should retain the keyboard before dispatching the insert event";
  require
    (contains source ~substring:"BonsaiNativeKeyboardHandoff.shared.completeHandoff()")
    "new focused text fields should release the handoff after becoming first responder";
  require
    (not (contains source ~substring:"asyncAfter(deadline: .now() + 0.05)"))
    "delete-at-start focus should not rely on short timed retries";
  require
    (not (contains source ~substring:"asyncAfter(deadline: .now() + 0.15)"))
    "delete-at-start focus should not rely on row replacement timeout retries";
  require
    (not (contains source ~substring:"asyncAfter(deadline: .now() + 0.4)"))
    "delete-at-start focus should not rely on hidden keyboard handoff timeout";
  require
    (contains source ~substring:"func requestFocus()")
    "delete-aware text fields should keep an explicit focus request";
  require
    (contains source ~substring:"guard !wantsFocus || !isFirstResponder else { return }")
    "focused text fields should not enqueue focus retries on every render while already \
     first responder";
  require
    (contains source ~substring:"if node.isTextFieldFocused != isFocused")
    "text-field focus setters should not publish unchanged focus values";
  require
    (contains source ~substring:"isTextFieldFocused = node.isTextFieldFocused")
    "SwiftUI text fields should synchronize false as well as true focus state on appear";
  require
    (contains source ~substring:"isTextFieldFocused = isFocused")
    "SwiftUI text fields should clear stale focus when OCaml focuses the next snapshot row";
  require
    (contains source ~substring:"override func didMoveToWindow()")
    "delete-aware text fields should focus when the replacement row is mounted"
;;

let test_swiftui_delete_aware_text_change_updates_model_immediately () =
  let source = read_file swiftui_source_path in
  require
    (contains
       source
       ~substring:"model.sendChange(node.changeEventId, text: value, deferOnMain: false)")
    "delete-aware text field edits should update OCaml before SwiftUI leaves the input \
     callback so the first character after deleting a block cannot be overwritten by a \
     stale rendered row"
;;

let test_swiftui_vertical_delete_aware_text_fields_wrap () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"private final class BonsaiNativeDeleteAwareUITextView")
    "vertical delete-aware text fields should use UITextView because UITextField cannot \
     wrap text";
  require
    (contains source ~substring:"BonsaiNativeDeleteAwareTextView(")
    "vertical delete-aware text fields should render the multiline delete-aware wrapper";
  require
    (contains source ~substring:"textView.isScrollEnabled = false")
    "multiline block editors should grow and wrap instead of scrolling inside one row";
  require
    (contains source ~substring:"replacementText text: String")
    "multiline block editors should keep Return mapped to submit for structural insert";
  require
    (contains source ~substring:"if text == \"\\n\"")
    "multiline block editors should intercept Return before UIKit inserts a newline";
  require
    (contains source ~substring:"BonsaiNativeKeyboardHandoff.shared.retainKeyboard(from: textView)")
    "Return in a multiline block editor should keep the keyboard while OCaml persists \
     the inserted block"
;;

let test_swiftui_delete_aware_focus_requests_are_transition_scoped () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"var lastIsFocused = false")
    "delete-aware text fields should remember the previous rendered focus state";
  require
    (contains
       source
       ~substring:"let shouldRequestFocus = isFocused && !context.coordinator.lastIsFocused")
    "delete-aware text fields should only request focus when rendered focus changes to true";
  require
    (contains source ~substring:"context.coordinator.lastIsFocused = isFocused")
    "delete-aware text fields should update the previous rendered focus state after each render";
  require
    (not (contains source ~substring:"if isFocused {\n      textField.requestFocus()"))
    "delete-aware text fields should not re-request focus on every render while true because \
     removed SwiftUI rows can briefly render stale focused state";
  require
    (contains source ~substring:"override func resignFirstResponder() -> Bool")
    "delete-aware text fields should observe first-responder loss";
  require
    (contains source ~substring:"wantsFocus = false")
    "delete-aware text fields should clear pending focus when UIKit moves first responder away"
  ;
  require
    (contains source ~substring:"func clearFocusRequest()")
    "delete-aware text fields should expose one shared path for clearing rendered focus";
  require
    (contains source ~substring:"if isFirstResponder {\n      _ = resignFirstResponder()\n    }")
    "when OCaml publishes a snapshot where a delete-aware editor is no longer focused, \
     UIKit must resign the old first responder so keyboard input cannot keep targeting a \
     reused list row"
;;

let counter graph =
  let count, set_count = Apple.state graph ~key:"count" 0 in
  Apple.vstack
    [ Apple.text (string_of_int count)
    ; Apple.button "Increment" ~on_click:(set_count (count + 1))
    ]
;;

let test_event_rerenders_component_state () =
  Backend.reset ();
  let app = App.create counter in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  require (Backend.find_text_exn root ~path:[ 0 ] = "0") "initial count should be 0";
  Backend.click_exn root ~path:[ 1 ];
  require (Backend.find_text_exn root ~path:[ 0 ] = "1") "click should rerender count"
;;

let test_scoped_state_is_independent () =
  let scoped key graph =
    Apple.scope graph ~key (fun graph ->
      let count, set_count = Apple.state graph ~key:"count" 0 in
      Apple.button (key ^ ":" ^ string_of_int count) ~on_click:(set_count (count + 1)))
  in
  Backend.reset ();
  let app =
    App.create (fun graph -> Apple.vstack [ scoped "a" graph; scoped "b" graph ])
  in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  require (Backend.find_text_exn root ~path:[ 0 ] = "a:0") "initial a count should be 0";
  require (Backend.find_text_exn root ~path:[ 1 ] = "b:0") "initial b count should be 0";
  Backend.click_exn root ~path:[ 0 ];
  require (Backend.find_text_exn root ~path:[ 0 ] = "a:1") "a should update";
  require (Backend.find_text_exn root ~path:[ 1 ] = "b:0") "b should not update"
;;

let test_tab_selection_updates_state () =
  Backend.reset ();
  let component graph =
    let selected, set_selected = Apple.state graph ~key:"selected" "counter" in
    Apple.tab_view
      ~selected
      ~on_select:set_selected
      [ Apple.tab ~id:"counter" ~title:"Counter" (Apple.text "Counter")
      ; Apple.tab ~id:"search" ~title:"Search" ~role:Apple.Search (Apple.text "Search")
      ]
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  Backend.select_tab_exn root ~id:"search";
  require
    (Backend.find_text_exn root ~path:[ 1 ] = "Search")
    "tab selection should keep tab content mounted"
;;

let test_sidebar_history_actions_are_separate_and_clickable () =
  Backend.reset ();
  let component graph =
    let selected, set_selected = Apple.state graph ~key:"selected" "compose" in
    let event, set_event = Apple.state graph ~key:"event" "none" in
    Apple.sidebar_split
      ~title:"Workspace"
      ~actions:
        [ Apple.sidebar_action
            ~id:"queue"
            ~title:"Queue"
            ~system_image:"tray"
            ~on_click:(set_event "queue")
            ()
        ]
      ~history_title:"Recent"
      ~history_actions:
        [ Apple.sidebar_action
            ~id:"history-item-1"
            ~title:"Open sample item"
            ~subtitle:"Preview: Open sample item"
            ~on_click:(set_event "history-item")
            ~menu_actions:
              [ { title = "Rename"
                ; system_image = Some "pencil"
                ; style = Apple.Default
                ; on_click = set_event "rename"
                }
              ]
            ()
        ]
      ~selected
      ~on_select:set_selected
      [ Apple.tab ~id:"compose" ~title:"Compose" (Apple.text event) ]
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  let rendered = Backend.show root in
  require
    (contains rendered ~substring:"sidebar-actions=[queue:Queue:tray]")
    "primary sidebar action should render separately";
  require
    (contains rendered ~substring:"sidebar-history-title=Recent")
    "history title should render";
  require
    (contains
       rendered
       ~substring:
         "sidebar-history-actions=[history-item-1:Open sample item:preview=Preview: Open \
          sample item:menu=[Rename:pencil:default]]")
    "history action should render separately";
  require
    (contains rendered ~substring:"sidebar-history-menu-presentation=context-menu")
    "history actions should use Swift-style context menus instead of replacing the row \
     button";
  Backend.click_sidebar_history_action_exn root ~id:"history-item-1";
  require
    (Backend.find_text_exn root ~path:[ 0 ] = "history-item")
    "history action click should run";
  Backend.click_sidebar_history_action_menu_action_exn
    root
    ~id:"history-item-1"
    ~title:"Rename";
  require
    (Backend.find_text_exn root ~path:[ 0 ] = "rename")
    "history action menu click should run"
;;

let test_sidebar_actions_can_keep_compact_drawer_open () =
  Backend.reset ();
  let component graph =
    let selected, set_selected = Apple.state graph ~key:"selected" "library" in
    let event, set_event = Apple.state graph ~key:"event" "none" in
    Apple.sidebar_split
      ~title:"Workspace"
      ~header_action:
        (Apple.sidebar_action
           ~id:"account"
           ~title:"Account"
           ~avatar_initial:"?"
           ~closes_sidebar:false
           ~on_click:(set_event "settings")
           ())
      ~actions:
        [ Apple.sidebar_action
            ~selects_tab:"compose"
            ~id:"queue"
            ~title:"Queue"
            ~system_image:"tray"
            ~on_click:(set_event "queue")
            ()
        ; Apple.sidebar_action
            ~id:"library"
            ~title:"Library"
            ~system_image:"rectangle.stack"
            ~on_click:(set_event "library")
            ()
        ; Apple.sidebar_action
            ~id:"run-action"
            ~title:"Run"
            ~system_image:"rectangle.stack.badge.play"
            ~closes_sidebar:false
            ~on_click:(set_event "run")
            ()
        ]
      ~selected
      ~on_select:set_selected
      [ Apple.tab ~id:"library" ~title:"Library" (Apple.text event)
      ; Apple.tab ~id:"compose" ~title:"Compose" (Apple.text event)
      ]
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  let rendered = Backend.show root in
  require
    (contains rendered ~substring:"queue:Queue:tray:selects=compose")
    "sidebar action should expose the route it selects when it differs from its action id";
  require
    (contains rendered ~substring:"sidebar-header-action=account:Account:avatar=?:keeps-sidebar")
    "header action should expose that it keeps the compact sidebar open";
  require
    (contains
       rendered
       ~substring:"run-action:Run:rectangle.stack.badge.play:keeps-sidebar")
    "sheet-style sidebar actions should expose that they keep the compact sidebar open";
  Backend.click_sidebar_header_action_exn root ~id:"account";
  require
    (String.equal (Backend.find_text_exn root ~path:[ 0 ]) "settings")
    "header action click should still run";
  Backend.click_sidebar_action_exn root ~id:"run-action";
  require
    (String.equal (Backend.find_text_exn root ~path:[ 0 ]) "run")
    "non-closing sidebar action click should still run"
;;

let test_compact_sidebar_top_bar_uses_system_toolbar_item_chrome () =
  Backend.reset ();
  let component graph =
    let selected, set_selected = Apple.state graph ~key:"selected" "library" in
    Apple.sidebar_split
      ~title:"Workspace"
      ~selected
      ~on_select:set_selected
      [ Apple.tab ~id:"library" ~title:"Library" (Apple.text "Library") ]
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  let rendered = Backend.show root in
  require
    (contains
       rendered
       ~substring:
         "compact-top-bar=system-toolbar toolbaritem-leading=sidebar-toggle \
          toolbaritem-title=navigation-title")
    "compact top bar should use system toolbar items like the Swift header";
  require
    (contains rendered ~substring:"toolbaritem-leading-chrome=liquid-glass")
    "compact sidebar leading toolbar item should use the same liquid glass chrome as \
     Swift";
  require
    (contains
       rendered
       ~substring:
         "sidebar-safe-area-padding=swift top=max-safe-area-plus-5-or-54 \
          bottom=max-safe-area-or-34")
    "compact sidebar should use the same safe-area padding as the Swift page root";
  require
    (contains
       rendered
       ~substring:"sidebar-shell-background=home-body-ignores-safe-area-outside-clip")
    "compact sidebar shell background should cover the top and bottom safe areas";
  require
    (contains
       rendered
       ~substring:"sidebar-bottom-controls=safe-area-inset keyboard-padding top-padding=10")
    "compact sidebar bottom controls should keep Swift safe-area inset layout while \
     padding above the keyboard";
  require
    (contains
       rendered
       ~substring:
         "sidebar-navigation=chatgpt-drawer")
    "compact sidebar should use a ChatGPT-style drawer";
  require
    (contains
       rendered
       ~substring:
         "sidebar-transition=interactive-drawer sidebar-toggle=open-drawer")
    "compact sidebar toggle should open the drawer through the Swift drawer animation";
  require
    (contains
       rendered
       ~substring:"sidebar-route-selection=select-route-and-close-drawer")
    "compact sidebar route selection should close the drawer";
  require
    (contains
       rendered
       ~substring:
         "sidebar-main-chrome=peek-rounded-shadow-continuous sidebar-swipe=open-anywhere")
    "compact sidebar should advertise the visible continuous-rounded main-page peek and \
     swipe-open behavior";
  require
    (contains
       rendered
       ~substring:"toolbaritem-leading-chrome=liquid-glass")
    "compact sidebar leading toolbar item should keep the liquid glass chrome"
;;

let test_compact_sidebar_bottom_search_tracks_keyboard () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"sidebarKeyboardBottomPadding")
    "compact sidebar bottom search should add keyboard-aware bottom padding instead of \
     staying behind the keyboard";
  require
    (contains source ~substring:"keyboardWillChangeFrameNotification")
    "compact sidebar should observe keyboard frame changes on the drawer root";
  require
    (contains source ~substring:".padding(.bottom, sidebarKeyboardBottomPadding)")
    "compact sidebar bottom search should relayout above the keyboard instead of only \
     applying a visual offset"
;;

let test_compact_sidebar_keyboard_tracking_stays_on_drawer_root () =
  let source = read_file swiftui_source_path in
  let split_start =
    match substring_index source ~substring:"private var compactSidebarSplitView" ~from:0 with
    | Some index -> index
    | None -> failwith "compactSidebarSplitView not found"
  in
  let content_start =
    match substring_index source ~substring:"private var compactSidebarContent" ~from:split_start with
    | Some index -> index
    | None -> failwith "compactSidebarContent not found"
  in
  let split_source = String.sub source split_start (content_start - split_start) in
  let sidebar_content_start =
    match substring_index split_source ~substring:"compactSidebarContent" ~from:0 with
    | Some index -> index
    | None -> failwith "compactSidebarContent call not found"
  in
  let route_detail_start =
    match substring_index split_source ~substring:"compactSidebarMainPage" ~from:sidebar_content_start with
    | Some index -> index
    | None -> failwith "selected route detail stack not found"
  in
  let sidebar_content_source =
    String.sub split_source sidebar_content_start (route_detail_start - sidebar_content_start)
  in
  require
    (not
       (contains
          sidebar_content_source
          ~substring:"UIResponder.keyboardWillChangeFrameNotification"))
    "compact sidebar keyboard notifications should be attached to the drawer root, not \
     the sidebar content subtree; when the focused search field changes keyboard layout \
     the content subtree can stop reporting the correct overlap";
  require
    (contains source ~substring:".padding(.bottom, sidebarKeyboardBottomPadding)")
    "compact sidebar bottom controls should use keyboard padding so the search field \
     gets relaid out above the keyboard instead of only being visually offset";
  require
    (not (contains source ~substring:".offset(y: -sidebarKeyboardBottomPadding)"))
    "compact sidebar bottom controls should not rely on a pure visual offset because it \
     can still leave the search field under the keyboard interaction region"
;;

let test_compact_sidebar_keeps_presented_sheets_interactive () =
  let source = read_file swiftui_source_path in
  require
    (not (contains source ~substring:".disabled(isCompactSidebarOpen)"))
    "compact sidebar should not disable the selected route subtree because app-level \
     sheets are attached there in the OCaml backend; disabling that subtree makes \
     modal sheets open but do not respond to taps"
;;

let test_multiple_sheet_modifiers_install_only_presented_sheet () =
  let source = read_file swiftui_backend_source_path in
  require
    (contains source ~substring:"pending_sheet")
    "SwiftUI backend should arbitrate multiple sheet modifiers through a pending sheet \
     instead of letting a later false sheet overwrite an earlier presented one";
  require
    (contains source ~substring:"install_pending_sheet")
    "SwiftUI backend should install the chosen sheet once after scanning modifiers"
;;

let test_sheet_content_host_fills_sheet_background () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"bonsaiSheetContentHost")
    "SwiftUI sheets should wrap native content in a common host container";
  require
    (contains
       source
       ~substring:".frame(maxWidth: .infinity, maxHeight: .infinity")
    "SwiftUI sheet host should fill the sheet instead of letting intrinsic-width content \
     leave uncovered side gutters";
  require
    (contains source ~substring:".background(bonsaiHomeBodyBackground")
    "SwiftUI sheet host should paint the app body background across the full sheet"
;;

let test_sheet_content_host_preserves_leading_content_alignment () =
  let source = read_file swiftui_source_path in
  let host_start =
    match substring_index source ~substring:"private func bonsaiSheetContentHost" ~from:0 with
    | Some index -> index
    | None -> failwith "bonsaiSheetContentHost not found"
  in
  let detents_start =
    match substring_index source ~substring:"private var sheetPresentationDetents" ~from:host_start with
    | Some index -> index
    | None -> failwith "sheetPresentationDetents not found after bonsaiSheetContentHost"
  in
  let host_source = String.sub source host_start (detents_start - host_start) in
  require
    (contains host_source ~substring:"ZStack(alignment: .topLeading)")
    "SwiftUI sheet host should paint a full-width background without forcing sheet \
     content into the horizontal center";
  require
    (contains host_source ~substring:"alignment: .topLeading")
    "SwiftUI sheet host should keep sheet content leading-aligned while the host \
     background fills the sheet"
;;

let test_custom_label_buttons_use_full_label_hit_target () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"customButtonLabelHitTarget")
    "custom label buttons should wrap their label content in a shared full-frame hit \
     target";
  require
    (contains source ~substring:".contentShape(Rectangle())")
    "custom label buttons should use the whole label frame as the tappable area instead \
     of only the visible glyphs"
;;

let test_image_semantic_color_renders () =
  Backend.reset ();
  let component _graph =
    Apple.hstack
      [ Apple.image ~color:Apple.Green "checkmark.circle.fill"
      ; Apple.image ~color:Apple.Red "xmark.circle.fill"
      ; Apple.image "circle"
      ]
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  let rendered = Backend.show root in
  require
    (contains rendered ~substring:"text=\"checkmark.circle.fill\" image-color=green")
    "green image color should render";
  require
    (contains rendered ~substring:"text=\"xmark.circle.fill\" image-color=red")
    "red image color should render";
  require
    (not (contains rendered ~substring:"text=\"circle\" image-color="))
    "default image color should not render"
;;

let test_button_label_renders_custom_clickable_content () =
  Backend.reset ();
  let component graph =
    let selected, set_selected = Apple.state graph ~key:"selected" false in
    Apple.button_label
      ~is_enabled:(not selected)
      ~on_click:(set_selected true)
      (Apple.hstack
         ~spacing:10.
         [ Apple.image ~color:Apple.Green "checkmark.circle.fill"
         ; Apple.text "Alpha"
         ; Apple.spacer ()
         ])
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  let rendered = Backend.show root in
  require
    (contains rendered ~substring:"button#")
    "custom label button should render as a button";
  require
    (contains rendered ~substring:"stack(horizontal)")
    "custom label button should keep its horizontal label content";
  require
    (contains rendered ~substring:"text=\"checkmark.circle.fill\" image-color=green")
    "custom label button should render its image child";
  Backend.click_exn root ~path:[];
  require
    (contains (Backend.show root) ~substring:"button#")
    "button should remain mounted after click";
  require
    (contains (Backend.show root) ~substring:" disabled")
    "click should run the button action"
;;

let test_hide_list_row_separator_modifier_renders () =
  Backend.reset ();
  let app =
    App.create (fun _graph ->
      Apple.list [ "row" ]
        ~key:(fun value -> value)
        ~row:(fun value -> Apple.text value |> Apple.hide_list_row_separator))
  in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  require
    (contains (Backend.show root) ~substring:"hide-list-row-separator")
    "row separator visibility should be exposed as a render modifier"
;;

let test_text_field_delete_backward_at_start_event () =
  Backend.reset ();
  let component graph =
    let deleted, set_deleted = Apple.state graph ~key:"deleted" false in
    Apple.vstack
      [
        Apple.text_field ~text:""
          ~placeholder:"Block"
          ~on_change:(fun _ -> Apple.Action.ignore)
          ~on_delete_backward_at_start:(set_deleted true)
          ();
        Apple.text (if deleted then "deleted" else "idle");
      ]
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  Backend.delete_backward_at_start_text_exn root ~path:[ 0 ];
  App.flush_and_render app;
  let rendered =
    match App.view app with
    | Some root -> Backend.show root
    | None -> failwith "app did not render"
  in
  require
    (contains rendered ~substring:"text=\"deleted\"")
    "delete backward at the start of a text field should dispatch its event"
;;

let test_text_field_focus_renders () =
  Backend.reset ();
  let component _graph =
    Apple.text_field ~text:"Focused" ~placeholder:"Block" ~is_focused:true
      ~on_change:(fun _ -> Apple.Action.ignore)
      ()
  in
  let app = App.create component in
  App.flush_and_render app;
  let rendered =
    match App.view app with
    | Some root -> Backend.show root
    | None -> failwith "app did not render"
  in
  require (contains rendered ~substring:"text-field#") rendered;
  require
    (contains rendered ~substring:" focused")
    "focused text field should expose focus state to the backend"
;;

let test_text_field_native_clear_button_renders_and_clears () =
  Backend.reset ();
  let component graph =
    let text, set_text = Apple.state graph ~key:"text" "Draft" in
    Apple.text_field
      ~style:Apple.Pill
      ~clear_button:Apple.While_editing
      ~text
      ~placeholder:"New item"
      ~on_change:set_text
      ()
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  require
    (contains (Backend.show root) ~substring:"native-clear-button=while-editing")
    "text fields should expose native clear-button mode instead of requiring app-level \
     trailing buttons";
  Backend.clear_text_exn root ~path:[];
  require
    (contains (Backend.show root) ~substring:"text=\"\"")
    "native clear button should dispatch the text field change handler with an empty \
     value"
;;

let test_button_renders_bordered_prominent_style () =
  Backend.reset ();
  let component _graph =
    Apple.button
      ~style:Apple.Bordered_prominent
      ~system_image:"eye"
      "Reveal answer"
      ~on_click:Apple.Action.ignore
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  require
    (contains
       (Backend.show root)
       ~substring:"text=\"Reveal answer\" image=eye button-style=bordered-prominent")
    "bordered prominent button style should be visible to native renderers"
;;

let test_button_renders_plain_style () =
  Backend.reset ();
  let component _graph =
    Apple.button
      ~style:Apple.Plain
      ~system_image:"arrow.up"
      ~is_title_visible:false
      "Send"
      ~on_click:Apple.Action.ignore
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  require
    (contains
       (Backend.show root)
       ~substring:"text=\"Send\" image=arrow.up button-style=plain title-hidden")
    "plain button style should be visible to native renderers"
;;

let test_on_appear_event_rerenders_component_state () =
  Backend.reset ();
  let component graph =
    let count, set_count = Apple.state graph ~key:"count" 0 in
    Apple.vstack
      [ Apple.text (string_of_int count)
      ; Apple.text "sentinel" |> Apple.on_appear ~on_appear:(set_count (count + 1))
      ]
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  require (Backend.find_text_exn root ~path:[ 0 ] = "0") "initial count should be 0";
  Backend.appear_exn root ~path:[ 1 ];
  require (Backend.find_text_exn root ~path:[ 0 ] = "1") "appear should rerender count"
;;

let test_searchable_renders_prompt () =
  Backend.reset ();
  let component _graph =
    Apple.navigation_stack
      [ Apple.text "Items"
        |> Apple.searchable ~text:"" ~prompt:"Search items" ~on_change:(fun _ ->
          Apple.Action.ignore)
      ]
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  require
    (contains (Backend.show root) ~substring:"searchable-prompt=\"Search items\"")
    "searchable prompt should be visible to native renderers"
;;

let test_picker_renders_segmented_style () =
  Backend.reset ();
  let component _graph =
    Apple.picker
      ~style:Apple.Segmented
      ~title:"Item type"
      ~selected:"basic"
      ~on_select:(fun _ -> Apple.Action.ignore)
      [ Apple.picker_option ~id:"basic" ~title:"Basic"
      ; Apple.picker_option ~id:"single" ~title:"Single"
      ]
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  require
    (contains (Backend.show root) ~substring:"picker-style=segmented")
    "segmented picker style should be visible to native renderers"
;;

let test_liquid_glass_panel_renders () =
  Backend.reset ();
  let component _graph =
    Apple.text "Review"
    |> Apple.liquid_glass_panel
         ~corner_radius:22.
         ~is_transparent:true
         ~tint_color:Apple.Green
         ~tint_opacity:0.1
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  let rendered = Backend.show root in
  require
    (contains
       rendered
       ~substring:"panel=liquid-glass corner-radius=22 transparent=true tint=green:0.1")
    "liquid glass panel should be visible to native renderers"
;;

let test_pill_text_field_uses_liquid_glass_chrome () =
  Backend.reset ();
  let component _graph =
    Apple.text_field
      ~style:Apple.Pill
      ~text:""
      ~placeholder:"New item"
      ~on_change:(fun _ -> Apple.Action.ignore)
      ()
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  let rendered = Backend.show root in
  require
    (contains
       rendered
       ~substring:
         "placeholder=\"New item\" style=pill chrome=liquid-glass corner-radius=26")
    "pill text fields should render with Swift-style liquid glass chrome"
;;

let test_plain_text_field_renders_plain_style () =
  Backend.reset ();
  let component _graph =
    Apple.text_field
      ~style:Apple.Plain_text
      ~text:""
      ~placeholder:"Search"
      ~on_change:(fun _ -> Apple.Action.ignore)
      ()
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  let rendered = Backend.show root in
  require
    (contains rendered ~substring:"placeholder=\"Search\" style=plain")
    "plain text fields should expose SwiftUI plain text field style"
;;

let test_plain_text_fields_match_body_text_size () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:".font(bonsaiNativePreferredFont(.body))")
    "plain SwiftUI text fields should use the same body font as display text";
  require
    (contains source ~substring:"bonsaiNativePreferredUIFont(.body)")
    "delete-aware UIKit text inputs should use the same body font as display text";
  require
    (not (contains source ~substring:"textView.font = bonsaiNativePreferredUIFont(size: 18"))
    "multiline block editors should not use a larger hard-coded font than display rows";
  require
    (not (contains source ~substring:"textField.font = bonsaiNativePreferredUIFont(size: 18"))
    "delete-aware single-line fields should not use a larger hard-coded font than display rows"
;;

let test_frame_renders_max_width () =
  Backend.reset ();
  let component _graph =
    Apple.text "Full width" |> Apple.frame ~max_width:infinity
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  let rendered = Backend.show root in
  require
    (contains rendered ~substring:"frame:_x_:inf")
    "frame should expose max width for SwiftUI maxWidth layout"
;;

let test_swiftui_frame_supports_leading_alignment () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"@Published var frameAlignment")
    "frame modifiers should carry explicit alignment to SwiftUI";
  require
    (contains source ~substring:"alignment: node.frameAlignment.swiftUIAlignment")
    "SwiftUI frame modifiers should use the published alignment instead of default \
     center alignment";
  require
    (contains source ~substring:"node.frameAlignment = BonsaiNativeFrameAlignment(rawValue:")
    "native frame setter should publish the OCaml alignment value"
;;

let test_swiftui_horizontal_stack_supports_top_alignment () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"@Published var horizontalStackAlignment")
    "horizontal stacks should carry explicit vertical alignment to SwiftUI";
  require
    (contains source ~substring:"HStack(alignment: node.horizontalStackAlignment.swiftUIVerticalAlignment")
    "SwiftUI horizontal stacks should use the published vertical alignment";
  require
    (contains source ~substring:"bonsai_native_swiftui_set_horizontal_stack_alignment")
    "native stack alignment setter should publish the OCaml alignment value"
  ;
  require
    (contains source ~substring:"BonsaiNativeHorizontalStackAlignment(rawValue: alignment)")
    "native stack alignment setter should decode the OCaml alignment value"
;;

let test_file_image_can_render_swift_image_file_style () =
  Backend.reset ();
  let component _graph =
    Apple.image_file ~max_height:180. ~corner_radius:8. "/tmp/preview.png"
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  let rendered = Backend.show root in
  require
    (contains rendered ~substring:"source=file")
    "file images should render from the filesystem";
  require
    (contains rendered ~substring:"image-style=max-height:\"180\":corner-radius:\"8\"")
    "file images should expose Swift image file sizing and clipping"
;;

let test_swiftui_image_view_supports_remote_urls () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"AsyncImage(url:")
    "SwiftUI file image nodes should render remote image URLs with AsyncImage"
;;

let test_swiftui_image_view_reserves_requested_height_before_load () =
  let source = read_file swiftui_source_path in
  require
    (count_substrings source ~substring:"minHeight: node.imageMaxHeight" >= 3)
    "SwiftUI image views should reserve the requested image height before and after \
     loading so rows do not change height while scrolling"
;;

let test_swiftui_strict_list_rows_remove_default_insets () =
  let source = read_file swiftui_source_path in
  require
    (contains source
       ~substring:
         "BonsaiNativeNodeView(node: child, model: model)\n          .listRowInsets(EdgeInsets())")
    "strict SwiftUI List rows should remove the default horizontal row insets so app rows \
     control their own margins"
;;

let test_swiftui_custom_view_supports_youtube_webkit_iframes () =
  let source = read_file swiftui_source_path in
  require (contains source ~substring:"import WebKit") "YouTube iframes should use WebKit";
  require
    (contains source ~substring:"BonsaiNativeYouTubeIframeView")
    "custom youtube views should render through a dedicated WebKit view";
  require
    (contains source ~substring:"WKWebView")
    "custom youtube views should be backed by WKWebView";
  require
    (contains source ~substring:"youtubePayload")
    "custom views should recognize youtube payloads by kind"
;;

let test_custom_view_payload_updates_reuse_mounted_node () =
  Backend.reset ();
  let app =
    App.create (fun graph ->
      let payload, set_payload = Apple.state graph ~key:"payload" "first" in
      Apple.vstack
        [
          Apple.custom_view ~kind:("app-webview:" ^ payload) ();
          Apple.button "Update" ~on_click:(set_payload "second");
        ])
  in
  App.flush_and_render app;
  let root = Option.get (App.view app) in
  let before = Backend.stats () in
  Backend.click_exn root ~path:[ 1 ];
  let diff = Backend.diff_stats before (Backend.stats ()) in
  require
    (diff.created = 0 && diff.destroyed = 0)
    (Printf.sprintf
       "custom view payload updates should reuse the mounted platform view; created=%d \
        destroyed=%d"
       diff.created
       diff.destroyed);
  require
    (contains (Backend.show root) ~substring:"custom(app-webview:second)")
    "custom view payload updates should reach the reused platform view"
;;

let test_custom_view_supports_change_messages () =
  let source = read_file apple_source_path in
  require
    (contains source ~substring:"on_change : (string -> unit Action.t) option")
    "custom views should optionally dispatch string messages into Bonsai";
  require
    (contains source ~substring:"Custom_view_node { key; kind; on_change }")
    "custom view updates should install their change callback"
;;

let test_swiftui_custom_view_supports_interactive_bundle_webviews () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"BonsaiNativeAppWebView")
    "app web views should use a dedicated UIViewRepresentable";
  require
    (contains source ~substring:"WKScriptMessageHandler")
    "app web views should receive JavaScript messages";
  require
    (contains source ~substring:"loadFileURL")
    "app web views should load body assets from the application bundle";
  require
    (contains source ~substring:"evaluateJavaScript")
    "OCaml responses and navigation updates should be evaluated in the web body";
  require
    (contains source ~substring:"model.sendChange(node.changeEventId")
    "JavaScript messages should be dispatched through the Bonsai event callback";
  require
    (contains source ~substring:"removeScriptMessageHandler")
    "app web views should remove their script message handler when dismantled"
;;

let test_youtube_iframe_does_not_steal_list_row_gestures () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"BonsaiNativeDeferredYouTubeIframeView(payload: payload)")
    "youtube iframe rows should render a lightweight preview first so scrolling does not \
     create WKWebView instances";
  require
    (contains source ~substring:"@State private var isLoaded = false")
    "youtube iframe previews should only create WebKit after an explicit user action";
  require
    (contains source ~substring:"BonsaiNativeYouTubeIframeView(payload: payload)")
    "loaded youtube iframes should not steal List row swipe or long-press move gestures";
  require
    (contains source ~substring:".allowsHitTesting(false)")
    "loaded youtube iframes should opt out of hit testing";
  require
    (contains source ~substring:"webView.isUserInteractionEnabled = false")
    "the underlying WKWebView should not receive row gesture touches"
;;

let test_swiftui_prefers_inter_for_typography () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"private let bonsaiNativePreferredFontFamily = \"Inter\"")
    "SwiftUI runtime should define Inter as the preferred app font family";
  require
    (contains source ~substring:"Font.custom(bonsaiNativePreferredFontFamily")
    "SwiftUI runtime should use Font.custom so Inter is preferred when available";
  require
    (contains source ~substring:"private func textFont(_ style: Int32, weight: Int32) -> Font")
    "text nodes should resolve style and weight through the Inter-preferred font helper";
  require
    (contains source ~substring:".font(textFont(node.textStyle, weight: node.textWeight))")
    "label text should use the Inter-preferred font helper instead of direct system fonts";
  require
    (contains source ~substring:".font(bonsaiNativePreferredFont(size:")
    "custom-sized runtime text should use the Inter-preferred font helper"
;;

let test_keyboard_dismiss_controls_renders () =
  Backend.reset ();
  let component _graph =
    Apple.form
      [ Apple.section
          ~key:"Fields"
          [ Apple.text_field ~text:"" ~on_change:(fun _ -> Apple.Action.ignore) () ]
      ]
    |> Apple.keyboard_dismiss_controls
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  require
    (contains (Backend.show root) ~substring:"modifiers=[keyboard-dismiss-controls]")
    "keyboard dismiss controls should be visible to native renderers"
;;

let test_keyboard_toolbar_renders_native_keyboard_items () =
  Backend.reset ();
  let component _graph =
    Apple.text_field ~text:"" ~on_change:(fun _ -> Apple.Action.ignore) ()
    |> Apple.keyboard_toolbar
         [
           Apple.toolbar_item ~id:"indent" ~title:"Indent"
             ~system_image:"increase.indent" ~is_title_visible:false
             ~on_click:Apple.Action.ignore ();
           Apple.toolbar_item ~id:"dismiss-keyboard" ~title:"Dismiss keyboard"
             ~system_image:"keyboard.chevron.compact.down" ~is_title_visible:false
             ~on_click:Apple.Action.ignore ();
         ]
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  let rendered = Backend.show root in
  require
    (contains rendered
       ~substring:
         "keyboard-toolbar=[indent:Indent:enabled:image=increase.indent:title-hidden,dismiss-keyboard:Dismiss keyboard:enabled:image=keyboard.chevron.compact.down:title-hidden]")
    ("keyboard toolbar should render native keyboard-placement items:\n" ^ rendered)
;;

let test_keyboard_toolbar_accessory_is_stable_during_text_updates () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"keyboardAccessorySignature")
    "UIKit keyboard accessory views should track a signature for the installed toolbar";
  require
    (contains source ~substring:"if textView.keyboardAccessorySignature != keyboardAccessorySignature")
    "UITextView accessory toolbar should only be replaced when toolbar items change";
  require
    (contains source ~substring:"if textField.keyboardAccessorySignature != keyboardAccessorySignature")
    "UITextField accessory toolbar should only be replaced when toolbar items change"
;;

let test_scroll_dismisses_keyboard_renders () =
  Backend.reset ();
  let component _graph =
    Apple.scroll_view (Apple.text "Transcript") |> Apple.scroll_dismisses_keyboard
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  let rendered = Backend.show root in
  require
    (contains rendered ~substring:"modifiers=[scroll-dismisses-keyboard]")
    "scroll-only keyboard dismissal should render without keyboard toolbar controls";
  require
    (not (contains rendered ~substring:"keyboard-dismiss-controls"))
    "scroll-only keyboard dismissal should not add keyboard toolbar controls"
;;

let test_secondary_fill_panel_renders () =
  Backend.reset ();
  let component _graph =
    Apple.text "You: Hello" |> Apple.secondary_fill_panel ~corner_radius:18. ~opacity:0.12
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  let rendered = Backend.show root in
  require
    (contains rendered ~substring:"panel=secondary-fill corner-radius=18 opacity=0.12")
    "secondary fill panel should expose Swift user message bubble chrome"
;;

let test_context_menu_renders_and_clicks_actions () =
  Backend.reset ();
  let copied = ref false in
  let component _graph =
    Apple.text "Message"
    |> Apple.context_menu
         [ { title = "Copy"
           ; system_image = Some "doc.on.doc"
           ; style = Apple.Default
           ; on_click = Apple.Action.of_thunk (fun () -> copied := true)
           }
         ; { title = "Delete"
           ; system_image = Some "trash"
           ; style = Apple.Destructive
           ; on_click = Apple.Action.ignore
           }
         ]
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  let rendered = Backend.show root in
  require
    (contains
       rendered
       ~substring:"context-menu=[Copy:doc.on.doc:default,Delete:trash:destructive]")
    "context menus should expose SwiftUI message actions";
  Backend.click_context_menu_action_exn root ~path:[] ~title:"Copy";
  require !copied "context menu actions should be clickable"
;;

let test_copy_text_to_clipboard_action_updates_test_clipboard () =
  Backend.reset ();
  Apple.copy_text_to_clipboard "Copied text" ();
  require
    (Backend.clipboard_text () = Some "Copied text")
    "copy text action should update the backend clipboard"
;;

let test_copy_image_file_to_clipboard_action_updates_test_clipboard () =
  Backend.reset ();
  Apple.copy_image_file_to_clipboard "/tmp/photo.png" ();
  require
    (Backend.clipboard_image_file () = Some "/tmp/photo.png")
    "copy image file action should update the backend clipboard image file"
;;

let test_toggle_audio_file_playback_action_updates_test_playback_state () =
  Backend.reset ();
  Apple.toggle_audio_file_playback "/tmp/recording.m4a" ();
  require
    (Backend.playing_audio_file () = Some "/tmp/recording.m4a")
    "toggle audio action should start playback for the file";
  Apple.toggle_audio_file_playback "/tmp/recording.m4a" ();
  require
    (Option.is_none (Backend.playing_audio_file ()))
    "toggle audio action should pause the currently playing file";
  Apple.toggle_audio_file_playback "/tmp/other.m4a" ();
  require
    (Backend.playing_audio_file () = Some "/tmp/other.m4a")
    "toggle audio action should switch to a different file"
;;

let test_audio_recording_actions_update_testing_backend () =
  Backend.reset ();
  require
    (not (Backend.is_audio_recording ()))
    "audio recorder should start idle in the testing backend";
  Apple.start_audio_recording ();
  require (Backend.is_audio_recording ()) "start recording action should mark recording";
  let result = Apple.stop_audio_recording_and_transcribe () in
  require
    (not (Backend.is_audio_recording ()))
    "stop recording action should return the testing backend to idle";
  require
    (String.equal result.transcript "Voice note")
    "stop recording should return the transcript";
  require
    (String.equal result.local_path "/tmp/voice-note.m4a")
    "stop recording should return the audio file path";
  require
    (String.equal result.filename "voice-note.m4a")
    "stop recording should return the audio filename";
  require
    (String.equal result.content_type "audio/mp4")
    "stop recording should return the audio content type";
  require (result.byte_size = 42) "stop recording should return the byte size"
;;

let test_toolbar_item_can_render_share_link () =
  Backend.reset ();
  let component _graph =
    Apple.text "Preview"
    |> Apple.toolbar
         [ Apple.toolbar_item
             ~id:"share"
             ~title:"Share"
             ~system_image:"square.and.arrow.up"
             ~is_title_visible:false
             ~share_url:"file:///tmp/photo.png"
             ~on_click:Apple.Action.ignore
             ()
         ]
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  require
    (contains
       (Backend.show root)
       ~substring:
         "toolbar=[share:Share:enabled:image=square.and.arrow.up:title-hidden:share-url=file:///tmp/photo.png]")
    "toolbar share items should expose the ShareLink URL";
  require
    (contains (Backend.show root) ~substring:"toolbar-presentation=system-toolbaritem")
    "toolbar actions should render through system ToolbarItem chrome";
  require
    (contains (Backend.show root) ~substring:"toolbaritem-chrome=system-default")
    "toolbar actions should keep the system ToolbarItem button chrome"
;;

let test_bottom_toolbar_groups_render_native_toolbar_content () =
  Backend.reset ();
  let item id title image =
    Apple.toolbar_item ~id ~title ~system_image:image ~is_title_visible:false
      ~on_click:Apple.Action.ignore ()
  in
  let component _graph =
    Apple.text "Preview"
    |> Apple.toolbar_groups
         [
           Apple.toolbar_group ~id:"nav" ~placement:Apple.Bottom_bar
             [
               item "home" "Home" "house";
               item "calendar" "Calendar" "calendar";
             ];
           Apple.toolbar_spacer ~id:"split" ~placement:Apple.Bottom_bar ();
           Apple.toolbar_group ~id:"actions" ~placement:Apple.Bottom_bar
             [
               item "search" "Search" "magnifyingglass";
               item "add" "Add" "plus";
             ];
         ]
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  let rendered = Backend.show root in
  require
    (contains rendered
       ~substring:
         "toolbar-groups=[group:nav:bottom-bar:[home:Home:enabled:image=house:title-hidden,calendar:Calendar:enabled:image=calendar:title-hidden],spacer:split:bottom-bar:true,group:actions:bottom-bar:[search:Search:enabled:image=magnifyingglass:title-hidden,add:Add:enabled:image=plus:title-hidden]]")
    ("bottom toolbar groups should render grouped bottom-bar toolbar content:\n"
     ^ rendered);
  require
    (contains rendered ~substring:"toolbar-presentation=system-toolbaritem-groups")
    "grouped toolbar content should still render through system ToolbarItem chrome";
  let swift = read_file swiftui_source_path in
  require
    (contains swift
       ~substring:"ToolbarItemGroup(placement: content.placement.swiftUIPlacement)")
    "SwiftUI backend should render grouped toolbar content through native ToolbarItemGroup";
  require
    (contains swift
       ~substring:"ToolbarSpacer(.fixed, placement: content.placement.swiftUIPlacement)")
    "SwiftUI backend should render toolbar separators through native fixed ToolbarSpacer"
;;

let test_navigation_path_stack_uses_grouped_background_chrome () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:".toolbarBackground(bonsaiHomeBodyBackground, for: .navigationBar)")
    "Navigation path stacks should tint the navigation bar with the same grouped background";
  require
    (contains source
       ~substring:".toolbarBackground(bonsaiHomeBodyBackground, for: .bottomBar)")
    "Navigation path stacks should tint the bottom toolbar with the same grouped background";
  require
    (contains source ~substring:".listRowBackground(bonsaiHomeBodyBackground)")
    "Native list rows should use the same grouped background as the page"
;;

let test_movable_rows_move_only_the_group_children () =
  Backend.reset ();
  let filteri list ~f =
    let rec loop index = function
      | [] -> []
      | value :: rest ->
        if f index value then value :: loop (index + 1) rest else loop (index + 1) rest
    in
    loop 0 list
  in
  let split_at index list =
    let rec loop remaining prefix rest =
      if remaining <= 0
      then List.rev prefix, rest
      else (
        match rest with
        | [] -> List.rev prefix, []
        | value :: tail -> loop (remaining - 1) (value :: prefix) tail)
    in
    loop index [] list
  in
  let choice_rows choices =
    match choices with
    | _question :: first :: second :: _hint :: _ -> [ first; second ]
    | _ -> []
  in
  let component graph =
    let choices, set_choices =
      Apple.state graph ~key:"choices" [ "Question"; "Beta"; "Alpha"; "Hint" ]
    in
    let move_choice ~from_index ~to_index =
      match choices with
      | question :: first :: second :: hint :: tail ->
        let rows = [ first; second ] in
        let item = List.nth rows from_index in
        let remaining = filteri rows ~f:(fun index _ -> index <> from_index) in
        let insert_index = if to_index > from_index then to_index - 1 else to_index in
        let before, after = split_at insert_index remaining in
        set_choices ([ question ] @ before @ [ item ] @ after @ (hint :: tail))
      | _ -> Apple.Action.ignore
    in
    Apple.list
      [ Apple.section
          ~key:"Item"
          [ Apple.text (List.nth choices 0)
          ; Apple.movable_rows
              ~edit_mode:true
              ~on_move:move_choice
              (choice_rows choices)
              ~key:(fun choice -> choice)
              ~row:Apple.text
          ; Apple.text (List.nth choices 3)
          ]
      ]
      ~key:Apple.section_key
      ~row:(fun node -> node)
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  let rendered = Backend.show root in
  require
    (contains rendered ~substring:"movable-rows#")
    "movable rows should render as a separate group inside a section";
  require
    (contains rendered ~substring:"edit-mode on-move")
    "movable rows should expose Swift edit mode and move behavior";
  Backend.move_rows_exn root ~path:[ 0; 1 ] ~from_index:0 ~to_index:2;
  require
    (contains (Backend.show root) ~substring:"text=\"Question\"")
    "non-movable rows should stay in the section";
  require
    (String.equal (Backend.find_text_exn root ~path:[ 0; 1; 0 ]) "Alpha")
    "moving the first movable row after the second should update that group"
;;

let test_list_marks_focused_row_for_native_scroll () =
  Backend.reset ();
  let component _graph =
    Apple.list
      ~focused_row_key:"third"
      [ "first"; "second"; "third" ]
      ~key:(fun row -> row)
      ~row:(fun row ->
        Apple.text_field
          ~text:row
          ~is_focused:(String.equal row "third")
          ~on_change:(fun _ -> Apple.Action.ignore)
          ())
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  require
    (contains (Backend.show root) ~substring:"focused-row=third")
    "focused list row should be exposed so the native list can keep it visible"
;;

let test_focused_row_scroll_keeps_row_visible_without_centering () =
  let source = read_file swiftui_source_path in
  require
    (contains
       source
       ~substring:"if node.lazyListVisibleIndices.contains(index)")
    "focusing an already visible lazy row should not issue a scroll because it can make \
     SwiftUI recycle visible rows and bounce focus";
  require
    (not
       (contains
          source
          ~substring:
            "withAnimation(.easeInOut(duration: 0.18)) {\n        proxy.scrollTo(targetID)"))
    "focused row reveal should not animate because a tap-to-focus must not move or recycle \
     rows under the user's finger";
  require
    (not (contains source ~substring:"proxy.scrollTo(index, anchor: .center)"))
    "focused row scrolling should keep the row visible without forcing it to the center";
  require
    (contains source ~substring:"proxy.scrollTo(targetID)")
    "focused row scrolling should let SwiftUI choose the minimal scroll needed to reveal it"
;;

let test_focused_lazy_row_replacement_does_not_blur_visible_index () =
  let source = read_file swiftui_source_path in
  require
    (contains source ~substring:"lazyListVisibleIndexCounts")
    "focused row visibility must be reference-counted because SwiftUI can call appear for \
     the editor row before disappear for the replaced display row";
  require
    (contains
       source
       ~substring:"guard !owner.lazyListVisibleIndices.contains(index) else")
    "when a focused lazy row is replaced in-place by its editor row, the old row view may \
     disappear, but the same index is still visible and must not send Blur_block"
;;

let () =
  test_event_rerenders_component_state ();
  test_scoped_state_is_independent ();
  test_tab_selection_updates_state ();
  test_sidebar_history_actions_are_separate_and_clickable ();
  test_sidebar_actions_can_keep_compact_drawer_open ();
  test_compact_sidebar_top_bar_uses_system_toolbar_item_chrome ();
  test_compact_sidebar_bottom_search_tracks_keyboard ();
  test_compact_sidebar_keyboard_tracking_stays_on_drawer_root ();
  test_compact_sidebar_keeps_presented_sheets_interactive ();
  test_multiple_sheet_modifiers_install_only_presented_sheet ();
  test_sheet_content_host_fills_sheet_background ();
  test_sheet_content_host_preserves_leading_content_alignment ();
  test_custom_label_buttons_use_full_label_hit_target ();
  test_navigation_value_links_do_not_preempt_system_push ();
  test_navigation_links_render_without_system_link_chrome ();
  test_compact_sidebar_uses_chatgpt_drawer ();
  test_compact_sidebar_keeps_drawer_drag_arbitration_local ();
  test_compact_sidebar_uses_drawer_for_content_swipes ();
  test_horizontal_swipe_ignores_disabled_directions ();
  test_native_list_uses_stable_node_identity ();
  test_list_virtualization_probe_does_not_log_per_row_events ();
  test_swiftui_library_builds_in_default_ios_context ();
  test_lazy_list_renders_rows_in_testing_backend ();
  test_lazy_list_patches_cached_rows ();
  test_lazy_list_state_key_refreshes_cached_row ();
  test_lazy_list_reorder_reuses_mounted_rows_by_key ();
  test_lazy_list_renderer_uses_indexed_keys ();
  test_lazy_list_marks_moved_target_indices_order_changed ();
  test_lazy_list_focus_cache_renders_only_focused_row ();
  test_swiftui_lazy_list_uses_native_row_provider ();
  test_swiftui_lazy_list_defers_missing_visible_row_render ();
  test_swiftui_lazy_list_uses_native_list_for_row_actions ();
  test_swiftui_lazy_list_rows_hide_native_separators_at_container ();
  test_swiftui_native_list_disables_implicit_row_count_animation ();
  test_swiftui_lazy_list_move_updates_visible_order_immediately ();
  test_swiftui_lazy_list_delete_leaves_native_delete_transaction ();
  test_swiftui_lazy_row_body_does_not_render_rows_synchronously ();
  test_swiftui_list_debug_perf_log_uses_swift_safe_interpolation ();
  test_swiftui_frame_probe_can_run_without_list_debug_bookkeeping ();
  test_swiftui_frame_probe_logs_slow_lazy_row_renders ();
  test_swiftui_frame_probe_reports_scroll_phase_row_lifecycle_counts ();
  test_swiftui_host_model_is_only_observed_by_root_view ();
  test_swiftui_lazy_list_row_is_equatable ();
  test_swiftui_lazy_list_visible_index_tracking_stays_off_scroll_hot_path ();
  test_swiftui_lazy_list_keeps_slots_off_scroll_hot_path ();
  test_swiftui_lazy_list_foreach_resolves_keys_only_for_visible_rows ();
  test_swiftui_lazy_list_disappear_does_not_enqueue_release_work ();
  test_ios_bootstrap_prefers_checkout_sources_for_local_packages ();
  test_swiftui_lazy_list_refreshes_visible_rows_after_provider_update ();
  test_swiftui_lazy_list_content_cache_uses_stable_row_key ();
  test_swiftui_lazy_list_defers_append_row_count_while_scrolling ();
  test_swiftui_lazy_list_publishes_deferred_appends_once_after_idle ();
  test_swiftui_lazy_list_row_count_publish_disables_implicit_animation_at_write ();
  test_swiftui_lazy_list_structural_row_count_publishes_synchronously ();
  test_swiftui_lazy_list_deferred_append_has_max_latency ();
  test_swiftui_lazy_list_logs_row_count_publish_decisions ();
  test_swiftui_lazy_list_emits_row_count_published_event ();
  test_swiftui_exposes_scroll_idle_main_dispatch ();
  test_swiftui_exposes_rendered_frame_main_dispatch ();
  test_swiftui_mac_bridge_exports_lazy_list_symbols ();
  test_swiftui_scroll_stress_pauses_at_end_for_deferred_appends ();
  test_swiftui_scroll_stress_does_not_restart_for_each_row_count_chunk ();
  test_swiftui_lazy_list_retained_cache_stays_small ();
  test_swiftui_lazy_list_logs_ui_row_lifecycle_counts ();
  test_swiftui_lazy_list_uses_stable_row_keys_for_identity ();
  test_swiftui_lazy_list_keeps_old_identity_keys_until_shrink_count_publishes ();
  test_swiftui_lazy_list_disappear_defers_detach_without_releasing_cache ();
  test_swiftui_lazy_list_blurs_focused_row_after_disappear ();
  test_swiftui_lazy_list_scroll_blur_ignores_tap_jitter ();
  test_swiftui_lazy_list_setters_skip_unchanged_published_values ();
  test_swiftui_navigation_setter_skips_unchanged_published_values ();
  test_swiftui_change_events_defer_from_view_update_callbacks ();
  test_swiftui_structural_text_edits_handoff_keyboard_until_next_focus ();
  test_swiftui_delete_aware_text_change_updates_model_immediately ();
  test_swiftui_vertical_delete_aware_text_fields_wrap ();
  test_swiftui_delete_aware_focus_requests_are_transition_scoped ();
  test_navigation_value_links_keep_primary_tap_for_link ();
  test_image_semantic_color_renders ();
  test_button_label_renders_custom_clickable_content ();
  test_hide_list_row_separator_modifier_renders ();
  test_text_field_delete_backward_at_start_event ();
  test_text_field_focus_renders ();
  test_text_field_native_clear_button_renders_and_clears ();
  test_button_renders_bordered_prominent_style ();
  test_button_renders_plain_style ();
  test_on_appear_event_rerenders_component_state ();
  test_searchable_renders_prompt ();
  test_picker_renders_segmented_style ();
  test_liquid_glass_panel_renders ();
  test_pill_text_field_uses_liquid_glass_chrome ();
  test_plain_text_field_renders_plain_style ();
  test_plain_text_fields_match_body_text_size ();
  test_frame_renders_max_width ();
  test_swiftui_frame_supports_leading_alignment ();
  test_swiftui_horizontal_stack_supports_top_alignment ();
  test_file_image_can_render_swift_image_file_style ();
  test_swiftui_image_view_supports_remote_urls ();
  test_swiftui_image_view_reserves_requested_height_before_load ();
  test_swiftui_strict_list_rows_remove_default_insets ();
  test_swiftui_custom_view_supports_youtube_webkit_iframes ();
  test_custom_view_payload_updates_reuse_mounted_node ();
  test_custom_view_supports_change_messages ();
  test_swiftui_custom_view_supports_interactive_bundle_webviews ();
  test_youtube_iframe_does_not_steal_list_row_gestures ();
  test_swiftui_prefers_inter_for_typography ();
  test_keyboard_dismiss_controls_renders ();
  test_keyboard_toolbar_renders_native_keyboard_items ();
  test_keyboard_toolbar_accessory_is_stable_during_text_updates ();
  test_scroll_dismisses_keyboard_renders ();
  test_secondary_fill_panel_renders ();
  test_context_menu_renders_and_clicks_actions ();
  test_copy_text_to_clipboard_action_updates_test_clipboard ();
  test_copy_image_file_to_clipboard_action_updates_test_clipboard ();
  test_toggle_audio_file_playback_action_updates_test_playback_state ();
  test_audio_recording_actions_update_testing_backend ();
  test_toolbar_item_can_render_share_link ();
  test_bottom_toolbar_groups_render_native_toolbar_content ();
  test_navigation_path_stack_uses_grouped_background_chrome ();
  test_movable_rows_move_only_the_group_children ();
  test_list_marks_focused_row_for_native_scroll ();
  test_focused_lazy_row_replacement_does_not_blur_visible_index ();
  test_focused_row_scroll_keeps_row_visible_without_centering ()
;;
