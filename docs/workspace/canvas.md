# Canvas

The canvas is a bounded terminal rendering of exact model geometry. Walls,
door leaves and swings, window apertures, wall/floor outlets, furniture footprints,
labels, dimensions, grid points, diagnostics, and selection are separate
semantic layers with hit information; the buffer text is never the source of
truth.

## View controls

| Key | Action |
| --- | --- |
| `f` or `zf` | Fit all rendered geometry with the configured margin |
| `.` / `,` | Zoom in / out around the logical cursor |
| `zh zj zk zl` | Pan the viewport |
| `p`, then directions | Enter dedicated PAN mode |
| `t` | Cycle high, middle, and no canvas detail |
| `Alt-l` / `Alt-h` | Rotate the view clockwise / counter-clockwise |
| `g0` | Restore north-up view |

Zoom is limited by `canvas.min_mm_per_column` and
`canvas.max_mm_per_column`. Terminal rows use `cell_aspect` times the
millimetres-per-column scale so plan proportions look correct in non-square
terminal cells. Normal and coarse `h/j/k/l` cursor movement automatically pans
at the `canvas.scrolloff` margin, so zoomed navigation does not stop at the
visible boundary.

Wall outlets use inward-facing half circles; floor outlets use full circles.
Both use the colorscheme-linked `RoomPlanOutlet` highlight.

## Detail levels

The default `middle` level shows object labels and dimensions for every
exterior wall run. `high` additionally shows furniture width/depth and
door/window width dimensions. `none` leaves geometry only, with no labels or
dimensions.
Use `t` to cycle levels or
`:RoomPlanCanvasDetail high|middle|none|cycle` to choose explicitly. The level
belongs to the live session and never dirties or rewrites the plan.

The header contains the plan state and, by default, a compact compass. The
action bar below the canvas reports mode, saved/dirty/conflict state, snapping,
and zoom. A selected object adds one compact breadcrumb, for example
`Office › Floor outlet · Power · 2 slots`; it disappears with the selection
instead of occupying another pane. Empty plans show a first-room card; if
geometry is outside the viewport, the canvas explicitly suggests `f` instead
of appearing blank.

## Selection and movement

Move the logical cursor with `h j k l` and press `Enter` to select. Multiple
objects can share a cell; pressing Enter repeatedly cycles the exact hit list.
Selection highlights all cells belonging to the semantic object, not just its
label.

In MOVE mode, changes are expressed in world millimetres and recorded as model
actions. View rotation only changes how direction keys are projected, so
moving right on screen still looks right. Grid and geometric snapping are
view-scale aware and capped by `snapping.max_distance_mm`. The breadcrumb adds
the active object, last visible direction and distance, and named snap target.
At deep zoom, the plan's existing `fine_step_mm` is the minimum magnetic range
(still capped by `snapping.max_distance_mm`), so tiny millimetre remainders snap
cleanly instead of requiring repeated Ctrl-directions.

## Live dimension resizing

Select a room or furniture item and press `r` to resize its rectangular union
directly on the canvas. One section is highlighted at a time. `Enter` selects under the cursor,
`Tab` cycles sections, and the usual direction keys use normal, coarse, or fine
plan steps. The first horizontal/vertical key chooses the corresponding west,
east, south, or north edge; the status keeps that handle visible while opposite
directions grow or shrink it. `a` adds an adjoining section and `d` removes one. `s` commits the
whole preview as one history action and saves the plan; `Esc` discards it. The header/action
bar identifies `RESIZE`, the active section and edge, the last step, and any
named snap target. Nearby section edges and
other-room walls take snap precedence over the grid; a light guide shows the
alignment and extends just beyond the target wall so horizontal and vertical
connections stay visible. Every positive-length exterior wall overlap around
the final room or furniture silhouette is strongly highlighted, including
separate wall segments that share the same coordinate; the target names remain
available in status. Centres can align to centres but are never misreported as
wall contact. `gs` toggles snapping and `g!` bypasses the next change.
Moving away releases a snap immediately, even with fine steps. Use ordinary
`m` movement to move the whole room and its furniture with the same snap
feedback. See
[Rooms](../planning/rooms.md) for the topology and wall-feature safeguards.

See [Appearance](../display/appearance.md) for glyphs/highlights and
[Aspect and rotation](../display/aspect-and-rotation.md) for calibration.

← [Forms and actions](forms-and-actions.md) | [Documentation home](../README.md) | [Rooms](../planning/rooms.md) →
