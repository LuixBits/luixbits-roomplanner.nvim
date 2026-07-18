-- Schema-v4 outlet placement plus unchanged schema-v3 entities.

local outlet_types = require("roomplan.outlet_types")
local common = require("roomplan.schema.common")
local footprint = require("roomplan.schema.v2.footprint")
local v3 = require("roomplan.schema.v3.entities")

local M = {
  normalize_room = v3.normalize_room,
  normalize_door = v3.normalize_door,
  normalize_furniture = v3.normalize_furniture,
  normalize_template = v3.normalize_template,
  validate_door_parts = v3.validate_door_parts,
  validate_window_parts = v3.validate_window_parts,
}

function M.normalize_window(context, source, path)
  local result = v3.normalize_window(context, source, path)
  if not result then return nil end
  local sill_present = result.sill_height_mm ~= nil
  local head_present = result.head_height_mm ~= nil
  if sill_present ~= head_present then
    common.add_error(context, "SCHEMA_WINDOW_HEIGHT_PAIR", path,
      "sill_height_mm and head_height_mm must be provided together")
  end
  if sill_present and head_present then
    result.sill_height_mm = common.integer(
      context, result.sill_height_mm, path .. ".sill_height_mm", 0,
      common.limits.local_mm_max, common.limits.local_mm_max
    )
    result.head_height_mm = common.dimension(context, result.head_height_mm, path .. ".head_height_mm")
    if result.sill_height_mm and result.head_height_mm
      and result.head_height_mm <= result.sill_height_mm
    then
      common.add_error(context, "SCHEMA_WINDOW_HEIGHT_ORDER", path .. ".head_height_mm",
        "must exceed sill_height_mm", result.head_height_mm)
    end
  end
  return result
end

local SIDES = { north = true, east = true, south = true, west = true }
local PLACEMENTS = { wall = true, floor = true }
local OUTLET_TYPES = {}
for _, value in ipairs(outlet_types.values) do OUTLET_TYPES[value] = true end

local function reject_fields(context, result, path, fields, placement)
  for _, field in ipairs(fields) do
    if result[field] ~= nil then
      common.add_error(context, "SCHEMA_OUTLET_PLACEMENT_FIELD", path .. "." .. field,
        field .. " is not valid for a " .. placement .. " outlet", result[field])
      result[field] = nil
    end
  end
end

function M.normalize_outlet(context, source, path)
  local result = common.object(context, source, path)
  if not result then return nil end
  result.id = common.normalize_id(
    context, common.required(context, result, "id", path), path .. ".id", "outlet"
  )
  result.room_id = common.normalize_id(
    context, common.required(context, result, "room_id", path), path .. ".room_id", "room"
  )
  result.placement = common.enum(
    context, common.required(context, result, "placement", path), path .. ".placement", PLACEMENTS
  )
  result.outlet_type = common.enum(
    context, common.required(context, result, "outlet_type", path), path .. ".outlet_type", OUTLET_TYPES
  )
  result.slots = common.integer(
    context, common.required(context, result, "slots", path), path .. ".slots", 1, 32,
    common.limits.local_mm_max
  )

  if result.placement == "wall" then
    reject_fields(context, result, path, { "position_mm" }, "wall")
    result.part_id = footprint.normalize_part_id(
      context, common.required(context, result, "part_id", path), path .. ".part_id"
    )
    result.side = common.enum(
      context, common.required(context, result, "side", path), path .. ".side", SIDES
    )
    result.offset_mm = common.integer(
      context, common.required(context, result, "offset_mm", path), path .. ".offset_mm",
      0, common.limits.local_mm_max, common.limits.local_mm_max
    )
  elseif result.placement == "floor" then
    reject_fields(context, result, path, { "part_id", "side", "offset_mm" }, "floor")
    result.position_mm = common.tuple(
      context, common.required(context, result, "position_mm", path), path .. ".position_mm", 2,
      function(value, item_path) return common.coordinate(context, value, item_path) end
    )
  end
  return result
end

function M.validate_outlet_parts(context, outlets, room_footprints)
  for index, value in ipairs(outlets or {}) do
    if value.placement == "wall" then
      local owner = room_footprints[value.room_id]
      if owner and value.part_id and not owner.part_ids[value.part_id] then
        common.add_error(context, "SCHEMA_OUTLET_PART", "$.outlets[" .. index .. "].part_id",
          "referenced footprint part does not exist in the owner room", value.part_id)
      end
    end
  end
end

return M
