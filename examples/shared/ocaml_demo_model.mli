type todo =
  { id : int
  ; title : string
  ; completed : bool
  }

type t

type action =
  | Increment
  | Decrement
  | Reset_counter
  | Set_todo_draft of string
  | Add_todo
  | Toggle_todo of int
  | Delete_todo of int
  | Set_search_query of string

type error =
  | Unknown_todo of int

val initial : t
val update : t -> action -> (t, error) result
val revision : t -> int
val count : t -> int
val todo_draft : t -> string
val todos : t -> todo list
val search_query : t -> string
val search_results : t -> string list
