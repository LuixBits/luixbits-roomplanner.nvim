# RoomPlan roadmap

This file records the stable baseline and the remaining implementation route.
Detailed shipped behaviour is documented under [`docs/`](docs/README.md), while
completed release history belongs in [`CHANGELOG.md`](CHANGELOG.md).

## Shipped baseline

- Schema v4 writing with explicit, non-destructive v1 → v2 → v3 → v4
  migration. Schema v4 distinguishes exterior-wall outlets from room-local
  floor outlets without introducing a second geometry authority.
- Exact pure-Lua rectangular-union geometry for compound rooms, furniture, and
  templates, including stable part IDs, bounds, area, perimeter, containment,
  snapping, hit provenance, rendering, and validation.
- Rectangular and configurable L-shaped room authoring, exact property editing,
  a responsive side preview, and direct canvas resizing that adds, resizes, or
  removes compound sections as one undoable room change. Ordinary movement
  carries room furniture with it and shares resize snapping feedback; named
  alignment guides and a highlighted overlap expose each connection without
  trapping fine-step movement. Direction-selected resize edges and visible-cell
  normal movement with explicit distance feedback keep terminal interaction
  coherent at every zoom. Guide tails expose both horizontal and vertical snaps.
- A compact colorscheme-linked selection breadcrumb shares the existing action
  bar instead of adding another pane. It identifies room ownership and object
  type, then adds active object, direction, distance, edge, section, and snap
  target feedback during MOVE and RESIZE without displacing existing actions.
- Doors, wall windows, typed multi-slot wall/floor outlets, furniture
  catalogues, canvas detail levels, view rotation, compass, aspect calibration,
  semantic colours, and responsive workspace drawers. Wall outlets use
  view-aware inward-facing half circles; floor outlets use full circles and
  remain strictly inside their owner room.
- Rooms, placed furniture, and project templates reach the shared direct
  compound-section editor from **Edit footprint** in their ordinary `e`
  popup or directly with `r`; `R` rotates furniture. Quarter-turned
  furniture movement and snapping operate in world space; templates use an
  isolated local preview. Explicit doubled-mm anchors stay fixed. A compact
  popup chooses item-only or item-plus-template scope, commits one undo step,
  and never silently rewrites other placed items. Saved project catalogues
  round-trip the edited default for future placements.
- The complete `?` action window has an in-popup `/` search row that filters
  actions after every character without changing the immediate one-key Add
  menu. Adjacent unshifted `,` and `.` keys zoom out and in for Swiss, compact,
  and ergonomic keyboards. Both remain configurable by semantic mapping name.
- Native packages, lazy.nvim, snacks, rocks, Nix flake, and nvf compatibility
  without optional integrations becoming hard dependencies.
- Exact silhouette snapping and resize feedback retain every simultaneous
  positive-length wall contact. The existing fine step becomes a bounded
  deep-zoom magnetic floor, removing tiny millimetre residuals without another
  configuration key.
- Popup-first wall placement and exact two-object measurement, Navigator
  marking with atomic batch move/duplicate/delete, and a named retained-history
  browser with confirmed revision restore.
- Offline sunlight study with one exact persisted site/north authority,
  top/right/bottom/left screen labels, optional per-window sill/head pairs,
  configurable assumed heights, clear-sky solar angles, exposed-wall/window
  emphasis, elevation-aware floor gradients, reliable whole-day playback,
  three-month comparison controls, and fixed-band daily exposure. Study
  date/time/playback/analysis remains transient and closes with its timer.

Schema v1, v2, and v3 stay readable compatibility formats; schema v4 is the only
writer. Compound footprints are connected, hole-free unions of at most 256
axis-aligned rectangles. Angled walls and arbitrary polygons are deliberately
outside the current model.

## Next — stable physical walls and openings

- Promote transient exterior/shared-boundary topology to reconciled persistent
  wall identity, representing each physical shared wall once.
- Give boundary runs stable IDs with deterministic reconciliation after room
  geometry changes; never persist array indexes or raster segments.
- Migrate door/window attachments from `room_id + part_id + side + offset` to
  persistent wall runs through a new sequential schema migration.
- Carry the shipped sill/head pair through any future stable wall migration.
  Wall thickness and materials wait for complete rendering, validation,
  clearance, and opening semantics.

## Analysis overlay framework

- Add a registry of pure analyses that emit semantic scene primitives,
  diagnostics, legends, and compact controls.
- Keep authored annotations separate from transient derived analysis.
- Add visibility, opacity, and focus without overloading the main workspace.
- Generalize the shipped exact measurement path into reusable overlay controls
  before treating the analysis framework as stable.

## Sunlight, circulation, and spatial studies

### Sun study

- Extend the shipped deterministic offline study only where the main canvas
  benefits: reusable overlay controls, wall thickness/overhangs, and
  furniture-height or explicit-obstacle shadows. The first fixed-band daily
  exposure legend and seasonal comparison controls are shipped.
- Keep view rotation as projection only and retain one exact persisted
  geographic-north/site authority.
- Label results as approximate 2D exposure, not illuminance, thermal,
  construction, or building-code analysis.

### Circulation and clearance

- Derive walkable room space minus furniture and obstacles, with doors as
  portals.
- Show reachability, selected-point routes, configurable-width bottlenecks,
  door swings, furniture clearance envelopes, and accessibility aids.
- Keep results advisory rather than code certification or automatic layout
  optimization.

## UI/UX backlog

- Further room/furniture presets only when they reduce common editing work
  without creating parallel geometry representations.
- Minimap drawer and named view presets.
- History grouping, locking, and layer visibility.
- Line-of-sight, window-view, robot-vacuum reachability, and egress studies.
- SVG export after compound silhouettes and annotations are stable. DXF and
  multi-floor planning remain separately scoped later projects.

## Acceptance gate

- No loss of commands, APIs, keymaps, save/load, undo, rendering, or supported
  package-manager compatibility.
- Every slice covers pure model/geometry, schema where necessary, validation,
  actions, UI, fixtures, documentation, and recovery behaviour.
- Full non-Nix tests, smoke checks, and `git diff --check` pass locally. Flake
  checks run in CI or only when explicitly requested; never invoke `nix build`
  directly.
- No dormant settings, speculative aliases, duplicate geometry authorities,
  or parallel legacy implementation paths.
