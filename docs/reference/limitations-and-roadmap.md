# Limitations and roadmap

RoomPlan is a terminal space planning tool. It is not CAD, BIM, a construction
drawing system, or a building code checker.

## Current scope

| Area | Current support |
| --- | --- |
| Plans | One floor per plan |
| Rooms and furniture | Connected shapes with up to 256 rectangular sections |
| Walls | Abstract boundaries with no thickness |
| Furniture rotation | 0, 90, 180, or 270 degrees |
| Doors | Single leaf hinged doors |
| Windows | Wall openings with optional room connection and height pair |
| Outlets | Typed wall or floor points with 1 to 32 slots |
| Storage | Schema v4 JSON, older schema migration, and optional Norg embedding |
| Canvas | Terminal cell rendering with temporary zoom, pan, and view rotation |

Measurements use whole millimetres. Furniture anchors can represent exact
half millimetre centres for odd sized objects. The Canvas is a view of this
data and is not a freehand text editor.

Room forms create rectangles and configurable L shapes. The direct footprint
editor can add, resize, and remove sections for rooms, placed furniture, and
project templates. Compound shapes must stay connected and free of holes or
overlaps.

Furniture forms create rectangular items. Loaded compound furniture remains
editable through the direct footprint editor. Updating a project template does
not rewrite existing items unless the selected item uses the explicit combined
save scope.

## Not represented

RoomPlan does not currently model:

- Wall thickness, assemblies, or materials.
- Glazing and window opening styles.
- Outlet height, circuits, or full electrical layers.
- Stairs, plumbing, curves, or arbitrary polygons.
- Sliding or multiple leaf doors.
- Construction dimensions or code compliance.
- Several floors or live multiuser editing.

Furniture height is stored and shown, but the Canvas remains a top view.
Geographic north is stored for sun study. Rotating the view does not rotate
saved geometry or Neovim windows.

## Planned work

The immediate goal is compatibility hardening and the first tagged release.
This includes the full supported Neovim matrix, package checks, manual smoke
tests, and an accurate screenshot or recording.

The next product milestone is a temporary circulation and clearance overlay.
It should show walkable space, furniture clearance, door swings, unreachable
areas, and narrow passages. The results will be advisory and will not certify
building codes.

Likely followups include:

- Reusable controls for analysis overlays.
- Furniture height shadows in sun study.
- SVG export.
- Useful layer visibility controls.
- Recent choices or duplicate and place again workflows.

Longer term candidates include more opening types, stable physical wall
identity, vertical wall data, multiple floors, richer annotations, and more
construction detail.

The sun study remains an approximate clear sky 2D analysis. Possible additions
include overhangs, wall thickness, and obstacle shadows. It will not be
presented as illuminance, thermal analysis, or a construction simulation.

## Compatibility

Schema v1, v2, and v3 remain readable through tested migrations. Schema v4 is
the only writer. Opening an older plan does not rewrite it. An explicit save is
required before the migrated data replaces the source.

Plugin releases and schema versions are independent. Planned features are not
compatibility promises. Shipped behaviour is defined by the current code,
tests, and documentation.

The detailed and canonical product roadmap is [`plan.md`](../../plan.md).

← [Troubleshooting](troubleshooting.md) | [Documentation home](../README.md) | [Architecture](../development/architecture.md) →
