let session = Ocaml_demo_rpc.Session.create ()
let call request = Ocaml_demo_rpc.Session.call session request
let () = Callback.register "ocaml_demo_mobile_call" call
