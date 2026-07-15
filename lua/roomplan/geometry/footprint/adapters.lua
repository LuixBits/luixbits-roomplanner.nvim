-- Persisted room and furniture adapters for the shared footprint model.

local core = require("roomplan.geometry.footprint.core")
local transforms = require("roomplan.geometry.footprint.transforms")
local internal = core._internal

local M = {}

local function doubled(value, operation)
  local result, err = internal.checked_double(value, operation)
  if result == nil then return nil, err end
  return internal.coordinate2(result, operation)
end

---Convert the persisted schema-v2 footprint representation into the exact
---runtime doubled-millimetre representation. This is deliberately owned by
---the geometry layer so every consumer interprets compound data identically.
function M.from_persisted(value)
  if type(value) ~= "table" or value.kind ~= core.KIND or type(value.parts) ~= "table" then
    return internal.failure("FOOTPRINT_PERSISTED", "persisted footprint must be a rect_union with parts")
  end
  local parts = {}
  for index = 1, #value.parts do
    local part = value.parts[index]
    if type(part) ~= "table" or type(part.id) ~= "string"
      or type(part.origin_mm) ~= "table" or type(part.size_mm) ~= "table"
    then
      return internal.failure("FOOTPRINT_PERSISTED", "persisted footprint parts require id, origin_mm, and size_mm", {
        index = index,
      })
    end
    local left2, left_error = doubled(part.origin_mm[1], "persisted part left coordinate")
    if left2 == nil then return nil, left_error end
    local bottom2, bottom_error = doubled(part.origin_mm[2], "persisted part bottom coordinate")
    if bottom2 == nil then return nil, bottom_error end
    local width2, width_error = doubled(part.size_mm[1], "persisted part width")
    if width2 == nil then return nil, width_error end
    local depth2, depth_error = doubled(part.size_mm[2], "persisted part depth")
    if depth2 == nil then return nil, depth_error end
    local right2, right_error = internal.checked_add(left2, width2, "persisted part right coordinate")
    if right2 == nil then return nil, right_error end
    local _, right_range_error = internal.coordinate2(right2, "persisted part right coordinate")
    if right_range_error then return nil, right_range_error end
    local top2, top_error = internal.checked_add(bottom2, depth2, "persisted part top coordinate")
    if top2 == nil then return nil, top_error end
    local _, top_range_error = internal.coordinate2(top2, "persisted part top coordinate")
    if top_range_error then return nil, top_range_error end
    parts[index] = {
      id = part.id,
      left2 = left2,
      bottom2 = bottom2,
      right2 = right2,
      top2 = top2,
    }
  end
  return core.compound(parts, { require_ids = true })
end

---Adapt a v1 room into the future compound convention: one stable local part
---starting at [0, 0], plus a frame that places it at the v1 southwest origin.
function M.local_from_room(room, part_id)
  if type(room) ~= "table" or type(room.origin_mm) ~= "table" then
    return internal.failure("FOOTPRINT_ROOM", "room must provide origin_mm")
  end
  local origin_x, origin_y = room.origin_mm[1], room.origin_mm[2]
  if not internal.finite_integer(origin_x) or not internal.finite_integer(origin_y) then
    return internal.failure("FOOTPRINT_ROOM", "room origin must use integer millimetres")
  end
  local origin_x2, origin_x_error = internal.checked_double(origin_x, "room frame X origin")
  if origin_x2 == nil then return nil, origin_x_error end
  local origin_y2, origin_y_error = internal.checked_double(origin_y, "room frame Y origin")
  if origin_y2 == nil then return nil, origin_y_error end
  local frame, frame_error = transforms.frame(origin_x2, origin_y2)
  if not frame then return nil, frame_error end

  if room.footprint ~= nil then
    local shape, shape_error = M.from_persisted(room.footprint)
    if not shape then return nil, shape_error end
    return shape, frame
  end
  if type(room.size_mm) ~= "table" then
    return internal.failure("FOOTPRINT_ROOM", "schema-v1 rooms must provide size_mm")
  end
  local width, depth = room.size_mm[1], room.size_mm[2]
  if not internal.finite_integer(width) or width <= 0
    or not internal.finite_integer(depth) or depth <= 0
  then
    return internal.failure("FOOTPRINT_ROOM", "room geometry must use an integer origin and positive integer dimensions")
  end
  local width2, width_error = internal.checked_double(width, "room-local width")
  if width2 == nil then return nil, width_error end
  local _, width_range_error = internal.coordinate2(width2, "room-local right coordinate")
  if width_range_error then return nil, width_range_error end
  local depth2, depth_error = internal.checked_double(depth, "room-local depth")
  if depth2 == nil then return nil, depth_error end
  local _, depth_range_error = internal.coordinate2(depth2, "room-local top coordinate")
  if depth_range_error then return nil, depth_range_error end
  local part = { left2 = 0, bottom2 = 0, right2 = width2, top2 = depth2 }
  if part_id ~= nil then part.id = part_id end
  local local_shape, shape_error = core.normalize({ kind = core.KIND, parts = { part } })
  if not local_shape then return nil, shape_error end
  return local_shape, frame
end

---Derive a world footprint from either persisted schema version.
function M.from_room(room)
  local part_id
  if not (room and room.footprint) then part_id = "part-main" end
  local local_shape, frame_or_error = M.local_from_room(room, part_id)
  if not local_shape then return nil, frame_or_error end
  return transforms.from_local(local_shape, frame_or_error)
end

---Derive a world footprint from either persisted furniture representation.
function M.from_furniture(room, furniture, options)
  if type(room) ~= "table" or type(room.origin_mm) ~= "table" or type(furniture) ~= "table" then
    return internal.failure("FOOTPRINT_FURNITURE", "furniture footprint requires an owner room")
  end
  options = options or {}

  if furniture.footprint ~= nil then
    if type(furniture.position_mm) ~= "table" or type(furniture.anchor2_mm) ~= "table" then
      return internal.failure(
        "FOOTPRINT_FURNITURE",
        "schema-v2 furniture requires position_mm, anchor2_mm, and footprint"
      )
    end
    local local_shape, local_error = M.from_persisted(furniture.footprint)
    if not local_shape then return nil, local_error end
    local rotation = furniture.rotation_deg or 0
    if not internal.rotations[rotation] and internal.rotations[options.rotation_fallback] then
      rotation = options.rotation_fallback
    end
    local anchor_x2, anchor_y2 = furniture.anchor2_mm[1], furniture.anchor2_mm[2]
    local room_x, room_y = room.origin_mm[1], room.origin_mm[2]
    local position_x, position_y = furniture.position_mm[1], furniture.position_mm[2]
    if not internal.finite_integer(anchor_x2) or not internal.finite_integer(anchor_y2)
      or not internal.finite_integer(room_x) or not internal.finite_integer(room_y)
      or not internal.finite_integer(position_x) or not internal.finite_integer(position_y)
      or not internal.rotations[rotation]
    then
      return internal.failure(
        "FOOTPRINT_FURNITURE",
        "schema-v2 furniture placement must use exact coordinates and quarter turns"
      )
    end
    local world_x, world_x_error = internal.checked_add(room_x, position_x, "furniture world anchor X")
    if world_x == nil then return nil, world_x_error end
    local world_y, world_y_error = internal.checked_add(room_y, position_y, "furniture world anchor Y")
    if world_y == nil then return nil, world_y_error end
    local world_x2, doubled_x_error = doubled(world_x, "furniture world anchor X")
    if world_x2 == nil then return nil, doubled_x_error end
    local world_y2, doubled_y_error = doubled(world_y, "furniture world anchor Y")
    if world_y2 == nil then return nil, doubled_y_error end
    local delta_x2, delta_x_error = internal.checked_subtract(world_x2, anchor_x2, "furniture X translation")
    if delta_x2 == nil then return nil, delta_x_error end
    local delta_y2, delta_y_error = internal.checked_subtract(world_y2, anchor_y2, "furniture Y translation")
    if delta_y2 == nil then return nil, delta_y_error end
    return transforms.transform2(local_shape, {
      rotation_deg = rotation,
      pivot_x2 = anchor_x2,
      pivot_y2 = anchor_y2,
      delta_x2 = delta_x2,
      delta_y2 = delta_y2,
    })
  end

  if type(furniture.center_mm) ~= "table" or type(furniture.size_mm) ~= "table" then
    return internal.failure("FOOTPRINT_FURNITURE", "schema-v1 furniture requires center_mm and size_mm")
  end
  local width, depth = furniture.size_mm[1], furniture.size_mm[2]
  local center_x, center_y = furniture.center_mm[1], furniture.center_mm[2]
  local room_x, room_y = room.origin_mm[1], room.origin_mm[2]
  local rotation = furniture.rotation_deg or 0
  if not internal.rotations[rotation] and internal.rotations[options.rotation_fallback] then
    rotation = options.rotation_fallback
  end
  if not internal.finite_integer(width) or width <= 0
    or not internal.finite_integer(depth) or depth <= 0
    or not internal.finite_integer(center_x) or not internal.finite_integer(center_y)
    or not internal.finite_integer(room_x) or not internal.finite_integer(room_y)
    or not internal.rotations[rotation]
  then
    return internal.failure(
      "FOOTPRINT_FURNITURE",
      "furniture geometry must use positive dimensions, integer coordinates, and quarter turns"
    )
  end

  -- Around a doubled origin, an integer-mm width has bounds [-width, width].
  -- This is what preserves half-millimetre edges for odd dimensions.
  local _, width_range_error = internal.coordinate2(width, "furniture half-width")
  if width_range_error then return nil, width_range_error end
  local _, depth_range_error = internal.coordinate2(depth, "furniture half-depth")
  if depth_range_error then return nil, depth_range_error end
  local local_shape, local_error = core.rectangle2(-width, -depth, width, depth)
  if not local_shape then return nil, local_error end
  local rotated, rotation_error = transforms.rotate_quarter(local_shape, rotation, 0, 0)
  if not rotated then return nil, rotation_error end
  local world_center_x, center_x_error = internal.checked_add(room_x, center_x, "furniture world-centre X")
  if world_center_x == nil then return nil, center_x_error end
  local world_center_y, center_y_error = internal.checked_add(room_y, center_y, "furniture world-centre Y")
  if world_center_y == nil then return nil, center_y_error end
  local world_center_x2, world_x_error = internal.checked_double(world_center_x, "furniture world-centre X")
  if world_center_x2 == nil then return nil, world_x_error end
  local _, world_x_range_error = internal.coordinate2(world_center_x2, "furniture world-centre X")
  if world_x_range_error then return nil, world_x_range_error end
  local world_center_y2, world_y_error = internal.checked_double(world_center_y, "furniture world-centre Y")
  if world_center_y2 == nil then return nil, world_y_error end
  local _, world_y_range_error = internal.coordinate2(world_center_y2, "furniture world-centre Y")
  if world_y_range_error then return nil, world_y_range_error end
  return transforms.translate2(rotated, world_center_x2, world_center_y2)
end

return M
