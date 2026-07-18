-- Canonical RoomPlan model helpers. This module is pure Lua and treats model
-- snapshots as immutable by convention.

local json = require("roomplan.codec.json")
local entities = require("roomplan.model.entities")
local schema = require("roomplan.schema")

local M = {}

local COLLECTION_FOR_KIND = {
  room = "rooms",
  door = "doors",
  window = "windows",
  outlet = "outlets",
  furniture = "furniture",
  template = "custom_templates",
}

function M.deep_copy(value)
  return json.deep_copy(value)
end

function M.deep_equal(left, right)
  return json.deep_equal(left, right)
end

function M.new(options)
  options = options or {}
  local metadata_options = options.metadata or {}
  local settings_options = options.settings or {}
  local metadata = json.object({
    name = options.name or metadata_options.name or schema.defaults.metadata.name,
    notes = options.notes or metadata_options.notes or schema.defaults.metadata.notes,
  })
  for key, value in pairs(metadata_options) do
    if key ~= "name" and key ~= "notes" then
      metadata[key] = json.deep_copy(value)
    end
  end
  local settings = json.object()
  for key, default in pairs(schema.defaults.settings) do
    settings[key] = settings_options[key] == nil and default or settings_options[key]
  end
  for key, value in pairs(settings_options) do
    if settings[key] == nil then
      settings[key] = json.deep_copy(value)
    end
  end
  local extensions = options.extensions
  if extensions == nil then
    extensions = json.object()
  elseif json.is_object(extensions) then
    extensions = json.deep_copy(extensions)
  else
    return nil, { code = "MODEL_EXTENSIONS", path = "$.extensions", message = "new-plan extensions must be a tagged JSON object" }
  end
  local document = json.object({
    format = schema.FORMAT,
    schema_version = schema.CURRENT_VERSION,
    units = "mm",
    metadata = metadata,
    settings = settings,
    site = options.site and json.deep_copy(options.site) or nil,
    rooms = json.array(),
    doors = json.array(),
    windows = json.array(),
    outlets = json.array(),
    furniture = json.array(),
    custom_templates = json.array(),
    extensions = extensions,
  })
  local normalized, info_or_error = schema.normalize(document)
  if not normalized then
    return nil, info_or_error
  end
  return normalized, info_or_error
end

function M.new_room(fields, options)
  return entities.room(fields, options and options.schema_version or schema.CURRENT_VERSION)
end

function M.new_door(fields, options)
  return entities.door(fields, options and options.schema_version or schema.CURRENT_VERSION)
end

function M.new_window(fields, options)
  return entities.window(fields, options and options.schema_version or schema.CURRENT_VERSION)
end

function M.new_outlet(fields, options)
  return entities.outlet(fields, options and options.schema_version or schema.CURRENT_VERSION)
end

function M.new_furniture(fields, options)
  return entities.furniture(fields, options and options.schema_version or schema.CURRENT_VERSION)
end

function M.new_custom_template(fields, options)
  return entities.template(fields, options and options.schema_version or schema.CURRENT_VERSION)
end

M.rectangle_footprint = entities.rectangle_footprint

function M.find(model, kind, id)
  local collection_name = COLLECTION_FOR_KIND[kind]
  if not collection_name or type(model) ~= "table" then
    return nil
  end
  local collection = model[collection_name]
  if type(collection) ~= "table" then
    return nil
  end
  local position = 1
  while position <= #collection do
    if collection[position].id == id then
      return collection[position], position, collection_name
    end
    position = position + 1
  end
  return nil
end

function M.decode(text, options)
  return schema.decode(text, options)
end

function M.encode(model, options)
  return schema.encode(model, options)
end

-- Cycle-safe deterministic estimate used for history budgets. It intentionally
-- estimates retained Lua memory rather than claiming allocator-exact bytes.
function M.estimate_size(value)
  local seen = {}
  local function estimate(current)
    local value_type = type(current)
    if value_type == "nil" then
      return 0
    elseif value_type == "boolean" then
      return 1
    elseif value_type == "number" then
      return 8
    elseif value_type == "string" then
      return 16 + #current
    elseif value_type ~= "table" then
      return 16
    end
    if seen[current] then
      return 0
    end
    seen[current] = true
    if current == json.null then
      return 8
    elseif json.is_decimal(current) then
      return 32 + #current.coefficient
    end
    local size = 40
    local keys = {}
    for key in pairs(current) do
      keys[#keys + 1] = key
    end
    table.sort(keys, function(left, right)
      local left_type, right_type = type(left), type(right)
      if left_type == right_type then
        return tostring(left) < tostring(right)
      end
      return left_type < right_type
    end)
    local position = 1
    while position <= #keys do
      local key = keys[position]
      size = size + 16 + estimate(key) + estimate(current[key])
      position = position + 1
    end
    return size
  end
  return estimate(value)
end

return M
