-- Deterministic schema-v2 to schema-v3 wall-feature migration.
--
-- Schema v2 allowed unknown root members, so generated collection names must
-- never overwrite extension data that happened to use the same names.

local json = require("roomplan.codec.json")

local M = {}

local function collision(path, field, value)
  local diagnostic = {
    code = "SCHEMA_MIGRATION_COLLISION",
    path = path .. "." .. field,
    message = "schema v2 extension data collides with the generated schema-v3 field '" .. field .. "'",
    value = value,
  }
  return nil,
    {
      code = diagnostic.code,
      path = diagnostic.path,
      message = diagnostic.message,
      diagnostics = { diagnostic },
    }
end

function M.migrate(document)
  local result = json.deep_copy(document)
  for _, field in ipairs({ "windows", "outlets" }) do
    if rawget(result, field) ~= nil then return collision("$", field, result[field]) end
  end
  result.windows = json.array()
  result.outlets = json.array()
  result.schema_version = 3
  return result,
    {
      {
        code = "SCHEMA_MIGRATED_V2_TO_V3",
        path = "$",
        message = "initialized canonical window and outlet collections",
      },
    }
end

return M
