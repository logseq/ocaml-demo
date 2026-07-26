module Json = Ocaml_demo_json

let session = ref (Ocaml_demo_rpc.Session.create ())
let sqlite_session : Ocaml_demo_sqlite.session option ref = ref None

let assoc name fields = List.assoc_opt name fields

let open_database request =
  match Json.from_string request with
  | Ok (`Assoc fields) ->
    (match assoc "method" fields, assoc "params" fields with
     | Some (`String "open"), Some (`Assoc params) ->
       (match assoc "path" params with
        | Some (`String path) ->
          Option.iter Ocaml_demo_sqlite.close !sqlite_session;
          let opened = Ocaml_demo_sqlite.open_session path in
          sqlite_session := Some opened;
          session :=
            Ocaml_demo_rpc.Session.create
              ~storage:(Ocaml_demo_sqlite.storage opened)
              ();
          Some
            (Ocaml_demo_rpc.Session.call
               !session
               {|{"apiVersion":1,"method":"snapshot","params":{"screen":"journal"}}|})
        | _ -> None)
     | _ -> None)
  | _ -> None
;;

let call request =
  match open_database request with
  | Some response -> response
  | None -> Ocaml_demo_rpc.Session.call !session request
;;

let () = Callback.register "ocaml_demo_mobile_call" call
