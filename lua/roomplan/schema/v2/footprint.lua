-- Schema-v2 footprint, part, and doubled-anchor normalization.

local geometry = require("roomplan.geometry.footprint")
local common = require("roomplan.schema.common")

local M = {}

local MAX_ANCHOR2 = 2 * (common.limits.coordinate_abs_exclusive - 1)

function M.normalize_part_id(context, value, path)
  local id = common.text(context, value, path, { nonempty = true, max_bytes = 128 })
  if id ~= nil and id:match("^part%-%w[%w._-]*$") == nil then
    common.add_error(
      context,
      "SCHEMA_PART_ID",
      path,
      "must match part-<name> using letters, digits, '.', '_', or '-'",
      id
    )
    return nil
  end
  return id
end

local function doubled_coordinate(context, value, path)
  return common.integer(context, value, path, -MAX_ANCHOR2, MAX_ANCHOR2, MAX_ANCHOR2)
end

local function normalize_part(context, source, path)
  local result = common.object(context, source, path)
  if not result then
    return nil
  end
  result.id = M.normalize_part_id(context, common.required(context, result, "id", path), path .. ".id")
  result.origin_mm = common.tuple(
    context,
    common.required(context, result, "origin_mm", path),
    path .. ".origin_mm",
    2,
    function(value, item_path)
      return common.coordinate(context, value, item_path)
    end
  )
  result.size_mm = common.tuple(
    context,
    common.required(context, result, "size_mm", path),
    path .. ".size_mm",
    2,
    function(value, item_path)
      return common.dimension(context, value, item_path)
    end
  )
  return result
end

function M.normalize(context, source, path)
  local initial_error_count = #context.errors
  local result = common.object(context, source, path)
  if not result then
    return nil
  end
  local kind = common.required(context, result, "kind", path)
  if kind ~= geometry.KIND then
    common.add_error(
      context,
      "SCHEMA_FOOTPRINT_KIND",
      path .. ".kind",
      "must be exactly '" .. geometry.KIND .. "'",
      kind
    )
    kind = nil
  end
  result.kind = kind
  result.parts = common.normalize_collection(
    context,
    common.required(context, result, "parts", path),
    path .. ".parts",
    normalize_part
  )

  if #context.errors > initial_error_count or not result.parts then
    return result
  end

  if #result.parts > geometry.DEFAULT_MAX_PARTS then
    common.add_error(
      context,
      "SCHEMA_FOOTPRINT_TOPOLOGY",
      path,
      "footprint contains more than " .. geometry.DEFAULT_MAX_PARTS .. " parts",
      #result.parts
    )
    return result
  end

  local runtime, topology_error = geometry.from_persisted(result)
  if not runtime then
    common.add_error(
      context,
      "SCHEMA_FOOTPRINT_TOPOLOGY",
      path,
      topology_error.message or "footprint violates the compound topology contract",
      topology_error
    )
    return result
  end
  return result, runtime
end

function M.normalize_anchor(context, source, path)
  return common.tuple(context, source, path, 2, function(value, item_path)
    return doubled_coordinate(context, value, item_path)
  end)
end

function M.validate_anchor(context, anchor, runtime, path)
  if not anchor or not runtime or type(anchor[1]) ~= "number" or type(anchor[2]) ~= "number" then
    return
  end
  local contained, containment_error = geometry.contains_point2(runtime, anchor[1], anchor[2])
  if contained == false then
    common.add_error(
      context,
      "SCHEMA_ANCHOR_OUTSIDE",
      path,
      "anchor must lie on or inside its footprint",
      anchor
    )
  elseif contained == nil then
    common.add_error(
      context,
      "SCHEMA_ANCHOR",
      path,
      containment_error.message or "anchor could not be validated",
      containment_error
    )
  end
end

return M
