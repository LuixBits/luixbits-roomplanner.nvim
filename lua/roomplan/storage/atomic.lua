local util = require("roomplan.util")

local M = {}

local function close(fd)
  if fd then return vim.uv.fs_close(fd) end
  return true
end

local function cleanup(path)
  if path then pcall(vim.uv.fs_unlink, path) end
end

local function result_error(code, message, path, extra)
  extra = extra or {}
  extra.path = path
  return nil, util.err(code, message, extra)
end

function M.write_new(path, data, opts)
  opts = opts or {}
  if type(path) ~= "string" or path == "" then
    return result_error("ATOMIC_PATH_INVALID", "expected a non-empty path", path)
  end
  if vim.uv.fs_lstat(path) then return result_error("ATOMIC_TARGET_EXISTS", "target already exists", path) end
  local parent = vim.fs.dirname(path)
  local parent_stat = vim.uv.fs_stat(parent)
  if not parent_stat or parent_stat.type ~= "directory" then
    return result_error("ATOMIC_PARENT_INVALID", "parent is not a directory", parent)
  end

  local temp
  local fd
  for attempt = 1, 100 do
    temp = string.format("%s/.%s.roomplan-tmp-%d-%d", parent, vim.fs.basename(path), vim.uv.os_getpid(), attempt)
    fd = vim.uv.fs_open(temp, "wx", opts.mode or 420)
    if fd then break end
  end
  if not fd then return result_error("ATOMIC_TEMP_CREATE_FAILED", "could not create exclusive temporary file", path) end

  local offset = 0
  while offset < #data do
    local written, write_err = vim.uv.fs_write(fd, data:sub(offset + 1), offset)
    if not written then
      close(fd)
      cleanup(temp)
      return result_error("ATOMIC_WRITE_FAILED", tostring(write_err), path, { temp = temp })
    end
    if written <= 0 then
      close(fd)
      cleanup(temp)
      return result_error("ATOMIC_PARTIAL_WRITE", "write made no progress", path, { temp = temp })
    end
    offset = offset + written
  end

  local sync_ok, sync_err = vim.uv.fs_fsync(fd)
  if not sync_ok then
    close(fd)
    cleanup(temp)
    return result_error("ATOMIC_FSYNC_FAILED", tostring(sync_err), path, { temp = temp })
  end
  local close_ok, close_err = close(fd)
  fd = nil
  if not close_ok then
    cleanup(temp)
    return result_error("ATOMIC_CLOSE_FAILED", tostring(close_err), path, { temp = temp })
  end

  if vim.uv.fs_lstat(path) then
    cleanup(temp)
    return result_error("ATOMIC_TARGET_RACED", "target appeared before finalization", path)
  end
  local linked, link_err = vim.uv.fs_link(temp, path)
  if not linked then
    cleanup(temp)
    return result_error("ATOMIC_FINALIZE_FAILED", tostring(link_err), path)
  end
  local unlinked, unlink_err = vim.uv.fs_unlink(temp)
  if not unlinked then
    return result_error(
      "ATOMIC_TEMP_CLEANUP_FAILED",
      tostring(unlink_err),
      path,
      { temp = temp, target_created = true }
    )
  end

  local dir_fd = vim.uv.fs_open(parent, "r", 438)
  if dir_fd then
    pcall(vim.uv.fs_fsync, dir_fd)
    close(dir_fd)
  end
  return true
end

return M
