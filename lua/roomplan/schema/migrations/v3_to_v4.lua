-- Schema v4 distinguishes wall outlets from room-local floor outlets.
-- Existing v3 outlets are wall outlets by definition, so migration only adds
-- the discriminator and preserves every other tagged field byte-semantically.

local json = require("roomplan.codec.json")

local M = {}

function M.migrate(document)
  local result = json.deep_copy(document)
  for index, outlet in ipairs(result.outlets or {}) do
    if rawget(outlet, "placement") ~= nil then
      local path = "$.outlets[" .. index .. "].placement"
      local diagnostic = {
        code = "SCHEMA_MIGRATION_COLLISION",
        path = path,
        message = "schema v3 extension data collides with the generated schema-v4 field 'placement'",
        value = outlet.placement,
      }
      return nil,
        {
          code = diagnostic.code,
          path = diagnostic.path,
          message = diagnostic.message,
          diagnostics = { diagnostic },
        }
    end
    outlet.placement = "wall"
  end
  result.schema_version = 4
  return result,
    {
      {
        code = "SCHEMA_MIGRATED_V3_TO_V4",
        path = "$.outlets",
        message = "classified existing outlets as wall outlets",
      },
    }
end

return M
