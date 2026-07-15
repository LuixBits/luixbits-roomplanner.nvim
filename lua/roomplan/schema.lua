-- Authoritative runtime schema v1 for roomplan.nvim.
-- Structural validation is intentionally separate from layout validation:
-- safely loadable overlap/containment problems belong to roomplan.validate.

local json = require("roomplan.codec.json")
local ids = require("roomplan.ids")
local color = require("roomplan.color")

local M = {}

M.FORMAT = "roomplan.nvim"
M.CURRENT_VERSION = 1
M.migrations = {} -- v1 is the first published schema; no fictitious v0.

M.defaults = {
  metadata = {
    name = "Untitled plan",
    notes = "",
  },
  settings = {
    grid_mm = 100,
    fine_step_mm = 10,
    normal_step_mm = 100,
    coarse_step_mm = 500,
    default_door_width_mm = 900,
  },
}

M.limits = {
  coordinate_abs_exclusive = 2 ^ 50,
  local_mm_max = 1000000000,
  entity_count = 10000,
  text_bytes = 512,
  notes_bytes = 1024 * 1024,
}

local SIDES = { north = true, east = true, south = true, west = true }
local HINGES = { start = true, ["end"] = true }
local SWINGS = { owner = true, connected = true, outside = true }
local ROTATIONS = { [0] = true, [90] = true, [180] = true, [270] = true }

local function diagnostic(code, path, message, value)
  return { code = code, path = path, message = message, value = value }
end

local function add_error(context, code, path, message, value)
  context.errors[#context.errors + 1] = diagnostic(code, path, message, value)
  return nil
end

local function mark_default(context, path)
  context.normalized = true
  context.added_fields[#context.added_fields + 1] = path
end

local function is_safe_lua_integer(value)
  return type(value) == "number"
    and value == value
    and value ~= math.huge
    and value ~= -math.huge
    and value == math.floor(value)
    and math.abs(value) <= 9007199254740991
end

local function decimal_to_integer(value, maximum_abs)
  if is_safe_lua_integer(value) then
    if math.abs(value) > maximum_abs then
      return nil, "outside the allowed integer range"
    end
    return value
  end
  if not json.is_decimal(value) then
    return nil, "expected an integer"
  end
  local sign, coefficient, exponent = json.decimal_parts(value)
  if coefficient == "0" then
    return 0
  end
  if exponent < 0 then
    return nil, "expected a whole integer, not a fractional value"
  end
  if #coefficient + exponent > 32 then
    return nil, "outside the allowed integer range"
  end
  local result = 0
  local cursor = 1
  while cursor <= #coefficient do
    local digit = coefficient:byte(cursor) - 48
    if result > math.floor((maximum_abs - digit) / 10) then
      return nil, "outside the allowed integer range"
    end
    result = result * 10 + digit
    cursor = cursor + 1
  end
  cursor = 1
  while cursor <= exponent do
    if result > math.floor(maximum_abs / 10) then
      return nil, "outside the allowed integer range"
    end
    result = result * 10
    cursor = cursor + 1
  end
  return sign < 0 and -result or result
end

local function integer(context, value, path, minimum, maximum, maximum_abs)
  maximum_abs = maximum_abs or M.limits.coordinate_abs_exclusive - 1
  local converted, reason = decimal_to_integer(value, maximum_abs)
  if converted == nil then
    return add_error(context, "SCHEMA_INTEGER", path, reason, value)
  end
  if minimum ~= nil and converted < minimum then
    return add_error(context, "SCHEMA_INTEGER_MIN", path, "must be at least " .. minimum, converted)
  end
  if maximum ~= nil and converted > maximum then
    return add_error(context, "SCHEMA_INTEGER_MAX", path, "must be at most " .. maximum, converted)
  end
  return converted
end

local function has_disallowed_control(value, allow_lines)
  local cursor = 1
  while cursor <= #value do
    local byte = value:byte(cursor)
    if byte == 0 then
      return true
    end
    if byte < 32 then
      if not allow_lines or (byte ~= 9 and byte ~= 10 and byte ~= 13) then
        return true
      end
    end
    cursor = cursor + 1
  end
  return false
end

local function text(context, value, path, options)
  options = options or {}
  if type(value) ~= "string" then
    return add_error(context, "SCHEMA_STRING", path, "must be a string", value)
  end
  local valid_utf8, invalid_position, invalid_message = json.valid_utf8(value)
  if not valid_utf8 then
    return add_error(context, "SCHEMA_STRING_UTF8", path, invalid_message .. " at byte " .. invalid_position, value)
  end
  if options.nonempty and value == "" then
    return add_error(context, "SCHEMA_STRING_EMPTY", path, "must not be empty", value)
  end
  local maximum = options.max_bytes or M.limits.text_bytes
  if #value > maximum then
    return add_error(context, "SCHEMA_STRING_LIMIT", path, "exceeds the " .. maximum .. " byte limit", value)
  end
  if has_disallowed_control(value, options.allow_lines) then
    return add_error(context, "SCHEMA_STRING_CONTROL", path, "contains a disallowed control character", value)
  end
  return value
end

local function persisted_color(context, value, path)
  local normalized, reason = color.normalize(value)
  if not normalized then
    return add_error(context, "SCHEMA_COLOR", path, reason, value)
  end
  if normalized ~= value then context.normalized = true end
  return normalized
end

---Validate a standalone value against the same text contract used by plan
---fields. This keeps configuration-supplied labels safe before they enter a
---model or renderer.
function M.validate_text(value, options)
  options = options or {}
  local context = { errors = {}, normalized = false, added_fields = {} }
  local normalized = text(context, value, options.path or "$", options)
  return normalized, context.errors[1]
end

local function object(context, value, path)
  if not json.is_object(value) then
    add_error(context, "SCHEMA_OBJECT", path, "must be a JSON object", value)
    return nil
  end
  return json.deep_copy(value)
end

local function array(context, value, path)
  if not json.is_array(value) then
    add_error(context, "SCHEMA_ARRAY", path, "must be a JSON array", value)
    return nil
  end
  local count = 0
  local maximum = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
      add_error(context, "SCHEMA_ARRAY_KEY", path, "contains a non-array key", key)
      return nil
    end
    count = count + 1
    if key > maximum then
      maximum = key
    end
  end
  if count ~= maximum then
    add_error(context, "SCHEMA_ARRAY_SPARSE", path, "must not be sparse", value)
    return nil
  end
  return value
end

local function enum(context, value, path, choices)
  if type(value) ~= "string" or not choices[value] then
    return add_error(context, "SCHEMA_ENUM", path, "has an unsupported value", value)
  end
  return value
end

local function required(context, source, key, path)
  if source[key] == nil then
    add_error(context, "SCHEMA_REQUIRED", path .. "." .. key, "required field is missing")
    return nil
  end
  return source[key]
end

local function tuple(context, value, path, length, item_normalizer)
  local source = array(context, value, path)
  if not source then
    return nil
  end
  if #source ~= length then
    add_error(context, "SCHEMA_TUPLE_LENGTH", path, "must contain exactly " .. length .. " items", value)
    return nil
  end
  local result = json.array()
  local position = 1
  while position <= length do
    result[position] = item_normalizer(source[position], path .. "[" .. position .. "]")
    position = position + 1
  end
  return result
end

local function normalize_metadata(context, value, path)
  local result = object(context, value, path)
  if not result then
    return nil
  end
  if result.name == nil then
    result.name = M.defaults.metadata.name
    mark_default(context, path .. ".name")
  else
    result.name = text(context, result.name, path .. ".name", { nonempty = true })
  end
  if result.notes == nil then
    result.notes = M.defaults.metadata.notes
    mark_default(context, path .. ".notes")
  else
    result.notes = text(context, result.notes, path .. ".notes", {
      max_bytes = M.limits.notes_bytes,
      allow_lines = true,
    })
  end
  return result
end

local SETTING_FIELDS = {
  "grid_mm",
  "fine_step_mm",
  "normal_step_mm",
  "coarse_step_mm",
  "default_door_width_mm",
}

local function normalize_settings(context, value, path)
  local result = object(context, value, path)
  if not result then
    return nil
  end
  local position = 1
  while position <= #SETTING_FIELDS do
    local key = SETTING_FIELDS[position]
    if result[key] == nil then
      result[key] = M.defaults.settings[key]
      mark_default(context, path .. "." .. key)
    else
      result[key] = integer(context, result[key], path .. "." .. key, 1, M.limits.local_mm_max, M.limits.local_mm_max)
    end
    position = position + 1
  end
  return result
end

local function normalize_id(context, value, path, kind)
  local id = text(context, value, path, { nonempty = true, max_bytes = 128 })
  if id == nil then
    return nil
  end
  local valid, err = ids.validate(id, kind)
  if not valid then
    add_error(context, err.code, path, err.message, id)
    return nil
  end
  return id
end

local function coordinate(context, value, path)
  return integer(
    context,
    value,
    path,
    -(M.limits.coordinate_abs_exclusive - 1),
    M.limits.coordinate_abs_exclusive - 1,
    M.limits.coordinate_abs_exclusive - 1
  )
end

local function dimension(context, value, path)
  return integer(context, value, path, 1, M.limits.local_mm_max, M.limits.local_mm_max)
end

local function normalize_room(context, source, path)
  local result = object(context, source, path)
  if not result then
    return nil
  end
  result.id = normalize_id(context, required(context, result, "id", path), path .. ".id", "room")
  result.name = text(context, required(context, result, "name", path), path .. ".name", { nonempty = true })
  result.origin_mm = tuple(context, required(context, result, "origin_mm", path), path .. ".origin_mm", 2, function(value, item_path)
    return coordinate(context, value, item_path)
  end)
  result.size_mm = tuple(context, required(context, result, "size_mm", path), path .. ".size_mm", 2, function(value, item_path)
    return dimension(context, value, item_path)
  end)
  if result.color ~= nil then result.color = persisted_color(context, result.color, path .. ".color") end
  return result
end

local function normalize_furniture(context, source, path)
  local result = object(context, source, path)
  if not result then
    return nil
  end
  result.id = normalize_id(context, required(context, result, "id", path), path .. ".id", "furniture")
  result.room_id = normalize_id(context, required(context, result, "room_id", path), path .. ".room_id", "room")
  local template_id = text(context, required(context, result, "template_id", path), path .. ".template_id", { nonempty = true, max_bytes = 128 })
  if template_id then
    local valid, err = ids.valid_template_reference(template_id)
    if not valid then
      add_error(context, err.code, path .. ".template_id", err.message, template_id)
      template_id = nil
    end
  end
  result.template_id = template_id
  result.name = text(context, required(context, result, "name", path), path .. ".name", { nonempty = true })
  result.category = text(context, required(context, result, "category", path), path .. ".category", { nonempty = true })
  result.center_mm = tuple(context, required(context, result, "center_mm", path), path .. ".center_mm", 2, function(value, item_path)
    return coordinate(context, value, item_path)
  end)
  result.size_mm = tuple(context, required(context, result, "size_mm", path), path .. ".size_mm", 3, function(value, item_path)
    return dimension(context, value, item_path)
  end)
  local rotation = integer(context, required(context, result, "rotation_deg", path), path .. ".rotation_deg", 0, 270, 270)
  if rotation ~= nil and not ROTATIONS[rotation] then
    add_error(context, "SCHEMA_ROTATION", path .. ".rotation_deg", "must be exactly 0, 90, 180, or 270", rotation)
    rotation = nil
  end
  result.rotation_deg = rotation
  if result.color ~= nil then result.color = persisted_color(context, result.color, path .. ".color") end
  return result
end

local function normalize_door(context, source, path)
  local result = object(context, source, path)
  if not result then
    return nil
  end
  result.id = normalize_id(context, required(context, result, "id", path), path .. ".id", "door")
  local kind = required(context, result, "kind", path)
  if kind ~= "hinged" then
    add_error(context, "SCHEMA_DOOR_KIND", path .. ".kind", "must be exactly 'hinged' in schema v1", kind)
    kind = nil
  end
  result.kind = kind
  result.room_id = normalize_id(context, required(context, result, "room_id", path), path .. ".room_id", "room")
  local connected = required(context, result, "connects_to_room_id", path)
  if connected == json.null then
    result.connects_to_room_id = json.null
  else
    result.connects_to_room_id = normalize_id(context, connected, path .. ".connects_to_room_id", "room")
  end
  result.side = enum(context, required(context, result, "side", path), path .. ".side", SIDES)
  result.offset_mm = integer(context, required(context, result, "offset_mm", path), path .. ".offset_mm", 0, M.limits.local_mm_max, M.limits.local_mm_max)
  result.width_mm = dimension(context, required(context, result, "width_mm", path), path .. ".width_mm")
  result.hinge = enum(context, required(context, result, "hinge", path), path .. ".hinge", HINGES)
  result.opens_into = enum(context, required(context, result, "opens_into", path), path .. ".opens_into", SWINGS)
  result.open_angle_deg = integer(context, required(context, result, "open_angle_deg", path), path .. ".open_angle_deg", 1, 180, 180)
  return result
end

local function normalize_template(context, source, path)
  local result = object(context, source, path)
  if not result then
    return nil
  end
  result.id = normalize_id(context, required(context, result, "id", path), path .. ".id", "custom_template")
  result.name = text(context, required(context, result, "name", path), path .. ".name", { nonempty = true })
  result.category = text(context, required(context, result, "category", path), path .. ".category", { nonempty = true })
  local shape = required(context, result, "shape", path)
  if shape ~= "rectangle" then
    add_error(context, "SCHEMA_TEMPLATE_SHAPE", path .. ".shape", "must be exactly 'rectangle' in schema v1", shape)
    shape = nil
  end
  result.shape = shape
  result.default_size_mm = tuple(context, required(context, result, "default_size_mm", path), path .. ".default_size_mm", 3, function(value, item_path)
    return dimension(context, value, item_path)
  end)
  return result
end

local function normalize_collection(context, source, path, normalizer)
  local values = array(context, source, path)
  if not values then
    return nil
  end
  if #values > M.limits.entity_count then
    add_error(context, "SCHEMA_ENTITY_LIMIT", path, "contains more than " .. M.limits.entity_count .. " entities", #values)
    return nil
  end
  local result = json.array()
  local position = 1
  while position <= #values do
    result[position] = normalizer(context, values[position], path .. "[" .. position .. "]")
    position = position + 1
  end
  return result
end

local function validate_json_tree(context, value, path, active)
  local value_type = type(value)
  if value == json.null or value_type == "boolean" or json.is_decimal(value) then
    return
  end
  if value_type == "string" then
    local valid_utf8, invalid_position, invalid_message = json.valid_utf8(value)
    if not valid_utf8 then
      add_error(context, "SCHEMA_JSON_UTF8", path, invalid_message .. " at byte " .. invalid_position, value)
    end
    return
  end
  if value_type == "number" then
    if not is_safe_lua_integer(value) then
      add_error(context, "SCHEMA_JSON_NUMBER", path, "contains an unsafe or fractional untagged Lua number", value)
    end
    return
  end
  if value_type ~= "table" then
    add_error(context, "SCHEMA_JSON_TYPE", path, "contains a value that JSON cannot represent", value_type)
    return
  end
  if not json.is_object(value) and not json.is_array(value) then
    add_error(context, "SCHEMA_JSON_TABLE_TAG", path, "contains an untagged Lua table", value)
    return
  end
  if active[value] then
    add_error(context, "SCHEMA_JSON_CYCLE", path, "contains a cyclic table", value)
    return
  end
  active[value] = true
  for key, child in pairs(value) do
    local child_path = path .. "." .. tostring(key)
    if json.is_object(value) and type(key) ~= "string" then
      add_error(context, "SCHEMA_JSON_OBJECT_KEY", child_path, "object key must be a string", key)
    elseif json.is_object(value) then
      local valid_utf8, invalid_position, invalid_message = json.valid_utf8(key)
      if not valid_utf8 then
        add_error(context, "SCHEMA_JSON_UTF8", child_path, invalid_message .. " at key byte " .. invalid_position, key)
      end
    elseif json.is_array(value) and (type(key) ~= "number" or key < 1 or key ~= math.floor(key)) then
      add_error(context, "SCHEMA_JSON_ARRAY_KEY", child_path, "array key must be a positive integer", key)
    end
    validate_json_tree(context, child, child_path, active)
  end
  active[value] = nil
end

local function result_or_error(context, result)
  if #context.errors > 0 then
    local first = context.errors[1]
    return nil, {
      code = first.code,
      path = first.path,
      message = first.message,
      diagnostics = context.errors,
    }
  end
  return result, {
    normalized = context.normalized,
    added_fields = context.added_fields,
    migration_notes = context.migration_notes or {},
  }
end

-- Validate and normalize an already-current v1 document. The returned model is
-- always a fresh tagged tree; callers retain the untouched decoded document for
-- conflict reporting if desired.
function M.normalize(document)
  local context = { errors = {}, normalized = false, added_fields = {}, migration_notes = {} }
  local result = object(context, document, "$")
  if not result then
    return result_or_error(context)
  end

  if result.format ~= M.FORMAT then
    add_error(context, "SCHEMA_FORMAT", "$.format", "must be exactly '" .. M.FORMAT .. "'", result.format)
  end
  result.format = M.FORMAT

  if result.schema_version == nil then
    add_error(context, "SCHEMA_VERSION_MISSING", "$.schema_version", "schema_version is required; unversioned documents are not guessed as v1")
  end
  local version = result.schema_version ~= nil
      and integer(context, result.schema_version, "$.schema_version", 1, 1000000, 1000000)
    or nil
  if version ~= M.CURRENT_VERSION then
    if version and version > M.CURRENT_VERSION then
      add_error(context, "SCHEMA_FUTURE_VERSION", "$.schema_version", "schema version is newer than this plugin supports", version)
    elseif version then
      add_error(context, "SCHEMA_VERSION", "$.schema_version", "schema version requires a registered migration", version)
    end
  end
  result.schema_version = version

  if result.units ~= "mm" then
    add_error(context, "SCHEMA_UNITS", "$.units", "must be exactly 'mm' in schema v1", result.units)
  end
  result.units = "mm"

  if result.metadata == nil then
    result.metadata = json.object({ name = M.defaults.metadata.name, notes = M.defaults.metadata.notes })
    mark_default(context, "$.metadata")
  else
    result.metadata = normalize_metadata(context, result.metadata, "$.metadata")
  end

  if result.settings == nil then
    result.settings = json.object(json.deep_copy(M.defaults.settings))
    mark_default(context, "$.settings")
  else
    result.settings = normalize_settings(context, result.settings, "$.settings")
  end

  result.rooms = normalize_collection(context, required(context, result, "rooms", "$"), "$.rooms", normalize_room)
  result.doors = normalize_collection(context, required(context, result, "doors", "$"), "$.doors", normalize_door)
  result.furniture = normalize_collection(context, required(context, result, "furniture", "$"), "$.furniture", normalize_furniture)
  result.custom_templates = normalize_collection(context, required(context, result, "custom_templates", "$"), "$.custom_templates", normalize_template)

  if result.extensions == nil then
    result.extensions = json.object()
    mark_default(context, "$.extensions")
  elseif not json.is_object(result.extensions) then
    add_error(context, "SCHEMA_OBJECT", "$.extensions", "must be a JSON object", result.extensions)
  else
    result.extensions = json.deep_copy(result.extensions)
  end

  if result.rooms and result.doors and result.furniture and result.custom_templates then
    local index, index_errors = ids.index(result)
    if not index then
      local position = 1
      while position <= #index_errors do
        local err = index_errors[position]
        add_error(context, err.code, "$", err.message, err.id)
        position = position + 1
      end
    end
  end

  validate_json_tree(context, result, "$", {})
  return result_or_error(context, result)
end

local function document_version(document)
  if not json.is_object(document) then
    return nil, diagnostic("SCHEMA_ROOT", "$", "root JSON value must be an object")
  end
  if document.format ~= M.FORMAT then
    return nil, diagnostic("SCHEMA_FORMAT", "$.format", "must be exactly '" .. M.FORMAT .. "'", document.format)
  end
  if document.schema_version == nil then
    return nil, diagnostic("SCHEMA_VERSION_MISSING", "$.schema_version", "schema_version is required; unversioned documents are not guessed as v1")
  end
  local version, reason = decimal_to_integer(document.schema_version, 1000000)
  if version == nil then
    return nil, diagnostic("SCHEMA_VERSION", "$.schema_version", reason, document.schema_version)
  end
  if version < 1 then
    return nil, diagnostic("SCHEMA_VERSION", "$.schema_version", "schema version 0/missing has no implicit migration", version)
  end
  if version > M.CURRENT_VERSION then
    return nil, diagnostic("SCHEMA_FUTURE_VERSION", "$.schema_version", "schema version " .. version .. " is newer than supported version " .. M.CURRENT_VERSION, version)
  end
  return version
end

-- Run the sequential migration registry on a deep copy. Initially this accepts
-- only v1 because v1 is the first published schema.
function M.migrate(document)
  local version, err = document_version(document)
  if not version then
    return nil, err
  end
  local copy = json.deep_copy(document)
  local notes = {}
  local migrated_any = false
  while version < M.CURRENT_VERSION do
    local migration = M.migrations[version]
    if type(migration) ~= "function" then
      return nil, diagnostic("SCHEMA_MIGRATION_MISSING", "$.schema_version", "no migration is registered from schema version " .. version, version)
    end
    local migrated, migration_notes = migration(copy)
    if not migrated then
      return nil, diagnostic("SCHEMA_MIGRATION_FAILED", "$", "migration from schema version " .. version .. " failed")
    end
    copy = migrated
    migrated_any = true
    if type(migration_notes) == "table" then
      local position = 1
      while position <= #migration_notes do
        notes[#notes + 1] = migration_notes[position]
        position = position + 1
      end
    end
    version = version + 1
  end
  return copy, notes, migrated_any
end

function M.load(document)
  local migrated, notes_or_error, migrated_any = M.migrate(document)
  if not migrated then
    return nil, notes_or_error
  end
  local model, info_or_error = M.normalize(migrated)
  if not model then
    return nil, info_or_error
  end
  info_or_error.migration_notes = notes_or_error
  info_or_error.migrated = migrated_any == true
  if info_or_error.migrated then
    info_or_error.normalized = true
  end
  return model, info_or_error
end

function M.decode(text_value, options)
  local document, err = json.decode(text_value, options)
  if document == nil then
    return nil, err
  end
  return M.load(document)
end

function M.validate(model)
  local normalized, info_or_error = M.normalize(model)
  if not normalized then
    return false, info_or_error
  end
  return true, info_or_error, normalized
end

function M.encode(model, options)
  local valid, info_or_error, normalized = M.validate(model)
  if not valid then
    return nil, info_or_error
  end
  local encoded, encode_error = json.encode(normalized, options)
  if not encoded then
    return nil, encode_error
  end
  return encoded, info_or_error
end

return M
