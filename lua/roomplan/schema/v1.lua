-- Explicit schema-v1 document normalizer.
--
-- This module owns only the v1 persisted shape. Shared scalar and tagged-JSON
-- contracts live in schema.common, while schema.lua owns version dispatch.

local json = require("roomplan.codec.json")
local ids = require("roomplan.ids")
local common = require("roomplan.schema.common")

local M = { VERSION = 1 }

local SIDES = { north = true, east = true, south = true, west = true }
local HINGES = { start = true, ["end"] = true }
local SWINGS = { owner = true, connected = true, outside = true }
local ROTATIONS = { [0] = true, [90] = true, [180] = true, [270] = true }

local function normalize_room(context, source, path)
  local result = common.object(context, source, path)
  if not result then return nil end
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
  result.size_mm = common.tuple(
    context,
    common.required(context, result, "size_mm", path),
    path .. ".size_mm",
    2,
    function(value, item_path) return common.dimension(context, value, item_path) end
  )
  if result.color ~= nil then result.color = common.persisted_color(context, result.color, path .. ".color") end
  return result
end

local function normalize_furniture(context, source, path)
  local result = common.object(context, source, path)
  if not result then return nil end
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
  result.center_mm = common.tuple(
    context,
    common.required(context, result, "center_mm", path),
    path .. ".center_mm",
    2,
    function(value, item_path) return common.coordinate(context, value, item_path) end
  )
  result.size_mm = common.tuple(
    context,
    common.required(context, result, "size_mm", path),
    path .. ".size_mm",
    3,
    function(value, item_path) return common.dimension(context, value, item_path) end
  )
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

local function normalize_door(context, source, path)
  local result = common.object(context, source, path)
  if not result then return nil end
  result.id = common.normalize_id(context, common.required(context, result, "id", path), path .. ".id", "door")
  local kind = common.required(context, result, "kind", path)
  if kind ~= "hinged" then
    common.add_error(context, "SCHEMA_DOOR_KIND", path .. ".kind", "must be exactly 'hinged' in schema v1", kind)
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

local function normalize_template(context, source, path)
  local result = common.object(context, source, path)
  if not result then return nil end
  result.id =
    common.normalize_id(context, common.required(context, result, "id", path), path .. ".id", "custom_template")
  result.name =
    common.text(context, common.required(context, result, "name", path), path .. ".name", { nonempty = true })
  result.category =
    common.text(context, common.required(context, result, "category", path), path .. ".category", { nonempty = true })
  local shape = common.required(context, result, "shape", path)
  if shape ~= "rectangle" then
    common.add_error(
      context,
      "SCHEMA_TEMPLATE_SHAPE",
      path .. ".shape",
      "must be exactly 'rectangle' in schema v1",
      shape
    )
    shape = nil
  end
  result.shape = shape
  result.default_size_mm = common.tuple(
    context,
    common.required(context, result, "default_size_mm", path),
    path .. ".default_size_mm",
    3,
    function(value, item_path) return common.dimension(context, value, item_path) end
  )
  return result
end

-- Validate and normalize an already-v1 document. The returned model is always
-- a fresh tagged tree; callers retain the untouched decoded document for
-- conflict reporting if desired.
function M.normalize(document)
  local context = common.new_context()
  local result = common.object(context, document, "$")
  if not result then return common.result_or_error(context) end

  if result.format ~= common.FORMAT then
    common.add_error(context, "SCHEMA_FORMAT", "$.format", "must be exactly '" .. common.FORMAT .. "'", result.format)
  end
  result.format = common.FORMAT

  if result.schema_version == nil then
    common.add_error(
      context,
      "SCHEMA_VERSION_MISSING",
      "$.schema_version",
      "schema_version is required; unversioned documents are not guessed as v1"
    )
  end
  local version = result.schema_version ~= nil
      and common.integer(context, result.schema_version, "$.schema_version", 1, 1000000, 1000000)
    or nil
  if version ~= M.VERSION then
    if version and version > M.VERSION then
      common.add_error(
        context,
        "SCHEMA_FUTURE_VERSION",
        "$.schema_version",
        "schema version is newer than this plugin supports",
        version
      )
    elseif version then
      common.add_error(
        context,
        "SCHEMA_VERSION",
        "$.schema_version",
        "schema version requires a registered migration",
        version
      )
    end
  end
  result.schema_version = version

  if result.units ~= "mm" then
    common.add_error(context, "SCHEMA_UNITS", "$.units", "must be exactly 'mm' in schema v1", result.units)
  end
  result.units = "mm"

  if result.metadata == nil then
    result.metadata = json.object({ name = common.defaults.metadata.name, notes = common.defaults.metadata.notes })
    common.mark_default(context, "$.metadata")
  else
    result.metadata = common.normalize_metadata(context, result.metadata, "$.metadata")
  end

  if result.settings == nil then
    result.settings = json.object(json.deep_copy(common.defaults.settings))
    common.mark_default(context, "$.settings")
  else
    result.settings = common.normalize_settings(context, result.settings, "$.settings")
  end

  result.rooms =
    common.normalize_collection(context, common.required(context, result, "rooms", "$"), "$.rooms", normalize_room)
  result.doors =
    common.normalize_collection(context, common.required(context, result, "doors", "$"), "$.doors", normalize_door)
  result.furniture = common.normalize_collection(
    context,
    common.required(context, result, "furniture", "$"),
    "$.furniture",
    normalize_furniture
  )
  result.custom_templates = common.normalize_collection(
    context,
    common.required(context, result, "custom_templates", "$"),
    "$.custom_templates",
    normalize_template
  )

  if result.extensions == nil then
    result.extensions = json.object()
    common.mark_default(context, "$.extensions")
  elseif not json.is_object(result.extensions) then
    common.add_error(context, "SCHEMA_OBJECT", "$.extensions", "must be a JSON object", result.extensions)
  else
    result.extensions = json.deep_copy(result.extensions)
  end

  if result.rooms and result.doors and result.furniture and result.custom_templates then
    local index, index_errors = ids.index(result)
    if not index then
      local position = 1
      while position <= #index_errors do
        local err = index_errors[position]
        common.add_error(context, err.code, "$", err.message, err.id)
        position = position + 1
      end
    end
  end

  common.validate_json_tree(context, result, "$", {})
  return common.result_or_error(context, result)
end

return M
