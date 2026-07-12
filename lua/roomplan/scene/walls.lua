-- Pure wall extraction for roomplan.nvim.
--
-- A wall segment is a union of one or more room-edge contributions.  Door
-- apertures are subtracted from contributions before coincident edges are
-- unioned, so an unverified connection can never punch through another room.

local M = {}

local json = require("roomplan.codec.json")

local SIDES = {
  north = true,
  east = true,
  south = true,
  west = true,
}

local OPPOSITE = {
  north = "south",
  south = "north",
  east = "west",
  west = "east",
}

local function finite_number(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function valid_room_geometry(room)
  return type(room) == "table"
    and type(room.id) == "string"
    and type(room.origin_mm) == "table"
    and type(room.size_mm) == "table"
    and finite_number(room.origin_mm[1])
    and finite_number(room.origin_mm[2])
    and finite_number(room.size_mm[1])
    and finite_number(room.size_mm[2])
    and room.size_mm[1] > 0
    and room.size_mm[2] > 0
end

local function ref_for(kind, id, order, context)
  return {
    type = kind,
    id = id,
    order = order or 0,
    context = context,
  }
end

local function contribution(room, order, side, orientation, fixed, start_value, finish_value)
  return {
    orientation = orientation,
    fixed = fixed,
    start = start_value,
    finish = finish_value,
    room_id = room.id,
    room_order = order,
    side = side,
    ref = ref_for("room", room.id, order, "wall"),
  }
end

---Return normalized room edge contributions.
---@param room table
---@param order integer|nil
---@return table
function M.room_edges(room, order)
  if not valid_room_geometry(room) then
    return {}
  end

  local x = room.origin_mm[1]
  local y = room.origin_mm[2]
  local width = room.size_mm[1]
  local depth = room.size_mm[2]
  order = order or 0

  return {
    contribution(room, order, "south", "horizontal", y, x, x + width),
    contribution(room, order, "east", "vertical", x + width, y, y + depth),
    contribution(room, order, "north", "horizontal", y + depth, x, x + width),
    contribution(room, order, "west", "vertical", x, y, y + depth),
  }
end

local function edge_for_side(room, side, order)
  local edges = M.room_edges(room, order)
  for i = 1, #edges do
    if edges[i].side == side then
      return edges[i]
    end
  end
  return nil
end

local function point_on_edge(edge, scalar)
  if edge.orientation == "horizontal" then
    return { scalar, edge.fixed }
  end
  return { edge.fixed, scalar }
end

---Classify a door aperture against the supplied room index.
---Malformed geometry is represented, not raised, so repair drafts still draw.
---@param door table
---@param rooms_by_id table
---@param room_orders table|nil
---@param order integer|nil
---@return table
function M.classify_door(door, rooms_by_id, room_orders, order)
  order = order or 0
  local result = {
    door = door,
    id = type(door) == "table" and door.id or nil,
    ref = ref_for("door", type(door) == "table" and door.id or "", order, "aperture"),
    owner_edge_valid = false,
    connection_valid = false,
    connection_requested = false,
    reason = nil,
  }

  if type(door) ~= "table" then
    result.reason = "door is not an object"
    return result
  end

  local owner = rooms_by_id[door.room_id]
  if not owner then
    result.reason = "owner room is missing"
    return result
  end
  if not SIDES[door.side] then
    result.reason = "unsupported owner side"
    return result
  end
  if not finite_number(door.offset_mm) or not finite_number(door.width_mm) or door.offset_mm < 0 or door.width_mm <= 0 then
    result.reason = "invalid aperture dimensions"
    return result
  end

  local owner_order = room_orders and room_orders[owner.id] or 0
  local edge = edge_for_side(owner, door.side, owner_order)
  if not edge then
    result.reason = "owner edge is unavailable"
    return result
  end

  local aperture_start = edge.start + door.offset_mm
  local aperture_finish = aperture_start + door.width_mm
  result.orientation = edge.orientation
  result.fixed = edge.fixed
  result.start = aperture_start
  result.finish = aperture_finish
  result.side = door.side
  result.owner_room_id = owner.id
  result.owner_side = door.side
  result.p0 = point_on_edge(edge, aperture_start)
  result.p1 = point_on_edge(edge, aperture_finish)

  if aperture_start < edge.start or aperture_finish > edge.finish then
    result.reason = "aperture extends beyond owner edge"
    return result
  end

  result.owner_edge_valid = true
  result.connection_requested = door.connects_to_room_id ~= nil and not json.is_null(door.connects_to_room_id)
  if not result.connection_requested then
    return result
  end

  local connected = rooms_by_id[door.connects_to_room_id]
  if not connected or connected.id == owner.id then
    result.reason = "connected room is missing or equals owner"
    return result
  end

  local opposite_side = OPPOSITE[door.side]
  local connected_order = room_orders and room_orders[connected.id] or 0
  local opposite_edge = edge_for_side(connected, opposite_side, connected_order)
  if not opposite_edge
    or opposite_edge.orientation ~= edge.orientation
    or opposite_edge.fixed ~= edge.fixed
    or opposite_edge.start > aperture_start
    or opposite_edge.finish < aperture_finish
  then
    result.reason = "connected room does not cover the aperture"
    return result
  end

  result.connection_valid = true
  result.connected_room_id = connected.id
  result.connected_side = opposite_side
  result.reason = nil
  return result
end

local function cut_key(room_id, side)
  return room_id .. "\0" .. side
end

local function sort_intervals(intervals)
  table.sort(intervals, function(a, b)
    if a[1] ~= b[1] then
      return a[1] < b[1]
    end
    return a[2] < b[2]
  end)
end

local function subtract_intervals(start_value, finish_value, cuts)
  if not cuts or #cuts == 0 then
    return { { start_value, finish_value } }
  end

  sort_intervals(cuts)
  local result = {}
  local cursor = start_value
  for i = 1, #cuts do
    local cut_start = math.max(start_value, cuts[i][1])
    local cut_finish = math.min(finish_value, cuts[i][2])
    if cut_finish > cut_start then
      if cut_start > cursor then
        result[#result + 1] = { cursor, cut_start }
      end
      if cut_finish > cursor then
        cursor = cut_finish
      end
    end
  end
  if cursor < finish_value then
    result[#result + 1] = { cursor, finish_value }
  end
  return result
end

local function copy_contribution(source, start_value, finish_value)
  return {
    orientation = source.orientation,
    fixed = source.fixed,
    start = start_value,
    finish = finish_value,
    room_id = source.room_id,
    room_order = source.room_order,
    side = source.side,
    ref = source.ref,
  }
end

local function line_key(edge)
  -- Model coordinates are safe integers, but %.17g keeps this helper useful for
  -- half-millimetre test fixtures without locale-dependent formatting.
  return edge.orientation .. ":" .. string.format("%.17g", edge.fixed)
end

local function contributor_sort(a, b)
  if a.room_order ~= b.room_order then
    return a.room_order < b.room_order
  end
  if a.room_id ~= b.room_id then
    return a.room_id < b.room_id
  end
  return a.side < b.side
end

local function same_contributors(a, b)
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i].room_id ~= b[i].room_id or a[i].side ~= b[i].side then
      return false
    end
  end
  return true
end

local function refs_for_contributors(contributors)
  local refs = {}
  for i = 1, #contributors do
    refs[#refs + 1] = contributors[i].ref
  end
  return refs
end

local function coordinates_for_segment(orientation, fixed, start_value, finish_value)
  if orientation == "horizontal" then
    return start_value, fixed, finish_value, fixed
  end
  return fixed, start_value, fixed, finish_value
end

---Partition and union collinear contributions while retaining provenance.
---@param contributions table
---@return table
function M.group_contributions(contributions)
  local grouped = {}
  for i = 1, #contributions do
    local edge = contributions[i]
    if edge.finish > edge.start then
      local key = line_key(edge)
      if not grouped[key] then
        grouped[key] = {
          orientation = edge.orientation,
          fixed = edge.fixed,
          edges = {},
        }
      end
      grouped[key].edges[#grouped[key].edges + 1] = edge
    end
  end

  local keys = {}
  for key in pairs(grouped) do
    keys[#keys + 1] = key
  end
  table.sort(keys)

  local segments = {}
  for key_index = 1, #keys do
    local line = grouped[keys[key_index]]
    local endpoints = {}
    for i = 1, #line.edges do
      endpoints[#endpoints + 1] = line.edges[i].start
      endpoints[#endpoints + 1] = line.edges[i].finish
    end
    table.sort(endpoints)

    local unique = {}
    for i = 1, #endpoints do
      if i == 1 or endpoints[i] ~= endpoints[i - 1] then
        unique[#unique + 1] = endpoints[i]
      end
    end

    local line_segments = {}
    for i = 1, #unique - 1 do
      local start_value = unique[i]
      local finish_value = unique[i + 1]
      if finish_value > start_value then
        local midpoint = start_value + (finish_value - start_value) / 2
        local contributors = {}
        for edge_index = 1, #line.edges do
          local edge = line.edges[edge_index]
          if edge.start <= midpoint and edge.finish >= midpoint then
            contributors[#contributors + 1] = edge
          end
        end
        if #contributors > 0 then
          table.sort(contributors, contributor_sort)
          local previous = line_segments[#line_segments]
          if previous and previous.finish == start_value and same_contributors(previous.contributors, contributors) then
            previous.finish = finish_value
          else
            line_segments[#line_segments + 1] = {
              start = start_value,
              finish = finish_value,
              contributors = contributors,
            }
          end
        end
      end
    end

    for i = 1, #line_segments do
      local part = line_segments[i]
      local x1, y1, x2, y2 = coordinates_for_segment(line.orientation, line.fixed, part.start, part.finish)
      segments[#segments + 1] = {
        kind = "wall",
        orientation = line.orientation,
        fixed = line.fixed,
        start = part.start,
        finish = part.finish,
        x1 = x1,
        y1 = y1,
        x2 = x2,
        y2 = y2,
        contributors = part.contributors,
        refs = refs_for_contributors(part.contributors),
      }
    end
  end

  table.sort(segments, function(a, b)
    if a.orientation ~= b.orientation then
      return a.orientation < b.orientation
    end
    if a.fixed ~= b.fixed then
      return a.fixed < b.fixed
    end
    if a.start ~= b.start then
      return a.start < b.start
    end
    return a.finish < b.finish
  end)
  return segments
end

---Build wall segments and classified apertures for a model.
---@param rooms table|nil
---@param doors table|nil
---@return table
function M.build(rooms, doors)
  rooms = rooms or {}
  doors = doors or {}
  local rooms_by_id = {}
  local room_orders = {}
  local contributions = {}

  for i = 1, #rooms do
    local room = rooms[i]
    if valid_room_geometry(room) then
      -- Preserve first occurrence in repair drafts with duplicate IDs.  The
      -- validator owns the diagnostic; scene extraction must stay deterministic.
      if rooms_by_id[room.id] == nil then
        rooms_by_id[room.id] = room
        room_orders[room.id] = i
      end
      local edges = M.room_edges(room, i)
      for j = 1, #edges do
        contributions[#contributions + 1] = edges[j]
      end
    end
  end

  local cuts = {}
  local apertures = {}
  for i = 1, #doors do
    local aperture = M.classify_door(doors[i], rooms_by_id, room_orders, i)
    apertures[#apertures + 1] = aperture
    if aperture.owner_edge_valid then
      local owner_key = cut_key(aperture.owner_room_id, aperture.owner_side)
      cuts[owner_key] = cuts[owner_key] or {}
      cuts[owner_key][#cuts[owner_key] + 1] = { aperture.start, aperture.finish }

      if aperture.connection_valid then
        local connected_key = cut_key(aperture.connected_room_id, aperture.connected_side)
        cuts[connected_key] = cuts[connected_key] or {}
        cuts[connected_key][#cuts[connected_key] + 1] = { aperture.start, aperture.finish }
      end
    end
  end

  local cut_contributions = {}
  for i = 1, #contributions do
    local edge = contributions[i]
    local pieces = subtract_intervals(edge.start, edge.finish, cuts[cut_key(edge.room_id, edge.side)])
    for j = 1, #pieces do
      cut_contributions[#cut_contributions + 1] = copy_contribution(edge, pieces[j][1], pieces[j][2])
    end
  end

  return {
    segments = M.group_contributions(cut_contributions),
    apertures = apertures,
    rooms_by_id = rooms_by_id,
    room_orders = room_orders,
    contributions = cut_contributions,
  }
end

M.valid_room_geometry = valid_room_geometry
M.opposite_side = function(side)
  return OPPOSITE[side]
end

return M
