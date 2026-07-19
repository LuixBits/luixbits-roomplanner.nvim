-- Version-aware persisted entity constructors. They keep schema-specific
-- geometry in one place while the public model facade stays small.

local json = require("roomplan.codec.json")
local outlet_types = require("roomplan.outlet_types")

local M = {}

local function copy_fields(fields)
  local result = json.object()
  for key, value in pairs(type(fields) == "table" and fields or {}) do
    result[key] = json.deep_copy(value)
  end
  return result
end

local function tuple(values, defaults, length)
  values = values or defaults or {}
  local result = json.array()
  local last = length or #values
  for index = 1, last do
    result[index] = values[index]
  end
  return result
end

function M.rectangle_footprint(size_mm)
  size_mm = size_mm or {}
  return json.object({
    kind = "rect_union",
    parts = json.array({
      json.object({
        id = "part-main",
        origin_mm = json.array({ 0, 0 }),
        size_mm = tuple(size_mm, nil, 2),
      }),
    }),
  })
end

function M.room(fields, version)
  fields = fields or {}
  local result = copy_fields(fields)
  result.id = fields.id
  result.name = fields.name or "Room"
  result.origin_mm = tuple(fields.origin_mm, { 0, 0 })
  if version >= 2 then
    result.footprint = fields.footprint and json.deep_copy(fields.footprint) or M.rectangle_footprint(fields.size_mm)
    result.size_mm = nil
  else
    result.size_mm = tuple(fields.size_mm)
  end
  return result
end

function M.door(fields, version)
  fields = fields or {}
  local result = copy_fields(fields)
  result.id = fields.id
  result.kind = fields.kind or "hinged"
  result.room_id = fields.room_id
  result.connects_to_room_id = fields.connects_to_room_id == nil and json.null or fields.connects_to_room_id
  if version >= 2 then result.part_id = fields.part_id or "part-main" end
  result.side = fields.side
  result.offset_mm = fields.offset_mm or 0
  result.width_mm = fields.width_mm
  result.hinge = fields.hinge or "start"
  local has_connection = fields.connects_to_room_id ~= nil and not json.is_null(fields.connects_to_room_id)
  result.opens_into = fields.opens_into or (has_connection and "connected" or "owner")
  result.open_angle_deg = fields.open_angle_deg or 90
  return result
end

function M.furniture(fields, version)
  fields = fields or {}
  local result = copy_fields(fields)
  result.id = fields.id
  result.room_id = fields.room_id
  result.template_id = fields.template_id or "builtin:custom-rectangle"
  result.name = fields.name or "Furniture"
  result.category = fields.category or "custom"
  result.rotation_deg = fields.rotation_deg or 0
  if version >= 2 then
    local size = fields.size_mm or {}
    result.position_mm = tuple(fields.position_mm, { 0, 0 })
    result.anchor2_mm = tuple(fields.anchor2_mm, { size[1], size[2] })
    result.footprint = fields.footprint and json.deep_copy(fields.footprint) or M.rectangle_footprint(size)
    result.height_mm = fields.height_mm or size[3]
    result.center_mm = nil
    result.size_mm = nil
  else
    result.center_mm = tuple(fields.center_mm, { 0, 0 })
    result.size_mm = tuple(fields.size_mm)
  end
  return result
end

function M.template(fields, version)
  fields = fields or {}
  local result = copy_fields(fields)
  result.id = fields.id
  result.name = fields.name or "Custom furniture"
  result.category = fields.category or "custom"
  if version >= 2 then
    local size = fields.default_size_mm or {}
    result.default_footprint = fields.default_footprint and json.deep_copy(fields.default_footprint)
      or M.rectangle_footprint(size)
    result.default_anchor2_mm = tuple(fields.default_anchor2_mm, { size[1], size[2] })
    result.default_height_mm = fields.default_height_mm or size[3]
    result.shape = nil
    result.default_size_mm = nil
  else
    result.shape = fields.shape or "rectangle"
    result.default_size_mm = tuple(fields.default_size_mm)
  end
  return result
end

function M.window(fields)
  fields = fields or {}
  local result = copy_fields(fields)
  result.id = fields.id
  result.room_id = fields.room_id
  result.connects_to_room_id = fields.connects_to_room_id == nil and json.null or fields.connects_to_room_id
  result.part_id = fields.part_id or "part-main"
  result.side = fields.side
  result.offset_mm = fields.offset_mm or 0
  result.width_mm = fields.width_mm
  return result
end

function M.outlet(fields, version)
  fields = fields or {}
  local result = copy_fields(fields)
  result.id = fields.id
  result.room_id = fields.room_id
  if (version or 3) >= 4 then
    result.placement = fields.placement or "wall"
    if result.placement == "floor" then
      result.position_mm = tuple(fields.position_mm, { 0, 0 }, 2)
      result.part_id, result.side, result.offset_mm = nil, nil, nil
    else
      result.part_id = fields.part_id or "part-main"
      result.side = fields.side
      result.offset_mm = fields.offset_mm or 0
      result.position_mm = nil
    end
  else
    result.part_id = fields.part_id or "part-main"
    result.side = fields.side
    result.offset_mm = fields.offset_mm or 0
    result.placement = nil
    result.position_mm = nil
  end
  result.outlet_type = fields.outlet_type or outlet_types.default
  result.slots = fields.slots or 2
  return result
end

return M
