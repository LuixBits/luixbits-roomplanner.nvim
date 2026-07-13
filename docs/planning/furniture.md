# Furniture

Furniture is a rectangular room-local footprint with an explicit label,
category, width, depth, height, centre, and rotation. Supported rotations are
`0`, `90`, `180`, and `270` degrees.

Press `F` or run `:RoomPlanAddFurniture`. Choose a room and a built-in,
imported, or project template. Template values seed the label, category, and
dimensions, but the placed item stores its own values and can be customized
before applying.

Placement choices are room centre, canvas cursor, or exact room-local
coordinates. Room-local `(0, 0)` is the room's southwest corner; a furniture
centre is translated into world coordinates only for validation and rendering.
An item must remain inside its owning room and must not overlap another
furniture footprint.

Select furniture and use:

- `e` to edit room, template, label, dimensions, centre, and rotation;
- `m` plus directions to move by the configured plan steps;
- `r` to rotate one quarter-turn;
- `y` to duplicate it;
- `d` to delete it.

Movement and rotation are semantic actions with undo/redo and validation.
Snapping can target room edges/centres, doors, furniture, and grid according
to the configured priority.

## Project templates

Enable **Save as project template** while adding furniture to create a
`custom:*` template with the current dimensions. Project templates are saved
inside that plan, appear as top-level Objects rows, and can be edited with
`e`. Existing placed furniture keeps explicit dimensions when its template is
edited.

For reusable personal or team defaults that should not be copied into every
plan, use [Furniture catalogues](furniture-catalogs.md).

← [Doors](doors.md) | [Documentation home](../README.md) | [Furniture catalogues](furniture-catalogs.md) →
