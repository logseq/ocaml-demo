type t =
  [ `Assoc of (string * t) list
  | `Bool of bool
  | `Float of float
  | `Int of int
  | `List of t list
  | `Null
  | `String of string
  ]

exception Parse_error of string

let fail message = raise (Parse_error message)

let add_utf8 buffer codepoint =
  if codepoint <= 0x7f
  then Buffer.add_char buffer (Char.chr codepoint)
  else if codepoint <= 0x7ff
  then (
    Buffer.add_char buffer (Char.chr (0xc0 lor (codepoint lsr 6)));
    Buffer.add_char buffer (Char.chr (0x80 lor (codepoint land 0x3f))))
  else if codepoint <= 0xffff
  then (
    Buffer.add_char buffer (Char.chr (0xe0 lor (codepoint lsr 12)));
    Buffer.add_char buffer (Char.chr (0x80 lor ((codepoint lsr 6) land 0x3f)));
    Buffer.add_char buffer (Char.chr (0x80 lor (codepoint land 0x3f))))
  else (
    Buffer.add_char buffer (Char.chr (0xf0 lor (codepoint lsr 18)));
    Buffer.add_char buffer (Char.chr (0x80 lor ((codepoint lsr 12) land 0x3f)));
    Buffer.add_char buffer (Char.chr (0x80 lor ((codepoint lsr 6) land 0x3f)));
    Buffer.add_char buffer (Char.chr (0x80 lor (codepoint land 0x3f)))
  )
;;

let hex_value = function
  | '0' .. '9' as value -> Char.code value - Char.code '0'
  | 'a' .. 'f' as value -> 10 + Char.code value - Char.code 'a'
  | 'A' .. 'F' as value -> 10 + Char.code value - Char.code 'A'
  | _ -> fail "invalid Unicode escape"
;;

let from_string source =
  let length = String.length source in
  let index = ref 0 in
  let peek () = if !index < length then Some source.[!index] else None in
  let take () =
    match peek () with
    | Some value ->
      incr index;
      value
    | None -> fail "unexpected end of input"
  in
  let rec skip_whitespace () =
    match peek () with
    | Some (' ' | '\n' | '\r' | '\t') ->
      incr index;
      skip_whitespace ()
    | _ -> ()
  in
  let expect literal =
    String.iter
      (fun expected ->
        if take () <> expected then fail ("expected " ^ literal))
      literal
  in
  let unicode_escape () =
    let codepoint = ref 0 in
    for _ = 1 to 4 do
      codepoint := (!codepoint lsl 4) lor hex_value (take ())
    done;
    !codepoint
  in
  let rec string () =
    if take () <> '"' then fail "expected string";
    let buffer = Buffer.create 32 in
    let rec loop () =
      match take () with
      | '"' -> Buffer.contents buffer
      | '\\' ->
        (match take () with
         | '"' -> Buffer.add_char buffer '"'
         | '\\' -> Buffer.add_char buffer '\\'
         | '/' -> Buffer.add_char buffer '/'
         | 'b' -> Buffer.add_char buffer '\b'
         | 'f' -> Buffer.add_char buffer '\012'
         | 'n' -> Buffer.add_char buffer '\n'
         | 'r' -> Buffer.add_char buffer '\r'
         | 't' -> Buffer.add_char buffer '\t'
         | 'u' ->
           let first = unicode_escape () in
           if first >= 0xd800 && first <= 0xdbff
           then (
             if take () <> '\\' || take () <> 'u'
             then fail "missing low Unicode surrogate";
             let second = unicode_escape () in
             if second < 0xdc00 || second > 0xdfff
             then fail "invalid low Unicode surrogate";
             add_utf8 buffer (0x10000 + ((first - 0xd800) lsl 10) + second - 0xdc00))
           else if first >= 0xdc00 && first <= 0xdfff
           then fail "unexpected low Unicode surrogate"
           else add_utf8 buffer first
         | _ -> fail "invalid string escape");
        loop ()
      | value when Char.code value < 0x20 -> fail "unescaped control character"
      | value ->
        Buffer.add_char buffer value;
        loop ()
    in
    loop ()
  and number () =
    let start = !index in
    let take_digits ~required =
      let first = !index in
      while
        match peek () with
        | Some ('0' .. '9') ->
          incr index;
          true
        | _ -> false
      do
        ()
      done;
      if required && !index = first then fail "expected digit"
    in
    if peek () = Some '-' then incr index;
    (match take () with
     | '0' ->
       (match peek () with
        | Some ('0' .. '9') -> fail "leading zero in number"
        | _ -> ())
     | '1' .. '9' -> take_digits ~required:false
     | _ -> fail "invalid number");
    (match peek () with
     | Some '.' ->
       incr index;
       take_digits ~required:true
     | _ -> ());
    (match peek () with
     | Some ('e' | 'E') ->
       incr index;
       (match peek () with
        | Some ('+' | '-') -> incr index
        | _ -> ());
       take_digits ~required:true
     | _ -> ());
    let value = String.sub source start (!index - start) in
    match int_of_string_opt value with
    | Some value -> `Int value
    | None ->
      (match float_of_string_opt value with
       | Some value -> `Float value
       | None -> fail "invalid number")
  and array () =
    ignore (take ());
    skip_whitespace ();
    if peek () = Some ']'
    then (
      ignore (take ());
      `List [])
    else (
      let rec loop values =
        let value = value () in
        skip_whitespace ();
        match take () with
        | ',' ->
          skip_whitespace ();
          loop (value :: values)
        | ']' -> `List (List.rev (value :: values))
        | _ -> fail "expected ',' or ']'"
      in
      loop [])
  and object_ () =
    ignore (take ());
    skip_whitespace ();
    if peek () = Some '}'
    then (
      ignore (take ());
      `Assoc [])
    else (
      let rec loop fields =
        let name = string () in
        skip_whitespace ();
        if take () <> ':' then fail "expected ':'";
        skip_whitespace ();
        let field = name, value () in
        skip_whitespace ();
        match take () with
        | ',' ->
          skip_whitespace ();
          loop (field :: fields)
        | '}' -> `Assoc (List.rev (field :: fields))
        | _ -> fail "expected ',' or '}'"
      in
      loop [])
  and value () =
    skip_whitespace ();
    match peek () with
    | Some '"' -> `String (string ())
    | Some '{' -> object_ ()
    | Some '[' -> array ()
    | Some 't' ->
      expect "true";
      `Bool true
    | Some 'f' ->
      expect "false";
      `Bool false
    | Some 'n' ->
      expect "null";
      `Null
    | Some ('-' | '0' .. '9') -> number ()
    | Some _ -> fail "unexpected token"
    | None -> fail "empty input"
  in
  try
    let value = value () in
    skip_whitespace ();
    if !index <> length then fail "trailing input";
    Ok value
  with
  | Parse_error message -> Error message
;;

let add_escaped_string buffer value =
  Buffer.add_char buffer '"';
  String.iter
    (function
      | '"' -> Buffer.add_string buffer "\\\""
      | '\\' -> Buffer.add_string buffer "\\\\"
      | '\b' -> Buffer.add_string buffer "\\b"
      | '\012' -> Buffer.add_string buffer "\\f"
      | '\n' -> Buffer.add_string buffer "\\n"
      | '\r' -> Buffer.add_string buffer "\\r"
      | '\t' -> Buffer.add_string buffer "\\t"
      | value when Char.code value < 0x20 ->
        Buffer.add_string buffer (Printf.sprintf "\\u%04x" (Char.code value))
      | value -> Buffer.add_char buffer value)
    value;
  Buffer.add_char buffer '"'
;;

let to_string json =
  let buffer = Buffer.create 128 in
  let rec add = function
    | `Null -> Buffer.add_string buffer "null"
    | `Bool value -> Buffer.add_string buffer (string_of_bool value)
    | `Int value -> Buffer.add_string buffer (string_of_int value)
    | `Float value -> Buffer.add_string buffer (string_of_float value)
    | `String value -> add_escaped_string buffer value
    | `List values ->
      Buffer.add_char buffer '[';
      add_values values;
      Buffer.add_char buffer ']'
    | `Assoc fields ->
      Buffer.add_char buffer '{';
      add_fields fields;
      Buffer.add_char buffer '}'
  and add_values = function
    | [] -> ()
    | [ value ] -> add value
    | value :: rest ->
      add value;
      Buffer.add_char buffer ',';
      add_values rest
  and add_fields = function
    | [] -> ()
    | [ name, value ] ->
      add_escaped_string buffer name;
      Buffer.add_char buffer ':';
      add value
    | (name, value) :: rest ->
      add_escaped_string buffer name;
      Buffer.add_char buffer ':';
      add value;
      Buffer.add_char buffer ',';
      add_fields rest
  in
  add json;
  Buffer.contents buffer
;;
