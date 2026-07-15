-- Single authority for transient canvas-detail levels.

local M = {}

M.default = "middle"
M.levels = { "high", "middle", "none" }

local valid = { high = true, middle = true, none = true }
local descriptions = {
  high = "all dimensions",
  middle = "wall dimensions",
  none = "labels and dimensions hidden",
}

function M.valid(value)
  return valid[value] == true
end

function M.normalize(value)
  if type(value) ~= "string" then return nil end
  value = value:lower()
  return valid[value] and value or nil
end

function M.next(value)
  value = M.normalize(value) or M.default
  for index, level in ipairs(M.levels) do
    if level == value then return M.levels[index % #M.levels + 1] end
  end
  return M.default
end

function M.description(value)
  return descriptions[M.normalize(value) or M.default]
end

return M
