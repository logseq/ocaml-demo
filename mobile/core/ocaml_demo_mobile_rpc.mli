module Session : sig
  type t

  val create : unit -> t
  val call : t -> string -> string
end
