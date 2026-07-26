type task =
  { id : int
  ; title : string
  ; completed : bool
  }

type block =
  { id : int
  ; content : string
  ; depth : int
  }

type journal =
  { id : int
  ; title : string
  }

type t

type action =
  | Set_task_draft of string
  | Add_task
  | Toggle_task of int
  | Delete_task of int
  | Ensure_today of string
  | Select_journal of int
  | Set_block_content of int * string
  | Add_sibling_block of int
  | Indent_block of int
  | Outdent_block of int

type error =
  | Unknown_task of int
  | Unknown_journal of int
  | Unknown_block of int

val create : ?storage:Datascript.storage -> unit -> t
val update : t -> action -> (unit, error) result
val revision : t -> int
val task_draft : t -> string
val tasks : t -> task list
val journals : t -> journal list
val selected_journal_id : t -> int
val blocks : t -> block list
