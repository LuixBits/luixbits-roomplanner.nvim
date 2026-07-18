local action_registry = require("roomplan.ui.action_registry")
local mappings = require("roomplan.ui.mappings")
local workspace_state = require("roomplan.ui.workspace_state")
local render = require("roomplan.ui.workspace.render")
local util = require("roomplan.ui.workspace.util")

local M = {}

function M.select_focused(api, session)
  local workspace = session and session.workspace
  if not workspace then return false end
  local role = workspace.state.focused_pane
  if role ~= "objects" and role ~= "issues" then return false end
  local row = render.selected_row(session, role)
  if not row then return false end
  local selection = row.kind == "plan" and { kind = "plan" }
    or (row.kind and row.id and { kind = row.kind, id = row.id }) or nil
  session.selection = selection
  if role == "issues" then session.validation_index = row.index end
  render.refresh(session)
  local canvas_ok, canvas = pcall(require, "roomplan.render.canvas")
  if canvas_ok and canvas.schedule_redraw then canvas.schedule_redraw(session, "workspace-selection") end
  if workspace.opts.on_selection then
    workspace.opts.on_selection(session, selection, row)
  else
    api.focus(session, "canvas")
  end
  return selection
end

function M.set_filter(_, session, pane, value)
  local workspace = session and session.workspace
  if not workspace then return false end
  workspace.state = workspace_state.reduce(workspace.state, { type = "filter", pane = pane, value = value })
  render.refresh(session, { pane, "action_bar" })
  return true
end

function M.set_interaction(_, session, mode, form)
  local workspace = session and session.workspace
  if not workspace then return false end
  local previous = workspace.state.interaction
  workspace.state = workspace_state.reduce(workspace.state, { type = "interaction", mode = mode })
  workspace.state.form = form
  render.refresh(session, { "properties", "action_bar" })
  if previous ~= workspace.state.interaction then
    local ok, canvas = pcall(require, "roomplan.render.canvas")
    if ok and canvas.schedule_redraw then canvas.schedule_redraw(session, "workspace-interaction") end
  end
  return true
end

function M.update_cursor(_, session, world, zoom)
  local workspace = session and session.workspace
  if not workspace then return false end
  workspace.state = workspace_state.reduce(workspace.state, { type = "cursor", world = world, zoom = zoom })
  render.refresh(session, "action_bar")
  return true
end

function M.filter_prompt(api, session, pane)
  local workspace = session and session.workspace
  if not workspace then return end
  local generation = workspace.generation
  vim.ui.input({
    prompt = "Filter RoomPlan " .. pane .. ": ",
    default = workspace.state.filters[pane] or "",
    scope = "window",
  }, function(value)
    if value == nil or not session.workspace or session.workspace.generation ~= generation then return end
    api.set_filter(session, pane, value)
  end)
end

function M.expand_focused(_, session, value)
  local workspace = session and session.workspace
  if not workspace or workspace.state.focused_pane ~= "objects" then return false end
  local row = render.selected_row(session, "objects")
  if not row or not row.expandable then return false end
  workspace.state = workspace_state.reduce(workspace.state, {
    type = "set_expanded",
    id = row.id,
    value = value,
  })
  render.refresh(session, { "objects", "action_bar" })
  return true
end

function M.collapse_focused(api, session)
  return M.expand_focused(api, session, false)
end

function M.filter_focused(api, session)
  local workspace = session and session.workspace
  if not workspace then return false end
  local pane = workspace.state.focused_pane
  if pane ~= "objects" and pane ~= "issues" then return false end
  M.filter_prompt(api, session, pane)
  return true
end

function M.set_details_section(_, session, expanded)
  local workspace = session and session.workspace
  if not workspace or workspace.state.focused_pane ~= "properties" then return false end
  local row = render.selected_row(session, "properties")
  if not row or row.kind ~= "section" or not row.section then return false end
  workspace.state = workspace_state.reduce(workspace.state, {
    type = "set_section",
    key = row.section,
    expanded = expanded,
  })
  render.refresh(session, "properties")
  return true
end

function M.toggle_details_section(_, session)
  local workspace = session and session.workspace
  if not workspace or workspace.state.focused_pane ~= "properties" then return false end
  local row = render.selected_row(session, "properties")
  if not row or row.kind ~= "section" or not row.section then return false end
  workspace.state = workspace_state.reduce(workspace.state, {
    type = "set_section",
    key = row.section,
    expanded = not row.expanded,
  })
  render.refresh(session, "properties")
  return true
end

local function notify_disabled(action)
  local ok, compat = pcall(require, "roomplan.compat")
  if ok then compat.notify(action.reason, vim.log.levels.WARN) end
end

function M.invoke(api, session, id)
  local workspace = session and session.workspace
  if not workspace then return false end
  local action = action_registry.get(id, render.context(session, workspace))
  if not action then return false end
  if not action.enabled then
    notify_disabled(action)
    return false, action.reason
  end
  if action.workspace then return api.focus(session, action.workspace) end
  if action.workspace_action then
    local handler = api[action.workspace_action]
    if type(handler) ~= "function" then
      return false, "missing RoomPlan workspace action " .. tostring(action.workspace_action)
    end
    return handler(session, unpack(action.args or {}))
  end
  if action.form then
    if workspace.opts.on_form_action then return workspace.opts.on_form_action(session, action.form, action) end
    if action.form == "cancel" then
      if session.workflow and session.workflow.kind then
        require("roomplan.ui.flow").cancel(session, "cancelled")
      else
        require("roomplan.controller").escape(session)
      end
      render.refresh(session)
      return true
    end
    return false, "no structured form is active"
  end
  if id == "help" then return require("roomplan.ui.help").open(session) end
  if id == "hide" then return api.hide(session) end
  if workspace.opts.on_action then return workspace.opts.on_action(session, action) end
  local controller = require("roomplan.controller")
  local handler = controller[action.handler]
  if type(handler) ~= "function" then return false, "missing RoomPlan handler " .. tostring(action.handler) end
  local result = handler(session, unpack(action.args or {}))
  vim.schedule(function()
    if session.workspace and not session.workspace.closed then render.refresh(session) end
  end)
  return result
end

function M.invoke_key(api, session, key)
  local workspace = session and session.workspace
  if not workspace then return false end
  local action = action_registry.by_key(render.context(session, workspace), key)
  if not action then return false end
  return M.invoke(api, session, action.id)
end

function M.escape(api, session)
  local workspace = session and session.workspace
  if not workspace then return false end
  if workspace.windows.drawer then return api.focus(session, "canvas") end
  if (session.workflow and session.workflow.kind) or workspace.state.form or session.mode ~= "NAV" then
    require("roomplan.controller").escape(session)
    render.refresh(session)
    return true
  end
  if workspace.state.focused_pane ~= "canvas" then return api.focus(session, "canvas") end
  require("roomplan.controller").escape(session)
  render.refresh(session)
  return true
end

function M.map_common(api, session, buffer, role)
  local function map(lhs, rhs, desc, name)
    return mappings.set(buffer, lhs, rhs, desc, name)
  end
  local workspace = session.workspace
  if not workspace or workspace.opts.cycle_tabs ~= false then
    map("<Tab>", function() api.cycle_focus(session, 1) end, "Next RoomPlan workspace pane", "workspace_next_pane")
    map("<S-Tab>", function() api.cycle_focus(session, -1) end,
      "Previous RoomPlan workspace pane", "workspace_previous_pane")
  end
  map("1", function() api.toggle(session, "objects") end, "Toggle RoomPlan navigator", "focus_objects")
  map("2", function() api.focus(session, "canvas") end, "Focus RoomPlan canvas", "focus_canvas")
  map("3", function() api.toggle(session, "properties") end, "Toggle RoomPlan details", "focus_properties")
  map("!", function() api.toggle(session, "issues") end, "Toggle RoomPlan issues", "focus_issues")
  map("o", function() api.toggle(session, "objects") end, "Toggle RoomPlan navigator", "objects")
  map("i", function() api.toggle(session, "properties") end, "Toggle RoomPlan details", "inspector")
  map("<Esc>", function() api.escape(session) end, "Leave RoomPlan workspace mode", "escape")
  map("q", function()
    local current = session.workspace
    if current and current.windows.drawer then api.focus(session, "canvas") else api.hide(session) end
  end, "Hide RoomPlan workspace", "hide")
  for _, id in ipairs({
    "add", "edit", "move", "pan", "align", "rotate", "duplicate", "delete",
    "validate", "save", "fit", "cycle_detail_level", "help",
    "add_door", "add_window", "add_outlet", "add_furniture", "undo", "redo",
    "rotate_view_clockwise", "rotate_view_counterclockwise", "reset_view", "apply", "reset", "shape_apply",
    "next_issue", "previous_issue",
  }) do
    local definition = action_registry.get(id, { keymaps = require("roomplan.config").get().keymaps })
    local lhs = definition and definition.key
    if lhs then
      local action_id = id
      mappings.set(buffer, lhs, function() api.invoke(session, action_id) end,
        "RoomPlan " .. action_id, nil, { enabled = true, mappings = {} })
    end
  end
  if role == "objects" or role == "issues" then
    map("<CR>", function() api.select_focused(session) end, "Select RoomPlan row", "workspace_activate_focused")
    map("/", function() api.filter_prompt(session, role) end, "Filter RoomPlan rows", "workspace_filter_focused")
  end
  if role == "objects" then
    map("h", function() api.expand_focused(session, false) end,
      "Collapse RoomPlan room", "workspace_collapse_focused")
    map("l", function() api.expand_focused(session, true) end,
      "Expand RoomPlan room", "workspace_expand_focused")
  elseif role == "properties" then
    map("<CR>", function() api.toggle_details_section(session) end,
      "Toggle RoomPlan details section", "workspace_toggle_details_section")
    map("<Space>", function() api.toggle_details_section(session) end, "Toggle RoomPlan details section")
    map("h", function() api.set_details_section(session, false) end, "Collapse RoomPlan details section")
    map("l", function() api.set_details_section(session, true) end, "Expand RoomPlan details section")
  end
end

function M.apply_canvas_keymaps(api, session, opts)
  opts = opts or {}
  local workspace = session and session.workspace
  local buffer = workspace and workspace.canvas_bufnr
  if not util.valid_buffer(buffer) then return false end
  local function map(lhs, rhs, desc, name)
    return mappings.set(buffer, lhs, rhs, desc, name)
  end
  if opts.cycle_tabs ~= false then
    map("<Tab>", function()
      if session.shape_edit then require("roomplan.controller").cycle_room_shape_part(session, 1)
      else api.cycle_focus(session, 1) end
    end, "Next RoomPlan workspace pane or room section", "workspace_next_pane")
    map("<S-Tab>", function()
      if session.shape_edit then require("roomplan.controller").cycle_room_shape_part(session, -1)
      else api.cycle_focus(session, -1) end
    end,
      "Previous RoomPlan workspace pane", "workspace_previous_pane")
  end
  map("1", function() api.toggle(session, "objects") end, "Toggle RoomPlan navigator", "focus_objects")
  map("2", function() api.focus(session, "canvas") end, "Focus RoomPlan canvas", "focus_canvas")
  map("3", function() api.toggle(session, "properties") end, "Toggle RoomPlan details", "focus_properties")
  map("!", function() api.toggle(session, "issues") end, "Toggle RoomPlan issues", "focus_issues")
  return true
end

return M
