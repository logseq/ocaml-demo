module Action = struct
  type 'a t = unit -> 'a

  let ignore () = ()
  let of_thunk f = f
  let many actions () = Stdlib.List.iter (fun action -> Stdlib.ignore (action ())) actions
end

let clipboard_text_for_testing = ref None
let clipboard_image_file_for_testing = ref None
let playing_audio_file_for_testing = ref None
let is_audio_recording_for_testing = ref false

let debug_enabled () =
  match Sys.getenv_opt "BONSAI_NATIVE_LIST_DEBUG" with
  | Some "1" | Some "true" -> true
  | _ -> false
;;

let debug_log format =
  Printf.ksprintf
    (fun message ->
      if debug_enabled ()
      then (
        prerr_endline ("[BonsaiAppleDebug] " ^ message);
        flush stderr))
    format
;;

let debug_time label f =
  let start = Sys.time () in
  let result = f () in
  debug_log "%s cpu_ms=%.2f" label ((Sys.time () -. start) *. 1000.);
  result
;;

type audio_recording_result =
  { transcript : string
  ; local_path : string
  ; filename : string
  ; content_type : string
  ; byte_size : int
  }

let default_clipboard_text_handler text = clipboard_text_for_testing := Some text

let default_clipboard_image_file_handler path =
  clipboard_image_file_for_testing := Some path
;;

let default_toggle_audio_file_playback_handler path =
  playing_audio_file_for_testing
  := match !playing_audio_file_for_testing with
     | Some current when String.equal current path -> None
     | _ -> Some path
;;

let default_audio_recording_result =
  { transcript = "Voice note"
  ; local_path = "/tmp/voice-note.m4a"
  ; filename = "voice-note.m4a"
  ; content_type = "audio/mp4"
  ; byte_size = 42
  }
;;

let default_start_audio_recording_handler () = is_audio_recording_for_testing := true

let default_stop_audio_recording_and_transcribe_handler () =
  is_audio_recording_for_testing := false;
  default_audio_recording_result
;;

let clipboard_text_handler = ref default_clipboard_text_handler
let clipboard_image_file_handler = ref default_clipboard_image_file_handler
let toggle_audio_file_playback_handler = ref default_toggle_audio_file_playback_handler
let start_audio_recording_handler = ref default_start_audio_recording_handler

let stop_audio_recording_and_transcribe_handler =
  ref default_stop_audio_recording_and_transcribe_handler
;;

let copy_text_to_clipboard text () = !clipboard_text_handler text
let copy_image_file_to_clipboard path () = !clipboard_image_file_handler path
let toggle_audio_file_playback path () = !toggle_audio_file_playback_handler path
let start_audio_recording () = !start_audio_recording_handler ()

let stop_audio_recording_and_transcribe () =
  !stop_audio_recording_and_transcribe_handler ()
;;

let set_clipboard_text_handler handler = clipboard_text_handler := handler
let set_clipboard_image_file_handler handler = clipboard_image_file_handler := handler

let set_toggle_audio_file_playback_handler handler =
  toggle_audio_file_playback_handler := handler
;;

let set_audio_recording_handlers ~start ~stop_and_transcribe =
  start_audio_recording_handler := start;
  stop_audio_recording_and_transcribe_handler := stop_and_transcribe
;;

let reset_clipboard_for_testing () =
  clipboard_text_for_testing := None;
  clipboard_image_file_for_testing := None;
  playing_audio_file_for_testing := None;
  is_audio_recording_for_testing := false;
  clipboard_text_handler := default_clipboard_text_handler;
  clipboard_image_file_handler := default_clipboard_image_file_handler;
  toggle_audio_file_playback_handler := default_toggle_audio_file_playback_handler;
  start_audio_recording_handler := default_start_audio_recording_handler;
  stop_audio_recording_and_transcribe_handler
  := default_stop_audio_recording_and_transcribe_handler
;;

type graph = Bonsai_native.graph

let state = Bonsai_native.state
let scope = Bonsai_native.scope

module Option = struct
  include Stdlib.Option

  let map t ~f = map f t
  let bind t ~f = bind t f
  let iter t ~f = iter f t
  let value t ~default = value ~default t

  let is_some = function
    | Some _ -> true
    | None -> false
  ;;

  let to_list = function
    | None -> []
    | Some value -> [ value ]
  ;;
end

module List = struct
  include Stdlib.List

  let map t ~f = map f t
  let mapi t ~f = mapi f t
  let iter t ~f = iter f t
  let filter_map t ~f = filter_map f t
  let filter_opt t = Stdlib.List.filter_map Fun.id t
  let find_map t ~f = find_map f t
  let find t ~f = find_opt f t
  let exists t ~f = exists f t
  let concat_map t ~f = concat_map f t
  let zip_exn left right = combine left right
  let nth t index = nth_opt t index

  let is_empty = function
    | [] -> true
    | _ :: _ -> false
  ;;
end

module Char = struct
  include Stdlib.Char

  let equal = equal
  let to_int = code

  let of_int_exn value =
    match chr value with
    | char -> char
    | exception Invalid_argument _ -> invalid_arg "Char.of_int_exn"
  ;;
end

module Int = struct
  include Stdlib.Int

  module Table = struct
    let create () = Stdlib.Hashtbl.create 16
  end

  module Hash_set = struct
    let create () = Stdlib.Hashtbl.create 16
  end

  let incr = Stdlib.incr

  let of_string_opt value =
    match int_of_string value with
    | value -> Some value
    | exception Failure _ -> None
  ;;
end

module Hashtbl = struct
  include Stdlib.Hashtbl

  let find table key = find_opt table key
  let set table ~key ~data = replace table key data
end

module Hash_set = struct
  let mem = Hashtbl.mem
  let add set value = Hashtbl.replace set value ()
end

module String = struct
  include Stdlib.String

  module Table = struct
    let create () = Stdlib.Hashtbl.create 16
  end

  module Hash_set = struct
    let create () = Stdlib.Hashtbl.create 16
  end

  module Map = struct
    module M = Stdlib.Map.Make (struct
        type t = string

        let compare = compare
      end)

    include M

    let find map key = find_opt key map

    let of_alist_reduce ~f entries =
      List.fold_left
        (fun map (key, value) ->
           update
             key
             (function
               | None -> Some value
               | Some old -> Some (f old value))
             map)
        empty
        entries
    ;;
  end

  let of_char char = make 1 char
  let concat ~sep values = Stdlib.String.concat sep values

  let concat_map value ~f =
    let buffer = Buffer.create (length value) in
    iter (fun char -> Buffer.add_string buffer (f char)) value;
    Buffer.contents buffer
  ;;

  let split ~on value =
    let rec loop start index acc =
      if index = length value
      then List.rev (sub value start (index - start) :: acc)
      else if Stdlib.Char.equal (get value index) on
      then loop (index + 1) (index + 1) (sub value start (index - start) :: acc)
      else loop start (index + 1) acc
    in
    loop 0 0 []
  ;;

  let split_lines value = split ~on:'\n' value

  let lsplit2 value ~on =
    match index_opt value on with
    | None -> None
    | Some index ->
      Some (sub value 0 index, sub value (index + 1) (length value - index - 1))
  ;;
end

module Map = struct
  let find = String.Map.find
end

let sprintf = Printf.sprintf
let failwithf format = Printf.ksprintf (fun message () -> failwith message) format
let quoted value = "\"" ^ String.escaped value ^ "\""

let option_text = function
  | None -> "none"
  | Some value -> quoted value
;;

type edge_insets =
  { top : float
  ; leading : float
  ; bottom : float
  ; trailing : float
  }

type frame =
  { width : float option
  ; height : float option
  ; max_width : float option
  ; alignment : frame_alignment option
  }

and frame_alignment =
  | Center
  | Leading

type row_action_style =
  | Default
  | Destructive

type alert_action_role =
  | Alert_default
  | Alert_cancel
  | Alert_destructive

type alert_action =
  { id : string
  ; title : string
  ; role : alert_action_role
  ; is_enabled : bool
  ; on_click : unit Action.t
  }

type presentation_detent =
  | Medium
  | Large
  | Fraction of float
  | Height of float

type menu_action =
  { id : string
  ; title : string
  ; system_image : string option
  ; style : row_action_style
  ; is_enabled : bool
  ; on_click : unit Action.t
  }

type file_export =
  { filename : string
  ; content_type : string
  ; content : string
  }

type share_link =
  { title : string
  ; url : string
  ; is_enabled : bool
  }

type image_source =
  | System_image
  | File_image

type toolbar_menu_action =
  { title : string
  ; system_image : string option
  ; style : row_action_style
  ; on_click : unit Action.t
  ; file_export : file_export option
  ; starts_section : bool
  }

type toolbar_item =
  { id : string
  ; title : string
  ; system_image : string option
  ; is_title_visible : bool
  ; is_enabled : bool
  ; on_click : unit Action.t
  ; share_url : string option
  ; menu_actions : toolbar_menu_action list
  }

type toolbar_placement =
  | Automatic
  | Bottom_bar

type toolbar_content =
  | Toolbar_group of
      { id : string
      ; placement : toolbar_placement
      ; items : toolbar_item list
      }
  | Toolbar_spacer of
      { id : string
      ; placement : toolbar_placement
      ; fixed : bool
      }

type text_style =
  | Large_title
  | Title
  | Title2
  | Title3
  | Headline
  | Body
  | Callout
  | Subheadline
  | Footnote
  | Caption
  | Caption2

type text_weight =
  | Regular
  | Medium
  | Semibold
  | Bold

type text_color =
  | Primary
  | Secondary
  | Tertiary
  | Red
  | Green
  | Orange
  | Blue
  | Accent

type image =
  { name : string
  ; source : image_source
  ; color : text_color option
  ; max_height : float option
  ; corner_radius : float option
  }

type text_field_style =
  | Rounded_border
  | Pill
  | Plain_text

type text_field_clear_button =
  | No_clear_button
  | While_editing

type button_style =
  | Bordered
  | Bordered_prominent
  | Plain

type text_attributes =
  { style : text_style
  ; weight : text_weight
  ; color : text_color
  }

type row_leading_button =
  { system_image : string
  ; selected_system_image : string option
  ; selected : bool
  ; accessibility_label : string
  ; on_click : unit Action.t
  }

type row_action =
  { title : string
  ; system_image : string option
  ; style : row_action_style
  ; on_click : unit Action.t
  }

type sidebar_action =
  { id : string
  ; title : string
  ; subtitle : string option
  ; system_image : string option
  ; avatar_image : string option
  ; avatar_initial : string option
  ; selects_tab : string option
  ; chrome : sidebar_action_chrome
  ; closes_sidebar : bool
  ; on_click : unit Action.t
  ; menu_actions : row_action list
  }

and sidebar_action_chrome =
  | Default_chrome
  | Prominent_capsule
  | Liquid_icon

type list_row_content_style =
  | Standard
  | Summary
  | Detail

type list_row_accessory =
  | No_accessory
  | Disclosure_indicator

type picker_option =
  { id : string
  ; title : string
  }

type picker_style =
  | Menu
  | Segmented

type image_payload =
  { id : string
  ; local_path : string
  ; mime_type : string
  ; byte_size : int
  ; sha256 : string
  ; width : int
  ; height : int
  ; recognized_text : string option
  }

type list_row =
  { title : string
  ; subtitle : string option
  ; trailing_text : string option
  ; leading_system_image : string option
  ; preview_image_path : string option
  ; content_style : list_row_content_style
  ; accessory : list_row_accessory
  ; title_strikethrough : bool
  ; on_click : unit Action.t option
  ; leading_button : row_leading_button option
  ; swipe_actions : row_action list
  ; menu_actions : row_action list
  }

type tab_role = Search

type rendered_tab =
  { id : string
  ; title : string
  ; system_image : string option
  ; role : tab_role option
  }

type axis =
  | Vertical
  | Horizontal

type horizontal_stack_alignment =
  | Stack_center
  | Stack_top

type backend_kind =
  | Label
  | Button
  | Text_field
  | Text_editor
  | Toggle
  | Stack of axis
  | Z_stack
  | Grid
  | Spacer
  | Divider
  | Form
  | Scroll_view
  | List
  | Movable_rows
  | Navigation_stack
  | Navigation_path_stack
  | Navigation_link
  | Navigation_split
  | Adaptive_layout
  | Tab_view
  | Sidebar_split
  | Image
  | List_row
  | Section
  | Picker
  | Slider
  | Stepper
  | Date_picker
  | Color_picker
  | Menu
  | Disclosure_group
  | Photo_picker
  | Share_link
  | File_exporter
  | File_importer
  | Camera_capture
  | Progress_view
  | Congrats_effect
  | Custom_view of string

type node =
  | Text of
      { text : string
      ; attributes : text_attributes
      }
  | Button_node of
      { title : string
      ; system_image : string option
      ; subtitle : string option
      ; style : button_style
      ; is_title_visible : bool
      ; is_enabled : bool
      ; on_click : unit Action.t
      }
  | Button_label_node of
      { label : node
      ; is_enabled : bool
      ; on_click : unit Action.t
      }
  | Text_field_node of
      { text : string
      ; placeholder : string option
      ; style : text_field_style
      ; axis : axis
      ; clear_button : text_field_clear_button
      ; is_secure : bool
      ; is_focused : bool
      ; on_change : string -> unit Action.t
      ; on_submit : unit Action.t option
      ; on_delete_backward_at_start : unit Action.t option
      }
  | Toggle_node of
      { title : string
      ; is_on : bool
      ; on_change : bool -> unit Action.t
      }
  | Text_editor_node of
      { text : string
      ; placeholder : string option
      ; on_change : string -> unit Action.t
      }
  | Progress_view_node of { value : float }
  | Stack_node of
      { axis : axis
      ; spacing : float option
      ; horizontal_alignment : horizontal_stack_alignment
      ; children : node list
      }
  | Z_stack_node of node list
  | Grid_node of
      { columns : int
      ; spacing : float
      ; children : node list
      }
  | Spacer_node
  | Divider_node
  | Form_node of node list
  | Scroll_view_node of node
  | List_node of
      { rows : keyed_node list
      ; on_refresh : unit Action.t option
      ; on_delete : (int -> unit Action.t) option
      ; on_move : (from_index:int -> to_index:int -> unit Action.t) option
      ; on_focused_row_disappear : unit Action.t option
      ; edit_mode : bool
      ; focused_row_key : string option
      ; focused_row_index : int option
      }
  | Lazy_list_node of
      { length : int
      ; key : int -> string
      ; state_key : (int -> string) option
      ; row : int -> node
      ; on_refresh : unit Action.t option
      ; on_delete : (int -> unit Action.t) option
      ; on_move : (from_index:int -> to_index:int -> unit Action.t) option
      ; on_focused_row_disappear : unit Action.t option
      ; on_rows_published : unit Action.t option
      ; edit_mode : bool
      ; focused_row_key : string option
      ; focused_row_index : int option
      }
  | Movable_rows_node of
      { rows : keyed_node list
      ; on_move : (from_index:int -> to_index:int -> unit Action.t) option
      ; edit_mode : bool
      }
  | Navigation_stack_node of node list
  | Navigation_path_stack_node of
      { path : string list
      ; on_path_change : string list -> unit Action.t
      ; root : node
      ; destinations : keyed_node list
      }
  | Navigation_link_node of
      { label : node
      ; destination : node option
      ; value : string option
      ; on_activate : unit Action.t option
      ; on_deactivate : unit Action.t option
      }
  | Navigation_split_node of
      { sidebar : node
      ; content : node
      ; detail : node
      }
  | Adaptive_layout_node of
      { compact : node
      ; regular : node
      }
  | Tab_view_node of
      { selected : string
      ; on_select : string -> unit Action.t
      ; tabs : tab list
      }
  | Sidebar_split_node of
      { title : string option
      ; compact_top_bar_visible : bool
      ; selected : string
      ; on_select : string -> unit Action.t
      ; tabs : tab list
      ; header_action : sidebar_action option
      ; actions : sidebar_action list
      ; history_title : string option
      ; history_actions : sidebar_action list
      ; bottom_search_placeholder : string option
      ; bottom_search_text : string
      ; bottom_search_on_change : (string -> unit Action.t) option
      ; bottom_action : sidebar_action option
      }
  | Image_node of image
  | List_row_node of list_row
  | Section_node of
      { key : string
      ; title : string option
      ; children : node list
      }
  | Picker_node of
      { title : string
      ; selected : string
      ; style : picker_style
      ; on_select : string -> unit Action.t
      ; options : picker_option list
      }
  | Slider_node of
      { title : string
      ; value : float
      ; min : float
      ; max : float
      ; on_change : float -> unit Action.t
      }
  | Stepper_node of
      { title : string
      ; value : int
      ; min : int
      ; max : int
      ; step : int
      ; on_change : int -> unit Action.t
      }
  | Date_picker_node of
      { title : string
      ; selected : string
      ; on_select : string -> unit Action.t
      }
  | Color_picker_node of
      { title : string
      ; selected : string
      ; on_select : string -> unit Action.t
      }
  | Menu_node of
      { title : string
      ; system_image : string option
      ; actions : menu_action list
      }
  | Disclosure_group_node of
      { title : string
      ; is_expanded : bool
      ; on_change : bool -> unit Action.t
      ; children : node list
      }
  | Photo_picker_node of
      { title : string
      ; system_image : string option
      ; is_title_visible : bool
      ; is_enabled : bool
      ; wants_payload : bool
      ; selected : string option
      ; on_select : string -> unit Action.t
      }
  | Share_link_node of share_link
  | File_exporter_node of
      { title : string
      ; is_enabled : bool
      ; export : file_export
      }
  | File_importer_node of
      { title : string
      ; allowed_content_types : string list
      ; on_select : string -> unit Action.t
      }
  | Camera_capture_node of
      { title : string
      ; wants_payload : bool
      ; captured : string option
      ; on_capture : string -> unit Action.t
      }
  | Congrats_effect_node
  | Custom_view_node of
      { key : string option
      ; kind : string
      ; on_change : (string -> unit Action.t) option
      }
  | Modified_node of modifier * node

and keyed_node =
  { key : string
  ; node : node
  }

and tab =
  { id : string
  ; title : string
  ; system_image : string option
  ; role : tab_role option
  ; content : node
  }

and modifier =
  | Padding of edge_insets
  | Regular_material_panel of { corner_radius : float }
  | Secondary_system_grouped_panel of { corner_radius : float }
  | Secondary_fill_panel of
      { corner_radius : float
      ; opacity : float
      }
  | Liquid_glass_panel of
      { corner_radius : float
      ; is_transparent : bool
      ; tint_color : text_color option
      ; tint_opacity : float
      }
  | Context_menu of row_action list
  | Frame of frame
  | Navigation_title of string
  | Searchable of
      { text : string
      ; is_presented : bool option
      ; prompt : string option
      ; on_change : string -> unit Action.t
      ; on_presented_change : (bool -> unit Action.t) option
      }
  | Toolbar of toolbar_item list
  | Toolbar_groups of toolbar_content list
  | Keyboard_toolbar of toolbar_item list
  | Tap_action of { on_click : unit Action.t }
  | Horizontal_swipe of
      { on_left : unit Action.t
      ; on_right : unit Action.t
      }
  | On_appear of { on_appear : unit Action.t }
  | Keyboard_dismiss_controls
  | Scroll_dismisses_keyboard
  | Hide_list_row_separator
  | Safe_area_inset_bottom of { content : node }
  | Sheet of
      { is_presented : bool
      ; content : node
      ; detents : presentation_detent list
      ; on_dismiss : unit Action.t option
      }
  | Popover of
      { is_presented : bool
      ; content : node
      ; on_dismiss : unit Action.t option
      }
  | Confirmation_dialog of
      { is_presented : bool
      ; title : string
      ; message : string option
      ; actions : alert_action list
      ; on_dismiss : unit Action.t option
      }
  | Alert of
      { is_presented : bool
      ; title : string
      ; message : string option
      ; text : string option
      ; placeholder : string option
      ; on_text_change : (string -> unit Action.t) option
      ; actions : alert_action list
      ; on_dismiss : unit Action.t option
      }

type 'view rendered_modifier =
  | Rendered_padding of edge_insets
  | Rendered_regular_material_panel of { corner_radius : float }
  | Rendered_secondary_system_grouped_panel of { corner_radius : float }
  | Rendered_secondary_fill_panel of
      { corner_radius : float
      ; opacity : float
      }
  | Rendered_liquid_glass_panel of
      { corner_radius : float
      ; is_transparent : bool
      ; tint_color : text_color option
      ; tint_opacity : float
      }
  | Rendered_context_menu of row_action list
  | Rendered_frame of frame
  | Rendered_navigation_title of string
  | Rendered_searchable of
      { text : string
      ; is_presented : bool option
      ; prompt : string option
      ; on_change : string -> unit Action.t
      ; on_presented_change : (bool -> unit Action.t) option
      }
  | Rendered_toolbar of toolbar_item list
  | Rendered_toolbar_groups of toolbar_content list
  | Rendered_keyboard_toolbar of toolbar_item list
  | Rendered_tap_action of { on_click : unit Action.t }
  | Rendered_horizontal_swipe of
      { on_left : unit Action.t
      ; on_right : unit Action.t
      }
  | Rendered_on_appear of { on_appear : unit Action.t }
  | Rendered_keyboard_dismiss_controls
  | Rendered_scroll_dismisses_keyboard
  | Rendered_hide_list_row_separator
  | Rendered_safe_area_inset_bottom of { content : 'view }
  | Rendered_sheet of
      { is_presented : bool
      ; content : 'view option
      ; detents : presentation_detent list
      ; on_dismiss : unit Action.t option
      }
  | Rendered_popover of
      { is_presented : bool
      ; content : 'view option
      ; on_dismiss : unit Action.t option
      }
  | Rendered_confirmation_dialog of
      { is_presented : bool
      ; title : string
      ; message : string option
      ; actions : alert_action list
      ; on_dismiss : unit Action.t option
      }
  | Rendered_alert of
      { is_presented : bool
      ; title : string
      ; message : string option
      ; text : string option
      ; placeholder : string option
      ; on_text_change : (string -> unit Action.t) option
      ; actions : alert_action list
      ; on_dismiss : unit Action.t option
      }

type rendered_row_leading_button =
  { system_image : string
  ; selected_system_image : string option
  ; selected : bool
  ; accessibility_label : string
  ; on_click : unit -> unit
  }

type rendered_row_action =
  { title : string
  ; system_image : string option
  ; style : row_action_style
  ; on_click : unit -> unit
  }

type rendered_sidebar_action =
  { id : string
  ; title : string
  ; subtitle : string option
  ; system_image : string option
  ; avatar_image : string option
  ; avatar_initial : string option
  ; selects_tab : string option
  ; chrome : sidebar_action_chrome
  ; closes_sidebar : bool
  ; on_click : unit -> unit
  ; menu_actions : rendered_row_action list
  }

type rendered_picker_option = picker_option =
  { id : string
  ; title : string
  }

let default_text_attributes = { style = Body; weight = Regular; color = Primary }

let list_row_content_style_name = function
  | Standard -> "standard"
  | Summary -> "summary"
  | Detail -> "detail"
;;

let list_row_accessory_name = function
  | No_accessory -> "no-accessory"
  | Disclosure_indicator -> "disclosure-indicator"
;;

let picker_style_name (style : picker_style) =
  match style with
  | Menu -> "menu"
  | Segmented -> "segmented"
;;

let button_style_name (style : button_style) =
  match style with
  | Bordered -> "bordered"
  | Bordered_prominent -> "bordered-prominent"
  | Plain -> "plain"
;;

let text_style_name = function
  | Large_title -> "large-title"
  | Title -> "title"
  | Title2 -> "title2"
  | Title3 -> "title3"
  | Headline -> "headline"
  | Body -> "body"
  | Callout -> "callout"
  | Subheadline -> "subheadline"
  | Footnote -> "footnote"
  | Caption -> "caption"
  | Caption2 -> "caption2"
;;

let text_weight_name = function
  | Regular -> "regular"
  | Medium -> "medium"
  | Semibold -> "semibold"
  | Bold -> "bold"
;;

let text_color_name = function
  | Primary -> "primary"
  | Secondary -> "secondary"
  | Tertiary -> "tertiary"
  | Red -> "red"
  | Green -> "green"
  | Orange -> "orange"
  | Blue -> "blue"
  | Accent -> "accent"
;;

let sidebar_action_chrome_name = function
  | Default_chrome -> "default"
  | Prominent_capsule -> "prominent-capsule"
  | Liquid_icon -> "liquid-icon"
;;

let text_attributes_name (attributes : text_attributes) =
  text_style_name attributes.style
  ^ ":"
  ^ text_weight_name attributes.weight
  ^ ":"
  ^ text_color_name attributes.color
;;

let text_field_style_name = function
  | Rounded_border -> "rounded-border"
  | Pill -> "pill"
  | Plain_text -> "plain"
;;

let text_field_clear_button_name = function
  | No_clear_button -> "none"
  | While_editing -> "while-editing"
;;

let axis_name = function
  | Vertical -> "vertical"
  | Horizontal -> "horizontal"
;;

let text ?(style = Body) ?(weight = Regular) ?(color = Primary) value =
  Text { text = value; attributes = { style; weight; color } }
;;

let button
      ?(is_enabled = true)
      ?(style = Bordered)
      ?system_image
      ?subtitle
      ?(is_title_visible = true)
      title
      ~on_click
  =
  Button_node
    { title; system_image; subtitle; style; is_title_visible; is_enabled; on_click }
;;

let button_label ?(is_enabled = true) ~on_click label =
  Button_label_node { label; is_enabled; on_click }
;;

let text_field
      ?placeholder
      ?(style = Rounded_border)
      ?(axis = Horizontal)
      ?(clear_button = No_clear_button)
      ?(is_secure = false)
      ?(is_focused = false)
      ?on_submit
      ?on_delete_backward_at_start
      ~text
      ~on_change
      ()
  =
  Text_field_node
    { text
    ; placeholder
    ; style
    ; axis
    ; clear_button
    ; is_secure
    ; is_focused
    ; on_change
    ; on_submit
    ; on_delete_backward_at_start
    }
;;

let toggle title ~is_on ~on_change = Toggle_node { title; is_on; on_change }

let text_editor ?placeholder ~text ~on_change () =
  Text_editor_node { text; placeholder; on_change }
;;

let progress_view ~value = Progress_view_node { value }
let congrats_effect () = Congrats_effect_node
let vstack ?spacing children =
  Stack_node
    { axis = Vertical; spacing; horizontal_alignment = Stack_center; children }
;;

let hstack ?spacing ?(alignment = Stack_center) children =
  Stack_node { axis = Horizontal; spacing; horizontal_alignment = alignment; children }
;;
let zstack children = Z_stack_node children
let grid ?(columns = 2) ?(spacing = 10.) children = Grid_node { columns; spacing; children }
let spacer () = Spacer_node
let divider () = Divider_node
let form children = Form_node children
let scroll_view child = Scroll_view_node child

let list ?on_refresh ?on_delete ?on_move ?on_focused_row_disappear
    ?(edit_mode = false) ?focused_row_key ?focused_row_index rows ~key ~row =
  let seen = String.Hash_set.create () in
  let rows =
    List.map rows ~f:(fun value ->
      let key = key value in
      if Hash_set.mem seen key then failwithf "duplicate Apple list key: %s" key ();
      Hash_set.add seen key;
      { key; node = row value })
  in
  List_node
    {
      rows;
      on_refresh;
      on_delete;
      on_move;
      on_focused_row_disappear;
      edit_mode;
      focused_row_key;
      focused_row_index;
    }
;;

let lazy_list
      ?on_refresh
      ?on_delete
      ?on_move
      ?on_focused_row_disappear
      ?on_rows_published
      ?(edit_mode = false)
      ?focused_row_key
      ?focused_row_index
      ?state_key
      ~length
      ~key
      ~row
      ()
  =
  if length < 0 then invalid_arg "Apple.lazy_list length must be non-negative";
  Lazy_list_node
    {
      length;
      key;
      state_key;
      row;
      on_refresh;
      on_delete;
      on_move;
      on_focused_row_disappear;
      on_rows_published;
      edit_mode;
      focused_row_key;
      focused_row_index;
    }
;;

let movable_rows ?on_move ?(edit_mode = false) rows ~key ~row =
  let seen = String.Hash_set.create () in
  let rows =
    List.map rows ~f:(fun value ->
      let key = key value in
      if Hash_set.mem seen key then failwithf "duplicate Apple movable row key: %s" key ();
      Hash_set.add seen key;
      { key; node = row value })
  in
  Movable_rows_node { rows; on_move; edit_mode }
;;

let section ~key ?title children = Section_node { key; title; children }

let section_key = function
  | Section_node { key; _ } -> key
  | _ -> failwith "Apple.section_key expects a section node"
;;

let picker_option ~id ~title = { id; title }

let row_action ?system_image ?(style = Default) title ~on_click : row_action =
  { title; system_image; style; on_click }
;;

let picker
      ?(style = (Menu : picker_style))
      ~title
      ~selected
      ~on_select
      (options : picker_option list)
  =
  let seen = String.Hash_set.create () in
  List.iter options ~f:(fun option ->
    if Hash_set.mem seen option.id
    then failwithf "duplicate Apple picker option id: %s" option.id ();
    Hash_set.add seen option.id);
  Picker_node { title; selected; style; on_select; options }
;;

let slider ~title ~value ~min ~max ~on_change =
  Slider_node { title; value; min; max; on_change }
;;

let stepper ~title ~value ~min ~max ~step ~on_change =
  Stepper_node { title; value; min; max; step; on_change }
;;

let date_picker ~title ~selected ~on_select =
  Date_picker_node { title; selected; on_select }
;;

let color_picker ~title ~selected ~on_select =
  Color_picker_node { title; selected; on_select }
;;

let menu_action
      ~id
      ~title
      ?system_image
      ?(style = Default)
      ?(is_enabled = true)
      ~on_click
      ()
  =
  { id; title; system_image; style; is_enabled; on_click }
;;

let menu ~title ?system_image (actions : menu_action list) =
  let seen = String.Hash_set.create () in
  List.iter actions ~f:(fun action ->
    if Hash_set.mem seen action.id
    then failwithf "duplicate Apple menu action id: %s" action.id ();
    Hash_set.add seen action.id);
  Menu_node { title; system_image; actions }
;;

let disclosure_group ~title ~is_expanded ~on_change children =
  Disclosure_group_node { title; is_expanded; on_change; children }
;;

let navigation_stack children = Navigation_stack_node children

let navigation_path_stack ~path ~on_path_change ~root ~destinations =
  let seen = String.Hash_set.create () in
  let destinations =
    List.map destinations ~f:(fun (key, node) ->
      if Hash_set.mem seen key
      then failwithf "duplicate Apple navigation destination id: %s" key ();
      Hash_set.add seen key;
      { key; node })
  in
  Navigation_path_stack_node { path; on_path_change; root; destinations }
;;

let navigation_link ?on_activate ?on_deactivate ~destination label =
  Navigation_link_node
    { label; destination = Some destination; value = None; on_activate; on_deactivate }
;;

let navigation_value_link ?on_activate ?on_deactivate ~value label =
  Navigation_link_node
    { label; destination = None; value = Some value; on_activate; on_deactivate }
;;

let navigation_split ~sidebar ~content ~detail =
  Navigation_split_node { sidebar; content; detail }
;;

let adaptive_layout ~compact ~regular = Adaptive_layout_node { compact; regular }

let tab ~id ~title ?system_image ?role content =
  { id; title; system_image; role; content }
;;

let tab_view ~selected ~on_select (tabs : tab list) =
  let seen = String.Hash_set.create () in
  List.iter tabs ~f:(fun tab ->
    if Hash_set.mem seen tab.id then failwithf "duplicate Apple tab id: %s" tab.id ();
    Hash_set.add seen tab.id);
  Tab_view_node { selected; on_select; tabs }
;;

let sidebar_split
      ?title
      ?(compact_top_bar_visible = true)
      ?(header_action : sidebar_action option)
      ?(actions = ([] : sidebar_action list))
      ?history_title
      ?(history_actions = ([] : sidebar_action list))
      ?bottom_search_placeholder
      ?(bottom_search_text = "")
      ?bottom_search_on_change
      ?(bottom_action : sidebar_action option)
      ~selected
      ~on_select
      (tabs : tab list)
  =
  let seen = String.Hash_set.create () in
  List.iter tabs ~f:(fun tab ->
    if Hash_set.mem seen tab.id
    then failwithf "duplicate Apple sidebar route id: %s" tab.id ();
    Hash_set.add seen tab.id);
  let seen_actions = String.Hash_set.create () in
  List.iter
    (Option.to_list header_action
     @ actions
     @ history_actions
     @ Option.to_list bottom_action)
    ~f:(fun action ->
      if Hash_set.mem seen_actions action.id
      then failwithf "duplicate Apple sidebar action id: %s" action.id ();
      Hash_set.add seen_actions action.id);
  Sidebar_split_node
    { title
    ; compact_top_bar_visible
    ; selected
    ; on_select
    ; tabs
    ; header_action
    ; actions
    ; history_title
    ; history_actions
    ; bottom_search_placeholder
    ; bottom_search_text
    ; bottom_search_on_change
    ; bottom_action
    }
;;

let image ?color name =
  Image_node
    { name; source = System_image; color; max_height = None; corner_radius = None }
;;

let image_file ?max_height ?corner_radius path =
  Image_node { name = path; source = File_image; color = None; max_height; corner_radius }
;;

let image_payload_header = "bonsai-image-payload"

let is_unreserved_payload_byte = function
  | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '-' | '_' | '.' | '~' -> true
  | _ -> false
;;

let escape_payload_field value =
  String.concat_map value ~f:(fun char ->
    if is_unreserved_payload_byte char
    then String.of_char char
    else sprintf "%%%02X" (Char.to_int char))
;;

let hex_value = function
  | '0' .. '9' as char -> Some (Char.to_int char - Char.to_int '0')
  | 'a' .. 'f' as char -> Some (10 + Char.to_int char - Char.to_int 'a')
  | 'A' .. 'F' as char -> Some (10 + Char.to_int char - Char.to_int 'A')
  | _ -> None
;;

let unescape_payload_field value =
  let buffer = Buffer.create (String.length value) in
  let rec loop index =
    if index >= String.length value
    then Buffer.contents buffer
    else if Char.equal value.[index] '%' && index + 2 < String.length value
    then (
      match hex_value value.[index + 1], hex_value value.[index + 2] with
      | Some high, Some low ->
        Buffer.add_char buffer (Char.of_int_exn ((high * 16) + low));
        loop (index + 3)
      | _ ->
        Buffer.add_char buffer value.[index];
        loop (index + 1))
    else (
      Buffer.add_char buffer value.[index];
      loop (index + 1))
  in
  loop 0
;;

let image_payload_to_event_text (payload : image_payload) =
  String.concat
    ~sep:"\n"
    ([ image_payload_header
     ; "id=" ^ payload.id
     ; "local_path=" ^ payload.local_path
     ; "mime_type=" ^ payload.mime_type
     ; "byte_size=" ^ Int.to_string payload.byte_size
     ; "sha256=" ^ payload.sha256
     ; "width=" ^ Int.to_string payload.width
     ; "height=" ^ Int.to_string payload.height
     ]
     @
     match payload.recognized_text with
     | None -> []
     | Some text -> [ "recognized_text=" ^ escape_payload_field text ])
;;

let image_payload_of_event_text text =
  match String.split_lines text with
  | header :: fields when String.equal header image_payload_header ->
    let values =
      fields
      |> List.filter_map ~f:(fun line -> String.lsplit2 line ~on:'=')
      |> String.Map.of_alist_reduce ~f:(fun _ latest -> latest)
    in
    let value key = Map.find values key in
    let int_value key = Option.bind (value key) ~f:Int.of_string_opt in
    (match
       ( value "id"
       , value "local_path"
       , value "mime_type"
       , int_value "byte_size"
       , value "sha256"
       , int_value "width"
       , int_value "height" )
     with
     | ( Some id
       , Some local_path
       , Some mime_type
       , Some byte_size
       , Some sha256
       , Some width
       , Some height ) ->
       Some
         { id
         ; local_path
         ; mime_type
         ; byte_size
         ; sha256
         ; width
         ; height
         ; recognized_text =
             Option.map (value "recognized_text") ~f:unescape_payload_field
         }
     | _ -> None)
  | _ -> None
;;

let photo_picker
      ?(is_enabled = true)
      ?system_image
      ?(is_title_visible = true)
      ~title
      ?selected
      ~on_select
      ()
  =
  Photo_picker_node
    { title
    ; system_image
    ; is_title_visible
    ; is_enabled
    ; wants_payload = false
    ; selected
    ; on_select
    }
;;

let legacy_image_payload image_id =
  { id = image_id
  ; local_path = ""
  ; mime_type = ""
  ; byte_size = 0
  ; sha256 = ""
  ; width = 0
  ; height = 0
  ; recognized_text = None
  }
;;

let photo_picker_payload
      ?(is_enabled = true)
      ?system_image
      ?(is_title_visible = true)
      ~title
      ?selected
      ~on_select
      ()
  =
  Photo_picker_node
    { title
    ; system_image
    ; is_title_visible
    ; is_enabled
    ; wants_payload = true
    ; selected
    ; on_select =
        (fun text ->
          let payload =
            image_payload_of_event_text text
            |> Option.value ~default:(legacy_image_payload text)
          in
          on_select payload)
    }
;;

let file_exporter ?(is_enabled = true) ~title ~filename ~content_type ~content () =
  File_exporter_node { title; is_enabled; export = { filename; content_type; content } }
;;

let share_link ?(is_enabled = true) ~title ~url () =
  Share_link_node { title; url; is_enabled }
;;

let file_importer ~title ~allowed_content_types ~on_select () =
  File_importer_node { title; allowed_content_types; on_select }
;;

let camera_capture ~title ?captured ~on_capture () =
  Camera_capture_node { title; wants_payload = false; captured; on_capture }
;;

let camera_capture_payload ~title ?captured ~on_capture () =
  Camera_capture_node
    { title
    ; wants_payload = true
    ; captured
    ; on_capture =
        (fun text ->
          let payload =
            image_payload_of_event_text text
            |> Option.value ~default:(legacy_image_payload text)
          in
          on_capture payload)
    }
;;

let list_row row = List_row_node row
let custom_view ?key ?on_change ~kind () = Custom_view_node { key; kind; on_change }
let default_insets = { top = 8.; leading = 8.; bottom = 8.; trailing = 8. }
let padding ?(insets = default_insets) node = Modified_node (Padding insets, node)

let regular_material_panel ?(corner_radius = 8.) node =
  Modified_node (Regular_material_panel { corner_radius }, node)
;;

let secondary_system_grouped_panel ?(corner_radius = 8.) node =
  Modified_node (Secondary_system_grouped_panel { corner_radius }, node)
;;

let secondary_fill_panel ?(corner_radius = 8.) ?(opacity = 0.12) node =
  Modified_node (Secondary_fill_panel { corner_radius; opacity }, node)
;;

let liquid_glass_panel
      ?(corner_radius = 8.)
      ?(is_transparent = false)
      ?tint_color
      ?(tint_opacity = 0.)
      node
  =
  Modified_node
    (Liquid_glass_panel { corner_radius; is_transparent; tint_color; tint_opacity }, node)
;;

let context_menu actions node = Modified_node (Context_menu actions, node)
let frame ?width ?height ?max_width ?alignment node =
  Modified_node (Frame { width; height; max_width; alignment }, node)
;;

let navigation_title title node = Modified_node (Navigation_title title, node)

let searchable ?is_presented ?on_presented_change ?prompt ~text ~on_change node =
  Modified_node
    (Searchable { text; is_presented; prompt; on_change; on_presented_change }, node)
;;

let toolbar_item
      ?system_image
      ?(is_title_visible = true)
      ?(is_enabled = true)
      ?(menu_actions = [])
      ?share_url
      ~id
      ~title
      ~on_click
      ()
  : toolbar_item
  =
  { id
  ; title
  ; system_image
  ; is_title_visible
  ; is_enabled
  ; on_click
  ; share_url
  ; menu_actions
  }
;;

let toolbar items node = Modified_node (Toolbar items, node)
let toolbar_group ?(placement = Automatic) ~id items =
  Toolbar_group { id; placement; items }
;;

let toolbar_spacer ?(placement = Automatic) ?(fixed = true) ~id () =
  Toolbar_spacer { id; placement; fixed }
;;

let toolbar_groups contents node = Modified_node (Toolbar_groups contents, node)
let keyboard_toolbar items node = Modified_node (Keyboard_toolbar items, node)
let tap_action ~on_click node = Modified_node (Tap_action { on_click }, node)
let horizontal_swipe ~on_left ~on_right node =
  Modified_node (Horizontal_swipe { on_left; on_right }, node)

let on_appear ~on_appear node = Modified_node (On_appear { on_appear }, node)
let keyboard_dismiss_controls node = Modified_node (Keyboard_dismiss_controls, node)
let scroll_dismisses_keyboard node = Modified_node (Scroll_dismisses_keyboard, node)
let hide_list_row_separator node = Modified_node (Hide_list_row_separator, node)

let safe_area_inset_bottom content node =
  Modified_node (Safe_area_inset_bottom { content }, node)
;;

let alert_action ?(role = Alert_default) ?(is_enabled = true) ~id ~title ~on_click () =
  { id; title; role; is_enabled; on_click }
;;

let alert
      ~is_presented
      ~title
      ?message
      ?text
      ?placeholder
      ?on_text_change
      ?(actions = [])
      ?on_dismiss
      ()
      node
  =
  Modified_node
    ( Alert
        { is_presented
        ; title
        ; message
        ; text
        ; placeholder
        ; on_text_change
        ; actions
        ; on_dismiss
        }
    , node )
;;

let sidebar_action
      ~id
      ~title
      ?subtitle
      ?system_image
      ?avatar_image
      ?avatar_initial
      ?selects_tab
      ?(chrome = Default_chrome)
      ?(closes_sidebar = true)
      ~(on_click : unit Action.t)
      ?(menu_actions = [])
      ()
  : sidebar_action
  =
  { id
  ; title
  ; subtitle
  ; system_image
  ; avatar_image
  ; avatar_initial
  ; selects_tab
  ; chrome
  ; closes_sidebar
  ; on_click
  ; menu_actions
  }
;;

let sheet ~is_presented ~content ?(detents = []) ?on_dismiss node =
  Modified_node (Sheet { is_presented; content; detents; on_dismiss }, node)
;;

let popover ~is_presented ~content ?on_dismiss node =
  Modified_node (Popover { is_presented; content; on_dismiss }, node)
;;

let confirmation_dialog ~is_presented ~title ?message ?(actions = []) ?on_dismiss () node =
  Modified_node
    (Confirmation_dialog { is_presented; title; message; actions; on_dismiss }, node)
;;

let rec unwrap_modifiers node =
  match node with
  | Modified_node (modifier, node) ->
    let base, modifiers = unwrap_modifiers node in
    base, modifier :: modifiers
  | node -> node, []
;;

let backend_kind = function
  | Text _ -> Label
  | Button_node _ -> Button
  | Button_label_node _ -> Button
  | Text_field_node _ -> Text_field
  | Toggle_node _ -> Toggle
  | Text_editor_node _ -> Text_editor
  | Progress_view_node _ -> Progress_view
  | Stack_node { axis; _ } -> Stack axis
  | Z_stack_node _ -> Z_stack
  | Grid_node _ -> Grid
  | Spacer_node -> Spacer
  | Divider_node -> Divider
  | Form_node _ -> Form
  | Scroll_view_node _ -> Scroll_view
  | List_node _ -> List
  | Lazy_list_node _ -> List
  | Movable_rows_node _ -> Movable_rows
  | Navigation_stack_node _ -> Navigation_stack
  | Navigation_path_stack_node _ -> Navigation_path_stack
  | Navigation_link_node _ -> Navigation_link
  | Navigation_split_node _ -> Navigation_split
  | Adaptive_layout_node _ -> Adaptive_layout
  | Tab_view_node _ -> Tab_view
  | Sidebar_split_node _ -> Sidebar_split
  | Image_node _ -> Image
  | List_row_node _ -> List_row
  | Section_node _ -> Section
  | Picker_node _ -> Picker
  | Slider_node _ -> Slider
  | Stepper_node _ -> Stepper
  | Date_picker_node _ -> Date_picker
  | Color_picker_node _ -> Color_picker
  | Menu_node _ -> Menu
  | Disclosure_group_node _ -> Disclosure_group
  | Photo_picker_node _ -> Photo_picker
  | Share_link_node _ -> Share_link
  | File_exporter_node _ -> File_exporter
  | File_importer_node _ -> File_importer
  | Camera_capture_node _ -> Camera_capture
  | Custom_view_node { kind; _ } -> Custom_view kind
  | Congrats_effect_node -> Congrats_effect
  | Modified_node _ -> assert false
;;

let equal_backend_kind left right =
  match left, right with
  | Custom_view _, Custom_view _ -> true
  | _ -> left = right
;;
let equal_text_attributes left right = left = right

module Renderer = struct
  module type Backend = sig
    type view

    val create : backend_kind -> view
    val destroy : view -> unit
    val set_text : view -> string -> unit
    val set_system_image : view -> string option -> unit
    val set_image_color : view -> text_color option -> unit

    val set_image_style
      :  view
      -> max_height:float option
      -> corner_radius:float option
      -> unit

    val set_button_subtitle : view -> string option -> unit
    val set_button_style : view -> button_style -> unit
    val set_title_visible : view -> bool -> unit
    val set_text_attributes : view -> text_attributes -> unit
    val set_placeholder : view -> string option -> unit
    val set_text_field_style : view -> text_field_style -> unit
    val set_text_field_axis : view -> axis -> unit
    val set_text_field_clear_button : view -> text_field_clear_button -> unit
    val set_text_field_secure : view -> bool -> unit
    val set_text_field_focus : view -> bool -> unit
    val set_text_field_delete_backward_at_start : view -> (unit -> unit) option -> unit
    val set_toggle : view -> is_on:bool -> on_change:(bool -> unit) -> unit
    val set_progress : view -> value:float -> unit
    val set_spacing : view -> float option -> unit
    val set_horizontal_stack_alignment : view -> horizontal_stack_alignment -> unit
    val set_grid : view -> columns:int -> spacing:float -> unit
    val set_children : view -> keyed:string option list -> view list -> unit

    val set_list_behavior
      :  view
      -> on_refresh:(unit -> unit) option
      -> on_delete:(int -> unit) option
      -> on_move:(from_index:int -> to_index:int -> unit) option
      -> on_focused_row_disappear:(unit -> unit) option
      -> edit_mode:bool
      -> focused_row_key:string option
      -> focused_row_index:int option
      -> unit

    val set_lazy_list_rows
      :  view
      -> length:int
      -> version:int
      -> stale_indices:int list
      -> identity_keys:(int * string) list
      -> cached_rows:(int * string * view) list
      -> key_row:(int -> string)
      -> render_row:(int -> view)
      -> release_row:(int -> unit)
      -> on_rows_published:(unit -> unit) option
      -> unit

    val set_tabs
      :  view
      -> selected:string
      -> on_select:(string -> unit) option
      -> rendered_tab list
      -> unit

    val set_sidebar_shell
      :  view
      -> title:string option
      -> compact_top_bar_visible:bool
      -> header_action:rendered_sidebar_action option
      -> actions:rendered_sidebar_action list
      -> history_title:string option
      -> history_actions:rendered_sidebar_action list
      -> bottom_search_placeholder:string option
      -> bottom_search_text:string
      -> bottom_search_on_change:(string -> unit) option
      -> bottom_action:rendered_sidebar_action option
      -> unit

    val set_list_row
      :  view
      -> title:string
      -> subtitle:string option
      -> trailing_text:string option
      -> leading_system_image:string option
      -> preview_image_path:string option
      -> content_style:list_row_content_style
      -> accessory:list_row_accessory
      -> title_strikethrough:bool
      -> leading_button:rendered_row_leading_button option
      -> swipe_actions:rendered_row_action list
      -> menu_actions:rendered_row_action list
      -> unit

    val refresh_list_row_callbacks
      :  view
      -> on_click:(unit -> unit) option
      -> leading_button:rendered_row_leading_button option
      -> swipe_actions:rendered_row_action list
      -> menu_actions:rendered_row_action list
      -> unit

    val set_navigation_link_callbacks
      :  view
      -> on_activate:(unit -> unit) option
      -> on_deactivate:(unit -> unit) option
      -> unit

    val set_navigation_link_value : view -> string option -> unit
    val set_section : view -> title:string option -> unit

    val set_picker
      :  view
      -> title:string
      -> selected:string
      -> style:picker_style
      -> on_select:(string -> unit) option
      -> rendered_picker_option list
      -> unit

    val set_slider
      :  view
      -> title:string
      -> value:float
      -> min:float
      -> max:float
      -> on_change:(float -> unit) option
      -> unit

    val set_stepper
      :  view
      -> title:string
      -> value:int
      -> min:int
      -> max:int
      -> step:int
      -> on_change:(int -> unit) option
      -> unit

    val set_date_picker
      :  view
      -> title:string
      -> selected:string
      -> on_select:(string -> unit) option
      -> unit

    val set_color_picker
      :  view
      -> title:string
      -> selected:string
      -> on_select:(string -> unit) option
      -> unit

    val set_menu
      :  view
      -> title:string
      -> system_image:string option
      -> actions:menu_action list
      -> schedule_event:(unit Action.t -> unit)
      -> unit

    val set_disclosure_group
      :  view
      -> title:string
      -> is_expanded:bool
      -> on_change:(bool -> unit) option
      -> unit

    val set_navigation_path_stack
      :  view
      -> path:string list
      -> on_path_change:(string list -> unit) option
      -> destinations:string list
      -> unit

    val set_file_exporter : view -> file_export -> unit
    val set_share_link : view -> share_link -> unit

    val set_file_importer
      :  view
      -> allowed_content_types:string list
      -> on_select:(string -> unit) option
      -> unit

    val set_image_payload_mode : view -> bool -> unit
    val set_image_source : view -> image_source -> unit
    val set_on_click : view -> (unit -> unit) option -> unit
    val set_on_change : view -> (string -> unit) option -> unit
    val set_enabled : view -> bool -> unit

    val set_modifiers
      :  view
      -> schedule_event:(unit Action.t -> unit)
      -> view rendered_modifier list
      -> unit
  end

  module Make (Backend : Backend) = struct
    type child =
      { key : string option
      ; mounted : t
      }

    and modifier_child =
      { index : int
      ; mounted : t
      }

    and lazy_row =
      { identity_key : string
      ; state_key : string
      ; mounted : t
      }

    and t =
      { mutable kind : backend_kind
      ; mutable view : Backend.view
      ; mutable fingerprint : string
      ; schedule_event : unit Action.t -> unit
      ; mutable children : child list
      ; mutable modifier_children : modifier_child list
      ; lazy_rows : (int, lazy_row) Hashtbl.t
      ; mutable lazy_list_version : int
      }

    let view t = t.view

    let rec destroy t =
      List.iter t.children ~f:(fun child -> destroy child.mounted);
      List.iter t.modifier_children ~f:(fun child -> destroy child.mounted);
      clear_lazy_rows t;
      Backend.destroy t.view

    and clear_lazy_rows t =
      let rows =
        Hashtbl.fold
          (fun _index (row : lazy_row) rows -> row.mounted :: rows)
          t.lazy_rows
          []
      in
      Hashtbl.clear t.lazy_rows;
      t.lazy_list_version <- 0;
      List.iter rows ~f:destroy
    ;;

    let build_lazy_row_index_by_key t =
      let index_by_key = String.Table.create () in
      Hashtbl.iter
        (fun cached_index (cached : lazy_row) ->
           Hashtbl.set index_by_key ~key:cached.identity_key ~data:cached_index)
        t.lazy_rows;
      index_by_key
    ;;

    let lazy_list_initial_cache_count = 96
    let lazy_list_focused_cache_radius = 0

    let find_lazy_row_by_key lazy_row_index_by_key t ~target_index ~target_key =
      match Hashtbl.find lazy_row_index_by_key target_key with
      | Some cached_index when cached_index <> target_index ->
        (match Hashtbl.find t.lazy_rows cached_index with
         | Some cached when String.equal cached.identity_key target_key ->
           Some (cached_index, cached)
         | Some _ | None -> None)
      | Some _ | None -> None
    ;;

    let rec fingerprint node =
      let node, modifiers = unwrap_modifiers node in
      fingerprint_parts node modifiers

    and fingerprint_parts node modifiers =
      let opt = function
        | None -> "_"
        | Some value -> value
      in
      let bool value = if value then "1" else "0" in
      let float value = string_of_float value in
      let int = string_of_int in
      let list values = "[" ^ String.concat ~sep:"," values ^ "]" in
      let frame_alignment_name = function
        | Center -> "center"
        | Leading -> "leading"
      in
      let horizontal_stack_alignment_name = function
        | Stack_center -> "center"
        | Stack_top -> "top"
      in
      let frame_value ({ width; height; max_width; alignment } : frame) =
        opt (Option.map width ~f:float)
        ^ "x"
        ^ opt (Option.map height ~f:float)
        ^
        (match max_width with
         | None -> ""
         | Some max_width -> ":" ^ float max_width)
        ^
        (match alignment with
         | None -> ""
         | Some alignment -> ":" ^ frame_alignment_name alignment)
      in
      let text_attrs { style; weight; color } =
        string_of_int (Obj.magic style)
        ^ ":"
        ^ string_of_int (Obj.magic weight)
        ^ ":"
        ^ string_of_int (Obj.magic color)
      in
      let role = function
        | None -> "_"
        | Some Search -> "search"
      in
      let toolbar_item_signature (action : toolbar_item) =
        action.id
        ^ ":"
        ^ action.title
        ^ ":"
        ^ opt action.system_image
        ^ ":"
        ^ bool action.is_enabled
        ^ ":"
        ^ opt action.share_url
      in
      let toolbar_placement_signature = function
        | Automatic -> "automatic"
        | Bottom_bar -> "bottom-bar"
      in
      let toolbar_content_signature = function
        | Toolbar_group { id; placement; items } ->
          "group:"
          ^ id
          ^ ":"
          ^ toolbar_placement_signature placement
          ^ ":"
          ^ list (List.map items ~f:toolbar_item_signature)
        | Toolbar_spacer { id; placement; fixed } ->
          "spacer:"
          ^ id
          ^ ":"
          ^ toolbar_placement_signature placement
          ^ ":"
          ^ bool fixed
      in
      let menu_action_signature (action : menu_action) =
        action.id
        ^ ":"
        ^ action.title
        ^ ":"
        ^ opt action.system_image
        ^ ":"
        ^ bool action.is_enabled
      in
      let row_action_signature (action : row_action) =
        action.title
        ^ ":"
        ^ opt action.system_image
        ^ ":"
        ^ string_of_int (Obj.magic action.style)
      in
      let modifier = function
        | Padding insets ->
          "padding:"
          ^ float insets.top
          ^ ":"
          ^ float insets.leading
          ^ ":"
          ^ float insets.bottom
          ^ ":"
          ^ float insets.trailing
        | Regular_material_panel { corner_radius } ->
          "regular-material-panel:" ^ float corner_radius
        | Secondary_system_grouped_panel { corner_radius } ->
          "secondary-system-grouped-panel:" ^ float corner_radius
        | Secondary_fill_panel { corner_radius; opacity } ->
          "secondary-fill-panel:" ^ float corner_radius ^ ":" ^ float opacity
        | Liquid_glass_panel { corner_radius; is_transparent; tint_color; tint_opacity }
          ->
          "liquid-glass-panel:"
          ^ float corner_radius
          ^ ":"
          ^ bool is_transparent
          ^ ":"
          ^ opt (Option.map tint_color ~f:text_color_name)
          ^ ":"
          ^ float tint_opacity
        | Context_menu actions ->
          "context-menu:" ^ list (List.map actions ~f:row_action_signature)
        | Frame frame -> "frame:" ^ frame_value frame
        | Navigation_title title -> "navigation-title:" ^ title
        | Searchable { text; is_presented; prompt; on_change = _; on_presented_change = _ }
          ->
          "searchable:" ^ text ^ ":" ^ opt (Option.map is_presented ~f:bool) ^ ":" ^ opt prompt
        | Toolbar items -> "toolbar:" ^ list (List.map items ~f:toolbar_item_signature)
        | Toolbar_groups contents ->
          "toolbar-groups:" ^ list (List.map contents ~f:toolbar_content_signature)
        | Keyboard_toolbar items ->
          "keyboard-toolbar:" ^ list (List.map items ~f:toolbar_item_signature)
        | Tap_action _ -> "tap-action"
        | Horizontal_swipe _ -> "horizontal-swipe"
        | On_appear _ -> "on-appear"
        | Keyboard_dismiss_controls -> "keyboard-dismiss-controls"
        | Scroll_dismisses_keyboard -> "scroll-dismisses-keyboard"
        | Hide_list_row_separator -> "hide-list-row-separator"
        | Safe_area_inset_bottom { content } ->
          "safe-area-inset-bottom:" ^ fingerprint content
        | Sheet { is_presented; content; detents; on_dismiss = _ } ->
          "sheet:"
          ^ bool is_presented
          ^ ":"
          ^ fingerprint content
          ^ ":"
          ^ int (List.length detents)
        | Popover { is_presented; content; on_dismiss = _ } ->
          "popover:" ^ bool is_presented ^ ":" ^ fingerprint content
        | Confirmation_dialog { is_presented; title; message; actions; on_dismiss = _ } ->
          "confirmation-dialog:"
          ^ bool is_presented
          ^ ":"
          ^ title
          ^ ":"
          ^ opt message
          ^ ":"
          ^ list
              (List.map actions ~f:(fun action ->
                 action.id ^ ":" ^ action.title ^ ":" ^ bool action.is_enabled))
        | Alert
            { is_presented
            ; title
            ; message
            ; text
            ; placeholder
            ; actions
            ; on_text_change = _
            ; on_dismiss = _
            } ->
          "alert:"
          ^ bool is_presented
          ^ ":"
          ^ title
          ^ ":"
          ^ opt message
          ^ ":"
          ^ opt text
          ^ ":"
          ^ opt placeholder
          ^ ":"
          ^ list
              (List.map actions ~f:(fun action ->
                 action.id ^ ":" ^ action.title ^ ":" ^ bool action.is_enabled))
      in
      let shape =
        match node with
        | Text { text; attributes } -> "text:" ^ text ^ ":" ^ text_attrs attributes
        | Button_node
            { title
            ; system_image
            ; subtitle
            ; style
            ; is_title_visible
            ; is_enabled
            ; on_click = _
            } ->
          "button:"
          ^ title
          ^ ":"
          ^ opt system_image
          ^ ":"
          ^ opt subtitle
          ^ ":"
          ^ button_style_name style
          ^ ":"
          ^ bool is_title_visible
          ^ ":"
          ^ bool is_enabled
        | Button_label_node { label; is_enabled; on_click = _ } ->
          "button-label:" ^ bool is_enabled ^ ":" ^ fingerprint label
        | Text_field_node
            { text
            ; placeholder
            ; style
            ; axis
            ; clear_button
            ; is_secure
            ; is_focused
            ; on_change = _
            ; on_submit = _
            ; on_delete_backward_at_start = _
            } ->
          "text-field:"
          ^ text
          ^ ":"
          ^ opt placeholder
          ^ ":"
          ^ text_field_style_name style
          ^ ":"
          ^ axis_name axis
          ^ ":"
          ^ text_field_clear_button_name clear_button
          ^ ":"
          ^ bool is_secure
          ^ ":"
          ^ bool is_focused
        | Toggle_node { title; is_on; on_change = _ } ->
          "toggle:" ^ title ^ ":" ^ bool is_on
        | Text_editor_node { text; placeholder; on_change = _ } ->
          "text-editor:" ^ text ^ ":" ^ opt placeholder
        | Progress_view_node { value } -> "progress-view:" ^ float value
        | Stack_node { axis; spacing; horizontal_alignment; children } ->
          "stack:"
          ^ string_of_int (Obj.magic axis)
          ^ ":"
          ^ opt (Option.map spacing ~f:float)
          ^ ":"
          ^ horizontal_stack_alignment_name horizontal_alignment
          ^ ":"
          ^ list (List.map children ~f:fingerprint)
        | Grid_node { columns; spacing; children } ->
          "grid:"
          ^ string_of_int columns
          ^ ":"
          ^ float spacing
          ^ ":"
          ^ list (List.map children ~f:fingerprint)
        | Z_stack_node children -> "zstack:" ^ list (List.map children ~f:fingerprint)
        | Spacer_node -> "spacer"
        | Divider_node -> "divider"
        | Form_node children -> "form:" ^ list (List.map children ~f:fingerprint)
        | Scroll_view_node child -> "scroll-view:" ^ fingerprint child
        | List_node
            {
              rows;
              on_refresh;
              on_delete;
              on_move;
              on_focused_row_disappear;
              edit_mode;
              focused_row_key;
              focused_row_index;
            } ->
          "list:"
          ^ list (List.map rows ~f:(fun row -> row.key ^ ":" ^ fingerprint row.node))
          ^ ":"
          ^ bool (Option.is_some on_refresh)
          ^ ":"
          ^ bool (Option.is_some on_delete)
          ^ ":"
          ^ bool (Option.is_some on_move)
          ^ ":"
          ^ bool (Option.is_some on_focused_row_disappear)
          ^ ":"
          ^ bool edit_mode
          ^ ":"
          ^ opt focused_row_key
          ^ ":"
          ^ opt (Option.map focused_row_index ~f:string_of_int)
        | Lazy_list_node
            {
              length;
              on_refresh;
              on_delete;
              on_move;
              on_focused_row_disappear;
              on_rows_published;
              edit_mode;
              focused_row_key;
              focused_row_index;
              _;
            } ->
          "lazy-list:"
          ^ string_of_int length
          ^ ":"
          ^ bool (Option.is_some on_refresh)
          ^ ":"
          ^ bool (Option.is_some on_delete)
          ^ ":"
          ^ bool (Option.is_some on_move)
          ^ ":"
          ^ bool (Option.is_some on_focused_row_disappear)
          ^ ":"
          ^ bool (Option.is_some on_rows_published)
          ^ ":"
          ^ bool edit_mode
          ^ ":"
          ^ opt focused_row_key
          ^ ":"
          ^ opt (Option.map focused_row_index ~f:string_of_int)
        | Movable_rows_node { rows; on_move; edit_mode } ->
          "movable-rows:"
          ^ list (List.map rows ~f:(fun row -> row.key ^ ":" ^ fingerprint row.node))
          ^ ":"
          ^ bool (Option.is_some on_move)
          ^ ":"
          ^ bool edit_mode
        | Navigation_stack_node children ->
          "navigation-stack:" ^ list (List.map children ~f:fingerprint)
        | Navigation_path_stack_node { path; root; destinations; on_path_change = _ } ->
          "navigation-path-stack:"
          ^ list path
          ^ ":"
          ^ fingerprint root
          ^ ":"
          ^ list
              (List.map destinations ~f:(fun row -> row.key ^ ":" ^ fingerprint row.node))
        | Navigation_link_node
            { label; destination; value; on_activate = _; on_deactivate = _ } ->
          let destination_signature =
            match destination with
            | Some destination -> fingerprint destination
            | None -> ""
          in
          "navigation-link:"
          ^ opt value
          ^ ":"
          ^ fingerprint label
          ^ ":"
          ^ destination_signature
        | Navigation_split_node { sidebar; content; detail } ->
          "navigation-split:"
          ^ fingerprint sidebar
          ^ ":"
          ^ fingerprint content
          ^ ":"
          ^ fingerprint detail
        | Adaptive_layout_node { compact; regular } ->
          "adaptive-layout:" ^ fingerprint compact ^ ":" ^ fingerprint regular
        | List_row_node row ->
          "list-row:"
          ^ row.title
          ^ ":"
          ^ opt row.subtitle
          ^ ":"
          ^ opt row.trailing_text
          ^ ":"
          ^ opt row.leading_system_image
          ^ ":"
          ^ bool row.title_strikethrough
          ^ ":"
          ^ list (List.map row.swipe_actions ~f:row_action_signature)
          ^ ":"
          ^ list (List.map row.menu_actions ~f:row_action_signature)
        | Section_node { key; title; children } ->
          "section:"
          ^ key
          ^ ":"
          ^ opt title
          ^ ":"
          ^ list (List.map children ~f:fingerprint)
        | Tab_view_node { selected; tabs; on_select = _ } ->
          "tabs:"
          ^ selected
          ^ ":"
          ^ list
              (List.map tabs ~f:(fun tab ->
                 tab.id
                 ^ ":"
                 ^ tab.title
                 ^ ":"
                 ^ opt tab.system_image
                 ^ ":"
                 ^ role tab.role
                 ^ ":"
                 ^ fingerprint tab.content))
        | Sidebar_split_node
            { title
            ; compact_top_bar_visible
            ; selected
            ; tabs
            ; header_action
            ; actions
            ; history_title
            ; history_actions
            ; bottom_search_placeholder
            ; bottom_search_text
            ; bottom_action
            ; on_select = _
            ; bottom_search_on_change = _
            } ->
          "sidebar-tabs:"
          ^ opt title
          ^ ":"
          ^ bool compact_top_bar_visible
          ^ ":"
          ^ selected
          ^ ":"
          ^ list
              (List.map tabs ~f:(fun tab ->
                 tab.id
                 ^ ":"
                 ^ tab.title
                 ^ ":"
                 ^ opt tab.system_image
                 ^ ":"
                 ^ role tab.role
                 ^ ":"
                 ^ fingerprint tab.content))
          ^ ":"
          ^ opt (Option.map header_action ~f:(fun action -> action.id))
          ^ ":"
          ^ list (List.map actions ~f:(fun action -> action.id))
          ^ ":"
          ^ opt history_title
          ^ ":"
          ^ list (List.map history_actions ~f:(fun action -> action.id))
          ^ ":"
          ^ opt bottom_search_placeholder
          ^ ":"
          ^ bottom_search_text
          ^ ":"
          ^ opt (Option.map bottom_action ~f:(fun action -> action.id))
        | Image_node image ->
          "image:"
          ^ image.name
          ^ ":"
          ^ string_of_int (Obj.magic image.source)
          ^ ":"
          ^ opt (Option.map image.color ~f:text_color_name)
          ^ ":"
          ^ opt (Option.map image.max_height ~f:float)
          ^ ":"
          ^ opt (Option.map image.corner_radius ~f:float)
        | Picker_node { title; selected; style; options; on_select = _ } ->
          "picker:"
          ^ title
          ^ ":"
          ^ selected
          ^ ":"
          ^ picker_style_name style
          ^ ":"
          ^ list (List.map options ~f:(fun option -> option.id ^ ":" ^ option.title))
        | Slider_node { title; value; min; max; on_change = _ } ->
          "slider:" ^ title ^ ":" ^ float value ^ ":" ^ float min ^ ":" ^ float max
        | Stepper_node { title; value; min; max; step; on_change = _ } ->
          "stepper:"
          ^ title
          ^ ":"
          ^ int value
          ^ ":"
          ^ int min
          ^ ":"
          ^ int max
          ^ ":"
          ^ int step
        | Date_picker_node { title; selected; on_select = _ } ->
          "date-picker:" ^ title ^ ":" ^ selected
        | Color_picker_node { title; selected; on_select = _ } ->
          "color-picker:" ^ title ^ ":" ^ selected
        | Menu_node { title; system_image; actions } ->
          "menu:"
          ^ title
          ^ ":"
          ^ opt system_image
          ^ ":"
          ^ list (List.map actions ~f:menu_action_signature)
        | Disclosure_group_node { title; is_expanded; children; on_change = _ } ->
          "disclosure-group:"
          ^ title
          ^ ":"
          ^ bool is_expanded
          ^ ":"
          ^ list (List.map children ~f:fingerprint)
        | Photo_picker_node
            { title
            ; system_image
            ; is_title_visible
            ; is_enabled
            ; wants_payload
            ; selected
            ; on_select = _
            } ->
          "photo-picker:"
          ^ title
          ^ ":"
          ^ opt system_image
          ^ ":"
          ^ bool is_title_visible
          ^ ":"
          ^ bool is_enabled
          ^ ":"
          ^ bool wants_payload
          ^ ":"
          ^ opt selected
        | Share_link_node { title; url; is_enabled } ->
          "share-link:" ^ title ^ ":" ^ url ^ ":" ^ bool is_enabled
        | File_exporter_node { title; is_enabled; export } ->
          "file-exporter:"
          ^ title
          ^ ":"
          ^ bool is_enabled
          ^ ":"
          ^ export.filename
          ^ ":"
          ^ export.content_type
          ^ ":"
          ^ export.content
        | File_importer_node { title; allowed_content_types; on_select = _ } ->
          "file-importer:" ^ title ^ ":" ^ list allowed_content_types
        | Camera_capture_node { title; wants_payload; captured; on_capture = _ } ->
          "camera-capture:" ^ title ^ ":" ^ bool wants_payload ^ ":" ^ opt captured
        | Congrats_effect_node -> "congrats-effect"
        | Custom_view_node { key; kind; _ } -> "custom-view:" ^ opt key ^ ":" ^ kind
        | Modified_node _ -> assert false
      in
      shape ^ "|" ^ list (List.map modifiers ~f:modifier)
    ;;

    let rec mount ~schedule_event node =
      let node, modifiers = unwrap_modifiers node in
      let kind = backend_kind node in
      let t =
        { kind
        ; view = Backend.create kind
        ; fingerprint = fingerprint_parts node modifiers
        ; schedule_event
        ; children = []
        ; modifier_children = []
        ; lazy_rows = Hashtbl.create 16
        ; lazy_list_version = 0
        }
      in
      patch_same_kind t node modifiers;
      t

    (* Skipping a patch also skips callback refresh. Only nodes whose callbacks are
       represented in their fingerprint can safely use this path. *)
    and can_skip_patch_when_unchanged = function
      | Text _
      | Image_node _
      | List_row_node _
      | Progress_view_node _
      | Congrats_effect_node
      | Spacer_node
      | Divider_node
      | Custom_view_node _ -> true
      | Button_node _
      | Button_label_node _
      | Text_field_node _
      | Toggle_node _
      | Text_editor_node _
      | Stack_node _
      | Grid_node _
      | Z_stack_node _
      | Form_node _
      | Scroll_view_node _
      | List_node _
      | Lazy_list_node _
      | Movable_rows_node _
      | Navigation_stack_node _
      | Navigation_path_stack_node _
      | Navigation_link_node _
      | Navigation_split_node _
      | Adaptive_layout_node _
      | Section_node _
      | Tab_view_node _
      | Sidebar_split_node _
      | Picker_node _
      | Slider_node _
      | Stepper_node _
      | Date_picker_node _
      | Color_picker_node _
      | Menu_node _
      | Disclosure_group_node _
      | Photo_picker_node _
      | Share_link_node _
      | File_exporter_node _
      | File_importer_node _
      | Camera_capture_node _
      | Modified_node _ -> false

    and patch_same_kind t node modifiers =
      t.fingerprint <- fingerprint_parts node modifiers;
      let replace_children children =
        List.iter t.children ~f:(fun child -> destroy child.mounted);
        t.children <- children;
        Backend.set_children
          t.view
          ~keyed:(List.map children ~f:(fun child -> child.key))
          (List.map children ~f:(fun child -> child.mounted.view))
      in
      let rendered_modifiers = reconcile_modifiers t modifiers in
      (match node with
       | Text { text; attributes } ->
         Backend.set_text t.view text;
         Backend.set_text_attributes t.view attributes;
         Backend.set_on_click t.view None;
         Backend.set_on_change t.view None;
         Backend.set_enabled t.view true;
         replace_children []
       | Button_node
           { title
           ; system_image
           ; subtitle
           ; style
           ; is_title_visible
           ; is_enabled
           ; on_click
           } ->
         Backend.set_text t.view title;
         Backend.set_system_image t.view system_image;
         Backend.set_button_subtitle t.view subtitle;
         Backend.set_button_style t.view style;
         Backend.set_title_visible t.view is_title_visible;
         Backend.set_enabled t.view is_enabled;
         Backend.set_on_click
           t.view
           (if is_enabled then Some (fun () -> t.schedule_event on_click) else None);
         Backend.set_on_change t.view None;
         replace_children []
       | Button_label_node { label; is_enabled; on_click } ->
         Backend.set_text t.view "";
         Backend.set_system_image t.view None;
         Backend.set_button_subtitle t.view None;
         Backend.set_button_style t.view Bordered;
         Backend.set_title_visible t.view true;
         Backend.set_enabled t.view is_enabled;
         Backend.set_on_click
           t.view
           (if is_enabled then Some (fun () -> t.schedule_event on_click) else None);
         Backend.set_on_change t.view None;
         reconcile_positional t [ label ]
       | Text_field_node
           { text
           ; placeholder
           ; style
           ; axis
           ; clear_button
           ; is_secure
           ; is_focused
           ; on_change
           ; on_submit
           ; on_delete_backward_at_start
           } ->
         Backend.set_text t.view text;
         Backend.set_placeholder t.view placeholder;
         Backend.set_text_field_style t.view style;
         Backend.set_text_field_axis t.view axis;
         Backend.set_text_field_clear_button t.view clear_button;
         Backend.set_text_field_secure t.view is_secure;
         Backend.set_text_field_focus t.view is_focused;
         Backend.set_text_field_delete_backward_at_start
           t.view
           (Option.map on_delete_backward_at_start ~f:(fun on_delete ->
              fun () -> t.schedule_event on_delete));
         Backend.set_on_click
           t.view
           (Option.map on_submit ~f:(fun on_submit ->
              fun () -> t.schedule_event on_submit));
         Backend.set_on_change
           t.view
           (Some (fun text -> t.schedule_event (on_change text)));
         replace_children []
       | Toggle_node { title; is_on; on_change } ->
         Backend.set_text t.view title;
         Backend.set_toggle t.view ~is_on ~on_change:(fun is_on ->
           t.schedule_event (on_change is_on));
         replace_children []
       | Text_editor_node { text; placeholder; on_change } ->
         Backend.set_text t.view text;
         Backend.set_placeholder t.view placeholder;
         Backend.set_on_click t.view None;
         Backend.set_on_change
           t.view
           (Some (fun text -> t.schedule_event (on_change text)));
         replace_children []
       | Progress_view_node { value } ->
         Backend.set_progress t.view ~value;
         Backend.set_on_click t.view None;
         Backend.set_on_change t.view None;
         Backend.set_enabled t.view true;
         replace_children []
       | Congrats_effect_node ->
         Backend.set_on_click t.view None;
         Backend.set_on_change t.view None;
         Backend.set_enabled t.view true;
         replace_children []
       | Stack_node { spacing; horizontal_alignment; children; _ } ->
         Backend.set_spacing t.view spacing;
         Backend.set_horizontal_stack_alignment t.view horizontal_alignment;
         Backend.set_on_click t.view None;
         Backend.set_on_change t.view None;
         reconcile_positional t children
       | Grid_node { columns; spacing; children } ->
         Backend.set_grid t.view ~columns ~spacing;
         Backend.set_on_click t.view None;
         Backend.set_on_change t.view None;
         reconcile_positional t children
       | Z_stack_node children ->
         Backend.set_on_click t.view None;
         Backend.set_on_change t.view None;
         reconcile_positional t children
       | Spacer_node | Divider_node ->
         Backend.set_on_click t.view None;
         Backend.set_on_change t.view None;
         replace_children []
       | Form_node children ->
         Backend.set_on_click t.view None;
         Backend.set_on_change t.view None;
         reconcile_positional t children
       | Scroll_view_node child ->
         Backend.set_on_click t.view None;
         Backend.set_on_change t.view None;
         reconcile_positional t [ child ]
       | List_node
           {
             rows;
             on_refresh;
             on_delete;
             on_move;
             on_focused_row_disappear;
             edit_mode;
             focused_row_key;
             focused_row_index;
           } ->
         clear_lazy_rows t;
         let focused_row_index =
           match focused_row_index with
           | Some _ as index -> index
           | None ->
             Option.bind focused_row_key ~f:(fun focused_row_key ->
               rows
               |> List.find_mapi (fun index (row : keyed_node) ->
                 if String.equal row.key focused_row_key then Some index else None))
         in
         Backend.set_on_click t.view None;
         Backend.set_on_change t.view None;
         Backend.set_list_behavior
           t.view
           ~on_refresh:
             (Option.map on_refresh ~f:(fun action -> fun () -> t.schedule_event action))
           ~on_delete:
             (Option.map on_delete ~f:(fun on_delete ->
                fun index -> t.schedule_event (on_delete index)))
           ~on_move:
             (Option.map on_move ~f:(fun on_move ->
                fun ~from_index ~to_index ->
                t.schedule_event (on_move ~from_index ~to_index)))
           ~on_focused_row_disappear:
             (Option.map on_focused_row_disappear ~f:(fun action ->
                fun () -> t.schedule_event action))
           ~edit_mode
           ~focused_row_key
           ~focused_row_index;
         reconcile_keyed t rows
       | Lazy_list_node
           {
             length;
             key;
             state_key;
             row;
             on_refresh;
             on_delete;
             on_move;
             on_focused_row_disappear;
             on_rows_published;
             edit_mode;
             focused_row_key;
             focused_row_index;
           } ->
         debug_log "lazy_list_update_start length=%d cached_rows=%d version=%d"
           length (Hashtbl.length t.lazy_rows) t.lazy_list_version;
         List.iter t.children ~f:(fun child -> destroy child.mounted);
         t.children <- [];
         let row_state_key index =
           match state_key with
           | None -> key index
           | Some state_key -> state_key index
         in
         let lazy_row_index_by_key = build_lazy_row_index_by_key t in
         let stale_indices, order_changed =
           debug_time "lazy_list_stale_scan" (fun () ->
               Hashtbl.fold
                 (fun index cached (stale_indices, order_changed) ->
                    if index >= length then index :: stale_indices, order_changed
                    else
                      let row_key = key index in
                      let row_state_key = row_state_key index in
                      if String.equal cached.identity_key row_key
                         && String.equal cached.state_key row_state_key
                      then stale_indices, order_changed
                      else if String.equal cached.identity_key row_key
                      then index :: stale_indices, order_changed
                      else
                        match
                          find_lazy_row_by_key lazy_row_index_by_key t
                            ~target_index:index ~target_key:row_key
                        with
                        | Some (_, moved) when String.equal moved.state_key row_state_key ->
                          stale_indices, true
                        | Some _ | None -> index :: stale_indices, order_changed)
                 t.lazy_rows
                 ([], false))
         in
         debug_log "lazy_list_stale_indices count=%d order_changed=%b"
           (List.length stale_indices) order_changed;
         let identity_keys = List.init length (fun index -> index, key index) in
         let stale_indices_to_destroy =
           List.filter (fun index -> index < 0 || index >= length) stale_indices
         in
         debug_time "lazy_list_destroy_stale" (fun () ->
             List.iter stale_indices_to_destroy ~f:(fun index ->
                 match Hashtbl.find_opt t.lazy_rows index with
                 | None -> ()
                 | Some cached ->
                   Hashtbl.remove t.lazy_rows index;
                   destroy cached.mounted));
         if order_changed || not (List.is_empty stale_indices) then
           t.lazy_list_version <- t.lazy_list_version + 1;
         let render_row index =
           let row_key = key index in
           let row_state_key = row_state_key index in
           match Hashtbl.find_opt t.lazy_rows index with
           | Some cached
             when String.equal cached.identity_key row_key
                  && String.equal cached.state_key row_state_key ->
             let mounted = cached.mounted in
             update mounted (row index);
             mounted.view
           | cached ->
             (match
                find_lazy_row_by_key lazy_row_index_by_key t ~target_index:index
                  ~target_key:row_key
              with
              | Some (cached_index, cached_row) ->
                let mounted = cached_row.mounted in
                Hashtbl.remove t.lazy_rows cached_index;
                Hashtbl.remove lazy_row_index_by_key row_key;
                Option.iter cached ~f:(fun displaced ->
                    if displaced.mounted != mounted
                    then
                      (Hashtbl.replace t.lazy_rows cached_index
                         displaced;
                       Hashtbl.set lazy_row_index_by_key ~key:displaced.identity_key
                         ~data:cached_index));
                update mounted (row index);
                Hashtbl.replace t.lazy_rows index
                  { identity_key = row_key; state_key = row_state_key; mounted };
                Hashtbl.set lazy_row_index_by_key ~key:row_key ~data:index;
                mounted.view
              | None ->
                Option.iter cached ~f:(fun cached -> destroy cached.mounted);
                let mounted = mount ~schedule_event:t.schedule_event (row index) in
                Hashtbl.replace t.lazy_rows index
                  { identity_key = row_key; state_key = row_state_key; mounted };
                Hashtbl.set lazy_row_index_by_key ~key:row_key ~data:index;
                mounted.view)
         in
         let release_row index =
           match Hashtbl.find_opt t.lazy_rows index with
           | None -> ()
           | Some cached ->
             Hashtbl.remove t.lazy_rows index;
             destroy cached.mounted
         in
         let cached_row_indices = Int.Hash_set.create () in
         let add_cached_row_index index =
           if index >= 0 && index < length then Hash_set.add cached_row_indices index
         in
         List.iter stale_indices ~f:add_cached_row_index;
         if Hashtbl.length t.lazy_rows = 0
         then
           for index = 0 to min (length - 1) (lazy_list_initial_cache_count - 1) do
             add_cached_row_index index
           done;
         Option.iter focused_row_index ~f:(fun index ->
             for row_index =
                   max 0 (index - lazy_list_focused_cache_radius)
                 to
                   min (length - 1) (index + lazy_list_focused_cache_radius)
             do
               add_cached_row_index row_index
             done);
         let cached_rows =
           debug_time "lazy_list_render_cached_rows" (fun () ->
               Hashtbl.fold
                 (fun index () rows ->
                    let row_key = key index in
                    let rendered = render_row index in
                    (index, row_key, rendered) :: rows)
                 cached_row_indices
                 [])
         in
         debug_time "lazy_list_set_handlers" (fun () ->
             Backend.set_on_click t.view None;
             Backend.set_on_change t.view None;
             Backend.set_list_behavior
               t.view
               ~on_refresh:
                 (Option.map on_refresh ~f:(fun action -> fun () -> t.schedule_event action))
               ~on_delete:
                 (Option.map on_delete ~f:(fun on_delete ->
                    fun index -> t.schedule_event (on_delete index)))
               ~on_move:
                 (Option.map on_move ~f:(fun on_move ->
                    fun ~from_index ~to_index ->
                    t.schedule_event (on_move ~from_index ~to_index)))
               ~on_focused_row_disappear:
                 (Option.map on_focused_row_disappear ~f:(fun action ->
                    fun () -> t.schedule_event action))
               ~edit_mode
               ~focused_row_key
               ~focused_row_index);
         debug_time "lazy_list_set_rows" (fun () ->
             Backend.set_lazy_list_rows t.view ~length ~version:t.lazy_list_version
               ~stale_indices
               ~identity_keys
               ~cached_rows
               ~key_row:key
               ~render_row ~release_row
               ~on_rows_published:
                 (Option.map on_rows_published ~f:(fun action ->
                    fun () -> t.schedule_event action)));
         debug_log "lazy_list_update_end length=%d cached_rows=%d version=%d"
           length (Hashtbl.length t.lazy_rows) t.lazy_list_version
       | Movable_rows_node { rows; on_move; edit_mode } ->
         clear_lazy_rows t;
         Backend.set_on_click t.view None;
         Backend.set_on_change t.view None;
         Backend.set_list_behavior
           t.view
           ~on_refresh:None
           ~on_delete:None
           ~on_move:
             (Option.map on_move ~f:(fun on_move ->
                fun ~from_index ~to_index ->
                t.schedule_event (on_move ~from_index ~to_index)))
           ~on_focused_row_disappear:None
           ~edit_mode
           ~focused_row_key:None
           ~focused_row_index:None;
         reconcile_keyed t rows
       | Navigation_stack_node children ->
         Backend.set_on_click t.view None;
         Backend.set_on_change t.view None;
         reconcile_positional t children
       | Navigation_path_stack_node { path; on_path_change; root; destinations } ->
         Backend.set_on_click t.view None;
         Backend.set_on_change t.view None;
         Backend.set_navigation_path_stack
           t.view
           ~path
           ~on_path_change:(Some (fun path -> t.schedule_event (on_path_change path)))
           ~destinations:(List.map destinations ~f:(fun destination -> destination.key));
         reconcile_keyed t ({ key = "__root__"; node = root } :: destinations)
       | Navigation_link_node { label; destination; value; on_activate; on_deactivate } ->
         Backend.set_on_click t.view None;
         Backend.set_on_change t.view None;
         Backend.set_navigation_link_value t.view value;
         Backend.set_navigation_link_callbacks
           t.view
           ~on_activate:
             (Option.map on_activate ~f:(fun action -> fun () -> t.schedule_event action))
           ~on_deactivate:
             (Option.map on_deactivate ~f:(fun action ->
                fun () -> t.schedule_event action));
         reconcile_positional t (label :: Option.to_list destination)
       | Navigation_split_node { sidebar; content; detail } ->
         Backend.set_on_click t.view None;
         Backend.set_on_change t.view None;
         reconcile_positional t [ sidebar; content; detail ]
       | Adaptive_layout_node { compact; regular } ->
         Backend.set_on_click t.view None;
         Backend.set_on_change t.view None;
         reconcile_positional t [ compact; regular ]
       | Tab_view_node { selected; on_select; tabs } ->
         Backend.set_on_click t.view None;
         Backend.set_on_change t.view None;
         reconcile_tabs t ~selected ~on_select tabs
       | Sidebar_split_node
           { title
           ; compact_top_bar_visible
           ; selected
           ; on_select
           ; tabs
           ; header_action
           ; actions
           ; history_title
           ; history_actions
           ; bottom_search_placeholder
           ; bottom_search_text
           ; bottom_search_on_change
           ; bottom_action
           } ->
         Backend.set_on_click t.view None;
         Backend.set_on_change t.view None;
         reconcile_tabs t ~selected ~on_select tabs;
         let render_action (action : sidebar_action) =
           { id = action.id
           ; title = action.title
           ; subtitle = action.subtitle
           ; system_image = action.system_image
           ; avatar_image = action.avatar_image
           ; avatar_initial = action.avatar_initial
           ; selects_tab = action.selects_tab
           ; chrome = action.chrome
           ; closes_sidebar = action.closes_sidebar
           ; on_click = (fun () -> t.schedule_event action.on_click)
           ; menu_actions =
               List.map action.menu_actions ~f:(fun menu_action ->
                 { title = menu_action.title
                 ; system_image = menu_action.system_image
                 ; style = menu_action.style
                 ; on_click = (fun () -> t.schedule_event menu_action.on_click)
                 })
           }
         in
         Backend.set_sidebar_shell
           t.view
           ~title
           ~compact_top_bar_visible
           ~header_action:(Option.map header_action ~f:render_action)
           ~actions:(List.map actions ~f:render_action)
           ~history_title
           ~history_actions:(List.map history_actions ~f:render_action)
           ~bottom_search_placeholder
           ~bottom_search_text
           ~bottom_search_on_change:
             (Option.map bottom_search_on_change ~f:(fun on_change ->
                fun text -> t.schedule_event (on_change text)))
           ~bottom_action:(Option.map bottom_action ~f:render_action)
       | Image_node { name; source; color; max_height; corner_radius } ->
         Backend.set_text t.view name;
         Backend.set_image_source t.view source;
         Backend.set_image_color t.view color;
         Backend.set_image_style t.view ~max_height ~corner_radius;
         Backend.set_on_click t.view None;
         Backend.set_on_change t.view None;
         replace_children []
       | List_row_node
           { title
           ; subtitle
           ; trailing_text
           ; leading_system_image
           ; preview_image_path
           ; content_style
           ; accessory
           ; title_strikethrough
           ; on_click
           ; leading_button
           ; swipe_actions
           ; menu_actions
           } ->
         Backend.set_list_row
           t.view
           ~title
           ~subtitle
           ~trailing_text
           ~leading_system_image
           ~preview_image_path
           ~content_style
           ~accessory
           ~title_strikethrough
           ~leading_button:
             (Option.map leading_button ~f:(fun leading_button ->
                { system_image = leading_button.system_image
                ; selected_system_image = leading_button.selected_system_image
                ; selected = leading_button.selected
                ; accessibility_label = leading_button.accessibility_label
                ; on_click = (fun () -> t.schedule_event leading_button.on_click)
                }))
           ~swipe_actions:
             (List.map swipe_actions ~f:(fun action ->
                { title = action.title
                ; system_image = action.system_image
                ; style = action.style
                ; on_click = (fun () -> t.schedule_event action.on_click)
                }))
           ~menu_actions:
             (List.map menu_actions ~f:(fun action ->
                { title = action.title
                ; system_image = action.system_image
                ; style = action.style
                ; on_click = (fun () -> t.schedule_event action.on_click)
                }));
         Backend.set_on_click
           t.view
           (Option.map on_click ~f:(fun on_click -> fun () -> t.schedule_event on_click));
         Backend.set_on_change t.view None;
         replace_children []
       | Section_node { key = _; title; children } ->
         Backend.set_section t.view ~title;
         Backend.set_on_click t.view None;
         Backend.set_on_change t.view None;
         reconcile_positional t children
       | Picker_node { title; selected; style; on_select; options } ->
         Backend.set_picker
           t.view
           ~title
           ~selected
           ~style
           ~on_select:(Some (fun id -> t.schedule_event (on_select id)))
           options;
         Backend.set_on_click t.view None;
         Backend.set_on_change t.view None;
         replace_children []
       | Slider_node { title; value; min; max; on_change } ->
         Backend.set_slider
           t.view
           ~title
           ~value
           ~min
           ~max
           ~on_change:(Some (fun value -> t.schedule_event (on_change value)));
         Backend.set_on_click t.view None;
         replace_children []
       | Stepper_node { title; value; min; max; step; on_change } ->
         Backend.set_stepper
           t.view
           ~title
           ~value
           ~min
           ~max
           ~step
           ~on_change:(Some (fun value -> t.schedule_event (on_change value)));
         Backend.set_on_click t.view None;
         replace_children []
       | Date_picker_node { title; selected; on_select } ->
         Backend.set_date_picker
           t.view
           ~title
           ~selected
           ~on_select:(Some (fun selected -> t.schedule_event (on_select selected)));
         Backend.set_on_click t.view None;
         replace_children []
       | Color_picker_node { title; selected; on_select } ->
         Backend.set_color_picker
           t.view
           ~title
           ~selected
           ~on_select:(Some (fun selected -> t.schedule_event (on_select selected)));
         Backend.set_on_click t.view None;
         replace_children []
       | Menu_node { title; system_image; actions } ->
         Backend.set_menu
           t.view
           ~title
           ~system_image
           ~actions
           ~schedule_event:t.schedule_event;
         Backend.set_on_click t.view None;
         Backend.set_on_change t.view None;
         replace_children []
       | Disclosure_group_node { title; is_expanded; on_change; children } ->
         Backend.set_disclosure_group
           t.view
           ~title
           ~is_expanded
           ~on_change:(Some (fun is_expanded -> t.schedule_event (on_change is_expanded)));
         Backend.set_on_click t.view None;
         reconcile_positional t children
       | Photo_picker_node
           { title
           ; system_image
           ; is_title_visible
           ; is_enabled
           ; wants_payload
           ; selected
           ; on_select
           } ->
         Backend.set_text t.view title;
         Backend.set_system_image t.view system_image;
         Backend.set_title_visible t.view is_title_visible;
         Backend.set_enabled t.view is_enabled;
         Backend.set_image_payload_mode t.view wants_payload;
         Backend.set_placeholder t.view selected;
         Backend.set_on_click t.view None;
         Backend.set_on_change
           t.view
           (if is_enabled
            then Some (fun image_id -> t.schedule_event (on_select image_id))
            else None);
         replace_children []
       | File_exporter_node { title; is_enabled; export } ->
         Backend.set_text t.view title;
         Backend.set_enabled t.view is_enabled;
         Backend.set_file_exporter t.view export;
         Backend.set_on_click t.view None;
         Backend.set_on_change t.view None;
         replace_children []
       | Share_link_node share ->
         Backend.set_text t.view share.title;
         Backend.set_enabled t.view share.is_enabled;
         Backend.set_share_link t.view share;
         Backend.set_on_click t.view None;
         Backend.set_on_change t.view None;
         replace_children []
       | File_importer_node { title; allowed_content_types; on_select } ->
         Backend.set_text t.view title;
         Backend.set_file_importer
           t.view
           ~allowed_content_types
           ~on_select:(Some (fun content -> t.schedule_event (on_select content)));
         Backend.set_on_click t.view None;
         replace_children []
       | Camera_capture_node { title; wants_payload; captured; on_capture } ->
         Backend.set_text t.view title;
         Backend.set_image_payload_mode t.view wants_payload;
         Backend.set_placeholder t.view captured;
         Backend.set_on_click t.view None;
         Backend.set_on_change
           t.view
           (Some (fun image_id -> t.schedule_event (on_capture image_id)));
         replace_children []
       | Custom_view_node { kind; on_change; _ } ->
         Backend.set_text t.view kind;
         Backend.set_on_click t.view None;
         Backend.set_on_change
           t.view
           (Option.map on_change ~f:(fun on_change message ->
              t.schedule_event (on_change message)));
         replace_children []
       | Modified_node _ -> assert false);
      Backend.set_modifiers t.view ~schedule_event:t.schedule_event rendered_modifiers

    and rendered_list_row_callbacks
          t
          ~on_click
          ~(leading_button : row_leading_button option)
          ~(swipe_actions : row_action list)
          ~(menu_actions : row_action list)
      =
      ( Option.map leading_button ~f:(fun leading_button ->
          { system_image = leading_button.system_image
          ; selected_system_image = leading_button.selected_system_image
          ; selected = leading_button.selected
          ; accessibility_label = leading_button.accessibility_label
          ; on_click = (fun () -> t.schedule_event leading_button.on_click)
          })
      , List.map swipe_actions ~f:(fun action ->
          { title = action.title
          ; system_image = action.system_image
          ; style = action.style
          ; on_click = (fun () -> t.schedule_event action.on_click)
          })
      , List.map menu_actions ~f:(fun action ->
          { title = action.title
          ; system_image = action.system_image
          ; style = action.style
          ; on_click = (fun () -> t.schedule_event action.on_click)
          })
      , Option.map on_click ~f:(fun on_click -> fun () -> t.schedule_event on_click) )

    and refresh_callbacks t node =
      match node with
      | List_row_node { on_click; leading_button; swipe_actions; menu_actions; _ } ->
        let leading_button, swipe_actions, menu_actions, on_click =
          rendered_list_row_callbacks
            t
            ~on_click
            ~leading_button
            ~swipe_actions
            ~menu_actions
        in
        Backend.refresh_list_row_callbacks
          t.view
          ~on_click
          ~leading_button
          ~swipe_actions
          ~menu_actions
      | _ -> ()

    and update t node =
      let node, modifiers = unwrap_modifiers node in
      let new_kind = backend_kind node in
      if equal_backend_kind t.kind new_kind
      then patch_same_kind t node modifiers
      else (
        destroy t;
        let replacement = mount ~schedule_event:t.schedule_event node in
        t.kind <- replacement.kind;
        t.view <- replacement.view;
        t.fingerprint <- replacement.fingerprint;
        t.children <- replacement.children;
        t.modifier_children <- replacement.modifier_children)

    and patch_child ~schedule_event existing node =
      let original_node = node in
      let base_node, modifiers = unwrap_modifiers node in
      let new_kind = backend_kind base_node in
      let next_fingerprint = fingerprint_parts base_node modifiers in
      match existing with
      | Some child
        when equal_backend_kind child.mounted.kind new_kind
             && can_skip_patch_when_unchanged base_node
             && String.equal child.mounted.fingerprint next_fingerprint ->
        refresh_callbacks child.mounted base_node;
        child.mounted
      | Some child when equal_backend_kind child.mounted.kind new_kind ->
        patch_same_kind child.mounted base_node modifiers;
        child.mounted
      | Some child ->
        destroy child.mounted;
        mount ~schedule_event original_node
      | None -> mount ~schedule_event original_node

    and reconcile_modifiers t modifiers =
      let old_by_index = Int.Table.create () in
      List.iter t.modifier_children ~f:(fun child ->
        Hashtbl.set old_by_index ~key:child.index ~data:child);
      let used = Int.Hash_set.create () in
      let next_modifier_children = ref [] in
      let rendered_modifiers =
        List.mapi modifiers ~f:(fun index modifier ->
          match modifier with
          | Padding insets -> Rendered_padding insets
          | Regular_material_panel { corner_radius } ->
            Rendered_regular_material_panel { corner_radius }
          | Secondary_system_grouped_panel { corner_radius } ->
            Rendered_secondary_system_grouped_panel { corner_radius }
          | Secondary_fill_panel { corner_radius; opacity } ->
            Rendered_secondary_fill_panel { corner_radius; opacity }
          | Liquid_glass_panel { corner_radius; is_transparent; tint_color; tint_opacity }
            ->
            Rendered_liquid_glass_panel
              { corner_radius; is_transparent; tint_color; tint_opacity }
          | Context_menu actions -> Rendered_context_menu actions
          | Frame frame -> Rendered_frame frame
          | Navigation_title title -> Rendered_navigation_title title
          | Searchable { text; is_presented; prompt; on_change; on_presented_change } ->
            Rendered_searchable { text; is_presented; prompt; on_change; on_presented_change }
          | Toolbar items -> Rendered_toolbar items
          | Toolbar_groups contents -> Rendered_toolbar_groups contents
          | Keyboard_toolbar items -> Rendered_keyboard_toolbar items
          | Tap_action { on_click } -> Rendered_tap_action { on_click }
          | Horizontal_swipe { on_left; on_right } ->
            Rendered_horizontal_swipe { on_left; on_right }
          | On_appear { on_appear } -> Rendered_on_appear { on_appear }
          | Keyboard_dismiss_controls -> Rendered_keyboard_dismiss_controls
          | Scroll_dismisses_keyboard -> Rendered_scroll_dismisses_keyboard
          | Hide_list_row_separator -> Rendered_hide_list_row_separator
          | Safe_area_inset_bottom { content } ->
            Hash_set.add used index;
            let existing =
              Hashtbl.find old_by_index index
              |> Option.map ~f:(fun (child : modifier_child) ->
                ({ key = None; mounted = child.mounted } : child))
            in
            let mounted = patch_child ~schedule_event:t.schedule_event existing content in
            next_modifier_children := { index; mounted } :: !next_modifier_children;
            Rendered_safe_area_inset_bottom { content = mounted.view }
          | Sheet { is_presented; content; detents; on_dismiss } ->
            let content =
              if is_presented
              then (
                Hash_set.add used index;
                let existing =
                  Hashtbl.find old_by_index index
                  |> Option.map ~f:(fun (child : modifier_child) ->
                    ({ key = None; mounted = child.mounted } : child))
                in
                let mounted =
                  patch_child ~schedule_event:t.schedule_event existing content
                in
                next_modifier_children := { index; mounted } :: !next_modifier_children;
                Some mounted.view)
              else None
            in
            Rendered_sheet { is_presented; content; detents; on_dismiss }
          | Popover { is_presented; content; on_dismiss } ->
            let content =
              if is_presented
              then (
                Hash_set.add used index;
                let existing =
                  Hashtbl.find old_by_index index
                  |> Option.map ~f:(fun (child : modifier_child) ->
                    ({ key = None; mounted = child.mounted } : child))
                in
                let mounted =
                  patch_child ~schedule_event:t.schedule_event existing content
                in
                next_modifier_children := { index; mounted } :: !next_modifier_children;
                Some mounted.view)
              else None
            in
            Rendered_popover { is_presented; content; on_dismiss }
          | Confirmation_dialog { is_presented; title; message; actions; on_dismiss } ->
            Rendered_confirmation_dialog
              { is_presented; title; message; actions; on_dismiss }
          | Alert
              { is_presented
              ; title
              ; message
              ; text
              ; placeholder
              ; on_text_change
              ; actions
              ; on_dismiss
              } ->
            Rendered_alert
              { is_presented
              ; title
              ; message
              ; text
              ; placeholder
              ; on_text_change
              ; actions
              ; on_dismiss
              })
      in
      List.iter t.modifier_children ~f:(fun child ->
        if not (Hash_set.mem used child.index) then destroy child.mounted);
      t.modifier_children <- List.rev !next_modifier_children;
      rendered_modifiers

    and reconcile_positional t nodes =
      let rec loop old_children nodes =
        match old_children, nodes with
        | [], [] -> []
        | old_child :: old_tail, node :: node_tail ->
          { key = None
          ; mounted = patch_child ~schedule_event:t.schedule_event (Some old_child) node
          }
          :: loop old_tail node_tail
        | [], node :: node_tail ->
          { key = None; mounted = mount ~schedule_event:t.schedule_event node }
          :: loop [] node_tail
        | old_child :: old_tail, [] ->
          destroy old_child.mounted;
          loop old_tail []
      in
      t.children <- loop t.children nodes;
      Backend.set_children
        t.view
        ~keyed:(List.map t.children ~f:(fun child -> child.key))
        (List.map t.children ~f:(fun child -> child.mounted.view))

    and reconcile_keyed t rows =
      let old_by_key = String.Table.create () in
      List.iter t.children ~f:(fun child ->
        Option.iter child.key ~f:(fun key -> Hashtbl.set old_by_key ~key ~data:child));
      let used = String.Hash_set.create () in
      let children =
        List.map rows ~f:(fun row ->
          Hash_set.add used row.key;
          let old_child = Hashtbl.find old_by_key row.key in
          { key = Some row.key
          ; mounted = patch_child ~schedule_event:t.schedule_event old_child row.node
          })
      in
      List.iter t.children ~f:(fun child ->
        match child.key with
        | Some key when Hash_set.mem used key -> ()
        | _ -> destroy child.mounted);
      t.children <- children;
      Backend.set_children
        t.view
        ~keyed:(List.map children ~f:(fun child -> child.key))
        (List.map children ~f:(fun child -> child.mounted.view))

    and reconcile_tabs t ~selected ~on_select tabs =
      let rows = List.map tabs ~f:(fun tab -> { key = tab.id; node = tab.content }) in
      let rendered_tabs =
        List.map tabs ~f:(fun tab ->
          { id = tab.id
          ; title = tab.title
          ; system_image = tab.system_image
          ; role = tab.role
          })
      in
      reconcile_keyed t rows;
      Backend.set_tabs
        t.view
        ~selected
        ~on_select:(Some (fun id -> t.schedule_event (on_select id)))
        rendered_tabs
    ;;
  end
end

module App = struct
  module Make (Backend : Renderer.Backend) = struct
    module R = Renderer.Make (Backend)

    type t = (node, R.t) Bonsai_native.App_driver.t

    let create component =
      Bonsai_native.App_driver.create
        component
        ~render:(fun ~schedule_event node -> R.mount ~schedule_event node)
        ~update:(fun mounted ~schedule_event:_ node ->
          R.update mounted node;
          mounted)
    ;;

    let flush_and_render = Bonsai_native.App_driver.flush_and_render
    let view t = Option.map (Bonsai_native.App_driver.rendered t) ~f:R.view
  end
end

module For_testing = struct
  module Backend = struct
    module Stats = struct
      type t =
        { created : int
        ; destroyed : int
        ; mutations : int
        }
    end

    type view =
      { id : int
      ; kind : backend_kind
      ; mutable text : string option
      ; mutable system_image : string option
      ; mutable image_color : text_color option
      ; mutable button_subtitle : string option
      ; mutable button_style : button_style
      ; mutable is_title_visible : bool
      ; mutable text_attributes : text_attributes
      ; mutable placeholder : string option
      ; mutable text_field_style : text_field_style
      ; mutable text_field_axis : axis
      ; mutable text_field_clear_button : text_field_clear_button
      ; mutable text_field_secure : bool
      ; mutable text_field_focused : bool
      ; mutable on_text_delete_backward_at_start : (unit -> unit) option
      ; mutable toggle_is_on : bool
      ; mutable progress_value : float option
      ; mutable grid_columns : int option
      ; mutable grid_spacing : float option
      ; mutable slider_value : float option
      ; mutable slider_range : (float * float) option
      ; mutable on_slider_change : (float -> unit) option
      ; mutable stepper_value : int option
      ; mutable stepper_range : (int * int) option
      ; mutable stepper_step : int option
      ; mutable on_stepper_change : (int -> unit) option
      ; mutable horizontal_stack_alignment : horizontal_stack_alignment
      ; mutable selected_date : string option
      ; mutable on_select_date : (string -> unit) option
      ; mutable selected_color : string option
      ; mutable on_select_color : (string -> unit) option
      ; mutable menu_actions : menu_action list
      ; mutable context_menu_actions : row_action list
      ; mutable disclosure_is_expanded : bool
      ; mutable on_disclosure_change : (bool -> unit) option
      ; mutable children : (string option * view) list
      ; mutable is_enabled : bool
      ; mutable on_click : (unit -> unit) option
      ; mutable on_change : (string -> unit) option
      ; mutable on_toggle : (bool -> unit) option
      ; mutable on_list_refresh : (unit -> unit) option
      ; mutable on_list_delete : (int -> unit) option
      ; mutable on_list_move : (from_index:int -> to_index:int -> unit) option
      ; mutable on_focused_row_disappear : (unit -> unit) option
      ; mutable list_edit_mode : bool
      ; mutable list_focused_row_key : string option
      ; mutable list_focused_row_index : int option
      ; mutable on_navigation_activate : (unit -> unit) option
      ; mutable on_navigation_deactivate : (unit -> unit) option
      ; mutable navigation_path : string list
      ; mutable navigation_destinations : string list
      ; mutable on_navigation_path_change : (string list -> unit) option
      ; mutable navigation_is_active : bool
      ; mutable selected_tab : string option
      ; mutable on_select_tab : (string -> unit) option
      ; mutable tabs : rendered_tab list
      ; mutable sidebar_title : string option
      ; mutable sidebar_compact_top_bar_visible : bool
      ; mutable sidebar_header_action : rendered_sidebar_action option
      ; mutable sidebar_actions : rendered_sidebar_action list
      ; mutable sidebar_history_title : string option
      ; mutable sidebar_history_actions : rendered_sidebar_action list
      ; mutable sidebar_bottom_search_placeholder : string option
      ; mutable sidebar_bottom_search_text : string
      ; mutable sidebar_bottom_search_on_change : (string -> unit) option
      ; mutable sidebar_bottom_action : rendered_sidebar_action option
      ; mutable section_title : string option
      ; mutable picker_title : string option
      ; mutable picker_selected : string option
      ; mutable picker_style : picker_style
      ; mutable on_select_picker : (string -> unit) option
      ; mutable picker_options : rendered_picker_option list
      ; mutable share_link : share_link option
      ; mutable file_export : file_export option
      ; mutable allowed_content_types : string list
      ; mutable on_import_file : (string -> unit) option
      ; mutable wants_image_payload : bool
      ; mutable image_source : image_source
      ; mutable image_max_height : float option
      ; mutable image_corner_radius : float option
      ; mutable list_row : string option
      ; mutable row_leading_button : rendered_row_leading_button option
      ; mutable row_actions : rendered_row_action list
      ; mutable row_menu_actions : rendered_row_action list
      ; mutable modifiers : view rendered_modifier list
      ; mutable schedule_event : (unit Action.t -> unit) option
      ; mutable on_appear : (unit -> unit) option
      }

    let next_id = ref 0
    let created = ref 0
    let destroyed = ref 0
    let mutations = ref 0

    let reset () =
      next_id := 0;
      created := 0;
      destroyed := 0;
      mutations := 0;
      reset_clipboard_for_testing ()
    ;;

    let clipboard_text () = !clipboard_text_for_testing
    let clipboard_image_file () = !clipboard_image_file_for_testing
    let playing_audio_file () = !playing_audio_file_for_testing
    let is_audio_recording () = !is_audio_recording_for_testing

    let stats () : Stats.t =
      { created = !created; destroyed = !destroyed; mutations = !mutations }
    ;;

    let diff_stats (before : Stats.t) (after : Stats.t) : Stats.t =
      { created = after.created - before.created
      ; destroyed = after.destroyed - before.destroyed
      ; mutations = after.mutations - before.mutations
      }
    ;;

    let mutate () = Int.incr mutations

    let create kind =
      Int.incr next_id;
      Int.incr created;
      { id = !next_id
      ; kind
      ; text = None
      ; system_image = None
      ; image_color = None
      ; button_subtitle = None
      ; button_style = Bordered
      ; is_title_visible = true
      ; text_attributes = default_text_attributes
      ; placeholder = None
      ; text_field_style = Rounded_border
      ; text_field_axis = Horizontal
      ; text_field_clear_button = No_clear_button
      ; text_field_secure = false
      ; text_field_focused = false
      ; on_text_delete_backward_at_start = None
      ; toggle_is_on = false
      ; progress_value = None
      ; grid_columns = None
      ; grid_spacing = None
      ; slider_value = None
      ; slider_range = None
      ; on_slider_change = None
      ; stepper_value = None
      ; stepper_range = None
      ; stepper_step = None
      ; on_stepper_change = None
      ; horizontal_stack_alignment = Stack_center
      ; selected_date = None
      ; on_select_date = None
      ; selected_color = None
      ; on_select_color = None
      ; menu_actions = []
      ; context_menu_actions = []
      ; disclosure_is_expanded = false
      ; on_disclosure_change = None
      ; children = []
      ; is_enabled = true
      ; on_click = None
      ; on_change = None
      ; on_toggle = None
      ; on_list_refresh = None
      ; on_list_delete = None
      ; on_list_move = None
      ; on_focused_row_disappear = None
      ; list_edit_mode = false
      ; list_focused_row_key = None
      ; list_focused_row_index = None
      ; on_navigation_activate = None
      ; on_navigation_deactivate = None
      ; navigation_path = []
      ; navigation_destinations = []
      ; on_navigation_path_change = None
      ; navigation_is_active = false
      ; selected_tab = None
      ; on_select_tab = None
      ; tabs = []
      ; sidebar_title = None
      ; sidebar_compact_top_bar_visible = true
      ; sidebar_header_action = None
      ; sidebar_actions = []
      ; sidebar_history_title = None
      ; sidebar_history_actions = []
      ; sidebar_bottom_search_placeholder = None
      ; sidebar_bottom_search_text = ""
      ; sidebar_bottom_search_on_change = None
      ; sidebar_bottom_action = None
      ; section_title = None
      ; picker_title = None
      ; picker_selected = None
      ; picker_style = Menu
      ; on_select_picker = None
      ; picker_options = []
      ; share_link = None
      ; file_export = None
      ; allowed_content_types = []
      ; on_import_file = None
      ; wants_image_payload = false
      ; image_source = System_image
      ; image_max_height = None
      ; image_corner_radius = None
      ; list_row = None
      ; row_leading_button = None
      ; row_actions = []
      ; row_menu_actions = []
      ; modifiers = []
      ; schedule_event = None
      ; on_appear = None
      }
    ;;

    let destroy _ = Int.incr destroyed

    let set_text view text =
      mutate ();
      view.text <- Some text
    ;;

    let set_system_image view system_image =
      mutate ();
      view.system_image <- system_image
    ;;

    let set_image_color view color =
      mutate ();
      view.image_color <- color
    ;;

    let set_image_style view ~max_height ~corner_radius =
      mutate ();
      view.image_max_height <- max_height;
      view.image_corner_radius <- corner_radius
    ;;

    let set_button_subtitle view subtitle =
      mutate ();
      view.button_subtitle <- subtitle
    ;;

    let set_button_style view style =
      mutate ();
      view.button_style <- style
    ;;

    let set_title_visible view is_visible =
      mutate ();
      view.is_title_visible <- is_visible
    ;;

    let set_text_attributes view attributes =
      mutate ();
      view.text_attributes <- attributes
    ;;

    let set_placeholder view placeholder =
      mutate ();
      view.placeholder <- placeholder
    ;;

    let set_text_field_style view style =
      mutate ();
      view.text_field_style <- style
    ;;

    let set_text_field_axis view axis =
      mutate ();
      view.text_field_axis <- axis
    ;;

    let set_text_field_clear_button view clear_button =
      mutate ();
      view.text_field_clear_button <- clear_button
    ;;

    let set_text_field_secure view is_secure =
      mutate ();
      view.text_field_secure <- is_secure
    ;;

    let set_text_field_focus view is_focused =
      mutate ();
      view.text_field_focused <- is_focused
    ;;

    let set_text_field_delete_backward_at_start view handler =
      mutate ();
      view.on_text_delete_backward_at_start <- handler
    ;;

    let set_toggle view ~is_on ~on_change =
      mutate ();
      view.toggle_is_on <- is_on;
      view.on_toggle <- Some on_change
    ;;

    let set_progress view ~value =
      mutate ();
      view.progress_value <- Some value
    ;;

    let set_spacing _view _spacing = mutate ()

    let set_horizontal_stack_alignment view alignment =
      mutate ();
      view.horizontal_stack_alignment <- alignment
    ;;

    let set_grid view ~columns ~spacing =
      mutate ();
      view.grid_columns <- Some columns;
      view.grid_spacing <- Some spacing
    ;;

    let set_enabled view is_enabled =
      mutate ();
      view.is_enabled <- is_enabled
    ;;

    let set_children view ~keyed children =
      mutate ();
      view.children <- List.zip_exn keyed children
    ;;

    let set_list_behavior
          view
          ~on_refresh
          ~on_delete
          ~on_move
          ~on_focused_row_disappear
          ~edit_mode
          ~focused_row_key
          ~focused_row_index
      =
      mutate ();
      view.on_list_refresh <- on_refresh;
      view.on_list_delete <- on_delete;
      view.on_list_move <- on_move;
      view.on_focused_row_disappear <- on_focused_row_disappear;
      view.list_edit_mode <- edit_mode;
      view.list_focused_row_key <- focused_row_key;
      view.list_focused_row_index <- focused_row_index
    ;;

    let set_lazy_list_rows view ~length ~version:_ ~stale_indices:_ ~identity_keys:_
        ~cached_rows:_
        ~key_row
        ~render_row
        ~release_row:_
        ~on_rows_published:_ =
      mutate ();
      view.children <-
        List.init length (fun index -> Some (key_row index), render_row index)
    ;;

    let set_tabs view ~selected ~on_select tabs =
      mutate ();
      view.selected_tab <- Some selected;
      view.on_select_tab <- on_select;
      view.tabs <- tabs
    ;;

    let set_sidebar_shell
          view
          ~title
          ~compact_top_bar_visible
          ~header_action
          ~actions
          ~history_title
          ~history_actions
          ~bottom_search_placeholder
          ~bottom_search_text
          ~bottom_search_on_change
          ~bottom_action
      =
      mutate ();
      view.sidebar_title <- title;
      view.sidebar_compact_top_bar_visible <- compact_top_bar_visible;
      view.sidebar_header_action <- header_action;
      view.sidebar_actions <- actions;
      view.sidebar_history_title <- history_title;
      view.sidebar_history_actions <- history_actions;
      view.sidebar_bottom_search_placeholder <- bottom_search_placeholder;
      view.sidebar_bottom_search_text <- bottom_search_text;
      view.sidebar_bottom_search_on_change <- bottom_search_on_change;
      view.sidebar_bottom_action <- bottom_action
    ;;

    let set_list_row
          view
          ~title
          ~subtitle
          ~trailing_text
          ~leading_system_image
          ~preview_image_path
          ~content_style
          ~accessory
          ~title_strikethrough
          ~(leading_button : rendered_row_leading_button option)
          ~(swipe_actions : rendered_row_action list)
          ~(menu_actions : rendered_row_action list)
      =
      mutate ();
      let leading =
        match leading_button with
        | None -> "leading=none"
        | Some leading ->
          sprintf "leading=%s:%s" leading.system_image (Bool.to_string leading.selected)
      in
      let actions =
        swipe_actions
        |> List.map ~f:(fun action ->
          let style =
            match action.style with
            | Default -> "default"
            | Destructive -> "destructive"
          in
          action.title ^ ":" ^ style)
        |> String.concat ~sep:","
      in
      let menu_actions_text =
        menu_actions
        |> List.map ~f:(fun action ->
          let style =
            match action.style with
            | Default -> "default"
            | Destructive -> "destructive"
          in
          action.title ^ ":" ^ style)
        |> String.concat ~sep:","
      in
      view.row_leading_button <- leading_button;
      view.row_actions <- swipe_actions;
      view.row_menu_actions <- menu_actions;
      view.list_row
      <- Some
           (sprintf
              " title=%s subtitle=%s trailing=%s style=%s accessory=%s strikethrough=%s \
               leading-image=%s preview-image=%s %s actions=[%s] menu=[%s]"
              (quoted title)
              (option_text subtitle)
              (option_text trailing_text)
              (list_row_content_style_name content_style)
              (list_row_accessory_name accessory)
              (Bool.to_string title_strikethrough)
              (Option.value leading_system_image ~default:"none")
              (Option.value preview_image_path ~default:"none")
              leading
              actions
              menu_actions_text)
    ;;

    let refresh_list_row_callbacks
          view
          ~on_click
          ~leading_button
          ~swipe_actions
          ~menu_actions
      =
      view.on_click <- on_click;
      view.on_change <- None;
      view.row_leading_button <- leading_button;
      view.row_actions <- swipe_actions;
      view.row_menu_actions <- menu_actions
    ;;

    let set_navigation_link_callbacks view ~on_activate ~on_deactivate =
      view.on_navigation_activate <- on_activate;
      view.on_navigation_deactivate <- on_deactivate
    ;;

    let set_navigation_link_value _view _value = ()

    let set_section view ~title =
      mutate ();
      view.section_title <- title
    ;;

    let set_picker view ~title ~selected ~style ~on_select options =
      mutate ();
      view.picker_title <- Some title;
      view.picker_selected <- Some selected;
      view.picker_style <- style;
      view.on_select_picker <- on_select;
      view.picker_options <- options
    ;;

    let set_slider view ~title ~value ~min ~max ~on_change =
      mutate ();
      view.text <- Some title;
      view.slider_value <- Some value;
      view.slider_range <- Some (min, max);
      view.on_slider_change <- on_change
    ;;

    let set_stepper view ~title ~value ~min ~max ~step ~on_change =
      mutate ();
      view.text <- Some title;
      view.stepper_value <- Some value;
      view.stepper_range <- Some (min, max);
      view.stepper_step <- Some step;
      view.on_stepper_change <- on_change
    ;;

    let set_date_picker view ~title ~selected ~on_select =
      mutate ();
      view.text <- Some title;
      view.selected_date <- Some selected;
      view.on_select_date <- on_select
    ;;

    let set_color_picker view ~title ~selected ~on_select =
      mutate ();
      view.text <- Some title;
      view.selected_color <- Some selected;
      view.on_select_color <- on_select
    ;;

    let set_menu view ~title ~system_image ~actions ~schedule_event:_ =
      mutate ();
      view.text <- Some title;
      view.system_image <- system_image;
      view.menu_actions <- actions
    ;;

    let set_disclosure_group view ~title ~is_expanded ~on_change =
      mutate ();
      view.text <- Some title;
      view.disclosure_is_expanded <- is_expanded;
      view.on_disclosure_change <- on_change
    ;;

    let set_navigation_path_stack view ~path ~on_path_change ~destinations =
      mutate ();
      view.navigation_path <- path;
      view.navigation_destinations <- destinations;
      view.on_navigation_path_change <- on_path_change
    ;;

    let set_file_exporter view export =
      mutate ();
      view.file_export <- Some export
    ;;

    let set_share_link view share_link =
      mutate ();
      view.share_link <- Some share_link
    ;;

    let set_file_importer view ~allowed_content_types ~on_select =
      mutate ();
      view.allowed_content_types <- allowed_content_types;
      view.on_import_file <- on_select
    ;;

    let set_image_payload_mode view wants_payload =
      mutate ();
      view.wants_image_payload <- wants_payload
    ;;

    let set_image_source view source =
      mutate ();
      view.image_source <- source
    ;;

    let set_on_click view on_click =
      mutate ();
      view.on_click <- on_click
    ;;

    let set_on_change view on_change =
      mutate ();
      view.on_change <- on_change
    ;;

    let set_modifiers view ~schedule_event modifiers =
      mutate ();
      view.modifiers <- modifiers;
      view.schedule_event <- Some schedule_event;
      view.context_menu_actions
      <- List.find_map modifiers ~f:(function
           | Rendered_context_menu actions -> Some actions
           | _ -> None)
         |> Option.value ~default:[];
      (match
         List.find_map modifiers ~f:(function
           | Rendered_tap_action { on_click } -> Some on_click
           | _ -> None)
       with
       | None -> ()
       | Some on_click -> view.on_click <- Some (fun () -> schedule_event on_click));
      view.on_appear
      <- List.find_map modifiers ~f:(function
           | Rendered_on_appear { on_appear } -> Some (fun () -> schedule_event on_appear)
           | _ -> None)
    ;;

    let kind_name view =
      match view.kind with
      | Label -> "label"
      | Button -> "button"
      | Text_field -> "text-field"
      | Text_editor -> "text-editor"
      | Toggle -> "toggle"
      | Stack Vertical -> "stack(vertical)"
      | Stack Horizontal -> (
          match view.horizontal_stack_alignment with
          | Stack_top -> "stack(horizontal-top)"
          | Stack_center -> "stack(horizontal)")
      | Z_stack -> "zstack"
      | Grid -> "grid"
      | Spacer -> "spacer"
      | Divider -> "divider"
      | Form -> "form"
      | Scroll_view -> "scroll-view"
      | List -> "list"
      | Movable_rows -> "movable-rows"
      | Navigation_stack -> "navigation-stack"
      | Navigation_path_stack -> "navigation-path-stack"
      | Navigation_link -> "navigation-link"
      | Navigation_split -> "navigation-split"
      | Adaptive_layout -> "adaptive-layout"
      | Tab_view -> "tab-view"
      | Sidebar_split -> "sidebar-split"
      | Image -> "image"
      | List_row -> "list-row"
      | Section -> "section"
      | Picker -> "picker"
      | Slider -> "slider"
      | Stepper -> "stepper"
      | Date_picker -> "date-picker"
      | Color_picker -> "color-picker"
      | Menu -> "menu"
      | Disclosure_group -> "disclosure-group"
      | Photo_picker -> "photo-picker"
      | Share_link -> "share-link"
      | File_exporter -> "file-exporter"
      | File_importer -> "file-importer"
      | Camera_capture -> "camera-capture"
      | Progress_view -> "progress-view"
      | Congrats_effect -> "congrats-effect"
      | Custom_view _ -> "custom(" ^ Option.value view.text ~default:"" ^ ")"
    ;;

    let rendered_frame_alignment_name = function
      | Center -> "center"
      | Leading -> "leading"
    ;;

    let rendered_frame_value ({ width; height; max_width; alignment } : frame) =
      let value = function
        | None -> "_"
        | Some value -> string_of_float value
      in
      value width
      ^ "x"
      ^ value height
      ^
      (match max_width with
       | None -> ""
       | Some max_width -> ":" ^ string_of_float max_width)
      ^
      (match alignment with
       | None -> ""
       | Some alignment -> ":" ^ rendered_frame_alignment_name alignment)
    ;;

    let modifier_name = function
      | Rendered_padding _ -> "padding"
      | Rendered_regular_material_panel _ -> "panel"
      | Rendered_secondary_system_grouped_panel _ -> "panel"
      | Rendered_secondary_fill_panel _ -> "panel"
      | Rendered_liquid_glass_panel _ -> "panel"
      | Rendered_context_menu _ -> "context-menu"
      | Rendered_frame frame -> "frame:" ^ rendered_frame_value frame
      | Rendered_navigation_title _ -> "navigation-title"
      | Rendered_searchable _ -> "searchable"
      | Rendered_toolbar _ -> "toolbar"
      | Rendered_toolbar_groups _ -> "toolbar-groups"
      | Rendered_keyboard_toolbar _ -> "keyboard-toolbar"
      | Rendered_tap_action _ -> "tap-action"
      | Rendered_horizontal_swipe _ -> "horizontal-swipe"
      | Rendered_on_appear _ -> "on-appear"
      | Rendered_keyboard_dismiss_controls -> "keyboard-dismiss-controls"
      | Rendered_scroll_dismisses_keyboard -> "scroll-dismisses-keyboard"
      | Rendered_hide_list_row_separator -> "hide-list-row-separator"
      | Rendered_safe_area_inset_bottom _ -> "safe-area-inset-bottom"
      | Rendered_sheet _ -> "sheet"
      | Rendered_popover _ -> "popover"
      | Rendered_confirmation_dialog _ -> "confirmation-dialog"
      | Rendered_alert _ -> "alert"
    ;;

    let navigation_path_stack_root view =
      match view.children with
      | (_, root) :: _ -> Some root
      | [] -> None
    ;;

    let navigation_path_stack_destination view =
      match List.rev view.navigation_path with
      | destination_id :: _ ->
        List.find_map view.children ~f:(fun (key, child) ->
          match key with
          | Some key when String.equal key destination_id -> Some child
          | _ -> None)
      | [] -> None
    ;;

    let rec active_navigation_destination view =
      match view.kind, view.navigation_is_active, view.children with
      | Navigation_link, true, [ _; (_, destination) ] -> Some destination
      | Navigation_path_stack, _, _ -> navigation_path_stack_destination view
      | _ ->
        List.find_map view.children ~f:(fun (_, child) ->
          active_navigation_destination child)

    and visible_view view =
      match view.kind with
      | Navigation_path_stack ->
        let visible_child =
          match navigation_path_stack_destination view with
          | Some destination -> Some destination
          | None -> navigation_path_stack_root view
        in
        (match visible_child with
         | Some destination -> visible_view destination
         | None -> view)
      | _ ->
        (match active_navigation_destination view with
         | None -> view
         | Some destination -> visible_view destination)

    and show_lines ?key view ~indent =
      let spaces = String.make indent ' ' in
      let key =
        match key with
        | None -> ""
        | Some key -> " key=" ^ key
      in
      let text =
        match view.text with
        | None -> ""
        | Some text -> " text=" ^ quoted text
      in
      let enabled = if view.is_enabled then "" else " disabled" in
      let system_image =
        match view.system_image with
        | None -> ""
        | Some system_image -> " image=" ^ system_image
      in
      let button_subtitle =
        match view.kind, view.button_subtitle with
        | Button, Some subtitle -> " subtitle=" ^ option_text (Some subtitle)
        | _ -> ""
      in
      let button_style =
        match view.kind, view.button_style with
        | Button, Bordered -> ""
        | Button, style -> " button-style=" ^ button_style_name style
        | _ -> ""
      in
      let title_visibility = if view.is_title_visible then "" else " title-hidden" in
      let text_attributes =
        if equal_text_attributes view.text_attributes default_text_attributes
        then ""
        else " text_attributes=" ^ text_attributes_name view.text_attributes
      in
      let placeholder =
        match view.kind, view.placeholder with
        | Photo_picker, _ -> ""
        | _, None -> ""
        | _, Some placeholder -> " placeholder=" ^ quoted placeholder
      in
      let text_field_style =
        match view.kind with
        | Text_field -> " style=" ^ text_field_style_name view.text_field_style
        | _ -> ""
      in
      let text_field_chrome =
        match view.kind, view.text_field_style with
        | Text_field, Pill -> " chrome=liquid-glass corner-radius=26"
        | _ -> ""
      in
      let text_field_axis =
        match view.kind, view.text_field_axis with
        | Text_field, Vertical -> " axis=vertical"
        | _ -> ""
      in
      let text_field_clear_button =
        match view.kind, view.text_field_clear_button with
        | Text_field, No_clear_button -> ""
        | Text_field, clear_button ->
          " native-clear-button=" ^ text_field_clear_button_name clear_button
        | _ -> ""
      in
      let text_field_secure =
        match view.kind, view.text_field_secure with
        | Text_field, true -> " secure"
        | _ -> ""
      in
      let text_field_focused =
        match view.kind, view.text_field_focused with
        | Text_field, true -> " focused"
        | _ -> ""
      in
      let toggle_selected =
        match view.kind with
        | Toggle -> " selected=" ^ Bool.to_string view.toggle_is_on
        | _ -> ""
      in
      let progress =
        match view.kind, view.progress_value with
        | Progress_view, Some value -> " progress=" ^ Float.to_string value
        | _ -> ""
      in
      let grid =
        match view.kind, view.grid_columns, view.grid_spacing with
        | Grid, Some columns, Some spacing -> sprintf " columns=%d spacing=%g" columns spacing
        | _ -> ""
      in
      let list_behavior =
        match view.kind with
        | List | Movable_rows ->
          let flags =
            List.filter_opt
              [ (if view.list_edit_mode then Some "edit-mode" else None)
              ; (if Option.is_some view.on_list_refresh then Some "refreshable" else None)
              ; (if Option.is_some view.on_list_delete then Some "on-delete" else None)
              ; (if Option.is_some view.on_list_move then Some "on-move" else None)
              ]
          in
          if List.is_empty flags then "" else " " ^ String.concat ~sep:" " flags
        | _ -> ""
      in
      let focused_row =
        match view.kind, view.list_focused_row_key, view.list_focused_row_index with
        | (List | Movable_rows), Some key, Some index ->
          sprintf " focused-row=%s focused-index=%d" key index
        | (List | Movable_rows), Some key, None -> " focused-row=" ^ key
        | (List | Movable_rows), None, Some index -> sprintf " focused-index=%d" index
        | _ -> ""
      in
      let slider =
        match view.kind, view.slider_value, view.slider_range with
        | Slider, Some value, Some (min, max) ->
          sprintf " value=%g range=%g..%g" value min max
        | _ -> ""
      in
      let stepper =
        match view.kind, view.stepper_value, view.stepper_range, view.stepper_step with
        | Stepper, Some value, Some (min, max), Some step ->
          sprintf " value=%d range=%d..%d step=%d" value min max step
        | _ -> ""
      in
      let date_picker =
        match view.kind, view.selected_date with
        | Date_picker, Some selected -> " selected=" ^ selected
        | _ -> ""
      in
      let color_picker =
        match view.kind, view.selected_color with
        | Color_picker, Some selected -> " selected=" ^ selected
        | _ -> ""
      in
      let menu =
        match view.kind, view.menu_actions with
        | Menu, actions ->
          let action_text =
            actions
            |> List.map ~f:(fun (action : menu_action) ->
              let image = Option.value action.system_image ~default:"none" in
              let style =
                match action.style with
                | Default -> "default"
                | Destructive -> "destructive"
              in
              sprintf
                "%s:%s:%s:%s:%s"
                action.id
                action.title
                image
                style
                (if action.is_enabled then "enabled" else "disabled"))
            |> String.concat ~sep:","
          in
          " actions=[" ^ action_text ^ "]"
        | _ -> ""
      in
      let disclosure =
        match view.kind with
        | Disclosure_group -> " expanded=" ^ Bool.to_string view.disclosure_is_expanded
        | _ -> ""
      in
      let navigation_path =
        match view.kind with
        | Navigation_path_stack ->
          " path=["
          ^ String.concat ~sep:"," view.navigation_path
          ^ "] destinations=["
          ^ String.concat ~sep:"," view.navigation_destinations
          ^ "]"
        | _ -> ""
      in
      let photo_picker =
        match view.kind with
        | Photo_picker -> " selected=" ^ option_text view.placeholder
        | _ -> ""
      in
      let camera_capture =
        match view.kind with
        | Camera_capture -> " captured=" ^ option_text view.placeholder
        | _ -> ""
      in
      let file_exporter =
        match view.file_export with
        | Some export ->
          sprintf " filename=%s content_type=%s" export.filename export.content_type
        | None -> ""
      in
      let share_link =
        match view.share_link with
        | Some share_link -> " url=" ^ share_link.url
        | None -> ""
      in
      let file_importer =
        match view.kind with
        | File_importer ->
          " allowed_content_types=["
          ^ String.concat ~sep:"," view.allowed_content_types
          ^ "]"
        | _ -> ""
      in
      let payload = if view.wants_image_payload then " payload" else "" in
      let image_source =
        match view.kind, view.image_source with
        | Image, File_image -> " source=file"
        | _ -> ""
      in
      let image_color =
        match view.kind, view.image_color with
        | Image, Some color -> " image-color=" ^ text_color_name color
        | _ -> ""
      in
      let image_style =
        match view.kind, view.image_max_height, view.image_corner_radius with
        | Image, None, None -> ""
        | Image, max_height, corner_radius ->
          " image-style=max-height:"
          ^ option_text (Option.map max_height ~f:(fun value -> sprintf "%g" value))
          ^ ":corner-radius:"
          ^ option_text (Option.map corner_radius ~f:(fun value -> sprintf "%g" value))
        | _ -> ""
      in
      let modifiers =
        match view.modifiers with
        | [] -> ""
        | modifiers ->
          " modifiers=["
          ^ String.concat ~sep:"," (List.map modifiers ~f:modifier_name)
          ^ "]"
      in
      let searchable_prompt =
        match
          List.find_map view.modifiers ~f:(function
            | Rendered_searchable { prompt = Some prompt; _ } -> Some prompt
            | _ -> None)
        with
        | None -> ""
        | Some prompt -> " searchable-prompt=" ^ quoted prompt
      in
      let panel =
        match
          List.find_map view.modifiers ~f:(function
            | Rendered_liquid_glass_panel
                { corner_radius; is_transparent; tint_color; tint_opacity } ->
              Some
                (sprintf
                   " panel=liquid-glass corner-radius=%g transparent=%s tint=%s:%g"
                   corner_radius
                   (Bool.to_string is_transparent)
                   (Option.value
                      (Option.map tint_color ~f:text_color_name)
                      ~default:"none")
                   tint_opacity)
            | Rendered_regular_material_panel { corner_radius } ->
              Some (sprintf " panel=regular-material corner-radius=%g" corner_radius)
            | Rendered_secondary_system_grouped_panel { corner_radius } ->
              Some
                (sprintf " panel=secondary-system-grouped corner-radius=%g" corner_radius)
            | Rendered_secondary_fill_panel { corner_radius; opacity } ->
              Some
                (sprintf
                   " panel=secondary-fill corner-radius=%g opacity=%g"
                   corner_radius
                   opacity)
            | _ -> None)
        with
        | None -> ""
        | Some panel -> panel
      in
      let toolbar_items_text items =
        items
        |> List.map ~f:(fun (item : toolbar_item) ->
          let system_image =
            match item.system_image with
            | None -> ""
            | Some system_image -> ":image=" ^ system_image
          in
          let menu =
            match item.menu_actions with
            | [] -> ""
            | menu_actions ->
              let action_text =
                menu_actions
                |> List.concat_map ~f:(fun (action : toolbar_menu_action) ->
                  let system_image = Option.value action.system_image ~default:"none" in
                  let style =
                    match action.style with
                    | Default -> "default"
                    | Destructive -> "destructive"
                  in
                  let action_text = action.title ^ ":" ^ system_image ^ ":" ^ style in
                  if action.starts_section then [ "divider"; action_text ] else [ action_text ])
                |> String.concat ~sep:","
              in
              ":menu=[" ^ action_text ^ "]"
          in
          let share_url =
            match item.share_url with
            | None -> ""
            | Some url -> ":share-url=" ^ url
          in
          sprintf
            "%s:%s:%s%s%s%s%s"
            item.id
            item.title
            (if item.is_enabled then "enabled" else "disabled")
            system_image
            (if item.is_title_visible then "" else ":title-hidden")
            share_url
            menu)
        |> String.concat ~sep:","
      in
      let toolbar_placement_text = function
        | Automatic -> "automatic"
        | Bottom_bar -> "bottom-bar"
      in
      let toolbar_content_text = function
        | Toolbar_group { id; placement; items } ->
          sprintf
            "group:%s:%s:[%s]"
            id
            (toolbar_placement_text placement)
            (toolbar_items_text items)
        | Toolbar_spacer { id; placement; fixed } ->
          sprintf
            "spacer:%s:%s:%s"
            id
            (toolbar_placement_text placement)
            (Bool.to_string fixed)
      in
      let toolbar =
        match
          List.find_map view.modifiers ~f:(function
            | Rendered_toolbar items -> Some items
            | _ -> None)
        with
        | None -> ""
        | Some items ->
          " toolbar=["
          ^ toolbar_items_text items
          ^ "] toolbar-presentation=system-toolbaritem toolbaritem-chrome=system-default"
      in
      let toolbar_groups =
        match
          List.find_map view.modifiers ~f:(function
            | Rendered_toolbar_groups contents -> Some contents
            | _ -> None)
        with
        | None -> ""
        | Some contents ->
          " toolbar-groups=["
          ^ (contents |> List.map ~f:toolbar_content_text |> String.concat ~sep:",")
          ^ "] toolbar-presentation=system-toolbaritem-groups toolbaritem-chrome=system-default"
      in
      let keyboard_toolbar =
        match
          List.find_map view.modifiers ~f:(function
            | Rendered_keyboard_toolbar items -> Some items
            | _ -> None)
        with
        | None -> ""
        | Some items -> " keyboard-toolbar=[" ^ toolbar_items_text items ^ "]"
      in
      let context_menu =
        match
          List.find_map view.modifiers ~f:(function
            | Rendered_context_menu actions -> Some actions
            | _ -> None)
        with
        | None -> ""
        | Some actions ->
          let action_text =
            actions
            |> List.map ~f:(fun (action : row_action) ->
              let system_image =
                match action.system_image with
                | None -> ""
                | Some system_image -> ":" ^ system_image
              in
              let style =
                match action.style with
                | Default -> "default"
                | Destructive -> "destructive"
              in
              action.title ^ system_image ^ ":" ^ style)
            |> String.concat ~sep:","
          in
          " context-menu=[" ^ action_text ^ "]"
      in
      let navigation_title =
        match
          List.find_map view.modifiers ~f:(function
            | Rendered_navigation_title title -> Some title
            | _ -> None)
        with
        | None -> ""
        | Some title -> " navigation-title=" ^ title
      in
      let alert =
        match
          List.find_map view.modifiers ~f:(function
            | Rendered_alert
                { is_presented = true; title; message; text; placeholder; actions; _ } ->
              Some (title, message, text, placeholder, actions)
            | _ -> None)
        with
        | None -> ""
        | Some (title, message, text, placeholder, actions) ->
          let role_name = function
            | Alert_default -> "default"
            | Alert_cancel -> "cancel"
            | Alert_destructive -> "destructive"
          in
          let action_text =
            actions
            |> List.map ~f:(fun (action : alert_action) ->
              sprintf
                "%s:%s:%s:%s"
                action.id
                action.title
                (role_name action.role)
                (if action.is_enabled then "enabled" else "disabled"))
            |> String.concat ~sep:","
          in
          " alert="
          ^ title
          ^ " message="
          ^ option_text message
          ^ " text="
          ^ option_text text
          ^ " placeholder="
          ^ option_text placeholder
          ^ " actions=["
          ^ action_text
          ^ "]"
      in
      let sheet_detents =
        match
          List.find_map view.modifiers ~f:(function
            | Rendered_sheet { detents = _ :: _ as detents; _ } -> Some detents
            | _ -> None)
        with
        | None -> ""
        | Some detents ->
          let detent_name : presentation_detent -> string = function
            | Medium -> "medium"
            | Large -> "large"
            | Fraction fraction -> sprintf "fraction:%g" fraction
            | Height height -> sprintf "height:%g" height
          in
          " sheet-detents=["
          ^ String.concat ~sep:"," (List.map detents ~f:detent_name)
          ^ "]"
      in
      let confirmation_dialog =
        match
          List.find_map view.modifiers ~f:(function
            | Rendered_confirmation_dialog
                { is_presented = true; title; message; actions; _ } ->
              Some (title, message, actions)
            | _ -> None)
        with
        | None -> ""
        | Some (title, message, actions) ->
          let role_name = function
            | Alert_default -> "default"
            | Alert_cancel -> "cancel"
            | Alert_destructive -> "destructive"
          in
          let action_text =
            actions
            |> List.map ~f:(fun (action : alert_action) ->
              sprintf
                "%s:%s:%s:%s"
                action.id
                action.title
                (role_name action.role)
                (if action.is_enabled then "enabled" else "disabled"))
            |> String.concat ~sep:","
          in
          " confirmation-dialog="
          ^ title
          ^ " message="
          ^ option_text message
          ^ " actions=["
          ^ action_text
          ^ "]"
      in
      let popover =
        match
          List.find_map view.modifiers ~f:(function
            | Rendered_popover { is_presented = true; _ } -> Some ()
            | _ -> None)
        with
        | None -> ""
        | Some () -> " popover=true"
      in
      let selected =
        match view.selected_tab with
        | None -> ""
        | Some selected -> " selected=" ^ selected
      in
      let tab_name (tab : rendered_tab) =
        let image =
          match tab.system_image with
          | None -> ""
          | Some image -> ":" ^ image
        in
        let role =
          match tab.role with
          | None -> ""
          | Some Search -> ":search"
        in
        tab.id ^ ":" ^ tab.title ^ image ^ role
      in
      let tabs =
        match view.kind, view.tabs with
        | _, [] -> ""
        | Sidebar_split, tabs ->
          " routes=[" ^ String.concat ~sep:"," (List.map tabs ~f:tab_name) ^ "]"
        | _, tabs -> " tabs=[" ^ String.concat ~sep:"," (List.map tabs ~f:tab_name) ^ "]"
      in
      let compact_top_bar =
        match view.kind with
        | Sidebar_split when view.sidebar_compact_top_bar_visible ->
          let title = Option.value view.sidebar_title ~default:"Menu" in
          " sidebar-navigation=chatgpt-drawer sidebar-padding=12 sidebar-header-title="
          ^ title
          ^ " sidebar-primary-row-height=52 sidebar-selected-corner-radius=12"
          ^ " sidebar-safe-area-padding=swift top=max-safe-area-plus-5-or-54 \
             bottom=max-safe-area-or-34"
          ^ " sidebar-shell-background=home-body-ignores-safe-area-outside-clip"
          ^ " sidebar-bottom-controls=safe-area-inset keyboard-padding top-padding=10"
          ^ " sidebar-transition=interactive-drawer sidebar-toggle=open-drawer"
          ^ " sidebar-route-selection=select-route-and-close-drawer"
          ^ " sidebar-main-chrome=peek-rounded-shadow-continuous sidebar-swipe=open-anywhere"
          ^ " sidebar-search-style=liquid-glass compact-top-bar=system-toolbar"
          ^ " toolbaritem-leading=sidebar-toggle toolbaritem-title=navigation-title"
          ^ " toolbaritem-leading-chrome=liquid-glass"
        | Sidebar_split -> " compact-top-bar=hidden"
        | _ -> ""
      in
      let sidebar_action_name (action : rendered_sidebar_action) =
        let subtitle =
          match action.subtitle with
          | None -> ""
          | Some subtitle -> ":preview=" ^ subtitle
        in
        let image =
          match action.system_image with
          | None -> ""
          | Some image -> ":" ^ image
        in
        let avatar =
          match action.avatar_image, action.avatar_initial with
          | Some image, _ -> ":avatar-image=" ^ image
          | None, Some initial -> ":avatar=" ^ initial
          | None, None -> image
        in
        let menu =
          match action.menu_actions with
          | [] -> ""
          | menu_actions ->
            ":menu=["
            ^ String.concat
                ~sep:","
                (List.map menu_actions ~f:(fun menu_action ->
                   let style =
                     match menu_action.style with
                     | Default -> "default"
                     | Destructive -> "destructive"
                   in
                   let image =
                     match menu_action.system_image with
                     | None -> ""
                     | Some image -> ":" ^ image
                   in
                   menu_action.title ^ image ^ ":" ^ style))
            ^ "]"
        in
        let selects =
          match action.selects_tab with
          | None -> ""
          | Some tab -> ":selects=" ^ tab
        in
        let close_policy = if action.closes_sidebar then "" else ":keeps-sidebar" in
        action.id ^ ":" ^ action.title ^ subtitle ^ avatar ^ menu ^ selects ^ close_policy
      in
      let sidebar_header_action =
        match view.kind, view.sidebar_header_action with
        | Sidebar_split, Some action ->
          " sidebar-header-action=" ^ sidebar_action_name action
        | _ -> ""
      in
      let sidebar_actions =
        match view.kind, view.sidebar_actions with
        | Sidebar_split, (_ :: _ as actions) ->
          " sidebar-actions=["
          ^ String.concat ~sep:"," (List.map actions ~f:sidebar_action_name)
          ^ "]"
        | _ -> ""
      in
      let sidebar_history_title =
        match view.kind, view.sidebar_history_title with
        | Sidebar_split, Some title -> " sidebar-history-title=" ^ title
        | _ -> ""
      in
      let sidebar_history_actions =
        match view.kind, view.sidebar_history_actions with
        | Sidebar_split, (_ :: _ as actions) ->
          " sidebar-history-actions=["
          ^ String.concat ~sep:"," (List.map actions ~f:sidebar_action_name)
          ^ "]"
        | _ -> ""
      in
      let sidebar_history_menu_presentation =
        match view.kind, view.sidebar_history_actions with
        | Sidebar_split, actions
          when List.exists actions ~f:(fun action ->
                 not (List.is_empty action.menu_actions)) ->
          " sidebar-history-menu-presentation=context-menu"
        | _ -> ""
      in
      let sidebar_bottom_search =
        match view.kind, view.sidebar_bottom_search_placeholder with
        | Sidebar_split, Some placeholder ->
          " sidebar-bottom-search="
          ^ placeholder
          ^ " text="
          ^ String.escaped view.sidebar_bottom_search_text
        | _ -> ""
      in
      let sidebar_bottom_action =
        match view.kind, view.sidebar_bottom_action with
        | Sidebar_split, Some action ->
          " sidebar-bottom-action=" ^ sidebar_action_name action
        | _ -> ""
      in
      let sidebar_bottom_action_chrome =
        match view.kind, view.sidebar_bottom_action with
        | Sidebar_split, Some action ->
          " sidebar-bottom-action-chrome=" ^ sidebar_action_chrome_name action.chrome
        | _ -> ""
      in
      let section =
        match view.section_title with
        | None -> ""
        | Some title -> " title=" ^ quoted title
      in
      let picker =
        match view.picker_title, view.picker_selected with
        | Some title, Some selected ->
          let option_name (option : rendered_picker_option) =
            option.id ^ ":" ^ option.title
          in
          sprintf
            " title=%s selected=%s picker-style=%s options=[%s]"
            (quoted title)
            selected
            (picker_style_name view.picker_style)
            (String.concat ~sep:"," (List.map view.picker_options ~f:option_name))
        | _ -> ""
      in
      let list_row = Option.value view.list_row ~default:"" in
      let child_lines =
        match view.kind, view.children with
        | Navigation_link, [ (_, label); _ ] ->
          let label_lines =
            (spaces ^ "  label:") :: show_lines label ~indent:(indent + 4)
          in
          if view.navigation_is_active
          then (
            match active_navigation_destination view with
            | None -> label_lines
            | Some destination ->
              label_lines
              @ ((spaces ^ "  active-destination:")
                 :: show_lines destination ~indent:(indent + 4)))
          else label_lines
        | Navigation_path_stack, _ ->
          let root_lines =
            match navigation_path_stack_root view with
            | None -> []
            | Some root -> show_lines root ~indent:(indent + 2)
          in
          (match navigation_path_stack_destination view with
           | None -> root_lines
           | Some destination ->
             root_lines
             @ ((spaces ^ "  active-destination:")
                :: show_lines destination ~indent:(indent + 4)))
        | _ ->
          List.concat_map view.children ~f:(fun (key, child) ->
            let key =
              match key with
              | Some "__root__" -> None
              | _ -> key
            in
            show_lines ?key child ~indent:(indent + 2))
      in
      let popover_lines =
        List.concat_map view.modifiers ~f:(function
          | Rendered_popover { is_presented = true; content = Some content; _ } ->
            (spaces ^ "  popover:") :: show_lines content ~indent:(indent + 4)
          | _ -> [])
      in
      let sheet_lines =
        List.concat_map view.modifiers ~f:(function
          | Rendered_sheet { is_presented = true; content = Some content; _ } ->
            (spaces ^ "  sheet:") :: show_lines content ~indent:(indent + 4)
          | _ -> [])
      in
      let safe_area_inset_lines =
        List.concat_map view.modifiers ~f:(function
          | Rendered_safe_area_inset_bottom { content } ->
            (spaces ^ "  safe-area-inset-bottom:")
            :: show_lines content ~indent:(indent + 4)
          | _ -> [])
      in
      ((spaces
        ^ kind_name view
        ^ "#"
        ^ Int.to_string view.id
        ^ key
        ^ text
        ^ text_attributes
        ^ placeholder
        ^ text_field_style
        ^ text_field_chrome
        ^ text_field_axis
        ^ text_field_clear_button
        ^ text_field_secure
        ^ text_field_focused
        ^ toggle_selected
        ^ progress
        ^ grid
        ^ list_behavior
        ^ focused_row
        ^ slider
        ^ stepper
        ^ date_picker
        ^ color_picker
        ^ photo_picker
        ^ camera_capture
        ^ share_link
        ^ file_exporter
        ^ file_importer
        ^ payload
        ^ image_source
        ^ image_color
        ^ image_style
        ^ panel
        ^ system_image
        ^ button_style
        ^ menu
        ^ disclosure
        ^ button_subtitle
        ^ title_visibility
        ^ enabled
        ^ navigation_path
        ^ selected
        ^ tabs
        ^ compact_top_bar
        ^ sidebar_header_action
        ^ sidebar_actions
        ^ sidebar_history_title
        ^ sidebar_history_actions
        ^ sidebar_history_menu_presentation
        ^ sidebar_bottom_search
        ^ sidebar_bottom_action
        ^ sidebar_bottom_action_chrome
        ^ section
        ^ picker
        ^ list_row
        ^ searchable_prompt
        ^ context_menu
        ^ modifiers
        ^ sheet_detents
        ^ toolbar
        ^ toolbar_groups
        ^ keyboard_toolbar
        ^ navigation_title
        ^ alert
        ^ confirmation_dialog
        ^ popover)
       :: safe_area_inset_lines)
      @ child_lines
      @ popover_lines
      @ sheet_lines
    ;;

    let show view = String.concat ~sep:"\n" (show_lines view ~indent:0)

    let rec find_raw_exn view ~path =
      match path with
      | [] -> view
      | index :: rest ->
        (match List.nth view.children index with
         | Some (_, child) -> find_raw_exn child ~path:rest
         | None -> failwithf "No child at index %d" index ())
    ;;

    let rec find_exn view ~path =
      match path with
      | [] -> view
      | index :: rest ->
        let view =
          match view.kind, active_navigation_destination view with
          | Navigation_stack, Some destination | Navigation_path_stack, Some destination
            -> destination
          | _ -> view
        in
        (match List.nth view.children index with
         | Some (_, child) -> find_exn child ~path:rest
         | None -> failwithf "No child at index %d" index ())
    ;;

    let find_visible_exn view ~path = find_exn view ~path |> visible_view
    let show_at_path view ~path = show (find_exn view ~path)

    let safe_area_inset_bottom_content view =
      match
        List.find_map view.modifiers ~f:(function
          | Rendered_safe_area_inset_bottom { content } -> Some content
          | _ -> None)
      with
      | Some content -> content
      | None -> failwith "View has no bottom safe-area inset"
    ;;

    let find_safe_area_host_exn view ~path =
      let view = find_exn view ~path in
      match safe_area_inset_bottom_content view with
      | _ -> view
      | exception Failure _ -> visible_view view
    ;;

    let safe_area_inset_bottom_content_exn view =
      match safe_area_inset_bottom_content view with
      | content -> content
      | exception Failure _ -> safe_area_inset_bottom_content (visible_view view)
    ;;

    let show_safe_area_inset_bottom_exn view ~path =
      show (safe_area_inset_bottom_content_exn (find_safe_area_host_exn view ~path))
    ;;

    let navigation_link_label_or_self view =
      match view.kind, view.children with
      | Navigation_link, (_, label) :: _ -> label
      | _ -> view
    ;;

    let click_exn view ~path =
      let view = find_visible_exn view ~path in
      match view.on_click with
      | Some f -> f ()
      | None ->
        (match view.on_navigation_activate with
         | Some f ->
           view.navigation_is_active <- true;
           f ()
         | None -> failwith "View has no click handler")
    ;;

    let activate_navigation_link_exn view ~path =
      let view = find_raw_exn view ~path in
      match view.on_navigation_activate with
      | Some f ->
        view.navigation_is_active <- true;
        f ()
      | None -> failwith "View has no navigation activation handler"
    ;;

    let deactivate_navigation_link_exn view ~path =
      let view = find_raw_exn view ~path in
      match view.on_navigation_deactivate with
      | Some f ->
        view.navigation_is_active <- false;
        f ()
      | None -> failwith "View has no navigation deactivation handler"
    ;;

    let click_safe_area_inset_bottom_exn view ~path ~inset_path =
      click_exn
        (safe_area_inset_bottom_content_exn (find_safe_area_host_exn view ~path))
        ~path:inset_path
    ;;

    let change_text_exn view ~path ~text =
      let view = find_visible_exn view ~path in
      view.text <- Some text;
      match view.on_change with
      | Some f -> f text
      | None -> failwith "View has no text-change handler"
    ;;

    let clear_text_exn view ~path =
      let view = find_visible_exn view ~path in
      (match view.kind, view.text_field_clear_button with
       | Text_field, No_clear_button -> failwith "Text field has no native clear button"
       | Text_field, _ -> ()
       | _ -> failwith "View is not a text field");
      change_text_exn view ~path:[] ~text:""
    ;;

    let change_safe_area_inset_bottom_text_exn view ~path ~inset_path ~text =
      change_text_exn
        (safe_area_inset_bottom_content_exn (find_safe_area_host_exn view ~path))
        ~path:inset_path
        ~text
    ;;

    let schedule_event_exn view action =
      match view.schedule_event with
      | Some schedule_event -> schedule_event action
      | None -> failwith "View has no event scheduler"
    ;;

    let change_toggle_exn view ~path ~is_on =
      let view = find_visible_exn view ~path in
      view.toggle_is_on <- is_on;
      match view.on_toggle with
      | Some f -> f is_on
      | None -> failwith "View has no toggle-change handler"
    ;;

    let change_slider_exn view ~path ~value =
      let view = find_visible_exn view ~path in
      view.slider_value <- Some value;
      match view.on_slider_change with
      | Some f -> f value
      | None -> failwith "View has no slider-change handler"
    ;;

    let change_stepper_exn view ~path ~value =
      let view = find_visible_exn view ~path in
      view.stepper_value <- Some value;
      match view.on_stepper_change with
      | Some f -> f value
      | None -> failwith "View has no stepper-change handler"
    ;;

    let select_date_exn view ~path ~selected =
      let view = find_visible_exn view ~path in
      view.selected_date <- Some selected;
      match view.on_select_date with
      | Some f -> f selected
      | None -> failwith "View has no date selection handler"
    ;;

    let select_color_exn view ~path ~selected =
      let view = find_visible_exn view ~path in
      view.selected_color <- Some selected;
      match view.on_select_color with
      | Some f -> f selected
      | None -> failwith "View has no color selection handler"
    ;;

    let click_menu_action_exn view ~path ~id =
      let view = find_visible_exn view ~path in
      match List.find view.menu_actions ~f:(fun action -> String.equal action.id id) with
      | Some action when action.is_enabled -> schedule_event_exn view action.on_click
      | Some _ -> failwithf "Menu action %S is disabled" id ()
      | None -> failwithf "View has no menu action with id %S" id ()
    ;;

    let change_disclosure_group_exn view ~path ~is_expanded =
      let view = find_visible_exn view ~path in
      view.disclosure_is_expanded <- is_expanded;
      match view.on_disclosure_change with
      | Some f -> f is_expanded
      | None -> failwith "View has no disclosure group handler"
    ;;

    let change_navigation_path_exn view ~path =
      view.navigation_path <- path;
      match view.on_navigation_path_change with
      | Some f -> f path
      | None -> failwith "View has no navigation path handler"
    ;;

    let refresh_list_exn view ~path =
      let view = find_visible_exn view ~path in
      match view.on_list_refresh with
      | Some f -> f ()
      | None -> failwith "View has no list refresh handler"
    ;;

    let delete_list_row_exn view ~path ~index =
      let view = find_visible_exn view ~path in
      match view.on_list_delete with
      | Some f -> f index
      | None -> failwith "View has no list delete handler"
    ;;

    let move_list_row_exn view ~path ~from_index ~to_index =
      let view = find_visible_exn view ~path in
      match view.on_list_move with
      | Some f -> f ~from_index ~to_index
      | None -> failwith "View has no list move handler"
    ;;

    let move_rows_exn = move_list_row_exn

    let focused_list_row_disappear_exn view ~path =
      let view = find_visible_exn view ~path in
      match view.on_focused_row_disappear with
      | Some f -> f ()
      | None -> failwith "View has no focused row disappear handler"
    ;;

    let submit_text_exn view ~path =
      let view = find_visible_exn view ~path in
      match view.on_click with
      | Some f -> f ()
      | None -> failwith "View has no text-submit handler"
    ;;

    let delete_backward_at_start_text_exn view ~path =
      let view = find_visible_exn view ~path in
      match view.on_text_delete_backward_at_start with
      | Some f -> f ()
      | None -> failwith "View has no text delete-backward-at-start handler"
    ;;

    let submit_safe_area_inset_bottom_text_exn view ~path ~inset_path =
      submit_text_exn
        (safe_area_inset_bottom_content_exn (find_safe_area_host_exn view ~path))
        ~path:inset_path
    ;;

    let select_photo_exn view ~path ~image_id =
      let view = find_visible_exn view ~path in
      view.placeholder <- Some image_id;
      match view.on_change with
      | Some f -> f image_id
      | None -> failwith "View has no photo-selection handler"
    ;;

    let select_safe_area_inset_bottom_photo_exn view ~path ~inset_path ~image_id =
      select_photo_exn
        (safe_area_inset_bottom_content_exn (find_safe_area_host_exn view ~path))
        ~path:inset_path
        ~image_id
    ;;

    let select_photo_payload_exn view ~path ~(payload : image_payload) =
      let view = find_visible_exn view ~path in
      view.placeholder <- Some payload.id;
      match view.on_change with
      | Some f -> f (image_payload_to_event_text payload)
      | None -> failwith "View has no photo-selection handler"
    ;;

    let capture_camera_exn view ~path ~image_id =
      let view = find_visible_exn view ~path in
      view.placeholder <- Some image_id;
      match view.on_change with
      | Some f -> f image_id
      | None -> failwith "View has no camera-capture handler"
    ;;

    let capture_camera_payload_exn view ~path ~(payload : image_payload) =
      let view = find_visible_exn view ~path in
      view.placeholder <- Some payload.id;
      match view.on_change with
      | Some f -> f (image_payload_to_event_text payload)
      | None -> failwith "View has no camera-capture handler"
    ;;

    let import_file_exn view ~path ~content =
      let view = find_visible_exn view ~path in
      match view.on_import_file with
      | Some f -> f content
      | None -> failwith "View has no file-import handler"
    ;;

    let presented_sheet_content_exn view =
      match
        List.find_map view.modifiers ~f:(function
          | Rendered_sheet { is_presented = true; content = Some content; _ } ->
            Some content
          | _ -> None)
      with
      | Some content -> content
      | None -> failwith "View has no presented sheet content"
    ;;

    let has_presented_sheet view =
      List.exists view.modifiers ~f:(function
        | Rendered_sheet { is_presented = true; content = Some _; _ } -> true
        | _ -> false)
    ;;

    let find_sheet_host_exn view ~path =
      let raw_view = find_raw_exn view ~path in
      if has_presented_sheet raw_view then raw_view else visible_view raw_view
    ;;

    let click_sheet_exn view ~path ~sheet_path =
      let view = find_sheet_host_exn view ~path in
      click_exn (presented_sheet_content_exn view) ~path:sheet_path
    ;;

    let click_sheet_menu_action_exn view ~path ~sheet_path ~id =
      let view = find_sheet_host_exn view ~path in
      click_menu_action_exn (presented_sheet_content_exn view) ~path:sheet_path ~id
    ;;

    let import_sheet_file_exn view ~path ~sheet_path ~content =
      let view = find_sheet_host_exn view ~path in
      import_file_exn (presented_sheet_content_exn view) ~path:sheet_path ~content
    ;;

    let change_sheet_text_exn view ~path ~sheet_path ~text =
      let view = find_sheet_host_exn view ~path in
      change_text_exn (presented_sheet_content_exn view) ~path:sheet_path ~text
    ;;

    let change_sheet_toggle_exn view ~path ~sheet_path ~is_on =
      let view = find_sheet_host_exn view ~path in
      change_toggle_exn (presented_sheet_content_exn view) ~path:sheet_path ~is_on
    ;;

    let move_sheet_rows_exn view ~path ~sheet_path ~from_index ~to_index =
      let view = find_sheet_host_exn view ~path in
      move_rows_exn
        (presented_sheet_content_exn view)
        ~path:sheet_path
        ~from_index
        ~to_index
    ;;

    let nested_sheet_host_exn view ~path ~host_path =
      let view = find_sheet_host_exn view ~path in
      presented_sheet_content_exn view |> find_exn ~path:host_path
    ;;

    let click_nested_sheet_exn view ~path ~host_path ~sheet_path =
      click_exn
        (presented_sheet_content_exn (nested_sheet_host_exn view ~path ~host_path))
        ~path:sheet_path
    ;;

    let change_nested_sheet_text_exn view ~path ~host_path ~sheet_path ~text =
      change_text_exn
        (presented_sheet_content_exn (nested_sheet_host_exn view ~path ~host_path))
        ~path:sheet_path
        ~text
    ;;

    let select_sheet_photo_exn view ~path ~sheet_path ~image_id =
      let view = find_sheet_host_exn view ~path in
      select_photo_exn (presented_sheet_content_exn view) ~path:sheet_path ~image_id
    ;;

    let select_sheet_photo_payload_exn view ~path ~sheet_path ~payload =
      let view = find_sheet_host_exn view ~path in
      select_photo_payload_exn
        (presented_sheet_content_exn view)
        ~path:sheet_path
        ~payload
    ;;

    let capture_sheet_camera_exn view ~path ~sheet_path ~image_id =
      let view = find_sheet_host_exn view ~path in
      capture_camera_exn (presented_sheet_content_exn view) ~path:sheet_path ~image_id
    ;;

    let capture_sheet_camera_payload_exn view ~path ~sheet_path ~payload =
      let view = find_sheet_host_exn view ~path in
      capture_camera_payload_exn
        (presented_sheet_content_exn view)
        ~path:sheet_path
        ~payload
    ;;

    let change_alert_text_exn view ~text =
      match
        List.find_map view.modifiers ~f:(function
          | Rendered_alert
              { is_presented = true; on_text_change = Some on_text_change; _ } ->
            Some on_text_change
          | _ -> None)
      with
      | Some on_text_change -> schedule_event_exn view (on_text_change text)
      | None -> failwith "Alert has no text-change handler"
    ;;

    let click_alert_action_exn view ~id =
      match
        List.find_map view.modifiers ~f:(function
          | Rendered_alert { is_presented = true; actions; _ } ->
            List.find actions ~f:(fun action -> String.equal action.id id)
          | _ -> None)
      with
      | Some action when action.is_enabled -> schedule_event_exn view action.on_click
      | Some _ -> failwithf "Alert action %S is disabled" id ()
      | None -> failwithf "Alert has no action with id %S" id ()
    ;;

    let click_confirmation_dialog_action_exn view ~id =
      match
        List.find_map view.modifiers ~f:(function
          | Rendered_confirmation_dialog { is_presented = true; actions; _ } ->
            List.find actions ~f:(fun action -> String.equal action.id id)
          | _ -> None)
      with
      | Some action when action.is_enabled -> schedule_event_exn view action.on_click
      | Some _ -> failwithf "Confirmation dialog action %S is disabled" id ()
      | None -> failwithf "Confirmation dialog has no action with id %S" id ()
    ;;

    let dismiss_popover_exn view =
      match
        List.find_map view.modifiers ~f:(function
          | Rendered_popover { is_presented = true; on_dismiss = Some on_dismiss; _ } ->
            Some on_dismiss
          | _ -> None)
      with
      | Some on_dismiss -> schedule_event_exn view on_dismiss
      | None -> failwith "View has no presented dismissible popover"
    ;;

    let change_nested_sheet_alert_text_exn view ~path ~host_path ~text =
      change_alert_text_exn (nested_sheet_host_exn view ~path ~host_path) ~text
    ;;

    let click_nested_sheet_alert_action_exn view ~path ~host_path ~id =
      click_alert_action_exn (nested_sheet_host_exn view ~path ~host_path) ~id
    ;;

    let change_search_exn view ~path ~text =
      let view = find_visible_exn view ~path in
      match
        List.find_map view.modifiers ~f:(function
          | Rendered_searchable { on_change; _ } -> Some on_change
          | _ -> None)
      with
      | Some on_change -> schedule_event_exn view (on_change text)
      | None -> failwith "View has no searchable modifier"
    ;;

    let click_toolbar_item_exn view ~path ~id =
      let raw_view = find_exn view ~path in
      let views = [ raw_view; visible_view raw_view ] in
      let find_grouped_item contents =
        List.find_map contents ~f:(function
          | Toolbar_group { items; _ } ->
            List.find items ~f:(fun item -> String.equal item.id id)
          | Toolbar_spacer _ -> None)
      in
      match
        List.find_map views ~f:(fun view ->
            List.find_map view.modifiers ~f:(function
              | Rendered_toolbar items ->
                List.find items ~f:(fun item -> String.equal item.id id)
              | Rendered_toolbar_groups contents -> find_grouped_item contents
              | _ -> None))
      with
      | Some item ->
        if item.is_enabled
        then schedule_event_exn view item.on_click
        else failwithf "Toolbar item %S is disabled" id ()
      | None -> failwithf "View has no toolbar item with id %S" id ()
    ;;

    let click_keyboard_toolbar_item_exn view ~path ~id =
      let view = find_visible_exn view ~path in
      match
        List.find_map view.modifiers ~f:(function
          | Rendered_keyboard_toolbar items ->
            List.find items ~f:(fun item -> String.equal item.id id)
          | _ -> None)
      with
      | Some item ->
        if item.is_enabled
        then schedule_event_exn view item.on_click
        else failwithf "Keyboard toolbar item %S is disabled" id ()
      | None -> failwithf "View has no keyboard toolbar item with id %S" id ()
    ;;

    let click_sheet_toolbar_item_exn view ~path ~id =
      let view = find_sheet_host_exn view ~path in
      click_toolbar_item_exn (presented_sheet_content_exn view) ~path:[] ~id
    ;;

    let click_nested_sheet_toolbar_item_exn view ~path ~host_path ~id =
      click_toolbar_item_exn
        (presented_sheet_content_exn (nested_sheet_host_exn view ~path ~host_path))
        ~path:[]
        ~id
    ;;

    let click_toolbar_menu_action_exn view ~path ~id ~title =
      let view = find_visible_exn view ~path in
      match
        List.find_map view.modifiers ~f:(function
          | Rendered_toolbar items ->
            Option.bind
              (List.find items ~f:(fun item -> String.equal item.id id))
              ~f:(fun item ->
                List.find item.menu_actions ~f:(fun action ->
                  String.equal action.title title))
          | _ -> None)
      with
      | Some action ->
        view.file_export <- action.file_export;
        schedule_event_exn view action.on_click
      | None ->
        failwithf "View has no toolbar menu action with id %S and title %S" id title ()
    ;;

    let dismiss_sheet_exn view ~path =
      let view = find_sheet_host_exn view ~path in
      match
        List.find_map view.modifiers ~f:(function
          | Rendered_sheet { is_presented = true; on_dismiss = Some on_dismiss; _ } ->
            Some on_dismiss
          | _ -> None)
      with
      | Some on_dismiss -> schedule_event_exn view on_dismiss
      | None -> failwith "View has no presented dismissible sheet"
    ;;

    let select_tab_exn view ~id =
      match view.on_select_tab with
      | Some f -> f id
      | None -> failwith "View has no tab selection handler"
    ;;

    let change_sidebar_bottom_search_exn view ~text =
      view.sidebar_bottom_search_text <- text;
      match view.sidebar_bottom_search_on_change with
      | Some f -> f text
      | None -> failwith "View has no sidebar bottom search handler"
    ;;

    let select_sidebar_route_exn view ~id =
      match view.on_select_tab with
      | Some f -> f id
      | None -> failwith "View has no sidebar route selection handler"
    ;;

    let click_sidebar_header_action_exn view ~id =
      match view.sidebar_header_action with
      | Some action when String.equal action.id id -> action.on_click ()
      | Some action ->
        failwithf "Expected sidebar header action id %s but found %s" id action.id ()
      | None -> failwith "View has no sidebar header action"
    ;;

    let click_sidebar_action_exn view ~id =
      match
        List.find view.sidebar_actions ~f:(fun action -> String.equal action.id id)
      with
      | Some action -> action.on_click ()
      | None -> failwithf "View has no sidebar action with id %s" id ()
    ;;

    let click_sidebar_action_menu_action_exn view ~id ~title =
      match
        List.find view.sidebar_actions ~f:(fun action -> String.equal action.id id)
      with
      | None -> failwithf "View has no sidebar action with id %s" id ()
      | Some action ->
        (match
           List.find action.menu_actions ~f:(fun menu_action ->
             String.equal menu_action.title title)
         with
         | Some menu_action -> menu_action.on_click ()
         | None ->
           failwithf "Sidebar action %s has no menu action with title %S" id title ())
    ;;

    let click_sidebar_history_action_exn view ~id =
      match
        List.find view.sidebar_history_actions ~f:(fun action ->
          String.equal action.id id)
      with
      | Some action -> action.on_click ()
      | None -> failwithf "View has no sidebar history action with id %s" id ()
    ;;

    let click_sidebar_history_action_menu_action_exn view ~id ~title =
      match
        List.find view.sidebar_history_actions ~f:(fun action ->
          String.equal action.id id)
      with
      | None -> failwithf "View has no sidebar history action with id %s" id ()
      | Some action ->
        (match
           List.find action.menu_actions ~f:(fun menu_action ->
             String.equal menu_action.title title)
         with
         | Some menu_action -> menu_action.on_click ()
         | None ->
           failwithf
             "Sidebar history action %s has no menu action with title %S"
             id
             title
             ())
    ;;

    let click_sidebar_bottom_action_exn view ~id =
      match view.sidebar_bottom_action with
      | Some action when String.equal action.id id -> action.on_click ()
      | Some action ->
        failwithf "Expected sidebar bottom action id %s but found %s" id action.id ()
      | None -> failwith "View has no sidebar bottom action"
    ;;

    let select_picker_exn view ~path ~id =
      let view = find_visible_exn view ~path in
      match view.on_select_picker with
      | Some f -> f id
      | None -> failwith "View has no picker selection handler"
    ;;

    let select_sheet_picker_exn view ~path ~sheet_path ~id =
      let view = find_sheet_host_exn view ~path in
      select_picker_exn (presented_sheet_content_exn view) ~path:sheet_path ~id
    ;;

    let click_row_leading_exn view ~path =
      let view = find_visible_exn view ~path |> navigation_link_label_or_self in
      match view.row_leading_button with
      | Some leading -> leading.on_click ()
      | None -> failwith "View has no row leading button"
    ;;

    let click_row_action_exn view ~path ~title =
      let view = find_visible_exn view ~path |> navigation_link_label_or_self in
      match
        List.find view.row_actions ~f:(fun action -> String.equal action.title title)
      with
      | Some action -> action.on_click ()
      | None -> failwithf "View has no row action with title %S" title ()
    ;;

    let click_context_menu_action_exn view ~path ~title =
      let view = find_visible_exn view ~path |> navigation_link_label_or_self in
      match
        List.find view.context_menu_actions ~f:(fun action ->
          String.equal action.title title)
      with
      | Some action ->
        (match view.schedule_event with
         | Some schedule_event -> schedule_event action.on_click
         | None -> action.on_click ())
      | None -> failwithf "View has no context menu action with title %S" title ()
    ;;

    let click_row_menu_action_exn view ~path ~title =
      let view = find_visible_exn view ~path |> navigation_link_label_or_self in
      match
        List.find view.row_menu_actions ~f:(fun action -> String.equal action.title title)
      with
      | Some action -> action.on_click ()
      | None -> failwithf "View has no row menu action with title %S" title ()
    ;;

    let appear_exn view ~path =
      let view = find_visible_exn view ~path in
      match view.on_appear with
      | Some on_appear -> on_appear ()
      | None -> failwith "View has no appear handler"
    ;;

    let click_sheet_row_menu_action_exn view ~path ~sheet_path ~title =
      let view = find_sheet_host_exn view ~path in
      click_row_menu_action_exn (presented_sheet_content_exn view) ~path:sheet_path ~title
    ;;

    let find_text_exn view ~path =
      let view = find_visible_exn view ~path in
      match view.text with
      | Some text -> text
      | None -> failwith "View has no text"
    ;;
  end
end
