# RoomPlan roadmap

This is the forward implementation plan. Current, shipped behaviour remains
documented under [`docs/`](docs/README.md); unchecked work below is not a
compatibility promise or a hidden runtime feature.

## Baseline and delivery rules

- Schema v3 is the active writer. Schema v1 and v2 remain readable through
  tested sequential migrations; loading never rewrites source bytes, and a
  migrated model requires an explicit save before it becomes durable.
- Geometry stays pure Lua, deterministic, and exact. Doubled millimetres are
  used internally where centred odd-sized objects create half-millimetre edges.
- Each phase must cover model/schema, validation, actions, rendering, UI,
  fixtures, documentation, and recovery behaviour before it is called shipped.
- New behaviour must remain usable with native packages, lazy.nvim, snacks,
  rocks, Nix flakes, and nvf; optional integrations must not become hard
  dependencies.
- No dormant settings, speculative compatibility aliases, or parallel legacy
  paths. View rotation, compass, aspect calibration, semantic highlighting,
  and responsive drawers are already part of the baseline.

## Phase 1 — Shared footprint foundation

Outcome: one shared runtime footprint boundary owns object bounds,
containment/overlap, snapping features, and scene interiors. It represents each
current room and furniture item as a one-part `rect_union` without changing
schema v1 or its encoded JSON.

- [x] Add a runtime-only footprint type with non-overlapping axis-aligned parts.
- [x] Keep exact doubled-mm bounds and pure translate/quarter-turn operations.
- [x] Adapt v1 rooms and placed furniture into one-part world footprints.
- [x] Route validation, snapping, and semantic scene extraction through it.
- [x] Keep `geometry.rect` as a compatible rectangle facade.
- [x] Prove unchanged v1 encoding, odd-size furniture parity, rotations,
  containment, boundary contact, diagnostics, and render output with tests.
- [x] Pass the complete test suite and plugin flake checks.

Stage boundary: this phase does **not** interpret compound data from JSON as
active geometry and does not add `footprint` members to persisted model
objects. As with any unknown schema-v1 member, a foreign `footprint` key is
preserved losslessly. Rectangle-specific wall, door, label, and room-alignment
topology remains v1 until its explicit compound phase below.

## Phase 2 — Compound geometry and schema v2

Outcome: rooms and furniture can be connected unions of rectangular parts,
covering L-, T-, and U-shaped rooms, sectional sofas, corner desks, counters,
and similar objects.

### 2A — Pure compound kernel

- [x] Preserve object-local frames and authored object-local `part-*` IDs
  without sorting, merging, renaming, or rebasing parts.
- [x] Make `compound()` enforce the persistable topology: positive dimensions,
  unique IDs, no positive-area overlap, one positive-edge-connected component,
  bounded part count, and no enclosed holes. General normalized/derived unions
  may remain ID-less or disconnected, as intersections can produce both.
- [x] Add aggregate-range-checked union area and perimeter, containment, complete
  intersection, connectivity, seam-free boundary, interior label anchor,
  part-level hit provenance, translation, quarter turns, and frame transforms.
- [x] Keep schema-v1 adapters and all existing one-part behavior passing while
  compound persistence remains disabled.

Stage boundary: this kernel is usable by later layers, but schema v1 remains
the only writable format. A schema-v1 `footprint` member remains preserved
unknown data and is not interpreted as active geometry.

### 2B — Single-authority schema v2 and migration

- [x] Split the schema implementation into a small version dispatcher, shared
  primitives, explicit v1/v2 normalizers, and a structured v1-to-v2 migration.
- [x] Define local footprints as `{ kind = "rect_union", parts = [...] }`,
  where each part has `id`, `origin_mm`, and `size_mm`.
- [x] Keep each room's `origin_mm` as its stable world frame. Store furniture
  with stable room-local `position_mm`, doubled local `anchor2_mm`, a footprint,
  `height_mm`, and `rotation_deg`; this preserves odd-size centres exactly.
- [x] Give project templates one matching authority: `default_footprint`,
  `default_anchor2_mm`, and `default_height_mm`. Keep external catalogue-v1
  rectangle definitions readable through an explicit conversion adapter.
- [x] Give v2 doors an interim `part_id` so `room + side + offset` is never
  ambiguous. The structural schema requires an existing owner part while
  keeping malformed-aperture repair drafts loadable. Phase 2C validates that
  the part-local side/offset aperture lies on the union exterior and prevents
  referenced parts from being silently removed. Phase 4 later migrates that
  tuple to persistent boundary-run IDs.
- [x] Migrate every v1 rectangle to `part-main` at local `[0, 0]`, preserve
  unknown tagged JSON values, reject active-field collisions, add fixtures and
  v3 forward-version rejection, and never write during load.
- [x] Normalize v1 before transforming and v2 afterward; retain structured
  path-specific failures, leave source bytes untouched on failure, keep migrated
  sessions protected/non-durable until explicit save, and provide no lossy v2
  downgrade writer.
- [x] Remove consumed v1 geometry fields from normalized v2 objects so there is
  exactly one geometry authority and no stale compatibility representation.

Stage boundary: these pieces were implemented behind the version dispatcher
and remained inactive until the complete 2C consumer and recovery gate passed.
Schema v2 and its writer then activated together; schema v1 now enters through
the sequential migration without being rewritten during load.

### 2C — End-to-end compound slice

- [x] Update model constructors, project templates, external catalogue
  conversion, movement, duplication, rotation, alignment, snapping, limits,
  diagnostics, and atomic undo around the v2 footprint authority.
- [x] Derive minimal transient compound wall/shared-boundary topology, enforce
  the interim door-part policy, and render one logical silhouette with internal
  seams removed. Persistent physical-wall identity remains Phase 4 work.
- [x] Keep existing forms safe for loaded compound objects: preserve the whole
  footprint and disable rectangle-only geometry fields until the Phase 3 editor;
  never collapse a union back to one rectangle.
- [x] Add JSON/Norg migration, save/reload/recovery, render/hit, workspace,
  packaging, and documentation fixtures; only then make schema v2 writable.

Current boundary: schema v3 is active. The room form creates rectangles and the
first compound preset (a configurable L); new furniture remains one-part.
Loaded compound rooms, furniture, and project templates are preserved across
supported edits, validation, rendering, duplication, movement, rotation,
save/reload, and undo. Windows and typed, multi-slot outlets use the same
interim part/side/offset wall attachment model as doors. Free-form part editing
and persistent physical-wall identity remain later work.

## Phase 3 — Compound editor and authoring UX

- [x] Add a configurable L-shaped room preset with four missing-corner
  orientations and exact leg dimensions.
- Add editing overlays while preserving one logical object selection and
  exposing optional part/edge provenance only inside the editor.
- Add a bordered footprint editor: select/add/remove/move/resize parts, show a
  live preview, and commit the whole edit as one undo action.
- [x] Show compact area, perimeter, bounds, and part count in the Details drawer.
- Add further room and furniture presets only where they stay clear and useful.

## Phase 4 — Stable physical walls and opening migration

- Promote transient exterior/shared-boundary topology to reconciled persistent
  physical-wall identity, representing each shared wall once.
- Give boundary runs persistent identities with deterministic reconciliation
  when geometry changes; never persist references to array indices or
  ephemeral raster segments.
- Migrate the current door/window apertures from part/side/offset tuples to
  openings on persistent wall runs.
- Deterministically migrate the v2/v3 interim
  `room_id + part_id + side + offset` tuple to wall-run identity. Older plans
  reach this through sequential migration; document ambiguous recovery.
- Add vertical window metadata only when rendering or analysis uses it. Wall
  thickness/material waits for complete rendering, validation, clearance, and
  opening semantics.

## Phase 5 — Analysis overlay framework

- Add a small registry of pure analyses that emit semantic scene primitives,
  optional diagnostics, a legend, and compact controls.
- Separate authored persisted annotations from transient derived analysis.
- Add visibility, opacity, and focus controls without overloading the main
  workspace.
- Ship one complete first overlay—measurement or clearance—before treating the
  framework as stable.

## Phase 6 — Sunlight, circulation, and spatial analysis

### Sun study

- Use geographic north plus user-supplied location, timezone, date, and time;
  do not require network access or geolocation.
- Start with deterministic morning/noon/evening sun-direction presets and an
  animated time slider. View rotation changes projection, never world north.
- Then project approximate light polygons through modeled windows using wall,
  sill, head, and obstacle heights.
- Clearly label results as approximate 2D exposure, not illuminance, thermal,
  construction, or building-code analysis.

### Circulation and clearance

- Derive walkable room space minus furniture/obstacles, with doors as portals.
- Show reachability, selected-point routes, configurable-width bottlenecks,
  door swings, furniture clearance envelopes, and optional accessibility aids.
- Keep results advisory rather than code certification or automatic layout
  optimization.

## UI/UX backlog

- Snap/alignment guides and equal-spacing constraints.
- Minimap drawer and named view presets.
- Searchable action palette and compact contextual breadcrumbs.
- Undo-history drawer, grouping, locking, and layer visibility.
- Line-of-sight, window-view, robot-vacuum reachability, and egress studies.
- SVG export after compound silhouettes and annotations are stable; DXF and
  multi-floor planning remain later, explicitly scoped projects.

## Acceptance gate for every phase

- No loss of current commands, API, keymaps, save/load, undo, rendering, or
  package-manager compatibility.
- Focused unit/integration fixtures cover the new contract and migrations.
- Full non-Nix tests, smoke checks, and `git diff --check` pass locally. Flake
  checks run in CI or only when the user explicitly requests them; never invoke
  `nix build` directly.
- User documentation describes only shipped behaviour; this roadmap owns
  future design until a phase lands.
