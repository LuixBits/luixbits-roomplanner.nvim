local interval = require("roomplan.geometry.interval")

local M = {}
local SIDES = { "south", "east", "north", "west" }

local opposites = { north = "south", south = "north", east = "west", west = "east" }
local inward = {
  south = { 0, 1 },
  north = { 0, -1 },
  west = { 1, 0 },
  east = { -1, 0 },
}

function M.opposite(side)
  return opposites[side]
end

function M.edge(room, side)
  local x = room.origin_mm[1]
  local y = room.origin_mm[2]
  local width = room.size_mm[1]
  local depth = room.size_mm[2]
  if side == "south" then
    return { side = side, axis = "x", fixed_mm = y, start_mm = x, finish_mm = x + width,
      p0 = { x, y }, p1 = { x + width, y }, inward = { 0, 1 }, outward = { 0, -1 } }
  elseif side == "north" then
    return { side = side, axis = "x", fixed_mm = y + depth, start_mm = x, finish_mm = x + width,
      p0 = { x, y + depth }, p1 = { x + width, y + depth }, inward = { 0, -1 }, outward = { 0, 1 } }
  elseif side == "west" then
    return { side = side, axis = "y", fixed_mm = x, start_mm = y, finish_mm = y + depth,
      p0 = { x, y }, p1 = { x, y + depth }, inward = { 1, 0 }, outward = { -1, 0 } }
  elseif side == "east" then
    return { side = side, axis = "y", fixed_mm = x + width, start_mm = y, finish_mm = y + depth,
      p0 = { x + width, y }, p1 = { x + width, y + depth }, inward = { -1, 0 }, outward = { 1, 0 } }
  end
  return nil, "invalid room side " .. tostring(side)
end

function M.edges(room)
  local result = {}
  local i
  for i = 1, #SIDES do
    result[#result + 1] = M.edge(room, SIDES[i])
  end
  return result
end

function M.between(a, b)
  local pairs = {
    { "east", "west" },
    { "north", "south" },
    { "west", "east" },
    { "south", "north" },
  }
  local i
  for i = 1, #pairs do
    local a_side, b_side = pairs[i][1], pairs[i][2]
    local ae = M.edge(a, a_side)
    local be = M.edge(b, b_side)
    if ae.fixed_mm == be.fixed_mm and interval.overlaps_positive(ae.start_mm, ae.finish_mm, be.start_mm, be.finish_mm) then
      return {
        a_side = a_side,
        b_side = b_side,
        axis = ae.axis,
        fixed_mm = ae.fixed_mm,
        start_mm = math.max(ae.start_mm, be.start_mm),
        finish_mm = math.min(ae.finish_mm, be.finish_mm),
      }
    end
  end
  return nil
end

function M.normal(side, outward)
  local value = inward[side]
  if not value then return nil end
  if outward then return { -value[1], -value[2] } end
  return { value[1], value[2] }
end

return M
