# Rooms

RoomPlan v1 models a room as an axis-aligned rectangle with a stable ID, name,
southwest world origin, width, and depth. All coordinates and dimensions are
integer millimetres.

## Creating and editing

Press `a` and choose Room, or run `:RoomPlanAddRoom`. The form supports:

- automatic deterministic non-overlapping placement;
- world origin or the current canvas cursor;
- north, east, south, or west of another room, with an optional gap.

The first room defaults to `4000 × 3000 mm`. Automatic placement considers
existing rooms, the cursor, the plan grid, and the configured maximum search
distance. Edit a selected room with `e` to change its name, origin, width, and
depth atomically.

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

`y` duplicates a room and finds a non-overlapping placement. `d` deletes it;
doors owned by or connected to the room and furniture owned by it are
dependencies, so the confirmation summarizes the cascade. Undo restores the
entire semantic change as one step.

Doors are stored once against an owning room, even when they cut a shared
boundary. Continue with [Doors](doors.md).

← [Canvas](../workspace/canvas.md) | [Documentation home](../README.md) | [Doors](doors.md) →
