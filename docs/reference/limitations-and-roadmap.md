# Limitations and roadmap

RoomPlan is a precise terminal floor-planning tool, not CAD/BIM software, a
construction drawing system, or a building-code checker.

## Current schema-v3 boundaries

- one floor per plan;
- connected, hole-free unions of at most 256 axis-aligned rectangular parts
  for rooms and furniture;
- abstract zero-thickness walls;
- furniture with 0/90/180/270-degree rotation;
- single-leaf hinged doors;
- wall-aligned windows with width and optional adjacent-room connection;
- point outlets with a type and 1–32 slots;
- schema-v3 JSON writing, sequential schema-v1/v2 migration, and optional Norg
  embedding;
- transient viewport zoom, pan, rotation, pane layout, filters, and collapsed
  sections;
- integer-mm authored parts with exact doubled-mm furniture anchors;
- terminal-cell raster rendering, not freehand text editing.

The compass rotates RoomPlan's view only; Neovim windows and the physical
display cannot be rotated by a plugin. Furniture height is stored and shown,
but the canvas remains a top-down 2D footprint.

The room form creates rectangles and configurable two-part L shapes; the
furniture form currently creates one-part rectangles. Canonical L shapes keep
their part IDs while their overall size, legs, and missing corner are edited.
Other compound objects loaded from schema-v3 JSON are preserved across
supported operations, but free-form part editing awaits the compound editor.
Rectangle-only resize actions are disabled for such objects.

## Deliberately not represented

Wall thickness, wall assemblies, window sill/head/opening heights, glazing and
opening styles, outlet mounting heights and circuits, stairs, plumbing or full
electrical layers, curves, arbitrary polygons, multi-leaf/sliding doors,
manufacturer catalog semantics, clearance/code compliance, dimensions suitable
for construction, and multi-user synchronization are outside schema v3.
Configuration does not pretend these fields work before the model, validation,
storage, and UI can support them coherently.

## Direction of future work

Likely extensions should arrive end-to-end: schema and migration, pure model
and geometry, validation, scene/raster representation, structured forms,
fixtures, and recovery documentation. Candidates include additional opening
types, stable physical wall construction, vertical wall-feature data, multiple
floors, richer annotations, and a stable tagged LuaRock release.

No candidate is a compatibility promise. The source of truth for shipped work
is the current documentation and tests; planned work belongs in the project
[`plan.md`](../../plan.md) roadmap rather than dormant runtime flags or legacy
branches.

Schema v1 and v2 remain explicitly loadable through tested sequential
migrations. Loading does not rewrite either source; the migrated session
requires an explicit save before schema-v3 bytes replace it. Plugin version
changes remain independent of schema versions.

← [Troubleshooting](troubleshooting.md) | [Documentation home](../README.md) | [Architecture](../development/architecture.md) →
