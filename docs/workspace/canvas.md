# Canvas

The canvas is a bounded terminal rendering of exact model geometry. Walls,
door leaves and swings, furniture footprints, labels, dimensions, grid points,
diagnostics, and selection are separate semantic layers with hit information;
the buffer text is never the source of truth.

## View controls

| Key | Action |
| --- | --- |
| `f` or `zf` | Fit all rendered geometry with the configured margin |
| `z+` / `z-` | Zoom in / out around the logical cursor |
| `zh zj zk zl` | Pan the viewport |
| `p`, then directions | Enter dedicated PAN mode |
| `]r` / `[r` | Rotate the view clockwise / counter-clockwise |
| `g0` | Restore north-up view |

Zoom is limited by `canvas.min_mm_per_column` and
`canvas.max_mm_per_column`. Terminal rows use `cell_aspect` times the
millimetres-per-column scale so plan proportions look correct in non-square
terminal cells.

The header contains the plan state and, by default, a compact compass. The
action bar below the canvas reports mode, saved/dirty/conflict state, snapping,
and zoom. Empty plans show a first-room card; if geometry is outside the
viewport, the canvas explicitly suggests `f` instead of appearing blank.

## Selection and movement

Move the logical cursor with `h j k l` and press `Enter` to select. Multiple
objects can share a cell; pressing Enter repeatedly cycles the exact hit list.
Selection highlights all cells belonging to the semantic object, not just its
label.

In MOVE mode, changes are expressed in world millimetres and recorded as model
actions. View rotation only changes how direction keys are projected, so
moving right on screen still looks right. Grid and geometric snapping are
view-scale aware and capped by `snapping.max_distance_mm`.

See [Appearance](../display/appearance.md) for glyphs/highlights and
[Aspect and rotation](../display/aspect-and-rotation.md) for calibration.

← [Forms and actions](forms-and-actions.md) | [Documentation home](../README.md) | [Rooms](../planning/rooms.md) →
