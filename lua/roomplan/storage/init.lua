local compat = require("roomplan.compat")
local source = require("roomplan.storage.source")
local util = require("roomplan.util")

local M = {}

local adapters = {
  json = function() return require("roomplan.storage.json") end,
  norg = function() return require("roomplan.storage.norg") end,
}

function M.detect(context)
  context = source.context(context)
  local path = context.path and context.path:lower() or ""
  local adapter
  if path:sub(-#".roomplan.json") == ".roomplan.json" then
    adapter = "json"
  elseif path:sub(-#".norg") == ".norg" then
    adapter = "norg"
  elseif context.filetype == "norg" then
    adapter = "norg"
  end
  if not adapter then
    return nil, util.err("STORAGE_UNSUPPORTED", "source must end in .roomplan.json or .norg (or be a norg buffer)", {
      path = context.path,
      filetype = context.filetype,
    })
  end
  context.adapter = adapter
  return adapters[adapter](), context
end

function M.adapter(name)
  return adapters[name] and adapters[name]() or nil
end

function M.ensure_buffer(path)
  local normalized = compat.normalize_path(path)
  local bufnr = vim.fn.bufnr(normalized)
  if bufnr == -1 then
    bufnr = vim.fn.bufadd(normalized)
  end
  vim.fn.bufload(bufnr)
  return bufnr
end

return M
