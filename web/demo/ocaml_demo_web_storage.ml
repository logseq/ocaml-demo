module Codec = Datascript_melange_storage

external restore_value : string -> string Js.nullable = "ocamlDemoSQLiteRestore" [@@mel.scope "window"]
external list_addresses : unit -> string array = "ocamlDemoSQLiteList" [@@mel.scope "window"]
external store_values : string array -> string array -> unit = "ocamlDemoSQLiteStore" [@@mel.scope "window"]
external delete_values : string array -> unit = "ocamlDemoSQLiteDelete" [@@mel.scope "window"]

let storage () : Datascript.storage =
  { storage_store =
      (fun entries ->
        let addresses, payloads =
          entries
          |> List.map (fun (address, payload) -> address, Codec.encode payload)
          |> List.split
        in
        store_values (Array.of_list addresses) (Array.of_list payloads))
  ; storage_restore =
      (fun address ->
        restore_value address |> Js.Nullable.toOption |> Option.map Codec.decode)
  ; storage_list_addresses =
      (fun () -> list_addresses () |> Array.to_list)
  ; storage_delete =
      (fun addresses -> delete_values (Array.of_list addresses))
  }
;;
