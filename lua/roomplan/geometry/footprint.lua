-- Public rectilinear-footprint facade.
--
-- Footprints use doubled millimetres so odd-sized, centre-anchored furniture
-- keeps exact half-millimetre edges without floating-point drift. Persisted
-- schema-v1 entities remain unchanged; adapters derive their footprint at the
-- geometry boundary.

local M = {}

local modules = {
  require("roomplan.geometry.footprint.core"),
  require("roomplan.geometry.footprint.transforms"),
  require("roomplan.geometry.footprint.adapters"),
  require("roomplan.geometry.footprint.metrics"),
  require("roomplan.geometry.footprint.relations"),
}

for _, module in ipairs(modules) do
  for name, value in pairs(module) do
    if name ~= "_internal" then
      assert(M[name] == nil, "duplicate footprint export " .. tostring(name))
      M[name] = value
    end
  end
end

return M
