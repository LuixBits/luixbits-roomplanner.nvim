-- Dependency-free built-in furniture catalogue.
-- Values are generic planning seeds, never manufacturer specifications.

local M = {}

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

local function copy_template(template)
  if not template then
    return nil
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

function M.all()
  local result = {}
  local position = 1
  while position <= #BUILTINS do
    result[position] = copy_template(BUILTINS[position])
    position = position + 1
  end
  return result
end

function M.get(id)
  return copy_template(BY_ID[id])
end

function M.exists(id)
  return BY_ID[id] ~= nil
end

function M.categories()
  local seen = {}
  local result = {}
  local position = 1
  while position <= #BUILTINS do
    local category = BUILTINS[position].category
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
  local builtin = BY_ID[id]
  if builtin then
    return copy_template(builtin)
  end
  if type(model) == "table" and type(model.custom_templates) == "table" then
    local position = 1
    while position <= #model.custom_templates do
      local template = model.custom_templates[position]
      if template.id == id then
        return copy_template(template)
      end
      position = position + 1
    end
  end
  return nil
end

return M
