-- Schema-v3 window/outlet normalization plus the unchanged v2 entities.

local json = require("roomplan.codec.json")
local outlet_types = require("roomplan.outlet_types")
local common = require("roomplan.schema.common")
local footprint = require("roomplan.schema.v2.footprint")
local v2 = require("roomplan.schema.v2.entities")

local M = {
  normalize_room = v2.normalize_room,
  normalize_door = v2.normalize_door,
  normalize_furniture = v2.normalize_furniture,
  normalize_template = v2.normalize_template,
  validate_door_parts = v2.validate_door_parts,
}

local SIDES = { north = true, east = true, south = true, west = true }
local OUTLET_TYPES = {}
for _, value in ipairs(outlet_types.values) do
  OUTLET_TYPES[value] = true
end

local function normalize_wall_owner(context, result, path)
  result.room_id =
    common.normalize_id(context, common.required(context, result, "room_id", path), path .. ".room_id", "room")
  result.part_id =
    footprint.normalize_part_id(context, common.required(context, result, "part_id", path), path .. ".part_id")
  result.side = common.enum(context, common.required(context, result, "side", path), path .. ".side", SIDES)
  result.offset_mm = common.integer(
    context,
    common.required(context, result, "offset_mm", path),
    path .. ".offset_mm",
    0,
    common.limits.local_mm_max,
    common.limits.local_mm_max
  )
end

function M.normalize_window(context, source, path)
  local result = common.object(context, source, path)
  if not result then return nil end
  result.id = common.normalize_id(context, common.required(context, result, "id", path), path .. ".id", "window")
  normalize_wall_owner(context, result, path)
  local connected = common.required(context, result, "connects_to_room_id", path)
  if json.is_null(connected) then
    result.connects_to_room_id = json.null
  else
    result.connects_to_room_id = common.normalize_id(context, connected, path .. ".connects_to_room_id", "room")
  end
  result.width_mm = common.dimension(context, common.required(context, result, "width_mm", path), path .. ".width_mm")
  return result
end

function M.normalize_outlet(context, source, path)
  local result = common.object(context, source, path)
  if not result then return nil end
  result.id = common.normalize_id(context, common.required(context, result, "id", path), path .. ".id", "outlet")
  normalize_wall_owner(context, result, path)
  result.outlet_type =
    common.enum(context, common.required(context, result, "outlet_type", path), path .. ".outlet_type", OUTLET_TYPES)
  result.slots = common.integer(
    context,
    common.required(context, result, "slots", path),
    path .. ".slots",
    1,
    32,
    common.limits.local_mm_max
  )
  return result
end

local function validate_wall_parts(context, values, room_footprints, collection, code)
  for index, value in ipairs(values or {}) do
    local owner = room_footprints[value.room_id]
    if owner and value.part_id and not owner.part_ids[value.part_id] then
      common.add_error(
        context,
        code,
        "$." .. collection .. "[" .. index .. "].part_id",
        "referenced footprint part does not exist in the owner room",
        value.part_id
      )
    end
  end
end

function M.validate_window_parts(context, windows, room_footprints)
  validate_wall_parts(context, windows, room_footprints, "windows", "SCHEMA_WINDOW_PART")
end

function M.validate_outlet_parts(context, outlets, room_footprints)
  validate_wall_parts(context, outlets, room_footprints, "outlets", "SCHEMA_OUTLET_PART")
end

return M
