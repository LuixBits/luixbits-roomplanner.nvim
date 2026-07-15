# Limitations and roadmap

RoomPlan is a precise terminal floor-planning tool, not CAD/BIM software, a
construction drawing system, or a building-code checker.

## Current v1 boundaries

- one floor per plan;
- axis-aligned rectangular rooms;
- abstract zero-thickness walls;
- rectangular furniture with 0/90/180/270-degree rotation;
- single-leaf hinged doors;
- one canonical JSON schema version and optional Norg embedding;
- transient viewport zoom, pan, rotation, pane layout, filters, and collapsed
  sections;
- exact integer-millimetre geometry, not fractional millimetres;
- terminal-cell raster rendering, not freehand text editing.

The compass rotates RoomPlan's view only; Neovim windows and the physical
display cannot be rotated by a plugin. Furniture height is stored and shown,
but the canvas remains a top-down 2D footprint.

## Deliberately not represented

Wall thickness, wall assemblies, windows, stairs, plumbing/electrical layers,
curves, polygons, multi-leaf/sliding doors, manufacturer catalog semantics,
clearance/code compliance, dimensions suitable for construction, and
multi-user synchronization are outside schema v1. Configuration does not
pretend these fields work before the model, validation, storage, and UI can
support them coherently.

## Direction of future work

Likely extensions should arrive end-to-end: schema and migration when needed,
pure model and geometry, validation, scene/raster representation, structured
forms, fixtures, and recovery documentation.

The current implementation sequence is deliberately incremental:

1. palette-based room and furniture colors, with validation colors retaining
   visual priority (implemented);
2. wall and floor outlets with fast repeated placement;
3. a transient companion cat that uses canvas navigation and diagnostics but
   is never saved in the plan or undo history;
4. wall-anchored windows;
5. an approximate sunlight preview based on plan north, location, date, time,
   and windows.

Related UX candidates are layer toggles, recent furniture and colors,
duplicate-and-place-again actions, live placement previews, diagnostic object
focus, and clearance overlays. Longer-term candidates already on the roadmap
remain additional opening types, non-rectangular geometry, multiple floors,
richer annotations, and a stable tagged LuaRock release.

Sunlight work should begin with direction, elevation, and exposed walls. Indoor
ray previews depend on windows and remain explicitly approximate in a 2D plan.
The companion is view-only, pauses with the workspace, avoids spatial errors,
patrols outside warning regions, and may be sent away temporarily. Electrical
objects should start as a narrow outlet model rather than a speculative generic
fixture framework.

No candidate is a compatibility promise. The source of truth for shipped work
is the current documentation and tests; planned work belongs in the project
roadmap/changelog rather than dormant runtime flags or legacy branches.

When schema v2 is eventually necessary, v1 files must remain explicitly
loadable through a sequential migration with fixtures and recovery guidance.
Plugin version changes remain independent of schema versions.

← [Troubleshooting](troubleshooting.md) | [Documentation home](../README.md) | [Architecture](../development/architecture.md) →
