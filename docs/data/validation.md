# Validation

RoomPlan separates **structural validity** from **layout validity**.

Structural checks protect the model contract: format/version/units,
collections, globally unique typed IDs, references shaped correctly, integer
coordinates, positive dimensions, supported rotations/enums, and required
fields. Structurally invalid JSON does not become an editable model, and
structural model errors can never be force-saved.

Layout validation runs on a safely loaded model and reports:

- missing room references and unavailable furniture templates;
- configured dimension, coordinate, and plan-span limits;
- room and furniture overlap, and furniture outside its owner room;
- door apertures outside walls, invalid/missing connections, obstructed
  exterior openings, and overlapping openings;
- door swing intersections with furniture, walls, and other doors.

Broken layout invariants are errors. An unavailable imported template and door
swing interference are warnings; warnings do not block saving.

Run `:RoomPlanValidate` or press `v` to recompute diagnostics and focus Issues.
Use `[e` / `]e` to move through them, or select an Issues row to focus its
object. Details shows diagnostics for the current selection.

## Invalid repair drafts

Some room operations expose **Allow invalid draft** so you can temporarily
create geometry that needs further repair. An ordinary interactive save asks
whether to review or deliberately save the invalid draft; a noninteractive
save returns an error. `:RoomPlanSave!` is the explicit command-line form for
saving a structurally valid layout-invalid draft.

Force-saving never bypasses malformed schema, unsafe source targets, write
failures, or source conflicts. `:RoomPlanSaveAs!` concerns replacement of an
existing valid destination; it is not a general safety bypass.

Diagnostics are deterministic and tied to a model revision. Any semantic edit
invalidates the cached result; selection and viewport changes do not.

← [Storage and sessions](storage-and-sessions.md) | [Documentation home](../README.md) | [Coordinates and schema](coordinates-and-schema.md) →
