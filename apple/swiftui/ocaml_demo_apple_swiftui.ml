module Apple = Ocaml_demo_apple

module Option = struct
  include Stdlib.Option

  let map t ~f = map f t
  let iter t ~f = iter f t
  let value t ~default = value ~default t
end

module List = struct
  include Stdlib.List

  let map t ~f = map f t
  let iter t ~f = iter f t
end

module Int = struct
  include Stdlib.Int

  module Table = struct
    type 'a t = (int, 'a) Stdlib.Hashtbl.t

    let create () = Stdlib.Hashtbl.create 128
  end

  let incr = Stdlib.incr
  let of_string = int_of_string
end

module Bool = struct
  include Stdlib.Bool

  let of_string value =
    match value with
    | "true" | "1" -> true
    | "false" | "0" -> false
    | _ -> invalid_arg "Bool.of_string"
  ;;
end

module Hashtbl = struct
  include Stdlib.Hashtbl

  let find table key = find_opt table key
  let set table ~key ~data = replace table key data
end

module String = struct
  include Stdlib.String

  let is_empty value = length value = 0

  let split value ~on =
    let rec loop start index acc =
      if index = length value
      then List.rev (sub value start (index - start) :: acc)
      else if Stdlib.Char.equal (get value index) on
      then loop (index + 1) (index + 1) (sub value start (index - start) :: acc)
      else loop start (index + 1) acc
    in
    loop 0 0 []
  ;;

  let lsplit2 value ~on =
    match index_opt value on with
    | None -> None
    | Some index ->
      Some (sub value 0 index, sub value (index + 1) (length value - index - 1))
  ;;
end

type native = nativeint
type application_delegate = nativeint
type application = nativeint
type launch_options = nativeint
type controller = nativeint
type window = nativeint

external register_event_callback
  :  (int -> string option -> unit)
  -> unit
  = "ocaml_demo_apple_swiftui_register_event_callback"

external register_lazy_list_callbacks
  :  (int -> int -> string)
  -> (int -> int -> native)
  -> (int -> int -> unit)
  -> unit
  = "ocaml_demo_apple_swiftui_register_lazy_list_callbacks"

external run_application
  :  (application_delegate -> application -> launch_options -> bool)
  -> unit
  = "ocaml_demo_apple_swiftui_run_application"

external run_on_main : (unit -> unit) -> unit = "ocaml_demo_apple_swiftui_run_on_main"

external run_on_main_when_scroll_idle
  :  (unit -> unit)
  -> unit
  = "ocaml_demo_apple_swiftui_run_on_main_when_scroll_idle"

external run_on_main_after_rendered_frame
  :  (unit -> unit)
  -> unit
  = "ocaml_demo_apple_swiftui_run_on_main_after_rendered_frame"

external set_native_clipboard_text
  :  string
  -> unit
  = "ocaml_demo_apple_swiftui_set_clipboard_text"

external set_native_clipboard_image_file
  :  string
  -> unit
  = "ocaml_demo_apple_swiftui_set_clipboard_image_file"

external toggle_native_audio_file_playback
  :  string
  -> unit
  = "ocaml_demo_apple_swiftui_toggle_audio_file_playback"

external start_native_audio_recording
  :  unit
  -> unit
  = "ocaml_demo_apple_swiftui_start_audio_recording"

external stop_native_audio_recording_and_transcribe
  :  unit
  -> string
  = "ocaml_demo_apple_swiftui_stop_audio_recording_and_transcribe"

let audio_recording_result_of_native value =
  match String.split value ~on:'\t' with
  | [ transcript; local_path; filename; content_type; byte_size ] ->
    let transcript =
      let transcript = String.trim transcript in
      if String.is_empty transcript then "Audio recording" else transcript
    in
    let local_path = String.trim local_path in
    let filename =
      let filename = String.trim filename in
      if String.is_empty filename then "recording.m4a" else filename
    in
    let content_type =
      let content_type = String.trim content_type in
      if String.is_empty content_type then "audio/mp4" else content_type
    in
    let byte_size =
      try Int.of_string (String.trim byte_size) with
      | Failure _ -> 0
    in
    Apple.{ transcript; local_path; filename; content_type; byte_size }
  | _ ->
    Apple.
      { transcript = "Audio recording"
      ; local_path = ""
      ; filename = "recording.m4a"
      ; content_type = "audio/mp4"
      ; byte_size = 0
      }
;;

let () = Apple.set_clipboard_text_handler set_native_clipboard_text
let () = Apple.set_clipboard_image_file_handler set_native_clipboard_image_file
let () = Apple.set_toggle_audio_file_playback_handler toggle_native_audio_file_playback

let () =
  Apple.set_audio_recording_handlers
    ~start:start_native_audio_recording
    ~stop_and_transcribe:(fun () ->
      stop_native_audio_recording_and_transcribe () |> audio_recording_result_of_native)
;;

external create_node : int -> native = "ocaml_demo_apple_swiftui_create_node"
external release_node : native -> unit = "ocaml_demo_apple_swiftui_release_node"
external set_native_text : native -> string -> unit = "ocaml_demo_apple_swiftui_set_text"

external set_native_system_image
  :  native
  -> string option
  -> unit
  = "ocaml_demo_apple_swiftui_set_system_image"

external set_native_button_subtitle
  :  native
  -> string option
  -> unit
  = "ocaml_demo_apple_swiftui_set_button_subtitle"

external set_native_button_style
  :  native
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_button_style"

external set_native_title_visible
  :  native
  -> bool
  -> unit
  = "ocaml_demo_apple_swiftui_set_title_visible"

external set_native_keyboard_dismiss_controls
  :  native
  -> bool
  -> unit
  = "ocaml_demo_apple_swiftui_set_keyboard_dismiss_controls"

external set_native_scroll_dismisses_keyboard
  :  native
  -> bool
  -> unit
  = "ocaml_demo_apple_swiftui_set_scroll_dismisses_keyboard"

external set_native_hide_list_row_separator
  :  native
  -> bool
  -> unit
  = "ocaml_demo_apple_swiftui_set_hide_list_row_separator"

external set_native_image_source
  :  native
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_image_source"

external set_native_image_color
  :  native
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_image_color"

external set_native_image_style
  :  native
  -> float
  -> float
  -> unit
  = "ocaml_demo_apple_swiftui_set_image_style"

external set_native_text_attributes
  :  native
  -> int
  -> int
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_text_attributes"

external set_native_enabled : native -> bool -> unit = "ocaml_demo_apple_swiftui_set_enabled"

external set_native_placeholder
  :  native
  -> string option
  -> unit
  = "ocaml_demo_apple_swiftui_set_placeholder"

external set_native_text_field_style
  :  native
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_text_field_style"

external set_native_text_field_axis
  :  native
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_text_field_axis"

external set_native_text_field_clear_button
  :  native
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_text_field_clear_button"

external set_native_text_field_secure
  :  native
  -> bool
  -> unit
  = "ocaml_demo_apple_swiftui_set_text_field_secure"

external set_native_text_field_focus
  :  native
  -> bool
  -> unit
  = "ocaml_demo_apple_swiftui_set_text_field_focus"

external set_native_text_field_blur
  :  native
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_text_field_blur"

external set_native_text_field_delete_backward_at_start
  :  native
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_text_field_delete_backward_at_start"

external set_native_toggle
  :  native
  -> bool
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_toggle"

external set_native_progress
  :  native
  -> float
  -> unit
  = "ocaml_demo_apple_swiftui_set_progress"

external set_native_regular_material_panel
  :  native
  -> float
  -> unit
  = "ocaml_demo_apple_swiftui_set_regular_material_panel"

external set_native_secondary_system_grouped_panel
  :  native
  -> float
  -> unit
  = "ocaml_demo_apple_swiftui_set_secondary_system_grouped_panel"

external set_native_secondary_fill_panel
  :  native
  -> float
  -> float
  -> unit
  = "ocaml_demo_apple_swiftui_set_secondary_fill_panel"

external set_native_liquid_glass_panel
  :  native
  -> float
  -> bool
  -> int
  -> float
  -> unit
  = "ocaml_demo_apple_swiftui_set_liquid_glass_panel"

external set_native_spacing
  :  native
  -> float option
  -> unit
  = "ocaml_demo_apple_swiftui_set_spacing"

external set_native_horizontal_stack_alignment
  :  native
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_horizontal_stack_alignment"

external set_native_grid
  :  native
  -> int
  -> float
  -> unit
  = "ocaml_demo_apple_swiftui_set_grid"

external set_native_children
  :  native
  -> native array
  -> unit
  = "ocaml_demo_apple_swiftui_set_children"

external set_native_lazy_list_rows
  :  native
  -> int
  -> int
  -> int
  -> int array
  -> int array
  -> string array
  -> int array
  -> string array
  -> native array
  -> unit
  = "ocaml_demo_apple_swiftui_set_lazy_list_rows_bytecode"
    "ocaml_demo_apple_swiftui_set_lazy_list_rows"

external set_native_lazy_list_rows_published_event
  :  native
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_lazy_list_rows_published_event"

external clear_native_lazy_list_rows
  :  native
  -> unit
  = "ocaml_demo_apple_swiftui_clear_lazy_list_rows"

external set_native_list_behavior
  :  native
  -> int
  -> int
  -> int
  -> bool
  -> unit
  = "ocaml_demo_apple_swiftui_set_list_behavior"

external set_native_list_focused_row_index
  :  native
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_list_focused_row_index"

external set_native_list_focused_row_disappear_event
  :  native
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_list_focused_row_disappear_event"

external set_native_on_click : native -> int -> unit = "ocaml_demo_apple_swiftui_set_on_click"

external set_native_navigation_link_callbacks
  :  native
  -> int
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_navigation_link_callbacks"

external set_native_navigation_link_value
  :  native
  -> string option
  -> unit
  = "ocaml_demo_apple_swiftui_set_navigation_link_value"

external set_native_tap_action
  :  native
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_tap_action"

external set_native_horizontal_swipe
  :  native
  -> int
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_horizontal_swipe"

external set_native_on_appear
  :  native
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_on_appear"

external set_native_on_change
  :  native
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_on_change"

external set_native_list_row_subtitle
  :  native
  -> string option
  -> unit
  = "ocaml_demo_apple_swiftui_set_list_row_subtitle"

external set_native_list_row_trailing_text
  :  native
  -> string option
  -> unit
  = "ocaml_demo_apple_swiftui_set_list_row_trailing_text"

external set_native_list_row_content_style
  :  native
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_list_row_content_style"

external set_native_list_row_accessory
  :  native
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_list_row_accessory"

external set_native_list_row_title_strikethrough
  :  native
  -> bool
  -> unit
  = "ocaml_demo_apple_swiftui_set_list_row_title_strikethrough"

external set_native_list_row_leading_system_image
  :  native
  -> string option
  -> unit
  = "ocaml_demo_apple_swiftui_set_list_row_leading_system_image"

external set_native_list_row_preview_image_path
  :  native
  -> string option
  -> unit
  = "ocaml_demo_apple_swiftui_set_list_row_preview_image_path"

external set_native_list_row_leading
  :  native
  -> string option
  -> string option
  -> bool
  -> unit
  = "ocaml_demo_apple_swiftui_set_list_row_leading"

external set_native_list_row_leading_accessibility
  :  native
  -> string
  -> unit
  = "ocaml_demo_apple_swiftui_set_list_row_leading_accessibility"

external set_native_list_row_leading_event
  :  native
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_list_row_leading_event"

external set_native_section
  :  native
  -> string option
  -> unit
  = "ocaml_demo_apple_swiftui_set_section"

external clear_native_picker
  :  native
  -> string
  -> string
  -> int
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_clear_picker"

external append_native_picker_option
  :  native
  -> string
  -> string
  -> unit
  = "ocaml_demo_apple_swiftui_append_picker_option"

external set_native_file_exporter
  :  native
  -> string
  -> string
  -> string
  -> unit
  = "ocaml_demo_apple_swiftui_set_file_exporter"

external set_native_share_link
  :  native
  -> string
  -> unit
  = "ocaml_demo_apple_swiftui_set_share_link"

external set_native_file_importer
  :  native
  -> string array
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_file_importer"

external set_native_slider
  :  native
  -> string
  -> float
  -> float
  -> float
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_slider_bytecode" "ocaml_demo_apple_swiftui_set_slider"

external set_native_stepper
  :  native
  -> string
  -> int
  -> int
  -> int
  -> int
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_stepper_bytecode" "ocaml_demo_apple_swiftui_set_stepper"

external set_native_date_picker
  :  native
  -> string
  -> string
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_date_picker"

external set_native_color_picker
  :  native
  -> string
  -> string
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_color_picker"

external clear_native_menu
  :  native
  -> string
  -> string option
  -> unit
  = "ocaml_demo_apple_swiftui_clear_menu"

external append_native_menu_action
  :  native
  -> string
  -> string
  -> string option
  -> int
  -> bool
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_append_menu_action_bytecode"
    "ocaml_demo_apple_swiftui_append_menu_action"

external set_native_disclosure_group
  :  native
  -> string
  -> bool
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_disclosure_group"

external set_native_navigation_path_stack
  :  native
  -> string array
  -> int
  -> string array
  -> unit
  = "ocaml_demo_apple_swiftui_set_navigation_path_stack"

external set_native_image_payload_mode
  :  native
  -> bool
  -> unit
  = "ocaml_demo_apple_swiftui_set_image_payload_mode"

external clear_native_list_row_actions
  :  native
  -> unit
  = "ocaml_demo_apple_swiftui_clear_list_row_actions"

external append_native_list_row_action
  :  native
  -> string
  -> string option
  -> int
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_append_list_row_action"

external clear_native_list_row_menu_actions
  :  native
  -> unit
  = "ocaml_demo_apple_swiftui_clear_list_row_menu_actions"

external append_native_list_row_menu_action
  :  native
  -> string
  -> string option
  -> int
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_append_list_row_menu_action"

external clear_native_context_menu_actions
  :  native
  -> unit
  = "ocaml_demo_apple_swiftui_clear_context_menu_actions"

external append_native_context_menu_action
  :  native
  -> string
  -> string option
  -> int
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_append_context_menu_action"

external set_native_searchable
  :  native
  -> int
  -> string
  -> string option
  -> (bool * int) option
  -> unit
  = "ocaml_demo_apple_swiftui_set_searchable"

external clear_native_searchable
  :  native
  -> unit
  = "ocaml_demo_apple_swiftui_clear_searchable"

external set_native_sheet
  :  native
  -> native option
  -> bool
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_sheet"

external set_native_sheet_detents
  :  native
  -> int array
  -> float array
  -> unit
  = "ocaml_demo_apple_swiftui_set_sheet_detents"

external set_native_safe_area_inset_bottom
  :  native
  -> native option
  -> unit
  = "ocaml_demo_apple_swiftui_set_safe_area_inset_bottom"

external set_native_popover
  :  native
  -> native option
  -> bool
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_popover"

external set_native_alert
  :  native
  -> bool
  -> int
  -> string option
  -> string option
  -> unit
  = "ocaml_demo_apple_swiftui_set_alert"

external set_native_alert_text_field
  :  native
  -> string option
  -> string option
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_alert_text_field"

external clear_native_alert_actions
  :  native
  -> unit
  = "ocaml_demo_apple_swiftui_clear_alert_actions"

external append_native_alert_action
  :  native
  -> string
  -> string
  -> int
  -> bool
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_append_alert_action_bytecode"
    "ocaml_demo_apple_swiftui_append_alert_action"

external set_native_confirmation_dialog
  :  native
  -> bool
  -> int
  -> string option
  -> string option
  -> unit
  = "ocaml_demo_apple_swiftui_set_confirmation_dialog"

external clear_native_confirmation_dialog_actions
  :  native
  -> unit
  = "ocaml_demo_apple_swiftui_clear_confirmation_dialog_actions"

external append_native_confirmation_dialog_action
  :  native
  -> string
  -> string
  -> int
  -> bool
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_append_confirmation_dialog_action_bytecode"
    "ocaml_demo_apple_swiftui_append_confirmation_dialog_action"

external set_native_navigation_title
  :  native
  -> string option
  -> unit
  = "ocaml_demo_apple_swiftui_set_navigation_title"

external clear_native_toolbar : native -> unit = "ocaml_demo_apple_swiftui_clear_toolbar"

external append_native_toolbar_item
  :  native
  -> string
  -> string
  -> string option
  -> bool
  -> bool
  -> string option
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_append_toolbar_item_bytecode"
    "ocaml_demo_apple_swiftui_append_toolbar_item"

external append_native_toolbar_group
  :  native
  -> string
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_append_toolbar_group"

external append_native_toolbar_spacer
  :  native
  -> string
  -> int
  -> bool
  -> unit
  = "ocaml_demo_apple_swiftui_append_toolbar_spacer"

external append_native_toolbar_group_item
  :  native
  -> string
  -> string
  -> string
  -> string option
  -> bool
  -> bool
  -> string option
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_append_toolbar_group_item_bytecode"
    "ocaml_demo_apple_swiftui_append_toolbar_group_item"

external clear_native_keyboard_toolbar
  :  native
  -> unit
  = "ocaml_demo_apple_swiftui_clear_keyboard_toolbar"

external append_native_keyboard_toolbar_item
  :  native
  -> string
  -> string
  -> string option
  -> bool
  -> bool
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_append_keyboard_toolbar_item_bytecode"
    "ocaml_demo_apple_swiftui_append_keyboard_toolbar_item"

external append_native_toolbar_menu_action
  :  native
  -> string
  -> string
  -> string option
  -> int
  -> int
  -> bool
  -> string option
  -> string option
  -> string option
  -> unit
  = "ocaml_demo_apple_swiftui_append_toolbar_menu_action_bytecode"
    "ocaml_demo_apple_swiftui_append_toolbar_menu_action"

external set_native_padding
  :  native
  -> float
  -> float
  -> float
  -> float
  -> unit
  = "ocaml_demo_apple_swiftui_set_padding"

external set_native_frame
  :  native
  -> float
  -> float
  -> float
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_frame"

external clear_native_tabs
  :  native
  -> string
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_clear_tabs"

external append_native_tab
  :  native
  -> string
  -> string
  -> string option
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_append_tab"

external clear_native_sidebar_shell
  :  native
  -> string option
  -> bool
  -> string option
  -> string
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_clear_sidebar_shell_bytecode"
    "ocaml_demo_apple_swiftui_clear_sidebar_shell"

external set_native_sidebar_header_action
  :  native
  -> string option
  -> string option
  -> string option
  -> string option
  -> string option
  -> string option
  -> int
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_sidebar_header_action_byte"
    "ocaml_demo_apple_swiftui_set_sidebar_header_action"

external append_native_sidebar_action
  :  native
  -> string
  -> string
  -> string option
  -> string option
  -> string option
  -> int
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_append_sidebar_action_byte"
    "ocaml_demo_apple_swiftui_append_sidebar_action"

external append_native_sidebar_action_menu_action
  :  native
  -> string
  -> string option
  -> int
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_append_sidebar_action_menu_action"

external set_native_sidebar_history_title
  :  native
  -> string option
  -> unit
  = "ocaml_demo_apple_swiftui_set_sidebar_history_title"

external append_native_sidebar_history_action
  :  native
  -> string
  -> string
  -> string option
  -> string option
  -> string option
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_append_sidebar_history_action_byte"
    "ocaml_demo_apple_swiftui_append_sidebar_history_action"

external append_native_sidebar_history_action_menu_action
  :  native
  -> string
  -> string option
  -> int
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_append_sidebar_history_action_menu_action"

external set_native_sidebar_bottom_action
  :  native
  -> string option
  -> string option
  -> string option
  -> int
  -> int
  -> string option
  -> int
  -> unit
  = "ocaml_demo_apple_swiftui_set_sidebar_bottom_action_byte"
    "ocaml_demo_apple_swiftui_set_sidebar_bottom_action"

external make_native_controller
  :  native
  -> controller
  = "ocaml_demo_apple_swiftui_make_controller"

external update_native_controller
  :  controller
  -> native
  -> unit
  = "ocaml_demo_apple_swiftui_update_controller"

external release_controller
  :  controller
  -> unit
  = "ocaml_demo_apple_swiftui_release_controller"

external make_native_window : native -> window = "ocaml_demo_apple_swiftui_make_window"
external release_window : window -> unit = "ocaml_demo_apple_swiftui_release_window"

external http_send_json_native
  :  string
  -> string
  -> string option
  -> string
  -> float
  -> (bool -> string -> unit)
  -> unit
  = "ocaml_demo_apple_swiftui_http_send_json_bytecode" "ocaml_demo_apple_swiftui_http_send_json"

module Http = struct
  type request =
    { method_ : string
    ; url : string
    ; authorization : string option
    ; body : string
    ; timeout_seconds : float
    }

  let send_json request =
    fun () ->
    let result = ref (Error "request did not complete synchronously") in
    http_send_json_native
      request.method_
      request.url
      request.authorization
      request.body
      request.timeout_seconds
      (fun success response -> result := if success then Ok response else Error response);
    !result
  ;;
end

let no_event = -1

type event_handler =
  | Click of (unit -> unit)
  | Change of (string -> unit)

let next_event_id = ref 0
let event_handlers : event_handler Int.Table.t = Int.Table.create ()

let install_handler event_id handler =
  match event_id with
  | Some event_id ->
    Hashtbl.set event_handlers ~key:event_id ~data:handler;
    event_id
  | None ->
    Int.incr next_event_id;
    Hashtbl.set event_handlers ~key:!next_event_id ~data:handler;
    !next_event_id
;;

let clear_handler = Option.iter ~f:(Hashtbl.remove event_handlers)

let dispatch_event event_id text =
  match Hashtbl.find event_handlers event_id with
  | None -> ()
  | Some (Click f) -> f ()
  | Some (Change f) -> f (Option.value text ~default:"")
;;

let () = register_event_callback dispatch_event

let node_kind_id = function
  | Apple.Label -> 0
  | Apple.Button -> 1
  | Apple.Text_field -> 2
  | Apple.Text_editor -> 3
  | Apple.Toggle -> 22
  | Apple.Stack Apple.Vertical -> 4
  | Apple.Stack Apple.Horizontal -> 5
  | Apple.Z_stack -> 26
  | Apple.Spacer -> 27
  | Apple.Divider -> 28
  | Apple.Form -> 29
  | Apple.Grid -> 38
  | Apple.Scroll_view -> 6
  | Apple.List -> 7
  | Apple.Movable_rows -> 37
  | Apple.Navigation_stack -> 8
  | Apple.Navigation_path_stack -> 30
  | Apple.Navigation_link -> 24
  | Apple.Navigation_split -> 20
  | Apple.Adaptive_layout -> 21
  | Apple.Tab_view -> 9
  | Apple.Sidebar_split -> 16
  | Apple.Image -> 10
  | Apple.List_row -> 11
  | Apple.Section -> 12
  | Apple.Picker -> 13
  | Apple.Slider -> 31
  | Apple.Stepper -> 32
  | Apple.Date_picker -> 33
  | Apple.Color_picker -> 34
  | Apple.Menu -> 35
  | Apple.Disclosure_group -> 36
  | Apple.Custom_view _ -> 14
  | Apple.Photo_picker -> 15
  | Apple.Share_link -> 23
  | Apple.File_exporter -> 17
  | Apple.File_importer -> 18
  | Apple.Camera_capture -> 19
  | Apple.Progress_view -> 25
  | Apple.Congrats_effect -> 14
;;

module Backend = struct
  type view =
    { native : native
    ; mutable click_event_id : int option
    ; mutable navigation_activate_event_id : int option
    ; mutable navigation_deactivate_event_id : int option
    ; mutable tap_event_id : int option
    ; mutable horizontal_swipe_left_event_id : int option
    ; mutable horizontal_swipe_right_event_id : int option
    ; mutable appear_event_id : int option
    ; mutable change_event_id : int option
    ; mutable text_blur_event_id : int option
    ; mutable text_delete_backward_at_start_event_id : int option
    ; mutable search_event_id : int option
    ; mutable search_presentation_event_id : int option
    ; mutable tab_select_event_id : int option
    ; mutable sheet_dismiss_event_id : int option
    ; mutable popover_dismiss_event_id : int option
    ; mutable alert_event_ids : int list
    ; mutable confirmation_dialog_event_ids : int list
    ; mutable toolbar_event_ids : int list
    ; mutable keyboard_toolbar_event_ids : int list
    ; mutable picker_select_event_id : int option
    ; mutable list_event_ids : int list
    ; mutable menu_event_ids : int list
    ; mutable row_event_ids : int list
    ; mutable context_menu_event_ids : int list
    ; mutable sidebar_event_ids : int list
    ; mutable sidebar_search_event_id : int option
    ; mutable lazy_list_provider_id : int option
    ; mutable lazy_list_native_length : int option
    ; mutable lazy_list_native_version : int option
    ; mutable lazy_list_native_stale_indices : int list
    ; mutable lazy_list_rows_published_event_id : int option
    ; mutable controller : controller option
    }

  and lazy_list_provider =
    { key_row : int -> string
    ; render_row : int -> view
    ; release_row : int -> unit
    }

  let next_lazy_list_provider_id = ref 0
  let lazy_list_providers : (int, lazy_list_provider) Hashtbl.t = Hashtbl.create 128

  let create kind =
    let native = create_node (node_kind_id kind) in
    (match kind with
     | Apple.Congrats_effect -> set_native_text native "congrats-effect"
     | Apple.Custom_view kind -> set_native_text native kind
     | _ -> ());
    { native
    ; click_event_id = None
    ; navigation_activate_event_id = None
    ; navigation_deactivate_event_id = None
    ; tap_event_id = None
    ; horizontal_swipe_left_event_id = None
    ; horizontal_swipe_right_event_id = None
    ; appear_event_id = None
    ; change_event_id = None
    ; text_blur_event_id = None
    ; text_delete_backward_at_start_event_id = None
    ; search_event_id = None
    ; search_presentation_event_id = None
    ; tab_select_event_id = None
    ; sheet_dismiss_event_id = None
    ; popover_dismiss_event_id = None
    ; alert_event_ids = []
    ; confirmation_dialog_event_ids = []
    ; toolbar_event_ids = []
    ; keyboard_toolbar_event_ids = []
    ; picker_select_event_id = None
    ; list_event_ids = []
    ; menu_event_ids = []
    ; row_event_ids = []
    ; context_menu_event_ids = []
    ; sidebar_event_ids = []
    ; sidebar_search_event_id = None
    ; lazy_list_provider_id = None
    ; lazy_list_native_length = None
    ; lazy_list_native_version = None
    ; lazy_list_native_stale_indices = []
    ; lazy_list_rows_published_event_id = None
    ; controller = None
    }
  ;;

  let clear_lazy_list_provider view =
    Option.iter view.lazy_list_provider_id ~f:(Hashtbl.remove lazy_list_providers);
    view.lazy_list_provider_id <- None;
    view.lazy_list_native_length <- None;
    view.lazy_list_native_version <- None;
    view.lazy_list_native_stale_indices <- [];
    Option.iter view.lazy_list_rows_published_event_id ~f:(Hashtbl.remove event_handlers);
    view.lazy_list_rows_published_event_id <- None;
    clear_native_lazy_list_rows view.native
  ;;

  let destroy view =
    clear_lazy_list_provider view;
    clear_handler view.click_event_id;
    clear_handler view.tap_event_id;
    clear_handler view.horizontal_swipe_left_event_id;
    clear_handler view.horizontal_swipe_right_event_id;
    clear_handler view.appear_event_id;
    clear_handler view.change_event_id;
    clear_handler view.text_blur_event_id;
    clear_handler view.text_delete_backward_at_start_event_id;
    clear_handler view.search_event_id;
    clear_handler view.search_presentation_event_id;
    clear_handler view.tab_select_event_id;
    clear_handler view.sheet_dismiss_event_id;
    clear_handler view.popover_dismiss_event_id;
    List.iter view.alert_event_ids ~f:(Hashtbl.remove event_handlers);
    List.iter view.confirmation_dialog_event_ids ~f:(Hashtbl.remove event_handlers);
    List.iter view.toolbar_event_ids ~f:(fun event_id -> clear_handler (Some event_id));
    List.iter view.keyboard_toolbar_event_ids ~f:(fun event_id ->
      clear_handler (Some event_id));
    clear_handler view.picker_select_event_id;
    List.iter view.list_event_ids ~f:(Hashtbl.remove event_handlers);
    List.iter view.menu_event_ids ~f:(Hashtbl.remove event_handlers);
    clear_handler view.sidebar_search_event_id;
    List.iter view.row_event_ids ~f:(Hashtbl.remove event_handlers);
    List.iter view.context_menu_event_ids ~f:(Hashtbl.remove event_handlers);
    List.iter view.sidebar_event_ids ~f:(Hashtbl.remove event_handlers);
    Option.iter view.controller ~f:release_controller;
    view.controller <- None;
    release_node view.native
  ;;

  let set_text view text = set_native_text view.native text

  let set_system_image view system_image =
    set_native_system_image view.native system_image
  ;;

  let set_button_subtitle view subtitle = set_native_button_subtitle view.native subtitle

  let set_button_style view style =
    let style_id =
      match style with
      | Apple.Bordered -> 0
      | Apple.Bordered_prominent -> 1
      | Apple.Plain -> 2
    in
    set_native_button_style view.native style_id
  ;;

  let set_title_visible view is_visible = set_native_title_visible view.native is_visible
  let set_enabled view is_enabled = set_native_enabled view.native is_enabled

  let image_source_id = function
    | Apple.System_image -> 0
    | Apple.File_image -> 1
  ;;

  let set_image_source view source =
    set_native_image_source view.native (image_source_id source)
  ;;

  let optional_text_color_id = function
    | None -> -1
    | Some Apple.Primary -> 0
    | Some Apple.Secondary -> 1
    | Some Apple.Tertiary -> 2
    | Some Apple.Red -> 3
    | Some Apple.Green -> 4
    | Some Apple.Orange -> 5
    | Some Apple.Blue -> 6
    | Some Apple.Accent -> 7
  ;;

  let set_image_color view color =
    set_native_image_color view.native (optional_text_color_id color)
  ;;

  let optional_float_value = function
    | None -> -1.
    | Some value -> value
  ;;

  let set_image_style view ~max_height ~corner_radius =
    set_native_image_style
      view.native
      (optional_float_value max_height)
      (optional_float_value corner_radius)
  ;;

  let text_style_id = function
    | Apple.Large_title -> 0
    | Apple.Title -> 1
    | Apple.Title2 -> 2
    | Apple.Title3 -> 3
    | Apple.Headline -> 4
    | Apple.Body -> 5
    | Apple.Callout -> 6
    | Apple.Subheadline -> 7
    | Apple.Footnote -> 8
    | Apple.Caption -> 9
    | Apple.Caption2 -> 10
  ;;

  let text_weight_id = function
    | Apple.Regular -> 0
    | Apple.Medium -> 1
    | Apple.Semibold -> 2
    | Apple.Bold -> 3
  ;;

  let text_color_id = function
    | Apple.Primary -> 0
    | Apple.Secondary -> 1
    | Apple.Tertiary -> 2
    | Apple.Red -> 3
    | Apple.Green -> 4
    | Apple.Orange -> 5
    | Apple.Blue -> 6
    | Apple.Accent -> 7
  ;;

  let set_text_attributes view (attributes : Apple.text_attributes) =
    set_native_text_attributes
      view.native
      (text_style_id attributes.Apple.style)
      (text_weight_id attributes.weight)
      (text_color_id attributes.color)
  ;;

  let set_placeholder view placeholder = set_native_placeholder view.native placeholder

  let text_field_style_id = function
    | Apple.Rounded_border -> 0
    | Apple.Pill -> 1
    | Apple.Plain_text -> 2
  ;;

  let set_text_field_style view style =
    set_native_text_field_style view.native (text_field_style_id style)
  ;;

  let text_field_axis_id = function
    | Apple.Horizontal -> 0
    | Apple.Vertical -> 1
  ;;

  let text_field_clear_button_id = function
    | Apple.No_clear_button -> 0
    | Apple.While_editing -> 1
  ;;

  let set_text_field_axis view axis =
    set_native_text_field_axis view.native (text_field_axis_id axis)
  ;;

  let set_text_field_clear_button view clear_button =
    set_native_text_field_clear_button
      view.native
      (text_field_clear_button_id clear_button)
  ;;

  let set_text_field_secure view is_secure =
    set_native_text_field_secure view.native is_secure
  ;;

  let set_text_field_focus view is_focused =
    set_native_text_field_focus view.native is_focused
  ;;

  let set_text_field_blur view handler =
    let event_id =
      match handler with
      | None -> no_event
      | Some handler -> install_handler view.text_blur_event_id (Click handler)
    in
    view.text_blur_event_id <- (if event_id = no_event then None else Some event_id);
    set_native_text_field_blur view.native event_id
  ;;

  let set_text_field_delete_backward_at_start view handler =
    let event_id =
      match handler with
      | None -> no_event
      | Some handler ->
        install_handler view.text_delete_backward_at_start_event_id (Click handler)
    in
    view.text_delete_backward_at_start_event_id
    <- (if event_id = no_event then None else Some event_id);
    set_native_text_field_delete_backward_at_start view.native event_id
  ;;

  let set_toggle view ~is_on ~on_change =
    let event_id =
      install_handler
        view.change_event_id
        (Change (fun value -> on_change (Bool.of_string value)))
    in
    view.change_event_id <- Some event_id;
    set_native_toggle view.native is_on event_id
  ;;

  let set_progress view ~value = set_native_progress view.native value
  let set_spacing view spacing = set_native_spacing view.native spacing

  let set_horizontal_stack_alignment view alignment =
    let alignment_id =
      match alignment with
      | Apple.Stack_center -> 0
      | Apple.Stack_top -> 1
    in
    set_native_horizontal_stack_alignment view.native alignment_id
  ;;

  let set_grid view ~columns ~spacing = set_native_grid view.native columns spacing

  let set_children view ~keyed:_ children =
    clear_lazy_list_provider view;
    set_native_children
      view.native
      (Array.of_list (List.map children ~f:(fun child -> child.native)))
  ;;

  let should_publish_lazy_list_rows view ~length ~version ~stale_indices =
    not
      (Option.equal Int.equal view.lazy_list_native_length (Some length)
       && Option.equal Int.equal view.lazy_list_native_version (Some version)
       && List.equal Int.equal view.lazy_list_native_stale_indices stale_indices)
  ;;

  let set_lazy_list_rows view ~length ~version ~stale_indices ~identity_keys
      ~cached_rows ~key_row ~render_row ~release_row ~on_rows_published =
    let provider_id =
      match view.lazy_list_provider_id with
      | Some provider_id -> provider_id
      | None ->
        Int.incr next_lazy_list_provider_id;
        let provider_id = !next_lazy_list_provider_id in
        view.lazy_list_provider_id <- Some provider_id;
        provider_id
    in
    Hashtbl.set lazy_list_providers ~key:provider_id ~data:{ key_row; render_row; release_row };
    Option.iter view.lazy_list_rows_published_event_id ~f:(Hashtbl.remove event_handlers);
    let rows_published_event_id =
      match on_rows_published with
      | None ->
        view.lazy_list_rows_published_event_id <- None;
        no_event
      | Some on_rows_published ->
        let event_id = install_handler None (Click on_rows_published) in
        view.lazy_list_rows_published_event_id <- Some event_id;
        event_id
    in
    if should_publish_lazy_list_rows view ~length ~version ~stale_indices
    then (
      view.lazy_list_native_length <- Some length;
      view.lazy_list_native_version <- Some version;
      view.lazy_list_native_stale_indices <- stale_indices;
      set_native_lazy_list_rows_published_event view.native rows_published_event_id;
      let identity_indices =
        Array.of_list (List.map identity_keys ~f:(fun (index, _) -> index))
      in
      let identity_values =
        Array.of_list (List.map identity_keys ~f:(fun (_, key) -> key))
      in
      let cached_indices =
        Array.of_list (List.map cached_rows ~f:(fun (index, _, _) -> index))
      in
      let cached_keys =
        Array.of_list (List.map cached_rows ~f:(fun (_, key, _) -> key))
      in
      let cached_row_pointers =
        Array.of_list
          (List.map cached_rows ~f:(fun (_, _, row) -> row.native))
      in
      set_native_lazy_list_rows view.native provider_id length version
        (Array.of_list stale_indices)
        identity_indices
        identity_values
        cached_indices
        cached_keys
        cached_row_pointers)
  ;;

  let set_list_behavior
        view
        ~on_refresh
        ~on_delete
        ~on_move
        ~on_focused_row_disappear
        ~edit_mode
        ~focused_row_key:_
        ~focused_row_index
    =
    List.iter view.list_event_ids ~f:(Hashtbl.remove event_handlers);
    view.list_event_ids <- [];
    let install_click = function
      | None -> no_event
      | Some f ->
        let event_id = install_handler None (Click f) in
        view.list_event_ids <- event_id :: view.list_event_ids;
        event_id
    in
    let install_change = function
      | None -> no_event
      | Some f ->
        let event_id = install_handler None (Change f) in
        view.list_event_ids <- event_id :: view.list_event_ids;
        event_id
    in
    let refresh_event_id = install_click on_refresh in
    let delete_event_id =
      install_change
        (Option.map on_delete ~f:(fun on_delete ->
           fun payload -> on_delete (Int.of_string payload)))
    in
    let move_event_id =
      install_change
        (Option.map on_move ~f:(fun on_move ->
           fun payload ->
           match String.lsplit2 payload ~on:':' with
           | Some (from_index, to_index) ->
             on_move
               ~from_index:(Int.of_string from_index)
               ~to_index:(Int.of_string to_index)
           | None -> ()))
    in
    let focused_row_disappear_event_id = install_click on_focused_row_disappear in
    set_native_list_behavior
      view.native
      refresh_event_id
      delete_event_id
      move_event_id
      edit_mode;
    set_native_list_focused_row_disappear_event
      view.native
      focused_row_disappear_event_id;
    set_native_list_focused_row_index
      view.native
      (Option.value focused_row_index ~default:(-1))
  ;;

  let set_tabs view ~selected ~on_select (tabs : Apple.rendered_tab list) =
    let event_id =
      match on_select with
      | None ->
        clear_handler view.tab_select_event_id;
        view.tab_select_event_id <- None;
        no_event
      | Some on_select ->
        let event_id =
          install_handler view.tab_select_event_id (Change (fun id -> on_select id))
        in
        view.tab_select_event_id <- Some event_id;
        event_id
    in
    clear_native_tabs view.native selected event_id;
    List.iter tabs ~f:(fun tab ->
      append_native_tab
        view.native
        tab.Apple.id
        tab.title
        tab.system_image
        (match tab.role with
         | None -> 0
         | Some Apple.Search -> 1))
  ;;

  let set_sidebar_shell
        view
        ~title
        ~compact_top_bar_visible
        ~(header_action : Apple.rendered_sidebar_action option)
        ~(actions : Apple.rendered_sidebar_action list)
        ~history_title
        ~(history_actions : Apple.rendered_sidebar_action list)
        ~bottom_search_placeholder
        ~bottom_search_text
        ~bottom_search_on_change
        ~(bottom_action : Apple.rendered_sidebar_action option)
    =
    List.iter view.sidebar_event_ids ~f:(Hashtbl.remove event_handlers);
    view.sidebar_event_ids <- [];
    let install_sidebar_action (action : Apple.rendered_sidebar_action) =
      let event_id = install_handler None (Click action.on_click) in
      view.sidebar_event_ids <- event_id :: view.sidebar_event_ids;
      event_id
    in
    let sidebar_action_chrome_id = function
      | Apple.Default_chrome -> 0
      | Apple.Prominent_capsule -> 1
      | Apple.Liquid_icon -> 2
    in
    let bottom_search_event_id =
      match bottom_search_on_change with
      | None ->
        clear_handler view.sidebar_search_event_id;
        view.sidebar_search_event_id <- None;
        no_event
      | Some on_change ->
        let event_id =
          install_handler
            view.sidebar_search_event_id
            (Change (fun text -> on_change text))
        in
        view.sidebar_search_event_id <- Some event_id;
        event_id
    in
    clear_native_sidebar_shell
      view.native
      title
      compact_top_bar_visible
      bottom_search_placeholder
      bottom_search_text
      bottom_search_event_id;
    set_native_sidebar_history_title view.native history_title;
    (match header_action with
     | None ->
       set_native_sidebar_header_action view.native None None None None None None no_event 1
     | Some action ->
       set_native_sidebar_header_action
         view.native
         (Some action.Apple.id)
         (Some action.title)
         action.system_image
         action.avatar_image
         action.avatar_initial
         action.selects_tab
         (install_sidebar_action action)
         (Bool.to_int action.closes_sidebar));
    List.iter actions ~f:(fun action ->
      append_native_sidebar_action
        view.native
        action.Apple.id
        action.title
        action.subtitle
        action.system_image
        action.selects_tab
        (install_sidebar_action action)
        (Bool.to_int action.closes_sidebar);
      List.iter action.menu_actions ~f:(fun menu_action ->
        let event_id = install_handler None (Click menu_action.on_click) in
        view.sidebar_event_ids <- event_id :: view.sidebar_event_ids;
        let style_id =
          match menu_action.style with
          | Apple.Default -> 0
          | Apple.Destructive -> 1
        in
        append_native_sidebar_action_menu_action
          view.native
          menu_action.title
          menu_action.system_image
          style_id
          event_id));
    List.iter history_actions ~f:(fun action ->
      append_native_sidebar_history_action
        view.native
        action.Apple.id
        action.title
        action.subtitle
        action.system_image
        action.selects_tab
        (install_sidebar_action action);
      List.iter action.menu_actions ~f:(fun menu_action ->
        let event_id = install_handler None (Click menu_action.on_click) in
        view.sidebar_event_ids <- event_id :: view.sidebar_event_ids;
        let style_id =
          match menu_action.style with
          | Apple.Default -> 0
          | Apple.Destructive -> 1
        in
        append_native_sidebar_history_action_menu_action
          view.native
          menu_action.title
          menu_action.system_image
          style_id
          event_id));
    match bottom_action with
    | None -> set_native_sidebar_bottom_action view.native None None None no_event 0 None 1
    | Some action ->
      set_native_sidebar_bottom_action
        view.native
        (Some action.Apple.id)
        (Some action.title)
        action.system_image
        (install_sidebar_action action)
        (sidebar_action_chrome_id action.chrome)
        action.selects_tab
        (Bool.to_int action.closes_sidebar)
  ;;

  let set_section view ~title = set_native_section view.native title

  let set_picker
        view
        ~title
        ~selected
        ~(style : Apple.picker_style)
        ~on_select
        (options : Apple.rendered_picker_option list)
    =
    let event_id =
      match on_select with
      | None ->
        clear_handler view.picker_select_event_id;
        view.picker_select_event_id <- None;
        no_event
      | Some on_select ->
        let event_id =
          install_handler view.picker_select_event_id (Change (fun id -> on_select id))
        in
        view.picker_select_event_id <- Some event_id;
        event_id
    in
    let style_id =
      match style with
      | Apple.Menu -> 0
      | Apple.Segmented -> 1
    in
    clear_native_picker view.native title selected style_id event_id;
    List.iter options ~f:(fun option ->
      append_native_picker_option view.native option.Apple.id option.title)
  ;;

  let set_slider view ~title ~value ~min ~max ~on_change =
    let event_id =
      match on_change with
      | None ->
        clear_handler view.change_event_id;
        view.change_event_id <- None;
        no_event
      | Some on_change ->
        let event_id =
          install_handler
            view.change_event_id
            (Change (fun value -> on_change (Float.of_string value)))
        in
        view.change_event_id <- Some event_id;
        event_id
    in
    set_native_slider view.native title value min max event_id
  ;;

  let set_stepper view ~title ~value ~min ~max ~step ~on_change =
    let event_id =
      match on_change with
      | None ->
        clear_handler view.change_event_id;
        view.change_event_id <- None;
        no_event
      | Some on_change ->
        let event_id =
          install_handler
            view.change_event_id
            (Change (fun value -> on_change (Int.of_string value)))
        in
        view.change_event_id <- Some event_id;
        event_id
    in
    set_native_stepper view.native title value min max step event_id
  ;;

  let set_date_picker view ~title ~selected ~on_select =
    let event_id =
      match on_select with
      | None ->
        clear_handler view.change_event_id;
        view.change_event_id <- None;
        no_event
      | Some on_select ->
        let event_id = install_handler view.change_event_id (Change on_select) in
        view.change_event_id <- Some event_id;
        event_id
    in
    Printf.eprintf
      "[SimpleOutlinerDebug] bridge_set_date_picker title=%s selected=%s event=%d\n%!"
      title selected event_id;
    set_native_date_picker view.native title selected event_id
  ;;

  let set_color_picker view ~title ~selected ~on_select =
    let event_id =
      match on_select with
      | None ->
        clear_handler view.change_event_id;
        view.change_event_id <- None;
        no_event
      | Some on_select ->
        let event_id = install_handler view.change_event_id (Change on_select) in
        view.change_event_id <- Some event_id;
        event_id
    in
    set_native_color_picker view.native title selected event_id
  ;;

  let style_id = function
    | Apple.Default -> 0
    | Apple.Destructive -> 1
  ;;

  let set_menu
        view
        ~title
        ~system_image
        ~(actions : Apple.menu_action list)
        ~schedule_event
    =
    List.iter view.menu_event_ids ~f:(Hashtbl.remove event_handlers);
    view.menu_event_ids <- [];
    clear_native_menu view.native title system_image;
    List.iter actions ~f:(fun action ->
      let event_id =
        install_handler None (Click (fun () -> schedule_event action.on_click))
      in
      view.menu_event_ids <- event_id :: view.menu_event_ids;
      append_native_menu_action
        view.native
        action.id
        action.title
        action.system_image
        (style_id action.style)
        action.is_enabled
        event_id)
  ;;

  let set_disclosure_group view ~title ~is_expanded ~on_change =
    let event_id =
      match on_change with
      | None ->
        clear_handler view.change_event_id;
        view.change_event_id <- None;
        no_event
      | Some on_change ->
        let event_id =
          install_handler
            view.change_event_id
            (Change (fun value -> on_change (Bool.of_string value)))
        in
        view.change_event_id <- Some event_id;
        event_id
    in
    set_native_disclosure_group view.native title is_expanded event_id
  ;;

  let set_navigation_path_stack view ~path ~on_path_change ~destinations =
    let event_id =
      match on_path_change with
      | None ->
        clear_handler view.change_event_id;
        view.change_event_id <- None;
        no_event
      | Some on_path_change ->
        let event_id =
          install_handler
            view.change_event_id
            (Change
               (fun payload ->
                 let path =
                   if String.is_empty payload then [] else String.split payload ~on:'\n'
                 in
                 on_path_change path))
        in
        view.change_event_id <- Some event_id;
        event_id
    in
    set_native_navigation_path_stack
      view.native
      (Array.of_list path)
      event_id
      (Array.of_list destinations)
  ;;

  let set_file_exporter view (export : Apple.file_export) =
    set_native_file_exporter
      view.native
      export.filename
      export.content_type
      export.content
  ;;

  let set_share_link view (share_link : Apple.share_link) =
    set_native_share_link view.native share_link.url
  ;;

  let set_file_importer view ~allowed_content_types ~on_select =
    let event_id =
      match on_select with
      | None ->
        clear_handler view.change_event_id;
        view.change_event_id <- None;
        no_event
      | Some on_select ->
        let event_id =
          install_handler view.change_event_id (Change (fun content -> on_select content))
        in
        view.change_event_id <- Some event_id;
        event_id
    in
    set_native_file_importer view.native (Array.of_list allowed_content_types) event_id
  ;;

  let set_image_payload_mode view wants_payload =
    set_native_image_payload_mode view.native wants_payload
  ;;

  let set_on_click view handler =
    match handler with
    | None ->
      clear_handler view.click_event_id;
      view.click_event_id <- None;
      set_native_on_click view.native no_event
    | Some handler ->
      let event_id = install_handler view.click_event_id (Click handler) in
      view.click_event_id <- Some event_id;
      set_native_on_click view.native event_id
  ;;

  let set_navigation_link_callbacks view ~on_activate ~on_deactivate =
    let install existing handler =
      match handler with
      | None ->
        clear_handler existing;
        None, no_event
      | Some handler ->
        let event_id = install_handler existing (Click handler) in
        Some event_id, event_id
    in
    let activate_event_id, native_activate_event_id =
      install view.navigation_activate_event_id on_activate
    in
    let deactivate_event_id, native_deactivate_event_id =
      install view.navigation_deactivate_event_id on_deactivate
    in
    view.navigation_activate_event_id <- activate_event_id;
    view.navigation_deactivate_event_id <- deactivate_event_id;
    set_native_navigation_link_callbacks
      view.native
      native_activate_event_id
      native_deactivate_event_id
  ;;

  let set_navigation_link_value view value =
    set_native_navigation_link_value view.native value
  ;;

  let set_tap_action view handler =
    match handler with
    | None ->
      clear_handler view.tap_event_id;
      view.tap_event_id <- None;
      set_native_tap_action view.native no_event
    | Some handler ->
      let event_id = install_handler view.tap_event_id (Click handler) in
      view.tap_event_id <- Some event_id;
      set_native_tap_action view.native event_id
  ;;

  let set_horizontal_swipe view handlers =
    let clear () =
      clear_handler view.horizontal_swipe_left_event_id;
      clear_handler view.horizontal_swipe_right_event_id;
      view.horizontal_swipe_left_event_id <- None;
      view.horizontal_swipe_right_event_id <- None;
      set_native_horizontal_swipe view.native no_event no_event
    in
    match handlers with
    | None -> clear ()
    | Some (on_left, on_right) ->
      let left_event_id =
        install_handler view.horizontal_swipe_left_event_id (Click on_left)
      in
      let right_event_id =
        install_handler view.horizontal_swipe_right_event_id (Click on_right)
      in
      view.horizontal_swipe_left_event_id <- Some left_event_id;
      view.horizontal_swipe_right_event_id <- Some right_event_id;
      set_native_horizontal_swipe view.native left_event_id right_event_id
  ;;

  let set_on_appear view handler =
    match handler with
    | None ->
      clear_handler view.appear_event_id;
      view.appear_event_id <- None;
      set_native_on_appear view.native no_event
    | Some handler ->
      let event_id = install_handler view.appear_event_id (Click handler) in
      view.appear_event_id <- Some event_id;
      set_native_on_appear view.native event_id
  ;;

  let set_on_change view handler =
    match handler with
    | None ->
      clear_handler view.change_event_id;
      view.change_event_id <- None;
      set_native_on_change view.native no_event
    | Some handler ->
      let event_id = install_handler view.change_event_id (Change handler) in
      view.change_event_id <- Some event_id;
      set_native_on_change view.native event_id
  ;;

  let list_row_content_style_id = function
    | Apple.Standard -> 0
    | Apple.Summary -> 1
    | Apple.Detail -> 2
  ;;

  let list_row_accessory_id = function
    | Apple.No_accessory -> 0
    | Apple.Disclosure_indicator -> 1
  ;;

  let clear_row_events view =
    List.iter view.row_event_ids ~f:(Hashtbl.remove event_handlers);
    view.row_event_ids <- []
  ;;

  let install_row_event view f =
    Int.incr next_event_id;
    Hashtbl.set event_handlers ~key:!next_event_id ~data:(Click f);
    view.row_event_ids <- !next_event_id :: view.row_event_ids;
    !next_event_id
  ;;

  let install_context_menu view ~schedule_event ~(actions : Apple.row_action list) =
    List.iter view.context_menu_event_ids ~f:(Hashtbl.remove event_handlers);
    view.context_menu_event_ids <- [];
    clear_native_context_menu_actions view.native;
    List.iter actions ~f:(fun action ->
      let event_id =
        install_handler None (Click (fun () -> schedule_event action.on_click))
      in
      view.context_menu_event_ids <- event_id :: view.context_menu_event_ids;
      append_native_context_menu_action
        view.native
        action.title
        action.system_image
        (style_id action.style)
        event_id)
  ;;

  let refresh_list_row_callbacks
        view
        ~on_click
        ~(leading_button : Apple.rendered_row_leading_button option)
        ~(swipe_actions : Apple.rendered_row_action list)
        ~(menu_actions : Apple.rendered_row_action list)
    =
    set_on_click view on_click;
    clear_row_events view;
    (match leading_button with
     | None -> set_native_list_row_leading_event view.native no_event
     | Some leading ->
       let event_id = install_row_event view leading.Apple.on_click in
       set_native_list_row_leading_event view.native event_id);
    clear_native_list_row_actions view.native;
    List.iter swipe_actions ~f:(fun action ->
      let event_id = install_row_event view action.Apple.on_click in
      append_native_list_row_action
        view.native
        action.title
        action.system_image
        (style_id action.style)
        event_id);
    clear_native_list_row_menu_actions view.native;
    List.iter menu_actions ~f:(fun action ->
      let event_id = install_row_event view action.Apple.on_click in
      append_native_list_row_menu_action
        view.native
        action.title
        action.system_image
        (style_id action.style)
        event_id)
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
        ~(leading_button : Apple.rendered_row_leading_button option)
        ~(swipe_actions : Apple.rendered_row_action list)
        ~(menu_actions : Apple.rendered_row_action list)
    =
    clear_row_events view;
    set_native_text view.native title;
    set_native_list_row_subtitle view.native subtitle;
    set_native_list_row_trailing_text view.native trailing_text;
    set_native_list_row_content_style
      view.native
      (list_row_content_style_id content_style);
    set_native_list_row_accessory view.native (list_row_accessory_id accessory);
    set_native_list_row_leading_system_image view.native leading_system_image;
    set_native_list_row_preview_image_path view.native preview_image_path;
    set_native_list_row_title_strikethrough view.native title_strikethrough;
    (match leading_button with
     | None ->
       set_native_list_row_leading view.native None None false;
       set_native_list_row_leading_accessibility view.native ""
     | Some leading ->
       set_native_list_row_leading
         view.native
         (Some leading.system_image)
         leading.selected_system_image
         leading.selected;
       set_native_list_row_leading_accessibility view.native leading.accessibility_label);
    refresh_list_row_callbacks
      view
      ~on_click:None
      ~leading_button
      ~swipe_actions
      ~menu_actions
  ;;

  let install_searchable
        view
        ~schedule_event
        ~text
        ~is_presented
        ~prompt
        ~on_change
        ~on_presented_change
    =
    let event_id =
      install_handler
        view.search_event_id
        (Change (fun text -> schedule_event (on_change text)))
    in
    view.search_event_id <- Some event_id;
    let presentation =
      match is_presented, on_presented_change with
      | Some is_presented, Some on_presented_change ->
        let event_id =
          install_handler
            view.search_presentation_event_id
            (Change
               (fun text ->
                 schedule_event
                   (on_presented_change (String.equal text "true"))))
        in
        view.search_presentation_event_id <- Some event_id;
        Some (is_presented, event_id)
      | _ ->
        clear_handler view.search_presentation_event_id;
        view.search_presentation_event_id <- None;
        None
    in
    set_native_searchable view.native event_id text prompt presentation
  ;;

  let clear_searchable view =
    clear_handler view.search_event_id;
    view.search_event_id <- None;
    clear_handler view.search_presentation_event_id;
    view.search_presentation_event_id <- None;
    clear_native_searchable view.native
  ;;

  let detent_id_and_value : Apple.presentation_detent -> int * float = function
    | Apple.Medium -> 0, 0.
    | Apple.Large -> 1, 0.
    | Apple.Fraction fraction -> 2, fraction
    | Apple.Height height -> 3, height
  ;;

  let install_sheet view ~schedule_event ~is_presented ~content ~detents ~on_dismiss =
    let dismiss_event_id =
      match on_dismiss with
      | None ->
        clear_handler view.sheet_dismiss_event_id;
        view.sheet_dismiss_event_id <- None;
        no_event
      | Some on_dismiss ->
        let event_id =
          install_handler
            view.sheet_dismiss_event_id
            (Click (fun () -> schedule_event on_dismiss))
        in
        view.sheet_dismiss_event_id <- Some event_id;
        event_id
    in
    set_native_sheet
      view.native
      (Option.map content ~f:(fun content -> content.native))
      is_presented
      dismiss_event_id;
    let detents = List.map detents ~f:detent_id_and_value in
    set_native_sheet_detents
      view.native
      (Array.of_list (List.map detents ~f:fst))
      (Array.of_list (List.map detents ~f:snd))
  ;;

  let clear_sheet view =
    clear_handler view.sheet_dismiss_event_id;
    view.sheet_dismiss_event_id <- None;
    set_native_sheet view.native None false no_event;
    set_native_sheet_detents view.native [||] [||]
  ;;

  let install_popover view ~schedule_event ~is_presented ~content ~on_dismiss =
    let dismiss_event_id =
      match on_dismiss with
      | None ->
        clear_handler view.popover_dismiss_event_id;
        view.popover_dismiss_event_id <- None;
        no_event
      | Some on_dismiss ->
        let event_id =
          install_handler
            view.popover_dismiss_event_id
            (Click (fun () -> schedule_event on_dismiss))
        in
        view.popover_dismiss_event_id <- Some event_id;
        event_id
    in
    set_native_popover
      view.native
      (Option.map content ~f:(fun content -> content.native))
      is_presented
      dismiss_event_id
  ;;

  let clear_popover view =
    clear_handler view.popover_dismiss_event_id;
    view.popover_dismiss_event_id <- None;
    set_native_popover view.native None false no_event
  ;;

  let set_safe_area_inset_bottom view content =
    set_native_safe_area_inset_bottom
      view.native
      (Option.map content ~f:(fun content -> content.native))
  ;;

  let alert_role_id = function
    | Apple.Alert_default -> 0
    | Alert_cancel -> 1
    | Alert_destructive -> 2
  ;;

  let clear_alert_events view =
    List.iter view.alert_event_ids ~f:(Hashtbl.remove event_handlers);
    view.alert_event_ids <- []
  ;;

  let install_alert
        view
        ~schedule_event
        ~is_presented
        ~title
        ~message
        ~text
        ~placeholder
        ~on_text_change
        ~actions
        ~on_dismiss
    =
    clear_alert_events view;
    let install_click action =
      let event_id = install_handler None (Click (fun () -> schedule_event action)) in
      view.alert_event_ids <- event_id :: view.alert_event_ids;
      event_id
    in
    let dismiss_event_id =
      match on_dismiss with
      | None -> no_event
      | Some on_dismiss -> install_click on_dismiss
    in
    let text_event_id =
      match text, on_text_change with
      | Some _, Some on_text_change ->
        let event_id =
          install_handler None (Change (fun text -> schedule_event (on_text_change text)))
        in
        view.alert_event_ids <- event_id :: view.alert_event_ids;
        event_id
      | _ -> no_event
    in
    set_native_alert view.native is_presented dismiss_event_id (Some title) message;
    set_native_alert_text_field view.native text placeholder text_event_id;
    clear_native_alert_actions view.native;
    List.iter actions ~f:(fun (action : Apple.alert_action) ->
      append_native_alert_action
        view.native
        action.id
        action.title
        (alert_role_id action.role)
        action.is_enabled
        (install_click action.on_click))
  ;;

  let clear_alert view =
    clear_alert_events view;
    set_native_alert view.native false no_event None None;
    set_native_alert_text_field view.native None None no_event;
    clear_native_alert_actions view.native
  ;;

  let install_confirmation_dialog
        view
        ~schedule_event
        ~is_presented
        ~title
        ~message
        ~actions
        ~on_dismiss
    =
    List.iter view.confirmation_dialog_event_ids ~f:(Hashtbl.remove event_handlers);
    view.confirmation_dialog_event_ids <- [];
    let install_click action =
      let event_id = install_handler None (Click (fun () -> schedule_event action)) in
      view.confirmation_dialog_event_ids <- event_id :: view.confirmation_dialog_event_ids;
      event_id
    in
    let dismiss_event_id =
      match on_dismiss with
      | None -> no_event
      | Some on_dismiss -> install_click on_dismiss
    in
    set_native_confirmation_dialog
      view.native
      is_presented
      dismiss_event_id
      (Some title)
      message;
    clear_native_confirmation_dialog_actions view.native;
    List.iter actions ~f:(fun (action : Apple.alert_action) ->
      append_native_confirmation_dialog_action
        view.native
        action.id
        action.title
        (alert_role_id action.role)
        action.is_enabled
        (install_click action.on_click))
  ;;

  let clear_confirmation_dialog view =
    List.iter view.confirmation_dialog_event_ids ~f:(Hashtbl.remove event_handlers);
    view.confirmation_dialog_event_ids <- [];
    set_native_confirmation_dialog view.native false no_event None None;
    clear_native_confirmation_dialog_actions view.native
  ;;

  let install_toolbar view ~schedule_event items =
    List.iter view.toolbar_event_ids ~f:(fun event_id -> clear_handler (Some event_id));
    view.toolbar_event_ids <- [];
    clear_native_toolbar view.native;
    let install_item append_item (item : Apple.toolbar_item) =
      let event_id =
        install_handler None (Click (fun () -> schedule_event item.on_click))
      in
      view.toolbar_event_ids <- event_id :: view.toolbar_event_ids;
      append_item item event_id;
      List.iter item.menu_actions ~f:(fun action ->
        let event_id =
          install_handler None (Click (fun () -> schedule_event action.on_click))
        in
        view.toolbar_event_ids <- event_id :: view.toolbar_event_ids;
        append_native_toolbar_menu_action
          view.native
          item.id
          action.title
          action.system_image
          (style_id action.style)
          event_id
          action.starts_section
          (Option.map action.file_export ~f:(fun export -> export.filename))
          (Option.map action.file_export ~f:(fun export -> export.content_type))
          (Option.map action.file_export ~f:(fun export -> export.content)))
    in
    List.iter items ~f:(fun item ->
      install_item
        (fun item event_id ->
          append_native_toolbar_item
            view.native
            item.id
            item.title
            item.system_image
            item.is_title_visible
            item.is_enabled
            item.share_url
            event_id)
        item)
  ;;

  let toolbar_placement_id = function
    | Apple.Automatic -> 0
    | Apple.Bottom_bar -> 1
  ;;

  let install_toolbar_groups view ~schedule_event contents =
    List.iter view.toolbar_event_ids ~f:(fun event_id -> clear_handler (Some event_id));
    view.toolbar_event_ids <- [];
    clear_native_toolbar view.native;
    let install_group_item group_id (item : Apple.toolbar_item) =
      let event_id =
        install_handler None (Click (fun () -> schedule_event item.on_click))
      in
      view.toolbar_event_ids <- event_id :: view.toolbar_event_ids;
      append_native_toolbar_group_item
        view.native
        group_id
        item.id
        item.title
        item.system_image
        item.is_title_visible
        item.is_enabled
        item.share_url
        event_id;
      List.iter item.menu_actions ~f:(fun action ->
        let event_id =
          install_handler None (Click (fun () -> schedule_event action.on_click))
        in
        view.toolbar_event_ids <- event_id :: view.toolbar_event_ids;
        append_native_toolbar_menu_action
          view.native
          item.id
          action.title
          action.system_image
          (style_id action.style)
          event_id
          action.starts_section
          (Option.map action.file_export ~f:(fun export -> export.filename))
          (Option.map action.file_export ~f:(fun export -> export.content_type))
          (Option.map action.file_export ~f:(fun export -> export.content)))
    in
    List.iter contents ~f:(function
      | Apple.Toolbar_group { id; placement; items } ->
        append_native_toolbar_group view.native id (toolbar_placement_id placement);
        List.iter items ~f:(install_group_item id)
      | Apple.Toolbar_spacer { id; placement; fixed } ->
        append_native_toolbar_spacer
          view.native
          id
          (toolbar_placement_id placement)
          fixed)
  ;;

  let clear_toolbar view =
    List.iter view.toolbar_event_ids ~f:(fun event_id -> clear_handler (Some event_id));
    view.toolbar_event_ids <- [];
    clear_native_toolbar view.native
  ;;

  let install_keyboard_toolbar view ~schedule_event items =
    List.iter view.keyboard_toolbar_event_ids ~f:(fun event_id ->
      clear_handler (Some event_id));
    view.keyboard_toolbar_event_ids <- [];
    clear_native_keyboard_toolbar view.native;
    List.iter items ~f:(fun (item : Apple.toolbar_item) ->
      let event_id =
        install_handler None (Click (fun () -> schedule_event item.on_click))
      in
      view.keyboard_toolbar_event_ids <- event_id :: view.keyboard_toolbar_event_ids;
      append_native_keyboard_toolbar_item
        view.native
        item.id
        item.title
        item.system_image
        item.is_title_visible
        item.is_enabled
        event_id)
  ;;

  let clear_keyboard_toolbar view =
    List.iter view.keyboard_toolbar_event_ids ~f:(fun event_id ->
      clear_handler (Some event_id));
    view.keyboard_toolbar_event_ids <- [];
    clear_native_keyboard_toolbar view.native
  ;;

  let set_modifiers view ~schedule_event modifiers =
    let saw_searchable = ref false in
    let saw_sheet = ref false in
    let saw_popover = ref false in
    let saw_confirmation_dialog = ref false in
    let saw_safe_area_inset_bottom = ref false in
    let saw_alert = ref false in
    let saw_toolbar = ref false in
    let saw_toolbar_groups = ref false in
    let saw_keyboard_toolbar = ref false in
    let saw_padding = ref false in
    let saw_regular_material_panel = ref false in
    let saw_secondary_system_grouped_panel = ref false in
    let saw_secondary_fill_panel = ref false in
    let saw_liquid_glass_panel = ref false in
    let saw_context_menu = ref false in
    let saw_frame = ref false in
    let saw_navigation_title = ref false in
    let saw_tap_action = ref false in
    let saw_horizontal_swipe = ref false in
    let saw_on_appear = ref false in
    let saw_keyboard_dismiss_controls = ref false in
    let saw_scroll_dismisses_keyboard = ref false in
    let saw_hide_list_row_separator = ref false in
    let pending_sheet = ref None in
    let install_pending_sheet () =
      match !pending_sheet with
      | Some (is_presented, content, detents, on_dismiss) ->
        install_sheet view ~schedule_event ~is_presented ~content ~detents ~on_dismiss
      | None -> clear_sheet view
    in
    List.iter modifiers ~f:(function
      | Apple.Rendered_searchable
          { text; is_presented; prompt; on_change; on_presented_change } ->
        saw_searchable := true;
        install_searchable
          view
          ~schedule_event
          ~text
          ~is_presented
          ~prompt
          ~on_change
          ~on_presented_change
      | Apple.Rendered_sheet { is_presented; content; detents; on_dismiss } ->
        saw_sheet := true;
        if is_presented && Option.is_none !pending_sheet
        then pending_sheet := Some (is_presented, content, detents, on_dismiss)
      | Apple.Rendered_popover { is_presented; content; on_dismiss } ->
        saw_popover := true;
        install_popover view ~schedule_event ~is_presented ~content ~on_dismiss
      | Apple.Rendered_confirmation_dialog
          { is_presented; title; message; actions; on_dismiss } ->
        saw_confirmation_dialog := true;
        install_confirmation_dialog
          view
          ~schedule_event
          ~is_presented
          ~title
          ~message
          ~actions
          ~on_dismiss
      | Apple.Rendered_safe_area_inset_bottom { content } ->
        saw_safe_area_inset_bottom := true;
        set_safe_area_inset_bottom view (Some content)
      | Apple.Rendered_alert
          { is_presented
          ; title
          ; message
          ; text
          ; placeholder
          ; on_text_change
          ; actions
          ; on_dismiss
          } ->
        saw_alert := true;
        install_alert
          view
          ~schedule_event
          ~is_presented
          ~title
          ~message
          ~text
          ~placeholder
          ~on_text_change
          ~actions
          ~on_dismiss
      | Apple.Rendered_padding { top; leading; bottom; trailing } ->
        saw_padding := true;
        set_native_padding view.native top leading bottom trailing
      | Apple.Rendered_regular_material_panel { corner_radius } ->
        saw_regular_material_panel := true;
        set_native_regular_material_panel view.native corner_radius
      | Apple.Rendered_secondary_system_grouped_panel { corner_radius } ->
        saw_secondary_system_grouped_panel := true;
        set_native_secondary_system_grouped_panel view.native corner_radius
      | Apple.Rendered_secondary_fill_panel { corner_radius; opacity } ->
        saw_secondary_fill_panel := true;
        set_native_secondary_fill_panel view.native corner_radius opacity
      | Apple.Rendered_liquid_glass_panel
          { corner_radius; is_transparent; tint_color; tint_opacity } ->
        saw_liquid_glass_panel := true;
        set_native_liquid_glass_panel
          view.native
          corner_radius
          is_transparent
          (optional_text_color_id tint_color)
          tint_opacity
      | Apple.Rendered_context_menu actions ->
        saw_context_menu := true;
        install_context_menu view ~schedule_event ~actions
      | Apple.Rendered_frame { width; height; max_width; alignment } ->
        saw_frame := true;
        let alignment_id =
          match alignment with
          | None | Some Apple.Center -> 0
          | Some Apple.Leading -> 1
        in
        set_native_frame
          view.native
          (Option.value width ~default:(-1.))
          (Option.value height ~default:(-1.))
          (Option.value max_width ~default:(-1.))
          alignment_id
      | Apple.Rendered_navigation_title title ->
        saw_navigation_title := true;
        set_native_navigation_title view.native (Some title)
      | Apple.Rendered_toolbar items ->
        saw_toolbar := true;
        install_toolbar view ~schedule_event items
      | Apple.Rendered_toolbar_groups contents ->
        saw_toolbar_groups := true;
        install_toolbar_groups view ~schedule_event contents
      | Apple.Rendered_keyboard_toolbar items ->
        saw_keyboard_toolbar := true;
        install_keyboard_toolbar view ~schedule_event items
      | Apple.Rendered_tap_action { on_click } ->
        saw_tap_action := true;
        set_tap_action view (Some (fun () -> schedule_event on_click))
      | Apple.Rendered_horizontal_swipe { on_left; on_right } ->
        saw_horizontal_swipe := true;
        set_horizontal_swipe
          view
          (Some
             ( (fun () -> schedule_event on_left)
             , fun () -> schedule_event on_right ))
      | Apple.Rendered_on_appear { on_appear } ->
        saw_on_appear := true;
        set_on_appear view (Some (fun () -> schedule_event on_appear))
      | Apple.Rendered_keyboard_dismiss_controls ->
        saw_keyboard_dismiss_controls := true;
        set_native_keyboard_dismiss_controls view.native true
      | Apple.Rendered_scroll_dismisses_keyboard ->
        saw_scroll_dismisses_keyboard := true;
        set_native_scroll_dismisses_keyboard view.native true
      | Apple.Rendered_hide_list_row_separator ->
        saw_hide_list_row_separator := true;
        set_native_hide_list_row_separator view.native true);
    if not !saw_searchable then clear_searchable view;
    if !saw_sheet then install_pending_sheet () else clear_sheet view;
    if not !saw_popover then clear_popover view;
    if not !saw_confirmation_dialog then clear_confirmation_dialog view;
    if not !saw_safe_area_inset_bottom then set_safe_area_inset_bottom view None;
    if not !saw_alert then clear_alert view;
    if not !saw_toolbar && not !saw_toolbar_groups then clear_toolbar view;
    if not !saw_keyboard_toolbar then clear_keyboard_toolbar view;
    if not !saw_padding then set_native_padding view.native (-1.) (-1.) (-1.) (-1.);
    if not !saw_regular_material_panel
    then set_native_regular_material_panel view.native (-1.);
    if not !saw_secondary_system_grouped_panel
    then set_native_secondary_system_grouped_panel view.native (-1.);
    if not !saw_secondary_fill_panel
    then set_native_secondary_fill_panel view.native (-1.) 0.;
    if not !saw_liquid_glass_panel
    then set_native_liquid_glass_panel view.native (-1.) false (-1) 0.;
    if not !saw_context_menu then install_context_menu view ~schedule_event ~actions:[];
    if not !saw_frame then set_native_frame view.native (-1.) (-1.) (-1.) 0;
    if not !saw_navigation_title then set_native_navigation_title view.native None;
    if not !saw_tap_action then set_tap_action view None;
    if not !saw_horizontal_swipe then set_horizontal_swipe view None;
    if not !saw_on_appear then set_on_appear view None;
    if not !saw_keyboard_dismiss_controls
    then set_native_keyboard_dismiss_controls view.native false;
    if not !saw_scroll_dismisses_keyboard
    then set_native_scroll_dismisses_keyboard view.native false;
    if not !saw_hide_list_row_separator
    then set_native_hide_list_row_separator view.native false
  ;;
end

let render_lazy_list_row provider_id index =
  match Hashtbl.find Backend.lazy_list_providers provider_id with
  | None -> Nativeint.zero
  | Some provider -> (provider.render_row index).Backend.native
;;

let key_lazy_list_row provider_id index =
  match Hashtbl.find Backend.lazy_list_providers provider_id with
  | None -> string_of_int index
  | Some provider -> provider.key_row index
;;

let release_lazy_list_row provider_id index =
  match Hashtbl.find Backend.lazy_list_providers provider_id with
  | None -> ()
  | Some provider -> provider.release_row index
;;

let () = register_lazy_list_callbacks key_lazy_list_row render_lazy_list_row release_lazy_list_row

module Renderer = Apple.Renderer.Make (Backend)
module App = Apple.App.Make (Backend)

let controller view =
  match view.Backend.controller with
  | Some controller -> controller
  | None ->
    let controller = make_native_controller view.native in
    view.controller <- Some controller;
    controller
;;

let update_controller controller view =
  update_native_controller controller view.Backend.native
;;

let window view = make_native_window view.Backend.native
