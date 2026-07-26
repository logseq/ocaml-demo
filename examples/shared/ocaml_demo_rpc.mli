module Session : sig
  type t

  val create : ?storage:Datascript.storage -> unit -> t
  val call : t -> string -> string
end
