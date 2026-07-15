# Navigation

RoomPlan is keyboard-first and installs mappings only in its own buffers.
Keys follow screen directions even after the view is rotated.

## Panes and rows

- `Tab` / `Shift-Tab` cycle enabled panes.
- `1`, `2`, `3`, and `!` focus Navigator, Canvas, Details, and Issues.
- In Objects and Issues, use `j` / `k` and `Enter` to select a row.
- In Objects, `h` / `l` collapse or expand the focused room; `/` filters.
- In Details, `Enter` or `Space` toggles a section and `h` / `l` collapses or
  expands it.

## Canvas modes

RoomPlan displays the active mode in the action bar.

**NAV** is the normal mode. `h j k l` moves the logical cursor one cell and
`H J K L` moves five. `Enter` selects an object under the cursor; repeated
presses cycle overlapping hit targets. `Tab` and `Shift-Tab` cycle scene
objects through the workspace panes.

**MOVE** starts with `m` and requires a selected room, door, window, outlet, or
furniture item. Directions use a whole multiple of the plan's normal step large
enough to move at least one visible cell; uppercase directions do the same with
the coarse step. This avoids partial terminal-cell movement where only one
border or label appears to shift. Ctrl-directions retain the exact fine step
for precision and can be smaller than a cell. The action bar reports the actual
distance used by the last keypress. Zoom in with `.` when normal movement
should become more granular without changing the saved plan settings. Door,
window, and wall-outlet movement is constrained to the assigned wall; floor
outlets move inside their owner room. Snapping
applies unless disabled with `gs` or bypassed once with `g!`.

**PAN** starts with `p`. Directions shift the viewport without changing model
geometry. The normal and coarse distances come from `canvas.pan_step_cells`
and `canvas.pan_coarse_step_cells`.

Forms are their own interaction context. Their drafts remain detached until
you apply them; see [Forms and actions](forms-and-actions.md).

## Escape and hide

`Esc` handles the innermost active context first: cancel a form or prompt,
leave MOVE/PAN, return from a side pane or drawer to Canvas, then clear the
selection. `q` closes a compact drawer when one is open; otherwise it hides
the workspace while retaining the session.

← [Workspace overview](overview.md) | [Documentation home](../README.md) | [Workspace panels](panels.md) →
