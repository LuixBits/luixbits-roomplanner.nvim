local geometry = require("roomplan.geometry.footprint")
local common = require("roomplan.ui.forms.common")

local M = {}

local function grid(shape, bounds)
  local columns, rows = 28, 7
  local result = { "+" .. string.rep("-", columns) .. "+" }
  for row = 1, rows do
    local cells = {}
    local y2 = bounds.top2 - (row - 0.5) * bounds.depth2 / rows
    for column = 1, columns do
      local x2 = bounds.left2 + (column - 0.5) * bounds.width2 / columns
      local hits = geometry.hit_test2(shape, x2, y2, { include_boundary = false }) or {}
      cells[column] = hits[1] and "#" or " "
    end
    result[#result + 1] = "|" .. table.concat(cells) .. "|"
  end
  result[#result + 1] = "+" .. string.rep("-", columns) .. "+"
  return result
end

function M.edit(resolve_footprint)
  return function(draft)
    local footprint, preset_error = resolve_footprint(draft)
    if not footprint then return nil, preset_error end

    local shape, shape_error = geometry.from_persisted(footprint)
    if not shape then return nil, shape_error end
    local bounds = assert(geometry.bounds2(shape))
    local area = assert(geometry.area(shape))
    local lines = {
      "Origin " .. common.point_text({ draft.origin_x_mm, draft.origin_y_mm }),
      string.format("%g x %g mm · %.2f m²", bounds.width2 / 2, bounds.depth2 / 2, area / 1000000),
    }
    for _, line in ipairs(grid(shape, bounds)) do lines[#lines + 1] = line end
    return { lines = lines }
  end
end

return M
