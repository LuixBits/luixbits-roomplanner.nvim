-- Dependency-free built-in furniture catalogue.
-- Values are generic planning seeds, never manufacturer specifications.

local M = {}
local json = require("roomplan.codec.json")
local v2_adapter = require("roomplan.catalog.v2_adapter")

local BUILTINS = {
  { id = "builtin:bed", name = "Bed", category = "sleeping", default_size_mm = { 2000, 1600, 500 }, shape = "rectangle" },
  { id = "builtin:sofa", name = "Sofa", category = "seating", default_size_mm = { 2100, 900, 850 }, shape = "rectangle" },
  { id = "builtin:armchair", name = "Armchair", category = "seating", default_size_mm = { 900, 900, 900 }, shape = "rectangle" },
  { id = "builtin:table", name = "Table", category = "dining", default_size_mm = { 1600, 900, 750 }, shape = "rectangle" },
  { id = "builtin:chair", name = "Chair", category = "seating", default_size_mm = { 500, 500, 900 }, shape = "rectangle" },
  { id = "builtin:desk", name = "Desk", category = "work", default_size_mm = { 1400, 700, 750 }, shape = "rectangle" },
  { id = "builtin:wardrobe", name = "Wardrobe", category = "storage", default_size_mm = { 1200, 600, 2000 }, shape = "rectangle" },
  { id = "builtin:bookcase", name = "Bookcase/shelf", category = "storage", default_size_mm = { 900, 300, 1800 }, shape = "rectangle" },
  { id = "builtin:cabinet", name = "Cabinet", category = "storage", default_size_mm = { 800, 450, 900 }, shape = "rectangle" },
  { id = "builtin:kitchen-unit", name = "Kitchen unit", category = "kitchen", default_size_mm = { 600, 600, 900 }, shape = "rectangle" },
  { id = "builtin:appliance", name = "Appliance", category = "appliance", default_size_mm = { 600, 600, 850 }, shape = "rectangle" },
  { id = "builtin:bathroom-fixture", name = "Bathroom fixture", category = "bathroom", default_size_mm = { 700, 400, 850 }, shape = "rectangle" },
  { id = "builtin:custom-rectangle", name = "Custom rectangle", category = "custom", default_size_mm = { 1000, 1000, 1000 }, shape = "rectangle" },
}

local BY_ID = {}
local index = 1
while index <= #BUILTINS do
  BY_ID[BUILTINS[index].id] = BUILTINS[index]
  index = index + 1
end

local imported = {}
local imported_by_id = {}
local include_builtins = true

local function copy_template(template, schema_version)
  if not template then
    return nil
  end
  schema_version = schema_version or 1
  if schema_version >= 2 then
    local result
    if template.default_footprint ~= nil then
      result = json.deep_copy(template)
    else
      result = assert(v2_adapter.from_catalog_v1(template))
    end
    result.builtin = template.id:sub(1, 8) == "builtin:"
    return result
  end
  return {
    id = template.id,
    name = template.name,
    category = template.category,
    shape = template.shape,
    default_size_mm = {
      template.default_size_mm[1],
      template.default_size_mm[2],
      template.default_size_mm[3],
    },
    builtin = template.id:sub(1, 8) == "builtin:",
  }
end

---Return the visible process catalogue, optionally merged with a plan's local
---templates. Plan-local custom IDs replace imported defaults. Built-ins stay
---resolvable for existing plans even when configuration hides them here.
function M.all(model)
  local schema_version = type(model) == "table" and model.schema_version or 1
  local local_templates = type(model) == "table" and model.custom_templates or {}
  local local_by_id = {}
  for position = 1, #local_templates do
    local_by_id[local_templates[position].id] = true
  end
  local result = {}
  local position = 1
  if include_builtins then
    while position <= #BUILTINS do
      result[position] = copy_template(BUILTINS[position], schema_version)
      position = position + 1
    end
  end
  position = 1
  while position <= #imported do
    if not local_by_id[imported[position].id] then
      result[#result + 1] = copy_template(imported[position], schema_version)
    end
    position = position + 1
  end
  position = 1
  while position <= #local_templates do
    if not BY_ID[local_templates[position].id] then
      result[#result + 1] = copy_template(local_templates[position], schema_version)
    end
    position = position + 1
  end
  return result
end

function M.get(id)
  return copy_template(BY_ID[id] or imported_by_id[id])
end

function M.exists(id)
  return BY_ID[id] ~= nil or imported_by_id[id] ~= nil
end

function M.categories()
  local seen = {}
  local result = {}
  local position = 1
  if include_builtins then
    while position <= #BUILTINS do
      local category = BUILTINS[position].category
      if not seen[category] then
        seen[category] = true
        result[#result + 1] = category
      end
      position = position + 1
    end
  end
  position = 1
  while position <= #imported do
    local category = imported[position].category
    if not seen[category] then
      seen[category] = true
      result[#result + 1] = category
    end
    position = position + 1
  end
  table.sort(result)
  return result
end

-- Resolve a built-in or plan-local template without retaining a mutable
-- reference to the model.
function M.resolve(model, id)
  if id == nil and type(model) == "string" then
    id, model = model, nil
  end
  local builtin = BY_ID[id]
  if builtin then
    return copy_template(builtin, type(model) == "table" and model.schema_version or 1)
  end
  if type(model) == "table" and type(model.custom_templates) == "table" then
    local position = 1
    while position <= #model.custom_templates do
      local template = model.custom_templates[position]
      if template.id == id then
        return copy_template(template, model.schema_version or 1)
      end
      position = position + 1
    end
  end
  return copy_template(imported_by_id[id], type(model) == "table" and model.schema_version or 1)
end

-- Replace only the user-supplied portion of the process-local catalogue.
-- Validation and file loading complete before state is swapped, so a failed
-- setup leaves the prior effective catalogue intact.
function M.configure(options, limits)
  local loaded, errors = require("roomplan.catalog.import").load(
    options,
    limits and limits.max_dimension_mm or nil
  )
  if not loaded then return nil, errors end
  local index = {}
  for position = 1, #loaded do index[loaded[position].id] = loaded[position] end
  imported = loaded
  imported_by_id = index
  include_builtins = options.include_builtins ~= false
  return true
end

function M.reset()
  imported = {}
  imported_by_id = {}
  include_builtins = true
end

return M
