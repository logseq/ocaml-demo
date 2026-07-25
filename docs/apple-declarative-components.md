# Apple Declarative Components

`ocaml_demo_apple` should grow as an Apple-native declarative UI layer, not as a
literal clone of SwiftUI's generic type system.

The app authoring boundary stays in OCaml graph components:

```text
OCaml graph component
  -> Ocaml_demo_apple.node tree
  -> Ocaml_demo_apple.Renderer
  -> SwiftUI backend
  -> native Apple UI
```

SwiftUI is the renderer target. App-specific Swift should not be required for
normal app screens.

## Design Rules

- Add product-level Apple primitives to `ocaml_demo_apple`, not app-local backend
  hacks.
- Keep primitive state explicit and graph-owned: selected tab, search text,
  picker value, toggle state, sheet visibility, and navigation selection should
  flow through events/effects.
- Prefer semantic platform primitives over styling knobs. A `tab_view` primitive
  is better than exposing arbitrary SwiftUI modifiers needed to assemble tabs.
- Implement each primitive in the SwiftUI backend where practical.
- Keep escape hatches for specialized controls through `custom_view`, but do not
  use escape hatches for common Apple UI.

## Current Coverage

`ocaml_demo_apple` already covers:

- Text, button, text field.
- Vertical and horizontal stacks.
- Scroll views.
- Keyed lists.
- Navigation stack.
- Images and custom views.
- Padding, frame, searchable, toolbar, and sheet modifiers.

## SwiftUI API Surface Checked

The installed SDK is `iPhoneSimulator26.0.sdk` with Apple Swift 6.2. The SwiftUI
interfaces expose native APIs for the components below:

- Navigation and shell: `TabView`, `Tab`, `TabRole.search`,
  `tabBarMinimizeBehavior`, `tabViewBottomAccessory`, `NavigationStack`, and
  `NavigationSplitView`.
- Search: `searchable`, searchable presentation binding, `searchFocused`, and
  search scopes.
- Collections: `List`, `Table`, `Grid`, `LazyVGrid`, `ScrollView`, `Form`, and
  `Section`.
- Row actions: `swipeActions`.
- Inputs: `Toggle`, `Picker`, `DatePicker`, `TextEditor`, `Slider`, `Stepper`,
  `ColorPicker`, `Menu`, and `DisclosureGroup`.
- Presentation: `sheet`, presentation detents/background/corner radius,
  `alert`, and `confirmationDialog`.
- Sharing and media: `ShareLink` and `PhotosPicker`.
- iOS 26 styling hooks: `GlassButtonStyle`, `ToolbarSpacer`,
  `backgroundExtensionEffect`, and `scrollEdgeEffectStyle`.

These APIs are enough to grow `ocaml_demo_apple` into a familiar Apple UI layer for
typical iPhone/iPad productivity apps.

## Recommended Primitive Layers

### Layer 1: App Shell

These should be implemented first because they define app structure and native
feel:

- `tab_view`
- `tab`
- `navigation_split_view`
- `toolbar`
- `searchable`
- `sheet`

Sketch:

```ocaml
val tab
  :  id:string
  -> title:string
  -> ?system_image:string
  -> ?role:[ `Search ]
  -> node
  -> tab

val tab_view
  :  selected:string
  -> on_select:(string -> unit Effect.t)
  -> tab list
  -> node

val navigation_split_view
  :  sidebar:node
  -> ?content:node
  -> detail:node
  -> node
```

### Layer 2: Forms And Inputs

These cover most settings/editing screens:

- `form`
- `section`
- `toggle`
- `picker`
- `date_picker`
- `text_editor`
- `slider`
- `stepper`

Sketch:

```ocaml
val form : node list -> node
val section : ?title:string -> node list -> node

val toggle
  :  title:string
  -> is_on:bool
  -> on_change:(bool -> unit Effect.t)
  -> node

val date_picker
  :  title:string
  -> date:Time_ns.t
  -> displayed_components:[ `Date | `Time | `Date_and_time ]
  -> on_change:(Time_ns.t -> unit Effect.t)
  -> node
```

### Layer 3: Collection Behavior

These make lists feel native:

- Row swipe actions.
- Row selection.
- Edit mode.
- Empty/content unavailable states.
- Pull to refresh.

Sketch:

```ocaml
type row_action =
  { id : string
  ; title : string
  ; system_image : string option
  ; role : [ `Normal | `Destructive ]
  ; on_click : unit Effect.t
  }

val swipe_actions
  :  ?edge:[ `Leading | `Trailing ]
  -> ?allows_full_swipe:bool
  -> row_action list
  -> node
  -> node
```

### Layer 4: Presentation

These should be modifiers because they present from existing content:

- `alert`
- `confirmation_dialog`
- `popover`
- Sheet detents and presentation styling.

### Layer 5: Media And Advanced Frameworks

These should live in optional modules/packages because they pull in extra Apple
framework semantics:

- `Ocaml_demo_apple_photos.photos_picker`
- `Ocaml_demo_apple_map.map`
- `Ocaml_demo_apple_share.share_link`
- Camera, documents, StoreKit, Charts, and similar framework-specific views.

## Backend Implications

SwiftUI backend:

- `tab_view` maps to `TabView(selection:)` with `Tab` values.
- Search tabs should use `TabRole.search` where appropriate.
- `navigation_split_view` maps to `NavigationSplitView`.
- Inputs map directly to native SwiftUI controls.
- iOS 26 styling should prefer system APIs such as glass button style and tab
  bar behavior, gated by availability in Swift.

## Feasibility

Yes, `ocaml_demo_apple` can grow to support the Apple-native component set needed
for a polished app. The practical target is not "every SwiftUI symbol"; it is a
stable, declarative OCaml API for common Apple UI patterns, backed by SwiftUI.

The next implementation step should be Layer 1 plus the minimal Layer 3 pieces
needed by Todos:

- `tab_view` and `tab`
- `swipe_actions`
- `date_picker`
- richer `searchable` presentation state for minimized/focused search behavior
