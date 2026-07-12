-- Canonical RoomPlan model helpers. This module is pure Lua and treats model
-- snapshots as immutable by convention.

local json = require("roomplan.codec.json")
local schema = require("roomplan.schema")
local ids = require("roomplan.ids")

local M = {}

local COLLECTION_FOR_KIND = {
  room = "rooms",
  door = "doors",
  furniture = "furniture",
  custom_template = "custom_templates",
  template = "custom_templates",
}

local function copy_fields(fields)
  local result = json.object()
  if type(fields) == "table" then
    for key, value in pairs(fields) do
      result[key] = json.deep_copy(value)
    end
  end
  return result
end

local function tagged_tuple(values, defaults)
  local result = json.array()
  values = values or defaults or {}
  local position = 1
  while position <= #values do
    result[position] = values[position]
    position = position + 1
  end
  return result
end

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
    rooms = json.array(),
    doors = json.array(),
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

function M.new_room(fields)
  fields = fields or {}
  local result = copy_fields(fields)
  result.id = fields.id
  result.name = fields.name or "Room"
  result.origin_mm = tagged_tuple(fields.origin_mm, { 0, 0 })
  result.size_mm = tagged_tuple(fields.size_mm)
  return result
end

function M.new_door(fields)
  fields = fields or {}
  local result = copy_fields(fields)
  result.id = fields.id
  result.kind = fields.kind or "hinged"
  result.room_id = fields.room_id
  result.connects_to_room_id = fields.connects_to_room_id == nil and json.null or fields.connects_to_room_id
  result.side = fields.side
  result.offset_mm = fields.offset_mm or 0
  result.width_mm = fields.width_mm
  result.hinge = fields.hinge or "start"
  local has_connection = fields.connects_to_room_id ~= nil and not json.is_null(fields.connects_to_room_id)
  result.opens_into = fields.opens_into or (has_connection and "connected" or "owner")
  result.open_angle_deg = fields.open_angle_deg or 90
  return result
end

function M.new_furniture(fields)
  fields = fields or {}
  local result = copy_fields(fields)
  result.id = fields.id
  result.room_id = fields.room_id
  result.template_id = fields.template_id or "builtin:custom-rectangle"
  result.name = fields.name or "Furniture"
  result.category = fields.category or "custom"
  result.center_mm = tagged_tuple(fields.center_mm, { 0, 0 })
  result.size_mm = tagged_tuple(fields.size_mm)
  result.rotation_deg = fields.rotation_deg or 0
  return result
end

function M.new_custom_template(fields)
  fields = fields or {}
  local result = copy_fields(fields)
  result.id = fields.id
  result.name = fields.name or "Custom furniture"
  result.category = fields.category or "custom"
  result.shape = fields.shape or "rectangle"
  result.default_size_mm = tagged_tuple(fields.default_size_mm)
  return result
end

function M.collection_name(kind)
  return COLLECTION_FOR_KIND[kind]
end

function M.index(model)
  return ids.index(model)
end

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

-- Append/replace/remove helpers return fresh complete models. Focused action
-- modules still own policy and final structural/layout validation.
function M.append(model, kind, entity)
  local collection_name = COLLECTION_FOR_KIND[kind]
  if not collection_name or type(model[collection_name]) ~= "table" then
    return nil, { code = "MODEL_KIND", message = "unknown model entity kind", kind = kind }
  end
  local result = json.deep_copy(model)
  result[collection_name][#result[collection_name] + 1] = json.deep_copy(entity)
  return result
end

function M.replace(model, kind, id, entity)
  local _, position, collection_name = M.find(model, kind, id)
  if not position then
    return nil, { code = "MODEL_NOT_FOUND", message = "entity was not found", kind = kind, id = id }
  end
  if entity.id ~= id then
    return nil, { code = "MODEL_ID_IMMUTABLE", message = "replacement cannot change an entity ID", kind = kind, id = id }
  end
  local result = json.deep_copy(model)
  result[collection_name][position] = json.deep_copy(entity)
  return result
end

function M.remove(model, kind, id)
  local _, position, collection_name = M.find(model, kind, id)
  if not position then
    return nil, { code = "MODEL_NOT_FOUND", message = "entity was not found", kind = kind, id = id }
  end
  local result = json.deep_copy(model)
  table.remove(result[collection_name], position)
  return result
end

function M.normalize(document)
  return schema.load(document)
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
