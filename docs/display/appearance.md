# Appearance

RoomPlan uses semantic highlights and one-cell glyph sets, so it follows the
active colorscheme without depending on a UI framework.

## Plan colors

Room and furniture forms include a Color choice. Press `Enter` on that field
to use the configured `vim.ui.select` provider, or use `h` / `l` to cycle the
built-in palette. `Theme default` inherits the active colorscheme.

Selected palette colors are saved as canonical `#RRGGBB` values and appear as
foreground accents on room labels and furniture outlines and labels. Selection,
error, and warning highlights always take priority, so plan colors cannot hide
diagnostics. The palette is intentionally small and dependency-free; arbitrary
hex input and recently used colors remain future UX work.

## Glyph modes

Set `canvas.unicode` to `"auto"` (default), `"unicode"`, or `"ascii"`.
Unicode provides box-drawing walls, furniture, hinge, and swing glyphs plus
double-line windows, inward-facing half-circle wall outlets, and full-circle
floor outlets. ASCII uses portable single-cell characters, including `=`/`W`
for windows, directional wall-outlet markers, and `O` for floor outlets.
RoomPlan validates the entire set with Neovim's display-width calculation; if
any configured glyph does not occupy exactly one cell, it falls back atomically
to ASCII rather than mixing misaligned characters.

`ui.workspace.ascii = true` separately changes the Details panel borders and
expansion markers to ASCII. `canvas.show_grid` and `canvas.show_compass`
control optional visual layers. They never change saved geometry.

## Canvas detail

`canvas.detail_level` defaults to `"middle"`. The three levels are:

- `high`: labels plus all exterior wall-run, furniture width/depth, and
  door/window width dimensions;
- `middle`: labels plus exterior wall-run dimensions;
- `none`: geometry only, with no labels or dimensions.

Press `t` to cycle them for the current session, or set an exact level with
`:RoomPlanCanvasDetail high|middle|none`. Detail is transient presentation;
it never changes plan geometry or semantic history.

A custom `glyphs` table must supply all 16 wall masks (`wall[0]` through
`wall[15]`) and every furniture, door, window, outlet, grid, error, warning,
and replacement glyph. Each value must be a non-empty one-cell string. Run
`:checkhealth roomplan` after changing fonts or glyphs.

## Highlight groups

The main canvas groups are:

`RoomPlanWall`, `RoomPlanDoor`, `RoomPlanWindow`, `RoomPlanOutlet`,
`RoomPlanFurniture`, `RoomPlanRoomLabel`, `RoomPlanFurnitureLabel`,
`RoomPlanPreview`, `RoomPlanSelected`, `RoomPlanSnap`, `RoomPlanSnapOverlap`, `RoomPlanError`,
`RoomPlanWarning`, `RoomPlanGrid`, `RoomPlanStatus`, `RoomPlanMuted`, and
`RoomPlanCompass`. Sun studies additionally use `RoomPlanSunWall`,
`RoomPlanSunWindow`, and `RoomPlanSunlight1` through `RoomPlanSunlight5`.
The five floor-light backgrounds form an adaptive yellow-to-orange gradient
derived from the active `Normal` background, so they remain visible without a
fixed light or dark theme palette.

Workspace groups use the `RoomPlanWorkspace*` prefix for titles, active and
inactive borders, cursor rows, selection, keys, values, object kinds, and
diagnostic severities. Defaults link to standard groups such as `Title`,
`Special`, `Identifier`, `Visual`, `IncSearch`, and `DiagnosticError`. RoomPlan
does not define a separate fixed palette: links follow the active colorscheme
and are restored after `ColorScheme`. User overrides remain optional.

Override groups after your colorscheme loads:

```lua
vim.api.nvim_set_hl(0, "RoomPlanWall", { link = "Function" })
vim.api.nvim_set_hl(0, "RoomPlanFurniture", { link = "Identifier" })
vim.api.nvim_set_hl(0, "RoomPlanPreview", { link = "DiffAdd" })
vim.api.nvim_set_hl(0, "RoomPlanSnap", { link = "DiagnosticInfo" })
vim.api.nvim_set_hl(0, "RoomPlanSnapOverlap", { link = "IncSearch" })
vim.api.nvim_set_hl(0, "RoomPlanWorkspaceActiveBorder", { link = "FloatBorder" })
```

Use a `ColorScheme` autocmd for overrides that must survive colorscheme
changes. If proportions, rather than glyph widths, look wrong, continue with
[Aspect and rotation](aspect-and-rotation.md).

← [Furniture catalogues](../planning/furniture-catalogs.md) | [Documentation home](../README.md) | [Aspect and rotation](aspect-and-rotation.md) →
