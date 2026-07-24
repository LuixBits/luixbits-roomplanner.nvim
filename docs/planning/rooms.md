# Rooms

A room is one footprint made from connected rectangular sections. Internal
section edges do not become walls. This makes L shapes and custom floor plans
behave like one room.

## Common actions

| Key | Action |
| --- | --- |
| `a` | Add a room |
| `e` | Edit its name, position, and dimensions |
| `m` | Move the whole room |
| `r` | Edit the footprint on the canvas |
| `A` | Align it with another room |
| `y` | Duplicate it |
| `d` | Delete it |

You can also use `:RoomPlanAddRoom` to create a room.

## Create a room

The add form supports rectangles and L shapes. Enter the dimensions, then
choose where the room should go. RoomPlan can place it automatically, use the
canvas cursor, use an exact origin, or place it beside another room.

The first room defaults to `4000 × 3000 mm`. Automatic placement avoids
overlaps and follows the plan grid.

An L shape is stored as two connected sections. You can change its overall
size, leg dimensions, and missing corner in the normal edit form.

## Edit room details

Select a room and press `e`. The form edits its name, origin, and available
dimensions as one change. A shape preview appears when the editor has enough
space.

For other compound shapes, the form shows the size of each section. Use
**Edit footprint** when you need to add, remove, or reposition section edges.
Pressing `r` opens the same canvas editor directly.

RoomPlan checks attached doors, windows, outlets, and furniture before it
accepts a geometry change. A rejected edit leaves the plan untouched.

## Edit the footprint

The canvas enters `RESIZE` mode and highlights one section.

| Key | Action |
| --- | --- |
| `Enter` | Select the section under the cursor |
| `Tab` / `Shift-Tab` | Select the next or previous section |
| `h j k l` | Choose an edge, then resize with the normal step |
| `H J K L` | Resize with the coarse step |
| `Ctrl-h/j/k/l` | Resize with the fine step |
| `a` | Add a section beside the selected one |
| `d` | Remove the selected section |
| `gs` | Toggle snapping |
| `g!` | Ignore snapping for the next change |
| `s` | Apply the full edit and save |
| `Esc` | Cancel the full edit |

The first horizontal key chooses the west or east edge. The first vertical key
chooses the south or north edge. Further keys on that axis move the chosen
edge.

The result must stay connected and free of holes or overlaps. A section cannot
be removed while a door, window, or outlet refers to it. Nothing enters undo
history until you press `s`.

Snapping can target nearby section edges, room walls, and the plan grid. The
canvas highlights the edge that will receive the snap. Use a fine step or `g!`
when you need an exact adjustment near a target.

## Move and align rooms

Press `m` to move a room in steps. Its furniture moves with it because
furniture positions are stored relative to the room.

Press `A` for exact alignment with another room. You can align outer edges or
centres, match corners, or place one room beside another with a gap.

Rooms may share an edge. This creates a shared wall. Positive area overlap is
invalid. **Allow invalid draft** exists for repair work, but validation still
reports the overlap and normal saving remains blocked.

## Duplicate and delete

Press `y` to copy the complete footprint. RoomPlan finds a free position for
the copy.

Press `d` to delete a room. The confirmation lists attached doors, windows,
outlets, and furniture that will also be removed. Undo restores the whole
change.

A doorway between two rooms is stored once against its owner room. Continue
with [Doors](doors.md).

← [Canvas](../workspace/canvas.md) | [Documentation home](../README.md) | [Doors](doors.md) →
