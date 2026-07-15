local adjacency = require("roomplan.geometry.adjacency")
local interval = require("roomplan.geometry.interval")

local M = {}

local function point(x, y)
  return { x = x, y = y, [1] = x, [2] = y }
end

local function has_part(edge, part_id)
  if part_id == nil then return true end
  for _, id in ipairs(edge.part_ids or {}) do
    if id == part_id then return true end
  end
  return false
end

local function same_wall(a, b)
  return a.axis == b.axis and a.fixed_mm == b.fixed_mm
end

local function point_on_edge(edge, scalar)
  if edge.axis == "x" then
    return point(scalar, edge.fixed_mm)
  end
  return point(edge.fixed_mm, scalar)
end

local function is_exterior_point(room, edge, scalar, part_id)
  for _, candidate in ipairs(adjacency.edges(room)) do
    if candidate.side == edge.side
      and candidate.axis == edge.axis
      and candidate.fixed_mm == edge.fixed_mm
      and candidate.start_mm < scalar
      and candidate.finish_mm > scalar
      and has_part(candidate, part_id)
    then
      return true
    end
  end
  return false
end

function M.edge_length(room, side, part_id)
  local edge = adjacency.edge(room, side, part_id)
  if not edge then return nil end
  return edge.finish_mm - edge.start_mm
end

function M.aperture(room, attachment)
  local edge, err = adjacency.edge(room, attachment.side, attachment.part_id)
  if not edge then return nil, err end
  local start_mm = edge.start_mm + attachment.offset_mm
  local finish_mm = start_mm + attachment.width_mm
  local within_edge = interval.contains_interval(edge.start_mm, edge.finish_mm, start_mm, finish_mm)
  return {
    id = attachment.id,
    room_id = attachment.room_id,
    side = attachment.side,
    axis = edge.axis,
    fixed_mm = edge.fixed_mm,
    start_mm = start_mm,
    finish_mm = finish_mm,
    edge_start_mm = edge.start_mm,
    edge_finish_mm = edge.finish_mm,
    p0 = point_on_edge(edge, start_mm),
    p1 = point_on_edge(edge, finish_mm),
    part_id = attachment.part_id,
    within_edge = within_edge,
    on_exterior = within_edge
      and adjacency.is_exterior_interval(room, edge, start_mm, finish_mm, attachment.part_id),
  }
end

function M.apertures_overlap(a, b)
  return same_wall(a, b)
    and interval.overlaps_positive(a.start_mm, a.finish_mm, b.start_mm, b.finish_mm)
end

function M.connection(room, other_room, attachment)
  local aperture = M.aperture(room, attachment)
  if not aperture or not aperture.within_edge or not aperture.on_exterior then return nil end
  if room.footprint == nil and other_room.footprint == nil then
    local record = adjacency.between(room, other_room)
    if not record or record.a_side ~= attachment.side
      or not interval.contains_interval(record.start_mm, record.finish_mm, aperture.start_mm, aperture.finish_mm)
    then
      return nil
    end
    return record
  end
  for _, other_edge in ipairs(adjacency.edges(other_room)) do
    if other_edge.side == adjacency.opposite(attachment.side)
      and other_edge.axis == aperture.axis
      and other_edge.fixed_mm == aperture.fixed_mm
      and interval.contains_interval(
        other_edge.start_mm,
        other_edge.finish_mm,
        aperture.start_mm,
        aperture.finish_mm
      )
    then
      return {
        a_side = attachment.side,
        b_side = other_edge.side,
        axis = aperture.axis,
        fixed_mm = aperture.fixed_mm,
        start_mm = aperture.start_mm,
        finish_mm = aperture.finish_mm,
        a_part_ids = attachment.part_id and { attachment.part_id } or nil,
        b_part_ids = other_edge.part_ids,
      }
    end
  end
  return nil
end

---Resolve a point attachment on an exterior wall. Edge endpoints are excluded:
---at a corner (or a compound-part boundary) there is no unambiguous wall owner.
function M.marker(room, attachment)
  local edge, err = adjacency.edge(room, attachment.side, attachment.part_id)
  if not edge then return nil, err end
  local scalar_mm = edge.start_mm + attachment.offset_mm
  local within_edge = scalar_mm > edge.start_mm and scalar_mm < edge.finish_mm
  return {
    id = attachment.id,
    room_id = attachment.room_id,
    side = attachment.side,
    axis = edge.axis,
    fixed_mm = edge.fixed_mm,
    scalar_mm = scalar_mm,
    edge_start_mm = edge.start_mm,
    edge_finish_mm = edge.finish_mm,
    p = point_on_edge(edge, scalar_mm),
    part_id = attachment.part_id,
    within_edge = within_edge,
    on_exterior = within_edge and is_exterior_point(room, edge, scalar_mm, attachment.part_id),
  }
end

return M
