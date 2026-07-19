local interval = require("roomplan.geometry.interval")
local footprint = require("roomplan.geometry.footprint")

local M = {}
local SIDES = { "south", "east", "north", "west" }

local opposites = { north = "south", south = "north", east = "west", west = "east" }
local inward = {
  south = { 0, 1 },
  north = { 0, -1 },
  west = { 1, 0 },
  east = { -1, 0 },
}

function M.opposite(side) return opposites[side] end

local function rectangle_edge(x, y, width, depth, side)
  if side == "south" then
    return {
      side = side,
      axis = "x",
      fixed_mm = y,
      start_mm = x,
      finish_mm = x + width,
      p0 = { x, y },
      p1 = { x + width, y },
      inward = { 0, 1 },
      outward = { 0, -1 },
    }
  elseif side == "north" then
    return {
      side = side,
      axis = "x",
      fixed_mm = y + depth,
      start_mm = x,
      finish_mm = x + width,
      p0 = { x, y + depth },
      p1 = { x + width, y + depth },
      inward = { 0, -1 },
      outward = { 0, 1 },
    }
  elseif side == "west" then
    return {
      side = side,
      axis = "y",
      fixed_mm = x,
      start_mm = y,
      finish_mm = y + depth,
      p0 = { x, y },
      p1 = { x, y + depth },
      inward = { 1, 0 },
      outward = { -1, 0 },
    }
  elseif side == "east" then
    return {
      side = side,
      axis = "y",
      fixed_mm = x + width,
      start_mm = y,
      finish_mm = y + depth,
      p0 = { x + width, y },
      p1 = { x + width, y + depth },
      inward = { -1, 0 },
      outward = { 1, 0 },
    }
  end
  return nil, "invalid room side " .. tostring(side)
end

local function part_by_id(shape, part_id)
  for index = 1, #shape.parts do
    local part = shape.parts[index]
    if part.id == part_id then return part end
  end
end

---Return a room edge. Compound rooms require a part ID because a cardinal
---side can occur more than once on their silhouette.
function M.edge(room, side, part_id)
  if type(room) ~= "table" or type(room.origin_mm) ~= "table" then return nil, "invalid room geometry" end
  if room.footprint == nil then
    if type(room.size_mm) ~= "table" then return nil, "invalid room geometry" end
    local edge, err = rectangle_edge(room.origin_mm[1], room.origin_mm[2], room.size_mm[1], room.size_mm[2], side)
    if edge and part_id ~= nil then edge.part_id = part_id end
    return edge, err
  end

  if type(part_id) ~= "string" then return nil, "compound room edges require a part_id" end
  local shape, shape_error = footprint.from_room(room)
  if not shape then return nil, shape_error and shape_error.message or "invalid room footprint" end
  local part = part_by_id(shape, part_id)
  if not part then return nil, "room part not found: " .. part_id end
  local edge, err = rectangle_edge(
    part.left2 / 2,
    part.bottom2 / 2,
    (part.right2 - part.left2) / 2,
    (part.top2 - part.bottom2) / 2,
    side
  )
  if edge then edge.part_id = part_id end
  return edge, err
end

local function has_part(segment, part_id)
  if not part_id then return true end
  for _, id in ipairs(segment.part_ids or {}) do
    if id == part_id then return true end
  end
  return false
end

---Return whether an interval of a part edge lies on the union exterior.
function M.is_exterior_interval(room, edge, start_mm, finish_mm, part_id)
  if room.footprint == nil then
    return interval.contains_interval(edge.start_mm, edge.finish_mm, start_mm, finish_mm)
  end
  local shape = footprint.from_room(room)
  if not shape then return false end
  local boundary = footprint.exterior_boundary2(shape)
  if not boundary then return false end
  local cursor = start_mm
  for _, segment in ipairs(boundary) do
    local axis = segment.axis
    local fixed = segment.fixed2 / 2
    local segment_start = segment.start2 / 2
    local segment_finish = segment.finish2 / 2
    if
      axis == edge.axis
      and fixed == edge.fixed_mm
      and segment.side == edge.side
      and has_part(segment, part_id)
      and segment_finish > cursor
      and segment_start <= cursor
    then
      cursor = math.max(cursor, segment_finish)
      if cursor >= finish_mm then return true end
    end
  end
  return false
end

function M.edges(room)
  if type(room) == "table" and room.footprint ~= nil then
    local shape = footprint.from_room(room)
    if not shape then return {} end
    local boundary = footprint.exterior_boundary2(shape)
    if not boundary then return {} end
    local result = {}
    for _, segment in ipairs(boundary) do
      local edge = {
        side = segment.side,
        axis = segment.axis,
        fixed_mm = segment.fixed2 / 2,
        start_mm = segment.start2 / 2,
        finish_mm = segment.finish2 / 2,
        inward = M.normal(segment.side),
        outward = M.normal(segment.side, true),
        part_ids = segment.part_ids,
      }
      if edge.axis == "x" then
        edge.p0 = { edge.start_mm, edge.fixed_mm }
        edge.p1 = { edge.finish_mm, edge.fixed_mm }
      else
        edge.p0 = { edge.fixed_mm, edge.start_mm }
        edge.p1 = { edge.fixed_mm, edge.finish_mm }
      end
      result[#result + 1] = edge
    end
    return result
  end
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
    local a_edges, b_edges = M.edges(a), M.edges(b)
    for _, ae in ipairs(a_edges) do
      if ae.side == a_side then
        for _, be in ipairs(b_edges) do
          if
            be.side == b_side
            and ae.fixed_mm == be.fixed_mm
            and interval.overlaps_positive(ae.start_mm, ae.finish_mm, be.start_mm, be.finish_mm)
          then
            return {
              a_side = a_side,
              b_side = b_side,
              axis = ae.axis,
              fixed_mm = ae.fixed_mm,
              start_mm = math.max(ae.start_mm, be.start_mm),
              finish_mm = math.min(ae.finish_mm, be.finish_mm),
              a_part_ids = ae.part_ids,
              b_part_ids = be.part_ids,
            }
          end
        end
      end
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
