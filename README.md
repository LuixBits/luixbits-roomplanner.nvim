# roomplan.nvim

`roomplan.nvim` is a terminal-native flat-planning plugin for Neovim. It keeps
exact geometry in millimetres, renders an interactive Unicode or ASCII canvas,
and stores the same plan either as a standalone `*.roomplan.json` file or as a
JSON block inside a Norg note.

The drawing is a view of structured data. Moving a wall character can never
corrupt the plan because rendered characters are not the source of truth.

## What it does

- Creates, sizes, moves, aligns, duplicates, and deletes rectangular rooms.
- Places one physical hinged doorway on an exterior or shared room boundary.
- Shows the door hinge, leaf, approximate swing, and opening side.
- Provides a generic furniture catalogue plus project-local custom templates.
- Places and rotates rectangular furniture at exact room-local coordinates.
- Snaps to the grid and plan geometry while retaining exact integer-mm data.
- Validates references, bounds, overlap, door apertures, and door swings.
- Provides semantic model undo/redo independent of the source buffer's undo.
- Saves deterministic, strict JSON with unknown extension fields preserved.
- Safely embeds the same model in a marked Norg ranged tag.
- Keeps multiple plans open while allowing only one writable session per source.
- Opens a persistent Objects/Issues, Canvas, Properties, and action-bar
  workspace that adapts to the terminal size.
- Uses structured, validated forms for rooms, furniture, doors, alignment,
  plan settings, and project templates instead of blind prompt sequences.
- Uses a native keyboard action palette for `:RoomPlan` and the non-empty Add
  menu, with no numbered prompt chain.
- Requires no runtime dependency beyond Neovim; Neorg is optional.

Representative wide workspace in ASCII mode:

```text
 Objects / Issues    |             Canvas              | Properties
 My flat             | +------------------+----------+ | Sofa
 2 rooms - 1 door    | | Living room      D Bedroom  | | Size: 2100 x 900 mm
 > Living room       | |   +--------+                 | | Rotation: 0 degrees
   D east -> Bedroom | |   | Sofa   |                 | | Diagnostics: none
   Sofa 2.1m x 0.9m  | |   +--------+                 | | [e] Edit  [m] Move
 [a] Add [e] Edit [m] Move [A] Align [v] Validate [s] Save [?] Help
 NAV - SAVED - snap on - focus canvas - zoom 1.00
```

This is a spatial planning tool, not CAD/BIM software or a building-code
checker. Version 1 deliberately supports one floor, rectangular rooms,
zero-thickness abstract walls, rectangular furniture, 90-degree furniture
rotation, and single-leaf hinged doors.

## Requirements

- Neovim 0.10 or newer.
- Primary tested target: Neovim 0.12.4.
- A UTF-8 terminal is recommended. ASCII mode is available for unsuitable
  fonts, glyph widths, or terminals.
- No mandatory Telescope, fzf-lua, Snacks, nui.nvim, Neorg, or Tree-sitter
  dependency.

The compatibility matrix covers the latest selected 0.10 and 0.11 patches,
0.12.4, and nightly. Nightly is visible but allowed to fail while upstream API
changes are investigated.

## Installation

### Neovim 0.12 `vim.pack`

`vim.pack` is available only on Neovim 0.12 and newer.

```lua
vim.pack.add({
  { src = "https://github.com/devluixos/luixbits-roomplanner.nvim" },
})

require("roomplan").setup({})
```

### lazy.nvim

```lua
{
  "devluixos/luixbits-roomplanner.nvim",
  config = function()
    require("roomplan").setup({})
  end,
}
```

Do not lazy-load solely on one filetype if you want `:RoomPlanInit path` and
`:RoomPlanOpen path` to work from arbitrary buffers. Loading on the RoomPlan
commands is safe if every command in the command table below is included.

### Native packages / another package manager

Clone the repository into a `start` package directory:

```sh
git clone https://github.com/devluixos/luixbits-roomplanner.nvim \
  ~/.local/share/nvim/site/pack/plugins/start/roomplan.nvim
nvim --headless "+helptags ALL" +qa
```

Any plugin manager that adds the repository root to `runtimepath` works. Call
`require("roomplan").setup({})` from `init.lua` when configuring options.

### Local development checkout

```lua
vim.opt.runtimepath:prepend("/absolute/path/to/roomplan.nvim")
require("roomplan").setup({})
```

The `plugin/roomplan.lua` loader registers commands automatically. `setup()` is
optional when all defaults are acceptable and is safe to call repeatedly.

## Five-minute standalone walkthrough

1. Initialize a new source. The standalone initializer refuses to overwrite a
   non-empty file.

   ```vim
   :RoomPlanInit flat.roomplan.json
   ```

2. The workspace opens with an explicit empty state. Press `a` to open the Add
   Room form. Move between fields with `j/k` or Tab, press Enter to edit, set
   the name to `Living room`, width to `5m`, depth to `4m`, and press Ctrl-s to
   create it. Measurements without a suffix are millimetres; `5000`, `5000mm`,
   `500cm`, and `5m` are equivalent.

3. Press `a` again. The native Add palette uses `j/k` and Enter (or its shown
   `r/d/f` shortcut); choose Room and add a `3m` by `3m` Bedroom. Select it in
   Objects, press `A`, then choose Living room and `Place east` in the alignment
   form. East/west placement aligns south edges.

4. Press `D` to add a shared door. The one form shows owner, wall, width,
   placement, hinge, connection, swing side, and angle together. Choose Living
   room's east wall, `900mm`, Bedroom, and `connected`. One stored doorway cuts
   both coincident room boundaries.

5. Press `F` to add a sofa. Catalogue dimensions are already populated and can
   be accepted unchanged or edited before choosing room-centre, cursor, or
   exact room-local placement.

6. Press `1` for Objects, use `j/k`, and Enter to select the sofa;
   press `2` to return to Canvas. Press `m`, move with `h/j/k/l`, rotate with
   `r`, and use Esc to leave MOVE mode. `u` and Ctrl-r provide semantic
   undo/redo.

7. Press `v` to validate and focus Issues, then `s` to save. Layout errors
   block an ordinary save; `:RoomPlanSave!` deliberately saves a structurally
   valid but layout-invalid repair draft.

8. Press `q` to hide the workspace without losing the session. Reopen it with
   `:RoomPlanOpen flat.roomplan.json` or `:RoomPlan`. Use `:RoomPlanClose` when
   you actually want to unload the session.

## Norg walkthrough

Neorg is not required. The current adapter uses a specification-based scanner
for Norg ranged tags; the health check reports whether a Norg parser is present
for diagnostics and future optional discovery enhancements.

Open an existing `.norg` note and run:

```vim
:RoomPlanInit
```

When the note has no plan, RoomPlan appends a `* Floor plan` heading and a
marked block:

```norg
* Floor plan

@code json roomplan.nvim
{
  "format": "roomplan.nvim",
  "schema_version": 1,
  "units": "mm",
  "metadata": {
    "name": "Untitled plan",
    "notes": ""
  },
  "settings": {
    "grid_mm": 100,
    "fine_step_mm": 10,
    "normal_step_mm": 100,
    "coarse_step_mm": 500,
    "default_door_width_mm": 900,
    "default_wall_thickness_mm": 120
  },
  "rooms": [],
  "doors": [],
  "furniture": [],
  "custom_templates": [],
  "extensions": {}
}
@end
```

Use `:RoomPlanOpen` on subsequent visits. RoomPlan replaces only the selected
JSON payload through buffer APIs, but `:RoomPlanSave` then performs a normal
`:write` of the whole Norg buffer. Consequently, unrelated unsaved note edits
are preserved and written too, and normal `BufWritePre`/`BufWritePost`, file
encoding, line-ending, and write-error behavior still applies.

Safety rules:

- Exactly one top-level object whose `format` is `roomplan.nvim` is accepted.
- New blocks use the explicit `@code json roomplan.nvim` marker.
- Legacy unmarked JSON blocks are readable when their top-level format matches.
- Multiple matching plans, malformed marked data, an unterminated marked block,
  or a suspected damaged legacy plan stop initialization instead of guessing.
- Text outside the selected payload is retained logically. Neovim may still
  apply configured line-ending, encoding, BOM, or write-hook transformations
  when the whole note is written.

## Workspace interaction

The default `ui.experience = "workspace"` surrounds the disposable canvas
with synchronized Objects/Issues and Properties panes plus a persistent
context-sensitive action/status bar. Selection is shared: choosing a row
updates the canvas highlight and human-readable properties. An empty plan
shows an Add First Room card instead of whitespace; the first room is selected
and fitted automatically. If populated geometry is outside the viewport, the
canvas says to press `f`.

The layout responds automatically:

- At 120 columns and above, Objects/Issues, Canvas, and Properties are visible.
- From 90 through 119 columns, Objects/Issues and Canvas remain visible;
  Properties uses the left pane when focused.
- At 89 columns or fewer, or under 22 usable rows, Canvas remains persistent
  and the other panes open as drawers.

All workspace, canvas, form, and palette mappings are buffer-local; nothing is
installed globally. `keymaps.enabled = false` installs none. Overrides may use
either a semantic name or the default left-hand side. The action bar and form
footer use the same resolver, so their displayed keys follow your overrides
and mark disabled actions as unmapped.

`:RoomPlan` opens a RoomPlan-native action palette for the active session (or
for choosing/opening one). A non-empty plan's `a` menu uses the same component.
Navigate with `j/k`, run with Enter or a displayed shortcut, and cancel with
Esc/`q`; it does not show a numbered `vim.ui.select` chain.

| Mapping | Where | Action |
| --- | --- | --- |
| Tab / Shift-Tab | workspace | Cycle Objects, Issues, Canvas, and Properties |
| `1` / `2` / `3` / `!` | workspace | Focus Objects / Canvas / Properties / Issues |
| `j` / `k`, Enter | Objects or Issues | Navigate; select the row and focus Canvas |
| `h` / `l` | Objects | Collapse / expand a room |
| `/` | Objects or Issues | Filter rows |
| `q` | workspace | Close a compact drawer, otherwise hide the workspace |
| `a` / `D` / `F` | workspace | Add an object / door / furniture |
| `e` / `d` / `y` | workspace | Edit / delete / duplicate selection |
| `m` / `A` / `r` | workspace | Move / align / rotate the applicable selection |
| `v` / `s` / `f` / `?` | workspace | Validate / save / fit / help |
| `u` / Ctrl-r | workspace | Undo / redo one semantic action |
| Enter | Canvas NAV | Select or cycle objects under the cursor |
| `h j k l` / `H J K L` | Canvas NAV | Move cursor one / five cells |
| `m`, then directions | Canvas MOVE | Move normal; uppercase coarse; Ctrl-direction fine |
| `p`, then directions | Canvas PAN | Pan without changing geometry |
| `z+` / `z-`, `zf` | Canvas | Zoom in/out; compatibility alias for Fit |
| `gs` / `g!` | Canvas | Toggle snapping / bypass it for the next move |
| Esc | workspace | Cancel form/mode, return to Canvas, then deselect |

### Structured forms

Room, furniture, door, alignment, plan, custom-template, and geometry-edit
commands open one form containing their related fields, derived values,
validation errors, and a text preview. Custom templates appear as selectable
top-level rows in Objects. Select the plan row or a template and press `e` to
edit all of its values together. The form draft is transient; only Apply
performs one semantic action.

| Mapping | Form action |
| --- | --- |
| `j` / `k`, Tab / Shift-Tab | Move between visible fields |
| Enter or `e` | Edit text/measurement, or choose from a list |
| `h` / `l` or Space | Cycle a choice or toggle |
| Ctrl-s | Validate and apply atomically |
| `R` | Reset the complete form draft |
| Esc or `q` | Cancel without changing the plan |

Add Room and Align expose an explicit `Allow invalid draft` toggle. It permits
the requested layout operation without silently repairing geometry; validation
still reports the resulting errors and normal save rules still apply.

Set `ui.experience = "classic"` to temporarily restore the original
canvas-plus-`vim.ui` prompt workflow. Classic mode retains the same model,
storage, commands, and safety behavior, but does not receive the workspace
panes or structured geometry forms.

## Commands

| Command | Meaning |
| --- | --- |
| `:RoomPlan` | Open the native context-aware action palette |
| `:RoomPlanMenu` | Alias for the action palette |
| `:RoomPlanOpen [path]` | Open/focus a standalone or Norg source |
| `:RoomPlanInit [path]` | Safely initialize current source or path |
| `:RoomPlanHide` | Hide workspace/canvas while retaining the live session |
| `:RoomPlanClose[!]` | Close session; `!` explicitly discards protected model state |
| `:RoomPlanAddRoom` | Open the structured Add Room form |
| `:RoomPlanAlign` | Open the room alignment form |
| `:RoomPlanAddDoor` | Open the structured Add Door form |
| `:RoomPlanAddFurniture` | Open the structured Add Furniture form |
| `:RoomPlanEdit` | Open a populated form for the selected plan/object/template |
| `:RoomPlanDuplicate` | Duplicate selected object |
| `:RoomPlanDelete` | Delete selection; room deletion summarizes its cascade |
| `:RoomPlanObjects` | Focus Objects/drawer; classic mode opens its list |
| `:RoomPlanInspect` | Focus Properties/drawer; classic mode toggles inspector |
| `:RoomPlanValidate` | Validate and focus Issues |
| `:RoomPlanNextIssue` / `:RoomPlanPrevIssue` | Navigate diagnostics |
| `:RoomPlanUndo` / `:RoomPlanRedo` | Semantic model history |
| `:RoomPlanFit` | Fit all scene geometry to canvas |
| `:RoomPlanAspect [ratio]` | Inspect or change terminal-cell aspect calibration |
| `:RoomPlanSave[!]` | Save; `!` permits layout errors, never structural/source conflicts |
| `:RoomPlanSaveAs[!] path` | Save to a new source; `!` may replace an existing valid JSON plan |
| `:RoomPlanReload[!]` | Reload source; `!` discards protected model state |
| `:RoomPlanResolveConflict` | Review, reload, Save As, or safely overwrite a still-parseable in-buffer payload |

Commands target the session attached to the current source, workspace, or
classic list buffer. When there is exactly one live session it is the fallback.
With multiple unattached sessions, use `:RoomPlan` to choose one.

## Configuration

Every `setup()` call validates a fresh merge over immutable defaults. Unknown
keys raise an error instead of silently doing nothing.

```lua
require("roomplan").setup({
  plan_defaults = {
    metadata = {
      -- nil means use the schema default for a new source
      name = nil,
      notes = "",
    },
    settings = {
      grid_mm = 100,
      fine_step_mm = 10,
      normal_step_mm = 100,
      coarse_step_mm = 500,
      default_door_width_mm = 900,
      default_wall_thickness_mm = 120, -- inert metadata in schema v1
    },
  },
  limits = {
    max_dimension_mm = 100000,
    max_abs_coordinate_mm = 1000000,
    max_plan_span_mm = 1000000,
    max_auto_place_distance_mm = 100000,
    max_history = 100,
    max_history_bytes_per_session = 64 * 1024 * 1024,
    max_history_bytes_global = 256 * 1024 * 1024,
  },
  canvas = {
    open = "tab", -- "tab", "split", or "vsplit"
    unicode = "auto", -- "auto", "unicode", or "ascii"
    mm_per_column = 100,
    cell_aspect = 2.0,
    zoom_factor = 1.25,
    min_mm_per_column = 1,
    max_mm_per_column = 100000,
    fit_margin_cells = 2,
    header_lines = 2,
    pan_step_cells = 5,
    pan_coarse_step_cells = 20,
    show_grid = false,
    show_rulers = false,
    show_dimensions = true,
  },
  snapping = {
    enabled = true,
    tolerance_cells = 1.5,
    max_distance_mm = 250,
    priority = { "door", "room_edge", "room_center", "furniture", "grid" },
  },
  ui = {
    experience = "workspace", -- "workspace" or temporary "classic" fallback
    inspector = "float",
    confirm_delete = true,
    notify_level = "info",
    workspace = {
      layout = "auto", -- "auto", "wide", "medium", or "compact"
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
  autosave = {
    enabled = false,
    debounce_ms = 1000,
    norg = false,
  },
  keymaps = {
    enabled = true,
    -- Keys are a semantic name (for example "form_apply") or a default lhs.
    -- Values are a replacement lhs or false to disable that mapping.
    mappings = {},
  },
  glyphs = nil,
})
```

`plan_defaults` affects only newly initialized plans. Fixed schema defaults,
not local configuration, fill optional fields in an existing v1 document.
Plan movement/grid/door defaults are persisted in each document; canvas style,
limits, snapping preference, and mappings are local.

`ui.workspace.layout = "auto"` chooses the responsive layout described above.
Forcing `wide`, `medium`, or `compact` is useful for a fixed terminal. The
workspace is dependency-free; `vim.ui.input` and `vim.ui.select` are used only
to edit the currently active form field or choice. `ui.inspector` controls the
classic inspector and the workspace's `i` compatibility alias; the normal
Properties pane is independent.

Autosave remains disabled by default. When enabled, successful model edits
schedule a debounced, noninteractive save only for a conflict-free layout with
zero errors. Norg autosave additionally requires `autosave.norg = true` and a
source buffer with no unrelated unsaved note edits. Manual `:RoomPlanSave`
remains the clearest choice when write hooks have side effects.

Workspace, canvas, action, form, and palette mappings share one resolver. Replace a
mapping by semantic name or default lhs, or disable it with `false`. Useful
semantic names include `workspace_next_pane`, `workspace_previous_pane`,
`focus_objects`, `focus_canvas`, `focus_properties`, `focus_issues`,
`form_apply`, `form_edit`, `form_cancel`, `palette_next`, `palette_choose`, and
`palette_cancel`. Displayed action-bar and form keys update automatically:

```lua
require("roomplan").setup({
  keymaps = {
    mappings = {
      hide = "<leader>q",
      workspace_next_pane = "]w",
      focus_objects = "go",
      focus_canvas = "gc",
      form_apply = "<leader>s",
      form_cancel = "<leader>c",
      ["<C-h>"] = false,
      ["s"] = "<leader>w",
    },
  },
})
```

A custom glyph set must be complete: wall masks `0` through `15` and every
furniture, door, grid, error, warning, and replacement glyph must occupy one
display cell. An invalid set falls back atomically to ASCII. See
`lua/roomplan/render/glyphs.lua` and `:help roomplan-glyphs`.

## Terminal aspect calibration

Terminal cells are rectangles, not square pixels. Kitty chooses their pixel
height and width from the active font, font size, DPI, and spacing. Neovim does
not expose that pixel ratio portably, so RoomPlan starts with the common
assumption that one row is twice as tall as one column is wide:

```lua
canvas = {
  cell_aspect = 2.0,
}
```

This is a display calibration only. Exact room and furniture dimensions remain
unchanged in the model and saved JSON. A mismatch becomes especially obvious
when furniture is rotated: its long edge moves from terminal columns to rows.
Low zoom can add a smaller one-cell rounding effect as geometry is rasterized.

Use the runtime command to tune the current Neovim instance without editing
the plan. It is also available as “Calibrate terminal aspect” in `:RoomPlan`:

```vim
:RoomPlanAspect
:RoomPlanAspect 2.2
```

With no argument, the command shows the current value and prompts for a new
one. It refits the visible RoomPlan canvas immediately. If geometry looks too
tall, increase the value; if it looks too flat, decrease it. Zooming in with
`z+` helps distinguish coarse raster rounding from a persistent calibration
error.

Once the value looks right, persist it in local configuration:

```lua
require("roomplan").setup({
  canvas = {
    cell_aspect = 2.2,
  },
})
```

The runtime command deliberately does not write configuration or plan data:
different terminals, fonts, displays, and remote sessions may need different
values. Changing Kitty's line or column adjustment would also affect every
terminal application, so calibrating RoomPlan is normally the safer fix.

## Data model and coordinates

The checked-in Draft 2020-12 schema is
[`schema/roomplan.schema.json`](schema/roomplan.schema.json). Runtime loading is
stricter where JSON Schema cannot express byte limits, global ID uniqueness,
or exact unknown-number preservation.

Core conventions:

- All persisted geometry is a finite integer number of millimetres.
- Positive X points east/right; positive Y points north/up.
- A room origin is its lower-left world coordinate; room size is
  `[width, depth]`.
- Room rectangles are zero-thickness topological boundaries in v1.
- Furniture centres are local to their owning room. Moving the room therefore
  moves its furniture without rewriting child positions.
- Furniture size is `[width, depth, height]`; rotation is clockwise and one of
  `0`, `90`, `180`, or `270` degrees.
- Door offsets start at west and run east on north/south edges; they start at
  south and run north on east/west edges.
- Door hinge `start`/`end` uses that canonical edge direction.
- Door `opens_into` is `owner`, `connected`, or `outside`.
- One connected doorway is stored once, owned by one room, and cuts both
  contributors to a valid shared wall.
- Boundary contact is allowed. Only positive-area rectangle intersection is
  overlap.

IDs are immutable, globally unique, and prefixed: `room-`, `door-`,
`furniture-`, and `custom:`. Built-in template references use `builtin:`.
Renaming an object never changes its ID.

The codec rejects comments, trailing commas, duplicate decoded keys, NaN,
infinity, invalid UTF-8, unsafe known numbers, missing/zero/future schema
versions, and trailing content. Unknown members survive supported-v1
load/edit/history/save semantically, including the difference between null,
empty object, and empty array.

## Furniture catalogue

Built-in generic seeds are always overrideable:

| Template | Default millimetres (W × D × H) |
| --- | --- |
| Bed | 2000 × 1600 × 500 |
| Sofa | 2100 × 900 × 850 |
| Armchair | 900 × 900 × 900 |
| Table | 1600 × 900 × 750 |
| Chair | 500 × 500 × 900 |
| Desk | 1400 × 700 × 750 |
| Wardrobe | 1200 × 600 × 2000 |
| Bookcase/shelf | 900 × 300 × 1800 |
| Cabinet | 800 × 450 × 900 |
| Kitchen unit | 600 × 600 × 900 |
| Appliance | 600 × 600 × 850 |
| Bathroom fixture | 700 × 400 × 850 |
| Custom rectangle | 1000 × 1000 × 1000 |

These are planning seeds, not manufacturer specifications or accessibility
claims. Explicit furniture dimensions remain authoritative when its template
or category changes. Saving dimensions as a custom template stores that
template in the current plan only. Project templates appear in Objects, where
they can be selected, inspected, edited, duplicated, or deleted.

## Validation and invalid drafts

Validation never changes geometry. Errors and warnings are sorted,
highlighted, shown textually, searchable, and navigable by object ID.

Errors include malformed primitives, invalid references, configured plan
limits, room overlap, furniture outside its room, furniture overlap, invalid or
overlapping apertures, and broken door connections. Warnings include unresolved
template references and approximate door-swing collisions with furniture,
walls, or other doors.

Structural failures prevent a session from opening or an action from
committing. Furniture layout errors can remain in a repair draft. Room and door
actions normally block newly introduced layout errors unless the action has an
explicit force policy. Ordinary save blocks layout errors; `:RoomPlanSave!`
saves a structurally valid invalid draft. It never bypasses malformed JSON,
unsupported schema, an unsafe destination, or a source conflict.

## Saving, conflicts, and quit protection

RoomPlan tracks three different things: semantic model history, text staged in
the source buffer, and durable bytes on disk. A successful save records the
current history revision as a savepoint without deleting undo history. Undoing
away from it becomes dirty; redoing exactly to it becomes clean again.

If the selected JSON payload or standalone document changes after opening,
save stops instead of overwriting it. Use `:RoomPlanResolveConflict` to review
the source, reload it, or Save As. When only the authoritative buffer payload
changed, disk is still the expected version, and the payload remains a valid
supported RoomPlan document, a second confirmation may overwrite that payload
while preserving Norg text outside it. A confirmed invalid-draft save is not a
conflict override.

Each live session owns a hidden `acwrite` guard buffer. Its modified flag
mirrors model or staged state that needs protection, allowing ordinary `:qall`,
`:wall`, and buffer deletion to participate in Neovim's unsaved-change checks
even though the visible canvas is a disposable `nofile` buffer.

- `q` / `:RoomPlanHide`: destroy only the workspace/canvas view.
- `:RoomPlanClose`: unload the semantic session after Save/Discard/Cancel.
- `:RoomPlanClose!`: explicitly discard the session's protected model state;
  it does not erase unrelated modifications already present in a source buffer.
- `:qa!`: remains Neovim's explicit process-wide forced escape.

## Lua API

The convenience API is intentionally small:

```lua
local roomplan = require("roomplan")

roomplan.setup({})
roomplan.init({ path = "/tmp/flat.roomplan.json" }, callback)
roomplan.open({ path = "/tmp/flat.roomplan.json" }, callback)
roomplan.save({}, callback)
roomplan.save_as("/tmp/other.roomplan.json", {}, callback)
roomplan.reload({}, callback)
roomplan.set_aspect(2.2)
roomplan.hide({})
roomplan.close({}, callback)
local diagnostics, summary = roomplan.validate({})
local sessions = roomplan.sessions()
```

Callbacks receive `(value, error)`. Errors are structured tables with at least
`code` and `message`. Calls are noninteractive by default; pass
`interactive = true` only when prompts are desired. A required confirmation
otherwise returns a structured error. For programmatic semantic edits:

```lua
local api = require("roomplan.api")
local result, err = api.dispatch(session_id, {
  type = "move_furniture",
  id = "furniture-sofa",
  delta_mm = { 100, 0 },
})
```

The Lua API is provisional before 1.0. The plugin's semantic version and the
persisted `schema_version` are intentionally independent.

## Health and troubleshooting

Run:

```vim
:checkhealth roomplan
```

It reports the Neovim version, Unicode display widths, Norg parser/Neorg
availability, active sessions and their dirty/conflict/pending state, and
autosave status.

Common problems:

- **Canvas corners are doubled or misaligned:** set
  `canvas.unicode = "ascii"`, choose a terminal font whose box-drawing glyphs
  occupy one cell, then rerun the health check.
- **No active session:** open a `*.roomplan.json`/`.norg` source first. When
  several sessions exist, focus one of its buffers or choose it through
  `:RoomPlan`.
- **Normal save refuses:** press `v` or run `:RoomPlanValidate`; repair errors or
  deliberately use `:RoomPlanSave!` for a structurally valid repair draft.
- **Source conflict:** do not edit the JSON payload behind a live canvas. Run
  `:RoomPlanResolveConflict`; Save As is the safest way to preserve both
  versions.
- **Norg save writes other note edits:** this is intentional normal `:write`
  behavior. Save/commit those edits separately before RoomPlan save if desired.
- **Malformed marked Norg block:** fix the existing block in the note. RoomPlan
  will not create a second block beside suspected damaged data.
- **Unsupported encoding:** in-place saving is UTF-8 only. Convert safely or use
  Save As; RoomPlan does not silently transcode surrounding notes.
- **Quit says a hidden buffer is modified:** that is the RoomPlan guard doing
  its job. Save or close the protected session rather than wiping the guard.
- **No mappings:** check `keymaps.enabled` and disabled overrides. All RoomPlan
  workspace, canvas, form, and palette mappings are buffer-local and exist
  only while their corresponding buffers are visible.

Release-candidate limitations: Norg discovery currently uses the conservative
specification-based scanner even when a Tree-sitter parser is installed;
`canvas.show_rulers` is reserved but rulers are not drawn yet. The hosted CI
matrix is configured but cannot run until this directory has a GitHub remote,
and installation examples still need the final repository owner.

## Development

Run the local test suite:

```sh
./scripts/test.sh
```

The suite checks Lua syntax and runs headless Neovim unit/integration tests.
Pure codec, schema, model, actions, geometry, validation, scene, and raster
layers must remain independent of Neovim where documented.

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) and the detailed implementation
contract in [`plan.md`](plan.md) before changing persistence, schema, geometry,
door handedness, lifecycle, or conflict behavior. A new schema version requires
a sequential migration, fixtures, JSON Schema updates, and recovery guidance.

## License

MIT; see [`LICENSE`](LICENSE). Third-party inspiration and attribution policy is
recorded in [`NOTICE`](NOTICE). Neorg is GPL-3.0, optional, and no Neorg
implementation code is copied into this project.
