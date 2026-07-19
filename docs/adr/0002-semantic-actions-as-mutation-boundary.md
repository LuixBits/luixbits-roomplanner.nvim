# ADR-0002: Semantic actions are the model mutation boundary

- Status: Accepted
- Date: 2026-07-19
- Deciders: RoomPlan maintainers

## Context

RoomPlan exposes the same model through commands, popups, direct canvas edits,
batch operations, and a Lua integration API. Direct mutation from each UI path
would make validation, history, stale-form protection, and undo behavior
inconsistent.

## Decision

Every persisted model change is expressed as a semantic action and applied
through the shared action boundary. Applying an action copies the model,
normalizes and validates the result, and returns either a complete new snapshot
or no change. Controllers add history only after a successful action.

UI modules may mutate transient session state such as selection, viewport,
filters, forms, minimaps, and analyses. They must not mutate nested persisted
model tables. Multi-object operations use compound actions and create one
history revision.

## Alternatives considered

- **Let forms modify model tables directly:** rejected because cancel,
  validation failure, and stale revisions could leave partial edits.
- **Use command-specific mutation paths:** rejected because behavior would
  diverge between Lua, Ex commands, and interactive UI.
- **Store incremental patches as the model:** rejected because schema
  validation and source reconciliation operate on complete snapshots.

## Consequences

### Positive

- Undo, validation, API dispatch, and UI edits share one contract.
- Failed operations cannot expose partial persisted state.
- Batch operations remain atomic and receive meaningful history labels.

### Costs and constraints

- New persisted behavior must define and test an action before UI wiring.
- Whole-snapshot copies require explicit history and memory limits.
- Integrations must treat returned model and session tables as read-only.

## Verification

Action, history, controller, compound-operation, stale-form, and persistence
tests verify atomicity and failure behavior.

## Related material

- [Architecture](../development/architecture.md)
- [Lua API](../reference/lua-api.md)
