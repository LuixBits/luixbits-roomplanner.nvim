# Furniture

Furniture is one logical room-local footprint made from a connected union of
rectangular parts, with an explicit label, category, height, anchor position,
and rotation. Supported rotations are `0`, `90`, `180`, and `270` degrees.

Press `F` or run `:RoomPlanAddFurniture`. Choose a room and a built-in,
imported, or project template. Template values seed the label, category,
footprint, and height, but the placed item stores its own values and can be
customized before applying.

Placement choices are room centre, canvas cursor, or exact room-local
coordinates. `position_mm` places the item's anchor relative to the room
origin; the persisted doubled-mm anchor preserves exact odd-size centres. An
item must remain inside its owning room and must not overlap another furniture
footprint.

While Add furniture is open, every valid template, size, rotation, and
placement draft appears as a colorscheme-linked ghost on the real canvas.
Invalid field input hides the stale ghost. The preview is not selectable and
never enters the plan, ID reservations, validation, history, undo, or saved
bytes; Apply replaces it with the real item and Cancel removes it.

Select furniture and use:

- `e` to edit room, template, label, geometry where available, position, and
  rotation, or activate **Edit footprint** for direct section editing;
- `r` to enter highlighted live dimension/section resizing immediately;
- `m` plus directions to move by the configured plan steps;
- `R` to rotate one quarter-turn;
- `y` to duplicate it;
- `d` to delete it.

The searchable `?` window adds **Place furniture against wall** without taking
another default key. Its popup lists exact exterior segments of the owner room,
offers start/centre/end or current along-wall alignment, and accepts a clearance
in the same measurement syntax as other forms. Apply is one exact move and one
undo entry. **Measure exact clearance** in the same window compares furniture
or rooms without changing the plan.

Movement and rotation are semantic actions with undo/redo and validation.
Snapping can target room edges/centres, doors, furniture, and grid according
to the configured priority. The final preview highlights every room or
furniture edge segment the complete silhouette touches, including simultaneous
contacts on compound footprints.

Built-in and imported rectangle templates become canonical one-part footprints
when placed. Loaded compound furniture can be moved, rotated, duplicated,
validated, rendered, shape-edited, and saved without flattening it. Its
rectangle-only width/depth form controls remain hidden; label, category,
room-local position, height, and rotation stay editable there.

## Direct shape editing

Press `r` for the direct path, or press `e` and activate **Edit footprint**.
The canvas then uses the same `RESIZE` interaction as rooms: `Enter` or `Tab`
selects a section, direction keys choose and resize its visible edge, `a` adds
an adjoining same-sized section, and `d` removes the selected section. `s`
applies the complete footprint as one undo step and saves; `Esc` cancels it.

The item's doubled-mm anchor and room-local position remain fixed, including
through quarter-turn rotations. RoomPlan rejects any resize or removal that
would leave the anchor outside the footprint. Snapping is calculated in world
space against other sections, room walls, furniture, and the plan grid, then
converted back to the item's local rotated geometry.

For furniture based on a project-local template, `s` opens a compact RoomPlan
popup with two explicit scopes:

- **This item only** changes the selected item and leaves every template and
  peer item unchanged.
- **Item + project template** changes the selected item and the default used by
  future placements as one undo step. Other already placed items remain
  unchanged because they own explicit geometry.

Built-in and imported templates are process-level read-only catalogue entries,
so their placed items use the item-only path. Cancelling the save-scope popup
returns to the active shape draft; it neither commits nor saves anything.

## Project templates

Enable **Save as project template** while adding furniture to create a
`custom:*` template with the current footprint and height. Project templates
are saved inside that plan, appear as top-level Objects rows, and can be edited
with `e`. Press `r` for direct editing, or activate **Edit footprint** in that
popup, to edit its rectangular sections in an isolated local canvas preview.
The usual `Enter`/`Tab`,
directions, `a`, `d`, `s`, and `Esc` controls apply. The plan viewport is
restored afterwards, and the template anchor stays fixed and valid.

Saving a direct template edit changes future placements only. Existing placed
furniture keeps its explicit geometry. Use the placed-item save-scope popup
when the current item and template should receive the same shape atomically.
The scalar `e` form remains the compact editor for template name, category,
height, and canonical rectangle dimensions.

For reusable personal or team defaults that should not be copied into every
plan, use [Furniture catalogues](furniture-catalogs.md).

← [Windows and outlets](windows-and-outlets.md) | [Documentation home](../README.md) | [Furniture catalogues](furniture-catalogs.md) →
