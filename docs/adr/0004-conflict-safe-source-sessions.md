# ADR-0004: Source sessions use conflict-safe single-writer ownership

- Status: Accepted
- Date: 2026-07-19
- Deciders: RoomPlan maintainers

## Context

RoomPlan writes standalone JSON and embedded Norg blocks while buffers, files,
autocommands, or other processes may change the same source. Unsaved geometry
must remain protected during `:q`, reload, Save As, write hooks, and external
modification.

## Decision

Allow one writable live RoomPlan session per canonical source. Storage adapters
prepare writes without mutation, compare the expected source revision
immediately before commit, and return structured conflicts. Sessions retain a
durable savepoint and use a hidden modified-buffer guard so Neovim's native
quit protection also protects RoomPlan state.

Conflicts require an explicit review, reload, Save As, or confirmed overwrite.
Atomic creation/replacement and post-write reconciliation are adapter
responsibilities. Hiding a workspace does not release source ownership;
closing the session does.

## Alternatives considered

- **Last writer wins:** rejected because it silently destroys plan or source
  changes.
- **Treat a hidden workspace as closed:** rejected because protected history
  and source ownership would disappear unexpectedly.
- **Keep only an in-memory hash:** rejected because buffer text and durable
  file state may diverge through hooks or external writes.

## Consequences

### Positive

- User data survives normal Neovim quit and conflict workflows.
- Standalone and Norg adapters share lifecycle guarantees.
- Save failures retain a recoverable in-memory model.

### Costs and constraints

- Lifecycle code must reconcile buffer, disk, and normalized model revisions.
- A source cannot be edited concurrently by two RoomPlan sessions.
- New adapters need conflict and recovery tests, not only round-trip tests.

## Verification

Lifecycle, atomic-write, conflict, Save As, write-hook, Norg, and quit-guard
tests cover both successful and interrupted paths.

## Related material

- [Storage and sessions](../data/storage-and-sessions.md)
- [Architecture](../development/architecture.md)
