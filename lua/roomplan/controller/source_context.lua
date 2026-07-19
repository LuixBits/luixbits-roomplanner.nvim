-- Source identity, ownership, and path helpers shared by opening and saving.
local compat = require("roomplan.compat")
local state = require("roomplan.state")
local storage = require("roomplan.storage")
local source_io = require("roomplan.storage.source")
local util = require("roomplan.util")

local M = {}

function M.explicit_path(opts)
  local path = opts and (opts.path or opts.args)
  if type(path) ~= "string" or path:match("^%s*$") then return nil end
  return compat.normalize_path(vim.fn.expand(path))
end

function M.explicit_requested_path(opts)
  local path = opts and (opts.path or opts.args)
  if type(path) ~= "string" or path:match("^%s*$") then return nil end
  -- Keep the final path component unresolved for safety checks. Resolving it
  -- first would make a user-supplied symlink look like a regular target.
  return vim.fn.fnamemodify(vim.fn.expand(path), ":p")
end

function M.context_for(opts, purpose)
  opts = opts or {}
  local path = M.explicit_path(opts)
  local bufnr = opts.bufnr
  if bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  if path then
    local existing = vim.fn.bufnr(path)
    if existing ~= -1 and vim.api.nvim_buf_is_valid(existing) then
      bufnr = existing
      vim.fn.bufload(bufnr)
    elseif
      purpose == "open"
      or path:lower():sub(-5) == ".norg"
      or (purpose == "init" and vim.uv.fs_lstat(path) ~= nil)
    then
      bufnr = storage.ensure_buffer(path)
    else
      bufnr = nil
    end
  elseif not bufnr then
    bufnr = vim.api.nvim_get_current_buf()
  end
  return source_io.context({ bufnr = bufnr, path = path, filetype = opts.filetype })
end

function M.find_existing(context)
  local key = state.source_key(context)
  local id = key and state.source_keys[key]
  return id and state.get(id) or nil
end

function M.reusable_existing(context, existing)
  if not existing or not context.bufnr or not existing.source.bufnr or context.bufnr == existing.source.bufnr then
    return existing
  end
  if not vim.api.nvim_buf_is_loaded(context.bufnr) or not vim.api.nvim_buf_is_loaded(existing.source.bufnr) then
    return existing
  end
  local alias_text = source_io.buffer_text(context.bufnr)
  local authoritative_text = source_io.buffer_text(existing.source.bufnr)
  if vim.bo[context.bufnr].modified or alias_text ~= authoritative_text then
    return nil,
      util.err("DUPLICATE_BUFFER_CONFLICT", "another loaded buffer for this RoomPlan path is modified or divergent", {
        authoritative_bufnr = existing.source.bufnr,
        alias_bufnr = context.bufnr,
      })
  end
  return existing
end

function M.reattach_existing(controller, context, existing)
  if not context.bufnr or (existing.source.bufnr and vim.api.nvim_buf_is_valid(existing.source.bufnr)) then
    return true
  end
  local replacement = vim.tbl_extend("force", existing.source, {
    bufnr = context.bufnr,
    path = context.path or existing.source.path,
    filetype = context.filetype,
  })
  local updated, err = state.update_source(existing, replacement)
  if not updated then return nil, err end
  existing:attach_source_autocmds()
  controller.check_source(existing)
  return true
end

function M.session_source(context, adapter, revision, locator)
  return {
    adapter = adapter.name,
    path = context.path,
    bufnr = context.bufnr,
    filetype = context.filetype,
    revision = revision,
    locator = locator,
  }
end

return M
