# Aspect and rotation

Terminal character cells are usually taller than they are wide. RoomPlan
stores `canvas.cell_aspect` as **cell height divided by cell width** and uses it
to derive the world distance represented by a row. The default is `2.0`.

If a square room looks vertically stretched or compressed, run:

```vim
:RoomPlanAspect 2.0
```

Omit the argument to edit the current value through `vim.ui.input`. Calibration
is process-wide because every canvas shares the same terminal font geometry;
RoomPlan refits every live session after a change. It does not write your
configuration. Once satisfied, persist the value:

```lua
require("roomplan").setup({
  canvas = { cell_aspect = 2.0 },
})
```

Changing the font, line spacing, terminal, or GUI frontend may require a new
value. Use `:checkhealth roomplan` to see the effective calibration.

## Rotating the view

`Alt-l` rotates clockwise, `Alt-h` rotates counter-clockwise, and `g0` resets to
north-up. The command form is:

```vim
:RoomPlanRotateView clockwise
:RoomPlanRotateView counterclockwise
:RoomPlanRotateView reset
```

Rotation affects only the canvas projection. It does not rotate Neovim's
windows, alter room/door/furniture coordinates, create history, or persist in
the plan. The compass displays where world north points (`N↑`, `N→`, `N↓`, or
`N←`). Movement and pan keys remain screen-relative and are converted to world
directions before a model action is created.

Rotation occurs in 90-degree steps and preserves the world point under the
logical cursor when possible. Aspect calibration remains height/width of the
terminal cell; it does not swap when the view rotates.

← [Appearance](appearance.md) | [Documentation home](../README.md) | [Storage and sessions](../data/storage-and-sessions.md) →
