-- Schema-v3 root document normalization and cross-entity checks.

local json = require("roomplan.codec.json")
local ids = require("roomplan.ids")
local common = require("roomplan.schema.common")
local entities = require("roomplan.schema.v3.entities")

local M = {}
local VERSION = 3

function M.normalize_with(document, schema_version, entity_normalizers, normalize_root)
  schema_version = schema_version or VERSION
  entity_normalizers = entity_normalizers or entities
  local context = common.new_context()
  local result = common.object(context, document, "$")
  if not result then return common.result_or_error(context) end

  if result.format ~= common.FORMAT then
    common.add_error(
      context,
      "SCHEMA_FORMAT",
      "$.format",
      "must be exactly '" .. common.FORMAT .. "'",
      result.format
    )
  end
  result.format = common.FORMAT

  if result.schema_version == nil then
    common.add_error(
      context,
      "SCHEMA_VERSION_MISSING",
      "$.schema_version",
      "schema_version is required; unversioned documents are not guessed as v" .. schema_version
    )
  end
  local version = result.schema_version ~= nil
      and common.integer(context, result.schema_version, "$.schema_version", 1, 1000000, 1000000)
    or nil
  if version ~= schema_version then
    if version and version > schema_version then
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
    common.add_error(context, "SCHEMA_UNITS", "$.units",
      "must be exactly 'mm' in schema v" .. schema_version, result.units)
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

  local room_footprints = {}
  result.rooms = common.normalize_collection(
    context,
    common.required(context, result, "rooms", "$"),
    "$.rooms",
    function(entity_context, source, path)
      return entity_normalizers.normalize_room(entity_context, source, path, room_footprints)
    end
  )
  result.doors = common.normalize_collection(
    context,
    common.required(context, result, "doors", "$"),
    "$.doors",
    entity_normalizers.normalize_door
  )
  result.windows = common.normalize_collection(
    context,
    common.required(context, result, "windows", "$"),
    "$.windows",
    entity_normalizers.normalize_window
  )
  result.outlets = common.normalize_collection(
    context,
    common.required(context, result, "outlets", "$"),
    "$.outlets",
    entity_normalizers.normalize_outlet
  )
  result.furniture = common.normalize_collection(
    context,
    common.required(context, result, "furniture", "$"),
    "$.furniture",
    entity_normalizers.normalize_furniture
  )
  result.custom_templates = common.normalize_collection(
    context,
    common.required(context, result, "custom_templates", "$"),
    "$.custom_templates",
    entity_normalizers.normalize_template
  )

  if result.extensions == nil then
    result.extensions = json.object()
    common.mark_default(context, "$.extensions")
  elseif not json.is_object(result.extensions) then
    common.add_error(context, "SCHEMA_OBJECT", "$.extensions", "must be a JSON object", result.extensions)
  else
    result.extensions = json.deep_copy(result.extensions)
  end

  if result.rooms and result.doors and result.windows and result.outlets
    and result.furniture and result.custom_templates
  then
    local index, index_errors = ids.index(result)
    if not index then
      local position = 1
      while position <= #index_errors do
        local err = index_errors[position]
        common.add_error(context, err.code, "$", err.message, err.id)
        position = position + 1
      end
    end
    entity_normalizers.validate_door_parts(context, result.doors, room_footprints)
    entity_normalizers.validate_window_parts(context, result.windows, room_footprints)
    entity_normalizers.validate_outlet_parts(context, result.outlets, room_footprints)
  end

  if type(normalize_root) == "function" then normalize_root(context, result) end

  common.validate_json_tree(context, result, "$", {})
  return common.result_or_error(context, result)
end

function M.normalize(document)
  return M.normalize_with(document, VERSION, entities)
end

return M
