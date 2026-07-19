-- Neovim adapter for dependency-free form specs/state.  A form is a single
-- structured float: every visible field remains on screen while scalar and
-- choice editors are anchored to the form generation and field key.

local fields = require("roomplan.ui.form.fields")
local mappings = require("roomplan.ui.mappings")
local form_state = require("roomplan.ui.form.state")
local renderer = require("roomplan.ui.form.render")
local side_preview = require("roomplan.ui.form.side_preview")
local util = require("roomplan.util")

local M = {}

local next_id = 0

local function valid_buffer(bufnr)
  return type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr)
end

local function valid_window(winid)
  return type(winid) == "number" and vim.api.nvim_win_is_valid(winid)
end

local function message(err)
  if type(err) == "table" then return err.message or err.code or vim.inspect(err) end
  return tostring(err)
end

local function revision_id(handle)
  if type(handle.callbacks.revision) == "function" then
    return handle.callbacks.revision(handle.session, handle)
  end
  if type(handle.session.revision_id) == "function" then return handle.session:revision_id() end
  return nil
end

local function workflow_current(handle)
  local workflow = handle.session.workflow
  return not workflow or (workflow.generation == handle.workflow_generation and workflow.kind == handle.workflow_kind)
end

function M.is_current(handle)
  return type(handle) == "table"
    and not handle.closed
    and handle.session
    and not handle.session.closed
    and handle.session.form == handle
    and workflow_current(handle)
end

function M.focus(handle)
  if not M.is_current(handle) or not valid_window(handle.winid) then return false end
  if vim.api.nvim_get_current_win() ~= handle.winid then vim.api.nvim_set_current_win(handle.winid) end
  return true
end

local function revision_current(handle)
  local base = handle.state.base_revision_id
  return base == nil or revision_id(handle) == base
end

local function set_lines(handle, output)
  if not valid_buffer(handle.bufnr) then return end
  vim.bo[handle.bufnr].modifiable = true
  vim.bo[handle.bufnr].readonly = false
  vim.api.nvim_buf_set_lines(handle.bufnr, 0, -1, false, output.lines)
  vim.bo[handle.bufnr].modifiable = false
  vim.bo[handle.bufnr].readonly = true
  vim.bo[handle.bufnr].modified = false
end

local function define_highlights()
  vim.api.nvim_set_hl(0, "RoomPlanFormTitle", { default = true, link = "Title" })
  vim.api.nvim_set_hl(0, "RoomPlanFormActive", { default = true, link = "Visual" })
  vim.api.nvim_set_hl(0, "RoomPlanFormError", { default = true, link = "DiagnosticError" })
  vim.api.nvim_set_hl(0, "RoomPlanFormMuted", { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, "RoomPlanFormFooter", { default = true, link = "StatusLine" })
end

local function highlight_line(handle, row, group)
  local line = vim.api.nvim_buf_get_lines(handle.bufnr, row - 1, row, false)[1] or ""
  vim.api.nvim_buf_set_extmark(handle.bufnr, handle.namespace, row - 1, 0, {
    end_col = #line,
    hl_group = group,
    hl_mode = "combine",
    strict = false,
  })
end

local function highlight_range(handle, row, start_col, end_col, group)
  if type(row) ~= "number" or type(start_col) ~= "number" or type(end_col) ~= "number"
    or end_col <= start_col
  then
    return
  end
  vim.api.nvim_buf_set_extmark(handle.bufnr, handle.namespace, row - 1, start_col, {
    end_col = end_col,
    hl_group = group,
    hl_mode = "combine",
    strict = false,
  })
end

local function apply_highlights(handle, output)
  if not valid_buffer(handle.bufnr) then return end
  vim.api.nvim_buf_clear_namespace(handle.bufnr, handle.namespace, 0, -1)
  highlight_line(handle, output.meta.title_row, "RoomPlanFormTitle")
  if output.meta.active_row then highlight_line(handle, output.meta.active_row, "RoomPlanFormActive") end
  for row in pairs(output.meta.error_rows) do highlight_line(handle, row, "RoomPlanFormError") end
  for row in pairs(output.meta.readonly_rows) do highlight_line(handle, row, "RoomPlanFormMuted") end
  if next(output.meta.preview_graphic_rows or {}) ~= nil then
    local accent = handle.state.preview and handle.state.preview.accent
    local graphic_group = "RoomPlanFormPreviewShape" .. handle.id
    if type(accent) == "string" and accent:match("^#%x%x%x%x%x%x$") then
      vim.api.nvim_set_hl(0, graphic_group, { fg = accent, bold = true })
    else
      vim.api.nvim_set_hl(0, graphic_group, { link = "RoomPlanPreview" })
    end
    if #(output.meta.preview_graphic_spans or {}) > 0 then
      for _, span in ipairs(output.meta.preview_graphic_spans) do
        highlight_range(handle, span.row, span.start_col, span.end_col, graphic_group)
      end
    else
      for row in pairs(output.meta.preview_graphic_rows) do highlight_line(handle, row, graphic_group) end
    end
  end
  for row in pairs(output.meta.footer_rows) do highlight_line(handle, row, "RoomPlanFormFooter") end
end

local function publish_workspace(handle)
  local ok, workspace = pcall(require, "roomplan.ui.workspace")
  if not ok or not handle.session.workspace then return end
  -- Publish a display-only descriptor. The live form handle points back to the
  -- session/workspace and would introduce a cycle into the pure UI reducer.
  workspace.set_interaction(handle.session, handle.spec.mode or "FORM", {
    kind = handle.spec.id,
    mode = handle.spec.mode,
    active_key = handle.state.active_key,
    dirty = handle.state.dirty,
    error_count = vim.tbl_count(handle.state.errors or {}),
  })
end

local function form_keys()
  return {
    edit = mappings.resolve("<CR>", "form_edit"),
    edit_alt = mappings.resolve("e"),
    previous_choice = mappings.resolve("h", "form_previous_choice"),
    next_choice = mappings.resolve("l", "form_next_choice"),
    toggle = mappings.resolve("<Space>", "form_toggle"),
    apply = mappings.resolve("<C-s>", "form_apply"),
    cancel = mappings.resolve("<Esc>", "form_cancel"),
    cancel_alt = mappings.resolve("q"),
  }
end

function M.render(handle)
  if not M.is_current(handle) or not valid_buffer(handle.bufnr) then return nil end
  local restore_focus = valid_window(handle.winid) and vim.api.nvim_get_current_win() == handle.winid
  local width = valid_window(handle.winid) and vim.api.nvim_win_get_width(handle.winid) or handle.width
  if side_preview.visible(handle) then width = side_preview.width(handle) end
  local output = renderer.build(handle.state, {
    width = width,
    keys = form_keys(),
    include_preview = not side_preview.visible(handle),
  })
  handle.output = output
  set_lines(handle, output)
  apply_highlights(handle, output)
  if valid_window(handle.winid) and output.meta.active_row then
    pcall(vim.api.nvim_win_set_cursor, handle.winid, { output.meta.active_row, 0 })
  end
  side_preview.sync(handle)
  if restore_focus then M.focus(handle) end
  publish_workspace(handle)
  return output
end

local function mark_stale(handle)
  if handle.state.stale then
    return nil, util.err("FORM_REVISION_STALE", "the plan changed while the form was open")
  end
  handle.state = form_state.reduce(handle.state, {
    type = "stale",
    error = "The plan changed while this form was open. Cancel and reopen it before applying.",
  })
  M.render(handle)
  if type(handle.callbacks.on_stale) == "function" then handle.callbacks.on_stale(handle) end
  return nil, util.err("FORM_REVISION_STALE", "the plan changed while the form was open")
end

local function guarded(handle)
  if not M.is_current(handle) then
    return nil, util.err("FORM_STALE", "the RoomPlan form is no longer active")
  end
  if not revision_current(handle) then return mark_stale(handle) end
  return true
end

local function clear_workflow(handle)
  local workflow = handle.session.workflow
  if workflow and workflow.generation == handle.workflow_generation and workflow.kind == handle.workflow_kind then
    workflow.kind = nil
    workflow.generation = workflow.generation + 1
  end
end

local function detach_buffer(handle)
  local ok, roomplan_state = pcall(require, "roomplan.state")
  if ok and valid_buffer(handle.bufnr) then roomplan_state.detach_buffer(handle.bufnr) end
end

local function finish(handle, reason, opts)
  opts = opts or {}
  if handle.closed then return false end
  handle.closed = true
  handle.internal_closing = true
  handle.edit_token = handle.edit_token + 1
  clear_workflow(handle)
  if handle.session.form == handle then handle.session.form = nil end
  if handle.session.workspace and handle.session.workspace.state then
    local ok, workspace = pcall(require, "roomplan.ui.workspace")
    if ok then
      workspace.set_interaction(handle.session, handle.session.mode or "NAV", nil)
    end
  end
  detach_buffer(handle)
  if handle.augroup then pcall(vim.api.nvim_del_augroup_by_id, handle.augroup) end
  side_preview.close(handle)
  if not opts.skip_window and valid_window(handle.winid) then pcall(vim.api.nvim_win_close, handle.winid, true) end
  if not opts.skip_buffer and valid_buffer(handle.bufnr) then pcall(vim.api.nvim_buf_delete, handle.bufnr, { force = true }) end
  handle.internal_closing = false
  handle.finish_reason = reason
  return true
end

function M.cancel(handle, reason, opts)
  if not M.is_current(handle) and not (handle and not handle.closed and handle.session.form == handle) then return false end
  local callback = handle.callbacks.on_cancel
  local draft = util.deepcopy(handle.state.draft)
  local done = finish(handle, reason or "cancelled", opts)
  if done and type(callback) == "function" then callback(reason or "cancelled", draft, handle) end
  return done
end

---Close a form as part of a deliberate transition to another RoomPlan editor.
---Unlike cancel/apply this does not invoke either user callback.
function M.transition(handle, reason)
  if not M.is_current(handle) then return false end
  return finish(handle, reason or "transition")
end

function M.refresh(handle)
  local ok, err = guarded(handle)
  if not ok then return nil, err end
  return M.render(handle)
end

function M.activate(handle, key)
  local ok, err = guarded(handle)
  if not ok then return nil, err end
  handle.state = form_state.reduce(handle.state, { type = "activate", key = key })
  M.render(handle)
  return true
end

function M.move(handle, delta)
  local ok, err = guarded(handle)
  if not ok then return nil, err end
  handle.state = form_state.reduce(handle.state, { type = "move", delta = delta })
  M.render(handle)
  return handle.state.active_key
end

function M.reset(handle)
  local ok, err = guarded(handle)
  if not ok then return nil, err end
  handle.state = form_state.new(handle.spec, handle.state.context, {
    draft = handle.state.initial_draft,
    base_revision_id = handle.state.base_revision_id,
    active_key = handle.state.active_key,
  })
  M.render(handle)
  if type(handle.callbacks.on_reset) == "function" then handle.callbacks.on_reset(handle) end
  return true
end

function M.set_value(handle, key, value, opts)
  local ok, err = guarded(handle)
  if not ok then return nil, err end
  handle.state = form_state.reduce(handle.state, {
    type = opts and opts.raw == false and "set_value" or "set_raw",
    key = key,
    value = value,
    trusted = opts and opts.trusted == true,
  })
  M.render(handle)
  if type(handle.callbacks.on_change) == "function" then
    handle.callbacks.on_change(util.deepcopy(handle.state.draft), handle.state, handle)
  end
  if handle.state.errors[key] then return nil, util.err("FORM_FIELD_INVALID", handle.state.errors[key], { field = key }) end
  return handle.state.draft[key]
end

local function choice_index(field, value, handle)
  local _, index, choices = fields.choice(field, value, handle.state.context, handle.state.draft, handle.state)
  return index, choices
end

function M.cycle(handle, delta)
  local ok, err = guarded(handle)
  if not ok then return nil, err end
  local key = handle.state.active_key
  local field = key and form_state.field(handle.state, key) or nil
  if not field then return nil, util.err("FORM_FIELD_MISSING", "no editable form field is active") end
  if field.type == "toggle" then return M.set_value(handle, key, not handle.state.draft[key], { raw = false, trusted = true }) end
  if field.type ~= "enum" and field.type ~= "object_ref" then
    return nil, util.err("FORM_FIELD_NOT_CHOICE", (field.label or key) .. " is not a choice field")
  end
  local current, choices = choice_index(field, handle.state.draft[key], handle)
  if #choices == 0 then return nil, util.err("FORM_CHOICES_EMPTY", "no choices are available") end
  current = current or 1
  local direction = delta and delta < 0 and -1 or 1
  local attempts = 0
  repeat
    current = ((current - 1 + direction) % #choices) + 1
    attempts = attempts + 1
  until not choices[current].disabled or attempts >= #choices
  if choices[current].disabled then return nil, util.err("FORM_CHOICES_DISABLED", "all choices are unavailable") end
  return M.set_value(handle, key, choices[current].value, { raw = false })
end

function M.edit(handle)
  local ok, err = guarded(handle)
  if not ok then return nil, err end
  local key = handle.state.active_key
  local field = key and form_state.field(handle.state, key) or nil
  if not field then return nil, util.err("FORM_FIELD_MISSING", "no editable form field is active") end
  if field.type == "action" then
    local callback = field.on_activate or handle.callbacks.on_action
    if type(callback) ~= "function" then
      return nil, util.err("FORM_ACTION_UNAVAILABLE", (field.label or key) .. " is unavailable")
    end
    local called, result, action_err = pcall(
      callback,
      field.action or key,
      handle.state,
      handle,
      field
    )
    if not called or result == false or (result == nil and action_err ~= nil) then
      local failure = not called and result or action_err or "the action could not be opened"
      if M.is_current(handle) then
        handle.state = form_state.reduce(handle.state, { type = "form_error", error = failure })
        M.render(handle)
      end
      return nil, type(failure) == "table" and failure
        or util.err("FORM_ACTION_FAILED", tostring(failure))
    end
    return result == nil and true or result
  end
  if field.type == "toggle" then return M.cycle(handle, 1) end
  handle.edit_token = handle.edit_token + 1
  local token = handle.edit_token
  local generation = handle.workflow_generation
  local function anchored()
    return M.is_current(handle) and handle.workflow_generation == generation and handle.edit_token == token
  end

  if field.type == "enum" or field.type == "object_ref" then
    local choices = fields.choices(field, handle.state.context, handle.state.draft, handle.state)
    vim.ui.select(choices, {
      prompt = field.prompt or (field.label or key) .. ":",
      kind = field.kind or "roomplan_form_choice",
      format_item = function(item)
        local suffix = item.description and (" — " .. item.description) or ""
        return item.label .. suffix
      end,
    }, function(choice)
      if not anchored() or choice == nil then return end
      local current = guarded(handle)
      if not current then return end
      M.focus(handle)
      M.set_value(handle, key, choice.value, { raw = false })
    end)
    return true
  end

  local value = handle.state.raw and handle.state.raw[key]
  if value == nil then value = fields.value(field, handle.state.context, handle.state.draft, handle.state) end
  vim.ui.input({
    prompt = field.prompt or (field.label or key) .. ": ",
    default = fields.input_default(field, value, handle.state.context, handle.state.draft, handle.state),
    scope = "window",
  }, function(raw)
    if not anchored() or raw == nil then return end
    local current = guarded(handle)
    if not current then return end
    M.focus(handle)
    M.set_value(handle, key, raw, { raw = true })
  end)
  return true
end

function M.apply(handle)
  local ok, err = guarded(handle)
  if not ok then return nil, err end
  local next_state, valid = form_state.validate_all(handle.state)
  handle.state = next_state
  M.render(handle)
  if not valid then
    return nil, util.err("FORM_INVALID", handle.state.form_error or "correct the highlighted fields before applying", {
      errors = util.deepcopy(handle.state.errors),
    })
  end
  local callback = handle.callbacks.on_submit or handle.spec.submit
  local draft = util.deepcopy(handle.state.draft)
  if type(callback) ~= "function" then
    finish(handle, "applied")
    return draft
  end
  local called, result, callback_err = pcall(callback, draft, handle.state, handle)
  if not called then
    handle.state = form_state.reduce(handle.state, { type = "form_error", error = result })
    M.render(handle)
    return nil, util.err("FORM_SUBMIT_FAILED", tostring(result))
  end
  if result == false or (result == nil and callback_err ~= nil) then
    handle.state = form_state.reduce(handle.state, {
      type = "form_error",
      error = callback_err or "the operation could not be applied",
    })
    M.render(handle)
    return nil, callback_err or util.err("FORM_SUBMIT_REJECTED", "the operation could not be applied")
  end
  finish(handle, "applied")
  return result == nil and draft or result
end

---Dispatch the semantic form actions exposed by ui/action_registry.lua.
function M.perform(handle, action)
  if action == "previous" then return M.move(handle, -1) end
  if action == "next" then return M.move(handle, 1) end
  if action == "edit" then return M.edit(handle) end
  if action == "apply" then return M.apply(handle) end
  if action == "reset" then return M.reset(handle) end
  if action == "cancel" then return M.cancel(handle, "cancelled") end
  return nil, util.err("FORM_ACTION", "unsupported structured form action " .. tostring(action))
end

local function set_buffer_options(bufnr)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modeline = false
  vim.bo[bufnr].undolevels = -1
  vim.bo[bufnr].filetype = "roomplan-form"
  vim.bo[bufnr].modifiable = false
end

local function install_keymaps(handle)
  local function map(lhs, rhs, desc, name)
    mappings.set(handle.bufnr, lhs, rhs, desc, name)
  end
  map("j", function() M.move(handle, 1) end, "Next RoomPlan form field")
  map("k", function() M.move(handle, -1) end, "Previous RoomPlan form field")
  map("<Tab>", function() M.move(handle, 1) end, "Next RoomPlan form field", "form_next_field")
  map("<S-Tab>", function() M.move(handle, -1) end, "Previous RoomPlan form field", "form_previous_field")
  map("<CR>", function() M.edit(handle) end, "Edit RoomPlan form field", "form_edit")
  map("e", function() M.edit(handle) end, "Edit RoomPlan form field")
  map("h", function() M.cycle(handle, -1) end, "Previous RoomPlan form choice", "form_previous_choice")
  map("l", function() M.cycle(handle, 1) end, "Next RoomPlan form choice", "form_next_choice")
  map("<Space>", function() M.cycle(handle, 1) end, "Toggle RoomPlan form choice", "form_toggle")
  map("<C-s>", function() M.apply(handle) end, "Apply RoomPlan form", "form_apply")
  map("R", function() M.reset(handle) end, "Reset RoomPlan form", "form_reset")
  map("?", function() require("roomplan.ui.help").open(handle.session) end,
    "Open RoomPlan form actions", "help")
  map("q", function() M.cancel(handle, "cancelled") end, "Cancel RoomPlan form")
  map("<Esc>", function() M.cancel(handle, "cancelled") end, "Cancel RoomPlan form", "form_cancel")
end

local function open_window(bufnr, callbacks, width, height)
  if type(callbacks.open_window) == "function" then return callbacks.open_window(bufnr, width, height) end
  local available_width = math.max(20, vim.o.columns - 4)
  local available_height = math.max(6, vim.o.lines - 4)
  width = math.min(width, available_width)
  height = math.min(height, available_height)
  return vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    style = "minimal",
    border = callbacks.border or "rounded",
    width = width,
    height = height,
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    row = math.max(0, math.floor((vim.o.lines - height) / 2)),
  })
end

function M.open(session, spec, callbacks)
  callbacks = callbacks or {}
  if type(session) ~= "table" then return nil, util.err("FORM_SESSION", "a RoomPlan session is required") end
  if type(spec) ~= "table" or type(spec.fields) ~= "table" then
    return nil, util.err("FORM_SPEC", "a structured form spec with fields is required")
  end
  if session.form and M.is_current(session.form) then
    if valid_window(session.form.winid) then vim.api.nvim_set_current_win(session.form.winid) end
    return session.form
  end
  session.workflow = session.workflow or { generation = 0, kind = nil }
  if session.workflow.kind then
    return nil, util.err("WORKFLOW_ACTIVE", "another RoomPlan workflow is already active", {
      active = session.workflow.kind,
    })
  end
  session.workflow.generation = session.workflow.generation + 1
  local workflow_generation = session.workflow.generation
  local workflow_kind = "form:" .. tostring(spec.id or "structured")
  session.workflow.kind = workflow_kind
  local base_revision_id = type(session.revision_id) == "function" and session:revision_id() or nil
  local context = callbacks.context or spec.context or {}
  context.session = context.session or session
  local state = form_state.new(spec, context, {
    draft = callbacks.draft,
    active_key = callbacks.active_key,
    base_revision_id = base_revision_id,
  })

  next_id = next_id + 1
  local bufnr = vim.api.nvim_create_buf(false, true)
  local handle = {
    id = next_id,
    session = session,
    spec = spec,
    state = state,
    callbacks = callbacks,
    bufnr = bufnr,
    namespace = vim.api.nvim_create_namespace("roomplan.form." .. next_id),
    workflow_generation = workflow_generation,
    workflow_kind = workflow_kind,
    edit_token = 0,
    closed = false,
  }
  session.form = handle
  define_highlights()
  set_buffer_options(bufnr)
  pcall(vim.api.nvim_buf_set_name, bufnr, "roomplan://form/" .. tostring(spec.id or next_id) .. "/" .. next_id)
  local width = callbacks.width or math.max(48, math.min(76, vim.o.columns - 6))
  handle.width = width
  local initial_output = renderer.build(state, {
    width = side_preview.width(handle),
    include_preview = not side_preview.visible(handle),
  })
  local height = callbacks.height or math.max(8, math.min(initial_output.meta.height, vim.o.lines - 6))
  handle.height = height
  handle.winid = open_window(bufnr, callbacks, width, height)
  if not valid_window(handle.winid) then
    finish(handle, "open failed", { skip_window = true })
    return nil, util.err("FORM_WINDOW", "could not open the RoomPlan form window")
  end
  vim.wo[handle.winid].wrap = false
  vim.wo[handle.winid].number = false
  vim.wo[handle.winid].relativenumber = false
  vim.wo[handle.winid].signcolumn = "no"
  vim.wo[handle.winid].cursorline = false
  local ok, roomplan_state = pcall(require, "roomplan.state")
  if ok and session.id then roomplan_state.attach_buffer(session, bufnr, "form") end
  install_keymaps(handle)
  handle.augroup = vim.api.nvim_create_augroup("RoomPlanForm" .. next_id, { clear = true })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = handle.augroup,
    buffer = bufnr,
    once = true,
    callback = function()
      if not handle.internal_closing and not handle.closed then
        M.cancel(handle, "buffer wiped", { skip_buffer = true, skip_window = true })
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = handle.augroup,
    pattern = tostring(handle.winid),
    once = true,
    callback = function()
      if not handle.internal_closing and not handle.closed then
        M.cancel(handle, "window closed", { skip_window = true })
      end
    end,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = handle.augroup,
    callback = function()
      if M.is_current(handle) then M.render(handle) end
    end,
  })
  M.render(handle)
  if type(callbacks.on_open) == "function" then callbacks.on_open(handle) end
  return handle
end

function M.for_session(session)
  return session and session.form or nil
end

M.close = M.cancel
M.fields = fields
M.state = form_state
M.renderer = renderer

return M
