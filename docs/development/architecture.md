# Architecture

RoomPlan keeps exact state, geometry, persistence, rendering, and editor UI in
separate layers. The important dependency direction is:

```text
configuration/catalogue
          ↓
schema ↔ model → actions → validation → history/session
   ↑                    ↓
storage adapters     scene primitives → viewport/raster → canvas
          ↖              controller              ↗
                    workspace/forms
```

Pure modules do not depend on Neovim where an editor API is unnecessary. That
makes geometry, schema, actions, validation, presentation, viewport transforms,
and raster logic deterministic and directly testable.

## Model and mutation

`schema` is the persisted-data authority; its small facade dispatches to shared
JSON-safe primitives and explicit version normalizers. Schema v4 is the active
reader/writer; schema v1, v2, and v3 enter through sequential migrations. Load
records migration metadata without rewriting source bytes, and the first
explicit save establishes the v4 durable revision. The strict JSON codec
preserves the difference between arrays, objects, null, and exact decimal
input. `model` constructs immutable-by-convention snapshots. Every user-visible
mutation goes
through `actions.apply`, which copies, applies, validates, and returns a whole
new snapshot or no change at all. `history` owns revision/savepoint and memory
budgets; `session` combines it with transient selection, viewport, validation,
source state, and quit protection.

Geometry is split by concept under `geometry/`: runtime footprints,
rectangles/intervals, adjacency, doors, sectors, alignment, and snapping. The
footprint layer is the shared authority for both migrated one-part rectangles
and current compound unions. It owns stable part identity, connected-union
topology, exact-range-checked measurements, seam-free boundaries, containment,
intersection, transforms, anchors, and hit provenance. Room forms preserve
compound footprints and can resize their rectangular sections without exposing
internal offsets; other compound object forms remain preservation-only.
Geometry uses integer or doubled-integer predicates where possible. `validate`
first defends structural invariants, then evaluates layout relationships and
returns deterministic diagnostics.

`room_shape` owns pure transient section selection and topology-safe add,
remove, and resize operations for rooms, placed furniture, and project
templates; `room_shape/snapping.lua` derives its axis-local structural/grid
candidates and display-only guides. `controller/shape.lua` publishes the draft
through `Session:current_model()` for rendering, while persistence and history
continue to see the durable model. Template drafts use an isolated local scene
instead of acquiring an artificial plan position. Applying emits one ordinary
entity action or one atomic furniture-plus-template action; cancelling emits
none.

## Persistence

`storage` detects the standalone JSON or Norg adapter. Adapters implement load,
prepare, compare-before-mutate commit, and initialization. `storage.source`
owns buffer/file text and durable revision snapshots; `storage.atomic` owns
safe creation. Adapters never evaluate source content and never guess through
malformed or ambiguous input. Normalization and migration metadata participates
in every durability reconciliation, so semantically equal source bytes cannot
accidentally turn an unsaved normalized or migrated snapshot into a savepoint.

`state` indexes live sessions, source ownership, and attached buffers. Only one
session may write a source. The session guard represents protected in-memory
work to Neovim's normal quit machinery.

## Controller and UI

[`controller.lua`](../../lua/roomplan/controller.lua) is a small stable facade.
Implementation lives in cohesive modules:

- `controller/source.lua` opens, initializes, reloads, and closes sources;
- `controller/persistence.lua` validates, saves, and resolves conflicts;
- `controller/view.lua` owns workspace visibility, selection, viewport,
  aspect, and view interaction;
- `controller/edit.lua` dispatches semantic changes and structured editing;
- `controller/shape.lua` coordinates direct transient room resizing;
- `controller/common.lua` and `source_context.lua` contain narrowly shared
  resolution and source-context helpers.

The facade is passed into the implementation attach functions, so those modules
do not require it back and create a cycle.

Workspace code separates state/layout calculation, presentation, panel
rendering, window lifecycle, mappings/interactions, and small shared utilities.
Forms similarly separate pure specs/state/rendering from the Neovim float
adapter. `ui.action_registry` is the single source for contextual labels,
keys, availability, and handlers; the footer and full palette consume it.

## Rendering

`scene/build` translates validated model concepts into semantic primitives.
Compound room walls are derived from the union exterior, internal part seams
are removed, and valid part-aware door/window apertures are applied before
coincident room walls are grouped. Wall and floor outlets remain non-cutting
points. Room
and furniture parts retain one logical object reference for selection and
diagnostics. The viewport maps world millimetres to logical cells;
rasterization remains bounded by visible cells and stores hit provenance
separately from glyph text. `render.canvas` alone adapts the result to Neovim
buffers, extmarks, cursor positions, and redraw scheduling.

These boundaries are design constraints, not only folder organization: UI
must never mutate nested model tables, storage must never bypass revisions, and
render text must never become persisted state.

The [ADR index](../adr/README.md) records why the durable boundaries were
chosen and how a future decision may supersede one. This chapter remains the
authority for the architecture as it exists now.

← [Limitations and roadmap](../reference/limitations-and-roadmap.md) | [Documentation home](../README.md) | [Compatibility](compatibility.md) →
