module Action : sig
  type 'a t = unit -> 'a

  val ignore : unit t
  val of_thunk : (unit -> 'a) -> 'a t
  val many : unit t list -> unit t
end

val copy_text_to_clipboard : string -> unit Action.t
val copy_image_file_to_clipboard : string -> unit Action.t
val toggle_audio_file_playback : string -> unit Action.t

type audio_recording_result =
  { transcript : string
  ; local_path : string
  ; filename : string
  ; content_type : string
  ; byte_size : int
  }

val start_audio_recording : unit Action.t
val stop_audio_recording_and_transcribe : audio_recording_result Action.t
val set_clipboard_text_handler : (string -> unit) -> unit
val set_clipboard_image_file_handler : (string -> unit) -> unit
val set_toggle_audio_file_playback_handler : (string -> unit) -> unit

val set_audio_recording_handlers
  :  start:(unit -> unit)
  -> stop_and_transcribe:(unit -> audio_recording_result)
  -> unit

type graph = Bonsai_native.graph

val state
  :  ?equal:('a -> 'a -> bool)
  -> graph
  -> key:string
  -> 'a
  -> 'a * ('a -> unit Action.t)

val scope : graph -> key:string -> (graph -> 'a) -> 'a

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

type text_field_style =
  | Rounded_border
  | Pill
  | Plain_text

type text_field_clear_button =
  | No_clear_button
  | While_editing

type axis =
  | Vertical
  | Horizontal

type horizontal_stack_alignment =
  | Stack_center
  | Stack_top

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
type tab
type sidebar_action

type sidebar_action_chrome =
  | Default_chrome
  | Prominent_capsule
  | Liquid_icon

type rendered_tab =
  { id : string
  ; title : string
  ; system_image : string option
  ; role : tab_role option
  }

type node

val text : ?style:text_style -> ?weight:text_weight -> ?color:text_color -> string -> node

val button
  :  ?is_enabled:bool
  -> ?style:button_style
  -> ?system_image:string
  -> ?subtitle:string
  -> ?is_title_visible:bool
  -> string
  -> on_click:unit Action.t
  -> node

val button_label : ?is_enabled:bool -> on_click:unit Action.t -> node -> node

val text_field
  :  ?placeholder:string
  -> ?style:text_field_style
  -> ?axis:axis
  -> ?clear_button:text_field_clear_button
  -> ?is_secure:bool
  -> ?is_focused:bool
  -> ?on_submit:unit Action.t
  -> ?on_delete_backward_at_start:unit Action.t
  -> text:string
  -> on_change:(string -> unit Action.t)
  -> unit
  -> node

val toggle : string -> is_on:bool -> on_change:(bool -> unit Action.t) -> node

val text_editor
  :  ?placeholder:string
  -> text:string
  -> on_change:(string -> unit Action.t)
  -> unit
  -> node

val progress_view : value:float -> node
val congrats_effect : unit -> node
val vstack : ?spacing:float -> node list -> node
val hstack
  :  ?spacing:float
  -> ?alignment:horizontal_stack_alignment
  -> node list
  -> node
val zstack : node list -> node
val grid : ?columns:int -> ?spacing:float -> node list -> node
val spacer : unit -> node
val divider : unit -> node
val form : node list -> node
val scroll_view : node -> node

val list
  :  ?on_refresh:unit Action.t
  -> ?on_delete:(int -> unit Action.t)
  -> ?on_move:(from_index:int -> to_index:int -> unit Action.t)
  -> ?on_focused_row_disappear:unit Action.t
  -> ?edit_mode:bool
  -> ?focused_row_key:string
  -> ?focused_row_index:int
  -> 'a list
  -> key:('a -> string)
  -> row:('a -> node)
  -> node

val lazy_list
  :  ?on_refresh:unit Action.t
  -> ?on_delete:(int -> unit Action.t)
  -> ?on_move:(from_index:int -> to_index:int -> unit Action.t)
  -> ?on_focused_row_disappear:unit Action.t
  -> ?on_rows_published:unit Action.t
  -> ?edit_mode:bool
  -> ?focused_row_key:string
  -> ?focused_row_index:int
  -> ?state_key:(int -> string)
  -> length:int
  -> key:(int -> string)
  -> row:(int -> node)
  -> unit
  -> node

val movable_rows
  :  ?on_move:(from_index:int -> to_index:int -> unit Action.t)
  -> ?edit_mode:bool
  -> 'a list
  -> key:('a -> string)
  -> row:('a -> node)
  -> node

val section : key:string -> ?title:string -> node list -> node
val section_key : node -> string
val picker_option : id:string -> title:string -> picker_option

val row_action
  :  ?system_image:string
  -> ?style:row_action_style
  -> string
  -> on_click:unit Action.t
  -> row_action

val picker
  :  ?style:picker_style
  -> title:string
  -> selected:string
  -> on_select:(string -> unit Action.t)
  -> picker_option list
  -> node

val slider
  :  title:string
  -> value:float
  -> min:float
  -> max:float
  -> on_change:(float -> unit Action.t)
  -> node

val stepper
  :  title:string
  -> value:int
  -> min:int
  -> max:int
  -> step:int
  -> on_change:(int -> unit Action.t)
  -> node

val date_picker
  :  title:string
  -> selected:string
  -> on_select:(string -> unit Action.t)
  -> node

val color_picker
  :  title:string
  -> selected:string
  -> on_select:(string -> unit Action.t)
  -> node

val menu_action
  :  id:string
  -> title:string
  -> ?system_image:string
  -> ?style:row_action_style
  -> ?is_enabled:bool
  -> on_click:unit Action.t
  -> unit
  -> menu_action

val menu : title:string -> ?system_image:string -> menu_action list -> node

val disclosure_group
  :  title:string
  -> is_expanded:bool
  -> on_change:(bool -> unit Action.t)
  -> node list
  -> node

val navigation_stack : node list -> node

val navigation_path_stack
  :  path:string list
  -> on_path_change:(string list -> unit Action.t)
  -> root:node
  -> destinations:(string * node) list
  -> node

val navigation_link
  :  ?on_activate:unit Action.t
  -> ?on_deactivate:unit Action.t
  -> destination:node
  -> node
  -> node

val navigation_value_link
  :  ?on_activate:unit Action.t
  -> ?on_deactivate:unit Action.t
  -> value:string
  -> node
  -> node

val navigation_split : sidebar:node -> content:node -> detail:node -> node
val adaptive_layout : compact:node -> regular:node -> node

val tab
  :  id:string
  -> title:string
  -> ?system_image:string
  -> ?role:tab_role
  -> node
  -> tab

val tab_view : selected:string -> on_select:(string -> unit Action.t) -> tab list -> node

val sidebar_action
  :  id:string
  -> title:string
  -> ?subtitle:string
  -> ?system_image:string
  -> ?avatar_image:string
  -> ?avatar_initial:string
  -> ?selects_tab:string
  -> ?chrome:sidebar_action_chrome
  -> ?closes_sidebar:bool
  -> on_click:unit Action.t
  -> ?menu_actions:row_action list
  -> unit
  -> sidebar_action

val sidebar_split
  :  ?title:string
  -> ?compact_top_bar_visible:bool
  -> ?header_action:sidebar_action
  -> ?actions:sidebar_action list
  -> ?history_title:string
  -> ?history_actions:sidebar_action list
  -> ?bottom_search_placeholder:string
  -> ?bottom_search_text:string
  -> ?bottom_search_on_change:(string -> unit Action.t)
  -> ?bottom_action:sidebar_action
  -> selected:string
  -> on_select:(string -> unit Action.t)
  -> tab list
  -> node

val image : ?color:text_color -> string -> node
val image_file : ?max_height:float -> ?corner_radius:float -> string -> node

val photo_picker
  :  ?is_enabled:bool
  -> ?system_image:string
  -> ?is_title_visible:bool
  -> title:string
  -> ?selected:string
  -> on_select:(string -> unit Action.t)
  -> unit
  -> node

val photo_picker_payload
  :  ?is_enabled:bool
  -> ?system_image:string
  -> ?is_title_visible:bool
  -> title:string
  -> ?selected:string
  -> on_select:(image_payload -> unit Action.t)
  -> unit
  -> node

val file_exporter
  :  ?is_enabled:bool
  -> title:string
  -> filename:string
  -> content_type:string
  -> content:string
  -> unit
  -> node

val share_link : ?is_enabled:bool -> title:string -> url:string -> unit -> node

val file_importer
  :  title:string
  -> allowed_content_types:string list
  -> on_select:(string -> unit Action.t)
  -> unit
  -> node

val camera_capture
  :  title:string
  -> ?captured:string
  -> on_capture:(string -> unit Action.t)
  -> unit
  -> node

val camera_capture_payload
  :  title:string
  -> ?captured:string
  -> on_capture:(image_payload -> unit Action.t)
  -> unit
  -> node

val list_row : list_row -> node
val custom_view
  :  ?key:string
  -> ?on_change:(string -> unit Action.t)
  -> kind:string
  -> unit
  -> node
val padding : ?insets:edge_insets -> node -> node
val regular_material_panel : ?corner_radius:float -> node -> node
val secondary_system_grouped_panel : ?corner_radius:float -> node -> node
val secondary_fill_panel : ?corner_radius:float -> ?opacity:float -> node -> node

val liquid_glass_panel
  :  ?corner_radius:float
  -> ?is_transparent:bool
  -> ?tint_color:text_color
  -> ?tint_opacity:float
  -> node
  -> node

val context_menu : row_action list -> node -> node
val frame
  :  ?width:float
  -> ?height:float
  -> ?max_width:float
  -> ?alignment:frame_alignment
  -> node
  -> node
val navigation_title : string -> node -> node

val searchable
  :  ?is_presented:bool
  -> ?on_presented_change:(bool -> unit Action.t)
  -> ?prompt:string
  -> text:string
  -> on_change:(string -> unit Action.t)
  -> node
  -> node

val toolbar_item
  :  ?system_image:string
  -> ?is_title_visible:bool
  -> ?is_enabled:bool
  -> ?menu_actions:toolbar_menu_action list
  -> ?share_url:string
  -> id:string
  -> title:string
  -> on_click:unit Action.t
  -> unit
  -> toolbar_item

val toolbar : toolbar_item list -> node -> node
val toolbar_group
  :  ?placement:toolbar_placement
  -> id:string
  -> toolbar_item list
  -> toolbar_content

val toolbar_spacer
  :  ?placement:toolbar_placement
  -> ?fixed:bool
  -> id:string
  -> unit
  -> toolbar_content

val toolbar_groups : toolbar_content list -> node -> node
val keyboard_toolbar : toolbar_item list -> node -> node
val tap_action : on_click:unit Action.t -> node -> node
val horizontal_swipe
  :  on_left:unit Action.t
  -> on_right:unit Action.t
  -> node
  -> node
val on_appear : on_appear:unit Action.t -> node -> node
val keyboard_dismiss_controls : node -> node
val scroll_dismisses_keyboard : node -> node
val hide_list_row_separator : node -> node
val safe_area_inset_bottom : node -> node -> node

val alert_action
  :  ?role:alert_action_role
  -> ?is_enabled:bool
  -> id:string
  -> title:string
  -> on_click:unit Action.t
  -> unit
  -> alert_action

val alert
  :  is_presented:bool
  -> title:string
  -> ?message:string
  -> ?text:string
  -> ?placeholder:string
  -> ?on_text_change:(string -> unit Action.t)
  -> ?actions:alert_action list
  -> ?on_dismiss:unit Action.t
  -> unit
  -> node
  -> node

val sheet
  :  is_presented:bool
  -> content:node
  -> ?detents:presentation_detent list
  -> ?on_dismiss:unit Action.t
  -> node
  -> node

val popover
  :  is_presented:bool
  -> content:node
  -> ?on_dismiss:unit Action.t
  -> node
  -> node

val confirmation_dialog
  :  is_presented:bool
  -> title:string
  -> ?message:string
  -> ?actions:alert_action list
  -> ?on_dismiss:unit Action.t
  -> unit
  -> node
  -> node

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

type modifier =
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

type rendered_picker_option =
  { id : string
  ; title : string
  }

module Renderer : sig
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

  module Make (Backend : Backend) : sig
    type t

    val mount : schedule_event:(unit Action.t -> unit) -> node -> t
    val update : t -> node -> unit
    val view : t -> Backend.view
  end
end

module App : sig
  module Make (Backend : Renderer.Backend) : sig
    type t

    val create : (graph -> node) -> t
    val flush_and_render : t -> unit
    val view : t -> Backend.view option
  end
end

module For_testing : sig
  module Backend : sig
    include Renderer.Backend

    module Stats : sig
      type t =
        { created : int
        ; destroyed : int
        ; mutations : int
        }
    end

    val reset : unit -> unit
    val stats : unit -> Stats.t
    val diff_stats : Stats.t -> Stats.t -> Stats.t
    val clipboard_text : unit -> string option
    val clipboard_image_file : unit -> string option
    val playing_audio_file : unit -> string option
    val is_audio_recording : unit -> bool
    val show : view -> string
    val show_at_path : view -> path:int list -> string
    val show_safe_area_inset_bottom_exn : view -> path:int list -> string
    val click_exn : view -> path:int list -> unit
    val activate_navigation_link_exn : view -> path:int list -> unit
    val deactivate_navigation_link_exn : view -> path:int list -> unit

    val click_safe_area_inset_bottom_exn
      :  view
      -> path:int list
      -> inset_path:int list
      -> unit

    val change_alert_text_exn : view -> text:string -> unit
    val click_alert_action_exn : view -> id:string -> unit
    val click_confirmation_dialog_action_exn : view -> id:string -> unit
    val dismiss_popover_exn : view -> unit

    val change_nested_sheet_alert_text_exn
      :  view
      -> path:int list
      -> host_path:int list
      -> text:string
      -> unit

    val click_nested_sheet_alert_action_exn
      :  view
      -> path:int list
      -> host_path:int list
      -> id:string
      -> unit

    val change_text_exn : view -> path:int list -> text:string -> unit
    val clear_text_exn : view -> path:int list -> unit

    val change_safe_area_inset_bottom_text_exn
      :  view
      -> path:int list
      -> inset_path:int list
      -> text:string
      -> unit

    val change_toggle_exn : view -> path:int list -> is_on:bool -> unit
    val change_slider_exn : view -> path:int list -> value:float -> unit
    val change_stepper_exn : view -> path:int list -> value:int -> unit
    val select_date_exn : view -> path:int list -> selected:string -> unit
    val select_color_exn : view -> path:int list -> selected:string -> unit
    val click_menu_action_exn : view -> path:int list -> id:string -> unit

    val click_sheet_menu_action_exn
      :  view
      -> path:int list
      -> sheet_path:int list
      -> id:string
      -> unit

    val change_disclosure_group_exn : view -> path:int list -> is_expanded:bool -> unit
    val change_navigation_path_exn : view -> path:string list -> unit
    val refresh_list_exn : view -> path:int list -> unit
    val delete_list_row_exn : view -> path:int list -> index:int -> unit

    val move_list_row_exn
      :  view
      -> path:int list
      -> from_index:int
      -> to_index:int
      -> unit

    val move_rows_exn : view -> path:int list -> from_index:int -> to_index:int -> unit
    val focused_list_row_disappear_exn : view -> path:int list -> unit
    val submit_text_exn : view -> path:int list -> unit
    val delete_backward_at_start_text_exn : view -> path:int list -> unit

    val submit_safe_area_inset_bottom_text_exn
      :  view
      -> path:int list
      -> inset_path:int list
      -> unit

    val select_safe_area_inset_bottom_photo_exn
      :  view
      -> path:int list
      -> inset_path:int list
      -> image_id:string
      -> unit

    val select_photo_exn : view -> path:int list -> image_id:string -> unit
    val capture_camera_exn : view -> path:int list -> image_id:string -> unit
    val select_photo_payload_exn : view -> path:int list -> payload:image_payload -> unit

    val capture_camera_payload_exn
      :  view
      -> path:int list
      -> payload:image_payload
      -> unit

    val import_file_exn : view -> path:int list -> content:string -> unit
    val click_sheet_exn : view -> path:int list -> sheet_path:int list -> unit

    val select_sheet_picker_exn
      :  view
      -> path:int list
      -> sheet_path:int list
      -> id:string
      -> unit

    val import_sheet_file_exn
      :  view
      -> path:int list
      -> sheet_path:int list
      -> content:string
      -> unit

    val change_sheet_text_exn
      :  view
      -> path:int list
      -> sheet_path:int list
      -> text:string
      -> unit

    val change_sheet_toggle_exn
      :  view
      -> path:int list
      -> sheet_path:int list
      -> is_on:bool
      -> unit

    val move_sheet_rows_exn
      :  view
      -> path:int list
      -> sheet_path:int list
      -> from_index:int
      -> to_index:int
      -> unit

    val click_sheet_toolbar_item_exn : view -> path:int list -> id:string -> unit

    val click_nested_sheet_exn
      :  view
      -> path:int list
      -> host_path:int list
      -> sheet_path:int list
      -> unit

    val click_nested_sheet_toolbar_item_exn
      :  view
      -> path:int list
      -> host_path:int list
      -> id:string
      -> unit

    val change_nested_sheet_text_exn
      :  view
      -> path:int list
      -> host_path:int list
      -> sheet_path:int list
      -> text:string
      -> unit

    val select_sheet_photo_exn
      :  view
      -> path:int list
      -> sheet_path:int list
      -> image_id:string
      -> unit

    val capture_sheet_camera_exn
      :  view
      -> path:int list
      -> sheet_path:int list
      -> image_id:string
      -> unit

    val select_sheet_photo_payload_exn
      :  view
      -> path:int list
      -> sheet_path:int list
      -> payload:image_payload
      -> unit

    val capture_sheet_camera_payload_exn
      :  view
      -> path:int list
      -> sheet_path:int list
      -> payload:image_payload
      -> unit

    val change_search_exn : view -> path:int list -> text:string -> unit
    val click_toolbar_item_exn : view -> path:int list -> id:string -> unit
    val click_keyboard_toolbar_item_exn : view -> path:int list -> id:string -> unit

    val click_toolbar_menu_action_exn
      :  view
      -> path:int list
      -> id:string
      -> title:string
      -> unit

    val dismiss_sheet_exn : view -> path:int list -> unit
    val select_tab_exn : view -> id:string -> unit
    val change_sidebar_bottom_search_exn : view -> text:string -> unit
    val select_sidebar_route_exn : view -> id:string -> unit
    val click_sidebar_header_action_exn : view -> id:string -> unit
    val click_sidebar_action_exn : view -> id:string -> unit
    val click_sidebar_action_menu_action_exn : view -> id:string -> title:string -> unit
    val click_sidebar_history_action_exn : view -> id:string -> unit

    val click_sidebar_history_action_menu_action_exn
      :  view
      -> id:string
      -> title:string
      -> unit

    val click_sidebar_bottom_action_exn : view -> id:string -> unit
    val select_picker_exn : view -> path:int list -> id:string -> unit
    val click_row_leading_exn : view -> path:int list -> unit
    val click_row_action_exn : view -> path:int list -> title:string -> unit
    val click_context_menu_action_exn : view -> path:int list -> title:string -> unit
    val click_row_menu_action_exn : view -> path:int list -> title:string -> unit
    val appear_exn : view -> path:int list -> unit

    val click_sheet_row_menu_action_exn
      :  view
      -> path:int list
      -> sheet_path:int list
      -> title:string
      -> unit

    val find_text_exn : view -> path:int list -> string
  end
end
