# Furniture

Furniture belongs to a room and moves with it. An item can use one rectangle
or a connected footprint made from several rectangular sections. Rotation is
limited to quarter turns.

## Add furniture

Press `F` or run `:RoomPlanAddFurniture`. Choose a room and a built in,
imported, or project template. The template supplies initial values. The
placed item keeps its own label, category, footprint, height, and rotation.

Place the item at the room centre, at the canvas cursor, or at exact local
coordinates. Its full footprint must stay inside the room and must not overlap
other furniture.

The add and edit forms show a shape preview when space allows. This preview is
only visual. It does not alter the plan or its undo history.

## Common actions

| Key | Action |
| --- | --- |
| `e` | Edit details and available dimensions |
| `m` | Move the item |
| `r` | Edit the footprint on the canvas |
| `R` | Rotate by 90 degrees |
| `y` | Duplicate the item |
| `d` | Delete the item |

Movement and rotation use the same validation and undo rules as other plan
changes. Snapping can target room edges, centres, doors, furniture, and the
grid.

Open `?` and choose **Place furniture against wall** for exact wall placement.
You can align the item with the start, centre, or end of a wall segment and set
a clearance. **Measure exact clearance** compares rooms or furniture without
changing the plan.

## Edit a compound footprint

Press `r`, or choose **Edit footprint** from the `e` form. The canvas uses the
same `RESIZE` controls as room editing.

| Key | Action |
| --- | --- |
| `Enter` | Select the section under the cursor |
| `Tab` / `Shift-Tab` | Select another section |
| Direction keys | Choose and move an edge |
| `a` | Add an adjoining section |
| `d` | Remove the selected section |
| `s` | Apply the footprint and save |
| `Esc` | Cancel the edit |

The furniture anchor stays fixed while you edit its shape. RoomPlan rejects a
change that leaves the anchor outside the footprint or places the item outside
its room.

If the item came from a project template, saving offers two scopes:

- **This item only** changes the selected item.
- **Item + project template** also changes the default for future placements.

Existing items keep their own geometry in both cases. Built in and imported
catalogue templates are read only, so their placed items use the first scope.

## Project templates

Enable **Save as project template** while adding furniture to store a reusable
template in the current plan. Project templates appear in Objects and can be
edited with `e` or `r`.

Changing a project template affects future placements. Existing furniture is
not changed unless you use the combined save scope from a placed item.

For defaults that should be available across plans, use
[Furniture catalogues](furniture-catalogs.md).

← [Windows and outlets](windows-and-outlets.md) | [Documentation home](../README.md) | [Furniture catalogues](furniture-catalogs.md) →
