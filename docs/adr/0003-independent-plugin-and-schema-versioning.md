# ADR-0003: Plugin and document-schema versions are independent

- Status: Accepted
- Date: 2026-07-19
- Deciders: RoomPlan maintainers

## Context

Most plugin releases do not change persisted data, while one schema version
may be read by many plugin releases. Coupling plugin SemVer to schema versions
would either force needless migrations or hide meaningful compatibility
changes. Floor-plan files are user data and require stronger recovery behavior
than ordinary configuration.

## Decision

Version plugin releases with SemVer and version the RoomPlan document format
with its own monotonically increasing integer. A schema change adds exactly one
forward migration from the previous version, fixtures for both sides, updated
JSON Schema, validation, and recovery documentation.

Loading may migrate and normalize in memory but never rewrites source bytes.
Only an explicit save establishes the current writer version. Future schema
versions are rejected instead of guessed or downgraded. Unknown extension data
is preserved when the schema contract permits it.

## Alternatives considered

- **Use the plugin version in every plan:** rejected because unrelated UI
  releases would churn durable documents.
- **Migrate and save automatically on open:** rejected because opening an old
  plan would become an irreversible write.
- **Best-effort loading of future versions:** rejected because silently
  misinterpreted geometry is worse than a clear compatibility error.

## Consequences

### Positive

- Plugin releases and plan migrations communicate different risks clearly.
- Old sources remain recoverable and unchanged until the user saves.
- Every migration path is sequential and independently testable.

### Costs and constraints

- Readers and migration fixtures must be retained for documented old schemas.
- Schema evolution requires coordinated model, storage, validation, UI, and
  documentation work.
- Downgrading a plan is not supported.

## Verification

JSON schemas, version fixtures, sequential migration tests, source-byte
preservation tests, and future-version failures enforce this decision.

## Related material

- [Coordinates and schema](../data/coordinates-and-schema.md)
- [Storage and sessions](../data/storage-and-sessions.md)
- [Compatibility policy](../development/compatibility.md)
