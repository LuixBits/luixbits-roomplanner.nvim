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

**MOVE** starts with `m` and requires a selected room, door, or furniture item.
Directions move by the plan's normal step, uppercase directions use the coarse
step, and Ctrl-directions use the fine step. Door movement is constrained to
its wall. Snapping applies unless disabled with `gs` or bypassed once with
`g!`.

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
