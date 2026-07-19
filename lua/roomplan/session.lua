local compat = require("roomplan.compat")
local config = require("roomplan.config")
local history = require("roomplan.history")
local state = require("roomplan.state")
local util = require("roomplan.util")

local M = {}
local Session = {}
Session.__index = Session
local editor_shutting_down = false
local exit_autocmd_installed = false

local function ensure_exit_autocmd()
  if exit_autocmd_installed then return end
  exit_autocmd_installed = true
  local group = vim.api.nvim_create_augroup("RoomPlanExitGuard", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function() editor_shutting_down = true end,
    desc = "Do not recreate RoomPlan guards while Neovim exits",
  })
end

local function valid_buffer(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

local function set_modified(bufnr, value)
  if not valid_buffer(bufnr) then
    return
  end
  pcall(vim.api.nvim_set_option_value, "modified", value, { buf = bufnr })
end

local function session_group(session)
  return "RoomPlanSession" .. session.id:gsub("[^%w]", "")
end

function Session:model()
  return self.history:current_model()
end

function Session:current_model()
  return self.preview_model or self:model()
end

function Session:revision_id()
  return self.history:current_revision_id()
end

function Session:model_dirty()
  return self.history:is_dirty()
end

function Session:schema_rewrite_pending()
  local info = self.normalization_info
  return info ~= nil and (info.normalized == true or info.migrated == true)
end

function Session:source_buffer_modified()
  return valid_buffer(self.source.bufnr) and vim.bo[self.source.bufnr].modified or false
end

function Session:requires_protection()
  return self:model_dirty()
    or self.pending_disk_write
    or self.retained_model_at_risk
    or self.source_rebind_pending ~= nil
    or (self.buffer_payload_revision_id ~= nil and self.buffer_payload_revision_id ~= self.history.durable_savepoint_revision_id)
end

function Session:status_flags()
  local flags = {}
  if self:model_dirty() then flags[#flags + 1] = "MODEL DIRTY" end
  if self.buffer_payload_revision_id then
    flags[#flags + 1] = "STAGED r" .. tostring(self.buffer_payload_revision_id)
  end
  if self:source_buffer_modified() then flags[#flags + 1] = "SOURCE MODIFIED" end
  if self.pending_disk_write then flags[#flags + 1] = "PENDING WRITE" end
  if self.source_rebind_pending then flags[#flags + 1] = "SOURCE RENAMED" end
  if self.source_conflicted then flags[#flags + 1] = "CONFLICT" end
  if #flags == 0 then flags[1] = "SAVED" end
  return flags
end

function Session:status_text()
  local flags = self:status_flags()
  for index, flag in ipairs(flags) do flags[index] = "[" .. flag .. "]" end
  return table.concat(flags, " ")
end

function Session:update_guard()
  if self.closed or self.tearing_down then
    return
  end
  if not valid_buffer(self.guard_bufnr) then
    self:create_guard()
  end
  set_modified(self.guard_bufnr, self:requires_protection())
end

function Session:create_guard()
  if self.closed or self.tearing_down or valid_buffer(self.guard_bufnr) then
    return self.guard_bufnr
  end
  local bufnr = vim.api.nvim_create_buf(false, true)
  self.guard_bufnr = bufnr
  vim.api.nvim_buf_set_name(bufnr, "roomplan://guard/" .. self.id)
  vim.bo[bufnr].buftype = "acwrite"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modeline = false
  vim.bo[bufnr].undolevels = -1
  vim.bo[bufnr].modifiable = false
  state.attach_buffer(self, bufnr, "guard")

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = self.augroup,
    buffer = bufnr,
    desc = "Persist protected RoomPlan session",
    callback = function()
      if self.closed or self.tearing_down then return end
      local ok, err = require("roomplan.controller").save(self, {
        noninteractive = true,
        guard = true,
      })
      if not ok then
        set_modified(bufnr, true)
        local message = (err and err.message) or "RoomPlan guard save failed"
        if err and err.code == "SOURCE_CONFLICT" then
          compat.notify("RoomPlan source changed; choose how to resolve it before saving.", vim.log.levels.WARN)
          if not self.guard_resolution_scheduled then
            self.guard_resolution_scheduled = true
            vim.schedule(function()
              self.guard_resolution_scheduled = false
              if not self.closed and not self.tearing_down and self.source_conflicted then
                require("roomplan.controller").resolve_conflict(self)
              end
            end)
          end
        else
          compat.notify("RoomPlan could not save protected changes: " .. message, vim.log.levels.ERROR)
        end
        return
      end
      set_modified(bufnr, false)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = self.augroup,
    buffer = bufnr,
    desc = "Restore RoomPlan quit guard",
    callback = function()
      state.detach_buffer(bufnr)
      if self.guard_bufnr == bufnr then self.guard_bufnr = nil end
      if self.closed or self.tearing_down or editor_shutting_down then return end
      vim.schedule(function()
        if not self.closed and not self.tearing_down and not editor_shutting_down then
          self:create_guard()
          self:update_guard()
          if self:requires_protection() then
            compat.notify("RoomPlan restored the quit guard for " .. (self.source.path or self.id), vim.log.levels.WARN)
          end
        end
      end)
    end,
  })
  set_modified(bufnr, self:requires_protection())
  return bufnr
end

function Session:attach_source_autocmds()
  local bufnr = self.source.bufnr
  if not valid_buffer(bufnr) then return end
  state.attach_buffer(self, bufnr, "source")
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = self.augroup,
    buffer = bufnr,
    desc = "Notice RoomPlan source edits",
    callback = function()
      if self.closed or self.internal_source_write then return end
      self.source_needs_recheck = true
      vim.schedule(function()
        if not self.closed and self.source_needs_recheck then
          require("roomplan.controller").check_source(self)
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = self.augroup,
    buffer = bufnr,
    desc = "Detach wiped RoomPlan source buffer",
    callback = function()
      state.detach_buffer(bufnr)
      if self.source.bufnr == bufnr then self.source.bufnr = nil end
    end,
  })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = self.augroup,
    buffer = bufnr,
    desc = "Reconcile a native write of staged RoomPlan text",
    callback = function()
      if self.closed or self.internal_source_write then return end
      vim.schedule(function()
        if not self.closed then require("roomplan.controller").source_written(self) end
      end)
    end,
  })
  vim.api.nvim_create_autocmd("BufFilePost", {
    group = self.augroup,
    buffer = bufnr,
    desc = "Notice RoomPlan source rename",
    callback = function()
      if self.closed then return end
      local name = vim.api.nvim_buf_get_name(bufnr)
      local normalized = name ~= "" and compat.normalize_path(name) or nil
      if normalized and normalized ~= self.source.path then
        self.source_rebind_pending = normalized
        self:update_guard()
        compat.notify("RoomPlan source was renamed; use Save As or restore the original name", vim.log.levels.WARN)
      elseif normalized == self.source.path and self.source_rebind_pending then
        self.source_rebind_pending = nil
        self:update_guard()
      end
    end,
  })
end

function Session:commit(snapshot, result)
  local node, info = self.history:push(snapshot, result)
  if not node then return nil, info end
  self.validation_revision_id = nil
  if result and result.touched and result.touched[1] then
    self.selection = result.touched[1]
  end
  self:update_guard()
  require("roomplan.controller").refresh(self)
  require("roomplan.controller").maybe_autosave(self)
  return node, info
end

function Session:undo()
  local snapshot, node = self.history:undo()
  if not snapshot then return nil, node end
  self.validation_revision_id = nil
  if node.touched and node.touched[1] then self.selection = node.touched[1] end
  self.marked_objects = {}
  self.batch_move = nil
  self:update_guard()
  require("roomplan.controller").refresh(self)
  return snapshot, node
end

function Session:redo()
  local snapshot, node = self.history:redo()
  if not snapshot then return nil, node end
  self.validation_revision_id = nil
  if node.touched and node.touched[1] then self.selection = node.touched[1] end
  self.marked_objects = {}
  self.batch_move = nil
  self:update_guard()
  require("roomplan.controller").refresh(self)
  return snapshot, node
end

function Session:restore_revision(revision_id)
  local snapshot, node = self.history:checkout(revision_id)
  if not snapshot then
    return nil, node
  end
  self.validation_revision_id = nil
  self.selection = node.touched and node.touched[1] or nil
  self.marked_objects = {}
  self.batch_move = nil
  self.measurement = nil
  self:update_guard()
  require("roomplan.controller").refresh(self)
  return snapshot, node
end

function Session:mark_saved(revision, locator)
  local ok, err = self.history:mark_saved()
  if not ok then return nil, err end
  self.source.revision = revision
  if locator then self.source.locator = locator end
  self.durable_source_matches_savepoint = true
  self.buffer_payload_revision_id = nil
  self.pending_disk_write = false
  self.source_conflicted = false
  self.retained_model_at_risk = false
  self.source_needs_recheck = false
  self.normalization_info = nil
  self:update_guard()
  return true
end

function Session:reset(snapshot, revision, locator, opts)
  opts = opts or {}
  pcall(function() require("roomplan.controller.sun").close(self) end)
  if self.form then pcall(function() require("roomplan.ui.form").cancel(self.form, "plan reloaded") end) end
  self.history:reset(snapshot, { durable = opts.durable ~= false, label = opts.label or "Reload plan" })
  self.source.revision = revision
  if locator then self.source.locator = locator end
  self.buffer_payload_revision_id = nil
  self.pending_disk_write = false
  self.source_conflicted = false
  self.retained_model_at_risk = false
  self.durable_source_matches_savepoint = opts.durable ~= false
  self.validation = {}
  self.validation_revision_id = nil
  self.selection = nil
  self.marked_objects = {}
  self.batch_move = nil
  self.measurement = nil
  self.mode = "NAV"
  self.shape_edit = nil
  self.preview_model = nil
  self.snap_guides = {}
  self.snap_exclusions = {}
  self.move_feedback = nil
  self.reserved_ids = require("roomplan.ids").used_set(snapshot, self.reserved_ids)
  self:update_guard()
end

function Session:destroy(opts)
  opts = opts or {}
  if self.closed then return true end
  if self:requires_protection() and not opts.force then
    return nil, util.err("SESSION_DIRTY", "RoomPlan session has protected changes")
  end
  self.tearing_down = true
  pcall(function() require("roomplan.controller.sun").close(self) end)
  pcall(function() require("roomplan.ui.minimap").close(self) end)
  if self.form then pcall(function() require("roomplan.ui.form").cancel(self.form, "session closed") end) end
  require("roomplan.ui.flow").cancel(self, "session closed")
  if self.workspace then pcall(function() require("roomplan.ui.workspace").close(self) end) end
  pcall(function() require("roomplan.render.canvas").close(self) end)
  if valid_buffer(self.guard_bufnr) then
    pcall(vim.api.nvim_set_option_value, "modified", false, { buf = self.guard_bufnr })
    pcall(vim.api.nvim_buf_delete, self.guard_bufnr, { force = true })
  end
  pcall(vim.api.nvim_del_augroup_by_id, self.augroup)
  self.history:dispose()
  self.closed = true
  self.tearing_down = false
  state.remove(self)
  return true
end

function M.new(source, model, opts)
  opts = opts or {}
  ensure_exit_autocmd()
  local limits = config.get().limits
  local session = setmetatable({
    id = state.allocate_id(),
    source = source,
    history = history.new(model, {
      durable = opts.durable ~= false,
      -- `max_history` is the advertised undo depth; history counts the
      -- current snapshot as a node as well.
      max_nodes = limits.max_history + 1,
      max_bytes = limits.max_history_bytes_per_session,
      global_max_bytes = limits.max_history_bytes_global,
    }),
    durable_source_matches_savepoint = opts.durable ~= false,
    buffer_payload_revision_id = nil,
    validation = {},
    selection = nil,
    selection_cycle = {},
    marked_objects = {},
    batch_move = nil,
    measurement = nil,
    viewport = opts.viewport,
    canvas_detail_level = config.get().canvas.detail_level,
    mode = "NAV",
    snap_enabled = config.get().snapping.enabled,
    snap_guides = {},
    snap_exclusions = {},
    move_feedback = nil,
    canvas = { bufnr = nil, winid = nil },
    minimap = { enabled = false },
    workflow = { generation = 0, kind = nil },
    source_conflicted = false,
    retained_model_at_risk = false,
    pending_disk_write = opts.pending_disk_write or false,
    reserved_ids = require("roomplan.ids").used_set(model),
    closed = false,
  }, Session)
  session.augroup = vim.api.nvim_create_augroup(session_group(session), { clear = true })
  local added, err = state.add(session)
  if not added then
    session.history:dispose()
    pcall(vim.api.nvim_del_augroup_by_id, session.augroup)
    return nil, err
  end
  session:create_guard()
  session:attach_source_autocmds()
  session:update_guard()
  return session
end

M.Session = Session

return M
