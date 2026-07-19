-- Exact proposals for placing a furniture silhouette against one exterior
-- room-wall segment. Persisted coordinates remain integer millimetres.

local footprint = require("roomplan.geometry.footprint")
local number = require("roomplan.geometry.number")

local M = {}

function M.walls(room)
  local shape, shape_error = footprint.from_room(room)
  if not shape then return nil, shape_error end
  local boundary, boundary_error = footprint.exterior_boundary2(shape)
  if not boundary then return nil, boundary_error end
  local result = {}
  for index, segment in ipairs(boundary) do
    result[index] = {
      id = tostring(index),
      index = index,
      axis = segment.axis,
      side = segment.side,
      fixed2 = segment.fixed2,
      start2 = segment.start2,
      finish2 = segment.finish2,
      length2 = segment.length2,
    }
  end
  return result
end

local function position_field(furniture)
  if furniture.position_mm ~= nil or furniture.footprint ~= nil then return "position_mm" end
  return "center_mm"
end

local function along_delta(bounds, wall, alignment)
  if alignment == "keep" then return 0 end
  if wall.axis == "y" then
    if alignment == "start" then return wall.start2 - bounds.bottom2 end
    if alignment == "end" then return wall.finish2 - bounds.top2 end
    return (wall.start2 + wall.finish2 - bounds.bottom2 - bounds.top2) / 2
  end
  if alignment == "start" then return wall.start2 - bounds.left2 end
  if alignment == "end" then return wall.finish2 - bounds.right2 end
  return (wall.start2 + wall.finish2 - bounds.left2 - bounds.right2) / 2
end

function M.propose(room, furniture, wall, options)
  options = options or {}
  if type(wall) ~= "table" then return nil, { code = "PLACEMENT_WALL", message = "choose a room wall" } end
  local shape, shape_error = footprint.from_furniture(room, furniture)
  if not shape then return nil, shape_error end
  local bounds, bounds_error = footprint.bounds2(shape)
  if not bounds then return nil, bounds_error end
  local clearance2 = 2 * (options.clearance_mm or 0)
  local dx2, dy2 = 0, 0
  if wall.side == "west" then
    dx2 = wall.fixed2 + clearance2 - bounds.left2
    dy2 = along_delta(bounds, wall, options.alignment or "center")
  elseif wall.side == "east" then
    dx2 = wall.fixed2 - clearance2 - bounds.right2
    dy2 = along_delta(bounds, wall, options.alignment or "center")
  elseif wall.side == "south" then
    dy2 = wall.fixed2 + clearance2 - bounds.bottom2
    dx2 = along_delta(bounds, wall, options.alignment or "center")
  elseif wall.side == "north" then
    dy2 = wall.fixed2 - clearance2 - bounds.top2
    dx2 = along_delta(bounds, wall, options.alignment or "center")
  else
    return nil, { code = "PLACEMENT_SIDE", message = "the selected wall side is invalid" }
  end
  local dx, residual_x = number.from_doubled(dx2)
  local dy, residual_y = number.from_doubled(dy2)
  local field = position_field(furniture)
  local current = furniture[field]
  if type(current) ~= "table" then
    return nil, { code = "PLACEMENT_POSITION", message = "furniture has no editable position" }
  end
  return {
    position_field = field,
    position_mm = { current[1] + dx, current[2] + dy },
    delta_mm = { dx, dy },
    residual_mm = { residual_x, residual_y },
    wall = wall,
  }
end

return M
