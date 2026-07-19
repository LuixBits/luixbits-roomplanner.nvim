local workspace_state = require("roomplan.ui.workspace_state")
local interaction = require("roomplan.ui.workspace.interaction")
local render = require("roomplan.ui.workspace.render")
local util = require("roomplan.ui.workspace.util")

local M = {}

function M.configure_window(workspace, winid, role, fixed)
  if not util.valid_window(winid) then return end
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = "no"
  vim.wo[winid].foldcolumn = "0"
  vim.wo[winid].foldenable = false
  vim.wo[winid].wrap = false
  vim.wo[winid].spell = false
  vim.wo[winid].list = false
  vim.wo[winid].cursorline = fixed ~= "footer"
  local active = workspace and workspace.state and workspace.state.focused_pane == role
  local border = active and "RoomPlanWorkspaceActiveBorder" or "RoomPlanWorkspaceBorder"
  local floating = vim.api.nvim_win_get_config(winid).relative ~= ""
  vim.wo[winid].winhighlight = table.concat({
    "EndOfBuffer:RoomPlanWorkspaceMuted",
    "WinSeparator:" .. border,
    "FloatBorder:" .. border,
    "CursorLine:RoomPlanWorkspaceCursorLine",
  }, ",")
  local pane_title = workspace and workspace.pane_titles and workspace.pane_titles[role] or util.pane_titles[role]
  if pane_title and not floating then
    local title_group = active and "RoomPlanWorkspaceActiveTitle" or "RoomPlanWorkspaceInactiveTitle"
    vim.wo[winid].winbar = string.format("%%#%s# %s %%*", title_group, pane_title)
  else
    vim.wo[winid].winbar = ""
  end
  if fixed == "width" then vim.wo[winid].winfixwidth = true end
  if fixed == "footer" then
    vim.wo[winid].winfixheight = true
    vim.wo[winid].cursorline = false
  end
end

function M.define_highlights() require("roomplan.highlights").setup() end

function M.close_window(workspace, key)
  local winid = workspace.windows[key]
  workspace.windows[key] = nil
  if util.valid_window(winid) then pcall(vim.api.nvim_win_close, winid, true) end
end

function M.close_owned_windows(workspace)
  -- The canvas is deliberately absent: it is not workspace-owned.
  for _, key in ipairs({ "drawer", "left", "properties", "action_bar" }) do
    M.close_window(workspace, key)
  end
  workspace.drawer_role = nil
  workspace.owns_footer = false
end

local function open_split(buffer, anchor, direction, size)
  -- This command-based path works throughout the supported Neovim 0.10+ range.
  local commands = {
    left = "leftabove vnew",
    right = "rightbelow vnew",
    above = "aboveleft new",
    below = "botright new",
  }
  local previous = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(anchor)
  vim.cmd(assert(commands[direction], "invalid split direction"))
  local winid = vim.api.nvim_get_current_win()
  local placeholder = vim.api.nvim_win_get_buf(winid)
  vim.api.nvim_win_set_buf(winid, buffer)
  if
    placeholder ~= buffer
    and util.valid_buffer(placeholder)
    and vim.api.nvim_buf_get_name(placeholder) == ""
    and not vim.bo[placeholder].modified
  then
    pcall(vim.api.nvim_buf_delete, placeholder, { force = true })
  end
  if util.valid_window(previous) then vim.api.nvim_set_current_win(previous) end
  if direction == "left" or direction == "right" then
    pcall(vim.api.nvim_win_set_width, winid, math.max(1, size))
  else
    pcall(vim.api.nvim_win_set_height, winid, math.max(1, size))
  end
  return winid
end

function M.left_role(workspace)
  local view = workspace.state.left_view
  return (view == "issues" or view == "properties") and view or "objects"
end

function M.show_left_buffer(workspace)
  local winid = workspace.windows.left
  local role = M.left_role(workspace)
  if util.valid_window(winid) and util.valid_buffer(workspace.buffers[role]) then
    vim.api.nvim_win_set_buf(winid, workspace.buffers[role])
    M.configure_window(workspace, winid, role, "width")
  end
end

function M.refresh_window_chrome(workspace)
  M.configure_window(workspace, workspace.windows.left, M.left_role(workspace), "width")
  M.configure_window(workspace, workspace.windows.properties, "properties", "width")
  M.configure_window(workspace, workspace.windows.drawer, workspace.drawer_role)
  M.configure_window(workspace, workspace.windows.action_bar, "action_bar", "footer")
  if util.valid_window(workspace.canvas_winid) then
    local active = workspace.state.focused_pane == "canvas"
    local border = active and "RoomPlanWorkspaceActiveBorder" or "RoomPlanWorkspaceBorder"
    vim.wo[workspace.canvas_winid].winhighlight = "WinSeparator:" .. border
  end
end

local function dimensions(workspace)
  local columns = workspace.opts.columns or vim.o.columns
  local tabline = vim.o.showtabline == 2 and 1 or 0
  local statusline = vim.o.laststatus == 0 and 0 or 1
  local lines = workspace.opts.lines or math.max(1, vim.o.lines - vim.o.cmdheight - tabline - statusline)
  return columns, lines
end

local function layout_windows_valid(workspace, next_layout)
  if not util.valid_window(workspace.canvas_winid) then return false end
  if next_layout.footer_height > 0 then
    if
      not util.valid_window(workspace.windows.action_bar)
      or vim.api.nvim_win_get_buf(workspace.windows.action_bar) ~= workspace.buffers.action_bar
    then
      return false
    end
  elseif util.valid_window(workspace.windows.action_bar) then
    return false
  end
  local left_visible = next_layout.panes.left and next_layout.panes.left.persistent
  if left_visible then
    local role = M.left_role(workspace)
    if
      not util.valid_window(workspace.windows.left)
      or vim.api.nvim_win_get_buf(workspace.windows.left) ~= workspace.buffers[role]
    then
      return false
    end
  elseif util.valid_window(workspace.windows.left) then
    return false
  end
  local details_visible = next_layout.panes.properties and next_layout.panes.properties.persistent
  if details_visible then
    if
      not util.valid_window(workspace.windows.properties)
      or vim.api.nvim_win_get_buf(workspace.windows.properties) ~= workspace.buffers.properties
    then
      return false
    end
  elseif util.valid_window(workspace.windows.properties) then
    return false
  end
  return true
end

function M.window_for_pane(workspace, pane)
  if pane == "canvas" then return workspace.canvas_winid end
  if workspace.layout and workspace.layout.kind == "compact" then
    return workspace.drawer_role == pane and workspace.windows.drawer or nil
  end
  if pane == "properties" then return workspace.windows.properties end
  if pane == "objects" or pane == "issues" then
    return M.left_role(workspace) == pane and workspace.windows.left or nil
  end
end

function M.restore_focus(workspace, pane)
  pane = pane or workspace.state.focused_pane or "canvas"
  local winid = M.window_for_pane(workspace, pane)
  if not util.valid_window(winid) then
    pane = "canvas"
    workspace.state = workspace_state.reduce(workspace.state, { type = "focus", pane = pane })
    winid = workspace.canvas_winid
  end
  if util.valid_window(winid) then vim.api.nvim_set_current_win(winid) end
  M.refresh_window_chrome(workspace)
  return winid
end

local function restore_reflow_focus(workspace, pane, preserved_winid)
  if util.valid_window(preserved_winid) then
    vim.api.nvim_set_current_win(preserved_winid)
    M.refresh_window_chrome(workspace)
    return preserved_winid
  end
  return M.restore_focus(workspace, pane)
end

function M.pane_for_window(workspace, winid)
  if winid == workspace.canvas_winid then return "canvas" end
  if winid == workspace.windows.properties then return "properties" end
  local is_left = winid == workspace.windows.left
  local is_drawer = winid == workspace.windows.drawer
  if not is_left and not is_drawer then return nil end
  local bufnr = util.valid_window(winid) and vim.api.nvim_win_get_buf(winid) or nil
  for _, role in ipairs({ "objects", "issues", "properties" }) do
    if bufnr == workspace.buffers[role] then return role end
  end
  return is_drawer and workspace.drawer_role or M.left_role(workspace)
end

function M.reflow(api, session, force)
  local workspace = session and session.workspace
  if not workspace or workspace.closed or workspace.hidden or not util.valid_window(workspace.canvas_winid) then
    return false
  end
  for _, role in ipairs(render.ensure_buffers(session, workspace)) do
    interaction.map_common(api, session, workspace.buffers[role], role)
  end
  local current_winid = vim.api.nvim_get_current_win()
  local current_pane = M.pane_for_window(workspace, current_winid)
  local pending_focus = workspace.pending_focus
  -- Forms, palettes, vim.ui providers, and unrelated editor windows are not
  -- workspace panes. A resize/reflow must never replace their native focus
  -- with the workspace's last remembered pane unless a pane focus was
  -- explicitly requested through pending_focus.
  local preserved_winid = pending_focus == nil
      and current_pane == nil
      and util.valid_window(current_winid)
      and current_winid
    or nil
  local restore_pane = pending_focus or current_pane or workspace.state.focused_pane
  local columns, lines = dimensions(workspace)
  local next_layout = workspace_state.calculate_layout(columns, lines, workspace.opts, workspace.state)
  if
    not force
    and workspace.layout
    and workspace.layout.kind == next_layout.kind
    and workspace.layout.columns == next_layout.columns
    and workspace.layout.lines == next_layout.lines
    and layout_windows_valid(workspace, next_layout)
  then
    workspace.pending_focus = nil
    render.refresh(session)
    restore_reflow_focus(workspace, restore_pane, preserved_winid)
    return next_layout
  end
  workspace.reflowing = true
  local ok, result = xpcall(function()
    M.close_owned_windows(workspace)
    workspace.layout = next_layout
    workspace.state = workspace_state.reduce(workspace.state, { type = "layout", kind = next_layout.kind })

    local canvas = workspace.canvas_winid
    if next_layout.footer_height > 0 then
      workspace.windows.action_bar =
        open_split(workspace.buffers.action_bar, canvas, "below", next_layout.footer_height)
      M.configure_window(workspace, workspace.windows.action_bar, "action_bar", "footer")
      workspace.owns_footer = true
    end
    if next_layout.panes.left and next_layout.panes.left.persistent then
      workspace.windows.left =
        open_split(workspace.buffers[M.left_role(workspace)], canvas, "left", next_layout.panes.left.width)
      M.configure_window(workspace, workspace.windows.left, M.left_role(workspace), "width")
    end
    if next_layout.panes.properties and next_layout.panes.properties.persistent then
      local direction = next_layout.panes.properties.dock == "left" and "left" or "right"
      workspace.windows.properties =
        open_split(workspace.buffers.properties, canvas, direction, next_layout.panes.properties.width)
      M.configure_window(workspace, workspace.windows.properties, "properties", "width")
    end
    M.show_left_buffer(workspace)
    render.refresh(session)
    workspace.pending_focus = nil
    restore_reflow_focus(workspace, restore_pane, preserved_winid)
    if workspace.opts.on_layout then workspace.opts.on_layout(session, next_layout) end
    return next_layout
  end, debug.traceback)
  workspace.reflowing = false
  if not ok then error(result, 0) end
  return result
end

local function open_drawer(session, role)
  local workspace = session.workspace
  M.close_window(workspace, "drawer")
  if workspace.tabpage and vim.api.nvim_tabpage_is_valid(workspace.tabpage) then
    vim.api.nvim_set_current_tabpage(workspace.tabpage)
  end
  if util.valid_window(workspace.canvas_winid) then vim.api.nvim_set_current_win(workspace.canvas_winid) end
  local pane = workspace.layout.panes.drawer
  local winid = vim.api.nvim_open_win(workspace.buffers[role], true, {
    relative = "editor",
    style = "minimal",
    border = workspace.opts.border or "rounded",
    title = " RoomPlan · "
      .. (workspace.pane_titles and workspace.pane_titles[role] or util.pane_titles[role] or role:gsub(
        "^%l",
        string.upper
      ))
      .. " ",
    title_pos = "center",
    width = pane.width,
    height = pane.height,
    col = math.max(0, math.floor((vim.o.columns - pane.width) / 2)),
    row = math.max(0, math.floor((vim.o.lines - pane.height) / 2) - 1),
  })
  workspace.windows.drawer = winid
  workspace.drawer_role = role
  M.configure_window(workspace, winid, role)
  return winid
end

function M.focus(api, session, pane)
  local workspace = session and session.workspace
  if not workspace or workspace.closed then return false end
  for _, role in ipairs(render.ensure_buffers(session, workspace)) do
    interaction.map_common(api, session, workspace.buffers[role], role)
  end
  pane = pane or "canvas"
  workspace.state = workspace_state.reduce(workspace.state, { type = "focus", pane = pane })
  local winid
  if pane == "canvas" then
    M.close_window(workspace, "drawer")
    workspace.drawer_role = nil
    winid = workspace.canvas_winid
  elseif workspace.layout.kind == "compact" then
    winid = open_drawer(session, pane)
  else
    if pane == "objects" or pane == "issues" then M.show_left_buffer(workspace) end
    workspace.pending_focus = pane
    M.reflow(api, session)
    winid = M.window_for_pane(workspace, pane)
  end
  if util.valid_window(winid) then vim.api.nvim_set_current_win(winid) end
  M.refresh_window_chrome(workspace)
  render.refresh(session, { "objects", "issues", "properties", "action_bar" })
  if workspace.opts.on_focus then workspace.opts.on_focus(session, pane) end
  return util.valid_window(winid)
end

local function pane_group(pane)
  if pane == "properties" then return "details" end
  if pane == "objects" or pane == "issues" then return "navigator" end
end

function M.toggle(api, session, pane)
  local workspace = session and session.workspace
  if not workspace or workspace.closed then return false end
  pane = pane or "objects"
  local group = pane_group(pane)
  if not group then return M.focus(api, session, pane) end

  if workspace.layout.kind == "compact" then
    if workspace.drawer_role == pane and util.valid_window(workspace.windows.drawer) then
      return M.focus(api, session, "canvas")
    end
    return M.focus(api, session, pane)
  end

  local visible = workspace.state.visibility and workspace.state.visibility[group] ~= false
  if visible and workspace.state.focused_pane == pane then
    workspace.state = workspace_state.reduce(workspace.state, {
      type = "set_pane_visible",
      pane = group,
      visible = false,
    })
    workspace.state = workspace_state.reduce(workspace.state, { type = "focus", pane = "canvas" })
    workspace.pending_focus = "canvas"
    M.reflow(api, session, true)
    return true
  end

  workspace.state = workspace_state.reduce(workspace.state, {
    type = "set_pane_visible",
    pane = group,
    visible = true,
  })
  return M.focus(api, session, pane)
end

function M.cycle_focus(api, session, direction)
  local workspace = session and session.workspace
  if not workspace then return false end
  return M.focus(api, session, workspace_state.next_focus(workspace.state, direction))
end

return M
