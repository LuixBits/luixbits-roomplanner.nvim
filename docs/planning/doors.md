# Doors

RoomPlan stores one physical, single-leaf hinged door on a room footprint part.
A door belongs to one **owner room** and **owner part**, and may connect either
to one adjacent room or to outside. A shared doorway is stored once; rendering
cuts the matching wall segments for both rooms.

Press `D` or run `:RoomPlanAddDoor`. The form defines owner, footprint part,
north/east/south/west side, width, placement, hinge, connection, swing target,
and open angle from 1–180 degrees.

## Offsets and hinges

The offset is measured along the selected part side from its canonical start,
independent of screen rotation:

- horizontal north/south walls start at the west end;
- vertical east/west walls start at the south end.

`hinge = start` uses that endpoint of the aperture; `end` uses the other.
Placement can centre the opening on the side or canvas cursor, or use an exact
offset. The complete aperture must fit that part side and lie on the union's
exterior; an internal seam between footprint parts is not a wall opening.

## Connections and swing

The connection chooser includes only rooms whose opposite exterior boundary
can cover the complete aperture. A connected door can open into the owner or
connected room; an exterior door can open into the owner or outside. The
rendered arc is a planning aid derived from hinge, width, target, and angle.

Validation reports missing/invalid connections, obstructed exterior openings,
overlapping door/window apertures, and door sweeps intersecting walls,
furniture, or other doors. Swing intersections are warnings; broken
aperture/connection geometry is an error.

Select a door and press `e` to edit every property, `m` to slide it along its
wall, `y` to duplicate it with an explicit offset/width/hinge form, or `d` to
delete it. Moving a door never moves it off its assigned footprint part side.

← [Rooms](rooms.md) | [Documentation home](../README.md) | [Windows and outlets](windows-and-outlets.md) →
