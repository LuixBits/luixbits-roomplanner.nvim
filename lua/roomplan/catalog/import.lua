local json = require("roomplan.codec.json")
local ids = require("roomplan.ids")
local schema = require("roomplan.schema")
local source = require("roomplan.storage.source")

local M = {}

local MAX_CATALOG_BYTES = 1024 * 1024
local ALLOWED_DEFINITION_KEYS = {
  id = true,
  name = true,
  category = true,
  shape = true,
  default_size_mm = true,
}
local ALLOWED_DOCUMENT_KEYS = { version = true, furniture = true }

local function append(errors, path, message)
  errors[#errors + 1] = path .. ": " .. message
end

local function is_dense_list(value)
  if type(value) ~= "table" then return false end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then return false end
    count = count + 1
  end
  return count == #value
end

local function nonempty_string(value)
  return type(value) == "string" and value:match("%S") ~= nil
end

local function safe_label(value, path, errors)
  if not nonempty_string(value) then
    append(errors, path, "expected a non-empty string")
    return nil
  end
  local normalized, err = schema.validate_text(value, { nonempty = true, path = path })
  if not normalized then
    append(errors, path, err.message)
    return nil
  end
  return normalized
end

local function positive_integer(value, maximum)
  if type(value) == "number" then
    if value == math.floor(value) and value >= 1 and value <= maximum then return value end
    return nil
  end
  if not json.is_decimal(value) then return nil end
  local sign, coefficient, exponent = json.decimal_parts(value)
  if sign < 0 or exponent < 0 then return nil end
  local result = 0
  for index = 1, #coefficient do
    result = result * 10 + coefficient:byte(index) - 48
    if result > maximum then return nil end
  end
  if result < 1 then return nil end
  for _ = 1, exponent do
    if result > math.floor(maximum / 10) then return nil end
    result = result * 10
  end
  return result >= 1 and result or nil
end

local function normalize_definition(value, path, max_dimension_mm, errors)
  local initial_error_count = #errors
  if type(value) ~= "table" then
    append(errors, path, "expected an object")
    return nil
  end
  for key in pairs(value) do
    if not ALLOWED_DEFINITION_KEYS[key] then append(errors, path .. "." .. tostring(key), "unknown field") end
  end

  if not nonempty_string(value.id) then
    append(errors, path .. ".id", "expected a non-empty string")
  else
    local valid, err = ids.valid_template_reference(value.id)
    if not valid then append(errors, path .. ".id", err.message) end
    if value.id:sub(1, 8) == "builtin:" then
      append(errors, path .. ".id", "imported furniture cannot replace built-in templates; use a custom: ID")
    end
  end
  local name = safe_label(value.name, path .. ".name", errors)
  local category = safe_label(value.category, path .. ".category", errors)

  local shape = value.shape or "rectangle"
  if shape ~= "rectangle" then append(errors, path .. ".shape", "only rectangle is currently supported") end

  local size = value.default_size_mm
  local normalized_size = {}
  if not is_dense_list(size) or #size ~= 3 then
    append(errors, path .. ".default_size_mm", "expected [width, depth, height]")
  else
    for index = 1, 3 do
      local dimension = positive_integer(size[index], max_dimension_mm)
      if not dimension then
        append(errors, string.format("%s.default_size_mm[%d]", path, index),
          "expected a positive integer no greater than " .. max_dimension_mm)
      else
        normalized_size[index] = dimension
      end
    end
  end

  if #errors > initial_error_count then return nil end
  return {
    id = value.id,
    name = name,
    category = category,
    shape = shape,
    default_size_mm = normalized_size,
  }
end

local function read_document(path, errors)
  local expanded = vim.fn.expand(path)
  local bytes, read_err = source.read_file(expanded, { max_bytes = MAX_CATALOG_BYTES })
  if not bytes then
    local message = read_err and read_err.code == "SOURCE_SIZE_LIMIT"
        and (expanded .. " exceeds the 1 MiB catalog limit")
      or ((read_err and read_err.message) or ("could not read " .. expanded))
    append(errors, "furniture.files", message)
    return nil
  end
  local document, decode_err = json.decode(bytes, { max_bytes = MAX_CATALOG_BYTES })
  if not document then
    local location = decode_err.line and string.format(" at line %d, column %d", decode_err.line, decode_err.column) or ""
    append(errors, "furniture.files", string.format("%s: %s%s", expanded, decode_err.message, location))
    return nil
  end
  if not json.is_object(document) then
    append(errors, "furniture.files", expanded .. ": expected a JSON object")
    return nil
  end
  for key in pairs(document) do
    if not ALLOWED_DOCUMENT_KEYS[key] then append(errors, "furniture.files", expanded .. ": unknown field " .. tostring(key)) end
  end
  if positive_integer(document.version, 1) ~= 1 then
    append(errors, "furniture.files", expanded .. ": version must be 1")
  end
  if not json.is_array(document.furniture) then
    append(errors, "furniture.files", expanded .. ": furniture must be a JSON array")
    return nil
  end
  return document.furniture, expanded
end

function M.load(options, max_dimension_mm)
  options = options or {}
  max_dimension_mm = max_dimension_mm or 100000
  local errors = {}
  local definitions = options.definitions
  local files = options.files
  if not is_dense_list(definitions) then append(errors, "furniture.definitions", "expected a list") end
  if not is_dense_list(files) then append(errors, "furniture.files", "expected a list") end
  if #errors > 0 then return nil, errors end

  local sources = { { values = definitions, path = "furniture.definitions" } }
  for index, path in ipairs(files) do
    if not nonempty_string(path) then
      append(errors, string.format("furniture.files[%d]", index), "expected a non-empty path string")
    else
      local values, expanded = read_document(path, errors)
      if values then sources[#sources + 1] = { values = values, path = expanded .. ".furniture" } end
    end
  end

  local result, seen = {}, {}
  for _, catalog_source in ipairs(sources) do
    for index, value in ipairs(catalog_source.values) do
      local before = #errors
      local path = string.format("%s[%d]", catalog_source.path, index)
      local normalized = normalize_definition(value, path, max_dimension_mm, errors)
      if normalized and #errors == before then
        if seen[normalized.id] then
          append(errors, path .. ".id", "duplicate imported template ID " .. normalized.id)
        else
          seen[normalized.id] = true
          result[#result + 1] = normalized
        end
      end
    end
  end
  if options.include_builtins == false and #result == 0 then
    append(errors, "furniture", "include_builtins=false requires at least one imported definition")
  end
  if #errors > 0 then return nil, errors end
  return result
end

return M
