# Storage and sessions

RoomPlan supports two source adapters and keeps one writable live session per
source.

## Standalone JSON

Files ending in `.roomplan.json` contain one deterministic schema-v4 document.
Initialization refuses to overwrite non-empty content. Saving updates a loaded
source through Neovim's buffer and normal write hooks; a detached writer only
creates a new path atomically and never replaces an existing one.

## Norg notes

Files ending in `.norg` (or Norg buffers) store the same JSON in a marked block:

```norg
* Floor plan

@code json roomplan.nvim
{ "format": "roomplan.nvim", "schema_version": 4, "units": "mm", ... }
@end
```

RoomPlan replaces only the selected payload through buffer APIs, then performs
a normal write of the whole note. Unrelated unsaved note edits are therefore
preserved and written too. A conservative scanner rejects multiple marked
plans, malformed marked JSON, unterminated blocks, or ambiguous candidates
instead of guessing. Legacy unmarked JSON is readable only when its top-level
`format` clearly identifies RoomPlan; new writes use the marker.

Neorg and Tree-sitter are optional. Multiple `* Floor plan` headings require an
interactive choice before initialization.

## Older schema migration

Opening a valid schema-v1, schema-v2, or schema-v3 JSON/Norg payload migrates
its in-memory model sequentially to schema v4. The v2-to-v3 step adds empty
canonical `windows` and `outlets` collections; v3-to-v4 marks existing outlets
as wall-mounted. Loading does not modify the source buffer or disk file. The
session remains protected and autosave stays paused until an explicit save
accepts the schema rewrite; that save writes the deterministic v4
representation. Reload and conflict checks retain this protection instead of
treating semantic equality as a durable savepoint.

## Session lifecycle

- **Hide** (`q` or `:RoomPlanHide`) closes workspace windows but retains the
  model, semantic history, source ownership, and quit protection.
- **Open** on an already owned source focuses/recreates that workspace instead
  of creating a second session.
- **Close** (`:RoomPlanClose`) unloads the session. Protected state prompts;
  `:RoomPlanClose!` deliberately discards it.
- **Reload** rereads the source. Protected state prompts;
  `:RoomPlanReload!` deliberately discards it.

Commands normally resolve the session attached to the current source or
workspace buffer, then fall back when exactly one session exists. With several
unattached sessions, `:RoomPlan` lets you choose.

Undo and redo retain named semantic revisions within the configured history
limits. **Browse undo history** in `?` lists those retained entries newest-first,
distinguishes the current and durable saved revisions, and confirms before
moving to an older or newer snapshot. Restoring is transient until saved;
making a new edit from an older revision discards the newer redo branch.

## Conflicts and recovery

RoomPlan records expected buffer and disk revisions. If the source changes
outside its save transaction, saving stops with `CONFLICT`; it never silently
overwrites the newer source. `:RoomPlanResolveConflict` offers review, reload,
Save As, and—only while the current payload is still parseable and unchanged—a
confirmed overwrite. A hidden `acwrite` guard keeps risky in-memory state from
being discarded by an ordinary quit. If saving that guard finds a conflict,
it keeps the session modified and opens the same resolution choices instead of
raising a Lua callback error.

Autosave is off by default, runs only after the debounce and clean validation,
and pauses on conflicts. Norg autosave requires both `autosave.enabled = true`
and `autosave.norg = true`, and never runs over unrelated modified note text.

← [Aspect and rotation](../display/aspect-and-rotation.md) | [Documentation home](../README.md) | [Validation](validation.md) →
