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

Select furniture and use:

- `e` to edit room, template, label, geometry where available, position, and
  rotation;
- `?`, then `/` and `shape`, to open direct section editing without adding a
  permanent furniture shortcut;
- `m` plus directions to move by the configured plan steps;
- `r` to rotate one quarter-turn;
- `y` to duplicate it;
- `d` to delete it.

Movement and rotation are semantic actions with undo/redo and validation.
Snapping can target room edges/centres, doors, furniture, and grid according
to the configured priority.

Built-in and imported rectangle templates become canonical one-part footprints
when placed. Loaded compound furniture can be moved, rotated, duplicated,
validated, rendered, shape-edited, and saved without flattening it. Its
rectangle-only width/depth form controls remain hidden; label, category,
room-local position, height, and rotation stay editable there.

## Direct shape editing

Choose **Edit furniture shape** from the full `?` action popup. The canvas then
uses the same `RESIZE` interaction as rooms: `Enter` or `Tab` selects a section,
direction keys choose and resize its visible edge, `a` adds an adjoining
same-sized section, and `d` removes the selected section. `s` applies the
complete footprint as one undo step and saves; `Esc` cancels it.

The item's doubled-mm anchor and room-local position remain fixed, including
through quarter-turn rotations. RoomPlan rejects any resize or removal that
would leave the anchor outside the footprint. Snapping is calculated in world
space against other sections, room walls, furniture, and the plan grid, then
converted back to the item's local rotated geometry.

Editing a placed item changes only that item. Its source project/imported
template is not silently rewritten; direct project-template shape editing and
an explicit update-template workflow remain separate roadmap work.

## Project templates

Enable **Save as project template** while adding furniture to create a
`custom:*` template with the current footprint and height. Project templates
are saved inside that plan, appear as top-level Objects rows, and can be edited
with `e`. Existing placed furniture keeps explicit geometry when its template
is edited. Loaded compound project templates are preserved; their
rectangle-only size controls are hidden until direct template shape editing is
implemented.

For reusable personal or team defaults that should not be copied into every
plan, use [Furniture catalogues](furniture-catalogs.md).

← [Windows and outlets](windows-and-outlets.md) | [Documentation home](../README.md) | [Furniture catalogues](furniture-catalogs.md) →
