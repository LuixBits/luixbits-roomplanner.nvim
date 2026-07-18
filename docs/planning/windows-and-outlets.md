# Windows and outlets

Schema v4 models windows as linear wall openings and outlets as wall- or
floor-mounted point markers. Every object belongs to a room. A wall feature
also belongs to one footprint part and one stable plan-coordinate side; the UI
names it top, right, bottom, or left for the current view. A floor outlet stores
a room-local point instead.

## Add and interact

- Press `W` or run `:RoomPlanAddWindow` to add a window.
- Press `O` or run `:RoomPlanAddOutlet` to add an outlet.
- The Add menu also offers them: press `a`, then `w` for Window or `o` for
  Outlet.

Windows and outlets appear beneath their owner room in Objects. Select either
type and use `e` to edit, `m` plus a direction to move it, `y` to duplicate it,
or `d` to delete it. Windows and wall outlets move along their assigned wall;
floor outlets move in room-local X/Y. These are ordinary semantic actions with
validation and undo/redo.

## Wall coordinates

Offsets use the same stable world-relative convention as doors:

- north/south part sides start at their west end;
- east/west part sides start at their south end.

The chosen interval or point must lie on the room union's exterior. An internal
seam between footprint parts is not an attachable wall. Screen rotation never
changes the stored part, side, or offset.

## Floor coordinates

A floor outlet stores `position_mm` relative to its owner room. It must be
strictly inside the room union, not on a wall or internal seam. The form can
start it at the room centre, at the canvas cursor, or at an exact local point.
Because its position is room-local, it travels with the room.

## Canvas shapes

At normal scale a Unicode window uses `═` or `║` along its aperture; a window
that projects to one cell uses `W`. ASCII uses `=`/`|` and the same `W` marker.
A floor outlet is `○` in Unicode and `O` in ASCII. A wall outlet is a
half-circle whose filled side points into its room; it rotates with the view.
ASCII uses the equivalent inward-pointing `^`, `>`, `v`, or `<`. Semantic
Window and Outlet highlights keep these shapes distinct from structural walls.

## Windows

A window has a positive `width_mm`. Its complete aperture must fit the selected
part side. `connects_to_room_id` is either `null` for an outside-facing window
or the ID of a room whose opposite wall covers the complete aperture.

A valid window cuts its owner wall. A verified room connection also cuts the
matching connected-room contribution, so one stored window represents one
shared opening. Invalid owner-aperture geometry never cuts a wall, and an
invalid connection never punches through the claimed connected room. Windows
have no door leaf or swing.

For sunlight, a window may also store `sill_height_mm` and `head_height_mm` as
one optional pair. The edit popup switches between explicit heights and the
configured plan defaults. The pair is required together, and head must be
higher than sill. Defaults stay in setup instead of creating redundant keys on
every window. See [Sun study](sun-study.md).

```json
{
  "id": "window-living-north",
  "room_id": "room-living",
  "connects_to_room_id": null,
  "part_id": "part-main",
  "side": "north",
  "offset_mm": 700,
  "width_mm": 1400,
  "sill_height_mm": 900,
  "head_height_mm": 2100
}
```

## Outlets

An outlet is a point marker and never cuts a wall. The supported
`outlet_type` values are `power`, `usb`, `ethernet`, `coax`, `phone`, and
`other`; `slots` is an integer from 1 through 32.

For wall placement, the offset must be strictly inside the selected exterior
edge. Endpoints are rejected because a corner or compound-part boundary has no
unambiguous owning wall.

```json
{
  "id": "outlet-office-east-data",
  "placement": "wall",
  "room_id": "room-office",
  "part_id": "part-main",
  "side": "east",
  "offset_mm": 1200,
  "outlet_type": "ethernet",
  "slots": 2
}
```

Floor placement uses mutually exclusive room-local coordinates:

```json
{
  "id": "outlet-office-floor-power",
  "placement": "floor",
  "room_id": "room-office",
  "position_mm": [1800, 1200],
  "outlet_type": "power",
  "slots": 2
}
```

## Current 2D limits

These remain top-down planning objects. Window sill/head height currently feeds
only the approximate sunlight patch; glazing, opening style, wall thickness,
and outlet mounting height are not represented. See
[Limitations and roadmap](../reference/limitations-and-roadmap.md).

← [Doors](doors.md) | [Documentation home](../README.md) | [Furniture](furniture.md) →
