-- Bounded full-snapshot semantic history for RoomPlan sessions.

local model = require("roomplan.model")

local M = {}
local History = {}
History.__index = History

M.DEFAULT_MAX_UNDO_NODES = 100
M.DEFAULT_MAX_NODES = M.DEFAULT_MAX_UNDO_NODES + 1
M.DEFAULT_MAX_BYTES = 64 * 1024 * 1024
M.DEFAULT_GLOBAL_MAX_BYTES = 256 * 1024 * 1024

local histories = setmetatable({}, { __mode = "k" })
local global_bytes = 0
local access_clock = 0

local function touch(history)
  access_clock = access_clock + 1
  history.last_access = access_clock
end

local function clamp_integer(value, default, minimum, maximum)
  if type(value) ~= "number" or value ~= math.floor(value) then return default end
  if value < minimum then
    return minimum
  elseif value > maximum then
    return maximum
  end
  return value
end

local function node_size(node)
  return 96
    + model.estimate_size(node.model)
    + model.estimate_size(node.label)
    + model.estimate_size(node.touched)
    + model.estimate_size(node.metadata)
end

local function add_bytes(history, amount)
  history.bytes = history.bytes + amount
  global_bytes = global_bytes + amount
end

local function subtract_bytes(history, amount)
  history.bytes = math.max(0, history.bytes - amount)
  global_bytes = math.max(0, global_bytes - amount)
end

local function clear_savepoint_if(history, revision_id)
  if history.durable_savepoint_revision_id == revision_id then history.durable_savepoint_revision_id = nil end
end

local function remove_node(history, index)
  local node = history.nodes[index]
  if not node or index == history.cursor then return false end
  clear_savepoint_if(history, node.revision_id)
  subtract_bytes(history, node.estimated_bytes)
  table.remove(history.nodes, index)
  if index < history.cursor then history.cursor = history.cursor - 1 end
  return true
end

local function trim_one(history)
  if #history.nodes <= 1 then return false end
  if history.cursor > 1 then return remove_node(history, 1) end
  return remove_node(history, #history.nodes)
end

local function trim_local(history)
  local trimmed = 0
  while #history.nodes > history.max_nodes do
    if not trim_one(history) then break end
    trimmed = trimmed + 1
  end
  while history.bytes > history.max_bytes and #history.nodes > 1 do
    if not trim_one(history) then break end
    trimmed = trimmed + 1
  end
  history.last_trimmed = trimmed
  history.reduced_capacity = history.bytes > history.max_bytes or history.max_nodes < M.DEFAULT_MAX_NODES
  return trimmed
end

local function trim_global(requesting_history)
  local limit = requesting_history.global_max_bytes
  local trimmed = 0
  while global_bytes > limit do
    local candidate
    for history in pairs(histories) do
      if not history.disposed and #history.nodes > 1 then
        if not candidate or history.last_access < candidate.last_access then candidate = history end
      end
    end
    if not candidate or not trim_one(candidate) then break end
    candidate.reduced_capacity = true
    candidate.last_trimmed = (candidate.last_trimmed or 0) + 1
    trimmed = trimmed + 1
  end
  return trimmed
end

local function make_node(history, snapshot, label, touched, metadata)
  local node = {
    revision_id = history.next_revision_id,
    label = label or "Edit plan",
    model = model.deep_copy(snapshot),
    touched = model.deep_copy(touched or {}),
    metadata = model.deep_copy(metadata or {}),
  }
  node.estimated_bytes = node_size(node)
  history.next_revision_id = history.next_revision_id + 1
  return node
end

function M.new(initial_model, options)
  options = options or {}
  local requested_max_nodes = options.max_nodes
  if requested_max_nodes == nil and type(options.max_undo_nodes) == "number" then
    requested_max_nodes = options.max_undo_nodes + 1
  end
  local history = setmetatable({
    nodes = {},
    cursor = 1,
    next_revision_id = 1,
    durable_savepoint_revision_id = nil,
    bytes = 0,
    max_nodes = clamp_integer(requested_max_nodes, M.DEFAULT_MAX_NODES, 1, 10001),
    max_bytes = clamp_integer(options.max_bytes, M.DEFAULT_MAX_BYTES, 1024, 1024 * 1024 * 1024),
    global_max_bytes = clamp_integer(
      options.global_max_bytes,
      M.DEFAULT_GLOBAL_MAX_BYTES,
      1024,
      4 * 1024 * 1024 * 1024
    ),
    reduced_capacity = false,
    last_trimmed = 0,
    disposed = false,
  }, History)
  touch(history)
  histories[history] = true
  local initial = make_node(history, initial_model, options.label or "Initial load", options.touched, options.metadata)
  history.nodes[1] = initial
  add_bytes(history, initial.estimated_bytes)
  if options.durable ~= false then history.durable_savepoint_revision_id = initial.revision_id end
  trim_local(history)
  trim_global(history)
  return history
end

function History:current_node()
  touch(self)
  return self.nodes[self.cursor]
end

function History:current_model()
  local node = self:current_node()
  return node and node.model or nil
end

function History:current_revision_id()
  local node = self:current_node()
  return node and node.revision_id or nil
end

function History:is_dirty()
  local node = self:current_node()
  return node == nil or node.revision_id ~= self.durable_savepoint_revision_id
end

function History:can_undo() return self.cursor > 1 end

function History:can_redo() return self.cursor < #self.nodes end

function History:push(snapshot, result)
  if self.disposed then return nil, { code = "HISTORY_DISPOSED", message = "history has been disposed" } end
  result = result or {}
  local current = self.nodes[self.cursor]
  if current and model.deep_equal(current.model, snapshot) then
    touch(self)
    return nil, { code = "HISTORY_NO_CHANGE", message = "semantically identical model creates no history node" }
  end

  -- Branch only after the no-op check, so a no-op after undo preserves redo.
  while #self.nodes > self.cursor do
    local removed = self.nodes[#self.nodes]
    clear_savepoint_if(self, removed.revision_id)
    subtract_bytes(self, removed.estimated_bytes)
    table.remove(self.nodes)
  end

  local node = make_node(self, snapshot, result.label, result.touched, result.metadata)
  self.nodes[#self.nodes + 1] = node
  self.cursor = #self.nodes
  add_bytes(self, node.estimated_bytes)
  touch(self)
  local locally_trimmed = trim_local(self)
  local globally_trimmed = trim_global(self)
  return node, {
    trimmed = locally_trimmed + globally_trimmed,
    reduced_capacity = self.reduced_capacity,
  }
end

function History:undo()
  if self.disposed then return nil, { code = "HISTORY_DISPOSED", message = "history has been disposed" } end
  if self.cursor <= 1 then
    touch(self)
    return nil, { code = "HISTORY_AT_OLDEST", message = "there is no older model revision" }
  end
  self.cursor = self.cursor - 1
  touch(self)
  local node = self.nodes[self.cursor]
  return node.model, node
end

function History:redo()
  if self.disposed then return nil, { code = "HISTORY_DISPOSED", message = "history has been disposed" } end
  if self.cursor >= #self.nodes then
    touch(self)
    return nil, { code = "HISTORY_AT_NEWEST", message = "there is no newer model revision" }
  end
  self.cursor = self.cursor + 1
  touch(self)
  local node = self.nodes[self.cursor]
  return node.model, node
end

function History:mark_saved(revision_id)
  local current = self.nodes[self.cursor]
  revision_id = revision_id or (current and current.revision_id)
  if not current or revision_id ~= current.revision_id then
    return nil,
      { code = "HISTORY_SAVEPOINT_REVISION", message = "only the current revision can become the durable savepoint" }
  end
  self.durable_savepoint_revision_id = revision_id
  touch(self)
  return true
end

function History:node_by_revision(revision_id)
  for _, node in ipairs(self.nodes) do
    if node.revision_id == revision_id then return node end
  end
  return nil
end

function History:model_at_revision(revision_id)
  local node = self:node_by_revision(revision_id)
  return node and node.model or nil
end

---Return detached history metadata for UI presentation without exposing the
---retained model snapshots themselves.
function History:entries()
  touch(self)
  local result = {}
  for index = #self.nodes, 1, -1 do
    local node = self.nodes[index]
    result[#result + 1] = {
      revision_id = node.revision_id,
      label = node.label,
      touched = model.deep_copy(node.touched or {}),
      current = index == self.cursor,
      saved = node.revision_id == self.durable_savepoint_revision_id,
      direction = index < self.cursor and "older" or index > self.cursor and "newer" or "current",
    }
  end
  return result
end

---Move the history cursor to any retained revision. The next semantic edit
---branches normally and discards newer nodes, exactly like undo followed by
---an edit.
function History:checkout(revision_id)
  if self.disposed then return nil, { code = "HISTORY_DISPOSED", message = "history has been disposed" } end
  for index, node in ipairs(self.nodes) do
    if node.revision_id == revision_id then
      self.cursor = index
      touch(self)
      return node.model, node
    end
  end
  touch(self)
  return nil, { code = "HISTORY_REVISION_MISSING", message = "that history revision is no longer retained" }
end

-- A later native :write may durably persist a staged older revision while the
-- history cursor has already moved on. Keep that exact savepoint when retained.
function History:mark_saved_revision(revision_id)
  if not self:node_by_revision(revision_id) then
    return nil, { code = "HISTORY_SAVEPOINT_MISSING", message = "saved revision is no longer retained in history" }
  end
  self.durable_savepoint_revision_id = revision_id
  touch(self)
  return true
end

function History:clear_savepoint()
  self.durable_savepoint_revision_id = nil
  touch(self)
end

-- Reload installs one fresh initial node while retaining monotonic session-local
-- revision IDs. A semantic no-op reload should be detected by the controller
-- before calling this method.
function History:reset(snapshot, options)
  options = options or {}
  local position = 1
  while position <= #self.nodes do
    subtract_bytes(self, self.nodes[position].estimated_bytes)
    position = position + 1
  end
  self.nodes = {}
  self.cursor = 1
  local node = make_node(self, snapshot, options.label or "Reload", options.touched, options.metadata)
  self.nodes[1] = node
  add_bytes(self, node.estimated_bytes)
  self.durable_savepoint_revision_id = options.durable == false and nil or node.revision_id
  touch(self)
  trim_local(self)
  trim_global(self)
  return node
end

function History:stats()
  touch(self)
  return {
    nodes = #self.nodes,
    undo_nodes = self.cursor - 1,
    redo_nodes = #self.nodes - self.cursor,
    bytes = self.bytes,
    max_nodes = self.max_nodes,
    max_bytes = self.max_bytes,
    current_revision_id = self.nodes[self.cursor] and self.nodes[self.cursor].revision_id or nil,
    durable_savepoint_revision_id = self.durable_savepoint_revision_id,
    dirty = self:is_dirty(),
    reduced_capacity = self.reduced_capacity,
    last_trimmed = self.last_trimmed,
  }
end

function History:dispose()
  if self.disposed then return end
  local position = 1
  while position <= #self.nodes do
    subtract_bytes(self, self.nodes[position].estimated_bytes)
    position = position + 1
  end
  self.nodes = {}
  self.cursor = 0
  self.durable_savepoint_revision_id = nil
  self.disposed = true
  histories[self] = nil
end

function M.global_stats()
  local count = 0
  for history in pairs(histories) do
    if not history.disposed then count = count + 1 end
  end
  return { histories = count, bytes = global_bytes, default_max_bytes = M.DEFAULT_GLOBAL_MAX_BYTES }
end

return M
