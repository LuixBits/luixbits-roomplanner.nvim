local adjacency = require("roomplan.geometry.adjacency")
local interval = require("roomplan.geometry.interval")
local number = require("roomplan.geometry.number")
local sector_geometry = require("roomplan.geometry.sector")
local segment = require("roomplan.geometry.segment")

local M = {}

local function point(x, y)
  return { x = x, y = y, [1] = x, [2] = y }
end

local function xy(value)
  return value.x or value[1], value.y or value[2]
end

function M.edge_length(room, side)
  if side == "north" or side == "south" then return room.size_mm[1] end
  if side == "east" or side == "west" then return room.size_mm[2] end
  return nil
end

function M.aperture(room, door)
  local edge, err = adjacency.edge(room, door.side)
  if not edge then return nil, err end
  local start_mm = edge.start_mm + door.offset_mm
  local finish_mm = start_mm + door.width_mm
  local p0, p1
  if edge.axis == "x" then
    p0, p1 = point(start_mm, edge.fixed_mm), point(finish_mm, edge.fixed_mm)
  else
    p0, p1 = point(edge.fixed_mm, start_mm), point(edge.fixed_mm, finish_mm)
  end
  return {
    id = door.id,
    room_id = door.room_id,
    side = door.side,
    axis = edge.axis,
    fixed_mm = edge.fixed_mm,
    start_mm = start_mm,
    finish_mm = finish_mm,
    edge_start_mm = edge.start_mm,
    edge_finish_mm = edge.finish_mm,
    p0 = p0,
    p1 = p1,
    within_edge = interval.contains_interval(edge.start_mm, edge.finish_mm, start_mm, finish_mm),
  }
end

local function same_wall(a, b)
  return a.axis == b.axis and a.fixed_mm == b.fixed_mm
end

function M.apertures_overlap(a, b)
  return same_wall(a, b) and interval.overlaps_positive(a.start_mm, a.finish_mm, b.start_mm, b.finish_mm)
end

local function rotated_endpoint(hinge, vector_x, vector_y, radians)
  local hx, hy = xy(hinge)
  local cosine, sine = math.cos(radians), math.sin(radians)
  return point(hx + vector_x * cosine - vector_y * sine, hy + vector_x * sine + vector_y * cosine)
end

function M.swing(room, door)
  local aperture, err = M.aperture(room, door)
  if not aperture then return nil, err end
  local hinge = door.hinge == "end" and aperture.p1 or aperture.p0
  local jamb = door.hinge == "end" and aperture.p0 or aperture.p1
  local hx, hy = xy(hinge)
  local jx, jy = xy(jamb)
  local vx, vy = jx - hx, jy - hy
  local normal = adjacency.normal(door.side, door.opens_into ~= "owner")
  if not normal then return nil, "invalid door side" end
  local ccw_dx, ccw_dy = -vy, vx
  local dot = ccw_dx * normal[1] + ccw_dy * normal[2]
  local direction = dot >= 0 and 1 or -1
  local signed_radians = direction * door.open_angle_deg * math.pi / 180
  local sector = sector_geometry.new(hinge, jamb, signed_radians)
  sector.door_id = door.id
  sector.target = door.opens_into
  sector.normal = normal
  sector.direction = direction
  sector.open_angle_deg = door.open_angle_deg
  sector.aperture = aperture
  sector.jamb = jamb
  sector.open_endpoint = rotated_endpoint(hinge, vx, vy, signed_radians)
  return sector
end

function M.connection(room, other_room, door)
  local aperture = M.aperture(room, door)
  if not aperture then return nil end
  local record = adjacency.between(room, other_room)
  if not record or record.a_side ~= door.side then return nil end
  if not interval.contains_interval(record.start_mm, record.finish_mm, aperture.start_mm, aperture.finish_mm) then
    return nil
  end
  return record
end

function M.interferes(room_a, door_a, room_b, door_b)
  local swing_a = M.swing(room_a, door_a)
  local swing_b = M.swing(room_b, door_b)
  if not swing_a or not swing_b then return false end
  local epsilon = number.local_epsilon(door_a.width_mm, door_b.width_mm)
  local same_hinge = number.almost_equal(swing_a.hinge.x, swing_b.hinge.x, epsilon)
    and number.almost_equal(swing_a.hinge.y, swing_b.hinge.y, epsilon)
  local exclusions = same_hinge and { swing_a.hinge } or nil
  local origin_x, origin_y = swing_a.hinge.x, swing_a.hinge.y
  local a0 = point(0, 0)
  local a1 = swing_a.open_vector or point(swing_a.open_endpoint.x - origin_x, swing_a.open_endpoint.y - origin_y)
  local b0 = point(swing_b.hinge.x - origin_x, swing_b.hinge.y - origin_y)
  local bvector = swing_b.open_vector or point(swing_b.open_endpoint.x - swing_b.hinge.x,
    swing_b.open_endpoint.y - swing_b.hinge.y)
  local b1 = point(b0.x + bvector.x, b0.y + bvector.y)
  local hit, kind, value = segment.intersection(a0, a1, b0, b1, epsilon)
  if hit then
    if kind ~= "point" or not exclusions or not (number.almost_equal(value.x, 0, epsilon)
      and number.almost_equal(value.y, 0, epsilon)) then
      return true, { kind = "leaf-leaf", intersection = value }
    end
  end
  local sector_hit, details = sector_geometry.intersects_sector(swing_a, swing_b, { exclude_points = exclusions })
  if sector_hit then return true, details end
  return false
end

function M.wall_piece_segment(edge, start_mm, finish_mm)
  if edge.axis == "x" then
    return point(start_mm, edge.fixed_mm), point(finish_mm, edge.fixed_mm)
  end
  return point(edge.fixed_mm, start_mm), point(edge.fixed_mm, finish_mm)
end

return M
