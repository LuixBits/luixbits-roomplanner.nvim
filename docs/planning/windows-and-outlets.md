# Windows and outlets

Windows are openings in walls. Outlets are point markers on a wall or floor.
Every window and outlet belongs to a room.

## Common actions

| Key | Action |
| --- | --- |
| `W` | Add a window |
| `O` | Add an outlet |
| `e` | Edit the selected window or outlet |
| `m` | Move it along its wall or across the floor |
| `y` | Duplicate it |
| `d` | Delete it |

The Add menu also includes both objects. Press `a`, then `w` for a window or
`o` for an outlet. You can also run `:RoomPlanAddWindow` or
`:RoomPlanAddOutlet`.

Windows and wall outlets move along their assigned wall. Floor outlets move in
room local coordinates. All changes support validation and undo.

## Wall placement

A wall feature is attached to one stable footprint section and side. The UI
shows that side as top, right, bottom, or left for the current view. Rotating
the view does not change the stored attachment.

Offsets follow a stable plan convention:

- North and south sides start at their west end.
- East and west sides start at their south end.

The selected position must be on the room's exterior wall. An internal seam
between footprint sections cannot hold a window or wall outlet.

## Windows

A window needs a positive width. Its full opening must fit on the selected
wall. It can face outside or connect to another room whose opposite wall covers
the opening.

One connected window cuts the matching wall of both rooms. An invalid
connection does not cut the claimed room. Windows do not have a leaf or swing.

Each window can use the plan's default sill and head heights or store its own
pair. Both values are required together, and the head must be above the sill.
These heights are used by the [Sun study](sun-study.md).

## Outlets

A wall outlet must sit inside an exterior wall edge. Corners are rejected
because they do not have one clear owning wall.

A floor outlet can start at the room centre, at the canvas cursor, or at exact
local coordinates. It must be inside the room and not on a wall. It moves with
the room.

Supported outlet types are power, USB, Ethernet, coax, phone, and other. The
slot count can be from 1 to 32. Outlets never cut a wall.

## Canvas symbols

Windows appear as a double line or a `W` at small scale. Floor outlets use a
circle. Wall outlets use a half circle whose filled side points into the room.
ASCII mode uses simpler equivalents.

## Current limits

These are 2D planning objects. Window heights currently affect only the
approximate sunlight patch. RoomPlan does not represent glazing, opening
style, wall thickness, or outlet mounting height.

The stored fields and coordinate rules are documented in
[Coordinates and schema](../data/coordinates-and-schema.md). See
[Limitations and roadmap](../reference/limitations-and-roadmap.md) for planned
work.

← [Doors](doors.md) | [Documentation home](../README.md) | [Furniture](furniture.md) →
