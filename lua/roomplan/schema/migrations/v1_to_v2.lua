-- Deterministic schema-v1 to schema-v2 geometry migration.
--
-- The dispatcher normalizes v1 before calling this module. We still produce a
-- fresh tagged JSON tree so callers keep ownership of the source snapshot.

local json = require("roomplan.codec.json")

local M = {}

local function failure(path, message, value)
  local diagnostic = {
    code = "SCHEMA_MIGRATION_COLLISION",
    path = path,
    message = message,
    value = value,
  }
  return nil, {
    code = diagnostic.code,
    path = diagnostic.path,
    message = diagnostic.message,
    diagnostics = { diagnostic },
  }
end

local function reject_generated_fields(entity, path, fields)
  for _, field in ipairs(fields) do
    if rawget(entity, field) ~= nil then
      return failure(
        path .. "." .. field,
        "schema v1 extension data collides with the generated schema-v2 field '" .. field .. "'",
        entity[field]
      )
    end
  end
  return true
end

local function rectangle_footprint(width, depth)
  return json.object({
    kind = "rect_union",
    parts = json.array({
      json.object({
        id = "part-main",
        origin_mm = json.array({ 0, 0 }),
        size_mm = json.array({ width, depth }),
      }),
    }),
  })
end

local function migrate_rooms(document)
  for index, room in ipairs(document.rooms) do
    local path = "$.rooms[" .. index .. "]"
    local ok, err = reject_generated_fields(room, path, { "footprint" })
    if not ok then return nil, err end
    room.footprint = rectangle_footprint(room.size_mm[1], room.size_mm[2])
    room.size_mm = nil
  end
  return true
end

local function migrate_doors(document)
  for index, door in ipairs(document.doors) do
    local path = "$.doors[" .. index .. "]"
    local ok, err = reject_generated_fields(door, path, { "part_id" })
    if not ok then return nil, err end
    door.part_id = "part-main"
  end
  return true
end

local function migrate_furniture(document)
  local generated = { "position_mm", "anchor2_mm", "footprint", "height_mm" }
  for index, item in ipairs(document.furniture) do
    local path = "$.furniture[" .. index .. "]"
    local ok, err = reject_generated_fields(item, path, generated)
    if not ok then return nil, err end
    local width, depth, height = item.size_mm[1], item.size_mm[2], item.size_mm[3]
    item.position_mm = json.deep_copy(item.center_mm)
    item.anchor2_mm = json.array({ width, depth })
    item.footprint = rectangle_footprint(width, depth)
    item.height_mm = height
    item.center_mm = nil
    item.size_mm = nil
  end
  return true
end

local function migrate_templates(document)
  local generated = { "default_footprint", "default_anchor2_mm", "default_height_mm" }
  for index, template in ipairs(document.custom_templates) do
    local path = "$.custom_templates[" .. index .. "]"
    local ok, err = reject_generated_fields(template, path, generated)
    if not ok then return nil, err end
    local width = template.default_size_mm[1]
    local depth = template.default_size_mm[2]
    template.default_footprint = rectangle_footprint(width, depth)
    template.default_anchor2_mm = json.array({ width, depth })
    template.default_height_mm = template.default_size_mm[3]
    template.shape = nil
    template.default_size_mm = nil
  end
  return true
end

function M.migrate(document)
  local result = json.deep_copy(document)
  local ok, err = migrate_rooms(result)
  if not ok then return nil, err end
  ok, err = migrate_doors(result)
  if not ok then return nil, err end
  ok, err = migrate_furniture(result)
  if not ok then return nil, err end
  ok, err = migrate_templates(result)
  if not ok then return nil, err end
  result.schema_version = 2
  return result, {
    {
      code = "SCHEMA_MIGRATED_V1_TO_V2",
      path = "$",
      message = "converted rectangular v1 geometry to canonical one-part v2 footprints",
    },
  }
end

return M
