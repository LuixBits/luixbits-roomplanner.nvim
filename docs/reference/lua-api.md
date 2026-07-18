# Lua API

The supported high-level entry point is `require("roomplan")`. Functions that
can fail return `value, err`; asynchronous prompt flows may return before the
optional callback runs. Structured errors contain at least `code` and
`message`.

```lua
local roomplan = require("roomplan")

roomplan.setup({})
roomplan.open({ path = "flat.roomplan.json" }, function(session, err) end)
roomplan.init({ path = "new.roomplan.json", name = "New flat" })
```

## Configuration and lifecycle

| Function | Result |
| --- | --- |
| `setup(opts)` | Validate and install a fresh effective configuration |
| `open(opts[, callback])` | Open/focus a source and return its session |
| `init(opts[, callback])` | Safely initialize a source and return its session |
| `save(opts[, callback])` | Save the resolved session |
| `save_as(path, opts[, callback])` | Save and rebind to another source |
| `reload(opts[, callback])` | Reload the resolved session |
| `hide(opts)` | Hide the resolved workspace without unloading it |
| `close(opts[, callback])` | Close the resolved session |
| `sessions()` | Return live sessions in deterministic session-ID order |

Common source options are `path`, `bufnr` (`0` means current), `filetype`, and
`session_id`. Lua calls are conservative/noninteractive by default; set
`interactive = true` when you want confirmation or selection prompts. Use
`bang = true` only where the matching Ex command documents deliberate force.

```lua
local saved, err = roomplan.save({ session_id = "session-1" })
if not saved then
  vim.notify(err.code .. ": " .. err.message, vim.log.levels.ERROR)
end
```

## View and diagnostics

| Function | Result |
| --- | --- |
| `validate(opts)` | `diagnostics, summary` for the resolved revision |
| `set_aspect(ratio[, opts, callback])` | Set process-wide height/width ratio and refit live sessions |
| `set_canvas_detail(level)` | Set resolved session detail to `high`, `middle`, or `none`; omit level to cycle |
| `rotate_view(direction)` | Rotate resolved viewport; accepts `clockwise`, `counterclockwise`, or `reset` |
| `sun_study()` | Open site setup or the transient sunlight study for the resolved session |

`set_aspect` also accepts one options table containing `ratio`. Canvas detail,
rotation, and aspect are display operations and do not add model history. Sun
study date/time/playback is also transient; its first site setup is a persisted,
undoable plan edit.

`roomplan.aspect` remains a compatibility alias for `set_aspect`; new
configuration should use the canonical name above.

## Semantic dispatch

`require("roomplan.api")` exposes two advanced functions:

```lua
local api = require("roomplan.api")
local result, err = api.dispatch("session-1", {
  type = "move_room",
  id = "room-living",
  delta_mm = { 100, 0 },
})
local session = api.session("session-1")
```

Dispatch copies and validates the model, creates one history revision on
success, and returns no partial model on failure. Action payloads must use the
same integer-mm and stable-ID contracts as the schema. Treat returned session
and model tables as read-only; mutate plans only through dispatch or supported
UI actions. The low-level action vocabulary is intended for integrations and
may grow as new model features are introduced.

← [Commands](commands.md) | [Documentation home](../README.md) | [Troubleshooting](troubleshooting.md) →
