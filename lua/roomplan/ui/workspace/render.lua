local presenter = require("roomplan.ui.presenter")
local action_registry = require("roomplan.ui.action_registry")
local state = require("roomplan.state")
local util = require("roomplan.ui.workspace.util")

local objects_panel = require("roomplan.ui.panels.objects")
local issues_panel = require("roomplan.ui.panels.issues")
local properties_panel = require("roomplan.ui.panels.properties")
local action_bar = require("roomplan.ui.panels.action_bar")

local M = {}
local roles = { "objects", "issues", "properties", "action_bar" }

local function update_pane_title(workspace, role, title)
  if not title or title == "" then return end
  workspace.pane_titles = workspace.pane_titles or {}
  workspace.pane_titles[role] = title
  local winid = role == "properties" and workspace.windows.properties or nil
  if not util.valid_window(winid) or vim.api.nvim_win_get_config(winid).relative ~= "" then return end
  local active = workspace.state and workspace.state.focused_pane == role
  local group = active and "RoomPlanWorkspaceActiveTitle" or "RoomPlanWorkspaceInactiveTitle"
  vim.wo[winid].winbar = string.format("%%#%s# %s %%*", group, title)
end

local function configure_buffer(bufnr, role)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modeline = false
  vim.bo[bufnr].undolevels = -1
  vim.bo[bufnr].filetype = "roomplan-" .. role:gsub("_", "-")
  vim.bo[bufnr].modifiable = false
end

local function write_buffer(workspace, role, rendered)
  local bufnr = workspace.buffers[role]
  if not util.valid_buffer(bufnr) then return end
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, rendered.lines or {})
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].modified = false
  local namespace = workspace.namespaces[role]
  if not namespace then
    namespace = vim.api.nvim_create_namespace("roomplan-workspace-" .. role .. "-" .. tostring(workspace.generation))
    workspace.namespaces[role] = namespace
  end
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  for _, span in ipairs(rendered.highlights or {}) do
    local row = math.max(0, (tonumber(span.row) or 1) - 1)
    if row < vim.api.nvim_buf_line_count(bufnr) and span.hl_group then
      local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
      local start_col = math.max(0, math.min(#line, tonumber(span.start_col) or 0))
      local options = { hl_group = span.hl_group }
      if span.end_col and span.end_col >= 0 then
        options.end_col = math.max(start_col, math.min(#line, span.end_col))
      else
        options.end_col = #line
        options.hl_eol = true
      end
      vim.api.nvim_buf_set_extmark(bufnr, namespace, row, start_col, options)
    end
  end
  update_pane_title(workspace, role, rendered.pane_title)
end

local function create_buffer(session, workspace, role)
  local bufnr = vim.api.nvim_create_buf(false, true)
  configure_buffer(bufnr, role)
  pcall(vim.api.nvim_buf_set_name, bufnr, string.format("roomplan://workspace/%s/%s", session.id, role))
  workspace.buffers[role] = bufnr
  workspace.namespaces[role] =
    vim.api.nvim_create_namespace(string.format("roomplan-workspace-%s-%s", tostring(session.id), role))
  state.attach_buffer(session, bufnr, "workspace-" .. role)
  return bufnr
end

function M.ensure_buffers(session, workspace)
  local created = {}
  for _, role in ipairs(roles) do
    if not util.valid_buffer(workspace.buffers[role]) then
      create_buffer(session, workspace, role)
      created[#created + 1] = role
    end
  end
  return created
end

local function panel_width(workspace, role)
  local winid = workspace.windows[role]
  if util.valid_window(winid) then return vim.api.nvim_win_get_width(winid) end
  if util.valid_window(workspace.windows.drawer) and workspace.drawer_role == role then
    return vim.api.nvim_win_get_width(workspace.windows.drawer)
  end
  local panes = workspace.layout and workspace.layout.panes or {}
  if role == "properties" and panes.properties then return panes.properties.width end
  if panes.left then return panes.left.width end
  return panes.drawer and panes.drawer.width or math.max(20, math.floor(vim.o.columns * 0.8))
end

local function panel_height(workspace, role)
  local winid = workspace.windows[role]
  if util.valid_window(winid) then return vim.api.nvim_win_get_height(winid) end
  if util.valid_window(workspace.windows.drawer) and workspace.drawer_role == role then
    return vim.api.nvim_win_get_height(workspace.windows.drawer)
  end
  local panes = workspace.layout and workspace.layout.panes or {}
  if role == "action_bar" then return (panes.footer and panes.footer.height) or 2 end
  return (panes.left and panes.left.height)
    or (panes.properties and panes.properties.height)
    or (panes.drawer and panes.drawer.height)
    or math.max(8, vim.o.lines - 4)
end

function M.selected_row(session, role)
  local workspace = session and session.workspace
  if not workspace or not workspace.rendered or not workspace.layout then return nil end
  local rendered = workspace.rendered[role]
  local winid = workspace.layout.kind == "compact" and workspace.windows.drawer
    or role == "properties" and workspace.windows.properties
    or workspace.windows.left
  if not rendered or not util.valid_window(winid) then return nil end
  local line = vim.api.nvim_win_get_cursor(winid)[1]
  return rendered.row_map and rendered.row_map[line]
end

function M.context(session, workspace)
  local ctx = presenter.context(session, workspace and workspace.state)
  if session.history then
    ctx.can_undo = type(session.history.can_undo) == "function" and session.history:can_undo() or nil
    ctx.can_redo = type(session.history.can_redo) == "function" and session.history:can_redo() or nil
  end
  local selection_set = require("roomplan.selection_set")
  local plan = type(session.current_model) == "function" and session:current_model()
    or type(session.model) == "function" and session:model()
    or session.model
  ctx.marked = selection_set.list(plan, session.marked_objects)
  ctx.marked_count = #ctx.marked
  local movable, unsupported = selection_set.move_refs(plan, session.marked_objects)
  ctx.marked_move_count = #movable
  ctx.marked_move_unsupported = #unsupported
  ctx.marked_duplicate_unsupported = 0
  for _, reference in ipairs(ctx.marked) do
    if reference.kind == "door" then ctx.marked_duplicate_unsupported = ctx.marked_duplicate_unsupported + 1 end
  end
  ctx.keymaps = require("roomplan.config").get().keymaps
  ctx.form = workspace and workspace.state.form or nil
  if ctx.form then ctx.focus = "form" end
  if ctx.focus == "objects" or ctx.focus == "issues" or ctx.focus == "properties" then
    ctx.focused_row = M.selected_row(session, ctx.focus)
  end
  local windows = workspace and workspace.windows or {}
  ctx.details_visible = util.valid_window(windows.properties)
    or workspace and workspace.drawer_role == "properties" and util.valid_window(windows.drawer)
    or false
  return ctx
end

function M.action_context(session)
  local workspace = session and session.workspace
  if not workspace then return presenter.context(session) end
  return M.context(session, workspace)
end

local function render_one(session, workspace, role)
  local width, height = panel_width(workspace, role), panel_height(workspace, role)
  local rendered
  if role == "objects" then
    local view = presenter.objects(session, {
      selection = session.selection,
      marked = session.marked_objects,
      expanded = workspace.state.expanded,
      filter = workspace.state.filters.objects,
    })
    rendered = objects_panel.render(view, width, height, {
      active = workspace.state.left_view,
      ascii = workspace.opts.ascii,
    })
  elseif role == "issues" then
    local view = presenter.issues(session, { filter = workspace.state.filters.issues })
    rendered = issues_panel.render(view, width, height)
  elseif role == "properties" then
    local ctx = M.context(session, workspace)
    local control_ctx = vim.deepcopy(ctx)
    if not control_ctx.form then
      control_ctx.focus = "canvas"
      control_ctx.focused_row = nil
    end
    local view = presenter.properties(session)
    view.context_title = action_registry.context_title(control_ctx)
    view.controls = action_registry.context_controls(control_ctx)
    view.controls_note = ctx.focus == "properties" and "Press 2 to use canvas controls · Enter toggles sections" or nil
    rendered = properties_panel.render(view, width, height, {
      collapsed_sections = workspace.state.collapsed_sections,
      ascii = workspace.opts.ascii,
    })
  else
    rendered = action_bar.render(M.context(session, workspace), width, {
      height = height,
      compact_reason = workspace.layout and workspace.layout.compact_reason,
    })
  end
  workspace.rendered[role] = rendered
  write_buffer(workspace, role, rendered)
end

function M.refresh(session, requested_roles)
  local workspace = session and session.workspace
  if not workspace or workspace.closed then return false end
  requested_roles = requested_roles or roles
  if type(requested_roles) == "string" then requested_roles = { requested_roles } end
  for _, role in ipairs(requested_roles) do
    render_one(session, workspace, role)
  end
  return true
end

return M
