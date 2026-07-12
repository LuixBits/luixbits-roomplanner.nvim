# `roomplan.nvim` — approved-design candidate and end-to-end implementation plan

**Status:** approved and implemented as an unreleased release candidate
**Plan date:** 2026-07-12
**Primary runtime target:** Neovim 0.12.4
**Compatibility target:** Neovim 0.10.4, 0.11.7, 0.12.4, and nightly
**Working project directory:** `roomplan.nvim/`
**Working license:** MIT, subject to approval with this plan
**Product scope:** one 2D floor plan per `.roomplan.json` file or embedded `.norg` block

**Implementation verification:** the local Neovim 0.12.4 suite exercises the
end-to-end standalone/Norg scenarios, strict model/geometry/actions,
rendering, conflict recovery, Save As matrices, and native quit protection.
The configured 0.10/0.11/0.12.4/nightly and Linux/macOS/Windows CI still needs
to run in the eventual hosted repository. The conservative Norg scanner is the
current discovery authority (Tree-sitter candidate discovery remains a future
enhancement), `show_rulers` is reserved but rulers are not yet drawn, and the
final GitHub owner/slug is not known in this workspace.

This document supersedes the initial handoff. It retains the strong parts of that proposal—canonical structured data, pure geometry, a rendered canvas, semantic undo, standalone JSON first, and optional Neorg integration—while resolving the contracts that were still ambiguous enough to produce incompatible or unsafe implementations.

Approval was granted in the follow-up implementation request. The repository now contains the model, geometry, actions, validation, renderer, sessions, standalone/Norg persistence, UI workflows, safety guards, documentation, fixtures, and CI described here. This document remains the architecture and acceptance reference for review and future changes.

---

## 1. Executive assessment

### 1.1 What was already strong

The original proposal chose the right foundation:

- The Unicode drawing is a projection, never the source of truth.
- Geometry is stored in integer millimetres and kept independent of Neovim.
- Rooms and furniture are deliberately rectangular for the first release.
- Storage is adapter-based, with standalone JSON implemented before Norg.
- Norg integration is file-format integration rather than a dependency on private Neorg internals.
- Model edits are semantic actions with their own undo/redo history.
- Rendering uses a scratch buffer, logical raster cells, junction masks, extmarks, and a hit map.
- Invalid layouts are reported instead of silently “fixed.”
- Core runtime dependencies remain zero.
- The proposed acceptance scenario is concrete and valuable.

Those decisions should not be revisited during implementation without a demonstrated blocker.

### 1.2 What needed correction or more precision

The original proposal was not yet a safe implementation handoff in these areas:

1. A shared door was anchored to one room but its effect on the other room's coincident wall was unspecified.
2. `opens_into` repeated room IDs unnecessarily and did not define the actual swing half-plane.
3. “Interior corner” and “wall centre-line” dimensions were both used for the same v1 rectangle.
4. Centre alignment can require half-millimetre origins even though persisted coordinates must be integer millimetres.
5. Contact versus positive-area overlap was not defined.
6. Directional room placement did not define the orthogonal alignment.
7. Deterministic JSON, strict duplicate-key rejection, JSON null, and empty array/object preservation were not designed for Neovim 0.10.
8. Model dirty state, source-buffer modified state, disk persistence, and source conflict were conflated.
9. Updating a loaded Norg buffer and durably saving that buffer were not distinguished.
10. A malformed intended Norg block could look like “zero matching blocks,” leading to accidental duplication.
11. A wiped `nofile` canvas could strand model-only changes without Neovim's ordinary modified-buffer protection.
12. Multi-plan session ownership and command targeting were undefined.
13. `vim.ui.select` does not guarantee search, and its default implementation does not provide a searchable object picker.
14. Callback-based UI flows lacked cancellation, stale-callback, and concurrency contracts.
15. Selecting an object and immediately turning `h/j/k/l` into destructive movement was too easy to do accidentally.
16. Terminal cursor columns, extmark columns, glyph widths, and display columns were treated as if they were the same.
17. The stated “MVP” is realistically a polished 1.0-sized feature set.
18. Version 1 is the first schema, so inventing a fake version 0 migration would be more dangerous than useful.

This plan resolves each item explicitly.

### 1.3 Scope judgment

The complete requested feature set remains the final target. It will be delivered as tested vertical milestones rather than as one large integration jump:

- **Milestone A / v0.1 standalone feature slice (phases 0–6):** strict model, standalone JSON, sessions, complete required room/furniture/shared-door workflows, snapping, searchable lists, essential validation, history, Unicode/ASCII canvas, and conflict-safe persistence.
- **Milestone B / v0.2 embedded-source beta (phase 7 plus its documentation):** Norg adapter/preservation/conflicts, no-Neorg/parser compatibility, and the complete Norg acceptance scenario.
- **Milestone C / v1.0 release gate (phase 8):** health/documentation completion, full compatibility/OS matrix, performance hardening, accessibility checks, release packaging, and every definition-of-done scenario.

Implementation is not considered complete merely because v0.1 works. These milestones are integration gates for the same approved project.

---

## 2. Proposed locked decisions

Approval of this plan approves the following defaults. They are called out because they materially refine the initial proposal.

1. **License:** use the MIT license. Implement the junction rasterizer independently. Do not copy Neorg code. If any third-party source is later adapted, preserve its license and add exact attribution to `NOTICE` before merging it.
2. **Multiple plans:** support multiple sessions in one Neovim process. Permit only one writable session per canonical source identity and one canvas window per session.
3. **Canvas close semantics:** `q` and `:RoomPlanHide` hide/wipe the canvas view but retain the session and its model. `:RoomPlanClose` unloads the session and prompts whenever model/staged/conflict state requires protection; `:RoomPlanClose!` explicitly discards the session while leaving any already modified source buffer intact.
4. **Quit protection:** every session owns an internal hidden `acwrite` guard buffer whose `modified` flag mirrors the broader `session_requires_protection` predicate (model dirty, staged/pending write, or unresolved model-at-risk conflict). This lets ordinary `:qall`, `:wall`, and buffer deletion participate in Neovim's native unsaved-change protection even though the canvas is `nofile`.
5. **Norg save meaning:** `:RoomPlanSave` replaces the selected JSON payload through buffer APIs and then performs a normal write of the named source buffer. This also writes unrelated unsaved edits in that Norg buffer, exactly as `:write` would. The documentation and confirmation/status text must say so.
6. **Norg marker:** newly created blocks use `@code json roomplan.nvim`. The extra standard tag parameter makes a malformed RoomPlan block identifiable without parsing its JSON. Legacy unmarked `@code json` blocks remain readable by their top-level `format` field and are not silently rewritten to marked form.
7. **Norg parsing:** a small specification-based ranged-tag scanner is the safety authority for exact replacement bounds. Tree-sitter is preferred for candidate discovery when an available, tested query works; the scanner is the dependency-free fallback and final bounds check. No private Neorg module tables are used.
8. **Door identity:** one physical shared doorway is stored once. `room_id` is its anchor/coordinate owner. A valid connected door cuts both contributors to the shared rendered wall.
9. **Door swing field:** replace room-ID-valued `opens_into` with the enum `owner | connected | outside`. The UI resolves these terms to room names. This removes redundant references and gives the field a precise “swing half-plane” meaning.
10. **IDs:** all persisted entity/template IDs are immutable and globally unique, use type prefixes, and are never edited when an object is renamed. Built-in template IDs use `builtin:*`; project template IDs use `custom:*`.
11. **Room deletion:** show a complete dependency summary and, after explicit confirmation, cascade-delete the room, its furniture, its owned doors, and doors from other rooms connected to it in one undoable action.
12. **Invalid edit policy:** malformed structure and impossible primitives are always rejected. Room overlap and broken connected-door relations are blocked unless an explicit force action is confirmed. Furniture may temporarily be outside its room or overlap another item so exploratory editing can continue; those are validation errors and block normal save.
13. **Save-invalid policy:** `:RoomPlanSave!` may save a structurally valid model with layout errors. It never bypasses a source conflict, unsupported schema, malformed JSON, unsafe destination, or failed migration.
14. **Canvas interaction:** use explicit `NAV`, `MOVE`, `PAN`, and placement modes. Selecting an object does not silently change navigation keys into geometry mutations. The current mode is always shown textually.
15. **Searchable lists:** implement an internal dependency-free scratch-buffer list for objects and validation results. Normal `/`, `n`, and `N` search it. Optional picker plugins may enhance menus, but required search does not depend on them.
16. **Integer lattice:** derived edges/centres use doubled-millimetre integers. An operation whose exact result lies at half a millimetre is rounded to the nearest stored integer millimetre, with ties away from zero, and reports a `0.5 mm` residual in its preview/result.
17. **Directional placement:** east/west placement aligns south edges; north/south placement aligns west edges. Explicit align-centre/corner operations remain available.
18. **History:** use bounded full-model snapshots first. The target plan size makes this simple and safe; switch to record patches only if profiling proves a real problem.
19. **Movement undo:** one committed movement keypress is one semantic history entry. Redraws may be coalesced, but timed history coalescing is deferred until it has an explicit transaction boundary.
20. **Initial migration policy:** schema version 1 has no predecessor. Implement the sequential migration registry and migration tests now, but leave it empty. Missing, zero, and future versions are rejected. Never guess that an unversioned object is v1.
21. **Schema extensions:** preserve unknown JSON members semantically at every known object level, retain JSON type distinctions, and deterministically reformat them on save. Exact original whitespace/key order inside the JSON payload is not preserved.
22. **Release scope:** the complete definition of done in this file remains required; the version milestones only order and de-risk delivery.
23. **Draft schema reset:** this is a new, unimplemented project with no published RoomPlan files. The revised authoritative v1 in section 6 intentionally supersedes the original planning example (including the `opens_into` enum, prefixed IDs/templates, `normal_step_mm`, furniture `category`, and `extensions`). No migration is fabricated for a draft that was never released. If real prototype files already exist, pause before coding and add an explicit importer/fixture.

---

## 3. Product definition

### 3.1 Objective

Build a Neovim plugin for planning a flat in a terminal. A user can create axis-aligned rectangular rooms, position and align them, place single-leaf hinged doors with visible handedness/swing direction, place rectangular furniture with exact dimensions, inspect and validate the geometry, undo semantic edits, and safely persist the same canonical plan in standalone JSON or an embedded Norg block.

The plugin is a planning tool, not a building-code checker or CAD system. It should make approximate spatial planning fast while keeping exact stored dimensions inspectable.

### 3.2 Primary user journeys

1. Create a new standalone plan, add two rooms, align them, add a connecting door, furnish them, validate, save, close, and reopen.
2. Open an existing source plan, inspect exact geometry, make a few keyboard moves, undo/redo, and save without losing concurrent source edits.
3. Initialize a marked RoomPlan block inside an existing Norg note, edit through the canvas, and preserve every unrelated logical line in the note.
4. On an initial malformed/unsupported open, receive source-located diagnostics and recover by editing/fixing then retrying, or initialize elsewhere; no session/model is fabricated. If an already-open session's source later becomes damaged, retain its valid model so Reload-after-fix or Save As can recover it without overwriting the damaged source.
5. Complete all essential operations without colour, a mouse, Telescope, fzf-lua, Snacks, nui.nvim, or a custom `vim.ui` provider.

### 3.3 In scope for 1.0

- One 2D plan/floor per source.
- Rectangular rooms with zero-thickness abstract boundaries.
- Rectangular furniture footprints and 90-degree rotations.
- Single-leaf hinged doors with angles from 1 through 180 degrees.
- Metric inputs and integer-millimetre storage.
- Standalone and Norg storage adapters.
- Multiple concurrent sessions for different sources.
- Scratch-buffer canvas, viewport, selection, inspector, lists, validation, history, save/reload/Save As, configurable mappings, health checks, tests, and documentation.

### 3.4 Explicitly out of scope

- 3D/perspective views.
- Polygonal or angled rooms, curved walls, and physical wall solids.
- Multiple floors in one model.
- Arbitrary-angle furniture.
- Windows, sliding/folding/revolving doors, and double doors.
- Required mouse drag-and-drop.
- CAD/BIM import or DXF/IFC/OpenSCAD export.
- Automated layout optimization.
- Building/accessibility-code certification.
- Collaborative editing or automatic three-way merges.
- Global furniture catalogue persistence in 1.0.
- Generated drawings inserted into the source note.

Future features must extend the model rather than reinterpret v1 coordinates.

---

## 4. Verified platform and research baseline

The implementation should re-check these sources when coding begins, but the assumptions were verified on 2026-07-12:

- [Neovim v0.12.4](https://github.com/neovim/neovim/releases/tag/v0.12.4) is the current stable release.
- Compatibility pins are [v0.10.4](https://github.com/neovim/neovim/releases/tag/v0.10.4), [v0.11.7](https://github.com/neovim/neovim/releases/tag/v0.11.7), v0.12.4, and nightly.
- The public [Neovim API documentation](https://neovim.io/doc/user/api/) covers scratch buffers, extmarks, changed ticks, buffer mutation, windows, and resize events used here.
- The public [`vim.ui` documentation](https://neovim.io/doc/user/lua.html#vim.ui) defines input/select as potentially asynchronous and cancellation as a nil callback value. Default `vim.ui.select` does not provide preview and cannot be treated as a searchable picker.
- [Neovim 0.12 news](https://neovim.io/doc/user/news-0.12/) must be checked for APIs that are new in 0.12. In particular, do not rely on 0.12-only JSON sorting/indent options when supporting 0.10/0.11.
- [`vim.pack`](https://neovim.io/doc/user/pack/) is a Neovim 0.12+ installation option and must be labelled accordingly.
- The current [Neorg README/repository](https://github.com/nvim-neorg/neorg) requires Neovim 0.10+, warns of occasional workflow-breaking changes, and declares GPL-3.0 licensing. This MIT project may use the public Norg specification/public integration APIs but must not copy Neorg implementation code; core RoomPlan must not depend on Neorg being installed.
- The [Norg 1.0 specification](https://github.com/nvim-neorg/norg-specs/blob/main/1.0-specification.norg) permits verbatim ranged tags, optional leading indentation, arbitrary same-line tag parameters, and `@end` delimiters.
- [`venn.nvim`](https://github.com/jbyuki/venn.nvim) is MIT-licensed. It may be studied conceptually, but this project will implement its own semantic scene and junction-mask rasterizer. Copying later requires attribution.

Compatibility rules:

- Write Lua 5.1-compatible syntax. Do not assume Lua 5.3 operators, the standard `utf8` module, or LuaJIT-only FFI/extensions.
- Use documented Neovim functions only. Centralize version differences in `compat.lua`.
- Core runtime dependencies are zero. Test/development tooling may be installed in CI.
- Neorg and the Norg Tree-sitter parser are optional.
- Use structured APIs for paths and commands; never interpolate user paths into Ex strings.
- Core runtime functionality launches no shell commands or external processes. Shell scripts exist only as developer/CI entry points around headless tests.

---

## 5. Terminology and system invariants

### 5.1 Terms

- **Document:** the JSON value stored in a standalone file or Norg payload.
- **Model:** the normalized, structurally valid in-memory document used by actions.
- **Entity:** a room, door, furniture item, or custom template.
- **Session:** one writable model/history/source association plus zero or one visible canvas.
- **Source:** a buffer-backed or detached standalone/Norg location.
- **Source revision:** the exact content fingerprint against which a commit is allowed.
- **Canvas:** disposable rendered scratch-buffer view of a session.
- **Scene:** pure semantic drawing primitives derived from the model before rasterization.
- **Layout diagnostic:** an error or warning produced from a structurally valid model.
- **Structural diagnostic:** a load/action error that prevents creation of a valid model.
- **Owner:** the room whose edge defines a door's side and offset.
- **Connected room:** the optional adjacent room referenced by a physical door.
- **Dirty:** the current history revision is not durably persisted at the source savepoint.
- **Conflicted:** current source content no longer matches the revision expected by the session.

### 5.2 Non-negotiable invariants

1. Rendered characters are never parsed into model geometry.
2. Stored geometry is finite, safe integer millimetres.
3. A session contains a structurally valid current-schema model or does not open.
4. All model mutations go through actions and are atomic.
5. UI drafts never mutate the model before final confirmation.
6. Selection, cursor, inspector, validation-list position, pan, and zoom are not history entries.
7. Saving never clears history.
8. Any reload that replaces the current model clears history and installs a new initial node, even if the external source revision is unchanged; a detected semantic no-op reload may preserve history and report that nothing changed.
9. A source conflict is rechecked immediately before every write, including after asynchronous confirmation.
10. No save path executes plan content or treats a plan string as Lua, a module name, an Ex fragment, a highlight name, or a filesystem path.
11. A valid connected door is exactly one physical aperture and affects both sides of the shared wall.
12. Boundaries may touch. Only positive-area rectangle intersection is overlap.
13. Unknown JSON members survive supported-schema load, edit, history, and save semantically.
14. Canvas destruction never destroys a live session implicitly.
15. `:qa!` is the explicit process-wide escape that may discard all live sessions. Forced wipes of canvas/guard/source buffers do not by themselves destroy a RoomPlan model under the lifecycle rules, although forcing away a modified source buffer can explicitly discard its staged text. Semantic session destruction occurs only through `RoomPlanClose[!]` or editor exit.

---

## 6. Authoritative schema v1

There must be exactly one authoritative example. The JSON Schema checked into `schema/roomplan.schema.json`, runtime validator, constructor defaults, documentation, fixtures, and this example must agree.

```json
{
  "format": "roomplan.nvim",
  "schema_version": 1,
  "units": "mm",
  "metadata": {
    "name": "My flat",
    "notes": ""
  },
  "settings": {
    "grid_mm": 100,
    "fine_step_mm": 10,
    "normal_step_mm": 100,
    "coarse_step_mm": 500,
    "default_door_width_mm": 900,
    "default_wall_thickness_mm": 120
  },
  "rooms": [
    {
      "id": "room-living",
      "name": "Living room",
      "origin_mm": [0, 0],
      "size_mm": [5000, 4000]
    },
    {
      "id": "room-bedroom",
      "name": "Bedroom",
      "origin_mm": [5000, 0],
      "size_mm": [3000, 3000]
    }
  ],
  "doors": [
    {
      "id": "door-living-bedroom",
      "kind": "hinged",
      "room_id": "room-living",
      "connects_to_room_id": "room-bedroom",
      "side": "east",
      "offset_mm": 800,
      "width_mm": 900,
      "hinge": "start",
      "opens_into": "connected",
      "open_angle_deg": 90
    }
  ],
  "furniture": [
    {
      "id": "furniture-sofa-1",
      "room_id": "room-living",
      "template_id": "builtin:sofa",
      "name": "Sofa",
      "category": "seating",
      "center_mm": [1550, 1050],
      "size_mm": [2100, 900, 800],
      "rotation_deg": 0
    }
  ],
  "custom_templates": [
    {
      "id": "custom:my-desk",
      "name": "My desk",
      "category": "work",
      "shape": "rectangle",
      "default_size_mm": [1600, 800, 740]
    }
  ],
  "extensions": {}
}
```

### 6.1 Root contract

| Field | Contract |
|---|---|
| `format` | Required exact string `roomplan.nvim`. |
| `schema_version` | Required safe integer. Exactly `1` for this schema. |
| `units` | Required exact string `mm` in v1. |
| `metadata` | Optional on input, normalized with fixed schema defaults, always emitted. |
| `settings` | Optional on input, normalized with fixed schema defaults, always emitted. |
| `rooms` | Required JSON array, model order preserved. |
| `doors` | Required JSON array, model order preserved. |
| `furniture` | Required JSON array, model order preserved. |
| `custom_templates` | Required JSON array, model order preserved. |
| `extensions` | Optional JSON object for deliberate namespaced extensions; always emitted. |

If normalization adds omitted optional known fields, the session reports that fact and starts dirty because a deterministic save will change the payload. Setup configuration never supplies missing defaults for an existing document; fixed schema defaults do, so a file has the same meaning on every machine.

### 6.2 Fixed schema defaults

| Field | Default |
|---|---:|
| `metadata.name` | `Untitled plan` |
| `metadata.notes` | empty string |
| `settings.grid_mm` | 100 |
| `settings.fine_step_mm` | 10 |
| `settings.normal_step_mm` | 100 |
| `settings.coarse_step_mm` | 500 |
| `settings.default_door_width_mm` | 900 |
| `settings.default_wall_thickness_mm` | 120 |

`setup().plan_defaults` affects only newly initialized plans. The initializer may derive a new plan name from its source basename when no configured name is supplied. It does not alter fallback semantics for loaded v1 documents, whose missing name always normalizes to `Untitled plan`.

### 6.3 Identity contract

- In schema/regex notation, IDs match `^[A-Za-z][A-Za-z0-9._:-]{0,127}$`. Runtime Lua 5.1 validation must implement this as an explicit 1–128 byte length check plus a first-character and remaining-character Lua-class check; Lua patterns do not support `{m,n}` quantifiers.
- IDs are unique across rooms, doors, furniture, and custom templates.
- Collection prefixes are structurally required on load: rooms `room-`, doors `door-`, furniture `furniture-`, and project templates `custom:`. Built-in templates are referenced with `builtin:` but are not persisted as entities.
- IDs are opaque and immutable after creation. Names are editable and need not be unique.
- Creation uses a readable slug plus collision suffix (`room-living`, `room-living-2`, …), with the generator injectable in tests.
- Duplication creates new IDs for every duplicated entity.
- Reserved top-level strings such as `owner`, `connected`, `outside`, and `builtin:*` cannot be entity IDs in conflicting namespaces.

### 6.4 Room contract

```text
id          immutable global ID
name        non-empty display string
origin_mm   [x, y] lower-left abstract interior boundary
size_mm     [width, depth], both positive
```

The v1 rectangle is the abstract topological room boundary and zero-thickness wall centre-line required by the original design. With zero wall thickness it also bounds the nominal interior planning area, so the earlier phrase “lower-left interior corner” has the same numeric location. A future wall-solid model must derive thickness around this boundary under a new explicit contract and must not reinterpret existing v1 coordinates.

`settings.default_wall_thickness_mm` is inert planning metadata in v1. Changing it has no effect on room bounds, rendering, snapping, adjacency, door apertures, containment, validation, or collisions.

Room origins may be negative. Rooms cannot rotate in v1.

### 6.5 Furniture contract

```text
id            immutable global ID
room_id       syntactically valid room-ID reference string; valid layout resolves it
template_id   builtin:* or custom:* catalogue reference; unresolved remains a warning
name          non-empty display label
category      non-empty project-visible category
center_mm     [x, y] in owning-room local coordinates
size_mm       [width, depth, height], all positive
rotation_deg  exactly 0, 90, 180, or 270; clockwise for UI meaning
```

Dimensions are explicit and authoritative. Changing a template or category never silently replaces explicit dimensions. An unresolved `template_id` is a warning, not an error, because the item remains fully measurable.

### 6.6 Door contract

```text
id                       immutable global ID
kind                     exactly hinged
room_id                  syntactically valid owner/anchor room-ID reference
connects_to_room_id      syntactically valid other-room ID reference or JSON null
side                     north, east, south, or west
offset_mm                integer >= 0 from canonical edge start
width_mm                 positive integer
hinge                    start or end
opens_into               owner, connected, or outside
open_angle_deg            integer 1..180
```

Syntactic field types/enums are structural. The following are valid-layout rules and may be reported on a safely loadable repair draft:

- New Add Door drafts default `open_angle_deg` to 90; editing preserves the stored angle unless changed explicitly.
- `offset_mm + width_mm` must not exceed the owner edge length.
- `connects_to_room_id` must differ from `room_id`.
- `connected` requires a non-null connected room and a valid shared aperture.
- A connected door permits `owner` or `connected`, not `outside`.
- An exterior door permits `owner` or `outside`, not `connected`.
- A valid unconnected/exterior aperture has zero positive collinear overlap with every opposite room edge. If exactly one other room covers the complete aperture, omitting that connection is `DOOR_CONNECTION_MISSING`; any partial or multi-room opposite overlap is `DOOR_EXTERIOR_OBSTRUCTED`. A connected door is valid only when one named room covers the complete aperture.
- One shared physical door is persisted once, even though its rendered aperture affects both room boundaries.
- Opposite-owned doors on the same global wall interval are diagnosed as overlapping duplicate apertures.

### 6.7 Custom template contract

```text
id                immutable custom:* ID
name              non-empty display name
category          non-empty category
shape             exactly rectangle in v1
default_size_mm   [width, depth, height], all positive
```

Deleting a template that is still referenced is blocked until the user reassigns those items to another project/built-in template such as `builtin:custom-rectangle`. V1 has no null/unlinked `template_id`. A global user catalogue is deferred.

### 6.8 Text and numeric safety limits

Hard limits are not configurable downward or upward through plan data:

- All known geometry coordinates are integers with absolute value below `2^50`; this leaves headroom for addition and doubled-coordinate predicates below Lua's exact-integer boundary. Individual dimensions, steps, and door widths also have a non-configurable `1000000000 mm` ceiling so local floating collision predicates retain sub-millimetre numerical headroom. Normal configured limits are vastly smaller.
- Default soft maximum room dimension: `100000 mm` (100 m).
- Default soft maximum absolute world coordinate: `1000000 mm` (1 km).
- Maximum JSON payload: 10 MiB.
- Maximum JSON nesting depth: 64.
- Maximum total JSON values: 100,000.
- Maximum entity count per collection: 10,000.
- Maximum ordinary name/category/ID length: 512 UTF-8 bytes, with the stricter ID regex above.
- Maximum `metadata.notes`: 1 MiB.
- Maximum numeric lexeme: 1024 bytes with a bounded absolute decimal exponent (default hard ceiling `1000000`); canonicalization may retain exponent form and must not allocate an exponent-sized zero string.
- Known display strings reject NUL and disallowed control characters. Notes may contain line breaks because JSON escaping prevents Norg delimiter injection.
- Known numeric fields must be safely representable and satisfy their exact integer/range contracts. Unknown extension numbers use the codec's bounded tagged decimal representation and are never coerced through Lua floating point merely to preserve them.

User-local `limits` normally impose much smaller plan/dimension thresholds. The hard ceiling exists to prevent arithmetic and resource abuse.

### 6.9 Unknown members and extensions

Unknown object members are preserved at the root and inside every known entity/settings/metadata object for supported schema versions.

- Missing, JSON null, empty object, and empty array remain distinguishable.
- Arrays retain order.
- Mutating known fields leaves unknown siblings unchanged.
- Duplication copies unknown members while replacing IDs/references as required.
- Deletion removes unknown data attached to the deleted entity.
- Migrations preserve unknown members unless a migration explicitly consumes one.
- Unknown object keys are serialized lexicographically after known ordered fields.
- `extensions` should use reverse-domain or otherwise namespaced keys, for example `org.example.clearance`.

This is semantic preservation, not byte-for-byte preservation of the JSON payload's original formatting.

The authoritative example's sofa height of 800 mm intentionally demonstrates an explicit override of the built-in `builtin:sofa` catalogue seed (850 mm); furniture dimensions, not catalogue defaults, are authoritative.

---

## 7. Strict JSON codec and schema pipeline

### 7.1 Why an original codec is required

Neovim 0.10/0.11 cannot be assumed to provide deterministic sorted/indented encoding options, and ordinary Lua tables cannot distinguish all JSON types. The plugin therefore implements a small original pure-Lua strict JSON codec under `lua/roomplan/codec/json.lua`.

The codec uses private tagged metatables/sentinels for JSON object, JSON array, JSON null, and decimal numbers that have not been consumed by the known schema. Plan keys such as `__index` remain ordinary data; no metatable is ever created from plan content.

Decoder requirements:

- Strict RFC-compatible JSON only: no comments, trailing commas, NaN, infinity, or trailing content.
- UTF-8 validation and correct Unicode escape/surrogate-pair decoding without assuming Lua's `utf8` module.
- Duplicate object-key rejection after escape decoding, including escaped-equivalent keys.
- Parse number lexemes into a bounded decimal representation `(sign, coefficient digits, decimal exponent)`. Schema normalization converts known safe integer fields to ordinary Lua integers; unknown extension numbers retain the tagged decimal representation.
- Configurable soft and fixed hard depth/value/string/payload limits.
- Exact source-offset, line, and column diagnostics.
- Array/object/null type tagging that survives deep copy and history.

Encoder requirements:

- UTF-8, no BOM.
- Two-space indentation.
- Known schema field order followed by byte-lexicographic unknown keys.
- Array order preserved.
- Integers in canonical base-10 form; normalize negative zero.
- Stable extension-number formatting through string arithmetic only: normalize zero/sign, coefficient leading/trailing zeros, exponent spelling/case, and plain-versus-exponent form under one documented rule. Never use platform `string.format`/locale/IEEE-754 rounding for an untouched extension number.
- Required JSON escaping for controls, quotes, and backslashes.
- Exactly one final newline for detached standalone JSON.
- No dependence on Lua table iteration order.

The codec and its tags are pure Lua and have no `vim` dependency.

### 7.2 Load pipeline

Every adapter runs the same pipeline:

1. Enforce source/payload size limits and valid UTF-8.
2. Strictly decode JSON and reject duplicate keys.
3. Require an object root.
4. Require exact `format`.
5. Require an integral `schema_version`.
6. Reject a future version without mutation.
7. Apply sequential pure migrations on a deep copy.
8. Validate/normalize structural fields with fixed schema defaults.
9. Build ID/reference indexes and report identity/reference errors.
10. Run layout validation separately.
11. Create a session only if structural validity succeeds.

Layout errors may exist in a loaded model so users can repair an invalid draft. Parse, root, format, version, type, unsafe-number, and impossible-reference-shape failures prevent session creation.

### 7.3 Migration contract

The registry is indexed by source schema version:

```text
migrations[N](document_copy) -> version_N_plus_1_document, notes
```

Migrations are pure, deterministic, sequential, preserve unknown members, never write automatically, and mark the resulting session dirty. Version 1 is the first published schema, so the initial registry is intentionally empty. Missing and version 0 documents are rejected with an explanation rather than guessed into v1.

Adding schema v2 is prohibited unless it includes:

- a documented `1 -> 2` migration;
- before/after fixtures;
- unknown-field retention tests;
- idempotence expectations for current-version load;
- downgrade/recovery guidance;
- an updated checked-in JSON Schema and help documentation.

---

## 8. Measurement and coordinate contracts

### 8.1 Input parsing

The pure unit parser trims surrounding whitespace, then scans: optional `+`/`-`; one or more ASCII digits; optional `.` followed by one or more digits; and an immediately adjacent optional alphabetic suffix. It lowercases the suffix and membership-checks exactly `""`, `mm`, `cm`, or `m`. Do not implement this with regex alternation—Lua 5.1 patterns have none. A suffixless number is millimetres. This deliberately rejects `.5`, `2.`, exponent notation, internal unit whitespace such as `2 m`, and locale decimal commas so parsing is stable; these choices must be shown in input errors/help.

Examples:

| Input | Result |
|---|---:|
| `2100` | 2100 mm |
| `2100mm` | 2100 mm |
| `210cm` | 2100 mm |
| `2.1m` | 2100 mm |
| `-1.2m` | -1200 mm when the field allows negative coordinates |

The parser uses decimal-rational string arithmetic rather than binary floating-point conversion. Scientific notation and locale commas are not accepted. A value that does not resolve to a whole millimetre, such as `1.5mm`, is rejected rather than rounded. Dimension/step/width fields reject zero and negatives; coordinate/gap policies are field-specific.

### 8.2 World coordinates

- Positive X points right/east.
- Positive Y points up/north.
- Room origin is lower-left.
- Furniture centre is room-local; world centre is room origin plus local centre.
- Door offsets use the owner edge's canonical tangent.
- Rendering inverts Y because buffer rows increase downward.

### 8.3 Doubled-millimetre derived geometry

An integer-centred furniture item with odd width has half-millimetre edges. Derived predicates therefore use doubled coordinates:

```text
left_x2   = 2 * world_center_x - effective_width
right_x2  = 2 * world_center_x + effective_width
bottom_y2 = 2 * world_center_y - effective_depth
top_y2    = 2 * world_center_y + effective_depth
```

Room centres are compared similarly. This prevents floating-point accumulation in containment, overlap, alignment, and snapping.

If a requested alignment would require a half-millimetre stored origin, round the final coordinate to the nearest integer millimetre, ties away from zero. Return a diagnostic such as `centre alignment rounded by 0.5 mm`; show it in menu preview and inspector history metadata. Persist only the rounded integer.

---

## 9. Pure geometry contract

All modules in `lua/roomplan/geometry/` are deterministic, side-effect-free, Lua 5.1-compatible, and do not reference `vim`.

### 9.1 Rectangles and intervals

For rectangle `R = (left, bottom, width, depth)`:

```text
right = left + width
top   = bottom + depth
```

Positive-area overlap is:

```text
max(a.left, b.left) < min(a.right, b.right)
and
max(a.bottom, b.bottom) < min(a.top, b.top)
```

Boundary contact is valid. Containment includes boundaries. Furniture touching a wall or another furniture boundary is valid. Door opening intervals touching at one endpoint are valid; positive-length collinear overlap is invalid.

Required primitives:

- points/vectors and integer-safe helpers;
- half-open and closed interval helpers with explicitly named semantics;
- AABBs in normal and doubled coordinates;
- containment, positive overlap, intersection rectangle, and broad phase;
- point/edge/interior hit tests;
- segment/rectangle and segment/segment intersection;
- 90-degree effective furniture dimensions;
- deterministic rounding and negative grid rounding.

### 9.2 Room edges

| Side | Fixed coordinate | Interval | Canonical start → end | Inward normal |
|---|---|---|---|---|
| south | `y` | `[x, x+w]` | west → east | north `(0, 1)` |
| north | `y+d` | `[x, x+w]` | west → east | south `(0, -1)` |
| west | `x` | `[y, y+d]` | south → north | east `(1, 0)` |
| east | `x+w` | `[y, y+d]` | south → north | west `(-1, 0)` |

The outward normal is the negation of the inward normal.

### 9.3 Adjacency

Corner-only contact is not adjacency. Exact collinearity plus positive shared length returns a record:

```lua
{
  a_side = "east",
  b_side = "west",
  axis = "y",
  fixed_mm = 5000,
  start_mm = 1000,
  finish_mm = 4000,
}
```

The full connected door aperture must lie within `[start_mm, finish_mm]`. Partial room-edge adjacency is valid if it covers the complete aperture.

### 9.4 Alignment operations

Use unambiguous internal names:

- `align_min_x` / left edges;
- `align_max_x` / right edges;
- `align_min_y` / south edges;
- `align_max_y` / north edges;
- `align_center_x` / vertical centre-lines;
- `align_center_y` / horizontal centre-lines;
- `place_north`, `place_east`, `place_south`, `place_west`;
- directional placement with a non-negative gap;
- `snap_corner(moving_corner, reference_corner)` for all four corners.

The moving room changes; the reference stays fixed. East/west placement aligns south edges. North/south placement aligns west edges. Functions return a proposed origin plus rounding/overlap/connection diagnostics and never mutate inputs.

Gaps are non-negative in normal UI. Creating overlap is a separate explicit forced transform, never an accidental negative gap.

### 9.5 Automatic room placement

For a non-empty plan:

1. Generate candidate origins immediately north/east/south/west of every room using the cross-axis rules.
2. Add grid-aligned candidates around the current plan bounding box.
3. Discard positive-area overlaps.
4. Rank by distance to the current cursor world point (or plan centre), then distance to world origin, direction priority east/north/west/south, reference model order, and coordinates.
5. Choose the first deterministic candidate.

An empty plan uses world origin. Failure within the configured search radius becomes an actionable error and offers exact placement.

### 9.6 Snapping

The pure snap function accepts an explicit tolerance in millimetres and an action parameter `bypass`; it reads no global state.

Movement procedure:

1. Apply the requested integer delta.
2. Generate the moving object's X/Y features.
3. Generate eligible target features.
4. Exclude the moving object and all objects moving with it.
5. Build correction candidates inside tolerance.
6. Rank by smallest screen-equivalent distance, semantic priority, target ID, feature name, and signed delta.
7. Apply independent deterministic X/Y corrections.
8. Round any impossible half-millimetre result under the lattice rule and report residual.
9. Run the action's collision policy before commit.

Target scopes:

- Room: other room edges, corners, centres, and grid; exclude its children.
- Furniture: owning-room edges/centres, other furniture edges/centres, door edges, and grid.
- Door offset: wall endpoints, shared-edge endpoints, grid projections, and other door endpoints.
- Exact numeric edits never snap.

Viewport code converts `snap_tolerance_cells` to world X/Y tolerances and caps them by `snap_max_distance_mm`. Grid rounding must work correctly for negative coordinates.

### 9.7 Door aperture and swing geometry

For a door:

1. Compute canonical aperture endpoints `p0` and `p1` from owner side, offset, and width.
2. The hinge point is `p0` for `start` and `p1` for `end`.
3. The closed leaf vector points from the hinge to the other endpoint.
4. `owner` selects the owner's inward half-plane.
5. `connected` or `outside` selects the owner's outward half-plane.
6. Choose the signed rotation whose initial motion enters that half-plane.
7. Rotate the closed vector by `open_angle_deg` to obtain the open leaf endpoint.
8. The swept area is the filled circular sector between the closed and open leaf, radius `width_mm`.

This is implemented once and tested for every `4 sides × 2 hinges × 2 valid swing sides`, plus representative angles 1, 45, 90, 135, and 180 degrees.

Door-sector/rectangle collision uses:

- AABB broad phase;
- hinge inside rectangle;
- rectangle corner inside sector;
- either radial boundary intersecting rectangle;
- circular arc intersecting a rectangle edge within the sweep angle.

Door-sector/wall collision applies the same point/radial/arc predicates to wall segments. Exclude the door's own aperture interval, its designed hinge/jamb endpoint contact, and the validated opposite aperture contribution; warn only when the sweep crosses/touches another wall portion beyond that exclusion.

Door/door interference uses AABB/circle broad phase followed by open-leaf segment intersection, leaf-versus-sector tests, and filled sector/sector boundary/interior intersection. Exact designed self contacts are excluded. For distinct doors, a non-excluded tangent leaf/sector contact is still a clearance warning; positive opening overlap remains the stronger layout error.

Transient trigonometry may use floating point. Translate sector predicates to hinge/local integer coordinates before conversion so a huge world origin never inflates error, and never write floats back to persisted coordinates. Centralize comparisons under one local-scale/machine-precision epsilon such as `max(1e-7 mm, 128 * 2^-52 * max(1, radius, local segment spans))`, with the hard local-dimension ceiling above; use the same inclusion/exclusion policy on every platform/snapshot and never scatter ad hoc epsilons. Tangent contact outside designed hinge/jamb exclusions counts as a warning for door clearance.

### 9.8 Geometry edit consequences

- Moving a room moves its local furniture and owner-anchored doors in world space without rewriting child-local coordinates.
- It does not move doors owned by another room or silently repair broken adjacency.
- A move/alignment that breaks a currently valid connected door is blocked by default and can be forced into an invalid draft after an explicit summary.
- Room resizing keeps the southwest origin fixed. Furniture centres and door offsets remain unchanged; resulting invalid containment/apertures are reported. Impossible door aperture geometry blocks the resize unless the operation is explicitly forced into a layout-error draft.
- Furniture resizing keeps its centre fixed.
- Door width editing keeps its canonical offset fixed.

---

## 10. Validation model

Validation is pure, deterministic, non-mutating, and cached by `(model revision, effective validation-limit/config generation)`. It returns structured diagnostics rather than strings alone:

```lua
{
  code = "FURNITURE_OUTSIDE_ROOM",
  severity = "error",
  object = { kind = "furniture", id = "furniture-sofa-1" },
  related = { { kind = "room", id = "room-living" } },
  message = "Sofa extends 120 mm beyond the east room boundary",
  details = { side = "east", overflow_mm = 120 },
  fix = nil,
}
```

Diagnostics are sorted deterministically by severity, code, primary object type, model order, and ID. Every message includes the failing ID where one exists. The UI never parses the human message to navigate; it uses structured object references.

### 10.1 Structural failures

These prevent a session/action commit and can never be force-saved:

- invalid JSON/UTF-8, duplicate keys, unsafe limits, or non-object root;
- missing/wrong `format`, missing/non-integral/unsupported `schema_version`, or wrong units;
- invalid JSON types or unsafe/non-integer known geometry fields;
- missing required collections;
- non-positive primitive dimensions/steps/door width;
- invalid ID syntax, duplicate global IDs, or impossible typed reference shape;
- unsupported object kind/shape or furniture rotation;
- invalid enum values;
- JSON codec/migration failure.

Actions validate their parameters before copying/committing, so normal editing cannot create these states.

### 10.2 Layout errors

These are structurally representable but block normal save:

| Code | Meaning |
|---|---|
| `INVALID_REFERENCE` | A syntactically valid room/door/entity reference names a missing entity or an entity in the wrong collection. Catalogue `template_id` misses are explicitly excluded and use `TEMPLATE_UNRESOLVED`. A non-string/impossible reference shape is structural. Loaded drafts may report this; UI actions do not create it. |
| `ROOM_OVERLAP` | Two room rectangles have positive-area intersection. |
| `PLAN_LIMIT_EXCEEDED` | Geometry exceeds configured user-local plan bounds but remains below hard arithmetic limits. |
| `FURNITURE_OUTSIDE_ROOM` | Rotated footprint is not contained, boundary-inclusive, by its owner. |
| `FURNITURE_OVERLAP` | Two furniture footprints overlap with positive area, including across forced-overlapping rooms. |
| `DOOR_OUTSIDE_EDGE` | Door aperture is outside its owner segment. |
| `DOOR_OPENING_OVERLAP` | Global physical opening intervals overlap positively, including opposite owners. |
| `DOOR_CONNECTION_INVALID` | Claimed connected room lacks the opposite collinear shared interval covering the aperture. |
| `DOOR_CONNECTION_MISSING` | Door is marked exterior/unconnected although another room's opposite shared edge covers the complete aperture. |
| `DOOR_EXTERIOR_OBSTRUCTED` | An exterior aperture partially overlaps, or is ambiguously covered by multiple, opposite room edges. |
| `DOOR_SWING_TARGET_INVALID` | `opens_into` is incompatible with exterior/interior connection state. |

### 10.3 Warnings

Warnings do not block save:

| Code | Meaning |
|---|---|
| `DOOR_SWING_FURNITURE` | Swept door sector intersects furniture. |
| `DOOR_SWING_WALL` | Door sweep crosses a non-aperture room boundary. |
| `DOOR_SWING_DOOR` | Two door sweep sectors/leaf paths interfere. |
| `TEMPLATE_UNRESOLVED` | Explicit furniture geometry is valid but its catalogue reference is unavailable. |

`ALIGNMENT_ROUNDED` is transient action/history metadata, not a model-validation result. `LABEL_NOT_RENDERED` is a viewport-revision render diagnostic, not a model-validation result. They use the same structured presentation style but are cached/cleared by their own action or render context so they cannot leak across unrelated revisions/viewports.

### 10.4 Validation scope and complexity

- Validate furniture in global coordinates, not only within matching `room_id`, so forced room overlap is fully diagnosed.
- Validate door openings by normalized global wall coordinates and intervals.
- Keep well-typed orphaned entities navigable in the textual validation list. Scene extraction skips only the geometry that cannot be safely placed because its owner is missing and continues rendering valid entities; it never invents a fallback owner/location.
- Use AABB broad phases before sector tests.
- Initial algorithms may be clear `O(R² + F² + D² + D·F)` loops. At the target size this is acceptable and easier to verify.
- Cache derived world geometry and results by history revision.
- Incremental validation may be added only after full validation is correct and benchmarked.

### 10.5 Save behavior with diagnostics

- Warnings: save normally; summarize in status/notification.
- Errors: interactive save offers `Review errors`, `Save invalid draft`, or `Cancel`; noninteractive guard/autosave refuses. `:RoomPlanSave!` pre-authorizes the same layout-invalid-draft choice.
- Structural failures: no write and no force option.
- Conflicts: no write and no bang bypass. Use the separate conflict-resolution flow.
- Autosave: runs only with zero errors and zero conflict.

Validation never adjusts geometry. Any future fix action must name its proposed changes, preview them, and commit as a normal undoable action.

---

## 11. Model actions and history

### 11.1 Action boundary

`commands.lua` registers Ex commands; it is not the model command layer. Pure mutations live in `actions.lua` and focused action modules.

Conceptual interface:

```lua
actions.apply(model, action, context)
  -> new_model, {
       label = "Move furniture Sofa east 100 mm",
       touched = { { kind = "furniture", id = "furniture-sofa-1" } },
       diagnostics = {},
       metadata = {},
     }
  | nil, structured_error
```

Every action:

1. resolves stable IDs against the supplied revision;
2. validates all parameters;
3. deep-copies the tagged JSON model;
4. changes only the copy through model helpers;
5. validates structural invariants;
6. applies its layout blocking/force policy;
7. either returns the complete new model or no change;
8. returns one successful model/result to the controller; the controller inserts exactly one history node. The pure action itself never mutates session history.

UI/session code owns revision checks, history insertion, validation caching, dirty guards, and redraw scheduling. UI code never assigns nested model fields directly.

### 11.2 Snapshot history

Each successful revision stores:

```text
revision_id    monotonic session-local integer
label          human-readable semantic operation
model          complete immutable-by-convention tagged model snapshot
touched        stable object references
metadata       optional rounding/force/placement details
```

Rules:

- Default limit: 100 undo nodes, configurable within a safe range.
- Enforce both node and memory budgets: default 64 MiB of estimated tagged-model history per session and 256 MiB globally. Use a cycle-safe deterministic size estimator. Trim oldest non-current nodes/LRU inactive-session history first, never the current model; if a single large model prevents retaining one undo node, keep the current node, report the reduced history, and remain correct.
- Initial load is a node.
- The initial node is a durable savepoint only when its selected plan payload/document semantically matches durable disk state and normalization/migration made no change. A plan payload that exists only in a pre-modified buffer gets `durable_savepoint_revision_id = nil`; unrelated outside-block Norg edits remain the source buffer's separate modified concern. Normalization/migration also sets a nil savepoint, keeps the original source revision for conflict checks, marks the guard dirty, and requires an explicit save to establish the first current-schema savepoint.
- Undo moves to the previous node; redo moves forward.
- A new successful action after undo drops the redo branch.
- Failed/cancelled/no-op actions create no node and do not drop redo.
- Save records the current `revision_id` as the durable savepoint and does not remove nodes.
- `model_dirty = current_revision_id ~= durable_savepoint_revision_id`.
- Undoing exactly to the savepoint clears model dirty.
- If the saved node is trimmed/branched away, the session remains dirty until another successful save.
- Reload installs a new initial node and clears prior undo/redo.
- View state is not stored in history.

The model is small enough that full copies prioritize correctness and unknown-field preservation. Benchmark copy time/memory against the large fixture before considering record-level patches.

### 11.3 Required actions

- `add_room`, `move_room`, `resize_room`, `align_room`, `duplicate_room`, `delete_room_cascade`, `rename_room`;
- `add_furniture`, `move_furniture`, `resize_furniture`, `rotate_furniture`, `duplicate_furniture`, `delete_furniture`, `rename_furniture`, `change_furniture_template`;
- `add_door`, `edit_door`, `toggle_door_hinge`, `toggle_door_swing`, `delete_door`, `duplicate_door_from_draft`;
- `add_custom_template`, `edit_custom_template`, `delete_custom_template`;
- `edit_metadata`, `edit_plan_settings`;
- explicit forced variants represented by an action option and recorded in history metadata.

### 11.4 Duplication semantics

- Furniture: clone with a new ID and translate by one normal step east and one normal step north. An overlap is allowed as a visible invalid draft. Select the clone.
- Room: clone only the room entity with a new ID, no referenced furniture/doors, and use automatic non-overlapping placement. This keeps “duplicate selected object” literal and avoids surprising relationship cloning.
- Door: open the Add/Edit Door draft seeded from the selected door. It cannot commit until its proposed aperture is non-overlapping and structurally valid.
- Custom template: clone with a new `custom:*` ID and “copy” suffix.

### 11.5 Deletion semantics

- Furniture/door deletion prompts according to confirmation settings and is one action.
- Room deletion first computes every direct/indirect dependant: local furniture, owner doors, and other-owner doors whose `connects_to_room_id` is the room. The confirmation shows counts and IDs. Acceptance deletes all in one history node; cancellation is a no-op.
- Custom template deletion is blocked while referenced; the UI lists referencing furniture.
- IDs are never reused automatically during the same session merely because an entity was deleted.

### 11.6 Move/edit modes

- Exact editing gathers a complete draft and commits once.
- Keyboard movement commits one action per keypress.
- Snapping information is stored in history metadata for inspection but not as extra model fields.
- Forced actions include the diagnostics the user accepted.
- An edit that produces the byte/semantic equivalent model is a no-op and creates no history entry.

---

## 12. Storage architecture

### 12.1 Adapter interface

Adapters expose a consistent boundary:

```lua
adapter.detect(context) -> match | nil
adapter.load(context) -> document, source_revision, locator, diagnostics
adapter.prepare_save(session, document) -> patch | error
adapter.commit(context, patch, expected_revision) -> new_revision | conflict/error
adapter.initialize(context, document) -> source_revision, locator | error
```

`detect`, extraction, serialization, and `prepare_save` are pure where possible. `commit` performs the last source re-read/re-scan and is the only mutation boundary.

### 12.2 Source authority

- If a source has a loaded Neovim buffer, that buffer—including unsaved edits that predate RoomPlan—is authoritative.
- Never read disk behind an authoritative modified buffer and overwrite it.
- Canonical writable source encoding is UTF-8. Buffers with `fileencoding` empty/`utf-8` are supported in place, including a pre-existing UTF-8 BOM tracked by buffer options. A different source encoding may be parsed from Neovim's logical text into a read-only RoomPlan session, but in-place RoomPlan save is refused with conversion/UTF-8 Save As guidance; never silently transcode the surrounding note.
- A second open of the same buffer/canonical path reuses/focuses its existing session.
- If Neovim has two loaded buffers for the same canonical path, the already session-attached buffer remains authoritative. A byte-identical clean alias may redirect/focus it; divergent or modified aliases produce a duplicate-buffer conflict and are never silently chosen.
- Detached standalone paths are used for new Save As targets or programmatic sources that have no loaded buffer.
- Existing Norg destinations are always loaded into a buffer before modification.

### 12.3 Source revisions

Use content hashes, not only time/size:

- Standalone buffer: exact whole logical buffer text, changed tick as fast-path, file stat/disk state for durable write checks.
- Detached standalone: exact raw bytes plus existence/type state.
- Norg buffer: exact selected opener identity, exact selected payload text, unique-block state, and changed tick as fast-path. Unrelated edits already present in the authoritative buffer are allowed. Separately retain the last durable whole-file raw fingerprint/stat so an external disk edit anywhere in the note is detected before the plugin patches a stale buffer.
- Detached Norg is not a normal editing path in v1; load it as a buffer.

Use `vim.fn.sha256` or an isolated compatibility wrapper for content fingerprints. The raw comparison remains authoritative even if a hash matches in tests/debug mode.

### 12.4 Dirty and persistence state

Track these independently:

```text
model_dirty             current history node differs from durable savepoint
buffer_payload_revision_id history revision currently serialized in the source buffer, or nil
durable_source_matches_savepoint whether current disk/source still contains the recorded savepoint
source_buffer_modified  Neovim buffer has unsaved changes
source_conflicted       selected source content differs from expected revision
retained_model_at_risk  current/old model no longer exists durably at active source
pending_disk_write      a recognized plugin-staged buffer payload is not durably written
session_requires_protection model_dirty OR pending/staged divergence OR retained_model_at_risk
```

The buffer sync state is revision-valued, not merely Boolean. After a failed write of revision 2, undoing to revision 1 or editing revision 3 leaves `buffer_payload_revision_id = 2`, so the next save knows it must replace the recognized staged payload and Close/quit remain protected. Action/undo/redo never pretend the source buffer followed the history cursor.

An external payload/disk change sets `durable_source_matches_savepoint = false`, `source_conflicted = true`, and `retained_model_at_risk = true` when the retained model no longer exists at the active source, even if the history cursor still equals the old savepoint. The guard remains modified until Reload, Save As, confirmed overwrite, or explicit session discard resolves it. A whole-note Norg disk conflict whose plan payload is proven semantically unchanged may block save without marking the model itself at risk.

Status must not collapse these into one `*`. Example:

```text
[MODEL DIRTY] [STAGED r2] [SOURCE MODIFIED] [CONFLICT]
```

### 12.5 Buffer-backed save transaction

For standalone or Norg source buffers:

1. Revalidate model and apply save-invalid policy.
2. Serialize completely in memory.
3. Re-locate/re-read current buffer source and compare the expected payload/document revision; also compare the durable whole-file fingerprint for buffer-backed files before patching. An outside-block edit already in the Norg buffer is preserved, but an external disk divergence means the buffer is stale and stops the transaction before mutation.
4. If conflicted, stop before mutation and launch conflict recovery.
5. Replace the complete standalone document or only the Norg payload with one buffer API call and record `buffer_payload_revision_id = current_revision_id` for that exact recognized staged payload.
6. Invoke a normal, non-forced write in the source buffer so `BufWritePre`, encoding, EOL, `BufWritePost`, and write errors apply.
7. After the write returns, re-read and strictly parse the actual buffer, inspect its `modified` state, and independently read/decode/parse/fingerprint the durable file bytes when it is a normal local file. Decode only the supported UTF-8/BOM and actual `fileformat` representation into logical text before semantic comparison; raw-byte preservation checks remain separate.
8. Confirm the buffer still represents the intended model semantically, is unmodified, and the durable file contains the corresponding intended payload/document. A `BufWritePre` formatter is acceptable only because its result was included in the write; a `BufWritePost` mutation normally leaves the buffer modified and therefore cannot establish a savepoint until another successful write.
9. Only after both authoritative buffer and durable file verification set the history savepoint and refresh buffer/disk source revisions.

Never use `:write!`, suppress disk-change checks, or set `modified=false` manually on the authoritative source buffer. The disposable canvas and internal guard manage their own flags under their separate contracts.

If step 6 fails after the buffer patch:

- retain the updated authoritative buffer;
- set `pending_disk_write` and keep the guard dirty;
- update the expected payload revision so retry does not treat the plugin's own patch as a conflict;
- skip re-patching if the current payload already equals the intended serialization;
- do not mark a durable savepoint until the write succeeds.

Undo/redo/new actions after staging do not alter `buffer_payload_revision_id`; they merely make it differ from `current_revision_id`. A later save may safely replace that exact recognized staged payload after rechecking it, while an unrecognized manual payload edit clears the revision ID and becomes a conflict. Successful durable verification sets the savepoint to the saved revision, marks the durable source match true, and clears pending state.

If a durably written hook changes only formatting but the parsed model is equal, accept it and fingerprint the actual payload/bytes. If a hook changes model semantics, leaves post-write modifications, creates malformed data, or makes buffer and disk diverge, keep the session dirty/pending/conflicted as appropriate and report the hook-induced divergence.

### 12.6 Detached standalone atomic write

This path is only for an expected-absent new/unloaded standalone destination. Every existing destination replacement is first loaded and uses the buffer-backed writer; do not pretend check-then-rename is compare-and-swap.

1. Serialize complete canonical bytes in memory.
2. Verify the target is absent and the parent is an eligible directory immediately before writing.
3. Reject an existing path of any type; a race-created file is never replacement-eligible here.
4. Create a unique same-directory temporary file using exclusive creation.
5. Apply documented safe new-file permission bits subject to the user's umask.
6. Loop until all bytes are written; handle partial `uv.fs_write` results.
7. `fs_fsync` and close the temp file.
8. Recheck absence after any asynchronous confirmation.
9. Finalize with a same-filesystem no-replace primitive (for example, atomically hard-link the fully written temp inode to the destination and fail on `EEXIST`) and then remove the temp name; never use ordinary overwriting rename for this case. If the platform cannot provide safe no-replace creation, fail with the race-created/original path intact and clean up the temp.
10. Best-effort fsync the parent directory where supported.
11. Clean up the temp on every failure and report cleanup failures separately.

Never implement a Windows fallback that unlinks a destination. Account explicitly for the check/finalize TOCTOU window: an unexpected newly created destination must survive and cause failure, not be overwritten. Existing replacements always use the buffer-backed path.

Detached standalone output uses UTF-8 without BOM, LF, and exactly one final newline. Supported buffer-backed output respects `fileformat`, a pre-existing UTF-8 BOM, `endofline`, and write hooks; non-UTF-8 in-place writing is refused as described above.

### 12.7 Standalone adapter

- Detection precedence is deterministic: a named `.roomplan.json` path selects standalone JSON; a named `.norg` path selects Norg regardless of incidental filetype; only an unnamed or unrecognized-suffix buffer falls back to `filetype=norg`. If none match, require an explicit supported Save As path instead of guessing.
- Extension match is `.roomplan.json`; case-insensitive on Windows.
- Initialization is allowed for nonexistent or empty/whitespace-only targets.
- `RoomPlanInit` for a nonexistent standalone path atomically creates/writes the canonical empty document immediately, then opens a clean session. For an authoritative empty/whitespace loaded standalone buffer, it inserts the canonical document and performs the normal buffer-backed write. If that write fails after insertion, retain the named modified buffer/session with a nil savepoint and guard protection so retry or Save As is possible; never claim the file was created durably.
- Nonempty malformed content is never overwritten by `RoomPlanInit` (which has no bang); use a different Save As path or fix the source explicitly.
- Loading a current modified buffer uses its text.
- Saving replaces the complete logical document in one buffer operation.
- `format` and schema are still verified; extension alone is not trust.

### 12.8 Norg block syntax

The Norg adapter matches a loaded buffer whose `filetype` is `norg` or whose path ends in `.norg` (case-insensitive on Windows). An unnamed `norg` buffer may be initialized and edited, but durable save requires assigning a name through normal buffer naming or RoomPlan Save As.

New block:

```norg
* Floor plan

@code json roomplan.nvim
{
  "format": "roomplan.nvim",
  "schema_version": 1,
  "units": "mm",
  "metadata": {
    "name": "My flat",
    "notes": ""
  },
  "settings": {
    "grid_mm": 100,
    "fine_step_mm": 10,
    "normal_step_mm": 100,
    "coarse_step_mm": 500,
    "default_door_width_mm": 900,
    "default_wall_thickness_mm": 120
  },
  "rooms": [],
  "doors": [],
  "furniture": [],
  "custom_templates": [],
  "extensions": {}
}
@end
```

The top-level `format` remains canonical. The opener marker is a recovery/discovery aid.

### 12.9 Norg discovery scanner

Implement a line-state scanner following the Norg tag grammar relevant here:

- recognize tag openers only at logical line start after optional whitespace;
- split tag name and escaped space-separated parameters;
- while inside a verbatim ranged tag, ignore nested-looking openers;
- recognize the matching exact-prefix `@end` delimiter at line start;
- retain opener/closer ranges, indentation, and raw payload logical lines;
- reject unterminated marked blocks with a source location;
- operate on Neovim logical lines and preserve the buffer's ordinary LF/CRLF `fileformat` on normal writes. Raw detached/pre-load byte inspection detects and rejects unsupported mixed, CR-only, or form-feed line endings when preservation is still knowable. An already loaded buffer has lost per-line terminator distinctions, so the plugin must document that Neovim may already have normalized a mixed-ending file rather than falsely claiming it detected one.

Discovery order:

1. Ask a tested Tree-sitter query for verbatim-tag candidates when the Norg parser is available.
2. Run the scanner to determine safe exact bounds and/or as fallback.
3. Identify every explicit `@code json roomplan.nvim` block. Any malformed marked block is a fatal plan-block error; more than one marked block is fatal ambiguity.
4. Independently parse legacy unmarked `@code json` blocks and collect every valid object root whose `format` is `roomplan.nvim`.
5. Combine marked and legacy valid candidates. Exactly one total candidate loads; more than one total candidate is fatal ambiguity, including one marked plus one legacy block. The marker aids identification/recovery but never overrides the one-plan-per-source invariant.
6. If a malformed legacy JSON block contains a lexical `roomplan.nvim` format marker, treat it as a damaged possible plan and refuse initialization.
7. Other malformed JSON blocks are reported before initialization; the user must explicitly confirm creating a new marked block because one could be an unrecognizable old plan.

For a clean zero-plan Norg result, `:RoomPlanOpen` offers `Initialize marked RoomPlan block` or `Cancel` and performs no edit until initialization is affirmatively chosen. `:RoomPlanInit` enters the same safety checks directly. Malformed, ambiguous, marked, or suspected damaged cases never use the clean-zero shortcut.

If Tree-sitter and the scanner disagree, do not guess. Use the scanner only when it yields one conservative well-formed range and warn; otherwise abort with diagnostic details. Tests pin representative grammar versions/fixtures without importing Neorg internals.

### 12.10 Norg initialization and replacement

- With exactly one top-level exact `* Floor plan` heading, insert a marked block at the end of that section with appropriate blank lines.
- With multiple exact headings, show their line numbers/text context and require an explicit heading choice or `Append a new Floor plan heading`; cancellation changes nothing. Never choose first/last silently.
- With no exact heading, append a new `* Floor plan` heading and marked block, respecting whether the buffer has a final line.
- Initialization is one buffer edit and normal undo step.
- Unlike standalone path creation, Norg initialization does not automatically write the note: it leaves the source buffer modified and the new model undurable until explicit `RoomPlanSave`, because initializing must not silently persist unrelated note edits.
- Saving re-locates the unique block; never trust stale line numbers.
- Compare exact current payload text with the base payload. Outside-block edits do not conflict.
- Replace only content between opener and closer. Preserve both delimiter lines and their indentation.
- Serialize JSON with payload indentation derived from the opener's indentation plus the canonical JSON indentation.
- Preserve all unrelated logical buffer text exactly.
- A normal Neovim write may normalize encoding/EOLs or invoke user hooks; document this limitation. Byte-for-byte disk preservation is guaranteed only in fixtures using a stable encoding/EOL/no-mutating-hook setup.

### 12.11 Save As

- Destination suffix determines adapter; unsupported suffix is rejected before mutation.
- Resolve the destination through the session registry before any prompt/write. If another live session owns that canonical source, refuse replacement and offer to focus/close that session or choose another destination; never merge or steal its source.
- New `.roomplan.json`: atomic create, then attach/load the resulting source buffer.
- Existing `.roomplan.json`: replacement eligibility requires an ordinary regular file containing a valid supported RoomPlan document (or empty/whitespace initialization target). Require overwrite confirmation, recheck after callback, then use buffer-backed save. Malformed, unsupported, or non-RoomPlan content remains untouched even with bang.
- New `.norg`: create a minimal note plus marked block through a buffer, then write normally.
- Existing `.norg`: open/use its authoritative buffer and run normal discovery. With zero plan blocks, initialize after confirmation; with one valid plan block, require an explicit “replace this plan payload” confirmation and last-moment recheck; with ambiguous/malformed/suspected damaged blocks, fail safely. Never overwrite the note wholesale.
- On successful Save As, the session changes source/adapter, refreshes registry identity, and records the current revision as durable savepoint.
- On any failure, the original source/session association remains active.
- Cross-adapter Save As serializes the same model; it does not mutate model geometry.
- Paths with spaces, Unicode, Windows drive letters, and UNC forms use path APIs and file completion, never string-built Ex commands.

### 12.12 Conflict resolution

On conflict, offer:

1. **Review source** — focus source at the standalone document or Norg block.
2. **Reload** — replace model after the `session_requires_protection` confirmation; clears history when it replaces the model.
3. **Save As** — preserve both versions.
4. **Overwrite current payload** — available only for a conflict inside the authoritative buffer when there is no unresolved whole-file external disk divergence and the changed active payload is still a structurally parseable supported RoomPlan document. Require an explicit second confirmation, then re-read/re-locate/recheck before replacing. For Norg, preserve all current outside-block buffer text. If the payload is malformed/unsupported or the loaded buffer is stale against disk, omit this option; Save As or fix/checktime/reload are the safe recovery paths.
5. **Cancel** — no mutation.

There is no automatic merge in v1. `:RoomPlanSave!` does not select overwrite. Every callback uses the session/workflow token and must harmlessly expire if the source changes again.

If conflict is an external whole-file disk divergence outside a stale loaded Norg buffer, payload overwrite is unavailable because it would discard unseen note text. Offer review/checktime/reload, Save As, or cancel; incorporate the external note into the buffer before any later plan commit.

---


## 13. Session and lifecycle architecture

### 13.1 Session registry

`state.lua` owns a registry keyed by canonical source identity and a secondary map for canvas/source/guard buffer handles.

Identity rules:

- Named buffer-backed sources are keyed primarily by normalized canonical path; buffer handles are secondary attachments. Unnamed sources are keyed by buffer identity plus adapter type.
- Existing paths use `fs_realpath` where practical.
- Nonexistent paths normalize the real parent plus basename.
- Windows comparisons account for case-insensitive suffix/path behavior without lowercasing user-visible paths.
- Opening the same authoritative buffer or canonical named path always reuses the session even if the file was reached through an alias or a second loaded buffer.
- If alias resolution is uncertain, prefer refusing a second writable session over risking concurrent writes.

Command resolution order:

1. session attached to the current canvas/inspector/list buffer;
2. session attached to the current source buffer;
3. the sole live session;
4. if multiple remain, open a session list instead of guessing;
5. otherwise fail with `No RoomPlan session is active; run :RoomPlanOpen or :RoomPlanInit`.

### 13.2 Session record

Conceptual state:

```lua
{
  id = "session-1",
  source = {
    adapter = "json",
    path = "/absolute/flat.roomplan.json",
    bufnr = 12,
    locator = {},
    revision = {},
  },
  history = {},
  current_revision_id = 1,
  durable_savepoint_revision_id = nil,
  durable_source_matches_savepoint = false,
  buffer_payload_revision_id = nil,
  validation = {},
  selection = nil,
  selection_cycle = {},
  viewport = {},
  mode = "NAV",
  snap_enabled = true,
  canvas = { bufnr = nil, winid = nil },
  inspector = { bufnr = nil, winid = nil },
  guard_bufnr = 20,
  workflow = { generation = 0, kind = nil },
  redraw_scheduled = false,
  source_conflicted = false,
  retained_model_at_risk = false,
  pending_disk_write = false,
}
```

The nil/false savepoint values above show the conservative pre-verification state; a clean durable load sets them to revision 1/true as defined in section 11.2. The model is obtained from the current history node. No persisted table stores Neovim handles or revision metadata.

### 13.3 Guard buffer

Each live session creates an unlisted hidden buffer:

```text
buftype=acwrite
bufhidden=hide
swapfile=false
modeline=false
name=roomplan://guard/<session-id>
```

Its `modified` flag mirrors `session_requires_protection`, not only history-node inequality. It therefore stays true for staged/pending buffer payloads and unresolved conflicts where the retained model no longer matches the source. A buffer-local `BufWriteCmd` attempts a noninteractive RoomPlan save:

- valid, conflict-free model: save synchronously and clear modified on success;
- layout errors: fail and tell the user to use `:RoomPlanSave!` deliberately;
- conflict/write failure: fail without clearing modified.

This means `:wall` can save conflict-free valid RoomPlan sessions and ordinary `:qall` sees at-risk work. If both the ordinary source buffer and model are dirty, `:wall` may write the source once before reaching the guard and the guard may then patch/write it again; document this possible duplicate `BufWritePre`/`BufWritePost` side effect, test it on every supported version, and recommend direct `:RoomPlanSave` for side-effectful hooks. The guard content is never the model and is not user-edited. Local Neovim 0.12.4 spikes confirmed that a hidden modified `acwrite` buffer blocks ordinary `:qall` with `E37`/`E162` and participates in `:wall`; the supported-version child-process tests remain mandatory.

While protection is active, ordinary guard deletion is blocked by its modified flag. Any non-semantic guard `BufWipeout`—clean or forced—recreates the guard on the next safe scheduled turn while the session remains live and the editor is continuing (and warns for an at-risk session); alternatively a clean session may recreate it lazily before first becoming at risk. Only `RoomPlanClose[!]` marks intentional guard teardown. Detect any ordinary or forced editor shutdown and never schedule guard recreation during exit.

Tests must prove the chosen buffer settings protect ordinary exit across 0.10/0.11/0.12. If a supported Neovim version does not treat the hidden modified guard as expected, add a documented synchronous `QuitPre` safety check as a compatibility fallback; never rely on an asynchronous prompt to pause an already-running quit.

### 13.4 Canvas lifecycle

- `:RoomPlanOpen` creates or focuses a canvas for the resolved source/session.
- Reopening the same source never creates a second model/history.
- One canvas buffer may appear in only one window. A second view focuses the existing window rather than sharing a raster buffer across differently sized windows.
- `q`, raw window close, `:bdelete`, or `:bwipeout` of the disposable canvas removes the view; the registry/model/guard survive.
- `:RoomPlanHide` deliberately removes the canvas without prompting because it discards no model state.
- Hiding closes the canvas split/tab when another normal window remains. If it is the last closable window, replace it with the still-valid source buffer (or a fresh ordinary empty buffer) before wiping the canvas; never fail with `E444` or expose the guard buffer as the editing view.
- Reopening recreates the buffer from session state and restores selection/viewport where practical.
- `:RoomPlanClose` is the semantic session close. If `session_requires_protection`, asynchronously offer Save, Discard session, or Cancel with a summary of model/staged/conflict state. Only after a successful choice does it remove session-owned UI and guard buffers.
- “Discard session” discards in-memory model/history protection but never silently rewrites the authoritative source buffer. If a failed save already staged a payload there, the prompt says that the modified source buffer will remain intact and under native buffer undo/quit protection.
- `:RoomPlanClose!` invalidates pending workflows and explicitly discards unsaved session/model state under the same source-buffer-preservation rule. It cannot overwrite a source or silently revert an already patched buffer.
- Clean close destroys the session immediately.
- `:qa!` remains an explicit force escape hatch under normal Neovim semantics.

### 13.5 Source buffer lifecycle

- Source buffer unload does not destroy any live session, including an otherwise clean-history session retaining a model-at-risk conflict. Reattach by canonical path when reloaded.
- Native source-buffer modified protection remains in force for unrelated edits.
- `BufFilePost` freezes RoomPlan writes and recomputes adapter/canonical identity. A same canonical path updates display metadata only. A different path from `:file` becomes `source_rebind_pending`: retain the old source revision/savepoint and require an explicit Adopt as Save As, return to old source, or cancel decision. If Neovim `:saveas` already durably wrote the current model to a supported-suffix new path, verify its bytes/model and registry uniqueness before adopting it as an external Save As/savepoint. Unsupported suffixes or collision with another live session are refused/left pending; never silently change adapter or steal another session's source.
- `BufWipeout` of a source records a detached/reloadable source state if the path exists; unsaved source text is already protected by Neovim.
- Source `TextChanged`/`TextChangedI` marks revision as needing recheck but does not redraw the canvas unless the selected plan payload changed or a reload is performed.
- Norg edits outside the block are permitted and do not make the model conflicted after payload comparison.
- A source payload edit made while the canvas is open marks conflict/stale status and blocks save until resolution.

### 13.6 Autocommands and reentrancy

Use one augroup and buffer/session-scoped callbacks for:

- `BufWipeout` / `BufUnload` cleanup bookkeeping;
- `BufFilePost` identity changes;
- `TextChanged`, `TextChangedI`, and buffer attach events as recheck hints;
- source `BufWritePost` to refresh the durable whole-file fingerprint after a verified user write. Outside-block-only Norg writes update the durable note revision without changing the plan savepoint; payload changes mark conflict. If the written payload exactly represents a recognized staged `buffer_payload_revision_id`, promote that revision to durable savepoint and clear pending protection. Plugin-initiated writes use the same verified path under the narrow reentrancy flag;
- `WinResized`/`VimResized` redraw scheduling;
- `ColorScheme` highlight relinking;
- `BufWinEnter` canvas option enforcement;
- `VimLeavePre`/`QuitPre` compatibility safety checks only if guard-buffer behavior requires them.

Callbacks may run under textlock/fast contexts. Schedule editor mutations when required. Protect intentional source/canvas updates with narrow per-session reentrancy flags; never broadly `pcall` and swallow programming errors.

---

## 14. Scene extraction and renderer

The renderer is split into a pure semantic scene, a pure logical rasterizer, and Neovim-specific canvas presentation.

### 14.1 Scene extraction

`scene/build.lua` consumes only the current model and validation output:

1. Convert room edges to normalized world segments with contributing room IDs.
2. Group collinear segments by orientation/fixed coordinate.
3. Partition/union overlaps while retaining contributor provenance.
4. Classify owner-edge-valid door apertures and whether each claimed shared connection is valid.
5. Subtract an owner-edge-valid aperture from the owner's wall contribution; subtract it from an opposite room contribution only for the one validated connected room. A missing/broken connection therefore leaves the opposite contributor visibly closed and annotated rather than inventing an interior opening.
6. Emit wall, room-interior, door hinge/leaf/arc/marker, furniture footprint/interior, label, dimension, grid/ruler, selection, and diagnostic primitives.
7. Compute a scene bounding box including invalid/outside furniture and open door sweeps.

World-space aperture subtraction before rasterization is mandatory. Erasing only the owner wall after drawing would allow the connected room's coincident edge to refill the doorway.

Scene primitives include stable provenance and hit references. Visual overlap never destroys semantic identity.

### 14.2 Layer order

Recommended semantic layers, low to high:

1. optional grid/rulers;
2. room interiors;
3. furniture interiors/outlines;
4. door swing areas/arcs;
5. structural walls;
6. door gaps, leaves, and hinges;
7. labels/dimensions;
8. validation annotations;
9. selection/cursor overlays.

Room/furniture “interior” layers add hit provenance and optional highlight/background roles; they never erase an existing glyph with a blank. Door swing arcs render above furniture so a collision remains visible, while structural walls and door leaves remain visually authoritative. Only structural wall segments merge into wall junction masks. Furniture outlines never create wall tees/crossings. Door leaves use their own glyph/style layer.

### 14.3 Viewport model

```text
world_left_mm
world_top_mm
mm_per_column
mm_per_row
```

Projection:

```text
screen_x = (world_x - world_left_mm) / mm_per_column
screen_y = (world_top_mm - world_y) / mm_per_row
```

Defaults begin at `100 mm/column` and derive `mm_per_row = mm_per_column * cell_aspect`; the default positive `cell_aspect = 2.0` therefore gives `200 mm/row`. Restored/custom viewport state preserves or re-derives that validated positive ratio. Neovim cannot detect physical terminal font aspect, so this is a user setting, not a claim of physical accuracy.

- Zoom multiplies/divides both scale values by the same factor and preserves their ratio.
- Zoom anchors the cursor world point when available, otherwise viewport centre.
- Fit includes all scene geometry plus a fixed cell margin.
- Empty-plan fit shows a stable region around world origin.
- Pan/zoom/fit never change model/history.
- Viewport values may be floating point because they are transient.

### 14.4 Logical raster grid

Each raster cell can hold:

```text
wall_direction_mask  N/E/S/W bits
visual primitives   ordered non-wall candidates
hit candidates      ordered stable object references
highlight roles     selection/error/warning/type
```

Raster steps:

1. determine drawable rows/columns from the actual canvas window after reserved header lines;
2. clip world primitives to the viewport;
3. project and deterministically round endpoints;
4. rasterize axis-aligned walls and rectangle edges;
5. use a line algorithm for door leaves and sampled display arcs;
6. merge wall masks into glyphs;
7. resolve visual layer priority without losing hit provenance;
8. place/truncate labels without overwriting critical wall/door cells;
9. emit complete one-cell-wide strings and byte-offset maps;
10. coalesce highlight spans and hit candidates.

Raster work is bounded by viewport cells, not world-plan extent.

### 14.5 Glyph sets

Unicode structural mapping covers all 16 direction masks, including:

```text
─ │ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼
```

Door/furniture/annotation glyphs may include single-width `╱`, `╲`, `·`, `●`, and similar characters only after display-width validation.

ASCII mode uses one-cell characters such as `-`, `|`, `+`, `/`, `\\`, `.`, `o`, and textual markers. It preserves hit testing and semantic information even if the drawing is less visually refined.

Every configured glyph must have Neovim display width exactly one. If any glyph fails, reject the custom set and fall back atomically to built-in ASCII with a health warning. `auto` mode may check UTF-8/display widths, but cannot guarantee the user's font; explicit `ascii` remains supported.

### 14.6 Byte columns versus display columns

Buffer cursor and extmark APIs use byte-oriented columns in important places; a Unicode box glyph occupies one screen cell but multiple bytes.

The renderer must:

- keep canvas backing text strictly addressable as one display column per logical raster cell; never insert a literal width-2 label grapheme into the backing grid because Neovim cannot place the cursor on its second screen cell;
- record a per-line mapping from logical cell column to byte offset;
- use `virtcol()`/display-width helpers to convert the current cursor to a logical cell;
- use recorded byte offsets for extmark ranges;
- sanitize/truncate labels by measured cluster display width, not byte count: retain validated width-1 clusters (including combining sequences whose total width is one), attach/omit standalone width-0 marks safely, and replace width-2, emoji/ZWJ, or otherwise non-addressable clusters in the canvas with a validated width-1 ASCII marker. The full exact label remains in inspector/object list;
- test CJK wide characters, combining marks, emoji-width edge cases, invalid UTF-8 rejection, and ASCII parity.

Never index a raster hit map directly with the second value of `nvim_win_get_cursor()` without conversion.

### 14.7 Canvas buffer and window

Create with `nvim_create_buf(false, true)` and enforce:

```text
buftype=nofile
bufhidden=wipe
swapfile=false
modeline=false
modifiable=false except during controlled redraw
readonly/display options appropriate to a canvas
wrap=false
number=false
relativenumber=false
signcolumn=no
foldcolumn=0
foldenable=false
list=false
spell=false
cursorline optional/configurable
```

Use a normal tab by default so the canvas has space. Split is configurable; floating canvas is optional after the main path works. Reserve one or two ordinary text lines at the top for accessible status/mode information rather than relying only on colour or a custom statusline.

Controlled redraw:

1. compute scene/raster outside modifiable state;
2. set `modifiable=true`;
3. replace all lines in one API call;
4. set `modifiable=false` and `modified=false` for the disposable view;
5. clear/apply namespace extmarks in contiguous runs;
6. restore logical cursor/selection visibility.

Canvas buffer undo is disabled/irrelevant; model history handles edits.

### 14.8 Header/status

Always show textual state similar to:

```text
RoomPlan | flat.roomplan.json | NAV | saved | zoom 1.00 | snap on
Selected: furniture “Sofa” [furniture-sofa-1] | errors 1 warnings 1
```

Possible flags include `MODEL DIRTY`, `SOURCE MODIFIED`, `PENDING WRITE`, `CONFLICT`, and `INVALID DRAFT`. Selection type/name/ID is textual so colour is never the sole indicator.

The status/inspector must expose the session's unambiguous source identity. The two-line canvas header may middle-abbreviate a long canonical path to fit, but the full canonical path (or explicit `unnamed norg buffer #N` identity) is always available verbatim in the inspector/help/status detail and object/session lists.

### 14.9 Labels and dimensions

- Room name first attempts the interior centre, then other free interior positions.
- Furniture label uses footprint centre and abbreviates by display width.
- Critical wall/door/hinge cells win over labels.
- Full exact labels are always available in inspector/list.
- Dimension labels may be toggled; area is derived and formatted, never persisted.
- At low zoom, omit a label and report a non-blocking render warning rather than corrupt geometry.

### 14.10 Low-resolution level of detail

A 900 mm door cannot always produce a literal visible gap when the fitted scale maps it below one cell. Define this honestly:

- if the projected aperture spans enough cells, render a true gap/leaf/arc;
- otherwise reserve the nearest wall cell for a distinct door marker with hit provenance;
- tiny furniture receives a minimum one-cell marker/hit target;
- inspector/status says exact dimensions regardless of zoom;
- zooming in reveals the full geometry.

The renderer never changes model dimensions to make them visible.

### 14.11 Hit testing and selection

Each logical cell stores an ordered candidate list. Priority:

1. door hinge/leaf/aperture;
2. furniture interior/edge;
3. room wall;
4. room interior.

Within equal priority, use model order then ID. Mark furniture and room interiors as hit regions even when only outlines are visible. Repeated `<Enter>` on the same cell cycles candidates. Moving the cursor resets the same-cell cycle. `<Tab>`/`<S-Tab>` cycles only spatial rooms/doors/furniture in deterministic model order; project templates/plan metadata are reachable through the searchable list/menu. The object list is the precision fallback.

### 14.12 Resize, scroll, and redraw scheduling

- Listen to supported resize events and recompute drawable dimensions.
- Coalesce multiple redraw requests into one scheduled redraw per event-loop turn.
- Reset/prevent native buffer scrolling from becoming an implicit viewport; pan commands alter viewport state explicitly.
- Preserve cursor world point/selection visibility after edits where practical.
- Very small windows show an actionable “window too small” text view, not an exception.
- If the canvas is somehow displayed in a second differently sized window, close/focus the canonical view rather than render incorrect shared lines.

---


## 15. User interaction design

### 15.1 Interaction modes

The canvas always displays one mode:

- **NAV:** `h/j/k/l` cursor movement and selection are non-destructive. Deliberate action mappings such as rotate, delete, duplicate, or an edit workflow may still commit clearly named actions without entering continuous MOVE mode.
- **MOVE:** `h/j/k/l` moves the selected room/furniture using configured steps.
- **PAN:** `h/j/k/l` moves the viewport only.
- **PLACE ROOM/FURNITURE/DOOR:** cursor previews a pending draft; confirm commits once; cancel discards.

`<Esc>` first cancels an active placement/workflow, otherwise exits MOVE/PAN to NAV, otherwise deselects. A second workflow cannot start while one is active; the UI reports the active workflow and offers cancellation.

### 15.2 Asynchronous workflow contract

All `vim.ui.input`/`vim.ui.select` flows use `ui/flow.lua` and obey these rules:

1. Capture stable session/object IDs, never “current buffer” for later callbacks.
2. Allocate a session workflow generation token.
3. Gather answers into a detached draft.
4. Treat nil at every callback as cancellation.
5. Validate a field and re-prompt without losing earlier draft values.
6. Avoid recursive synchronous re-prompt overflow; schedule retries where needed.
7. Before every callback step and final commit, verify session exists, token matches, source/model revision is still appropriate, and referenced IDs still exist.
8. A stale callback is a harmless no-op plus optional debug log.
9. Final confirmation dispatches exactly one model action.
10. Cancellation/failure creates no history entry, dirty change, partial entity, or custom template.
11. Both synchronous test stubs and delayed UI providers must produce the same result.
12. Reload/close/source switch invalidates the token.

### 15.3 Main menu

`:RoomPlan` and `:RoomPlanMenu` use `vim.ui.select` with context-labelled text. Required items:

1. Open/focus or hide canvas.
2. Initialize plan in current source.
3. Add room.
4. Align room.
5. Add door.
6. Add furniture.
7. Manage project templates.
8. Edit plan metadata/settings.
9. Edit selected spatial object.
10. Duplicate selected object.
11. Delete selected object.
12. Open object list.
13. Validate/open validation list.
14. Fit viewport.
15. Save.
16. Save As.
17. Reload.
18. Close session.

Unavailable actions remain visible where useful with a concise reason, or are grouped after available actions. Menu text includes previews such as `Place Bedroom east of Living room (new origin 5000, 0)` because the default selector cannot be assumed to render a preview buffer.

### 15.4 Object list

Implement an internal scratch-buffer list, not a dependency on picker plugins:

```text
[ROOM] Living room  room-living  origin=(0,0) size=5000x4000
[DOOR] Living → Bedroom  door-living-bedroom  east offset=800 width=900
[FURNITURE] Sofa  furniture-sofa-1  room=Living centre=(1550,1050)
[TEMPLATE] My desk  custom:my-desk  work 1600x800x740
[PLAN] My flat  metadata/settings
```

- `/`, `n`, and `N` use normal buffer search.
- `<Enter>` on a spatial room/door/furniture selects it, centres/focuses it, and returns to canvas. On a template or plan pseudo-entry it opens the corresponding management/exact-edit workflow; it never invents canvas geometry for non-spatial data.
- `q` closes only the list.
- Sorting can be model order or type/name via buffer-local mappings, without changing the model.
- Exact IDs and dimensions remain literal searchable text.
- Optional UI providers may replace/enhance this through a public item API later.

### 15.5 Inspector

The inspector is a toggleable read-only scratch split/float and shows:

- type, name, ID, owning/reference IDs and resolved names;
- exact stored coordinates/dimensions/rotation/door semantics;
- derived world bounds, area, aperture endpoints, and swing target;
- `[ERROR]` and `[WARN]` diagnostics with codes;
- latest action rounding/force metadata where relevant;
- template/category and unknown extension-key presence without dumping unsafe volumes of data.

Selection always has a header summary even when the inspector is closed. A complete workflow remains possible through menus/commands/list/inspector without spatial cursor precision.

### 15.6 Validation list

Use the same accessible list framework:

```text
[ERROR] FURNITURE_OUTSIDE_ROOM furniture-sofa-1: extends 120 mm east of room-living
[WARN] DOOR_SWING_FURNITURE door-living-bedroom: sweep intersects furniture-sofa-1
```

`<Enter>` selects and centres the primary object; next/previous mappings navigate diagnostics in the canvas. The list is regenerated from structured results and is never the validation source of truth.

### 15.7 Add Room flow

Collect:

1. name;
2. width;
3. depth;
4. placement: origin, canvas cursor, directional relative to selected/reference room, or automatic;
5. reference/direction/gap when applicable;
6. preview summary and final confirmation.

For “at canvas cursor,” the cursor world point is the proposed room's southwest/lower-left origin, rounded under the viewport/lattice rule and shown explicitly in the preview. Block overlap by default. Exact input and automatic placement use the same action validation. Select the new room after commit.

### 15.8 Align Room flow

Collect moving room, reference room, operation, optional gap/corners, then show exact proposed origin and rounding/overlap/connection consequences. Keep reference fixed. Commit one action. A forced invalid result requires a separate explicit confirmation listing new errors.

### 15.9 Add/Edit Door flow

Collect owner, side, width, offset source (exact or cursor projection), hinge, connection, swing half-plane, and angle.

For a new door, initialize the angle prompt/draft to exactly 90 degrees. Editing starts from the door's stored angle and never resets it implicitly.

- Detect all adjacent rooms whose shared interval covers the proposed aperture and offer them by name/ID.
- Exterior is an explicit valid option only when no opposite room edge positively overlaps the proposed aperture. Forcing it despite one complete cover creates `DOOR_CONNECTION_MISSING`; partial/multiple covers create `DOOR_EXTERIOR_OBSTRUCTED`.
- Cursor placement projects onto the selected edge; it does not silently clamp an invalid aperture.
- Preview describes `hinge at canonical start/end; swings into Living/Bedroom/outside`.
- Impossible aperture/overlap never commits.
- Swing collisions commit with warnings.
- Toggle hinge/swing actions are direct one-node edits after structural validation.

### 15.10 Furniture catalogue

Built-in defaults are intentionally generic and always overrideable:

| ID | Name | Category | Width × depth × height (mm) |
|---|---|---|---:|
| `builtin:bed` | Bed | sleeping | 2000 × 1600 × 500 |
| `builtin:sofa` | Sofa | seating | 2100 × 900 × 850 |
| `builtin:armchair` | Armchair | seating | 900 × 900 × 900 |
| `builtin:table` | Table | dining | 1600 × 900 × 750 |
| `builtin:chair` | Chair | seating | 500 × 500 × 900 |
| `builtin:desk` | Desk | work | 1400 × 700 × 750 |
| `builtin:wardrobe` | Wardrobe | storage | 1200 × 600 × 2000 |
| `builtin:bookcase` | Bookcase/shelf | storage | 900 × 300 × 1800 |
| `builtin:cabinet` | Cabinet | storage | 800 × 450 × 900 |
| `builtin:kitchen-unit` | Kitchen unit | kitchen | 600 × 600 × 900 |
| `builtin:appliance` | Appliance | appliance | 600 × 600 × 850 |
| `builtin:bathroom-fixture` | Bathroom fixture | bathroom | 700 × 400 × 850 |
| `builtin:custom-rectangle` | Custom rectangle | custom | 1000 × 1000 × 1000 |

These are planning seeds, not manufacturer or code-standard claims.

### 15.11 Add Furniture flow

Collect room, template, exact width/depth/height overrides, label, category, placement (room centre, cursor, or exact local centre), and optional “save as project template.”

The template chooser displays each template's width × depth × height and category before the override prompts. Template saving and furniture creation are one atomic action only after all confirmation. Select the item after commit. Movement/resize/rotation may create visible layout errors but never structural invalidity.

### 15.12 Exact Edit flows

Editing never exposes immutable IDs and commits all changed fields as one action:

- Room: name, exact world X/Y origin, width, and depth. The southwest origin is the resize anchor.
- Furniture: name, category, template reference, exact room-local centre X/Y, width/depth/height, and one of the four rotations. Changing template/category retains explicit dimensions unless the user separately enters new values.
- Door: owner/side/offset/width/hinge/connection/swing target/angle under the aperture rules. Moving to a different owner is treated as a complete validated re-anchor draft.
- Custom template: name, category, and default dimensions, subject to reference/deletion rules.
- Plan: metadata and persisted settings through a separate clearly labelled settings editor.

Every numeric field shows its stored value/unit as the default and previews resulting diagnostics. Coordinates, dimensions, offsets, gaps, and millimetre settings use the exact measurement parser. `open_angle_deg` uses a dedicated whole-degree parser constrained to 1..180; furniture rotation is an enum choice, not a measurement. Cancellation at any field is a no-op.

### 15.13 Close/reload/save flows

- Close when `session_requires_protection`: Save / Discard session / Cancel with staged/conflict details. Failed save leaves the session open.
- Reload when `session_requires_protection`: Reload and discard retained session state / Save or Save As first / Cancel. `:RoomPlanReload!` explicitly discards all protected in-memory/staged/conflict recovery state needed to replace the model, not merely history-node inequality; it still leaves an independently modified source buffer under native protection.
- Save invalid: Review / Save invalid draft / Cancel; specifically `:RoomPlanSave!` preselects invalid-draft permission. Save As bang retains its separate overwrite-only meaning.
- Conflict: use the dedicated five-choice recovery flow; never overload bang.
- Every prompt expiring because the session/source changed is a no-op.

---

## 16. Default keymaps

All maps are buffer-local, individually configurable/disableable, shown dynamically in help, and never installed globally. Control-key aliases are optional because terminal encodings vary (`<C-h>` may be Backspace, for example).

### 16.1 NAV mode

| Mapping | Action |
|---|---|
| `q` | Hide canvas; retain session/model. |
| `<Enter>` | Select/cycle candidates under cursor; update inspector. |
| `<Tab>` | Select next entity. |
| `<S-Tab>` | Select previous entity; `g<Tab>` is a portable alias. |
| `h j k l` | Move canvas cursor by one display cell. |
| `m` | Enter MOVE for selected movable object. |
| `p` | Enter PAN mode. |
| `a` | Contextual Add menu. |
| `e` | Edit selected object exactly. |
| `d` | Delete selected object with required confirmation. |
| `y` | Duplicate selected object under type rules. |
| `r` | Rotate selected furniture 90 degrees clockwise. |
| `i` | Toggle inspector. |
| `o` | Open searchable object list. |
| `v` | Validate/open validation list. |
| `]e` / `[e` | Next/previous validation diagnostic. |
| `u` | Undo one semantic action. |
| `<C-r>` | Redo; `U` is a portable optional alias. |
| `z+` / `z-` | Zoom in/out. |
| `zf` | Fit scene. |
| `zh zj zk zl` | Direct viewport pan without entering PAN. |
| `gs` | Toggle snapping. |
| `g!` | Bypass snapping for the next placement/move action. |
| `s` | Save. |
| `S` | Save As. |
| `?` | Open readable help buffer with effective mappings. |
| `<Esc>` | Cancel workflow/mode or deselect by precedence. |

### 16.2 MOVE mode

| Mapping | Action |
|---|---|
| `h j k l` | Move selected object by normal plan step with snapping. |
| `H J K L` | Move by coarse plan step. |
| `gh gj gk gl` | Move by fine plan step (portable defaults). |
| optional `<C-h/j/k/l>` | Fine-step aliases when terminal/config supports them. |
| `gs` | Toggle snapping. |
| `g!` | Bypass snapping for next move. |
| `<Esc>` | Return to NAV without deselecting. |

Doors are repositioned through exact/cursor Edit Door rather than MOVE mode because their motion is constrained to one wall scalar.

### 16.3 PAN mode

| Mapping | Action |
|---|---|
| `h j k l` | Pan viewport by configured cell amount. |
| `H J K L` | Pan by a larger amount. |
| `z+ z- zf` | Zoom/fit while remaining in PAN. |
| `<Esc>` | Return to NAV. |

### 16.4 Placement modes

`h/j/k/l` move the placement cursor; `<Enter>` confirms the current valid preview; `g!` bypasses snap; `<Esc>` cancels. No model mutation occurs until confirmation.

---

## 17. Commands and public API

### 17.1 Ex commands

| Command | Contract |
|---|---|
| `:RoomPlan` | Open context menu. |
| `:RoomPlanMenu` | Alias for context menu. |
| `:RoomPlanOpen [path]` | Open/reuse plan from path or current named buffer; file completion. |
| `:RoomPlanInit [path]` | Initialize a safe empty target/current source; never overwrite nonempty malformed data. |
| `:RoomPlanHide` | Remove canvas view, retain session. |
| `:RoomPlanClose[!]` | Close session; bang discards protected model/staged/conflict recovery state without reverting or overwriting an already modified source buffer. |
| `:RoomPlanAddRoom` | Launch Add Room workflow. |
| `:RoomPlanAlign` | Launch room alignment workflow. |
| `:RoomPlanAddDoor` | Launch Add Door workflow. |
| `:RoomPlanAddFurniture` | Launch Add Furniture workflow. |
| `:RoomPlanEdit` | Edit selected object. |
| `:RoomPlanDuplicate` | Duplicate selected object under type rules. |
| `:RoomPlanDelete` | Delete selected object under dependency rules. |
| `:RoomPlanObjects` | Open searchable object list. |
| `:RoomPlanInspect` | Toggle/focus inspector. |
| `:RoomPlanValidate` | Validate and open results. |
| `:RoomPlanNextIssue` | Navigate next diagnostic. |
| `:RoomPlanPrevIssue` | Navigate previous diagnostic. |
| `:RoomPlanUndo` | Semantic undo. |
| `:RoomPlanRedo` | Semantic redo. |
| `:RoomPlanFit` | Fit scene to canvas. |
| `:RoomPlanSave[!]` | Save; bang permits layout-error draft, never conflicts/structural failures. |
| `:RoomPlanSaveAs[!] {path}` | Save As; bang permits replacing an existing ordinary standalone target after last-minute checks. Existing Norg notes are never wholesale overwritten. |
| `:RoomPlanReload[!]` | Reload; bang discards protected session/model recovery state without prompt, while never clearing unrelated source-buffer modifications by fiat. |
| `:RoomPlanResolveConflict` | Open dedicated conflict actions. |

Commands are primarily discoverability/UI entry points. “For scripting” is fulfilled by the Lua API, not by pretending prompt-launching Ex commands are noninteractive.

Bang meanings are command-specific and never imply “ignore every safety check.” In particular, `RoomPlanSaveAs!` authorizes replacement only of an eligible valid supported RoomPlan standalone destination; if the model also has layout errors, the invalid-draft confirmation remains a separate explicit choice. Conflicts, malformed/non-RoomPlan destinations, and unsafe file types are never bypassed by bang.

Registration is idempotent and guarded by `g:loaded_roomplan`. Commands that require a session or selection fail with actionable errors when it is unavailable; `RoomPlanOpen`, `RoomPlanInit`, and the context menu can establish one. No command assumes `setup()` was called; default setup is lazy and safe.

### 17.2 Lua API

Initial public surface:

```lua
require("roomplan").setup(opts)
require("roomplan").open(opts, callback)
require("roomplan").init(opts, callback)
require("roomplan").save(opts, callback)
require("roomplan").save_as(path, opts, callback)
require("roomplan").reload(opts, callback)
require("roomplan").hide(opts)
require("roomplan").close(opts, callback)
require("roomplan").validate(opts)
require("roomplan").sessions()
```

Programmatic model edits use complete specs and structured results:

```lua
require("roomplan.api").dispatch(session_id, {
  type = "add_room",
  room = {
    name = "Living room",
    origin_mm = { 0, 0 },
    size_mm = { 5000, 4000 },
  },
})
```

API calls never launch prompts unless their name/documentation explicitly says they are UI workflows. Return/callback errors are structured `{ code, message, details }`. The API is provisional before 1.0 and semantically versioned independently from file `schema_version`.

### 17.3 Optional Neorg alias

After core integration is stable, an optional external module may register:

```text
:Neorg roomplan open
:Neorg roomplan init
:Neorg roomplan validate
```

It delegates to the public RoomPlan API. It is not required for 1.0 acceptance unless implementation proves low-risk after the adapter is complete, and it never becomes a core dependency.

---

## 18. Configuration contract

`setup(opts)` is optional, idempotent, validates types/ranges, never mutates the caller's table, and returns the effective configuration. Every call deep-merges a fresh copy of `opts` over immutable built-in defaults rather than over the previous call. Unknown keys or invalid values raise one aggregated path-specific setup error and leave the prior effective configuration unchanged; typos never silently do nothing.

Conceptual defaults:

```lua
require("roomplan").setup({
  plan_defaults = {
    metadata = { name = nil, notes = "" },
    settings = {
      grid_mm = 100,
      fine_step_mm = 10,
      normal_step_mm = 100,
      coarse_step_mm = 500,
      default_door_width_mm = 900,
      default_wall_thickness_mm = 120,
    },
  },
  limits = {
    max_dimension_mm = 100000,
    max_abs_coordinate_mm = 1000000,
    max_plan_span_mm = 1000000,
    max_auto_place_distance_mm = 100000,
    max_history = 100,
    max_history_bytes_per_session = 64 * 1024 * 1024,
    max_history_bytes_global = 256 * 1024 * 1024,
  },
  canvas = {
    open = "tab",
    unicode = "auto",
    mm_per_column = 100,
    cell_aspect = 2.0,
    zoom_factor = 1.25,
    min_mm_per_column = 1,
    max_mm_per_column = 100000,
    fit_margin_cells = 2,
    header_lines = 2,
    pan_step_cells = 5,
    pan_coarse_step_cells = 20,
    show_grid = false,
    show_rulers = false,
    show_dimensions = true,
  },
  snapping = {
    enabled = true,
    tolerance_cells = 1.5,
    max_distance_mm = 250,
    priority = { "door", "room_edge", "room_center", "furniture", "grid" },
  },
  ui = {
    inspector = "float",
    confirm_delete = true,
    notify_level = "info",
  },
  autosave = {
    enabled = false,
    debounce_ms = 1000,
    norg = false,
  },
  keymaps = {
    enabled = true,
    -- each documented action accepts a lhs string, list, or false
  },
  glyphs = nil,
})
```

Rules:

- `plan_defaults` seeds new plans only.
- Persisted `plan.settings` controls that plan's grid/movement/door defaults.
- Render style, mappings, window layout, glyph choice, user limits, confirmations, autosave, and highlights are local configuration and never persisted.
- Effective plan limits use the stricter of hard safety ceiling and user-local limit; an oversized loaded plan opens only if structurally safe and clearly reports configured-limit layout errors.
- Autosave is disabled by default, debounced, conflict-safe, and skips models with errors. It never prompts from a timer. `autosave.norg` is a separate default-false whole-buffer opt-in because durable Norg save writes the entire note; even when opted in, autosave skips whenever text outside the plan block differs from the last durable note revision, so unrelated note edits are never silently written by a RoomPlan timer. Manual `RoomPlanSave` remains explicit.
- Each mapping can be disabled. Help is generated from effective mappings.
- Highlight groups link to standard groups and specify no hard-coded colours by default.
- Custom glyph tables are accepted only as a complete validated set; partial invalid state never leaks into rendering.

### 18.1 Highlight groups

Define/link at minimum:

```text
RoomPlanWall
RoomPlanDoor
RoomPlanFurniture
RoomPlanRoomLabel
RoomPlanFurnitureLabel
RoomPlanSelected
RoomPlanError
RoomPlanWarning
RoomPlanGrid
RoomPlanStatus
RoomPlanMuted
```

Relink on `ColorScheme`; selection/error/warning remain textually represented if all highlights look identical.

---


## 19. Repository architecture

Planned repository after implementation:

```text
roomplan.nvim/
├── plan.md
├── README.md
├── LICENSE
├── NOTICE
├── CHANGELOG.md
├── CONTRIBUTING.md
├── stylua.toml
├── plugin/
│   └── roomplan.lua
├── lua/roomplan/
│   ├── init.lua
│   ├── api.lua
│   ├── commands.lua
│   ├── config.lua
│   ├── compat.lua
│   ├── state.lua
│   ├── session.lua
│   ├── controller.lua
│   ├── model.lua
│   ├── schema.lua
│   ├── ids.lua
│   ├── units.lua
│   ├── actions.lua
│   ├── history.lua
│   ├── validate.lua
│   ├── catalog.lua
│   ├── health.lua
│   ├── codec/
│   │   └── json.lua
│   ├── geometry/
│   │   ├── number.lua
│   │   ├── interval.lua
│   │   ├── rect.lua
│   │   ├── segment.lua
│   │   ├── adjacency.lua
│   │   ├── alignment.lua
│   │   ├── snapping.lua
│   │   ├── door.lua
│   │   └── sector.lua
│   ├── storage/
│   │   ├── init.lua
│   │   ├── source.lua
│   │   ├── json.lua
│   │   ├── norg.lua
│   │   ├── norg_scan.lua
│   │   ├── atomic.lua
│   │   └── conflict.lua
│   ├── scene/
│   │   ├── build.lua
│   │   ├── walls.lua
│   │   └── labels.lua
│   ├── render/
│   │   ├── viewport.lua
│   │   ├── raster.lua
│   │   ├── glyphs.lua
│   │   ├── text.lua
│   │   └── canvas.lua
│   └── ui/
│       ├── flow.lua
│       ├── menu.lua
│       ├── prompts.lua
│       ├── object_list.lua
│       ├── validation_list.lua
│       ├── inspector.lua
│       ├── keymaps.lua
│       └── help.lua
├── schema/
│   └── roomplan.schema.json
├── queries/norg/
│   └── roomplan.scm
├── doc/
│   └── roomplan.txt
├── scripts/
│   ├── test.sh
│   ├── benchmark.lua
│   └── minimal_init.lua
├── tests/
│   ├── harness.lua
│   ├── run.lua
│   ├── unit/
│   ├── integration/
│   ├── fixtures/
│   ├── snapshots/
│   └── helpers/
└── .github/workflows/
    ├── ci.yml
    └── nightly.yml
```

The implementation may split a module further when it becomes unwieldy, but it must preserve the dependency boundaries below.

### 19.1 Dependency boundaries

Pure Lua, no `vim` global:

- codec, schema, IDs, units, model, actions, history data structures, validation;
- every geometry module;
- scene extraction;
- logical raster/glyph-mask mapping except display-width validation.

Neovim boundary:

- plugin registration, commands, compat, state/session/controller;
- source buffers/filesystem commits;
- canvas/window/extmarks/display-width calls;
- all UI/health/autocommands.

Further rules:

- Storage adapters convert source text to/from the same tagged canonical model.
- UI invokes controller/action APIs and never mutates model tables.
- Renderer consumes model/validation/viewport only and cannot dispatch geometry changes.
- `compat.lua` is the only place for supported-version API differences; it is not a dumping ground for business logic.
- Norg adapter cannot require `neorg` or private module paths. Tree-sitter access uses public Neovim APIs.
- No module imports a user-specified string as code.

### 19.2 Runtime data flow

```text
source buffer/path
  -> storage extraction
  -> strict JSON decode
  -> migrate/normalize/schema validate
  -> session history node
  -> action dispatch
  -> new history node
  -> layout validation
  -> scene extraction
  -> viewport projection/raster
  -> scratch buffer + extmarks + hit map
```

Save flows in the opposite direction only through adapter `prepare_save`/`commit`; the canvas is never involved.

---

## 20. Implementation phases and gates

Implementation must keep the repository runnable at each gate. Do not begin a later subsystem by bypassing failing earlier contracts.

### Phase 0 — Approval, repository, and reproducible skeleton

Tasks:

- Receive explicit approval/change requests for this plan.
- Initialize the project repository structure.
- Add MIT `LICENSE`, `NOTICE`, `README` skeleton, `CHANGELOG`, `CONTRIBUTING`, and formatting configuration.
- Add minimal `plugin/roomplan.lua`, default `setup()`, idempotent commands, health stub, and headless harness.
- Pin CI actions by stable versions/SHAs and establish 0.10.4/0.11.7/0.12.4 syntax smoke tests.
- Record version policy: plugin SemVer independent of document schema.

Gate:

- Clean minimal Neovim can load/unload the plugin without optional dependencies.
- Commands register exactly once and global mappings remain unchanged.
- CI and local `scripts/test.sh` run one passing smoke test.
- No functional geometry/storage is faked in source buffers.

### Phase 1 — Pure codec, schema, model, units, IDs, history

Tasks:

- Implement tagged strict JSON decoder/encoder with limits and duplicate-key rejection.
- Add authoritative JSON Schema and complete v1 constructors/defaults.
- Implement unit parser/formatter using decimal rational conversion.
- Implement global ID indexes/generation and immutable IDs.
- Implement pure schema validation/normalization and empty migration registry.
- Implement deep-copy/tag preservation, action shell, snapshot history, savepoint semantics.
- Add complete fixtures for null/empty/unknown fields and deterministic bytes.

Gate:

- Model round-trips byte-deterministically on 0.10/0.11/0.12.
- Unknown nested fields and JSON type distinctions survive an edit/history cycle.
- Undo to savepoint clears dirty; branch behavior is correct.
- Malformed/duplicate/unsafe data never produces a model.

### Phase 2 — Pure geometry, doors, validation, scene

Tasks:

- Implement intervals/rectangles/segments/doubled-coordinate footprints.
- Implement all alignment, adjacency, auto-placement, and snapping contracts.
- Implement owner-anchored aperture, handed swing, sector intersection, and global door overlap.
- Implement full structured validator and deterministic sorting.
- Implement semantic wall grouping/union and physical aperture subtraction.
- Add property tests and table-driven handedness fixtures.

Gate:

- Two aligned rooms produce one semantic shared wall with one shared aperture.
- Every door side/hinge/swing combination matches expected endpoints/sectors.
- Boundary contact is not overlap; half-mm cases never use accumulated float.
- Validator finds all required errors/warnings without changing the model.

### Phase 3 — Raster/canvas technical vertical slice

Tasks:

- Implement viewport projection, clipping, wall masks, Unicode/ASCII glyphs, and layer rules.
- Implement line/arc/furniture rasterization, label placement, display-column byte maps, and hit candidates.
- Implement scratch canvas, options, header/status, resize/redraw scheduler, NAV selection, inspector basics, fit/zoom/pan.
- Hard-code only through fixtures/controller input, never as production model shortcuts.
- Create snapshots for one room, two shared rooms, one door, one sofa.

Gate:

- A canonical fixture renders materially correctly in Unicode and ASCII.
- Shared doorway remains open through both room contributors.
- Cursor hit selection works on multibyte glyph lines.
- Window resize, small window, clipping, low zoom, and fit do not error.
- Exact geometry is visible in inspector.

### Phase 4 — Sessions and standalone persistence

Tasks:

- Implement registry/context resolution, source identity, guard buffers, hide/reopen/close lifecycle.
- Implement the minimal workflow-token/async flow engine needed for Save As, close, reload, and conflict confirmations before exposing those Phase 4 UI paths.
- Implement standalone detect/init/load, authoritative loaded-buffer behavior, strict conflict revisions, buffer-backed save, pending write recovery, and detached atomic create.
- Implement Save/Save As/Reload/conflict flows and model/source status flags.
- Implement source autocmd recheck hints without unrelated redraw.

Gate:

- Create/save/reopen produces identical model and deterministic logical JSON.
- Same source opened twice reuses one session.
- Canvas wipe preserves model/history and ordinary quit is protected by the guard.
- Concurrent source edits block save; Save As preserves both versions.
- Failed buffer/disk write never marks the session saved.

This completes the persistence backbone before broad UI editing.

### Phase 5 — Rooms and furniture editing

Tasks:

- Extend the Phase 4 async flow engine to all multi-step room/furniture editing wizards and complete its cancellation/token test matrix.
- Implement Add/Edit/Move/Resize/Align/Duplicate/Delete Room.
- Implement catalogue, Add/Edit/Move/Resize/Rotate/Duplicate/Delete Furniture and project custom templates.
- Implement MOVE/PAN/placement modes, snapping toggle/bypass, object list, dynamic help, and action menus.
- Integrate validation/selection/history/viewport retention after every action.

Gate:

- Standalone acceptance flow works through two rooms and custom-size sofa.
- Every wizard cancellation point is a no-op under sync and delayed callbacks.
- Force policies and cascade summary are explicit and undoable.
- Searchable list provides a non-spatial complete workflow.

### Phase 6 — Complete door and validation UX

Tasks:

- Implement Add/Edit/toggle/duplicate-from-draft/delete Door flows and cursor projection.
- Finish visible gaps/leaves/hinges/arcs/low-zoom markers and inspector semantics.
- Finish swing warnings, validation list, next/previous issue, and invalid-draft save UX.
- Complete all snapping targets and deterministic previews.

Gate:

- Complete standalone definition-of-done scenario through connected door, hinge toggle, swing into bedroom, collision warning, undo/redo, save/reopen.
- All validation problems are textually navigable.
- Opposite-owned duplicate aperture and broken connection cases are safe/clear.

### Phase 7 — Norg adapter

Tasks:

- Implement spec scanner, optional Tree-sitter query/candidate discovery, marked/legacy discovery, initialization, replacement, and payload conflicts.
- Implement loaded-buffer normal-write semantics and EOL/encoding limitations.
- Add existing/new Norg Save As behavior.
- Complete Norg user/help documentation, preservation guarantees, and recovery examples for the v0.2 beta.
- Test with no Neorg, parser only, Neorg installed, and parser failure.

Gate:

- Full edit/save/reopen scenario works in a marked Norg block.
- Outside logical text is unchanged; stable LF/CRLF fixtures meet documented byte expectations.
- Malformed marked/possible-legacy blocks never cause duplicate initialization.
- Outside-block edits are preserved while payload edits conflict.

### Phase 8 — Hardening, docs, compatibility, and 1.0 release

Tasks:

- Complete health checks, configuration validation, highlight links, clean-install smoke, and all docs.
- Run full Linux version matrix and macOS/Windows stable smoke/integration jobs.
- Add benchmarks/profile large fixtures; optimize only measured bottlenecks.
- Finish snapshots/accessibility tests, release checklist, changelog, help tags, and text-equivalent captures.
- Perform license/source audit and ensure `NOTICE` matches actual copied/adapted material (ideally none).
- Test nightly non-blocking and file issues for regressions.

Gate:

- Every definition-of-done item in section 27 passes on Neovim 0.12.4.
- Required compatibility CI is green; nightly status is visible.
- Normal move/redraw/validation meets engineering targets on the reference fixture/machine.
- Documentation follows the actual UI and commands.

---

## 21. Testing strategy

### 21.1 Harness

Use a small repository-owned Lua 5.1-compatible test harness run by:

```text
nvim --headless -u NONE -i NONE -n --cmd "set rtp^=<repo>" -c "luafile tests/run.lua" -c "qa!"
```

Tests are isolated by temp directories/buffers and restore overridden `vim.ui`/autocommands/options. Pure modules are still tested in headless Neovim for one consistent Lua runtime, while their code remains `vim`-independent.

Support assertions, suites, table tests, deterministic random seeds, snapshots, async drain/timeouts, temp cleanup, and structured diagnostic comparisons. A failed test prints file/case and a useful diff.

### 21.2 Codec/schema/unit tests

- every measurement form, whitespace/case, negative-coordinate policy, sub-mm rejection, overflow, and malformed decimal;
- all JSON scalar escapes, Unicode/surrogate cases, invalid UTF-8, invalid number grammar, trailing content;
- duplicate keys including escaped-equivalent forms;
- missing versus null versus empty object versus empty array;
- payload/depth/value/string limits;
- all v1 defaults, wrong types/enums, unsafe integers, unknown fields at every object level;
- deterministic exact bytes across supported Neovim versions;
- empty migration registry behavior, future version rejection, synthetic migration-runner chaining;
- global ID collisions/prefix validation/generation/duplication.

### 21.3 Geometry tests

- boundary contact, positive overlap, containment, negative coordinates;
- odd dimensions and doubled half-mm edges;
- every alignment, all direction/gap/corner operations, parity-mismatch rounding;
- automatic placement ranking and exhaustion;
- partial shared edges, corner-only contact, disjoint/overlap adjacency;
- grid snapping around zero/negative values;
- room/furniture/door snapping ranking/ties/bypass;
- all furniture rotations;
- wall-thickness metadata changes leave every v1 geometry, snapping, validation, collision, and rendered boundary primitive unchanged;
- every door side/hinge/swing target and angle sample;
- aperture just inside/outside owner/shared intervals;
- endpoint-touching versus overlapping openings;
- opposite-owned physical duplicates;
- sector/rectangle corner, edge, tangent, hinge-inside, and nonintersection cases.
- sector/wall-segment radial/arc crossings plus designed own-aperture/hinge/jamb exclusions;
- sector/sector, leaf/leaf, and leaf/sector intersections for distinct doors, including tangency and shared-point exclusions;
- epsilon behavior at small/large coordinate scales with identical expected diagnostics across supported OS/runtime snapshots.

### 21.4 Action/history tests

- add/edit/move/resize/align/rotate/duplicate/delete actions are atomic;
- cancelled/no-op/failed actions do not add history or clear redo;
- undo/redo every action type;
- undo to savepoint and branch away from savepoint;
- history trimming and dirty state;
- forced action metadata and normal blocking;
- room cascade deletes every dependant and undo restores order/unknown fields;
- room resize anchors southwest and leaves children local;
- duplicate semantics by type;
- unresolved template warning without dimension loss;
- exact edit does not snap.

### 21.5 Validation tests

One focused fixture per code plus combinations:

- duplicate IDs and invalid refs from loaded drafts;
- nonpositive/unsupported structural failures;
- room overlap/contact;
- furniture outside/overlap across same and forced-overlap rooms;
- invalid aperture/opening overlap/connection/swing target;
- furniture-door swing, wall swing, and door-door warning;
- diagnostic deterministic order, structured related refs, and no model mutation;
- invalid-draft save versus non-overrideable failures.

### 21.6 Scene/raster snapshots

- empty plan/default view;
- one room with short/long/non-ASCII name;
- two aligned rooms/shared wall;
- every door side/hinge/swing target at 90 degrees and representative other angles;
- aperture subtraction from both shared contributors;
- opposite-owned duplicate diagnostic rendering;
- furniture at each rotation and half-mm derived edges;
- all wall junction masks/crossings/tees;
- structural wall versus furniture non-merging;
- selection/error/warning overlays with colours effectively identical;
- clipping at every viewport boundary;
- zoom, fit, pan, low-resolution markers, tiny items;
- Unicode and ASCII semantic parity;
- CJK, combining, and awkward-width labels;
- small window fallback and window resize.

Snapshots fix canvas size, locale, glyph mode, scale, plan order, and viewport. Updating snapshots requires an explicit environment flag and human diff review.

### 21.7 UI flow tests

For Add Room, Align, Add Door, Add Furniture, Edit, Save As, Reload, Close, conflict, and delete cascade:

- cancel at every step; serialized model/history depth unchanged;
- synchronous UI callbacks;
- callbacks deferred through `vim.schedule`/timers;
- invalid answer followed by correction without losing draft;
- callback invoked with nil item/index;
- close/reload session while prompt pending; late callback harmless;
- start two workflows quickly; only documented active flow can commit;
- referenced object deleted while prompt pending;
- source changes during confirmation; commit rechecks and refuses;
- final success creates exactly one history entry.
- Add Door with no angle override commits `open_angle_deg = 90`; Edit Door starts from the stored angle.

### 21.8 Storage/integration tests

Standalone:

- init nonexistent standalone atomically creates a clean canonical file/session; empty loaded-buffer init writes normally; failed init write retains a protected modified buffer; refuse nonempty malformed;
- source buffer modified before open is authoritative;
- buffer-backed save/reopen;
- detached atomic creation and permission behavior;
- partial temp writes/fsync/close/rename/cleanup failures through injected filesystem adapter;
- target created/changed after Save As confirmation;
- expected-absent detached finalization uses no-replace semantics: a file created in the final race window survives byte-for-byte and the temp is cleaned;
- directory/FIFO/device/symlink rejection where platform supports fixtures;
- pending disk write after buffer patch;
- `BufWritePre` formatting-only versus semantic mutation hooks, and `BufWritePost` mutations that leave buffer/disk divergent and must not establish a savepoint;
- same source twice, aliases, multiple-session resolution;
- disk/source conflict choices.

Norg:

- marked init under existing/new heading;
- marked/legacy discovery, marked-plus-legacy and other multiple matches, malformed marker, unterminated range;
- Norg adapter detection independently by `filetype=norg` and by `.norg` extension;
- conflicting suffix/filetype detection follows `.roomplan.json`/`.norg` suffix precedence and uses filetype only as fallback;
- clean-zero `RoomPlanOpen`: Cancel is byte/model/history neutral; Initialize inserts exactly one marked block;
- Norg initialization is one undoable buffer edit, performs no disk write, and leaves a nil durable savepoint/guard protection until explicit Save (contrasted with durable standalone Init);
- multiple exact `* Floor plan` headings require explicit line-context selection or append-new; cancellation changes nothing;
- malformed legacy possible-plan confirmation;
- preserve opener/closer indentation and outside text;
- outside edit allowed, payload edit conflicts;
- outside-block edits in the authoritative Norg buffer are allowed, while an external whole-file disk edit anywhere makes the stale buffer conflict before patch;
- manually writing authoritative-buffer outside-block Norg edits refreshes the durable whole-note fingerprint and does not create a false conflict on the next plan save;
- no parser, parser present, query failure/disagreement;
- no Neorg installed and Neorg active;
- normal write saves unrelated note edits as documented;
- Norg autosave is default-off; even after explicit opt-in it skips when outside-block note text is modified;
- LF, CRLF, no-final-newline, BOM/encoding errors, mixed-ending refusal;
- existing/new Norg Save As targets.

### 21.9 Session/lifecycle tests

- context resolution from canvas/source/list/inspector/sole/multiple sessions;
- same source open focus/recreate;
- divergent/modified alias buffers for one canonical path are refused while the first attached buffer remains authoritative;
- canvas `q`, `:q`, `:bd`, `:bwipeout`, raw window close, tab close;
- `RoomPlanHide`, unprotected/protected `RoomPlanClose`, bang close, and staged-source-buffer preservation;
- guard `modified` follows edit/undo/save/write failure;
- failed save staging revision 2 followed by undo to revision 1, redo, and new revision 3 preserves `buffer_payload_revision_id = 2`, keeps protection, and safely replaces/retries only after exact recheck;
- a later manual successful `:write` of an exact staged revision promotes that revision to the durable savepoint and clears pending protection; a different payload does not;
- clean-history external source conflict activates protection even though the history cursor equals the old savepoint;
- clean and forced non-semantic guard wipes recreate/lazily restore protection; semantic Close teardown does not;
- ordinary `:qall`/`:wall` protection and explicit forced variants in child Neovim processes;
- `:wall` with both unrelated source edits and model dirty remains correct even when source write hooks run once before and once through the guard save; direct-save documentation warns about side effects;
- canvas wipe/reopen retains model/history/viewport;
- header/inspector exposes an unambiguous canonical source identity/full path even when the canvas header abbreviates it;
- source unload/reload/rename;
- Save As to a canonical destination owned by another live session is refused without stealing either source;
- no global mappings changed and disabled/remapped keys;
- setup idempotence and command idempotence.

### 21.10 Compatibility and clean-install tests

- Linux: 0.10.4, 0.11.7, 0.12.4 blocking; nightly visible/non-blocking on schedule.
- macOS/Windows: 0.12.4 smoke plus selected storage/path tests.
- Windows spaces, Unicode, drive-letter and UNC path helpers.
- Minimal config, no optional UI, no Neorg, no Telescope/fzf/Snacks/nui.
- `vim.pack` documentation/example only tested on 0.12+.
- Lua 5.1 syntax/static compatibility and no 0.12-only APIs outside compat guards.

---


## 22. Performance and profiling

Reference workload:

- 20 rooms;
- 50 doors;
- 200 furniture items;
- fixed 160 × 50 drawable-cell canvas for benchmark reproducibility.

Engineering targets on a typical current machine:

- ordinary action dispatch plus validation feels immediate;
- full redraw normally under 100 ms;
- full validation normally under 200 ms;
- object-list/inspector open without perceptible delay;
- save serialization linear in payload size and not interleaved with partial source mutation.

Implementation rules:

- Measure with `vim.uv.hrtime()` after warmup; report median and p95 across repeated runs.
- Keep performance checks informational initially so noisy CI does not create false failures.
- Cache pure derived geometry by model revision; validation by model revision plus effective limit/config generation; scene by model/validation/render-setting generation; and raster by scene plus viewport/window generation. A cache may never hide a configuration or viewport-dependent change.
- Clip primitives before rasterizing.
- Rewrite canvas lines in one buffer call.
- Apply extmarks by contiguous range/object, not one extmark per cell.
- Coalesce scheduled redraws, not semantic history.
- Avoid redraw on unrelated source-buffer edits.
- Use simple broad-phase rejection before sector math.
- Do not add a spatial index until profiling demonstrates it improves the reference workload without correctness complexity.
- Add a large stress fixture near configured soft limits for graceful behavior, not for normal interactive promises.

Memory acceptance includes measuring 100 full snapshots of the reference plan. If this is excessive, move to immutable record/patch history in a dedicated reviewed change while retaining exactly the same savepoint/action semantics.

---

## 23. Reliability and security checklist

### 23.1 Source/data safety

- Never call `load`, `loadstring`, `loadfile`, `dofile`, or module loaders on plan content.
- Never pass plan strings as format strings without a literal format.
- Never generate Ex command strings containing user paths/names.
- Never mutate source before parse/schema/conflict/save-policy checks finish.
- Never mark a history savepoint before durable commit/post-write semantic verification.
- Never initialize over malformed/nonempty standalone data.
- Never add a second block beside a marked or suspected damaged RoomPlan block.
- Never use mtime/size alone as a conflict revision.
- Never silently discard unknown members for supported schemas.
- Never silently auto-fix geometry.

### 23.2 Filesystem safety

- Use same-directory exclusive temp creation for detached atomic writes.
- Handle partial writes and every cleanup path.
- Do not delete destination before rename.
- Reject unsafe file types and detached symlinks by default.
- Recheck after asynchronous overwrite confirmation.
- Preserve loaded buffers as authority.
- Keep old source association if Save As fails.
- Treat write hooks and external disk changes as first-class outcomes.

### 23.3 Resource safety

- Enforce payload/depth/value/string/entity/arithmetic ceilings.
- Avoid recursive UI retry with synchronous providers.
- Avoid unbounded history, extmark-per-cell, and unbounded notifications.
- Validate display glyph width and input UTF-8.
- Treat plan keys such as `__index` as inert JSON, never Lua prototypes.
- Use `pcall` only at codec/UI/provider/filesystem/plugin-boundary calls where a foreign/user error is expected; let internal programming errors surface in tests.

### 23.4 Error quality

Every user error should contain, where applicable:

- operation and adapter;
- source path/buffer and Norg block line;
- entity type/ID;
- stable diagnostic code;
- what remained unchanged;
- next safe actions (review, reload, Save As, retry).

Debug logging is opt-in, bounded, and never dumps large notes or private metadata by default.

---

## 24. Health checks

`lua/roomplan/health.lua` implements `:checkhealth roomplan` using supported health APIs through `compat.lua`.

Report:

- installed Neovim version versus minimum/primary targets;
- Lua/runtime compatibility assumptions;
- effective Unicode/ASCII mode and every built-in/custom glyph width failure;
- configuration validation warnings and conflicting/empty keymaps;
- optional Neorg installation/version if discoverable without private imports;
- Norg Tree-sitter parser/query availability;
- active session count, adapters, dirty/conflict/pending-write states (without private plan content);
- source buffer/path writability for the current session;
- autosave state;
- common tiny-window/display-width/fileformat problems;
- whether atomic same-directory temp creation can be attempted for the active detached destination, without destructive writes.

Health must succeed meaningfully with no active plan and no Neorg installed.

---

## 25. Documentation deliverables

### 25.1 README

- concise product statement and limitations;
- five-minute standalone tutorial matching the acceptance scenario;
- five-minute Norg tutorial using the marked block;
- text captures/screenshots with equivalent text/alt descriptions;
- install examples for:
  - Neovim 0.12+ experimental `vim.pack`;
  - lazy.nvim;
  - generic native package/runtimepath manager;
  - local development checkout;
- minimal and complete `setup()` examples;
- persisted-plan settings versus user-local configuration;
- default modes/keymaps and commands;
- source/save/hide/close/guard-buffer lifecycle;
- invalid draft and conflict recovery;
- ASCII mode/accessibility workflow;
- Neorg optionality and preservation limitations;
- support/version matrix and troubleshooting.

### 25.2 Vim help

`doc/roomplan.txt` covers:

- `*roomplan*`, setup, schema, coordinate conventions;
- every command argument/bang meaning;
- generated/effective keymap concepts and modes;
- all configuration keys/types/defaults;
- public Lua API;
- adapters and marked Norg syntax;
- validation codes/severity and navigation;
- history/savepoint/conflict behavior;
- catalogue/custom templates;
- health/troubleshooting;
- schema migration policy.

Run a help-tag/check step in CI and test referenced command/help tags.

### 25.3 Contributor documentation

Explain how to add:

- a catalogue template;
- a model action and history/validation tests;
- a geometry primitive;
- a scene primitive/raster layer/glyph;
- a storage adapter;
- a schema version/migration;
- a validation diagnostic;
- compatibility shims and CI fixtures.

Include dependency boundaries, test commands, snapshot update procedure, release checklist, security expectations, and license/NOTICE procedure.

### 25.4 Schema and example files

- checked-in Draft 2020-12 JSON Schema for tooling/documentation with `additionalProperties: true` consistent with preservation;
- valid empty, acceptance, invalid-layout, malformed, future-version, extension-field, and legacy-Norg fixtures;
- coordinate/door diagrams in prose/text so docs remain useful without images.

---

## 26. CI and release policy

### 26.1 Required jobs

Blocking pull-request jobs:

- formatting/static Lua 5.1 compatibility;
- headless tests on Linux Neovim 0.10.4, 0.11.7, and 0.12.4;
- deterministic codec/schema/snapshot checks;
- clean minimal-config install/load;
- help/schema/fixture consistency;
- macOS and Windows stable smoke where runner cost permits, otherwise required on release branches.

Scheduled/non-blocking but visible:

- Neovim nightly full suite;
- performance report;
- optional current Neorg/parser integration.

Release gate requires macOS/Windows 0.12.4 results even if they are not blocking every small PR.

### 26.2 Version policy

- Plugin uses Semantic Versioning.
- File `schema_version` changes only for persisted semantic incompatibility, not every plugin release.
- Pre-1.0 Lua API may change with changelog/migration guidance; persisted v1 remains protected once released.
- A future schema version ships sequential migrations before writers emit it.
- Nightly failures are triaged and tracked, not ignored silently.

### 26.3 Release checklist

- all CI/definition-of-done gates;
- compatibility/Neorg assumptions re-verified against official sources;
- README/help/schema/examples agree;
- clean installation on each documented method/version;
- changelog and SemVer/schema notes complete;
- license and NOTICE audit;
- no generated source drawing or test temp files committed;
- performance reference results recorded;
- tagged release and post-release installation smoke.

---

## 27. Complete definition of done

The project is complete only when all items below pass on Neovim 0.12.4, with compatibility jobs as specified.

### 27.1 Core acceptance scenario

1. Create `flat.roomplan.json` safely.
2. Add a `5000 × 4000 mm` Living room at `(0, 0)`.
3. Add a `3000 × 3000 mm` Bedroom.
4. Align/place Bedroom immediately east of Living, south edges aligned.
5. Add one `900 mm` physical hinged door on the shared boundary.
6. Verify the opening cuts both coincident room edges.
7. Toggle hinge and set swing half-plane to `connected`; inspector says it opens into Bedroom and canvas visibly changes.
8. Add a sofa with explicit `2100 × 900 × 800 mm` dimensions.
9. Move and rotate it; furniture outside/overlap is a visible error and door-swing collision is a warning.
10. Undo and redo the furniture edit semantically.
11. Restore/fix every blocking furniture error (a door-swing warning may remain), then perform a normal Save and verify that history remains and the current node is the durable savepoint.
12. Undo to a pre-save node and verify dirty state, then redo to the savepoint and verify clean state.
13. Hide/reopen the canvas and verify the live session retains model/history and a materially equivalent viewport/selection.
14. Close the clean session, reopen from disk, and obtain identical model geometry and a materially identical fixed-viewport rendering with a fresh initial history.

### 27.2 Norg acceptance scenario

1. Initialize a marked `@code json roomplan.nvim` block in an existing note.
2. Repeat room/door/furniture editing and durable save.
3. Confirm unrelated logical text is unchanged.
4. For ordinary UTF-8 LF and CRLF files without mutating write hooks, compare raw disk bytes and confirm every byte outside the payload range is unchanged. Separately test/document Neovim-controlled normalization cases (`fileencoding`, BOM, `endofline`/`fixeol`, and write hooks) rather than weakening the normal guarantee.
5. Modify unrelated note text while canvas is open; plan save preserves and writes it.
6. Modify the selected payload while canvas is open; plan save detects conflict.
7. Open a malformed marked/possible legacy block; report it and never initialize a duplicate.
8. Work with Neorg absent, parser absent, parser present, and Neorg active.

### 27.3 Safety/lifecycle acceptance

1. Same source opened twice has one model/history.
2. Two different sources have independent sessions/canvases.
3. `q` wipes/hides the canvas but preserves the live model/history and all protection state.
4. Reopen restores a material viewport/selection equivalent.
5. Ordinary quit cannot silently discard any session requiring protection; forced process quit is explicit.
6. Close offers Save/Discard/Cancel; failed save does not close.
7. Source conflict offers safe review/reload/Save As/overwrite/cancel and rechecks after callbacks.
8. Standalone atomic failure leaves original intact.
9. Invalid layout save requires explicit action; malformed/unsupported data cannot be force-saved.
10. No global mapping or optional dependency is required.

### 27.4 Accessibility/terminal acceptance

1. Unicode and ASCII complete workflows produce equivalent model/history/hit behavior.
2. Selected object and validation severity remain understandable when highlights are visually identical.
3. Object/validation lists are searchable with built-in buffer search.
4. All essential operations are reachable without cursor-precision selection.
5. CJK/combining/long names do not corrupt raster columns and remain exact in inspector.
6. Tiny windows/low zoom degrade textually without crashing or inventing geometry.
7. Help shows effective configured mappings.

### 27.5 Validation and diagnostics acceptance

The test suite creates every required structural/layout/warning diagnostic. Initial parse/schema failures that prevent a session have severity, stable code, explanation, and source byte/line location where knowable; they cannot promise an object ID or canvas navigation. Every in-session layout/warning entry has its primary object ID and navigates through list/canvas/inspector. Validation never changes geometry.

### 27.6 Health/release acceptance

- `:checkhealth roomplan` succeeds with and without an active source/Neorg.
- Linux 0.10.4/0.11.7/0.12.4 pass; macOS/Windows 0.12.4 release smoke passes; nightly is reported.
- Reference workload normally meets redraw/validation engineering targets.
- README/help/schema/changelog/license/NOTICE/contributor docs are complete.

---

## 28. Requirement traceability

| Original requirement area | Primary design/test sections |
|---|---|
| Initialize/open | 12, 13, 15.3, 17, Phase 4/7 |
| Create/move/align rooms | 8, 9.4–9.5, 11, 15.7–15.8 |
| Selection/inspection/search | 14.11, 15.4–15.6, 16 |
| Doors/shared boundary/swing | 6.6, 9.2–9.7, 10, 14.1, 15.9 |
| Furniture/catalogue/custom sizes | 6.5/6.7, 11, 15.10–15.11 |
| Snapping/bypass | 9.6, 16, 18 |
| Collision/validation | 9.7, 10, 15.6 |
| Undo/redo | 11, 21.4, 21.9 |
| Save/reload/close/conflicts | 12, 13, 15.13, 17, 21.8–21.9 |
| Commands/menu/keymaps | 15–17 |
| Canvas/render/viewport | 14 |
| Geometry purity | 8–10, 19.1 |
| Norg integration/preservation | 12.8–12.10, Phase 7 |
| Compatibility/dependencies | 4, 18–19, 21.10, 26 |
| Reliability/security | 7, 12–13, 23 |
| Performance | 22 |
| Testing | 21 |
| Documentation/license | 24–26 |

---

## 29. Risk register

| Risk | Likelihood/impact | Mitigation and stop condition |
|---|---|---|
| Terminal quantization makes doors/furniture unreadable | High/medium | Explicit low-detail markers, exact inspector, zoom, fixed snapshots. Never distort model. |
| Shared wall raster gaps refill | High/high | World-space wall union/aperture subtraction gate before canvas integration. |
| Async UI commits stale drafts | Medium/high | Workflow tokens, stable IDs/revisions, cancellation/stale-callback tests. |
| Canvas wipe loses model edits | Medium/high | Session outside canvas plus modified `acwrite` guard and child-process quit tests. |
| Loaded buffer/disk diverge | Medium/high | Buffer authority, normal writer, post-write parse, separate pending/conflict state. |
| Norg malformed block duplicated | Medium/high | Explicit opener marker, conservative scanner, suspected legacy refusal. |
| Norg Tree-sitter grammar changes | Medium/medium | Optional public query only; scanner remains safety authority; fixtures and fallback. |
| JSON unknown fields lose type | Medium/high | Original tagged strict codec and nested preservation tests. |
| Deterministic output differs across Neovim versions | Medium/medium | Pure encoder and exact cross-version fixture job. |
| Windows replacement semantics harm target | Medium/high | No unlink fallback; buffer writer/fail intact; Windows integration fixtures. |
| Full-snapshot history costs too much | Low/medium at target | Benchmark reference model; enforce 100-node, 64 MiB/session, and 256 MiB/global budgets; patch redesign only from evidence. |
| Scope delays working feedback | High/medium | Vertical gates; complete standalone scenario before Norg polish. |
| Accessibility relies on colour/spatial precision | Medium/high | Text header, inspector/lists/commands, ASCII parity, identical-highlight tests. |
| User expects architectural/CAD accuracy | Medium/medium | Clear zero-thickness/planning limitations and exact coordinate docs. |
| Third-party licensing contamination | Low/high | Original implementation, pre-merge NOTICE/license audit, no Neorg code copy. |

If a risk exposes a contradiction with a locked decision rather than an implementation bug, stop and amend this plan with user approval instead of silently changing behavior.

---

## 30. Deferred roadmap

These are allowed by boundaries but not part of 1.0:

- windows and more door kinds;
- physical wall thickness derived around v1 topological wall-centre-line boundaries under a new schema contract;
- arbitrary polygon rooms and angled walls through a new schema version;
- multiple floors/plans with explicit migration;
- global user template catalogue;
- mouse placement/dragging as an optional interface;
- read-only Norg inline virtual-line preview;
- optional `:Neorg roomplan ...` module aliases;
- exports/imports after canonical geometry semantics stabilize;
- explicit clearance zones and accessibility heuristics clearly labelled non-certifying;
- history gesture coalescing with explicit begin/end transactions;
- spatial index only for measured large-plan needs.

None should be started before the 1.0 gate unless the user explicitly reprioritizes scope.

---

## 31. Approval checklist

There are no hidden blocking questions: this plan chooses recommended defaults so implementation can proceed deterministically after approval. Approval specifically confirms:

- MIT license;
- full feature target delivered through milestones;
- multi-session registry and one canvas window per session;
- `q` hides while `RoomPlanClose` unloads;
- hidden modified guard buffer for native unsaved-change protection;
- Norg Save writes the entire source buffer through normal `:write` behavior;
- new `@code json roomplan.nvim` marker with legacy support;
- one physical shared door and `owner | connected | outside` swing enum;
- global immutable prefixed IDs and namespaced template IDs;
- confirmed cascade room deletion;
- modal NAV/MOVE/PAN behavior and built-in searchable lists;
- editable invalid furniture layouts, explicit forced room transformations, and `Save!` only for layout-invalid drafts;
- half-millimetre derived math with reported integer rounding;
- v1 room rectangles as zero-thickness topological wall centre-lines/nominal interior bounds, never silently reinterpreted by future thickness support;
- specification scanner as Norg safety authority with preferred optional Tree-sitter discovery;
- semantic unknown-field preservation and deterministic JSON reformatting;
- migration framework with no fabricated v0 migration.
- the revised section 6 schema superseding the unimplemented draft example; any existing prototype files must be disclosed before coding so an importer can be planned.

If any item is unwanted, revise it before coding. After approval, implementation should follow phases 0 through 8, verify every gate, and stop only for a demonstrated contradiction, unsafe external-state requirement, or a user-requested scope change.
