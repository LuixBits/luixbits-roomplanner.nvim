# Canvas

The Canvas draws the plan and accepts spatial input. Its text is not saved as
plan data.

## View controls

| Key | Action |
| --- | --- |
| `f` or `zf` | Fit the plan |
| `.` / `,` | Zoom in / out around the cursor |
| `zh zj zk zl` | Pan directly |
| `p`, then directions | Enter PAN mode |
| `t` | Cycle Canvas detail |
| `M` | Toggle the minimap |
| `Alt-l` / `Alt-h` | Rotate clockwise / counter-clockwise |
| `g0` | Restore plan view/up |
| `S` | Open the sun study |

The minimap appears in the upper-right corner when enough space is available.
It shows all rooms and outlines the area visible in the main Canvas. It follows
zoom, pan, rotation, edits, and window resizing.

View rotation changes only the projection. Saved coordinates do not rotate.
The Canvas uses `cell_aspect` to compensate for terminal cells that are taller
than they are wide.

## Detail levels

| Level | Shows |
| --- | --- |
| `high` | Labels, wall dimensions, furniture dimensions, and door/window widths |
| `middle` | Labels and wall dimensions |
| `none` | Geometry only |

`middle` is the default. Press `t` to cycle the levels or use
`:RoomPlanCanvasDetail high|middle|none|cycle`.

Labels and dimensions shorten or disappear when an object becomes too small on
screen. This keeps fitted views readable. The chosen level belongs to the live
session and does not change the plan.

## Selection

Move the logical cursor with `h j k l`. Press `Enter` to select under it. If
several objects share a cell, press `Enter` again to cycle them.

The header shows plan state and a compass. Before site setup, the compass shows
plan up. Afterwards it shows geographic north. The action bar shows mode,
save state, snapping, zoom, and a short description of the selection.

## Movement

Select an object and press `m`. Normal movement covers at least one visible
cell. Uppercase directions use the coarse step. `Ctrl-h/j/k/l` uses the exact
fine step.

Snapping can target room edges, room centres, doors, furniture, and the grid.
The Canvas names the target and highlights the touching edge. Press `gs` to
toggle snapping or `g!` to bypass the next snap.

Moving a room also moves its furniture. Doors, windows, and wall outlets remain
on their assigned wall. Floor outlets remain inside their room.

## Live resizing

Select a room, furniture item, or project template and press `r`. One section
is active at a time.

| Key | Action |
| --- | --- |
| `Enter` | Select a section under the cursor |
| `Tab` / `Shift-Tab` | Next / previous section |
| `h j k l` | Choose and move an edge |
| `H J K L` | Resize by the coarse step |
| `Ctrl-h/j/k/l` | Resize by the fine step |
| `a` / `d` | Add / remove a section |
| `s` | Apply and save |
| `Esc` | Cancel |

The first horizontal or vertical direction chooses the active edge. The status
keeps that edge visible. Every preview must remain connected, hole-free, and
non-overlapping.

See [Rooms](../planning/rooms.md) for room topology and wall-feature rules. See
[Furniture](../planning/furniture.md) for anchors and template save scope.

## Sun study controls

While a sun study is visible, `h` and `l` change the time. `j` and `k` move
between dates three months apart. `Space` starts or pauses playback. `S`
reopens the form and `Esc` closes the study.

See [Sun study](../planning/sun-study.md) for setup, window heights, and the
limits of the analysis.

## Appearance

Wall outlets use inward-facing half circles. Floor outlets use full circles.
Colors come from semantic Neovim highlight groups and follow the active
colorscheme.

See [Appearance](../display/appearance.md) for glyphs and highlights. See
[Aspect and rotation](../display/aspect-and-rotation.md) if the plan looks
stretched.

← [Forms and actions](forms-and-actions.md) | [Documentation home](../README.md) | [Rooms](../planning/rooms.md) →
