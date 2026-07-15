-- Shared schema primitives. Version modules own persisted entity shapes;
-- this module owns the exact JSON, scalar, diagnostic, and default contracts.

local json = require("roomplan.codec.json")
local ids = require("roomplan.ids")

local M = {}

M.FORMAT = "roomplan.nvim"

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

function M.diagnostic(code, path, message, value)
  return { code = code, path = path, message = message, value = value }
end

function M.new_context()
  return { errors = {}, normalized = false, added_fields = {}, migration_notes = {} }
end

function M.add_error(context, code, path, message, value)
  context.errors[#context.errors + 1] = M.diagnostic(code, path, message, value)
  return nil
end

function M.mark_default(context, path)
  context.normalized = true
  context.added_fields[#context.added_fields + 1] = path
end

function M.is_safe_lua_integer(value)
  return type(value) == "number"
    and value == value
    and value ~= math.huge
    and value ~= -math.huge
    and value == math.floor(value)
    and math.abs(value) <= 9007199254740991
end

function M.decimal_to_integer(value, maximum_abs)
  if M.is_safe_lua_integer(value) then
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

function M.integer(context, value, path, minimum, maximum, maximum_abs)
  maximum_abs = maximum_abs or M.limits.coordinate_abs_exclusive - 1
  local converted, reason = M.decimal_to_integer(value, maximum_abs)
  if converted == nil then
    return M.add_error(context, "SCHEMA_INTEGER", path, reason, value)
  end
  if minimum ~= nil and converted < minimum then
    return M.add_error(context, "SCHEMA_INTEGER_MIN", path, "must be at least " .. minimum, converted)
  end
  if maximum ~= nil and converted > maximum then
    return M.add_error(context, "SCHEMA_INTEGER_MAX", path, "must be at most " .. maximum, converted)
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

function M.text(context, value, path, options)
  options = options or {}
  if type(value) ~= "string" then
    return M.add_error(context, "SCHEMA_STRING", path, "must be a string", value)
  end
  local valid_utf8, invalid_position, invalid_message = json.valid_utf8(value)
  if not valid_utf8 then
    return M.add_error(
      context,
      "SCHEMA_STRING_UTF8",
      path,
      invalid_message .. " at byte " .. invalid_position,
      value
    )
  end
  if options.nonempty and value == "" then
    return M.add_error(context, "SCHEMA_STRING_EMPTY", path, "must not be empty", value)
  end
  local maximum = options.max_bytes or M.limits.text_bytes
  if #value > maximum then
    return M.add_error(context, "SCHEMA_STRING_LIMIT", path, "exceeds the " .. maximum .. " byte limit", value)
  end
  if has_disallowed_control(value, options.allow_lines) then
    return M.add_error(context, "SCHEMA_STRING_CONTROL", path, "contains a disallowed control character", value)
  end
  return value
end

---Validate a standalone value against the same text contract used by plan
---fields. This keeps configuration-supplied labels safe before they enter a
---model or renderer.
function M.validate_text(value, options)
  options = options or {}
  local context = M.new_context()
  local normalized = M.text(context, value, options.path or "$", options)
  return normalized, context.errors[1]
end

function M.object(context, value, path)
  if not json.is_object(value) then
    M.add_error(context, "SCHEMA_OBJECT", path, "must be a JSON object", value)
    return nil
  end
  return json.deep_copy(value)
end

function M.array(context, value, path)
  if not json.is_array(value) then
    M.add_error(context, "SCHEMA_ARRAY", path, "must be a JSON array", value)
    return nil
  end
  local count = 0
  local maximum = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
      M.add_error(context, "SCHEMA_ARRAY_KEY", path, "contains a non-array key", key)
      return nil
    end
    count = count + 1
    if key > maximum then
      maximum = key
    end
  end
  if count ~= maximum then
    M.add_error(context, "SCHEMA_ARRAY_SPARSE", path, "must not be sparse", value)
    return nil
  end
  return value
end

function M.enum(context, value, path, choices)
  if type(value) ~= "string" or not choices[value] then
    return M.add_error(context, "SCHEMA_ENUM", path, "has an unsupported value", value)
  end
  return value
end

function M.required(context, source, key, path)
  if source[key] == nil then
    M.add_error(context, "SCHEMA_REQUIRED", path .. "." .. key, "required field is missing")
    return nil
  end
  return source[key]
end

function M.tuple(context, value, path, length, item_normalizer)
  local source = M.array(context, value, path)
  if not source then
    return nil
  end
  if #source ~= length then
    M.add_error(context, "SCHEMA_TUPLE_LENGTH", path, "must contain exactly " .. length .. " items", value)
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

function M.normalize_metadata(context, value, path)
  local result = M.object(context, value, path)
  if not result then
    return nil
  end
  if result.name == nil then
    result.name = M.defaults.metadata.name
    M.mark_default(context, path .. ".name")
  else
    result.name = M.text(context, result.name, path .. ".name", { nonempty = true })
  end
  if result.notes == nil then
    result.notes = M.defaults.metadata.notes
    M.mark_default(context, path .. ".notes")
  else
    result.notes = M.text(context, result.notes, path .. ".notes", {
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

function M.normalize_settings(context, value, path)
  local result = M.object(context, value, path)
  if not result then
    return nil
  end
  local position = 1
  while position <= #SETTING_FIELDS do
    local key = SETTING_FIELDS[position]
    if result[key] == nil then
      result[key] = M.defaults.settings[key]
      M.mark_default(context, path .. "." .. key)
    else
      result[key] = M.integer(
        context,
        result[key],
        path .. "." .. key,
        1,
        M.limits.local_mm_max,
        M.limits.local_mm_max
      )
    end
    position = position + 1
  end
  return result
end

function M.normalize_id(context, value, path, kind)
  local id = M.text(context, value, path, { nonempty = true, max_bytes = 128 })
  if id == nil then
    return nil
  end
  local valid, err = ids.validate(id, kind)
  if not valid then
    M.add_error(context, err.code, path, err.message, id)
    return nil
  end
  return id
end

function M.coordinate(context, value, path)
  return M.integer(
    context,
    value,
    path,
    -(M.limits.coordinate_abs_exclusive - 1),
    M.limits.coordinate_abs_exclusive - 1,
    M.limits.coordinate_abs_exclusive - 1
  )
end

function M.dimension(context, value, path)
  return M.integer(context, value, path, 1, M.limits.local_mm_max, M.limits.local_mm_max)
end

function M.normalize_collection(context, source, path, normalizer)
  local values = M.array(context, source, path)
  if not values then
    return nil
  end
  if #values > M.limits.entity_count then
    M.add_error(
      context,
      "SCHEMA_ENTITY_LIMIT",
      path,
      "contains more than " .. M.limits.entity_count .. " entities",
      #values
    )
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

function M.validate_json_tree(context, value, path, active)
  local value_type = type(value)
  if value == json.null or value_type == "boolean" or json.is_decimal(value) then
    return
  end
  if value_type == "string" then
    local valid_utf8, invalid_position, invalid_message = json.valid_utf8(value)
    if not valid_utf8 then
      M.add_error(context, "SCHEMA_JSON_UTF8", path, invalid_message .. " at byte " .. invalid_position, value)
    end
    return
  end
  if value_type == "number" then
    if not M.is_safe_lua_integer(value) then
      M.add_error(context, "SCHEMA_JSON_NUMBER", path, "contains an unsafe or fractional untagged Lua number", value)
    end
    return
  end
  if value_type ~= "table" then
    M.add_error(context, "SCHEMA_JSON_TYPE", path, "contains a value that JSON cannot represent", value_type)
    return
  end
  if not json.is_object(value) and not json.is_array(value) then
    M.add_error(context, "SCHEMA_JSON_TABLE_TAG", path, "contains an untagged Lua table", value)
    return
  end
  if active[value] then
    M.add_error(context, "SCHEMA_JSON_CYCLE", path, "contains a cyclic table", value)
    return
  end
  active[value] = true
  for key, child in pairs(value) do
    local child_path = path .. "." .. tostring(key)
    if json.is_object(value) and type(key) ~= "string" then
      M.add_error(context, "SCHEMA_JSON_OBJECT_KEY", child_path, "object key must be a string", key)
    elseif json.is_object(value) then
      local valid_utf8, invalid_position, invalid_message = json.valid_utf8(key)
      if not valid_utf8 then
        M.add_error(context, "SCHEMA_JSON_UTF8", child_path, invalid_message .. " at key byte " .. invalid_position, key)
      end
    elseif json.is_array(value) and (type(key) ~= "number" or key < 1 or key ~= math.floor(key)) then
      M.add_error(context, "SCHEMA_JSON_ARRAY_KEY", child_path, "array key must be a positive integer", key)
    end
    M.validate_json_tree(context, child, child_path, active)
  end
  active[value] = nil
end

function M.result_or_error(context, result)
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

function M.document_version(document, current_version)
  if not json.is_object(document) then
    return nil, M.diagnostic("SCHEMA_ROOT", "$", "root JSON value must be an object")
  end
  if document.format ~= M.FORMAT then
    return nil, M.diagnostic(
      "SCHEMA_FORMAT",
      "$.format",
      "must be exactly '" .. M.FORMAT .. "'",
      document.format
    )
  end
  if document.schema_version == nil then
    return nil, M.diagnostic(
      "SCHEMA_VERSION_MISSING",
      "$.schema_version",
      "schema_version is required; unversioned documents are not guessed as v1"
    )
  end
  local version, reason = M.decimal_to_integer(document.schema_version, 1000000)
  if version == nil then
    return nil, M.diagnostic("SCHEMA_VERSION", "$.schema_version", reason, document.schema_version)
  end
  if version < 1 then
    return nil, M.diagnostic(
      "SCHEMA_VERSION",
      "$.schema_version",
      "schema version 0/missing has no implicit migration",
      version
    )
  end
  if version > current_version then
    return nil, M.diagnostic(
      "SCHEMA_FUTURE_VERSION",
      "$.schema_version",
      "schema version " .. version .. " is newer than supported version " .. current_version,
      version
    )
  end
  return version
end

return M
