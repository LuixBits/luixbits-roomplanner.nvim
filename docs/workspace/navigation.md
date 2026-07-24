# Navigation

RoomPlan mappings are local to its buffers. Direction keys follow the screen,
even when the plan view is rotated.

## Panes and rows

- `Tab` and `Shift-Tab` cycle visible panes.
- `1`, `2`, `3`, and `!` open Navigator, Canvas, Details, and Issues.
- In Navigator, use `j` and `k` to move between rows.
- Press `Enter` to select an Objects or Issues row.
- In Objects, use `h` and `l` to collapse or expand a room.
- In Details, `Enter` or `Space` toggles a section.
- Press `/` to filter Objects or Issues.

## Canvas modes

The action bar and Details show the active mode.

### NAV

NAV is the normal mode. Use `h j k l` to move the logical cursor and
`H J K L` for coarse movement. Press `Enter` to select under the cursor.
Repeated presses cycle objects that occupy the same cell.

At the configured `canvas.scrolloff` margin, further movement pans the view.
You can keep navigating a zoomed plan without entering PAN mode.

### MOVE

Select an object and press `m`. Rooms, doors, windows, outlets, and furniture
can move when their geometry permits it.

Normal and coarse movement cover at least one visible Canvas cell. This keeps
movement readable when zoomed out. `Ctrl-h/j/k/l` always uses the exact fine
step. The status shows the distance used.

Doors, windows, and wall outlets stay on their assigned wall. Floor outlets
stay inside their room. Use `gs` to toggle snapping or `g!` to bypass the next
snap.

### PAN

Press `p`, then use the direction keys. PAN changes only the viewport. It never
changes plan geometry.

You can also pan directly with `zh`, `zj`, `zk`, and `zl`.

### RESIZE

Select a room, furniture item, or project template and press `r`. See [Rooms](../planning/rooms.md)
or [Furniture](../planning/furniture.md) for the section controls.

## Leave a context

`Esc` leaves the innermost active context first. It cancels a form or prompt,
leaves MOVE, PAN, RESIZE, or SUN STUDY, returns from a pane to the Canvas, and
then clears the selection.

`q` closes a compact drawer when one is open. Otherwise it hides the workspace
and keeps the session.

← [Workspace overview](overview.md) | [Documentation home](../README.md) | [Workspace panels](panels.md) →
