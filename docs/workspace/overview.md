# Workspace overview

RoomPlan opens a workspace around the plan Canvas. The Canvas shows the saved
geometry but is not itself the source data.

The workspace has four areas:

- **Canvas** shows the plan and receives movement, resize, zoom, and pan input.
- **Navigator** shows either Objects or Issues.
- **Details** shows information about the selection and the current mode.
- **Action bar** shows useful keys and status for the current context.

Press `?` to see every available action. Disabled actions include a reason.
Press `/` in that window to search.

## Layouts

RoomPlan changes the layout to protect the useful Canvas area.

| Layout | Default size | Result |
| --- | --- | --- |
| Wide | 120 columns or more | Canvas with enabled panes on both sides |
| Medium | 90–119 columns | Canvas with at most one side pane |
| Compact | 89 columns or fewer, or under 22 rows | Canvas with temporary pane drawers |

Pane visibility, selection, filters, and collapsed sections survive a reflow.
Closing a side pane keeps it closed until you open it again.

## Common pane keys

| Key | Area |
| --- | --- |
| `1` | Navigator |
| `2` | Canvas |
| `3` | Details |
| `!` | Issues |
| `Tab` / `Shift-Tab` | Next / previous visible pane |

Pressing the key for an active side pane hides it and returns to the Canvas.

Details lists commands for the current NAV, MOVE, PAN, RESIZE, form, or SUN
STUDY context. Press `2` before using a Canvas command while Details has focus.

## Hide or close

`q` hides the workspace and keeps the live session with its undo history.
Opening the same source restores that session.

`:RoomPlanClose` unloads the session. Unsaved work requires confirmation. See
[Storage and sessions](../data/storage-and-sessions.md) for the complete
lifecycle.

← [Core concepts](../getting-started/concepts.md) | [Documentation home](../README.md) | [Navigation](navigation.md) →
