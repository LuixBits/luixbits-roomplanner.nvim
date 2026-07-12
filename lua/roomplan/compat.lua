local M = {}

function M.version_at_least(major, minor, patch)
  local current = vim.version()
  if current.major ~= major then
    return current.major > major
  end
  if current.minor ~= minor then
    return current.minor > minor
  end
  return current.patch >= (patch or 0)
end

function M.supported()
  return M.version_at_least(0, 10, 0)
end

function M.notify(message, level, opts)
  vim.schedule(function()
    if not level then
      local ok, configured = pcall(function() return require("roomplan.config").get().ui.notify_level end)
      local levels = {
        debug = vim.log.levels.DEBUG,
        info = vim.log.levels.INFO,
        warn = vim.log.levels.WARN,
        error = vim.log.levels.ERROR,
      }
      level = ok and levels[configured] or vim.log.levels.INFO
    end
    vim.notify(message, level, vim.tbl_extend("force", { title = "RoomPlan" }, opts or {}))
  end)
end

function M.set_option(name, value, scope)
  vim.api.nvim_set_option_value(name, value, scope or {})
end

function M.normalize_path(path)
  if not path or path == "" then
    return nil
  end
  local absolute = vim.fn.fnamemodify(path, ":p")
  local real = vim.uv.fs_realpath(absolute)
  if real then
    return real
  end
  local parent = vim.fn.fnamemodify(absolute, ":h")
  local base = vim.fn.fnamemodify(absolute, ":t")
  local real_parent = vim.uv.fs_realpath(parent)
  if real_parent then
    return real_parent:gsub("[\\/]$", "") .. "/" .. base
  end
  return absolute
end

function M.sha256(text)
  return vim.fn.sha256(text)
end

function M.buf_text(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = table.concat(lines, "\n")
  if vim.bo[bufnr].endofline then
    text = text .. "\n"
  end
  return text
end

function M.health()
  return vim.health
end

return M
