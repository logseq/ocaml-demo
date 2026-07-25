# Open Questions

## How should OCaml support SwiftUI-style builder customization?

SwiftUI customizes views by chaining modifiers:

```swift
Text("Queue")
  .font(.headline)
  .padding(.horizontal, 16)
  .padding(.vertical, 8)
  .background(.regularMaterial)
```

OCaml does not have Swift's trailing-closure and fluent builder syntax, but the
authoring API still needs the same ergonomics. A user should be able to adjust
common presentation details, such as padding, without dropping into backend
Swift calls.

### Example Problem

How should app code express "this row has 16pt horizontal padding and 8pt
vertical padding"?

The API should be:

- Declarative and readable in OCaml.
- Backend-neutral where possible.
- Compatible with graph state values and effects.
- Extensible as SwiftUI-only or iOS-version-specific capabilities appear.
- Hard to misuse for common cases.

### Answer A: Function Modifiers

Expose modifiers as ordinary functions that transform `node -> node`.

```ocaml
Apple.text "Queue"
|> Apple.font Apple.Headline
|> Apple.padding ~horizontal:16. ~vertical:8.
|> Apple.background Apple.Regular_material
```

This is the closest OCaml equivalent to SwiftUI chaining. It is simple, familiar
to OCaml users, and already matches the current `Apple.padding node` direction.

Pros:

- Very readable for small and medium modifier stacks.
- Easy to implement as a list of rendered modifiers on each node.
- Modifier order can be preserved when order matters.
- Works well with helpers:

```ocaml
let panel node =
  node
  |> Apple.padding ~all:16.
  |> Apple.background Apple.Secondary_grouped_background
  |> Apple.clip_shape (Apple.Rounded_rect { radius = 24.; style = `Continuous })
```

Cons:

- Long modifier chains can become noisy.
- Type checking usually cannot prevent backend-specific modifiers from being
  attached to unsupported nodes unless we add extra phantom types.

Recommendation:

Use this as the default API shape for common SwiftUI-style customizations.

### Answer B: Optional Constructor Arguments

Put common customization directly on component constructors.

```ocaml
Apple.text
  ~style:Apple.Headline
  ~padding:{ top = 8.; leading = 16.; bottom = 8.; trailing = 16. }
  "Queue"
```

Pros:

- Compact for highly common options.
- Easy to discover from a constructor signature.
- Can make important semantic settings explicit.

Cons:

- Constructors grow too large as the component surface expands.
- It does not compose well for reusable styles.
- It is a poor fit for modifiers that apply to many different components.

Recommendation:

Use optional arguments only for component identity and semantic content, not for
general styling. For example, `Apple.text ~style ~weight ~color "Queue"` is fine;
padding should stay a modifier.

### Answer C: Attribute Records

Represent customization as a typed record passed to constructors or modifiers.

```ocaml
let row_style =
  { Apple.Style.empty with
    padding = Some (Apple.EdgeInsets.symmetric ~horizontal:16. ~vertical:8.)
  ; background = Some Apple.Regular_material
  }
in
Apple.text "Queue" |> Apple.style row_style
```

Pros:

- Easy to serialize, diff, inspect, and test.
- Good for design-system tokens and reusable style presets.
- Lets app code construct styles separately from view structure.

Cons:

- Less natural than modifier chaining for one-off customization.
- Record growth can recreate the same "giant options bag" problem.
- Modifier order is harder to represent.

Recommendation:

Use records for reusable style presets and design-system tokens, not as the only
customization mechanism.

### Answer D: Builder Modules

Provide small builder modules for families of modifiers.

```ocaml
Apple.text "Queue"
|> Apple.Padding.symmetric ~horizontal:16. ~vertical:8.
|> Apple.Material.background Apple.Regular
```

Pros:

- Keeps the top-level module from becoming too crowded.
- Creates a clear home for modifier variants.
- Maps well to SwiftUI families such as `padding`, `background`, `toolbar`,
  `presentation`, and `accessibility`.

Cons:

- Slightly more verbose.
- Requires careful naming so common cases do not feel buried.

Recommendation:

Use submodules once a modifier family has several variants. Keep the most common
forms at the top level:

```ocaml
Apple.padding ~all:16.
Apple.Padding.edges [ `Leading; `Trailing ] 16.
```

### Answer E: Backend-Specific Escape Hatches

Allow a modifier to carry backend-specific data.

```ocaml
node
|> Apple.Swiftui.modifier "glassEffect" [ Apple.Swiftui.Bool true ]
```

Pros:

- Unblocks experiments before a stable OCaml API exists.
- Useful for app-specific or newly released Apple APIs.

Cons:

- Easy to make apps backend-specific.
- Hard to test and refactor.
- Pushes stringly typed API details into application code.

Recommendation:

Keep this as an explicit escape hatch, not the normal path. Promote repeated
escape-hatch usage into typed `ocaml_demo_apple` primitives.

## Proposed Direction

Use a layered API:

1. Constructors describe semantic UI:

```ocaml
Apple.text ~style:Apple.Headline "Queue"
Apple.list_row { title; trailing_text; leading_button; swipe_actions }
```

2. Common modifiers are composable `node -> node` functions:

```ocaml
Apple.text "Queue"
|> Apple.padding ~horizontal:16. ~vertical:8.
|> Apple.frame ~max_width:`Infinity
```

3. Reusable styling is built from ordinary OCaml functions:

```ocaml
let row_content node =
  node
  |> Apple.padding ~horizontal:16. ~vertical:8.
  |> Apple.foreground_style Apple.Primary
```

4. Larger modifier families get submodules:

```ocaml
Apple.Presentation.detents [ Apple.Presentation.medium; Apple.Presentation.large ]
Apple.Accessibility.label "Mark complete"
```

5. Backend-specific or OS-specific features are typed and availability-aware
   before they become public API.

This gives OCaml code a SwiftUI-like customization model without copying
SwiftUI's generic type system. Padding should be modeled as a normal modifier,
with ergonomic helpers for common cases:

```ocaml
val padding
  :  ?all:float
  -> ?horizontal:float
  -> ?vertical:float
  -> ?top:float
  -> ?leading:float
  -> ?bottom:float
  -> ?trailing:float
  -> node
  -> node
```

The renderer can normalize this into `EdgeInsets` and attach it to the existing
modifier list.
