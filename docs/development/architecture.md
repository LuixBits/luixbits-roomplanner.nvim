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

`schema` is the persisted-data authority; the strict JSON codec preserves the
difference between arrays, objects, null, and exact decimal input. `model`
constructs immutable-by-convention snapshots. Every user-visible mutation goes
through `actions.apply`, which copies, applies, validates, and returns a whole
new snapshot or no change at all. `history` owns revision/savepoint and memory
budgets; `session` combines it with transient selection, viewport, validation,
source state, and quit protection.

Geometry is split by concept under `geometry/`: rectangles/intervals,
adjacency, doors, sectors, alignment, and snapping. It uses integer or doubled
integer predicates where possible. `validate` first defends structural
invariants, then evaluates layout relationships and returns deterministic
diagnostics.

## Persistence

`storage` detects the standalone JSON or Norg adapter. Adapters implement load,
prepare, compare-before-mutate commit, and initialization. `storage.source`
owns buffer/file text and durable revision snapshots; `storage.atomic` owns
safe creation. Adapters never evaluate source content and never guess through
malformed or ambiguous input.

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
Walls are assembled with door apertures before rasterization. The viewport maps
world millimetres to logical cells; rasterization remains bounded by visible
cells and stores hit provenance separately from glyph text. `render.canvas`
alone adapts the result to Neovim buffers, extmarks, cursor positions, and
redraw scheduling.

These boundaries are design constraints, not only folder organization: UI
must never mutate nested model tables, storage must never bypass revisions, and
render text must never become persisted state.

← [Limitations and roadmap](../reference/limitations-and-roadmap.md) | [Documentation home](../README.md) | [Contributing](contributing.md) →
