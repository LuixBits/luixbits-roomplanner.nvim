# Rooms

RoomPlan models a room as one logical footprint made from a connected union of
axis-aligned rectangular parts. The room has a stable ID, name, and world
origin; every part has a stable local ID, origin, width, and depth in integer
millimetres. Internal part seams are removed from the rendered wall silhouette.

## Creating and editing

Press `a` and choose Room, or run `:RoomPlanAddRoom`. The form supports:

- rectangular or L-shaped footprints;
- overall width/depth and, for an L, both leg dimensions and the missing corner;
- automatic deterministic non-overlapping placement;
- world origin or the current canvas cursor;
- north, east, south, or west of another room, with an optional gap.

The first room defaults to a one-part `4000 × 3000 mm` rectangle. Automatic
placement considers existing rooms, the cursor, the plan grid, and the
configured maximum search distance. Rectangle edits can change name, origin,
width, and depth atomically.

An L-shaped room is stored as two connected parts with no internal wall seam.
Its overall dimensions, leg dimensions, and missing corner can be edited in the
ordinary room form. RoomPlan keeps the preset's stable part IDs while applying
the complete geometry change atomically. The form shows the number of attached
wall features and furniture; an edit that would invalidate one is rejected
without changing the plan. Other compound shapes expose each rectangular
section's width and depth while preserving its position, stable ID, and unknown
extension data.

Select a room and press `e` for this compact form. On a wide editor, a live
shape preview opens in a separate panel to its right. On a narrow editor the
preview is omitted so the fields and command footer remain visible. The editor
does not expose internal part coordinates or approximate angled walls with tiny
rectangles. **Edit footprint** opens the direct canvas section controls; `r`
is a shortcut to the same controls when no scalar property edit is needed.

### Direct canvas resizing

Activate **Edit footprint** from the room's `e` popup, or select a room and press
`r` as a shortcut. Its first section is highlighted on the canvas and the
workspace enters `RESIZE`.

| Key | Shape action |
| --- | --- |
| `Enter` | Select the section under the cursor |
| `Tab` / `Shift-Tab` | Select the next / previous section |
| `h j k l` | Resize it by the normal plan step |
| `H J K L` | Resize it by the coarse plan step |
| `Ctrl-h/j/k/l` | Resize it by the fine plan step |
| `a` | Add a same-sized section beside the selection, preferring the cursor-facing side |
| `d` | Remove the selected section |
| `gs` / `g!` | Toggle snapping / bypass it for the next change |
| `s` | Apply the complete shape as one undo step and save the plan |
| `Esc` | Cancel the complete shape edit |

The first horizontal direction chooses the section's west (`h`) or east (`l`)
edge; the first vertical direction chooses south (`j`) or north (`k`). Further
keys on that axis move the chosen edge inward or outward, so the opposite key
shrinks it. The chosen edge is shown in the header and stays active until you
select another section. If the first attempted movement would break topology,
RoomPlan still selects that edge without applying the invalid geometry.

Every preview must remain a connected, hole-free, non-overlapping rectangular
union. Invalid resizes are rejected immediately. A section referenced
by a door, window, or outlet cannot be removed until that wall feature is moved
or deleted. The edit remains transient until `s`; cancelling does not
change history or saved data. The result is still one logical room, not a group
of separately selectable rectangles.

The canvas header and action bar show **RESIZE**, the selected section number,
and the active edge. With snapping enabled, the changed edge snaps first
to neighbouring section edges or another room's exterior walls, then to the
plan grid when no structural edge is close enough. A light alignment guide,
text such as `X → Kitchen west wall`, and a heavy highlighted segment on
the actual edge overlap identify the target. Guides are transient and disappear
after selection or mode changes. Moving away releases the snap immediately;
fine steps are not pulled back to the same target.

When a room is selected, Details reports its compact bounding width and depth,
exact union area and perimeter, and part count.

## Moving and alignment

Select a room and press `m` for incremental movement. Press `A` for exact
alignment against a fixed reference room. Supported operations align left,
right, north, south, horizontal centre, or vertical centre; place on any side
with a gap; or snap any pair of corners. If a centre alignment falls between
millimetres, the proposal is deterministically rounded to the integer-mm
lattice and reports that fact.

Moving uses the same light guide, target status, and highlighted overlap as
resizing. The guide has a short support tail beyond the aligned walls, so
north/south connections remain as obvious as east/west connections. Moving
changes the room's world origin. Furniture keeps its room-local
coordinates, so it travels with the room exactly as it does during ordinary
room movement; there is no separate section-move mode inside `RESIZE`.

Rooms may touch along an edge, which is how shared walls are formed. Positive
area overlap is an error. `Allow invalid draft` permits a deliberate overlap
for repair, but validation and normal saving continue to report/block it.

## Duplication and deletion

`y` duplicates a room's complete footprint and finds a non-overlapping
placement. `d` deletes it; doors/windows owned by or connected to the room,
plus outlets and furniture owned by it, are dependencies, so the confirmation
summarizes the cascade. Undo restores the entire semantic change as one step.

Doors are stored once against an owning room, even when they cut a shared
boundary. Continue with [Doors](doors.md).

← [Canvas](../workspace/canvas.md) | [Documentation home](../README.md) | [Doors](doors.md) →
