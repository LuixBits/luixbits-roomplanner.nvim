local util = require("roomplan.util")

local M = {}
local Flow = {}
Flow.__index = Flow

function M.new(session, kind, opts)
  opts = opts or {}
  session.workflow = session.workflow or { generation = 0 }
  if session.workflow.kind then
    return nil, util.err("WORKFLOW_ACTIVE", "another RoomPlan workflow is already active", {
      active = session.workflow.kind,
    })
  end
  session.workflow.generation = session.workflow.generation + 1
  session.workflow.kind = kind
  local flow = setmetatable({
    session = session,
    generation = session.workflow.generation,
    kind = kind,
    draft = opts.draft or {},
    on_cancel = opts.on_cancel,
    done = false,
  }, Flow)
  return flow
end

function Flow:is_current()
  return not self.done
    and self.session
    and self.session.workflow
    and self.session.workflow.generation == self.generation
    and self.session.workflow.kind == self.kind
    and not self.session.closed
end

function Flow:finish(value)
  if not self:is_current() then
    return false
  end
  self.done = true
  self.session.workflow.kind = nil
  self.session.workflow.generation = self.session.workflow.generation + 1
  return true, value
end

function Flow:cancel(reason)
  if self.done then
    return
  end
  local current = self:is_current()
  self.done = true
  if current then
    self.session.workflow.kind = nil
    self.session.workflow.generation = self.session.workflow.generation + 1
  end
  if self.on_cancel then
    self.on_cancel(reason)
  end
end

function Flow:input(opts, callback)
  if not self:is_current() then
    return
  end
  vim.ui.input(opts, function(value)
    if not self:is_current() then
      return
    end
    if value == nil then
      self:cancel("cancelled")
      return
    end
    callback(value, self)
  end)
end

function Flow:select(items, opts, callback)
  if not self:is_current() then
    return
  end
  vim.ui.select(items, opts or {}, function(choice, index)
    if not self:is_current() then
      return
    end
    if choice == nil then
      self:cancel("cancelled")
      return
    end
    callback(choice, index, self)
  end)
end

function Flow:retry(fn)
  if self:is_current() then
    vim.schedule(function()
      if self:is_current() then
        fn(self)
      end
    end)
  end
end

function M.cancel(session, reason)
  if not session.workflow then
    return
  end
  session.workflow.generation = (session.workflow.generation or 0) + 1
  session.workflow.kind = nil
  if session.workflow.on_cancel then
    pcall(session.workflow.on_cancel, reason)
  end
end

return M
