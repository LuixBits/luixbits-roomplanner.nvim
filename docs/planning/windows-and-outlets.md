# Windows and outlets

Schema v3 adds two wall-attached object types: windows are linear openings and
outlets are point markers. Both belong to one room footprint part and one of
its north, east, south, or west sides.

## Add and interact

- Press `W` or run `:RoomPlanAddWindow` to add a window.
- Press `O` or run `:RoomPlanAddOutlet` to add an outlet.
- The Add palette also offers them: press `a`, then `w` for Window or `o` for
  Outlet.

Windows and outlets appear beneath their owner room in Objects. Select either
type and use `e` to edit, `m` plus a direction to move it along its assigned
wall, `y` to duplicate it, or `d` to delete it. These are ordinary semantic
actions with validation and undo/redo.

## Wall coordinates

Offsets use the same stable world-relative convention as doors:

- north/south part sides start at their west end;
- east/west part sides start at their south end.

The chosen interval or point must lie on the room union's exterior. An internal
seam between footprint parts is not an attachable wall. Screen rotation never
changes the stored part, side, or offset.

## Canvas shapes

At normal scale a Unicode window uses `═` or `║` along its aperture; a window
that projects to one cell uses `W`. ASCII uses `=`/`|` and the same `W` marker.
An outlet is `○` in Unicode and `O` in ASCII. Semantic Window and Outlet
highlights keep these shapes distinct from structural walls.

## Windows

A window has a positive `width_mm`. Its complete aperture must fit the selected
part side. `connects_to_room_id` is either `null` for an outside-facing window
or the ID of a room whose opposite wall covers the complete aperture.

A valid window cuts its owner wall. A verified room connection also cuts the
matching connected-room contribution, so one stored window represents one
shared opening. Invalid owner-aperture geometry never cuts a wall, and an
invalid connection never punches through the claimed connected room. Windows
have no door leaf or swing.

```json
{
  "id": "window-living-north",
  "room_id": "room-living",
  "connects_to_room_id": null,
  "part_id": "part-main",
  "side": "north",
  "offset_mm": 700,
  "width_mm": 1400
}
```

## Outlets

An outlet is a point on a wall and never cuts the wall. The supported
`outlet_type` values are `power`, `usb`, `ethernet`, `coax`, `phone`, and
`other`; `slots` is an integer from 1 through 32.

The offset must be strictly inside the selected exterior edge. Endpoints are
rejected because a corner or compound-part boundary has no unambiguous owning
wall.

```json
{
  "id": "outlet-office-east-data",
  "room_id": "room-office",
  "part_id": "part-main",
  "side": "east",
  "offset_mm": 1200,
  "outlet_type": "ethernet",
  "slots": 2
}
```

## Current 2D limits

These are top-down planning objects. Windows do not yet store sill height,
opening height, head height, glazing, or opening style; outlets do not store a
mounting height. See [Limitations and roadmap](../reference/limitations-and-roadmap.md).

← [Doors](doors.md) | [Documentation home](../README.md) | [Furniture](furniture.md) →
