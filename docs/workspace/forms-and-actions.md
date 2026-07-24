# Forms and actions

Forms collect related changes and apply them together. A draft does not change
the plan until you apply it.

## Form controls

| Key | Action |
| --- | --- |
| `j` / `k` | Next / previous field |
| `Tab` / `Shift-Tab` | Next / previous field |
| `Enter` or `e` | Edit the active field |
| `h` / `l` | Previous / next choice |
| `Space` | Toggle or advance a choice |
| `Ctrl-s` | Validate and apply |
| `R` | Reset the draft |
| `?` | Show form actions |
| `q` or `Esc` | Cancel |

Measurements accept `mm`, `cm`, and `m`. A value without a suffix means
millimetres. The result must be a whole millimetre. For example, `5m`, `500cm`,
and `5000mm` are equal. `0.5mm` is rejected.

Applying a form creates one undo entry. Cancelling creates none. A form also
refuses to apply if the plan changed after the form opened.

## Find an action

The action bar shows a short list for the current focus and mode. Press `?` for
the complete list. Disabled actions explain what is missing.

Press `/` in that window to search labels, descriptions, groups, IDs, and keys.
The results update as you type. `Enter` runs the first match. `Esc` returns to
the filtered list.

`:RoomPlan` opens the same action surface for the active session.

## Edit a compound footprint

Room, furniture, and project-template forms include **Edit footprint**. This
opens the shared section editor on the Canvas. Pressing `r` on a selected
object opens the same editor directly.

If you changed other fields first, RoomPlan validates and applies them before
opening the Canvas editor. A project template uses a local preview instead of a
position in the plan.

When furniture refers to a project template, saving the new footprint asks for
the scope:

- **This item only** changes the selected item.
- **Item + project template** also changes the default for future placements.

Existing furniture is never changed in bulk.

## Tools in the action window

Some tools have no default Canvas key. Search for them in `?`.

### Measure exact clearance

Choose two rooms or furniture items. The popup shows nearest clearance,
horizontal and vertical gaps, centre offset, and the closest path. The result
is temporary and does not change the plan.

### Place furniture against a wall

This action appears for selected furniture. Choose a room wall, an alignment,
and a clearance. Applying the form moves the furniture as one undoable change.

### Browse undo history

The history window lists retained revisions and marks the current and saved
ones. Restoring a revision requires confirmation. Editing after an older
restore creates a new history branch.

### Marked-object actions

Mark objects with `Space` in Navigator. The action window can move, duplicate,
delete, or clear the marked set. See [Workspace panels](panels.md).

## Repair drafts

Add Room and Align offer **Allow invalid draft** for deliberate repair work.
The resulting issues remain visible. Normal save rules still apply.

← [Workspace panels](panels.md) | [Documentation home](../README.md) | [Canvas](canvas.md) →
