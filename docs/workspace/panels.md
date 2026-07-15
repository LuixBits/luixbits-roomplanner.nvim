# Workspace panels

The side panels provide progressive detail without covering the canvas with
permanent information.

## Navigator: Objects

Objects begins with the plan, then lists rooms in document order. Each room
contains its owned doors, windows, outlets, and furniture. Project-local
furniture templates are top-level rows. Diagnostic markers appear beside
affected objects.

Use `j` / `k` to move, `Enter` to select, `h` / `l` to collapse or expand a
room, and `/` to filter by kind, ID, name, label, or room. Selecting a row
normally returns focus to the canvas while retaining the selection.

## Navigator: Issues

Issues shows the latest validation result with severity, code, object, and
message. `v` refreshes validation and focuses this view; `Alt-k` and `Alt-j` move
between diagnostics. `Enter` selects the affected object, and `/` filters the
list. Errors block a normal save, while warnings do not. See
[Validation](../data/validation.md).

Objects and Issues share the Navigator slot. `1` opens Objects and `!` opens
Issues, so the left side never needs two overlapping lists.

## Details

Details is selection-aware. It shows plan/source summaries when nothing is
selected, room geometry and area, wall-feature placement, door swing,
furniture position and size, or project-template defaults. Stable IDs and
source details live in collapsed sections rather than the primary view.
Validation messages for the selection get their own section.

Sections use drawn borders and behave like accordions: `Enter` or `Space`
toggles the focused heading, while `h` and `l` explicitly collapse and expand.
Use `e` when you want to edit the selected plan or object; Details itself is
read-only.

## Visibility

`1` and `3` toggle Navigator and Details. Their visibility choices survive
reflows, and manually closing a side split records it as hidden. In compact
mode the same keys open temporary centered drawers.

← [Navigation](navigation.md) | [Documentation home](../README.md) | [Forms and actions](forms-and-actions.md) →
