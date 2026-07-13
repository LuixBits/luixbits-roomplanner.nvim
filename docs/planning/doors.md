# Doors

Schema v1 supports one physical, single-leaf hinged door on a room wall. A
door belongs to one **owner room** and may connect either to one adjacent room
or to outside. A shared doorway is stored once; rendering cuts the matching
wall segments for both rooms.

Press `D` or run `:RoomPlanAddDoor`. The form defines owner, north/east/south/
west wall, width, placement, hinge, connection, swing target, and open angle
from 1–180 degrees.

## Offsets and hinges

The offset is measured from the wall's canonical start, independent of screen
rotation:

- horizontal north/south walls start at the west end;
- vertical east/west walls start at the south end.

`hinge = start` uses that endpoint of the aperture; `end` uses the other.
Placement can centre the opening on the wall or canvas cursor, or use an exact
offset. The complete aperture must fit the owner edge.

## Connections and swing

The connection chooser includes only rooms whose opposite boundary can cover
the complete aperture. A connected door can open into the owner or connected
room; an exterior door can open into the owner or outside. The rendered arc is
a planning aid derived from hinge, width, target, and angle.

Validation reports missing/invalid connections, obstructed exterior openings,
overlapping apertures, and door sweeps intersecting walls, furniture, or other
doors. Swing intersections are warnings; broken aperture/connection geometry
is an error.

Select a door and press `e` to edit every property, `m` to slide it along its
wall, `y` to duplicate it with an explicit offset/width/hinge form, or `d` to
delete it. Moving a door never moves it off its assigned wall.

← [Rooms](rooms.md) | [Documentation home](../README.md) | [Furniture](furniture.md) →
