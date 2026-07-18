# Forms and actions

RoomPlan groups related changes in structured forms. A room, door, window,
outlet, furniture, alignment, plan-settings, or project-template form shows
every relevant field, derived values, validation messages, and a preview at
once.

## Form controls

| Key | Action |
| --- | --- |
| `j` / `k`, `Tab` / `Shift-Tab` | Move between visible fields |
| `Enter` or `e` | Edit text/measurement or open a choice list |
| `h` / `l` | Move through choices |
| `Space` | Toggle a boolean field |
| `Ctrl-s` | Validate and apply the whole draft |
| `R` | Reset every field to the form's initial state |
| `Esc` or `q` | Cancel without changing the plan |

Measurements accept exact `mm`, `cm`, and `m` input. A suffixless value means
millimetres. Only values that resolve to whole millimetres are accepted, so
`5m`, `500cm`, and `5000mm` are equivalent while `0.5mm` is rejected.

Room and furniture Color fields use the same choice-list controls. Enhanced
`vim.ui.select` providers may present the palette as a searchable popup; the
form and saved data do not depend on a particular provider.

The form draft is transient. Apply creates exactly one semantic history entry;
cancel creates none. If the model changes while a form is open, the stale form
refuses to apply rather than overwriting newer state.

## Contextual actions

The one-line action bar changes with focus, selection, and mode. It hides
irrelevant or unmapped actions to remain compact. `?` opens the full grouped
action window and explains why actions such as Align or Rotate are unavailable.
Press `/` in that window to search labels, descriptions, groups, IDs, and keys;
the search row stays inside the popup and reduces the visible actions after
every character. It is a dedicated native prompt over a fixed, read-only
results window, so filtering cannot move its cursor or focus. `Backspace` edits
the query, `Enter` runs the first match, and `Esc` returns focus to the filtered
results without running anything. Clear the query to restore the complete list.
`:RoomPlan` opens the same context-aware action surface for the active session.

A useful selection also adds a short room/object breadcrumb to that same line;
MOVE and RESIZE extend it with direction, distance, section/edge, and snap
feedback. It adds no mapping, never replaces an action hint that already fits,
and is clipped with the rest of the one-line status on narrow layouts. Complete
properties remain in Details rather than being repeated in the footer.

The ordinary `e` popup is a discoverable entry point for compound-shape
editing. Room, furniture, and project-template forms include **Edit footprint**;
row; pressing `Enter` there opens the shared canvas section controls. If other
popup fields changed first, RoomPlan validates and applies them before the
transition. Project templates use an isolated local preview. When a placed item
references a project-local template, saving opens a second compact popup for
**This item only** versus **Item + project template**. Neither choice rewrites
other placed items. Lowercase `r` enters the same live resize directly for
rooms, furniture, and project templates; uppercase `R` rotates furniture.

Common actions are `a` (Add), `e` (Edit), `m` (Move), `A` (room alignment or
equal furniture spacing), `r`
(live resize), `R` (rotate furniture), `y` (Duplicate), and `d` (Delete). `D`, `W`, `O`, and `F`
open Door, Window, Outlet, and Furniture directly; the `a` Add menu uses
lowercase `d`, `w`, `o`, and `f`. Deleting a room summarizes and confirms its
cascading doors, windows, outlets, and furniture when deletion confirmation is
enabled.

Add Room and room alignment include **Allow invalid draft** for deliberate repair work.
It never hides the resulting diagnostics, and ordinary save rules still
apply.

← [Workspace panels](panels.md) | [Documentation home](../README.md) | [Canvas](canvas.md) →
