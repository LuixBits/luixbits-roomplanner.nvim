# Validation

RoomPlan separates **structural validity** from **layout validity**.

Structural checks protect the model contract: format/version/units,
collections, globally unique typed IDs, references shaped correctly, integer
coordinates, positive dimensions, supported rotations/enums, and required
fields. Structurally invalid JSON does not become an editable model, and
structural model errors can never be force-saved.

For schema-v4 features this includes positive window widths, supported outlet
types, outlet `slots` from 1 through 32, and mutually exclusive wall or floor
outlet fields. Wall features require owner/part/side fields; floor outlets
require a room-local point.

Layout validation runs on a safely loaded model and reports:

- missing room/part/connection references and unavailable furniture templates;
- configured dimension, coordinate, and plan-span limits;
- room and furniture overlap, and furniture outside its owner room;
- door/window apertures outside exterior walls, invalid/missing connections,
  obstructed openings, and overlapping door/window apertures;
- wall outlets outside their exterior wall, on an internal seam, or at an
  ambiguous edge endpoint; floor outlets outside or on the boundary of their
  owner room;
- door swing intersections with furniture, walls, and other doors.

Broken layout invariants are errors. An unavailable imported template and door
swing interference are warnings; warnings do not block saving.

Run `:RoomPlanValidate` or press `v` to recompute diagnostics and focus Issues.
Use `Alt-k` / `Alt-j` to move through them, or activate an Issues row to select,
reveal, and centre its object without changing the working zoom or rotation.
Details shows diagnostics for the current selection.

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
