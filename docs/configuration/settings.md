# Settings

Call `setup()` after RoomPlan is on `runtimepath`:

```lua
require("roomplan").setup({})
```

Every call starts from immutable defaults, validates the complete candidate,
then swaps it in. Unknown keys and wrong value types raise one grouped error
instead of becoming stale no-ops.

## Plan defaults and catalogues

```lua
plan_defaults = {
  metadata = { name = nil, notes = "" },
  settings = {
    grid_mm = 100,
    fine_step_mm = 10,
    normal_step_mm = 100,
    coarse_step_mm = 500,
    default_door_width_mm = 900,
  },
},
furniture = {
  include_builtins = true,
  definitions = {},
  files = {},
},
```

These plan defaults apply only when initializing a new source; they do not
rewrite opened plans. A `nil` name uses the schema's `Untitled plan`. Movement
steps and the grid are stored per plan and can later be edited by selecting the
plan row and pressing `e`. Furniture imports are covered in
[Furniture catalogues](../planning/furniture-catalogs.md).

## Safety and history limits

```lua
limits = {
  max_dimension_mm = 100000,
  max_abs_coordinate_mm = 1000000,
  max_plan_span_mm = 1000000,
  max_auto_place_distance_mm = 100000,
  max_history = 100,
  max_history_bytes_per_session = 64 * 1024 * 1024,
  max_history_bytes_global = 256 * 1024 * 1024,
},
```

The geometry limits produce validation errors; the auto-placement limit bounds
its search. History is bounded by both entry count and estimated retained
snapshot memory. Eviction preserves the current revision and may reduce the
available undo depth.

## Canvas and snapping

```lua
canvas = {
  open = "tab",                 -- "tab", "split", or "vsplit"
  unicode = "auto",             -- "auto", "unicode", or "ascii"
  mm_per_column = 100,
  cell_aspect = 2.0,             -- terminal cell height / width
  zoom_factor = 1.25,
  min_mm_per_column = 1,
  max_mm_per_column = 100000,
  fit_margin_cells = 2,
  header_lines = 1,
  pan_step_cells = 5,
  pan_coarse_step_cells = 20,
  show_grid = false,
  show_dimensions = true,
  show_compass = true,
},
snapping = {
  enabled = true,
  tolerance_cells = 1.5,
  max_distance_mm = 250,
  priority = { "door", "room_edge", "room_center", "furniture", "grid" },
},
```

`mm_per_column` is the initial/fallback scale; Fit chooses a scale from the
scene. Snap tolerance begins in displayed cells, converts through the current
viewport, then is capped in millimetres. The priority resolves equal
candidates deterministically.

## Workspace and notifications

```lua
ui = {
  confirm_delete = true,
  notify_level = "info",         -- "debug", "info", "warn", or "error"
  workspace = {
    layout = "auto",             -- "auto", "wide", "medium", or "compact"
    left_width = 26,
    right_width = 30,
    navigator_visible = true,
    details_visible = false,
    wide_min_columns = 120,
    compact_max_columns = 89,
    compact_min_rows = 22,
    min_canvas_width = 55,
    min_canvas_height = 10,
    footer_height = 1,
    cycle_tabs = true,
    ascii = false,
    border = "rounded",
  },
},
```

`layout = "auto"` selects the responsive rules documented in
[Workspace overview](../workspace/overview.md). A forced layout is useful for
testing but may be cramped. `border` accepts any border style supported by
`nvim_open_win`. Setting `footer_height = 0` removes the persistent action bar;
`?` and commands remain available.

## Autosave, mappings, and glyphs

```lua
autosave = {
  enabled = false,
  debounce_ms = 1000,
  norg = false,
},
keymaps = {
  enabled = true,
  mappings = {},
},
glyphs = nil,
```

Autosave runs only for an unchanged, conflict-free, layout-valid revision.
Norg requires explicit opt-in and an otherwise unmodified source buffer.
Mappings and custom glyph requirements have dedicated chapters:
[Keymaps](keymaps.md) and [Appearance](../display/appearance.md).

← [Coordinates and schema](../data/coordinates-and-schema.md) | [Documentation home](../README.md) | [Keymaps](keymaps.md) →
