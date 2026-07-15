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
without changing the plan. Unknown or free-form compound shapes remain geometry-read-only
until the general part editor can preserve every authored detail safely.

When a room is selected, Details reports its compact bounding width and depth,
exact union area and perimeter, and part count.

## Moving and alignment

Select a room and press `m` for incremental movement. Press `A` for exact
alignment against a fixed reference room. Supported operations align left,
right, north, south, horizontal centre, or vertical centre; place on any side
with a gap; or snap any pair of corners. If a centre alignment falls between
millimetres, the proposal is deterministically rounded to the integer-mm
lattice and reports that fact.

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
