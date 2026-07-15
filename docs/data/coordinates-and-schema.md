# Coordinates and schema

RoomPlan documents use strict JSON and schema version `1`. The authoritative
machine-readable definition is
[`schema/roomplan.schema.json`](../../schema/roomplan.schema.json).

## Coordinate system

- Units are always integer millimetres.
- World `X` increases east/right and world `Y` increases north/up.
- A room's `origin_mm` is its southwest corner; `size_mm` is
  `[width, depth]`.
- Furniture `center_mm` is relative to its owner room's southwest corner;
  `size_mm` is `[width, depth, height]`.
- A door offset starts at the west end of a horizontal wall or south end of a
  vertical wall.

Negative world and room-local coordinates are representable. Dimensions are
strictly positive. Display rotation changes only projection; stored directions
and coordinates remain world-relative.

## Document shape

```json
{
  "format": "roomplan.nvim",
  "schema_version": 1,
  "units": "mm",
  "metadata": { "name": "Flat", "notes": "" },
  "settings": {
    "grid_mm": 100,
    "fine_step_mm": 10,
    "normal_step_mm": 100,
    "coarse_step_mm": 500,
    "default_door_width_mm": 900
  },
  "rooms": [],
  "doors": [],
  "furniture": [],
  "custom_templates": [],
  "extensions": {}
}
```

IDs are stable and globally unique. Room, door, and furniture IDs begin with
`room-`, `door-`, and `furniture-`; project template IDs begin with `custom:`.
Template references may also use the reserved `builtin:` namespace.

Rooms and furniture may contain an optional `color` value. It is either
`"auto"`, which inherits the active colorscheme, or a canonical six-digit
`#RRGGBB` color. Older v1 documents without this field remain valid, so this
optional addition does not require a schema migration.

Unknown object members are allowed and preserved semantically through
normalization and deterministic encoding. Put namespaced integrations in
`extensions` when possible. Consumers must still understand that v1 supports
one floor, rectangular rooms/furniture, hinged doors, and quarter-turn
furniture rotation.

Missing optional metadata/settings are normalized to current schema defaults.
Normalization or a future migration leaves the session non-durable until the
normalized model is explicitly saved. Plugin releases and persisted schema
versions are separate: a plugin update does not by itself rewrite a plan.

← [Validation](validation.md) | [Documentation home](../README.md) | [Settings](../configuration/settings.md) →
