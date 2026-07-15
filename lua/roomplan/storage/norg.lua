local codec = require("roomplan.codec.json")
local scan = require("roomplan.storage.norg_scan")
local schema = require("roomplan.schema")
local source = require("roomplan.storage.source")
local util = require("roomplan.util")

local M = { name = "norg" }

local function unchanged_by_schema(info)
  return not (info and (info.normalized or info.migrated))
end

local function decode_document(text)
  local document, err = codec.decode(text)
  if document == nil then
    error((err and err.message) or "malformed JSON")
  end
  return document
end

local function discover(text)
  return scan.discover(text, decode_document)
end

function M.load(context)
  local text, err, origin = source.text(context)
  if not text then
    return nil, err
  end
  local logical_text = origin and origin.kind == "file" and source.logical_text(text, context) or text
  local found, discover_err = discover(logical_text)
  if not found then
    return nil, discover_err
  end
  if found.kind == "missing" then
    return nil, util.err("NORG_PLAN_MISSING", "Norg source has no RoomPlan block", {
      missing = true,
      malformed_json_count = #(found.malformed_json or {}),
      text = logical_text,
    })
  end
  local model, info = schema.load(found.block.document)
  if not model then
    return nil, info
  end
  local revision, disk_err = source.with_disk(source.revision(found.block.content, context, {
    payload = found.block.content,
    whole_text = logical_text,
    whole_hash = vim.fn.sha256(logical_text),
  }), context)
  if not revision then return nil, disk_err end
  if revision.disk and revision.disk.exists and revision.disk.type == "file" then
    local disk_found = discover(source.logical_text(revision.disk.text, context))
    local disk_model, disk_info
    if disk_found and disk_found.kind == "found" then
      disk_model, disk_info = schema.load(disk_found.block.document)
    end
    revision.durable_model_matches = disk_model ~= nil
      and unchanged_by_schema(info)
      and unchanged_by_schema(disk_info)
      and codec.deep_equal(disk_model, model)
  else
    revision.durable_model_matches = false
  end
  return model, revision, found.block, info
end

function M.serialize(model)
  return schema.encode(model, { final_newline = false })
end

function M.prepare_save(session, model)
  local payload, info = M.serialize(model)
  if not payload then
    return nil, info
  end
  return { payload = payload, info = info, locator = session and session.source and session.source.locator }
end

local function indent_payload(payload, indent)
  if not indent or indent == "" then
    return payload
  end
  local lines = vim.split(payload, "\n", { plain = true })
  for index, line in ipairs(lines) do
    lines[index] = indent .. line
  end
  return table.concat(lines, "\n")
end

function M.commit(context, patch, expected_revision, opts)
  opts = opts or {}
  local disk_ok, disk_err = source.verify_expected_disk(context, expected_revision)
  if not disk_ok then return nil, disk_err end
  if not context.bufnr or not vim.api.nvim_buf_is_loaded(context.bufnr) then
    return nil, util.err("NORG_BUFFER_REQUIRED", "Norg sources must be saved through a loaded buffer")
  end
  local current = source.buffer_text(context.bufnr)
  local found, discover_err = discover(current)
  if not found then
    return nil, discover_err
  end
  if found.kind ~= "found" then
    return nil, util.err("NORG_PLAN_MISSING", "RoomPlan block disappeared before save")
  end
  if expected_revision and found.block.content ~= expected_revision.payload and found.block.content ~= patch.payload then
    return nil, util.err("SOURCE_CONFLICT", "RoomPlan Norg payload changed after the canvas opened", {
      expected_hash = expected_revision.hash,
      actual_hash = vim.fn.sha256(found.block.content),
    })
  end
  local payload = indent_payload(patch.payload, found.block.indent)
  local replaced, replace_err = scan.replace(current, found.block, payload)
  if not replaced then
    return nil, replace_err
  end
  if replaced ~= current then
    source.set_buffer_text(context.bufnr, replaced)
  end
  if opts.write ~= false then
    local written, write_err = source.write_buffer(context.bufnr)
    if not written then
      return nil, write_err, { staged = true, payload = patch.payload }
    end
  end
  local actual = source.buffer_text(context.bufnr)
  local rediscovered, after_err = discover(actual)
  if not rediscovered or rediscovered.kind ~= "found" then
    return nil, util.err("SOURCE_POST_WRITE_INVALID", "RoomPlan block is invalid after write hooks", { cause = after_err })
  end
  local model, model_err = schema.load(rediscovered.block.document)
  if not model then
    return nil, util.err("SOURCE_POST_WRITE_INVALID", "RoomPlan model is invalid after write hooks", { cause = model_err })
  end
  local revision, revision_err = source.with_disk(source.revision(rediscovered.block.content, context, {
    payload = rediscovered.block.content,
    whole_text = actual,
    whole_hash = vim.fn.sha256(actual),
  }), context)
  if not revision then return nil, revision_err end
  if revision.disk and revision.disk.exists then
    local durable_found, durable_err = discover(source.logical_text(revision.disk.text, context))
    if not durable_found or durable_found.kind ~= "found" then
      return nil, util.err("SOURCE_POST_WRITE_INVALID", "durable Norg RoomPlan block is invalid after write", { cause = durable_err })
    end
    local durable_model, durable_model_err = schema.load(durable_found.block.document)
    if not durable_model then
      return nil, util.err("SOURCE_POST_WRITE_INVALID", "durable Norg RoomPlan model is invalid after write", { cause = durable_model_err })
    end
    if not codec.deep_equal(durable_model, model) then
      return nil, util.err("SOURCE_POST_WRITE_DIVERGED", "source buffer and durable Norg file contain different RoomPlan models")
    end
  end
  return revision, model, rediscovered.block
end

function M.initialize(context, model, opts)
  opts = opts or {}
  if not context.bufnr or not vim.api.nvim_buf_is_loaded(context.bufnr) then
    return nil, util.err("NORG_BUFFER_REQUIRED", "Norg initialization requires a loaded buffer")
  end
  local current = source.buffer_text(context.bufnr)
  local result, discover_err = discover(current)
  if not result then
    return nil, discover_err
  end
  if result.kind == "found" then
    return nil, util.err("NORG_PLAN_EXISTS", "Norg source already contains a RoomPlan block")
  end
  if #(result.malformed_json or {}) > 0 and not opts.allow_other_malformed_json then
    return nil, util.err("NORG_MALFORMED_JSON_AMBIGUOUS", "Norg note contains malformed JSON blocks; confirmation is required")
  end
  local payload, encode_err = M.serialize(model)
  if not payload then
    return nil, encode_err
  end
  local initialized = scan.initialize(current, payload, opts.heading_line)
  source.set_buffer_text(context.bufnr, initialized)
  local found = assert(discover(initialized))
  local revision, disk_err = source.with_disk(source.revision(found.block.content, context, {
    payload = found.block.content,
    whole_text = initialized,
    whole_hash = vim.fn.sha256(initialized),
    undurable = true,
  }), context)
  if not revision then return nil, disk_err end
  return revision, found.block
end

function M.headings(context)
  local text, err, origin = source.text(context)
  if not text then
    return nil, err
  end
  if origin and origin.kind == "file" then text = source.logical_text(text, context) end
  return scan.floor_plan_headings(text)
end

return M
