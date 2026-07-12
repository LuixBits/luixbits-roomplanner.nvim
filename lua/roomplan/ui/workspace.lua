-- Dependency-free RoomPlan workspace shell.  It mounts around an already-open
-- canonical canvas window and owns only its side panes, footer and drawers.
-- The canvas buffer/window remain owned by roomplan.render.canvas.

local action_registry = require("roomplan.ui.action_registry")
local mappings = require("roomplan.ui.mappings")
local presenter = require("roomplan.ui.presenter")
local workspace_state = require("roomplan.ui.workspace_state")
local state = require("roomplan.state")

local objects_panel = require("roomplan.ui.panels.objects")
local issues_panel = require("roomplan.ui.panels.issues")
local properties_panel = require("roomplan.ui.panels.properties")
local action_bar = require("roomplan.ui.panels.action_bar")

local M = {}
local pane_for_window

local function valid_buffer(bufnr)
  return type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr)
end

local function valid_window(winid)
  return type(winid) == "number" and vim.api.nvim_win_is_valid(winid)
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = copy(item) end
  return result
end

local function merge(target, source)
  target = copy(target or {})
  for key, value in pairs(source or {}) do target[key] = copy(value) end
  return target
end

local function configured_options(opts)
  local from_config = {}
  local ok, config = pcall(require, "roomplan.config")
  if ok and config.get then
    local ui = config.get().ui or {}
    from_config = ui.workspace or {}
  end
  return merge(from_config, opts)
end

local function role_filetype(role)
  return "roomplan-" .. role:gsub("_", "-")
end

local function configure_buffer(bufnr, role)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modeline = false
  vim.bo[bufnr].undolevels = -1
  vim.bo[bufnr].filetype = role_filetype(role)
  vim.bo[bufnr].modifiable = false
end

local function configure_window(winid, fixed)
  if not valid_window(winid) then return end
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = "no"
  vim.wo[winid].foldcolumn = "0"
  vim.wo[winid].foldenable = false
  vim.wo[winid].wrap = false
  vim.wo[winid].spell = false
  vim.wo[winid].list = false
  vim.wo[winid].cursorline = fixed ~= "footer"
  vim.wo[winid].winhighlight = "EndOfBuffer:RoomPlanWorkspaceMuted"
  if fixed == "width" then vim.wo[winid].winfixwidth = true end
  if fixed == "footer" then
    vim.wo[winid].winfixheight = true
    vim.wo[winid].cursorline = false
  end
end

local function define_highlights()
  local links = {
    RoomPlanWorkspaceTitle = "Title",
    RoomPlanWorkspaceSelected = "Visual",
    RoomPlanWorkspaceMuted = "NonText",
    RoomPlanWorkspaceStatus = "StatusLine",
    RoomPlanWorkspaceError = "DiagnosticError",
    RoomPlanWorkspaceWarning = "DiagnosticWarn",
  }
  for name, link in pairs(links) do vim.api.nvim_set_hl(0, name, { default = true, link = link }) end
end

local function write_buffer(bufnr, lines)
  if not valid_buffer(bufnr) then return end
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].modified = false
end

local function create_buffer(session, workspace, role)
  local bufnr = vim.api.nvim_create_buf(false, true)
  configure_buffer(bufnr, role)
  pcall(vim.api.nvim_buf_set_name, bufnr, string.format("roomplan://workspace/%s/%s", session.id, role))
  workspace.buffers[role] = bufnr
  state.attach_buffer(session, bufnr, "workspace-" .. role)
  return bufnr
end

local function ensure_buffers(session, workspace)
  for _, role in ipairs({ "objects", "issues", "properties", "action_bar" }) do
    if not valid_buffer(workspace.buffers[role]) then create_buffer(session, workspace, role) end
  end
end

local function panel_width(workspace, role)
  local winid = workspace.windows[role]
  if valid_window(winid) then return vim.api.nvim_win_get_width(winid) end
  if valid_window(workspace.windows.drawer) and workspace.drawer_role == role then
    return vim.api.nvim_win_get_width(workspace.windows.drawer)
  end
  local panes = workspace.layout and workspace.layout.panes or {}
  if role == "properties" and panes.properties then return panes.properties.width end
  if panes.left then return panes.left.width end
  return panes.drawer and panes.drawer.width or math.max(20, math.floor(vim.o.columns * 0.8))
end

local function panel_height(workspace, role)
  local winid = workspace.windows[role]
  if valid_window(winid) then return vim.api.nvim_win_get_height(winid) end
  if valid_window(workspace.windows.drawer) and workspace.drawer_role == role then
    return vim.api.nvim_win_get_height(workspace.windows.drawer)
  end
  local panes = workspace.layout and workspace.layout.panes or {}
  if role == "action_bar" then return (panes.footer and panes.footer.height) or 2 end
  return (panes.left and panes.left.height) or (panes.properties and panes.properties.height)
    or (panes.drawer and panes.drawer.height) or math.max(8, vim.o.lines - 4)
end

local function ui_state(workspace)
  return workspace.state
end

local function context(session, workspace)
  local ctx = presenter.context(session, ui_state(workspace))
  if session.history then
    ctx.can_undo = type(session.history.can_undo) == "function" and session.history:can_undo() or nil
    ctx.can_redo = type(session.history.can_redo) == "function" and session.history:can_redo() or nil
  end
  ctx.keymaps = require("roomplan.config").get().keymaps
  ctx.form = workspace.state.form
  if ctx.form then ctx.focus = "form" end
  return ctx
end

local function render_one(session, workspace, role)
  local width, height = panel_width(workspace, role), panel_height(workspace, role)
  local rendered
  if role == "objects" then
    local view = presenter.objects(session, {
      selection = session.selection,
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
    local ctx = context(session, workspace)
    local view = presenter.properties(session)
    rendered = properties_panel.render(view, width, height, {
      actions = action_registry.for_ids(view.actions, ctx),
    })
  else
    rendered = action_bar.render(context(session, workspace), width, {
      height = height,
      compact_reason = workspace.layout and workspace.layout.compact_reason,
    })
  end
  workspace.rendered[role] = rendered
  write_buffer(workspace.buffers[role], rendered.lines)
end

function M.refresh(session, roles)
  local workspace = session and session.workspace
  if not workspace or workspace.closed then return false end
  workspace.state = workspace_state.reduce(workspace.state, { type = "selection", selection = session.selection })
  roles = roles or { "objects", "issues", "properties", "action_bar" }
  if type(roles) == "string" then roles = { roles } end
  for _, role in ipairs(roles) do render_one(session, workspace, role) end
  return true
end

local function close_window(workspace, key)
  local winid = workspace.windows[key]
  workspace.windows[key] = nil
  if valid_window(winid) then pcall(vim.api.nvim_win_close, winid, true) end
end

local function close_owned_windows(workspace)
  -- The canvas is deliberately absent: it is not workspace-owned.
  for _, key in ipairs({ "drawer", "left", "properties", "action_bar" }) do close_window(workspace, key) end
  workspace.drawer_role = nil
  workspace.owns_footer = false
end

local function open_split(buffer, anchor, direction, size)
  -- Use commands available throughout the supported Neovim 0.10+ range. The
  -- split form of nvim_open_win was added later than nvim_open_win itself.
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
  if placeholder ~= buffer and valid_buffer(placeholder)
    and vim.api.nvim_buf_get_name(placeholder) == "" and not vim.bo[placeholder].modified then
    pcall(vim.api.nvim_buf_delete, placeholder, { force = true })
  end
  if valid_window(previous) then vim.api.nvim_set_current_win(previous) end
  if direction == "left" or direction == "right" then
    pcall(vim.api.nvim_win_set_width, winid, math.max(1, size))
  else
    pcall(vim.api.nvim_win_set_height, winid, math.max(1, size))
  end
  return winid
end

local function left_role(workspace)
  local view = workspace.state.left_view
  return (view == "issues" or view == "properties") and view or "objects"
end

local function show_left_buffer(workspace)
  local winid = workspace.windows.left
  local role = left_role(workspace)
  if valid_window(winid) and valid_buffer(workspace.buffers[role]) then
    vim.api.nvim_win_set_buf(winid, workspace.buffers[role])
  end
end

local function dimensions(workspace)
  local columns = workspace.opts.columns or vim.o.columns
  local tabline = vim.o.showtabline == 2 and 1 or 0
  local statusline = vim.o.laststatus == 0 and 0 or 1
  local lines = workspace.opts.lines or math.max(1, vim.o.lines - vim.o.cmdheight - tabline - statusline)
  return columns, lines
end

local function layout_windows_valid(workspace, layout)
  if not valid_window(workspace.canvas_winid) then return false end
  if layout.footer_height > 0 then
    if not valid_window(workspace.windows.action_bar)
      or vim.api.nvim_win_get_buf(workspace.windows.action_bar) ~= workspace.buffers.action_bar then
      return false
    end
  end
  if layout.kind == "wide" or layout.kind == "medium" then
    local role = left_role(workspace)
    if not valid_window(workspace.windows.left)
      or vim.api.nvim_win_get_buf(workspace.windows.left) ~= workspace.buffers[role] then
      return false
    end
  end
  if layout.kind == "wide" then
    if not valid_window(workspace.windows.properties)
      or vim.api.nvim_win_get_buf(workspace.windows.properties) ~= workspace.buffers.properties then
      return false
    end
  end
  return true
end

function M.reflow(session, force)
  local workspace = session and session.workspace
  if not workspace or workspace.closed or workspace.hidden or not valid_window(workspace.canvas_winid) then return false end
  local restore_pane = pane_for_window(workspace, vim.api.nvim_get_current_win())
  local columns, lines = dimensions(workspace)
  local layout = workspace_state.calculate_layout(columns, lines, workspace.opts)
  if not force and workspace.layout and workspace.layout.kind == layout.kind
    and workspace.layout.columns == layout.columns and workspace.layout.lines == layout.lines
    and layout_windows_valid(workspace, layout) then
    return M.refresh(session)
  end
  workspace.reflowing = true
  close_owned_windows(workspace)
  workspace.layout = layout
  workspace.state = workspace_state.reduce(workspace.state, { type = "layout", kind = layout.kind })

  local canvas = workspace.canvas_winid
  if layout.footer_height > 0 then
    workspace.windows.action_bar = open_split(workspace.buffers.action_bar, canvas, "below", layout.footer_height)
    configure_window(workspace.windows.action_bar, "footer")
    workspace.owns_footer = true
  end
  if layout.kind == "wide" or layout.kind == "medium" then
    workspace.windows.left = open_split(workspace.buffers[left_role(workspace)], canvas, "left", layout.panes.left.width)
    configure_window(workspace.windows.left, "width")
  end
  if layout.kind == "wide" then
    workspace.windows.properties = open_split(workspace.buffers.properties, canvas, "right", layout.panes.properties.width)
    configure_window(workspace.windows.properties, "width")
  end
  show_left_buffer(workspace)
  workspace.reflowing = false
  M.refresh(session)
  if restore_pane then M.focus(session, restore_pane) end
  if workspace.opts.on_layout then workspace.opts.on_layout(session, layout) end
  return layout
end

local function open_drawer(session, role)
  local workspace = session.workspace
  close_window(workspace, "drawer")
  local pane = workspace.layout.panes.drawer
  local buffer = workspace.buffers[role]
  local winid = vim.api.nvim_open_win(buffer, true, {
    relative = "editor",
    style = "minimal",
    border = workspace.opts.border or "rounded",
    title = " RoomPlan " .. role:gsub("^%l", string.upper) .. " ",
    title_pos = "center",
    width = pane.width,
    height = pane.height,
    col = math.max(0, math.floor((vim.o.columns - pane.width) / 2)),
    row = math.max(0, math.floor((vim.o.lines - pane.height) / 2) - 1),
  })
  workspace.windows.drawer = winid
  workspace.drawer_role = role
  configure_window(winid)
  return winid
end

function M.focus(session, pane)
  local workspace = session and session.workspace
  if not workspace or workspace.closed then return false end
  pane = pane or "canvas"
  local previous_left_view = workspace.state.left_view
  workspace.state = workspace_state.reduce(workspace.state, { type = "focus", pane = pane })
  if pane == "properties" and workspace.layout.kind == "wide" then
    workspace.state.left_view = previous_left_view
  end
  local winid
  if pane == "canvas" then
    close_window(workspace, "drawer")
    workspace.drawer_role = nil
    winid = workspace.canvas_winid
  elseif workspace.layout.kind == "compact" then
    winid = open_drawer(session, pane)
  elseif pane == "properties" and workspace.layout.kind == "wide" then
    winid = workspace.windows.properties
  else
    workspace.state.left_view = pane
    show_left_buffer(workspace)
    winid = workspace.windows.left
  end
  if valid_window(winid) then vim.api.nvim_set_current_win(winid) end
  M.refresh(session, { "objects", "issues", "properties", "action_bar" })
  if workspace.opts.on_focus then workspace.opts.on_focus(session, pane) end
  return valid_window(winid)
end

function M.cycle_focus(session, direction)
  local workspace = session and session.workspace
  if not workspace then return false end
  local pane = workspace_state.next_focus(workspace.state, direction)
  return M.focus(session, pane)
end

local function selected_row(session, role)
  local workspace = session.workspace
  local rendered = workspace.rendered[role]
  local winid = workspace.layout.kind == "compact" and workspace.windows.drawer
    or role == "properties" and workspace.windows.properties or workspace.windows.left
  if not rendered or not valid_window(winid) then return nil end
  local line = vim.api.nvim_win_get_cursor(winid)[1]
  return rendered.row_map and rendered.row_map[line]
end

function M.select_focused(session)
  local workspace = session and session.workspace
  if not workspace then return false end
  local role = workspace.state.focused_pane
  if role ~= "objects" and role ~= "issues" then return false end
  local row = selected_row(session, role)
  if not row then return false end
  local selection = row.kind == "plan" and { kind = "plan" }
    or (row.kind and row.id and { kind = row.kind, id = row.id }) or nil
  session.selection = selection
  if role == "issues" then session.validation_index = row.index end
  workspace.state = workspace_state.reduce(workspace.state, { type = "selection", selection = selection })
  M.refresh(session)
  if workspace.opts.on_selection then
    workspace.opts.on_selection(session, selection, row)
  else
    M.focus(session, "canvas")
  end
  return selection
end

function M.set_filter(session, pane, value)
  local workspace = session and session.workspace
  if not workspace then return false end
  workspace.state = workspace_state.reduce(workspace.state, { type = "filter", pane = pane, value = value })
  M.refresh(session, pane)
  return true
end

---Publish an interaction/form mode for the persistent command bar. Structured
---form engines may pass their detached draft as `form`; it is never persisted.
function M.set_interaction(session, mode, form)
  local workspace = session and session.workspace
  if not workspace then return false end
  local previous = workspace.state.interaction
  workspace.state = workspace_state.reduce(workspace.state, { type = "interaction", mode = mode })
  workspace.state.form = form
  M.refresh(session, { "properties", "action_bar" })
  if previous ~= workspace.state.interaction then
    local ok, canvas = pcall(require, "roomplan.render.canvas")
    if ok and canvas.schedule_redraw then canvas.schedule_redraw(session, "workspace-interaction") end
  end
  return true
end

function M.set_preview(session, preview)
  local workspace = session and session.workspace
  if not workspace then return false end
  workspace.state = workspace_state.reduce(workspace.state, { type = "preview", value = preview })
  return true
end

---Update status-only cursor data without redrawing the model panes.
function M.update_cursor(session, world, zoom)
  local workspace = session and session.workspace
  if not workspace then return false end
  workspace.state = workspace_state.reduce(workspace.state, { type = "cursor", world = world, zoom = zoom })
  M.refresh(session, "action_bar")
  return true
end

function M.filter_prompt(session, pane)
  local workspace = session and session.workspace
  if not workspace then return end
  local generation = workspace.generation
  vim.ui.input({ prompt = "Filter RoomPlan " .. pane .. ": ", default = workspace.state.filters[pane] or "" }, function(value)
    if value == nil or not session.workspace or session.workspace.generation ~= generation then return end
    M.set_filter(session, pane, value)
  end)
end

function M.expand_focused(session, value)
  local workspace = session and session.workspace
  if not workspace or workspace.state.focused_pane ~= "objects" then return false end
  local row = selected_row(session, "objects")
  if not row or not row.expandable then return false end
  workspace.state = workspace_state.reduce(workspace.state, {
    type = "set_expanded", id = row.id, value = value,
  })
  M.refresh(session, "objects")
  return true
end

local function notify_disabled(action)
  local ok, compat = pcall(require, "roomplan.compat")
  if ok then compat.notify(action.reason, vim.log.levels.WARN) end
end

function M.invoke(session, id)
  local workspace = session and session.workspace
  if not workspace then return false end
  local action = action_registry.get(id, context(session, workspace))
  if not action then return false end
  if not action.enabled then notify_disabled(action); return false, action.reason end
  if action.workspace then return M.focus(session, action.workspace) end
  if action.form then
    if workspace.opts.on_form_action then return workspace.opts.on_form_action(session, action.form, action) end
    if action.form == "cancel" then
      if session.workflow and session.workflow.kind then
        require("roomplan.ui.flow").cancel(session, "cancelled")
      else
        require("roomplan.controller").escape(session)
      end
      M.refresh(session)
      return true
    end
    return false, "no structured form is active"
  end
  if id == "help" then return require("roomplan.ui.help").open(session) end
  if id == "hide" then return M.hide(session) end
  if workspace.opts.on_action then return workspace.opts.on_action(session, action) end
  local controller = require("roomplan.controller")
  local handler = controller[action.handler]
  if type(handler) ~= "function" then return false, "missing RoomPlan handler " .. tostring(action.handler) end
  local result = handler(session, unpack(action.args or {}))
  vim.schedule(function()
    if session.workspace and not session.workspace.closed then M.refresh(session) end
  end)
  return result
end

function M.invoke_key(session, key)
  local workspace = session and session.workspace
  if not workspace then return false end
  local action = action_registry.by_key(context(session, workspace), key)
  if not action then return false end
  return M.invoke(session, action.id)
end

function M.escape(session)
  local workspace = session and session.workspace
  if not workspace then return false end
  if workspace.windows.drawer then return M.focus(session, "canvas") end
  if (session.workflow and session.workflow.kind) or workspace.state.form or session.mode ~= "NAV" then
    require("roomplan.controller").escape(session)
    M.refresh(session)
    return true
  end
  if workspace.state.focused_pane ~= "canvas" then return M.focus(session, "canvas") end
  require("roomplan.controller").escape(session)
  M.refresh(session)
  return true
end

local function map_common(session, buffer, role)
  local function map(lhs, rhs, desc, name)
    return mappings.set(buffer, lhs, rhs, desc, name)
  end
  map("<Tab>", function() M.cycle_focus(session, 1) end, "Next RoomPlan workspace pane", "workspace_next_pane")
  map("<S-Tab>", function() M.cycle_focus(session, -1) end, "Previous RoomPlan workspace pane", "workspace_previous_pane")
  map("1", function() M.focus(session, "objects") end, "Focus RoomPlan objects", "focus_objects")
  map("2", function() M.focus(session, "canvas") end, "Focus RoomPlan canvas", "focus_canvas")
  map("3", function() M.focus(session, "properties") end, "Focus RoomPlan properties", "focus_properties")
  map("!", function() M.focus(session, "issues") end, "Focus RoomPlan issues", "focus_issues")
  map("<Esc>", function() M.escape(session) end, "Leave RoomPlan workspace mode", "escape")
  map("q", function()
    local workspace = session.workspace
    if workspace and workspace.windows.drawer then M.focus(session, "canvas") else M.hide(session) end
  end, "Hide RoomPlan workspace", "hide")
  for _, entry in ipairs({
    { "a", "add" }, { "e", "edit" }, { "m", "move" }, { "p", "pan" },
    { "A", "align" }, { "r", "rotate" }, { "y", "duplicate" }, { "d", "delete" },
    { "v", "validate" }, { "s", "save" }, { "f", "fit" }, { "?", "help" },
    { "D", "add_door" }, { "F", "add_furniture" }, { "u", "undo" }, { "<C-r>", "redo" },
    { "<C-s>", "apply" }, { "R", "reset" },
  }) do
    local definition = action_registry.get(entry[2], { keymaps = require("roomplan.config").get().keymaps })
    local lhs = definition and definition.key
    if lhs then
      mappings.set(buffer, entry[1], function() M.invoke(session, entry[2]) end,
        "RoomPlan " .. entry[2], definition.mapping)
    end
  end
  if role == "objects" or role == "issues" then
    map("<CR>", function() M.select_focused(session) end, "Select RoomPlan row")
    map("/", function() M.filter_prompt(session, role) end, "Filter RoomPlan rows")
  end
  if role == "objects" then
    map("h", function() M.expand_focused(session, false) end, "Collapse RoomPlan room")
    map("l", function() M.expand_focused(session, true) end, "Expand RoomPlan room")
  end
end

function M.apply_canvas_keymaps(session, opts)
  opts = opts or {}
  local workspace = session and session.workspace
  local buffer = workspace and workspace.canvas_bufnr
  if not valid_buffer(buffer) then return false end
  local function map(lhs, rhs, desc, name)
    return mappings.set(buffer, lhs, rhs, desc, name)
  end
  if opts.cycle_tabs ~= false then
    map("<Tab>", function() M.cycle_focus(session, 1) end, "Next RoomPlan workspace pane", "workspace_next_pane")
    map("<S-Tab>", function() M.cycle_focus(session, -1) end, "Previous RoomPlan workspace pane", "workspace_previous_pane")
  end
  map("1", function() M.focus(session, "objects") end, "Focus RoomPlan objects", "focus_objects")
  map("2", function() M.focus(session, "canvas") end, "Focus RoomPlan canvas", "focus_canvas")
  map("3", function() M.focus(session, "properties") end, "Focus RoomPlan properties", "focus_properties")
  map("!", function() M.focus(session, "issues") end, "Focus RoomPlan issues", "focus_issues")
  return true
end

pane_for_window = function(workspace, winid)
  if winid == workspace.canvas_winid then return "canvas" end
  if winid == workspace.windows.properties then return "properties" end
  local is_left = winid == workspace.windows.left
  local is_drawer = winid == workspace.windows.drawer
  if not is_left and not is_drawer then return nil end
  local bufnr = valid_window(winid) and vim.api.nvim_win_get_buf(winid) or nil
  for _, role in ipairs({ "objects", "issues", "properties" }) do
    if bufnr == workspace.buffers[role] then return role end
  end
  return is_drawer and workspace.drawer_role or left_role(workspace)
end

local function synchronize_native_focus(session, workspace)
  if workspace.closed or workspace.hidden or workspace.reflowing then return end
  local pane = pane_for_window(workspace, vim.api.nvim_get_current_win())
  if not pane or workspace.state.focused_pane == pane then return end
  local previous_left_view = workspace.state.left_view
  workspace.state = workspace_state.reduce(workspace.state, { type = "focus", pane = pane })
  if pane == "properties" and workspace.layout.kind == "wide" then
    workspace.state.left_view = previous_left_view
  end
  M.refresh(session, { "objects", "issues", "properties", "action_bar" })
end

local function install_autocommands(session, workspace)
  if workspace.augroup then pcall(vim.api.nvim_del_augroup_by_id, workspace.augroup) end
  workspace.augroup = vim.api.nvim_create_augroup("RoomPlanWorkspace" .. session.id:gsub("[^%w]", ""), { clear = true })
  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    group = workspace.augroup,
    callback = function()
      if workspace.closed or workspace.reflow_scheduled then return end
      workspace.reflow_scheduled = true
      vim.schedule(function()
        workspace.reflow_scheduled = false
        if not workspace.closed then M.reflow(session) end
      end)
    end,
    desc = "Reflow RoomPlan workspace",
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = workspace.augroup,
    callback = define_highlights,
    desc = "Refresh RoomPlan workspace highlights",
  })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = workspace.augroup,
    callback = function() synchronize_native_focus(session, workspace) end,
    desc = "Synchronize native RoomPlan workspace focus",
  })
  if valid_buffer(workspace.canvas_bufnr) then
    vim.api.nvim_create_autocmd("BufWipeout", {
      group = workspace.augroup,
      buffer = workspace.canvas_bufnr,
      once = true,
      callback = function()
        if workspace.closed then return end
        workspace.hidden = true
        workspace.canvas_winid = nil
        workspace.canvas_bufnr = nil
        close_owned_windows(workspace)
      end,
      desc = "Hide panes with RoomPlan canvas",
    })
  end
end

function M.mount(session, opts)
  assert(type(session) == "table", "RoomPlan workspace requires a session")
  opts = configured_options(opts)
  local canvas_winid = opts.canvas_winid or (session.canvas and session.canvas.winid)
  local canvas_bufnr = opts.canvas_bufnr or (session.canvas and session.canvas.bufnr)
  assert(valid_window(canvas_winid), "RoomPlan workspace requires an open canvas window")
  assert(valid_buffer(canvas_bufnr), "RoomPlan workspace requires an open canvas buffer")

  local workspace = session.workspace
  if workspace and not workspace.closed then
    close_owned_windows(workspace)
    workspace.opts = merge(workspace.opts, opts)
    workspace.canvas_winid = canvas_winid
    workspace.canvas_bufnr = canvas_bufnr
    workspace.tabpage = vim.api.nvim_win_get_tabpage(canvas_winid)
    workspace.hidden = false
    workspace.generation = workspace.generation + 1
  else
    workspace = {
      opts = opts,
      state = workspace_state.initial(opts),
      buffers = {},
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
  define_highlights()
  ensure_buffers(session, workspace)
  for role, buffer in pairs(workspace.buffers) do map_common(session, buffer, role) end
  install_autocommands(session, workspace)
  M.apply_canvas_keymaps(session, { cycle_tabs = opts.cycle_tabs ~= false })
  vim.api.nvim_set_current_tabpage(workspace.tabpage)
  M.reflow(session, true)
  M.focus(session, workspace.state.focused_pane or "canvas")
  return workspace
end

M.attach = M.mount

function M.hide(session)
  local workspace = session and session.workspace
  if not workspace or workspace.closed then return false end
  close_owned_windows(workspace)
  workspace.hidden = true
  local callback = workspace.opts.on_hide
  if callback then return callback(session) end
  return require("roomplan.render.canvas").close(session)
end

function M.close(session, opts)
  opts = opts or {}
  local workspace = session and session.workspace
  if not workspace or workspace.closed then return true end
  workspace.closed = true
  workspace.generation = workspace.generation + 1
  close_owned_windows(workspace)
  if workspace.augroup then pcall(vim.api.nvim_del_augroup_by_id, workspace.augroup) end
  for role, buffer in pairs(workspace.buffers) do
    state.detach_buffer(buffer)
    if valid_buffer(buffer) then pcall(vim.api.nvim_buf_delete, buffer, { force = true }) end
    workspace.buffers[role] = nil
  end
  if opts.close_canvas and valid_window(workspace.canvas_winid) then
    pcall(function() require("roomplan.render.canvas").close(session) end)
  end
  if session.workspace == workspace then session.workspace = nil end
  return true
end

function M.is_visible(session)
  local workspace = session and session.workspace
  return workspace ~= nil and not workspace.closed and not workspace.hidden and valid_window(workspace.canvas_winid)
end

function M.owns_window(session, winid)
  local workspace = session and session.workspace
  if not workspace then return false end
  for _, owned in pairs(workspace.windows) do if owned == winid then return true end end
  return false
end

function M.layout(session)
  return session and session.workspace and session.workspace.layout or nil
end

return M
