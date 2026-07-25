module Apple = Ocaml_demo_apple

let initial_tab_id () =
  let initial_tab =
    match Sys.getenv_opt "OCAML_DEMO_INITIAL_TAB" with
    | Some value -> Some value
    | None -> Sys.getenv_opt "OCAML_DEMO_APPLE_INITIAL_TAB"
  in
  match initial_tab with
  | Some ("counter" | "0") -> "counter"
  | Some ("todo" | "1") -> "todo"
  | Some ("search" | "2") -> "search"
  | _ -> "counter"
;;

let component graph =
  let counter = Counter.component graph in
  let todo = Todo.component graph in
  let search = Searchable_list.component graph in
  let selected_tab, set_selected_tab =
    Apple.state graph ~key:"selected-tab" (initial_tab_id ())
  in
  Apple.tab_view
    ~selected:selected_tab
    ~on_select:set_selected_tab
    [ Apple.tab
        ~id:"counter"
        ~title:"Counter"
        ~system_image:"plus.circle"
        counter
    ; Apple.tab ~id:"todo" ~title:"Todo" ~system_image:"checklist" todo
    ; Apple.tab
        ~id:"search"
        ~title:"Search"
        ~system_image:"magnifyingglass"
        ~role:Apple.Search
        search
    ]
;;
