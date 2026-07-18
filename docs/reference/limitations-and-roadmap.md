# Limitations and roadmap

RoomPlan is a precise terminal floor-planning tool, not CAD/BIM software, a
construction drawing system, or a building-code checker.

## Current schema-v4 boundaries

- one floor per plan;
- connected, hole-free unions of at most 256 axis-aligned rectangular parts
  for rooms and furniture;
- abstract zero-thickness walls;
- furniture with 0/90/180/270-degree rotation;
- single-leaf hinged doors;
- wall-aligned windows with width and optional adjacent-room connection;
- wall and floor point outlets with a type and 1–32 slots;
- schema-v4 JSON writing, sequential schema-v1/v2/v3 migration, and optional Norg
  embedding;
- transient viewport zoom, pan, rotation, pane layout, filters, and collapsed
  sections;
- integer-mm authored parts with exact doubled-mm furniture anchors;
- terminal-cell raster rendering, not freehand text editing.

The compass rotates RoomPlan's view only; Neovim windows and the physical
display cannot be rotated by a plugin. Furniture height is stored and shown,
but the canvas remains a top-down 2D footprint.

The room form creates rectangles and configurable two-part L shapes; direct
canvas resizing can also add, resize, and remove rectangular sections while
preserving valid union topology. The furniture form currently creates
one-part rectangles. Placed furniture can use the direct canvas section editor
from the full action popup while preserving its explicit anchor through every
quarter turn. Project templates use the same editor in an isolated local
preview. A placed item that references a project template chooses item-only or
item-plus-template scope in a popup; other placed items are never implicitly
rewritten. Rectangle-only form resizing remains disabled for compound or
custom-anchor objects.

## Deliberately not represented

Wall thickness, wall assemblies, window sill/head/opening heights, glazing and
opening styles, outlet mounting heights and circuits, stairs, plumbing or full
electrical layers, curves, arbitrary polygons, multi-leaf/sliding doors,
manufacturer catalog semantics, clearance/code compliance, dimensions suitable
for construction, and multi-user synchronization are outside schema v4.
Configuration does not pretend these fields work before the model, validation,
storage, and UI can support them coherently.

## Direction of future work

Likely extensions should arrive end-to-end: schema and migration when needed,
pure model and geometry, validation, scene/raster representation, structured
forms, fixtures, and recovery documentation.

Palette-based room and furniture colors, compound footprints, wall-anchored
windows, wall outlets, and the contextual selection/MOVE/RESIZE breadcrumb are
implemented. Likely next candidates include a transient companion cat that is
never saved in the plan or undo history, and an approximate sunlight preview
based on plan north, location, date, time, and windows.

Related UX candidates are layer toggles, recent furniture and colors,
duplicate-and-place-again actions, live placement previews, diagnostic object
focus, and clearance overlays. Longer-term candidates already on the roadmap
remain additional opening types, stable physical wall construction, vertical
wall-feature data, multiple floors, richer annotations, and a stable tagged
LuaRock release.

Sunlight work should begin with direction, elevation, and exposed walls. Indoor
ray previews depend on windows and remain explicitly approximate in a 2D plan.
The companion is view-only, pauses with the workspace, avoids spatial errors,
patrols outside warning regions, and may be sent away temporarily.

No candidate is a compatibility promise. The source of truth for shipped work
is the current documentation and tests; planned work belongs in the project
[`plan.md`](../../plan.md) roadmap rather than dormant runtime flags or legacy
branches.

Schema v1, v2, and v3 remain explicitly loadable through tested sequential
migrations. Loading does not rewrite the source; the migrated session requires
an explicit save before schema-v4 bytes replace it. Plugin version
changes remain independent of schema versions.

← [Troubleshooting](troubleshooting.md) | [Documentation home](../README.md) | [Architecture](../development/architecture.md) →
