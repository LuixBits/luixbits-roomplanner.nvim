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
- Doors, wall windows, typed multi-slot wall/floor outlets, furniture
  catalogues, canvas detail levels, view rotation, compass, aspect calibration,
  semantic colours, and responsive workspace drawers. Wall outlets use
  view-aware inward-facing half circles; floor outlets use full circles and
  remain strictly inside their owner room.
- The complete `?` action window supports `/` search without changing the
  immediate one-key Add menu. Adjacent unshifted `,` and `.` keys zoom out and
  in for Swiss, compact, and ergonomic keyboards. Both remain configurable by
  semantic mapping name.
- Native packages, lazy.nvim, snacks, rocks, Nix flake, and nvf compatibility
  without optional integrations becoming hard dependencies.

Schema v1, v2, and v3 stay readable compatibility formats; schema v4 is the only
writer. Compound footprints are connected, hole-free unions of at most 256
axis-aligned rectangles. Angled walls and arbitrary polygons are deliberately
outside the current model.

## Next — compact contextual status

- Add one short selection breadcrumb, such as
  `Office › Floor outlet · Power · 2 slots`, to existing header/action-bar
  space; do not add another permanent pane or popup.
- Change the breadcrumb with selection and interaction mode so MOVE and RESIZE
  communicate their active object, axis/edge, step, and snap target without
  duplicating Details.
- Reuse presenter data and colorscheme-linked highlight groups, keeping narrow
  layouts to one clipped line and hiding the breadcrumb when nothing useful is
  selected.
- Cover wide, medium, and compact layouts before treating the slice as shipped.

## Then — extend compound authoring

- Reuse that interaction for placed furniture and project templates, including
  explicit anchor handling and catalogue round trips.
- Add further room/furniture presets only when they reduce common editing work
  without creating parallel geometry representations.

## Stable physical walls and openings

- Promote transient exterior/shared-boundary topology to reconciled persistent
  wall identity, representing each physical shared wall once.
- Give boundary runs stable IDs with deterministic reconciliation after room
  geometry changes; never persist array indexes or raster segments.
- Migrate door/window attachments from `room_id + part_id + side + offset` to
  persistent wall runs through a new sequential schema migration.
- Add vertical window metadata only when rendering or analysis consumes it.
  Wall thickness and materials wait for complete rendering, validation,
  clearance, and opening semantics.

## Analysis overlay framework

- Add a registry of pure analyses that emit semantic scene primitives,
  diagnostics, legends, and compact controls.
- Keep authored annotations separate from transient derived analysis.
- Add visibility, opacity, and focus without overloading the main workspace.
- Ship one complete measurement or clearance overlay before treating the
  framework as stable.

## Sunlight, circulation, and spatial studies

### Sun study

- Use geographic north plus user-supplied location, timezone, date, and time;
  never require network access or geolocation.
- Start with deterministic morning/noon/evening directions and a time slider.
  View rotation changes projection, never world north.
- Later project approximate light polygons through windows using modeled wall,
  sill, head, and obstacle heights.
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

- Equal-spacing constraints.
- Minimap drawer and named view presets.
- Undo-history drawer, grouping, locking, and layer visibility.
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
