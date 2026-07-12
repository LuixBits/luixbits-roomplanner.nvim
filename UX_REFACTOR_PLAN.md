# `roomplan.nvim` UX refactor plan

**Status:** implemented release candidate; remaining gaps recorded below
**Date:** 2026-07-12
**Scope:** interaction and presentation layer; canonical model, geometry, actions,
history, validation, storage, and the semantic renderer remain authoritative
**Primary goal:** make a new user understand how to create and edit a visible
floor plan without reading help or answering a long sequence of disconnected
numbered prompts

## Implementation outcome

The refactor is now the default `ui.experience = "workspace"` path:

- an empty plan has a visible Add First Room state, valid initial cursor,
  first-object fit, object counts, and an offscreen-plan warning;
- wide, medium, and compact layouts provide synchronized Objects/Issues,
  Canvas, Properties, and a persistent two-line action/status bar;
- Room, Furniture, Door, Alignment, Plan, Custom Template, and geometry Edit
  use structured forms with conditional fields, normalized measurements,
  inline validation, revision guards, textual previews, and atomic
  Apply/Cancel behavior;
- custom templates appear as selectable top-level Objects rows, while Add Room
  and Align expose an explicit `Allow invalid draft` policy;
- `:RoomPlan` and non-empty Add use a dependency-free `j/k`/Enter action
  palette rather than a numbered `vim.ui.select` chain;
- `ui.experience = "classic"` retains the original canvas and sequential
  provider workflows as a temporary fallback;
- the model, history, renderer, commands, storage, and safety contracts were
  preserved.

This file remains the design and acceptance record. The authoritative user
instructions are `README.md` and `:help roomplan`. Not yet implemented from the
original proposal: canvas ghost geometry/PICK round-trips. Form previews are
currently textual. This gap does not restore the header-only or blind
sequential geometry workflow that motivated the refactor.

## 1. Decision

A UX refactor is needed. The reported behavior is not simply user error.

The current implementation has a capable model and renderer, but its first-run
experience hides that capability:

1. A newly initialized plan has no scene primitives. The rasterizer correctly
   returns blank cells, and the canvas adds only two status lines. The user sees
   a name, path, and `[SAVED]`, followed by whitespace.
2. The canvas opens with the Neovim cursor on header line 1. Header rows are not
   logical canvas rows, so `h/j/k/l` and `<Enter>` silently do nothing until the
   cursor reaches the drawing area through some unrelated motion or selection.
3. The empty canvas establishes a valid viewport. Adding the first room reuses
   that viewport instead of fitting the new geometry. A normal 4000 × 3000 mm
   room can therefore appear only as a clipped L shape until `zf` is pressed.
4. Add Room asks for name, width, depth, and placement in separate dialogs. Add
   Furniture and Add Door require roughly eight to ten successive dialogs.
   There is no overview, progress, Back action, persistent draft, preview, or
   final review.
5. Inspector, object list, validation list, help, canvas, and action menus open
   as separate experiences. They do not behave like one planning workspace.
6. The only always-visible guidance is technical state. The useful commands
   (`a`, `e`, `m`, `i`, `o`, `v`, `zf`, `?`) are invisible until help is opened.

The populated acceptance fixture renders rooms, a shared door, and furniture,
so the geometry and rasterizer are not the primary problem. They should be
retained and placed inside a substantially better UI shell.

## 2. Refactor objectives

The refactor must provide:

- an explicit empty state with one obvious first action;
- a usable canvas cursor immediately after opening;
- automatic visibility of newly created geometry;
- a persistent LazyGit-style workspace rather than disconnected temporary
  windows;
- a synchronized object tree, canvas selection, properties, and diagnostics;
- structured forms that show related values together;
- inline measurement normalization and validation;
- an atomic Apply/Cancel workflow with optional geometry preview;
- visible context-sensitive key hints;
- a responsive design that remains useful in narrow terminals;
- keyboard-only and no-color usability;
- no mandatory third-party UI dependency;
- preservation of existing Ex commands, Lua API, model actions, undo semantics,
  and source safety behavior.

The refactor must not turn rendered text into source data or move transient UI
state into the saved JSON schema.

## 3. Target workspace

### 3.1 Wide layout

At 120 columns or wider, open one RoomPlan tab with three synchronized panes and
a shared action bar:

```text
┌ Objects / Issues (30–36c) ┬──────────── Canvas ────────────┬ Properties (32–40c) ┐
│ My flat                   │                                │ Living room          │
│ 2 rooms · 1 door · 3 items│         Bedroom               │ Position              │
│                           │    ┌──────────────┐             │   X        5000 mm    │
│ ▾ Living room  5m × 4m    │    │              │             │   Y           0 mm    │
│   ├ door east → Bedroom   │ ┌──┘              │             │ Size                  │
│   └Sofa  2.1m × 0.9m      │ │ Living room     │             │   Width    5000 mm    │
│ ▾ Bedroom  3m × 3m        │ │       Sofa      │             │   Depth    4000 mm    │
│                           │ └──────────────────┘             │ Diagnostics: none     │
│                           │                                │ [e] Edit [m] Move     │
├───────────────────────────┴────────────────────────────────┴──────────────────────┤
│ [a] Add  [e] Edit  [m] Move  [A] Align  [v] Validate  [s] Save  [?] Help          │
│ NAV · SAVED · snap on · cursor (2400, 1700) mm · zoom 1.00                        │
└───────────────────────────────────────────────────────────────────────────────────┘
```

The canvas remains the largest pane. Opening sidebars must never leave it too
small to display meaningful geometry.

### 3.2 Medium layout

From 90 to 119 columns:

- keep Objects/Issues on the left and Canvas on the right;
- show Properties as a tab below Objects or as a toggleable drawer;
- keep the two-line action/status bar;
- preserve at least 55 columns for the canvas where possible.

### 3.3 Narrow layout

Below 90 columns or below 22 usable rows:

- make the canvas the only persistent pane;
- show Objects, Properties, Issues, Help, and Forms as centered or edge-anchored
  floating drawers;
- show a concise action/status footer;
- never silently create a layout whose canvas is too small;
- explain the compact mode textually rather than relying only on changed
  borders.

Breakpoints must be configurable and tested at representative sizes rather
than inferred from one developer terminal.

## 4. Immediate canvas repairs

These are phase-zero correctness fixes and should land before the workspace is
complete.

### 4.1 Empty-plan state

When the plan has zero rooms, the drawable area must contain a centered card:

```text
Empty floor plan

No rooms yet.
[a] Add first room    [?] Help    [q] Hide

Measurements accept mm, cm, and m.
```

Requirements:

- The card is raster chrome, not model geometry and not persisted.
- The same Add First Room action appears in the sidebar.
- `a` opens Add Room directly when the model is empty; it does not first show a
  redundant Room/Door/Furniture menu.
- Door and Furniture actions remain visible but disabled with the reason “Add
  a room first.”
- Focus, selection, and severity remain understandable without color.

### 4.2 Initial cursor placement

After the first canvas redraw:

- if a selected object has a visible anchor, place the cursor on that anchor;
- otherwise place it at the center of the drawable area;
- never leave it on a header row;
- `logical_cursor()` must be valid immediately;
- `h/j/k/l` and `<Enter>` must work on the first keypress.

If a redraw changes header height or responsive layout, preserve the cursor's
world coordinate rather than its raw buffer row.

### 4.3 First-object fitting and visibility

When a successful action changes the scene from empty to non-empty:

- select the new spatial object;
- fit the complete spatial scene once;
- place the cursor on or near the new object;
- focus the canvas;
- render before returning control to the user.

For later additions and edits, do not refit the entire plan automatically.
Instead, pan just enough to keep the selected/touched object visible. Explicit
Fit remains available as `f`, with `zf` retained as a compatibility alias.

### 4.4 Offscreen and render safeguards

If the model has spatial objects but the current raster contains no visible
geometry, show:

```text
Plan is outside the viewport — press f to fit
```

If an explicit fit still produces no drawable geometry for a non-empty valid
scene, show a render-error banner and a diagnostic action instead of blank
space. Add room/door/furniture counts to the header or sidebar so a viewport
problem cannot masquerade as an empty model.

### 4.5 Persistent action hints

Add a bottom action line whose entries change by focus, selection, and mode.
Examples:

- Empty: `[a] Add first room  [?] Help  [q] Hide`
- Canvas/no selection: `[a] Add  [Enter] Select  [f] Fit  [v] Validate`
- Room selected: `[e] Edit  [m] Move  [A] Align  [d] Delete`
- Furniture selected: `[e] Edit  [m] Move  [r] Rotate  [y] Duplicate`
- Form: `[Enter] Edit  [Ctrl-s] Apply  [Esc] Cancel`

Unavailable actions should either be omitted or shown disabled with an
inspectable reason. They must not fail only through transient notifications.

## 5. Pane behavior

### 5.1 Objects pane

Render a hierarchical, searchable tree:

```text
My flat
2 rooms · 1 door · 3 items

▾ Living room  5m × 4m
  ├ D east → Bedroom  900mm
  ├ Sofa  2.1m × 0.9m
  └ Table 1.6m × 0.9m
▾ Bedroom  3m × 3m
```

Behavior:

- `j/k` navigates visible rows.
- Selection updates the shared `session.selection` and canvas highlight.
- `<Enter>` selects, centers, and focuses the canvas.
- `/` filters by name, ID, kind, or room.
- Rooms may expand/collapse; child furniture and doors are grouped under their
  owning room.
- Every row shows textual error/warning counts where present.
- A plan-level row exposes metadata and settings.

### 5.2 Issues tab

Objects and Issues share the left pane as tabs.

- Rows begin with `ERROR`, `WARN`, or `INFO`, not just icons/highlights.
- `<Enter>` selects the object, centers it, and updates Properties.
- The tab title shows counts.
- An empty list says “No validation problems.”
- Validation refreshes in place; it must not open an unrelated bottom split.

### 5.3 Properties pane

When nothing is selected, show plan summary and useful actions:

- room/door/furniture counts;
- units and grid step;
- source adapter/path;
- save/conflict status;
- Add Room, Fit, Validate, and Plan Settings actions.

When an object is selected, group properties for humans:

- Identity: name and kind;
- Position: origin or center in millimetres and formatted metric values;
- Size: width/depth/height and room area where applicable;
- Placement: room, wall, side, offset, rotation;
- Connection: destination, hinge, swing direction, angle;
- Diagnostics: persistent messages with severity;
- Actions: Edit, Move, Align, Rotate, Duplicate, Delete.

Stable IDs and extension fields belong under an Advanced group. The pane is not
a raw JSON dump.

### 5.4 Shared selection contract

There is exactly one semantic selection per session. Object pane, Issues,
Canvas, Properties, and Forms observe it.

- Selecting in any pane updates every other pane.
- Focus and selection are separate. Moving focus must not change geometry.
- Deleting a selection chooses the next sensible sibling or clears selection.
- Newly created objects are selected immediately.
- Hidden/collapsed children remain selected but their parent indicates it.

## 6. Focus and keyboard model

Recommended defaults:

- `<Tab>` / `<S-Tab>`: next/previous workspace pane;
- `1`: Objects/Issues;
- `2`: Canvas;
- `3`: Properties;
- `<C-w>h/j/k/l`: retain native-style window navigation;
- `j/k`: list navigation when a list pane has focus;
- `h/j/k/l`: canvas cursor or active mode behavior when canvas has focus;
- `<Enter>`: select/activate the focused row or canvas hit;
- `a/e/d/y/m/r/v/s/?`: context actions throughout the workspace;
- `A`: Align selected room;
- `f`: Fit; retain `zf` as an alias;
- `Esc`: close active popup, then leave interaction mode, then focus canvas,
  then deselect on subsequent presses;
- `q`: close popup/drawer first, otherwise hide the workspace while retaining
  the session.

The exact pane-cycle mapping is configurable. Existing canvas mappings remain
aliases for at least one compatibility cycle. All mappings stay buffer-local.

## 7. Structured form system

### 7.1 Interaction model

Replace sequential interrogation with one visible draft:

```text
┌ Add room ─────────────────────────────────────────────┐
│ Name             Living room                         │
│ Width            5m       → 5000 mm                  │
│ Depth            4m       → 4000 mm                  │
│ Placement        East of selected room               │
│ Reference        Hall                                 │
│ Gap              0 mm                                │
│ Result origin    (3200, 0) mm                        │
│ Area             20.0 m²                             │
│                                                      │
│ No validation problems                               │
│                                                      │
│ [Create room]                             [Cancel]    │
├──────────────────────────────────────────────────────┤
│ j/k or Tab fields · Enter edit · Ctrl-s apply · Esc │
└──────────────────────────────────────────────────────┘
```

Requirements:

- All related fields and defaults remain visible together.
- `j/k` and Tab navigate fields.
- Enter edits the active scalar or opens a local choice list.
- Space toggles boolean fields.
- Ctrl-s or the Apply row submits.
- Esc cancels without mutating the model.
- Errors appear beside the field and persist until corrected.
- Apply focuses the first invalid field instead of closing the form.
- Entered values survive validation errors and switching fields.
- Measurements show both entered text and normalized millimetres.
- Forms expose Apply, Cancel, and when meaningful Back/Reset-to-default.

For the first implementation, use a read-only form buffer plus a small anchored
input/dropdown for the active field. This provides structure without fragile
arbitrary editable-buffer regions. In-place field editing may be later polish.

### 7.2 Declarative field descriptors

Create reusable field types:

- `text`;
- `measurement`;
- `integer`;
- `enum`;
- `object_ref`;
- `toggle`;
- `coordinates`;
- `readonly` derived value;
- `action` row.

Each descriptor may define:

- key, label, help, and default;
- parser and formatter;
- required/enabled/visible predicates;
- validation returning persistent messages;
- choices derived from the current model/draft;
- dependency keys that trigger recalculation;
- preview contribution;
- serialization into an existing model action.

Form state is a detached draft. Only Apply calls `controller.dispatch`, and it
must produce exactly one semantic history entry.

### 7.3 Add Room form

Fields:

- Name;
- Width;
- Depth;
- Placement: Automatic, World origin, Canvas cursor, North/East/South/West of
  reference;
- Reference room when required;
- Gap when applicable;
- derived origin and area.

Default placement is Automatic non-overlapping. If a room is selected, offer
directional placement prominently without forcing it.

### 7.4 Furniture form

Fields:

- Room;
- Template;
- Label;
- Width, depth, height;
- Rotation;
- Placement: Room centre, Canvas cursor, Exact;
- X/Y only when Exact;
- Save as custom template toggle/name where appropriate.

Template dimensions are accepted automatically. The user must not retype width,
depth, and height merely to accept defaults.

### 7.5 Door form

Fields:

- Owner room;
- Wall side;
- Width;
- Placement mode and offset;
- Hinge;
- Connected room or Outside;
- Opens into;
- Opening angle;
- derived aperture bounds and a small textual hinge/swing preview.

Only geometrically adjacent rooms are offered as connected destinations. Invalid
offsets, overlaps, and destination combinations are explained inline.

### 7.6 Alignment and edit forms

Alignment shows Moving room, Reference room, Operation, conditional Gap, and
conditional source/target corners together.

Edit reuses the same form definition populated from the selected object. Add
and Edit must not drift into separate validation behavior.

## 8. Geometry preview and PICK mode

When form values are valid enough to describe geometry, show a transient ghost
preview on the canvas:

- proposed room bounds;
- proposed furniture footprint;
- door aperture, leaf, and swing;
- alignment result and gap;
- errors/warnings attached to the proposed location.

Preview state is never:

- added to the canonical model;
- added to history;
- assigned a permanent ID;
- written to disk;
- considered by autosave.

The renderer may consume `session.ui_state.preview` as an additional semantic
scene layer. Apply constructs and dispatches the real action once.

Spatial fields may offer a PICK action:

1. Keep the form open or docked.
2. Focus the canvas in `PICK` mode.
3. Move the crosshair with the canvas navigation keys.
4. Enter accepts the coordinate and returns to the form.
5. Esc returns without changing the draft field.

## 9. Architecture

Add the following modules:

```text
lua/roomplan/ui/
├── workspace.lua          tab/window/buffer lifecycle and responsive layout
├── workspace_state.lua    pure transient UI reducer
├── presenter.lua          session/model → display-only pane view models
├── action_registry.lua    contextual actions, keys, availability and reasons
├── palette.lua            native keyboard action/session chooser
├── panels/
│   ├── objects.lua
│   ├── properties.lua
│   ├── issues.lua
│   ├── action_bar.lua
│   └── empty_state.lua
├── form/
│   ├── engine.lua         form lifecycle and generation/revision guards
│   ├── reducer.lua        pure draft/event transitions
│   ├── render.lua
│   └── fields.lua
└── forms/
    ├── room.lua
    ├── furniture.lua
    ├── door.lua
    ├── alignment.lua
    ├── plan.lua
    └── template.lua
```

The release-candidate implementation uses `form/init.lua` for the Neovim
adapter and `form/state.lua` for the pure reducer. Room, Furniture, Door,
Alignment, Plan, and Template form modules are implemented.

### 9.1 Responsibilities

- `workspace.lua` owns only UI buffers/windows and focus restoration.
- `workspace_state.lua` contains no Neovim calls.
- `presenter.lua` converts exact model/session state into human display rows.
- `action_registry.lua` is the single source for menu, sidebar, footer, command
  availability, key hints, and disabled reasons.
- Form reducers and validators are pure where possible.
- Form submission invokes existing controller/actions; it does not mutate model
  tables.
- `render/canvas.lua` continues to own canvas rendering but must support being
  attached to a workspace-supplied window.
- Existing object/validation/inspector formatting may be reused through
  presenters, then retired after parity.
- `controller.lua` remains the public compatibility facade while long UI chains
  move into form specifications.

### 9.2 Transient state

Suggested session-only state:

```lua
session.workspace = {
  tabpage = nil,
  layout = "wide",
  focused_pane = "canvas",
  buffers = {},
  windows = {},
}

session.ui_state = {
  left_tab = "objects",
  expanded = {},
  filters = {},
  preview = nil,
  form = {
    kind = "add_room",
    generation = 4,
    base_revision_id = 12,
    active_field = "width",
    raw = {},
    parsed = {},
    errors = {},
  },
}
```

Continue using the existing authoritative transient fields for selection,
viewport, interaction mode, snapping, and validation.

Form callbacks require both a workflow generation token and the model revision
on which the draft was based. Reload, close, source replacement, or an
incompatible model edit invalidates stale callbacks safely.

### 9.3 Refresh model

Avoid redrawing every pane for every keystroke.

- Model revision change: refresh objects, properties, issues, action bar, and
  canvas scene.
- Selection change: refresh selection marks, properties, action bar, and only
  affected object rows.
- Viewport/cursor change: refresh canvas and coordinate status only.
- Form field change: refresh form, preview, and relevant derived properties.
- Source status change: refresh global status/action bar only.

Coalesce scheduled redraws as the current canvas already does.

## 10. Compatibility and configuration

All existing Ex commands remain:

- `:RoomPlan` opens the native keyboard action palette for the active session,
  or for choosing/opening a session;
- `:RoomPlanAddRoom`, `AddDoor`, `AddFurniture`, `Align`, and `Edit` open the
  matching form;
- `:RoomPlanObjects`, `Inspect`, and `Validate` focus the corresponding pane or
  drawer;
- direct save/reload/conflict commands keep existing semantics;
- Lua API method signatures remain stable.

Implemented configuration surface:

```lua
require("roomplan").setup({
  ui = {
    experience = "workspace", -- temporary "classic" fallback for one cycle
    workspace = {
      layout = "auto",        -- auto, wide, medium, compact
      left_width = 32,
      right_width = 36,
      wide_min_columns = 120,
      compact_max_columns = 89,
      compact_min_rows = 22,
      min_canvas_width = 55,
      min_canvas_height = 10,
      footer_height = 2,
      cycle_tabs = true,
      ascii = false,
      border = "rounded",
    },
  },
})
```

Workspace, Canvas, form, palette, and contextual-action mappings share one resolver.
`keymaps.enabled` suppresses all of them; semantic-name and default-lhs
overrides affect both installed bindings and displayed action-bar/form hints.
Useful semantic names include `workspace_next_pane`, `focus_objects`,
`focus_canvas`, `focus_properties`, `focus_issues`, `form_apply`, `form_edit`,
`form_cancel`, `palette_next`, `palette_choose`, and `palette_cancel`.

If a classic compatibility mode is retained, it receives safety fixes but no
new workflows. It should be removed after one compatibility cycle once form
parity and documentation are complete.

## 11. Implementation phases

### Phase 0 — Repair the first five minutes

Deliver:

- initial logical cursor placement;
- centered empty-state card;
- direct `a` → Add Room behavior on an empty plan;
- first-spatial-object fit/select/focus;
- offscreen-plan banner;
- object counts and cursor world coordinates;
- contextual footer;
- `f` Fit alias;
- regression tests and documentation of the temporary current workflow.

Exit criteria:

- A fresh plan is never header plus whitespace.
- First canvas navigation works without manual cursor repositioning.
- A newly added 5000 × 4000 room is fully visible and selected.
- A populated fixture produces visible geometry in a controller-level test.

### Phase 1 — Workspace shell

Deliver:

- workspace/window lifecycle manager;
- wide, medium, and compact layout calculation;
- Objects/Issues pane;
- Properties pane;
- shared action/status footer;
- focus navigation and synchronized selection;
- responsive resize handling;
- hide/reopen/close cleanup;
- existing prompt workflows routed from the new action registry temporarily.

Exit criteria:

- One tab behaves as one application workspace.
- Selection from sidebar and canvas stays synchronized.
- No inspector/object/validation action opens a surprise unrelated split.
- Narrow terminals retain a usable canvas and accessible drawers.

### Phase 2 — Form engine and Room vertical slice

Deliver:

- pure form reducer and field descriptors;
- form buffer/float renderer;
- anchored scalar/choice editors;
- inline validation and measurement normalization;
- Apply/Cancel/revision guards;
- Add Room and Edit Room forms;
- valid room preview;
- PICK placement mode;
- one-action undo behavior.

Exit criteria:

- The user sees name, width, depth, placement, and result together.
- `5m` visibly normalizes to `5000 mm`.
- Invalid input remains present with an inline error.
- Cancel leaves model/history/IDs unchanged.
- Apply creates exactly one undo entry and shows the fitted room.

### Phase 3 — Complete primary planning workflows

Deliver:

- Furniture Add/Edit form using template defaults without forced re-entry;
- Door Add/Edit form with adjacency and swing preview;
- Alignment form and preview;
- plan/settings and custom-template forms;
- duplicate/delete confirmations integrated into workspace;
- Properties actions and Issues navigation;
- preview validation styling;
- keep-selection-visible behavior for edits.

Exit criteria:

- The complete MVP acceptance scenario is possible without a chain of blind
  prompts or leaving the workspace.
- Door and furniture forms expose all relevant state simultaneously.
- Every Apply is atomic; every Cancel is side-effect-free.

### Phase 4 — Polish, compatibility, and release

Deliver:

- accessibility/no-color review;
- ASCII and Unicode workspace snapshots;
- light/dark theme checks;
- manual terminal-size smoke matrix;
- performance profiling and refresh coalescing;
- classic-mode deprecation decision;
- README captures, five-minute walkthrough, and `:help` rewrite;
- compatibility testing on supported Neovim versions.

Exit criteria:

- No known P0/P1 workspace defect.
- All old storage/model/action tests still pass.
- New UX acceptance and responsive-layout tests pass.
- Documentation begins with the visible workspace, not a command catalogue.

## 12. Test plan

### 12.1 Pure tests

- responsive layout calculation at boundary sizes;
- action availability and disabled reasons;
- object tree presentation and ordering;
- properties presentation;
- form navigation/reducer events;
- conditional field visibility;
- measurement raw/parsed/normalized representation;
- form validation and first-error focus;
- stale revision/generation rejection;
- cancel and reset semantics;
- preview proposal generation without input mutation.

### 12.2 Renderer snapshots

- empty plan card at 80 × 24 and 120 × 40;
- non-empty but offscreen warning;
- first room fully fitted;
- wide workspace;
- medium workspace;
- compact canvas with each drawer;
- Objects and Issues tabs;
- selected properties and diagnostics;
- Add Room, Furniture, Door, and Alignment forms;
- inline field errors;
- Unicode and ASCII modes;
- focus/selection/severity without color assumptions.

### 12.3 Headless integration tests

- initial cursor is in drawable area;
- first `h/j/k/l` moves and first Enter can hit-test;
- empty plan → `a` → structured Add Room form;
- invalid value retained with inline error;
- cancel leaves model and history unchanged;
- Apply creates one history node;
- first room is selected, fitted, and visibly rasterized;
- sidebar selection updates canvas and Properties;
- Issues selection navigates to geometry;
- template-default furniture creation;
- connected-door creation and preview;
- alignment preview and Apply;
- hide/reopen retains workspace UI state safely;
- close destroys all workspace buffers/windows but not unrelated user windows;
- resize crosses all breakpoints cleanly;
- multiple sessions do not share buffers, drafts, or selections;
- source reload/conflict invalidates forms safely;
- no global mappings;
- guard/source/save lifecycle regressions remain green.

### 12.4 Manual smoke matrix

Headless tests cannot determine whether the interaction feels coherent. Before
release, manually test:

- 80 × 24, approximately 110 × 35, and 160 × 50 terminals;
- a common Unicode font and ASCII fallback;
- light and dark colorschemes;
- vanilla `vim.ui`, plus one enhanced select/input provider if installed;
- Neovim 0.10, 0.11, and 0.12;
- keyboard-only complete acceptance workflow;
- temporarily hide/reopen, suspend/resume, and terminal resize.

## 13. UX acceptance scenarios

### Scenario A — First room

1. Initialize an empty plan.
2. See “Empty floor plan,” Add First Room, Help, and key hints.
3. Press `a`.
4. See one form containing Name, Width, Depth, Placement, and derived result.
5. Enter `Living room`, `5m`, and `4m`.
6. Apply once.
7. See a complete selected 5000 × 4000 room fitted in the canvas.
8. See the room in Objects and exact values in Properties.
9. Undo once and return to the explicit empty state.

### Scenario B — Bedroom, door, and sofa

1. Add a bedroom using one room form and place it east of Living room.
2. Add a shared door using one door form and inspect the swing preview.
3. Add a sofa by accepting catalogue dimensions without retyping them.
4. Move and rotate the sofa while Properties remains synchronized.
5. See collision warnings in both Properties and Issues.
6. Save without leaving the workspace.

### Scenario C — Narrow terminal

1. Open the same plan at 79 columns.
2. Canvas remains useful rather than being crushed by permanent sidebars.
3. Open Objects as a drawer, select Bedroom, and return to centered canvas.
4. Open Edit and complete the form without content being clipped.
5. Resize wider and receive the full workspace without losing selection or
   viewport unnecessarily.

## 14. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Workspace window teardown affects user windows | Track every owned tab/window/buffer; make teardown idempotent; never close unowned handles. |
| Canvas shrinks when panes open | Responsive minimum canvas size; preserve world center; fit only on first object or explicit request. |
| Forms become a second model layer | Store raw draft only; derive proposals; submit through existing canonical actions. |
| Preview accidentally persists | Separate preview scene layer; no ID reservation/history/storage/autosave. |
| Async callbacks become stale | Existing generation token plus base model revision checks. |
| Controller remains too large | Migrate one workflow at a time into form specs after parity tests. |
| Key meanings vary by pane | Persistent action bar, contextual help, buffer-local maps, predictable Esc/q stack. |
| Enhanced `vim.ui` provider differences | Workspace owns structure; use `vim.ui` only for a scalar editor/choice fallback. |
| Refresh becomes slow | Pure presenters, dirty-pane tracking, scheduled/coalesced redraws. |
| UI regressions threaten storage safety | Do not change persistence contracts; retain all existing lifecycle tests. |

## 15. Explicit non-goals

This refactor does not include:

- mouse drag-and-drop as a required workflow;
- arbitrary-angle or polygon geometry;
- a rewrite of the canonical model or storage format;
- a mandatory `nui.nvim`, Telescope, Snacks, or other UI dependency;
- parsing geometry from canvas text;
- free-form editing of raw JSON in the workspace;
- animation or graphical assets;
- simultaneous multi-session plans in one workspace tab.

Optional mouse selection and resizing may be added after the keyboard UX is
complete and tested.

## 16. Accepted implementation decision

The core of phases 0 through 3 was accepted and implemented as one coherent
workspace release candidate. The resulting defaults are:

- workspace experience enabled by default;
- Objects/Issues left, Canvas center, Properties right on wide terminals;
- compact drawers below 90 columns;
- built-in dependency-free form engine;
- RoomPlan-native action palette for session and Add actions;
- scalar editing uses `vim.ui.input` while the complete draft and errors remain
  visible;
- textual form preview enabled; Canvas ghost preview remains follow-up work;
- temporary classic mode for one compatibility cycle only;
- existing commands and buffer-local mappings preserved through a centralized,
  configurable resolver.

## 17. Remaining UX work

The former workaround is no longer required: a fresh plan has a visible empty
state, `a` opens Add Room directly, the first room is fitted, and Objects,
Issues, Properties, and action hints remain part of one workspace.

Release follow-up should concentrate on:

- rendering the detached form proposal as ghost geometry on the Canvas;
- adding an interactive PICK round-trip for cursor-derived form fields;
- completing manual theme, terminal-size, and enhanced-`vim.ui` smoke tests.
