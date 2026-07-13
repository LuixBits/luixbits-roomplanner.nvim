local compat = require("roomplan.compat")
local util = require("roomplan.util")

local M = {}

local UTF8_BOM = "\239\187\191"

local function uv_error(code, message, path)
  return nil, util.err(code, message .. (path and (": " .. path) or ""), { path = path })
end

function M.read_file(path, opts)
  opts = opts or {}
  local fd, open_err = vim.uv.fs_open(path, "r", 438)
  if not fd then
    return uv_error("SOURCE_OPEN_FAILED", tostring(open_err), path)
  end
  local stat, stat_err = vim.uv.fs_fstat(fd)
  if not stat then
    vim.uv.fs_close(fd)
    return uv_error("SOURCE_STAT_FAILED", tostring(stat_err), path)
  end
  if stat.type ~= "file" then
    vim.uv.fs_close(fd)
    return uv_error("SOURCE_NOT_REGULAR", "source is not a regular file", path)
  end
  if type(opts.max_bytes) == "number" and stat.size > opts.max_bytes then
    vim.uv.fs_close(fd)
    return uv_error("SOURCE_SIZE_LIMIT", "source exceeds the configured byte limit", path)
  end
  local chunks = {}
  local offset = 0
  while offset < stat.size do
    local chunk, read_err = vim.uv.fs_read(fd, math.min(1024 * 1024, stat.size - offset), offset)
    if not chunk then
      vim.uv.fs_close(fd)
      return uv_error("SOURCE_READ_FAILED", tostring(read_err), path)
    end
    if #chunk == 0 then
      break
    end
    chunks[#chunks + 1] = chunk
    offset = offset + #chunk
  end
  local close_ok, close_err = vim.uv.fs_close(fd)
  if not close_ok then
    return uv_error("SOURCE_CLOSE_FAILED", tostring(close_err), path)
  end
  return table.concat(chunks), nil, stat
end

function M.buffer_text(bufnr)
  return compat.buf_text(bufnr)
end

-- Convert raw file bytes into the logical UTF-8 text Neovim exposes through a
-- loaded buffer. Keep this separate from disk snapshots: conflict detection
-- must continue comparing the original bytes, including BOM and line endings.
--
-- Exactly one leading UTF-8 BOM is a transport marker and is removed. A second
-- BOM remains content, so the strict JSON codec will still reject it. Line
-- endings are normalized only when the bytes uniformly match the loaded
-- buffer's fileformat. Mixed endings remain visible to conservative adapters
-- such as the Norg scanner.
function M.logical_text(bytes, context)
  if type(bytes) ~= "string" then return bytes end
  local text = bytes
  if text:sub(1, #UTF8_BOM) == UTF8_BOM then
    text = text:sub(#UTF8_BOM + 1)
  end

  local bufnr = context and context.bufnr
  if not bufnr or not vim.api.nvim_buf_is_loaded(bufnr) then
    return text
  end
  local fileformat = vim.bo[bufnr].fileformat
  if fileformat == "dos" then
    local remainder = text:gsub("\r\n", "")
    if not remainder:find("[\r\n]") then
      text = text:gsub("\r\n", "\n")
    end
  elseif fileformat == "mac" and not text:find("\n", 1, true) then
    text = text:gsub("\r", "\n")
  end
  return text
end

function M.context(opts)
  opts = opts or {}
  local bufnr = opts.bufnr
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local path = opts.path
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
      path = name
    end
  end
  return {
    bufnr = bufnr,
    path = path and compat.normalize_path(path) or nil,
    filetype = bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype or opts.filetype,
  }
end

function M.text(context)
  if context.bufnr and vim.api.nvim_buf_is_loaded(context.bufnr) then
    return M.buffer_text(context.bufnr), nil, { kind = "buffer", changedtick = vim.api.nvim_buf_get_changedtick(context.bufnr) }
  end
  if not context.path then
    return nil, util.err("SOURCE_UNNAMED", "source has no buffer or path")
  end
  local bytes, err, stat = M.read_file(context.path)
  if not bytes then
    return nil, err
  end
  return bytes, nil, { kind = "file", stat = stat }
end

function M.revision(text, context, extra)
  local revision = {
    hash = compat.sha256(text),
    text = text,
    changedtick = context and context.bufnr and vim.api.nvim_buf_is_valid(context.bufnr)
        and vim.api.nvim_buf_get_changedtick(context.bufnr)
      or nil,
    path = context and context.path or nil,
  }
  for key, value in pairs(extra or {}) do
    revision[key] = value
  end
  return revision
end

function M.disk_snapshot(context)
  if not context or not context.path then return nil end
  local stat = vim.uv.fs_lstat(context.path)
  if not stat then return { exists = false } end
  if stat.type ~= "file" then
    return { exists = true, type = stat.type }
  end
  local bytes, err = M.read_file(context.path)
  if bytes == nil then return nil, err end
  return {
    exists = true,
    type = "file",
    text = bytes,
    hash = compat.sha256(bytes),
    size = #bytes,
  }
end

function M.with_disk(revision, context)
  if not context or not context.path then return revision end
  local snapshot, err = M.disk_snapshot(context)
  if not snapshot then return nil, err end
  revision.disk = snapshot
  if snapshot.exists and snapshot.type == "file" then
    local logical = revision.whole_text or revision.text or ""
    if context.bufnr and vim.api.nvim_buf_is_loaded(context.bufnr) then
      local fileformat = vim.bo[context.bufnr].fileformat
      if fileformat == "dos" then
        logical = logical:gsub("\n", "\r\n")
      elseif fileformat == "mac" then
        logical = logical:gsub("\n", "\r")
      end
      if vim.bo[context.bufnr].bomb then logical = "\239\187\191" .. logical end
    end
    revision.durable_whole_matches_buffer = logical == snapshot.text
  else
    revision.durable_whole_matches_buffer = snapshot.exists == false
  end
  return revision
end

function M.verify_expected_disk(context, revision)
  if not context or not context.path or not revision or not revision.disk then return true end
  local actual, err = M.disk_snapshot(context)
  if not actual then return nil, err end
  local expected = revision.disk
  local equal = expected.exists == actual.exists and expected.type == actual.type
  if equal and expected.exists and expected.type == "file" then equal = expected.text == actual.text end
  if not equal then
    return nil, util.err("SOURCE_CONFLICT", "source file changed on disk after RoomPlan opened", {
      kind = "disk",
      path = context.path,
      expected_hash = expected.hash,
      actual_hash = actual.hash,
      expected_exists = expected.exists,
      actual_exists = actual.exists,
    })
  end
  return true
end

function M.buffer_encoding_supported(bufnr)
  local encoding = (vim.bo[bufnr].fileencoding or ""):lower()
  return encoding == "" or encoding == "utf-8" or encoding == "utf8"
end

function M.set_buffer_text(bufnr, text)
  local had_final_eol = text:sub(-1) == "\n"
  if had_final_eol then
    text = text:sub(1, -2)
  end
  local lines = vim.split(text, "\n", { plain = true })
  if #lines == 0 then
    lines = { "" }
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].endofline = had_final_eol
end

function M.write_buffer(bufnr)
  local ok, err = pcall(vim.api.nvim_buf_call, bufnr, function()
    vim.cmd("write")
  end)
  if not ok then
    return nil, util.err("SOURCE_WRITE_FAILED", tostring(err), { bufnr = bufnr })
  end
  return true
end

return M
