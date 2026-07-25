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

let () =
  let app = Ocaml_demo_android.App.create Counter_component.component in
  let before = Ocaml_demo_android.App.render_json app in
  if not (contains before ~substring:{|"text":"0"|})
  then failwith ("expected initial render to contain counter text 0, got: " ^ before);
  Ocaml_demo_android.App.dispatch_click app 1;
  let after = Ocaml_demo_android.App.render_json app in
  if not (contains after ~substring:{|"text":"1"|})
  then failwith ("expected click dispatch to contain counter text 1, got: " ^ after);
  print_endline after
;;
