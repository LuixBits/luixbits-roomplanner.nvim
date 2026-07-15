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

The form draft is transient. Apply creates exactly one semantic history entry;
cancel creates none. If the model changes while a form is open, the stale form
refuses to apply rather than overwriting newer state.

## Contextual actions

The one-line action bar changes with focus, selection, and mode. It hides
irrelevant or unmapped actions to remain compact. `?` opens the full grouped
action window and explains why actions such as Align or Rotate are unavailable.
Press `/` in that window to search labels, descriptions, groups, IDs, and keys;
submit an empty search to restore the complete list.
`:RoomPlan` opens the same context-aware action surface for the active session.

Common actions are `a` (Add), `e` (Edit), `m` (Move), `A` (Align), `r`
(resize a room or rotate furniture), `y` (Duplicate), and `d` (Delete). `D`, `W`, `O`, and `F`
open Door, Window, Outlet, and Furniture directly; the `a` Add menu uses
lowercase `d`, `w`, `o`, and `f`. Deleting a room summarizes and confirms its
cascading doors, windows, outlets, and furniture when deletion confirmation is
enabled.

Add Room and Align include **Allow invalid draft** for deliberate repair work.
It never hides the resulting diagnostics, and ordinary save rules still
apply.

← [Workspace panels](panels.md) | [Documentation home](../README.md) | [Canvas](canvas.md) →
