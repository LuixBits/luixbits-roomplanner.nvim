local atomic = require("roomplan.storage.atomic")
local codec = require("roomplan.codec.json")
local schema = require("roomplan.schema")
local source = require("roomplan.storage.source")
local util = require("roomplan.util")

local M = { name = "json" }

local function unchanged_by_schema(info) return not (info and (info.normalized or info.migrated)) end

function M.load(context)
  local text, err, origin = source.text(context)
  if not text then return nil, err end
  local logical_text = origin and origin.kind == "file" and source.logical_text(text, context) or text
  local model, info = schema.decode(logical_text)
  if not model then return nil, info end
  local revision, disk_err = source.with_disk(source.revision(logical_text, context), context)
  if not revision then return nil, disk_err end
  if revision.disk and revision.disk.exists and revision.disk.type == "file" then
    local disk_model, disk_info = schema.decode(source.logical_text(revision.disk.text, context))
    revision.durable_model_matches = disk_model ~= nil
      and unchanged_by_schema(info)
      and unchanged_by_schema(disk_info)
      and codec.deep_equal(disk_model, model)
  else
    revision.durable_model_matches = false
  end
  return model, revision, { kind = "document" }, info
end

function M.serialize(model, options)
  options = options or {}
  options.final_newline = options.final_newline ~= false
  return schema.encode(model, options)
end

function M.prepare_save(_, model, options)
  local text, info = M.serialize(model, options)
  if not text then return nil, info end
  return { text = text, info = info }
end

function M.commit(context, patch, expected_revision, opts)
  opts = opts or {}
  local disk_ok, disk_err = source.verify_expected_disk(context, expected_revision)
  if not disk_ok then return nil, disk_err end
  if context.bufnr and vim.api.nvim_buf_is_loaded(context.bufnr) then
    local current = source.buffer_text(context.bufnr)
    if expected_revision and current ~= expected_revision.text and current ~= patch.text then
      return nil,
        util.err("SOURCE_CONFLICT", "standalone source buffer changed after RoomPlan opened", {
          expected_hash = expected_revision.hash,
          actual_hash = vim.fn.sha256(current),
        })
    end
    if current ~= patch.text then source.set_buffer_text(context.bufnr, patch.text) end
    if opts.write ~= false then
      local written, write_err = source.write_buffer(context.bufnr)
      if not written then return nil, write_err, { staged = true, text = patch.text } end
    end
    local actual = source.buffer_text(context.bufnr)
    local parsed, parse_err = schema.decode(actual)
    if not parsed then
      return nil, util.err("SOURCE_POST_WRITE_INVALID", "source is invalid after write hooks", { cause = parse_err })
    end
    local revision, revision_err = source.with_disk(source.revision(actual, context), context)
    if not revision then return nil, revision_err end
    if revision.disk and revision.disk.exists then
      local durable, durable_err = schema.decode(source.logical_text(revision.disk.text, context))
      if not durable then
        return nil,
          util.err(
            "SOURCE_POST_WRITE_INVALID",
            "durable standalone file is invalid after write",
            { cause = durable_err }
          )
      end
      if not codec.deep_equal(durable, parsed) then
        return nil,
          util.err("SOURCE_POST_WRITE_DIVERGED", "source buffer and durable standalone file contain different models")
      end
    end
    return revision, parsed
  end

  if not context.path then return nil, util.err("SOURCE_UNNAMED", "standalone save requires a path") end
  if vim.uv.fs_lstat(context.path) then
    return nil, util.err("ATOMIC_TARGET_EXISTS", "detached writer only creates new paths")
  end
  local ok, atomic_err = atomic.write_new(context.path, patch.text)
  if not ok then return nil, atomic_err end
  local revision, revision_err = source.with_disk(source.revision(patch.text, context), context)
  if not revision then return nil, revision_err end
  return revision
end

function M.initialize(context, model)
  local patch, err = M.prepare_save(nil, model)
  if not patch then return nil, err end
  return M.commit(context, patch, nil, { write = true })
end

return M
