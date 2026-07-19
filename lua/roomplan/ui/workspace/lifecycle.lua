local interaction = require("roomplan.ui.workspace.interaction")
local layout = require("roomplan.ui.workspace.layout")
local render = require("roomplan.ui.workspace.render")
local util = require("roomplan.ui.workspace.util")
local workspace_state = require("roomplan.ui.workspace_state")
local state = require("roomplan.state")

local M = {}

local function synchronize_native_focus(session, workspace)
  if workspace.closed or workspace.hidden or workspace.reflowing then return end
  local pane = layout.pane_for_window(workspace, vim.api.nvim_get_current_win())
  if not pane or workspace.state.focused_pane == pane then return end
  workspace.state = workspace_state.reduce(workspace.state, { type = "focus", pane = pane })
  render.refresh(session, { "objects", "issues", "properties", "action_bar" })
  layout.refresh_window_chrome(workspace)
end

local function schedule_reflow(api, session, workspace, force)
  if workspace.closed then return end
  workspace.reflow_force = workspace.reflow_force or force == true
  if workspace.reflow_scheduled then return end
  workspace.reflow_scheduled = true
  vim.schedule(function()
    workspace.reflow_scheduled = false
    local requested_force = workspace.reflow_force
    workspace.reflow_force = false
    if not workspace.closed then api.reflow(session, requested_force) end
  end)
end

local function install_autocommands(api, session, workspace)
  if workspace.augroup then pcall(vim.api.nvim_del_augroup_by_id, workspace.augroup) end
  workspace.augroup = vim.api.nvim_create_augroup("RoomPlanWorkspace" .. session.id:gsub("[^%w]", ""), { clear = true })
  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    group = workspace.augroup,
    callback = function() schedule_reflow(api, session, workspace) end,
    desc = "Reflow RoomPlan workspace",
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = workspace.augroup,
    callback = layout.define_highlights,
    desc = "Refresh RoomPlan workspace highlights",
  })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = workspace.augroup,
    callback = function() synchronize_native_focus(session, workspace) end,
    desc = "Synchronize native RoomPlan workspace focus",
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = workspace.augroup,
    callback = function(event)
      for _, role in ipairs({ "objects", "issues", "properties" }) do
        if event.buf == workspace.buffers[role] then
          if workspace.state.focused_pane == role then render.refresh(session, "action_bar") end
          return
        end
      end
    end,
    desc = "Refresh contextual RoomPlan actions",
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = workspace.augroup,
    callback = function(event)
      if workspace.closed then return end
      for _, role in ipairs({ "objects", "issues", "properties", "action_bar" }) do
        if event.buf == workspace.buffers[role] then
          state.detach_buffer(event.buf)
          workspace.buffers[role] = nil
          workspace.namespaces[role] = nil
          schedule_reflow(api, session, workspace, true)
          return
        end
      end
    end,
    desc = "Repair wiped RoomPlan workspace buffers",
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = workspace.augroup,
    callback = function(event)
      if workspace.closed or workspace.reflowing then return end
      local closed = tonumber(event.match)
      if closed == workspace.windows.left then
        workspace.windows.left = nil
        workspace.state = workspace_state.reduce(workspace.state, {
          type = "set_pane_visible",
          pane = "navigator",
          visible = false,
        })
        workspace.pending_focus = "canvas"
        schedule_reflow(api, session, workspace, true)
      elseif closed == workspace.windows.properties then
        workspace.windows.properties = nil
        workspace.state = workspace_state.reduce(workspace.state, {
          type = "set_pane_visible",
          pane = "details",
          visible = false,
        })
        workspace.pending_focus = "canvas"
        schedule_reflow(api, session, workspace, true)
      elseif closed == workspace.windows.drawer then
        workspace.windows.drawer = nil
        workspace.drawer_role = nil
        workspace.state = workspace_state.reduce(workspace.state, { type = "focus", pane = "canvas" })
        layout.restore_focus(workspace, "canvas")
      elseif closed == workspace.windows.action_bar then
        workspace.windows.action_bar = nil
        workspace.owns_footer = false
        schedule_reflow(api, session, workspace, true)
      end
    end,
    desc = "Track manually closed RoomPlan panes",
  })
  if util.valid_buffer(workspace.canvas_bufnr) then
    vim.api.nvim_create_autocmd("BufWipeout", {
      group = workspace.augroup,
      buffer = workspace.canvas_bufnr,
      once = true,
      callback = function()
        if workspace.closed then return end
        workspace.hidden = true
        workspace.canvas_winid = nil
        workspace.canvas_bufnr = nil
        layout.close_owned_windows(workspace)
      end,
      desc = "Hide panes with RoomPlan canvas",
    })
  end
end

function M.mount(api, session, opts)
  assert(type(session) == "table", "RoomPlan workspace requires a session")
  opts = util.configured_options(opts)
  local canvas_winid = opts.canvas_winid or (session.canvas and session.canvas.winid)
  local canvas_bufnr = opts.canvas_bufnr or (session.canvas and session.canvas.bufnr)
  assert(util.valid_window(canvas_winid), "RoomPlan workspace requires an open canvas window")
  assert(util.valid_buffer(canvas_bufnr), "RoomPlan workspace requires an open canvas buffer")

  local workspace = session.workspace
  if workspace and not workspace.closed then
    layout.close_owned_windows(workspace)
    workspace.opts = util.merge(workspace.opts, opts)
    workspace.canvas_winid = canvas_winid
    workspace.canvas_bufnr = canvas_bufnr
    workspace.tabpage = vim.api.nvim_win_get_tabpage(canvas_winid)
    workspace.hidden = false
    workspace.generation = workspace.generation + 1
    workspace.namespaces = workspace.namespaces or {}
  else
    workspace = {
      opts = opts,
      state = workspace_state.initial(opts),
      buffers = {},
      namespaces = {},
      windows = {},
      rendered = {},
      canvas_winid = canvas_winid,
      canvas_bufnr = canvas_bufnr,
      tabpage = vim.api.nvim_win_get_tabpage(canvas_winid),
      generation = 1,
      closed = false,
      hidden = false,
    }
    session.workspace = workspace
  end
  layout.define_highlights()
  render.ensure_buffers(session, workspace)
  for role, buffer in pairs(workspace.buffers) do
    interaction.map_common(api, session, buffer, role)
  end
  install_autocommands(api, session, workspace)
  interaction.apply_canvas_keymaps(api, session, { cycle_tabs = opts.cycle_tabs ~= false })
  vim.api.nvim_set_current_tabpage(workspace.tabpage)
  api.reflow(session, true)
  api.focus(session, workspace.state.focused_pane or "canvas")
  return workspace
end

function M.hide(_, session)
  local workspace = session and session.workspace
  if not workspace or workspace.closed then return false end
  layout.close_owned_windows(workspace)
  workspace.hidden = true
  local callback = workspace.opts.on_hide
  if callback then return callback(session) end
  return require("roomplan.render.canvas").close(session)
end

function M.close(_, session, opts)
  opts = opts or {}
  local workspace = session and session.workspace
  if not workspace or workspace.closed then return true end
  workspace.closed = true
  workspace.generation = workspace.generation + 1
  layout.close_owned_windows(workspace)
  if workspace.augroup then pcall(vim.api.nvim_del_augroup_by_id, workspace.augroup) end
  for role, buffer in pairs(workspace.buffers) do
    state.detach_buffer(buffer)
    if util.valid_buffer(buffer) then pcall(vim.api.nvim_buf_delete, buffer, { force = true }) end
    workspace.buffers[role] = nil
  end
  if opts.close_canvas and util.valid_window(workspace.canvas_winid) then
    pcall(function() require("roomplan.render.canvas").close(session) end)
  end
  if session.workspace == workspace then session.workspace = nil end
  return true
end

function M.is_visible(_, session)
  local workspace = session and session.workspace
  return workspace ~= nil
    and not workspace.closed
    and not workspace.hidden
    and util.valid_window(workspace.canvas_winid)
end

function M.owns_window(_, session, winid)
  local workspace = session and session.workspace
  if not workspace then return false end
  for _, owned in pairs(workspace.windows) do
    if owned == winid then return true end
  end
  return false
end

function M.current_layout(_, session) return session and session.workspace and session.workspace.layout or nil end

return M
