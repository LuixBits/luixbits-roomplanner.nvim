# Coordinates and schema

RoomPlan writes strict JSON schema version `3`. The authoritative
machine-readable definition is
[`schema/roomplan-v3.schema.json`](../../schema/roomplan-v3.schema.json).
Schema-v1 and schema-v2 documents remain readable through sequential tested
migrations; the [v2 schema](../../schema/roomplan-v2.schema.json) and
[v1 schema](../../schema/roomplan.schema.json) remain available for legacy
producers.

## Coordinate system

- Units are always integer millimetres.
- World `X` increases east/right and world `Y` increases north/up.
- A room's `origin_mm` is the stable world origin of its local footprint.
- A footprint is a `rect_union` of local rectangular parts. Each part has a
  stable `part-*` ID, local `origin_mm`, and `[width, depth]` `size_mm`.
- Furniture `position_mm` is the room-local position of its anchor.
  `anchor2_mm` stores that footprint-local anchor in doubled millimetres, so
  odd-sized centred objects retain exact half-millimetre edges. Divide an
  `anchor2_mm` component by two to express it in millimetres.
- A door or window references one owner `part_id`. Its offset starts at the
  west end of a north/south part side or the south end of an east/west part
  side. The whole aperture must also lie on the footprint union's exterior.
- An outlet uses the same part/side/offset coordinates for one exterior-wall
  point. Edge endpoints are excluded because their owning wall is ambiguous.

Footprint parts must have unique IDs, positive integer-mm dimensions, no
positive-area overlap, one positive-edge-connected union, no enclosed holes,
and at most 256 parts. Negative world and local coordinates are representable.
Display rotation changes only projection; stored directions and coordinates
remain world-relative.

## Document shape

```json
{
  "format": "roomplan.nvim",
  "schema_version": 3,
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
  "windows": [],
  "outlets": [],
  "furniture": [],
  "custom_templates": [],
  "extensions": {}
}
```

IDs are stable and globally unique. Room, door, window, outlet, and furniture
IDs begin with `room-`, `door-`, `window-`, `outlet-`, and `furniture-`;
project template IDs begin with `custom:`. Template references may also use the
reserved `builtin:` namespace.

Unknown object members are allowed and preserved semantically through
normalization and deterministic encoding. Put namespaced integrations in
`extensions` when possible. Schema v3 supports one floor, connected
rectangular-union rooms and furniture, hinged doors, wall windows, typed
outlets, and quarter-turn furniture rotation. Rooms store `origin_mm` and
`footprint`; furniture stores
`position_mm`, `anchor2_mm`, `footprint`, `height_mm`, and `rotation_deg`;
project templates use the corresponding `default_*` fields. Removed v1
rectangle fields are not retained beside these authorities.

Missing optional metadata/settings are normalized to current schema defaults.
Normalization or migration leaves the source untouched and the session
non-durable until the normalized v3 model is explicitly saved. The v2-to-v3
migration initializes empty `windows` and `outlets` arrays; it never overwrites
same-named extension data. Autosave does not perform that first rewrite. Plugin
releases and persisted schema versions remain separate: a plugin update does
not by itself rewrite a plan.

← [Validation](validation.md) | [Documentation home](../README.md) | [Settings](../configuration/settings.md) →
