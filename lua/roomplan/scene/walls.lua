-- Pure wall extraction for roomplan.nvim.
--
-- A wall segment is a union of one or more room-edge contributions.  Valid
-- door and window apertures are subtracted before coincident edges are unioned;
-- point attachments such as outlets never cut walls.

local M = {}

local json = require("roomplan.codec.json")
local footprint = require("roomplan.geometry.footprint")
local wall_attachment = require("roomplan.geometry.wall_attachment")

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
  if not (type(room) == "table"
    and type(room.id) == "string"
    and type(room.origin_mm) == "table"
    and finite_number(room.origin_mm[1])
    and finite_number(room.origin_mm[2]))
  then
    return false
  end
  if room.footprint ~= nil then
    return footprint.from_room(room) ~= nil
  end
  return type(room.size_mm) == "table"
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

local function contribution(room, order, side, orientation, fixed, start_value, finish_value, part_ids)
  local result = {
    orientation = orientation,
    fixed = fixed,
    start = start_value,
    finish = finish_value,
    room_id = room.id,
    room_order = order,
    side = side,
    ref = ref_for("room", room.id, order, "wall"),
  }
  if part_ids then
    result.part_ids = part_ids
    if #part_ids == 1 then result.part_id = part_ids[1] end
  end
  return result
end

---Return normalized room edge contributions.
---@param room table
---@param order integer|nil
---@return table
function M.room_edges(room, order)
  if not valid_room_geometry(room) then
    return {}
  end

  order = order or 0
  if room.footprint ~= nil then
    local shape = footprint.from_room(room)
    local boundary = shape and footprint.exterior_boundary2(shape) or nil
    if not boundary then return {} end
    local result = {}
    for _, segment in ipairs(boundary) do
      result[#result + 1] = contribution(
        room,
        order,
        segment.side,
        segment.axis == "x" and "horizontal" or "vertical",
        segment.fixed2 / 2,
        segment.start2 / 2,
        segment.finish2 / 2,
        segment.part_ids
      )
    end
    return result
  end

  local x = room.origin_mm[1]
  local y = room.origin_mm[2]
  local width = room.size_mm[1]
  local depth = room.size_mm[2]
  return {
    contribution(room, order, "south", "horizontal", y, x, x + width),
    contribution(room, order, "east", "vertical", x + width, y, y + depth),
    contribution(room, order, "north", "horizontal", y + depth, x, x + width),
    contribution(room, order, "west", "vertical", x, y, y + depth),
  }
end

---Classify a wall aperture against the supplied room index.
---Malformed geometry is represented, not raised, so repair drafts still draw.
---@param kind "door"|"window"
---@param value table
---@param rooms_by_id table
---@param room_orders table|nil
---@param order integer|nil
---@return table
local function classify_aperture(kind, value, rooms_by_id, room_orders, order)
  order = order or 0
  local result = {
    id = type(value) == "table" and value.id or nil,
    ref = ref_for(kind, type(value) == "table" and value.id or "", order, "aperture"),
    owner_edge_valid = false,
    connection_valid = false,
    connection_requested = false,
    reason = nil,
  }
  result[kind] = value

  if type(value) ~= "table" then
    result.reason = kind .. " is not an object"
    return result
  end

  local owner = rooms_by_id[value.room_id]
  if not owner then
    result.reason = "owner room is missing"
    return result
  end
  if not SIDES[value.side] then
    result.reason = "unsupported owner side"
    return result
  end
  if not finite_number(value.offset_mm)
    or not finite_number(value.width_mm)
    or value.offset_mm < 0
    or value.width_mm <= 0
  then
    result.reason = "invalid aperture dimensions"
    return result
  end

  local aperture = wall_attachment.aperture(owner, value)
  if not aperture then
    result.reason = "owner edge is unavailable"
    return result
  end

  result.orientation = aperture.axis == "x" and "horizontal" or "vertical"
  result.fixed = aperture.fixed_mm
  result.start = aperture.start_mm
  result.finish = aperture.finish_mm
  result.side = value.side
  result.owner_room_id = owner.id
  result.owner_side = value.side
  if value.part_id ~= nil then result.owner_part_id = value.part_id end
  result.p0 = { aperture.p0[1], aperture.p0[2] }
  result.p1 = { aperture.p1[1], aperture.p1[2] }

  if not aperture.within_edge then
    result.reason = "aperture extends beyond owner edge"
    return result
  end

  if not aperture.on_exterior then
    result.reason = "aperture is not on owner footprint exterior"
    return result
  end

  result.owner_edge_valid = true
  result.connection_requested = value.connects_to_room_id ~= nil and not json.is_null(value.connects_to_room_id)
  if not result.connection_requested then
    return result
  end

  local connected = rooms_by_id[value.connects_to_room_id]
  if not connected or connected.id == owner.id then
    result.reason = "connected room is missing or equals owner"
    return result
  end

  local connection = wall_attachment.connection(owner, connected, value)
  if not connection then
    result.reason = "connected room does not cover the aperture"
    return result
  end

  result.connection_valid = true
  result.connected_room_id = connected.id
  result.connected_side = connection.b_side or OPPOSITE[value.side]
  result.connected_part_ids = connection.b_part_ids
  result.reason = nil
  return result
end

function M.classify_door(door, rooms_by_id, room_orders, order)
  return classify_aperture("door", door, rooms_by_id, room_orders, order)
end

function M.classify_window(window, rooms_by_id, room_orders, order)
  return classify_aperture("window", window, rooms_by_id, room_orders, order)
end

---Classify a point wall attachment. Points at edge endpoints are intentionally
---invalid because their owning wall is ambiguous.
function M.classify_outlet(outlet, rooms_by_id, _, order)
  order = order or 0
  local result = {
    outlet = outlet,
    id = type(outlet) == "table" and outlet.id or nil,
    ref = ref_for("outlet", type(outlet) == "table" and outlet.id or "", order, "marker"),
    owner_edge_valid = false,
    placement = type(outlet) == "table" and (outlet.placement or "wall") or nil,
    reason = nil,
  }

  if type(outlet) ~= "table" then
    result.reason = "outlet is not an object"
    return result
  end
  local owner = rooms_by_id[outlet.room_id]
  if not owner then
    result.reason = "owner room is missing"
    return result
  end
  if result.placement == "floor" then
    local marker = wall_attachment.floor_marker(owner, outlet)
    if not marker then
      result.reason = "floor position is unavailable"
      return result
    end
    result.owner_room_id = owner.id
    result.p = { marker.p[1], marker.p[2] }
    if not marker.within_room then
      result.reason = "floor outlet lies outside its owner room"
      return result
    end
    result.owner_edge_valid = true
    return result
  elseif result.placement ~= "wall" then
    result.reason = "unsupported outlet placement"
    return result
  end
  if not SIDES[outlet.side] then
    result.reason = "unsupported owner side"
    return result
  end
  if not finite_number(outlet.offset_mm) or outlet.offset_mm < 0 then
    result.reason = "invalid marker position"
    return result
  end

  local marker = wall_attachment.marker(owner, outlet)
  if not marker then
    result.reason = "owner edge is unavailable"
    return result
  end

  result.orientation = marker.axis == "x" and "horizontal" or "vertical"
  result.fixed = marker.fixed_mm
  result.position = marker.scalar_mm
  result.side = outlet.side
  result.owner_room_id = owner.id
  result.owner_side = outlet.side
  if outlet.part_id ~= nil then result.owner_part_id = outlet.part_id end
  result.p = { marker.p[1], marker.p[2] }

  if not marker.within_edge then
    if marker.scalar_mm == marker.edge_start_mm or marker.scalar_mm == marker.edge_finish_mm then
      result.reason = "outlet position is ambiguous at an edge endpoint"
    else
      result.reason = "outlet lies outside owner edge"
    end
    return result
  end
  if not marker.on_exterior then
    result.reason = "outlet is not on owner footprint exterior"
    return result
  end

  result.owner_edge_valid = true
  return result
end

local function cut_key(room_id, side, orientation, fixed)
  return table.concat({ room_id, side, orientation, string.format("%.17g", fixed) }, "\0")
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
  local result = {
    orientation = source.orientation,
    fixed = source.fixed,
    start = start_value,
    finish = finish_value,
    room_id = source.room_id,
    room_order = source.room_order,
    side = source.side,
    ref = source.ref,
  }
  if source.part_ids then result.part_ids = source.part_ids end
  if source.part_id then result.part_id = source.part_id end
  return result
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

local function add_aperture_cuts(cuts, aperture)
  if not aperture.owner_edge_valid then return end
  local owner_key = cut_key(
    aperture.owner_room_id,
    aperture.owner_side,
    aperture.orientation,
    aperture.fixed
  )
  cuts[owner_key] = cuts[owner_key] or {}
  cuts[owner_key][#cuts[owner_key] + 1] = { aperture.start, aperture.finish }

  if not aperture.connection_valid then return end
  local connected_key = cut_key(
    aperture.connected_room_id,
    aperture.connected_side,
    aperture.orientation,
    aperture.fixed
  )
  cuts[connected_key] = cuts[connected_key] or {}
  cuts[connected_key][#cuts[connected_key] + 1] = { aperture.start, aperture.finish }
end

---Build wall segments and classified wall attachments for a model.
---@param rooms table|nil
---@param doors table|nil
---@param windows table|nil
---@param outlets table|nil
---@return table
function M.build(rooms, doors, windows, outlets)
  rooms = rooms or {}
  doors = doors or {}
  windows = windows or {}
  outlets = outlets or {}
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
    add_aperture_cuts(cuts, aperture)
  end

  local window_apertures = {}
  for i = 1, #windows do
    local aperture = M.classify_window(windows[i], rooms_by_id, room_orders, i)
    window_apertures[#window_apertures + 1] = aperture
    add_aperture_cuts(cuts, aperture)
  end

  local outlet_markers = {}
  for i = 1, #outlets do
    outlet_markers[#outlet_markers + 1] = M.classify_outlet(outlets[i], rooms_by_id, room_orders, i)
  end

  local cut_contributions = {}
  for i = 1, #contributions do
    local edge = contributions[i]
    local pieces = subtract_intervals(
      edge.start,
      edge.finish,
      cuts[cut_key(edge.room_id, edge.side, edge.orientation, edge.fixed)]
    )
    for j = 1, #pieces do
      cut_contributions[#cut_contributions + 1] = copy_contribution(edge, pieces[j][1], pieces[j][2])
    end
  end

  return {
    segments = M.group_contributions(cut_contributions),
    apertures = apertures,
    window_apertures = window_apertures,
    outlet_markers = outlet_markers,
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
