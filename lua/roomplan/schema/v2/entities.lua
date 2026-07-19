-- Schema-v2 room, furniture, door, and project-template normalization.

local json = require("roomplan.codec.json")
local ids = require("roomplan.ids")
local common = require("roomplan.schema.common")
local footprint = require("roomplan.schema.v2.footprint")

local M = {}

local SIDES = { north = true, east = true, south = true, west = true }
local HINGES = { start = true, ["end"] = true }
local SWINGS = { owner = true, connected = true, outside = true }
local ROTATIONS = { [0] = true, [90] = true, [180] = true, [270] = true }

local function reject_stale_fields(context, value, path, fields)
  for _, field in ipairs(fields) do
    if value[field] ~= nil then
      common.add_error(
        context,
        "SCHEMA_STALE_FIELD",
        path .. "." .. field,
        field .. " belongs to schema v1 and cannot coexist with schema-v2 geometry",
        value[field]
      )
    end
  end
end

function M.normalize_room(context, source, path, room_footprints)
  local result = common.object(context, source, path)
  if not result then return nil end
  reject_stale_fields(context, result, path, { "size_mm" })
  result.id = common.normalize_id(context, common.required(context, result, "id", path), path .. ".id", "room")
  result.name =
    common.text(context, common.required(context, result, "name", path), path .. ".name", { nonempty = true })
  result.origin_mm = common.tuple(
    context,
    common.required(context, result, "origin_mm", path),
    path .. ".origin_mm",
    2,
    function(value, item_path) return common.coordinate(context, value, item_path) end
  )
  local runtime
  result.footprint, runtime =
    footprint.normalize(context, common.required(context, result, "footprint", path), path .. ".footprint")
  if result.id and runtime then
    local part_ids = {}
    for _, part in ipairs(runtime.parts) do
      part_ids[part.id] = true
    end
    room_footprints[result.id] = { runtime = runtime, part_ids = part_ids }
  end
  if result.color ~= nil then result.color = common.persisted_color(context, result.color, path .. ".color") end
  return result
end

function M.normalize_furniture(context, source, path)
  local result = common.object(context, source, path)
  if not result then return nil end
  reject_stale_fields(context, result, path, { "center_mm", "size_mm" })
  result.id = common.normalize_id(context, common.required(context, result, "id", path), path .. ".id", "furniture")
  result.room_id =
    common.normalize_id(context, common.required(context, result, "room_id", path), path .. ".room_id", "room")
  local template_id = common.text(
    context,
    common.required(context, result, "template_id", path),
    path .. ".template_id",
    { nonempty = true, max_bytes = 128 }
  )
  if template_id then
    local valid, err = ids.valid_template_reference(template_id)
    if not valid then
      common.add_error(context, err.code, path .. ".template_id", err.message, template_id)
      template_id = nil
    end
  end
  result.template_id = template_id
  result.name =
    common.text(context, common.required(context, result, "name", path), path .. ".name", { nonempty = true })
  result.category =
    common.text(context, common.required(context, result, "category", path), path .. ".category", { nonempty = true })
  result.position_mm = common.tuple(
    context,
    common.required(context, result, "position_mm", path),
    path .. ".position_mm",
    2,
    function(value, item_path) return common.coordinate(context, value, item_path) end
  )
  result.anchor2_mm =
    footprint.normalize_anchor(context, common.required(context, result, "anchor2_mm", path), path .. ".anchor2_mm")
  local runtime
  result.footprint, runtime =
    footprint.normalize(context, common.required(context, result, "footprint", path), path .. ".footprint")
  footprint.validate_anchor(context, result.anchor2_mm, runtime, path .. ".anchor2_mm")
  result.height_mm =
    common.dimension(context, common.required(context, result, "height_mm", path), path .. ".height_mm")
  local rotation = common.integer(
    context,
    common.required(context, result, "rotation_deg", path),
    path .. ".rotation_deg",
    0,
    270,
    270
  )
  if rotation ~= nil and not ROTATIONS[rotation] then
    common.add_error(
      context,
      "SCHEMA_ROTATION",
      path .. ".rotation_deg",
      "must be exactly 0, 90, 180, or 270",
      rotation
    )
    rotation = nil
  end
  result.rotation_deg = rotation
  if result.color ~= nil then result.color = common.persisted_color(context, result.color, path .. ".color") end
  return result
end

function M.normalize_door(context, source, path)
  local result = common.object(context, source, path)
  if not result then return nil end
  result.id = common.normalize_id(context, common.required(context, result, "id", path), path .. ".id", "door")
  local kind = common.required(context, result, "kind", path)
  if kind ~= "hinged" then
    common.add_error(context, "SCHEMA_DOOR_KIND", path .. ".kind", "must be exactly 'hinged' in schema v2", kind)
    kind = nil
  end
  result.kind = kind
  result.room_id =
    common.normalize_id(context, common.required(context, result, "room_id", path), path .. ".room_id", "room")
  local connected = common.required(context, result, "connects_to_room_id", path)
  if connected == json.null then
    result.connects_to_room_id = json.null
  else
    result.connects_to_room_id = common.normalize_id(context, connected, path .. ".connects_to_room_id", "room")
  end
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
  result.width_mm = common.dimension(context, common.required(context, result, "width_mm", path), path .. ".width_mm")
  result.hinge = common.enum(context, common.required(context, result, "hinge", path), path .. ".hinge", HINGES)
  result.opens_into =
    common.enum(context, common.required(context, result, "opens_into", path), path .. ".opens_into", SWINGS)
  result.open_angle_deg = common.integer(
    context,
    common.required(context, result, "open_angle_deg", path),
    path .. ".open_angle_deg",
    1,
    180,
    180
  )
  return result
end

function M.normalize_template(context, source, path)
  local result = common.object(context, source, path)
  if not result then return nil end
  reject_stale_fields(context, result, path, { "shape", "default_size_mm" })
  result.id =
    common.normalize_id(context, common.required(context, result, "id", path), path .. ".id", "custom_template")
  result.name =
    common.text(context, common.required(context, result, "name", path), path .. ".name", { nonempty = true })
  result.category =
    common.text(context, common.required(context, result, "category", path), path .. ".category", { nonempty = true })
  local runtime
  result.default_footprint, runtime = footprint.normalize(
    context,
    common.required(context, result, "default_footprint", path),
    path .. ".default_footprint"
  )
  result.default_anchor2_mm = footprint.normalize_anchor(
    context,
    common.required(context, result, "default_anchor2_mm", path),
    path .. ".default_anchor2_mm"
  )
  footprint.validate_anchor(context, result.default_anchor2_mm, runtime, path .. ".default_anchor2_mm")
  result.default_height_mm =
    common.dimension(context, common.required(context, result, "default_height_mm", path), path .. ".default_height_mm")
  return result
end

function M.validate_door_parts(context, doors, room_footprints)
  for index, door in ipairs(doors or {}) do
    local owner = room_footprints[door.room_id]
    if owner and door.part_id and not owner.part_ids[door.part_id] then
      common.add_error(
        context,
        "SCHEMA_DOOR_PART",
        "$.doors[" .. index .. "].part_id",
        "referenced footprint part does not exist in the owner room",
        door.part_id
      )
    end
  end
end

return M
