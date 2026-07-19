# ADR-0001: Exact authored geometry is independent of terminal rendering

- Status: Accepted
- Date: 2026-07-19
- Deciders: RoomPlan maintainers

## Context

A terminal cell is a lossy, aspect-dependent projection. Zooming, Unicode
glyph choice, font metrics, and window size cannot be allowed to change saved
room dimensions or object positions. Compound room and furniture silhouettes
also need deterministic adjacency, snapping, validation, and migrations.

## Decision

Persist authored geometry in integer millimetres. Use doubled-integer
millimetres where centered odd-sized furniture creates half-millimetre edges.
Pure geometry is authoritative. Scene extraction, viewport projection, and
rasterization are downstream views and never become saved input.

View rotation, zoom, pan, minimaps, sunlight overlays, labels, and terminal-cell
aspect calibration remain transient projections. User-visible edits are
converted back into exact world-space operations before validation.

## Alternatives considered

- **Persist terminal cells:** rejected because resizing the editor or changing
  fonts would change physical dimensions.
- **Use floating-point geometry throughout:** rejected because boundary
  equality, migration, snapping, and deterministic serialization would become
  sensitive to rounding.
- **Adopt arbitrary polygons immediately:** deferred because they require a
  substantially different topology, editing, validation, and opening model.

## Consequences

### Positive

- Save/load, snapping, and validation remain deterministic.
- Rendering can evolve without schema migrations.
- Unicode and ASCII views describe the same plan.

### Costs and constraints

- The current model is limited to connected, hole-free rectangular unions.
- Every screen-space interaction needs an explicit world/view conversion.
- Half-millimetre anchors require doubled-integer predicates in selected paths.

## Verification

Geometry, viewport, raster, migration, Unicode/ASCII, and hit-provenance tests
exercise the boundary. Schema files accept authored measurements, not display
cells.

## Related material

- [Architecture](../development/architecture.md)
- [Coordinates and schema](../data/coordinates-and-schema.md)
