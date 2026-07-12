local common = require("roomplan.ui.panels.common")

local M = {}

function M.render(width, height)
  local card = {
    "Empty floor plan",
    "",
    "No rooms yet.",
    "[a] Add first room    [?] Help    [q] Hide",
    "",
    "Measurements accept mm, cm, and m.",
  }
  local top = math.max(0, math.floor((height - #card) / 2))
  local lines = {}
  for _ = 1, top do lines[#lines + 1] = "" end
  for _, line in ipairs(card) do lines[#lines + 1] = common.center(line, width) end
  return { lines = common.fit(lines, width, height) }
end

return M
