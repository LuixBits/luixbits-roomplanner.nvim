local base_document = require("roomplan.schema.v3.document")
local entities = require("roomplan.schema.v4.entities")

local M = {}

function M.normalize(document)
  return base_document.normalize_with(document, 4, entities)
end

return M
