# Core concepts

[← Quick start](quick-start.md) · [Documentation home](../README.md) · [Next: Workspace overview →](../workspace/overview.md)

RoomPlan separates saved data from its terminal presentation.

## Plan

The plan is structured geometry: metadata, settings, rooms, doors, windows,
outlets, furniture, and project-local furniture templates. Coordinates and
dimensions are stored as integer millimetres. Canvas characters are never
source data.

## Source

A source is either a standalone `*.roomplan.json` document or one marked JSON
block inside a Norg note. The source adapter owns loading, conflict detection,
and saving.

## Session

A session owns the live plan, semantic undo history, source revision, current
selection, viewport, and safety guard. RoomPlan permits several live plans but
only one writable session for a given canonical source.

## Workspace

The workspace is a disposable view of a session. It combines Canvas,
Navigator, Issues, Details, forms, and a contextual action bar. Hiding the
workspace does not discard the session.

This distinction explains two important commands:

- `:RoomPlanHide` removes the view but retains model and history.
- `:RoomPlanClose` unloads the session and therefore confirms protected work.

## Model changes and view changes

Adding, moving, editing, or deleting an object creates a semantic history
entry. Zoom, pan, pane visibility, filtering, aspect calibration, and view
rotation are transient presentation state and are not written into the plan.

[← Quick start](quick-start.md) · [Documentation home](../README.md) · [Next: Workspace overview →](../workspace/overview.md)
