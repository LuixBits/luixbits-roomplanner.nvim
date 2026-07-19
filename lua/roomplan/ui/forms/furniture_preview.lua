-- Compact, presentation-only furniture silhouette for structured forms.
-- It uses the same exact footprint adapter as the main canvas, then samples
-- that geometry into a bounded one-cell grid suitable for a side float.

local footprint = require("roomplan.geometry.footprint")

local M = {}

local function rounded(value)
  return math.max(1, math.floor(value + 0.5))
end

local function grid(shape, bounds, opts)
  opts = opts or {}
  local max_columns = math.max(8, math.floor(opts.columns or 26))
  local max_rows = math.max(3, math.floor(opts.rows or 9))
  -- Terminal cells are normally about twice as tall as they are wide. Account
  -- for that so a square footprint reads as square instead of as a flat bar.
  local scale = math.min(max_columns / bounds.width2, (max_rows * 2) / bounds.depth2)
  local columns = math.min(max_columns, math.max(2, rounded(bounds.width2 * scale)))
  local rows = math.min(max_rows, math.max(2, rounded(bounds.depth2 * scale / 2)))
  local lines = { "+" .. string.rep("-", columns) .. "+" }
  for row = 1, rows do
    local cells = {}
    local y2 = bounds.top2 - (row - 0.5) * bounds.depth2 / rows
    for column = 1, columns do
      local x2 = bounds.left2 + (column - 0.5) * bounds.width2 / columns
      local hits = footprint.hit_test2(shape, x2, y2, { include_boundary = false }) or {}
      cells[column] = hits[1] and "#" or " "
    end
    lines[#lines + 1] = "|" .. table.concat(cells) .. "|"
  end
  lines[#lines + 1] = "+" .. string.rep("-", columns) .. "+"
  return lines
end

function M.render(furniture, opts)
  local shape, err = footprint.from_furniture({ origin_mm = { 0, 0 } }, furniture, {
    rotation_fallback = 0,
  })
  if not shape then return nil, err end
  local bounds = footprint.bounds2(shape)
  if not bounds or bounds.width2 <= 0 or bounds.depth2 <= 0 then
    return nil, { code = "FURNITURE_PREVIEW", message = "the furniture footprint is unavailable" }
  end
  local lines = grid(shape, bounds, opts)
  return {
    lines = lines,
    width_mm = bounds.width2 / 2,
    depth_mm = bounds.depth2 / 2,
  }
end

return M
