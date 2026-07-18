local action_registry = require("roomplan.ui.action_registry")
local list = require("roomplan.ui.list")

local M = {}

local focus_labels = {
  canvas = "Canvas",
  objects = "Navigator · Objects",
  issues = "Navigator · Issues",
  properties = "Details",
  form = "Form",
}

local reference_lines = {
  "roomplan.nvim workspace help",
  "============================",
  "1/o Navigator, 2 Canvas, 3/i Details, ! Issues",
  "<Tab>/<S-Tab> cycle panes; ? opens actions; / searches there",
  "NAV: h/j/k/l cursor, <Enter> select",
  "m MOVE mode, p PAN mode, <Esc> cancel/mode/deselect",
  "a add; D/F/W/O add door/furniture/window/outlet",
  "e exact edit, r live resize, R rotate furniture",
  "d delete, y duplicate",
  "v validate, Alt-k/Alt-j previous/next issue",
  "<C-h/j/k/l> fine move; u undo, <C-r>/U redo",
  ",/. zoom out/in, f fit, zh/zj/zk/zl pan",
  "t cycles canvas detail: high / middle / none",
  "Alt-l/Alt-h rotate view, g0 restore north-up",
  "gs toggle snapping, g! bypass next snap, s save, S Save As",
  "q returns toward the canvas, then hides the retained session",
  "",
  "Mappings are buffer-local and may be changed in setup().",
}

local function context(session, workspace)
  local workspace_ok, workspace_module = pcall(require, "roomplan.ui.workspace")
  if workspace_ok and workspace_module.action_context then return workspace_module.action_context(session) end
  local presenter = require("roomplan.ui.presenter")
  local ctx = presenter.context(session, workspace and workspace.state)
  if session and session.history then
    ctx.can_undo = type(session.history.can_undo) == "function" and session.history:can_undo() or nil
    ctx.can_redo = type(session.history.can_redo) == "function" and session.history:can_redo() or nil
  end
  local ok, config = pcall(require, "roomplan.config")
  if ok and config.get then ctx.keymaps = config.get().keymaps end
  if workspace and workspace.state then
    ctx.form = workspace.state.form
    if ctx.form then ctx.focus = "form" end
  end
  return ctx
end

function M.reference(session)
  return list.open(session, { role = "help", filetype = "help", lines = reference_lines })
end

---Open the complete action list for a workspace. The registry owns labels,
---keys, ordering and disabled reasons; the workspace remains the dispatcher.
function M.open(session, opts)
  opts = opts or {}
  local workspace = session and session.workspace
  if not workspace then return M.reference(session) end

  local ctx = opts.context or context(session, workspace)
  local actions = action_registry.full(ctx, { include_disabled = true, exclude = { "help" } })
  local on_action = opts.on_action or function(action)
    return require("roomplan.ui.workspace").invoke(session, action.id)
  end
  for _, action in ipairs(actions) do
    action.callback = function(chosen) return on_action(chosen) end
  end

  local focus = focus_labels[ctx.focus] or tostring(ctx.focus or "canvas"):gsub("^%l", string.upper)
  return require("roomplan.ui.palette").open({
    session = session,
    title = opts.title or ("RoomPlan actions · " .. focus),
    items = actions,
    grouped = true,
    searchable = true,
    resolve_keys = false,
    border = opts.border or workspace.opts and workspace.opts.border,
  })
end

return M
