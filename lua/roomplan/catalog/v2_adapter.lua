-- Pure conversion from the public external catalogue-v1 rectangle contract to
-- the compound project-template shape introduced by schema v2 and retained by
-- later schemas.

local json = require("roomplan.codec.json")
local ids = require("roomplan.ids")
local schema_common = require("roomplan.schema.common")

local M = {}

local function failure(path, message, value)
  return nil, {
    code = "CATALOG_V1_CONVERSION",
    path = path,
    message = message,
    value = value,
  }
end

local function positive_integer(value)
  return type(value) == "number"
    and value == math.floor(value)
    and value > 0
    and value <= schema_common.limits.local_mm_max
end

local function dimensions(value)
  if type(value) ~= "table" then return failure("$.default_size_mm", "must contain [width, depth, height]", value) end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
      return failure("$.default_size_mm", "must be a dense three-item array", value)
    end
    count = count + 1
  end
  if count ~= 3 or value[1] == nil or value[2] == nil or value[3] == nil then
    return failure("$.default_size_mm", "must contain exactly [width, depth, height]", value)
  end
  for index = 1, 3 do
    if not positive_integer(value[index]) then
      return failure(string.format("$.default_size_mm[%d]", index), "must be a positive exact integer", value[index])
    end
  end
  return value[1], value[2], value[3]
end

local function convert(definition, validate_id)
  if type(definition) ~= "table" then return failure("$", "catalogue definition must be an object", definition) end
  local valid_id, id_error = validate_id(definition.id)
  if not valid_id then return failure("$.id", id_error.message, definition.id) end
  local name, name_error = schema_common.validate_text(definition.name, {
    path = "$.name",
    nonempty = true,
  })
  if not name then return failure("$.name", name_error.message, definition.name) end
  local category, category_error = schema_common.validate_text(definition.category, {
    path = "$.category",
    nonempty = true,
  })
  if not category then return failure("$.category", category_error.message, definition.category) end
  if definition.shape ~= nil and definition.shape ~= "rectangle" then
    return failure("$.shape", "external catalogue v1 supports only rectangle", definition.shape)
  end

  local width, depth_or_error, height = dimensions(definition.default_size_mm)
  if width == nil then return nil, depth_or_error end
  local depth = depth_or_error

  return json.object({
    id = definition.id,
    name = name,
    category = category,
    default_footprint = json.object({
      kind = "rect_union",
      parts = json.array({
        json.object({
          id = "part-main",
          origin_mm = json.array({ 0, 0 }),
          size_mm = json.array({ width, depth }),
        }),
      }),
    }),
    -- Anchors use doubled local millimetres. [width, depth] is the exact centre
    -- of a [0, 0] -> [width, depth] rectangle, including odd dimensions.
    default_anchor2_mm = json.array({ width, depth }),
    default_height_mm = height,
  })
end

---Convert one external catalogue-v1 rectangle definition into a fresh tagged
---JSON tree matching the schema-v2 custom-template geometry authority.
---@param definition table
---@return table|nil template
---@return table|nil error
function M.from_external_v1(definition)
  return convert(definition, function(id) return ids.validate(id, "custom_template") end)
end

---Convert any trusted process-catalogue rectangle, including built-ins. User
---definitions still enter through from_external_v1 and retain the custom-ID
---contract; this wider helper is only the internal v2 view boundary.
function M.from_catalog_v1(definition) return convert(definition, ids.valid_template_reference) end

return M
