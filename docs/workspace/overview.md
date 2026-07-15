# Workspace overview

RoomPlan opens a canvas-first workspace. The canvas is a read-only projection
of the saved model; editing canvas characters never edits the plan.

The workspace has four areas:

- **Canvas** renders rooms, doors, windows, outlets, furniture, selection,
  dimensions, and the compass.
- **Navigator** uses one side slot for either Objects or Issues.
- **Details** shows compact, accordion-style information about the selection.
- **Action bar** shows only the most useful actions for the current pane and
  mode. Press `?` for the complete grouped action palette, including disabled
  actions and their reasons.

Selection is shared by every area. Selecting an Objects or Issues row updates
the canvas and Details; selecting on the canvas updates both side panes.

## Responsive layouts

With the default settings, RoomPlan chooses the layout from the editor size:

| Layout | Default range | Behaviour |
| --- | --- | --- |
| Wide | 120 columns or more | Canvas with any enabled side panes on both sides |
| Medium | 90–119 columns | Canvas plus at most one side pane |
| Compact | 89 columns or fewer, or under 22 rows | Persistent Canvas; side panes open as bordered drawers |

Side panes surrender width before the canvas drops below its configured
minimum. Resize events reflow the workspace while preserving pane visibility,
selection, filters, and collapsed sections.

## Opening and leaving

`:RoomPlanOpen` and `:RoomPlanInit` open the workspace. `q` hides it but keeps
the live session and its history; reopening the same source restores that
session. `:RoomPlanClose` unloads the session and protects unsaved work with a
confirmation. See [Storage and sessions](../data/storage-and-sessions.md) for
the full lifecycle.

The fastest pane controls are `1` for Navigator, `2` for Canvas, `3` for
Details, and `!` for Issues. Pressing the active side-pane key again hides that
pane and returns to Canvas.

← [Core concepts](../getting-started/concepts.md) | [Documentation home](../README.md) | [Navigation](navigation.md) →
