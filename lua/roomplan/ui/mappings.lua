-- Shared mapping resolution for the canvas, workspace, forms, and the
-- contextual action bar. Keeping this in one place ensures displayed keys are
-- the keys that are actually installed.

local M = {}

local function configured(options)
  if type(options) == "table" then return options end
  local ok, config = pcall(require, "roomplan.config")
  if ok and config.get then return config.get().keymaps or {} end
  return { enabled = true, mappings = {} }
end

function M.resolve(default_lhs, semantic_name, options)
  local keymaps = configured(options)
  if keymaps.enabled == false then return nil end
  local overrides = keymaps.mappings or {}
  local lhs
  if semantic_name ~= nil then lhs = overrides[semantic_name] end
  if lhs == nil then lhs = overrides[default_lhs] end
  if lhs == nil then lhs = default_lhs end
  if lhs == false or lhs == "" then return nil end
  return lhs
end

function M.set(bufnr, default_lhs, rhs, desc, semantic_name, options)
  local lhs = M.resolve(default_lhs, semantic_name, options)
  if not lhs then return nil end
  vim.keymap.set("n", lhs, rhs, {
    buffer = bufnr,
    silent = true,
    nowait = true,
    desc = desc,
  })
  return lhs
end

return M
