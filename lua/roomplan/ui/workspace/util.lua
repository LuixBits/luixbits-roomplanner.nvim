local M = {}

M.pane_titles = {
  objects = "Navigator · Objects",
  issues = "Navigator · Issues",
  properties = "Details",
}

function M.valid_buffer(bufnr)
  return type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr)
end

function M.valid_window(winid)
  return type(winid) == "number" and vim.api.nvim_win_is_valid(winid)
end

function M.copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = M.copy(item) end
  return result
end

function M.merge(target, source)
  target = M.copy(target or {})
  for key, value in pairs(source or {}) do target[key] = M.copy(value) end
  return target
end

function M.configured_options(opts)
  local from_config = {}
  local ok, config = pcall(require, "roomplan.config")
  if ok and config.get then
    local ui = config.get().ui or {}
    from_config = ui.workspace or {}
  end
  return M.merge(from_config, opts)
end

return M
