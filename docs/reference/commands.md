# Commands

The plugin loader registers commands as soon as RoomPlan is sourced. `setup()`
is needed only for non-default configuration.

## Sources and sessions

| Command | Purpose |
| --- | --- |
| `:RoomPlan` | Open the context-aware action window, choose a session, or start from the current source |
| `:RoomPlanOpen [path]` | Open/focus a `.roomplan.json` or Norg plan; no path uses the current buffer |
| `:RoomPlanInit [path]` | Safely initialize an empty standalone source or Norg block |
| `:RoomPlanHide` | Hide workspace windows while retaining the live session |
| `:RoomPlanClose[!]` | Close the session; `!` deliberately discards protected state |
| `:RoomPlanSave[!]` | Save; `!` permits a structurally valid layout-invalid repair draft |
| `:RoomPlanSaveAs[!] path` | Rebind to a destination; `!` confirms replacement of an existing valid JSON target |
| `:RoomPlanReload[!]` | Reload the source; `!` deliberately discards protected state |
| `:RoomPlanResolveConflict` | Review, reload, Save As, or safely confirm overwrite of a changed source |

Initialization never overwrites a non-empty standalone file. Save As refuses
links/special files and malformed destinations; its bang is not permission to
bypass structural validation or source-conflict checks.

## Model actions

| Command | Purpose |
| --- | --- |
| `:RoomPlanAddRoom` | Open Add Room form |
| `:RoomPlanAlign` | Align the selected room against another room |
| `:RoomPlanAddDoor` | Open Add Door form |
| `:RoomPlanAddWindow` | Open Add Window form |
| `:RoomPlanAddOutlet` | Open Add Outlet form |
| `:RoomPlanAddFurniture` | Open Add Furniture form |
| `:RoomPlanEdit` | Edit the selected plan, room, door, window, outlet, furniture, or project template |
| `:RoomPlanDuplicate` | Duplicate the selected room, door, window, outlet, furniture, or project template |
| `:RoomPlanDelete` | Delete selection; room dependencies are confirmed as one cascade |
| `:RoomPlanUndo` / `:RoomPlanRedo` | Move through semantic model history |

## Workspace, view, and validation

| Command | Purpose |
| --- | --- |
| `:RoomPlanToggleNavigator` | Focus/show Navigator, or hide it when already active |
| `:RoomPlanToggleDetails` | Focus/show Details, or hide it when already active |
| `:RoomPlanValidate` | Revalidate and focus Issues |
| `:RoomPlanNextIssue` / `:RoomPlanPrevIssue` | Select the next/previous diagnostic |
| `:RoomPlanFit` | Fit scene geometry to the canvas |
| `:RoomPlanCanvasDetail [high\|middle\|none\|cycle]` | Set canvas detail, or cycle when omitted |
| `:RoomPlanAspect [ratio]` | Prompt for or set terminal cell height/width calibration |
| `:RoomPlanRotateView [clockwise\|counterclockwise\|reset]` | Rotate only the viewport projection |

The following convenience aliases remain available:

| Alias | Equivalent behaviour |
| --- | --- |
| `:RoomPlanMenu` | `:RoomPlan` |
| `:RoomPlanObjects` | Focus/toggle Navigator |
| `:RoomPlanInspect` | Focus/toggle Details |

Commands target the session attached to the current source, canvas, workspace,
form, or palette buffer. When no buffer owns a session, exactly one live
session is an unambiguous fallback. Use `:RoomPlan` to choose when several are
open. Canvas detail is session-local presentation and never changes model
history.

← [Keymaps](../configuration/keymaps.md) | [Documentation home](../README.md) | [Lua API](lua-api.md) →
