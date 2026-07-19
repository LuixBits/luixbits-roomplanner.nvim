local compat = require("roomplan.compat")
local util = require("roomplan.util")

local M = {
  sessions = {},
  source_keys = {},
  buffer_sessions = {},
  next_id = 1,
}

function M.source_key(source)
  if source.path then
    local path = compat.normalize_path(source.path) or source.path
    local uname = vim.uv.os_uname()
    if uname and uname.sysname and uname.sysname:lower():find("windows", 1, true) then path = path:lower() end
    return "path:" .. path
  end
  if source.bufnr then return string.format("buffer:%d:%s", source.bufnr, source.adapter or "unknown") end
  return nil
end

function M.allocate_id()
  local id = "session-" .. M.next_id
  M.next_id = M.next_id + 1
  return id
end

function M.add(session)
  assert(type(session) == "table" and type(session.id) == "string", "invalid RoomPlan session")
  local key = M.source_key(session.source or {})
  if key and M.source_keys[key] and M.source_keys[key] ~= session.id then
    return nil,
      util.err("SESSION_SOURCE_OWNED", "another RoomPlan session owns this source", {
        owner = M.source_keys[key],
        key = key,
      })
  end
  M.sessions[session.id] = session
  if key then
    M.source_keys[key] = session.id
    session.source_key = key
  end
  if session.source and session.source.bufnr then M.attach_buffer(session, session.source.bufnr, "source") end
  return session
end

function M.attach_buffer(session, bufnr, role)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
  M.buffer_sessions[bufnr] = session.id
  vim.b[bufnr].roomplan_session_id = session.id
  vim.b[bufnr].roomplan_buffer_role = role
end

function M.detach_buffer(bufnr)
  M.buffer_sessions[bufnr] = nil
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.b[bufnr].roomplan_session_id = nil
    vim.b[bufnr].roomplan_buffer_role = nil
  end
end

function M.get(id) return id and M.sessions[id] or nil end

function M.for_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local id = M.buffer_sessions[bufnr] or vim.b[bufnr].roomplan_session_id
  return M.sessions[id]
end

function M.list()
  local result = {}
  for _, session in pairs(M.sessions) do
    result[#result + 1] = session
  end
  table.sort(result, function(a, b) return a.id < b.id end)
  return result
end

function M.resolve(opts)
  opts = opts or {}
  if opts.session_id then
    local session = M.get(opts.session_id)
    if session then return session end
    return nil, util.err("SESSION_NOT_FOUND", "RoomPlan session no longer exists", { session_id = opts.session_id })
  end
  local current = M.for_buffer(opts.bufnr or vim.api.nvim_get_current_buf())
  if current then return current end
  local sessions = M.list()
  if #sessions == 1 then
    return sessions[1]
  elseif #sessions == 0 then
    return nil, util.err("NO_ACTIVE_SESSION", "no RoomPlan session is active")
  end
  return nil, util.err("SESSION_AMBIGUOUS", "multiple RoomPlan sessions are active", { count = #sessions })
end

function M.remove(session)
  if not session then return end
  M.sessions[session.id] = nil
  if session.source_key and M.source_keys[session.source_key] == session.id then
    M.source_keys[session.source_key] = nil
  end
  for bufnr, id in pairs(M.buffer_sessions) do
    if id == session.id then
      M.buffer_sessions[bufnr] = nil
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.b[bufnr].roomplan_session_id = nil
        vim.b[bufnr].roomplan_buffer_role = nil
      end
    end
  end
end

function M.update_source(session, source)
  local old_key = session.source_key
  local old_bufnr = session.source and session.source.bufnr
  local new_key = M.source_key(source)
  if new_key and M.source_keys[new_key] and M.source_keys[new_key] ~= session.id then
    return nil,
      util.err("SESSION_SOURCE_OWNED", "another RoomPlan session owns the destination", {
        owner = M.source_keys[new_key],
        key = new_key,
      })
  end
  if old_key and M.source_keys[old_key] == session.id then M.source_keys[old_key] = nil end
  if old_bufnr and old_bufnr ~= source.bufnr then
    if session.augroup then pcall(vim.api.nvim_clear_autocmds, { group = session.augroup, buffer = old_bufnr }) end
    if M.buffer_sessions[old_bufnr] == session.id then
      M.buffer_sessions[old_bufnr] = nil
      if vim.api.nvim_buf_is_valid(old_bufnr) then
        vim.b[old_bufnr].roomplan_session_id = nil
        vim.b[old_bufnr].roomplan_buffer_role = nil
      end
    end
  end
  session.source = source
  session.source_key = new_key
  if new_key then M.source_keys[new_key] = session.id end
  if source.bufnr then M.attach_buffer(session, source.bufnr, "source") end
  return true
end

function M.reset()
  for _, session in ipairs(M.list()) do
    if session.destroy then pcall(session.destroy, session, { force = true }) end
  end
  M.sessions = {}
  M.source_keys = {}
  M.buffer_sessions = {}
  M.next_id = 1
end

return M
