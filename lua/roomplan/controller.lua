-- Stable public controller facade. Cohesive implementation modules attach their
-- methods to this table without requiring the facade back, which keeps module
-- dependencies acyclic while preserving the established controller API.
local M = {}

local modules = {
  "roomplan.controller.source",
  "roomplan.controller.persistence",
  "roomplan.controller.view",
  "roomplan.controller.edit",
  "roomplan.controller.shape",
  "roomplan.controller.sun",
}

for _, name in ipairs(modules) do
  require(name).attach(M)
end

return M
