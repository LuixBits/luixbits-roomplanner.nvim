# Workspace panels

The side panels keep object lists and detailed information out of the Canvas.

## Objects

Objects lists the plan, its rooms, and each room's doors, windows, outlets, and
furniture. Project furniture templates appear at the top level. Diagnostic
markers show which objects need attention.

| Key | Action |
| --- | --- |
| `j` / `k` | Move through rows |
| `Enter` | Select the row and return to the Canvas |
| `h` / `l` | Collapse / expand a room |
| `/` | Filter by kind, ID, name, label, or room |
| `Space` | Mark or unmark an object |

Marked objects can move, duplicate, or delete together. Open `?` to find those
actions. One operation creates one undo entry. A failed operation changes
nothing.

If a marked room owns marked furniture, the furniture moves with the room only
once. Doors are not batch duplicated because their placement needs a wall.

## Issues

Press `v` to validate and open Issues. Errors block a normal save. Warnings do
not.

Use `Alt-j` and `Alt-k` for the next and previous issue. `Enter` selects and
centres the affected object without changing zoom or rotation. Press `/` to
filter the list.

Objects and Issues share one side slot. Press `1` for Objects and `!` for
Issues.

## Details

Details shows facts about the selected plan or object. It includes room area,
wall placement, door swing, furniture position, source information, and
validation messages where relevant.

The first section lists Canvas controls for the current mode. These keys come
from the same action data as the footer and `?`. Press `2` before using a Canvas
control while Details has focus.

Use `Enter` or `Space` to toggle a section. Use `h` and `l` to collapse or
expand it. Details is read-only. Press `e` to edit the selected object.

## Visibility

`1` toggles Navigator and `3` toggles Details. In compact layouts these keys
open centered drawers. Manual visibility choices survive later layout changes.

← [Navigation](navigation.md) | [Documentation home](../README.md) | [Forms and actions](forms-and-actions.md) →
