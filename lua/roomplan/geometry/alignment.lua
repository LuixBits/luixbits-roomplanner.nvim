local number = require("roomplan.geometry.number")
local footprint = require("roomplan.geometry.footprint")

local M = {}

local corners = {
  southwest = true,
  southeast = true,
  northwest = true,
  northeast = true,
}

local function origin_result(x2, y2, operation)
  local x, rx = number.from_doubled(x2)
  local y, ry = number.from_doubled(y2)
  local rounded = rx ~= 0 or ry ~= 0
  local diagnostics = {}
  if rounded then
    diagnostics[1] = {
      code = "ALIGNMENT_ROUNDED",
      severity = "info",
      message = string.format("%s rounded to the integer-millimetre lattice", operation),
      details = { residual_mm = { x = rx, y = ry } },
    }
  end
  return {
    origin_mm = { x, y },
    rounded = rounded,
    residual_mm = { x = rx, y = ry },
    diagnostics = diagnostics,
    operation = operation,
  }
end

local function corner2(room, name)
  if not corners[name] then return nil end
  local shape, shape_error = footprint.from_room(room)
  if not shape then return nil, nil, shape_error end
  local bounds, bounds_error = footprint.bounds2(shape)
  if not bounds then return nil, nil, bounds_error end
  local x2 = (name == "southeast" or name == "northeast") and bounds.right2 or bounds.left2
  local y2 = (name == "northwest" or name == "northeast") and bounds.top2 or bounds.bottom2
  return x2, y2
end

local function room_bounds2(room)
  local shape, shape_error = footprint.from_room(room)
  if not shape then return nil, shape_error end
  return footprint.bounds2(shape)
end

function M.propose(moving, reference, operation, options)
  options = options or {}
  local mx, my = moving.origin_mm[1], moving.origin_mm[2]
  local moving_bounds, moving_error = room_bounds2(moving)
  if not moving_bounds then return nil, moving_error end
  local reference_bounds, reference_error = room_bounds2(reference)
  if not reference_bounds then return nil, reference_error end
  local gap = options.gap_mm or 0
  if type(gap) ~= "number" or gap ~= math.floor(gap) or gap < 0 then
    return nil, { code = "INVALID_ALIGNMENT", message = "alignment gap must be a non-negative integer" }
  end
  local x2, y2 = 2 * mx, 2 * my
  if operation == "align_min_x" or operation == "align_left" then
    x2 = x2 + reference_bounds.left2 - moving_bounds.left2
  elseif operation == "align_max_x" or operation == "align_right" then
    x2 = x2 + reference_bounds.right2 - moving_bounds.right2
  elseif operation == "align_min_y" or operation == "align_bottom" or operation == "align_south" then
    y2 = y2 + reference_bounds.bottom2 - moving_bounds.bottom2
  elseif operation == "align_max_y" or operation == "align_top" or operation == "align_north" then
    y2 = y2 + reference_bounds.top2 - moving_bounds.top2
  elseif operation == "align_center_x" then
    x2 = x2 + reference_bounds.center_x2 - moving_bounds.center_x2
  elseif operation == "align_center_y" then
    y2 = y2 + reference_bounds.center_y2 - moving_bounds.center_y2
  elseif operation == "place_east" then
    x2 = x2 + reference_bounds.right2 + 2 * gap - moving_bounds.left2
    y2 = y2 + reference_bounds.bottom2 - moving_bounds.bottom2
  elseif operation == "place_west" then
    x2 = x2 + reference_bounds.left2 - 2 * gap - moving_bounds.right2
    y2 = y2 + reference_bounds.bottom2 - moving_bounds.bottom2
  elseif operation == "place_north" then
    x2 = x2 + reference_bounds.left2 - moving_bounds.left2
    y2 = y2 + reference_bounds.top2 + 2 * gap - moving_bounds.bottom2
  elseif operation == "place_south" then
    x2 = x2 + reference_bounds.left2 - moving_bounds.left2
    y2 = y2 + reference_bounds.bottom2 - 2 * gap - moving_bounds.top2
  elseif operation == "snap_corner" then
    local moving_corner = corners[options.moving_corner] and options.moving_corner
    local reference_corner = corners[options.reference_corner] and options.reference_corner
    if not moving_corner or not reference_corner then
      return nil, { code = "INVALID_ALIGNMENT", message = "snap_corner requires valid moving and reference corners" }
    end
    local mcx2, mcy2, moving_corner_error = corner2(moving, moving_corner)
    if mcx2 == nil then return nil, moving_corner_error end
    local rcx2, rcy2, reference_corner_error = corner2(reference, reference_corner)
    if rcx2 == nil then return nil, reference_corner_error end
    x2 = 2 * mx + rcx2 - mcx2
    y2 = 2 * my + rcy2 - mcy2
  else
    return nil, { code = "INVALID_ALIGNMENT", message = "unsupported alignment operation " .. tostring(operation) }
  end
  return origin_result(x2, y2, operation)
end

function M.snap_corner(moving, reference, moving_corner, reference_corner)
  return M.propose(moving, reference, "snap_corner", {
    moving_corner = moving_corner,
    reference_corner = reference_corner,
  })
end

local direction_rank = { east = 1, north = 2, west = 3, south = 4 }

local function squared_distance(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return dx * dx + dy * dy
end

function M.auto_place(moving_or_size, rooms, options)
  options = options or {}
  rooms = rooms or {}
  if #rooms == 0 then return { origin_mm = { 0, 0 }, direction = "origin", reference_id = nil } end
  local moving = moving_or_size
  if type(moving_or_size) == "table" and moving_or_size.origin_mm == nil then
    moving = { origin_mm = { 0, 0 }, size_mm = moving_or_size }
  end
  if type(moving) ~= "table" or type(moving.origin_mm) ~= "table" then
    return nil, { code = "INVALID_ALIGNMENT", message = "automatic placement requires room geometry or size_mm" }
  end
  local moving_shape, moving_shape_error = footprint.from_room(moving)
  if not moving_shape then return nil, moving_shape_error end
  local moving_bounds, moving_bounds_error = footprint.bounds(moving_shape)
  if not moving_bounds then return nil, moving_bounds_error end
  local origin_x, origin_y = moving.origin_mm[1], moving.origin_mm[2]
  local offsets = {
    left = moving_bounds.left - origin_x,
    right = moving_bounds.right - origin_x,
    bottom = moving_bounds.bottom - origin_y,
    top = moving_bounds.top - origin_y,
  }
  local cursor = options.cursor_mm or options.plan_center_mm or { 0, 0 }
  local maximum = options.max_distance_mm
  local candidates = {}
  local operations = {
    { "place_east", "east" },
    { "place_north", "north" },
    { "place_west", "west" },
    { "place_south", "south" },
  }
  local function candidate_shape(origin)
    return footprint.translate(moving_shape, origin[1] - origin_x, origin[2] - origin_y)
  end
  local function overlaps_rooms(shape)
    for room_index = 1, #rooms do
      local room_shape = footprint.from_room(rooms[room_index])
      if room_shape and footprint.overlaps_positive(shape, room_shape) then return true end
    end
    return false
  end
  local i, j
  for i = 1, #rooms do
    for j = 1, #operations do
      local proposed, propose_error = M.propose(moving, rooms[i], operations[j][1], { gap_mm = options.gap_mm or 0 })
      if not proposed then return nil, propose_error end
      local shape, shape_error = candidate_shape(proposed.origin_mm)
      if not shape then return nil, shape_error end
      if not overlaps_rooms(shape) then
        local x, y = proposed.origin_mm[1], proposed.origin_mm[2]
        local distance = math.sqrt(squared_distance(x, y, cursor[1], cursor[2]))
        if not maximum or distance <= maximum then
          candidates[#candidates + 1] = {
            origin_mm = { x, y },
            direction = operations[j][2],
            direction_rank = direction_rank[operations[j][2]],
            reference_id = rooms[i].id,
            reference_index = i,
            cursor_distance2 = squared_distance(x, y, cursor[1], cursor[2]),
            origin_distance2 = squared_distance(x, y, 0, 0),
          }
        end
      end
    end
  end

  -- Add deterministic grid-aligned candidates around the complete plan bounds.
  -- These cover cases where every immediate reference placement is occupied by
  -- another (possibly forced-overlapping) room.
  local bounds
  for i = 1, #rooms do
    local shape = footprint.from_room(rooms[i])
    local current = shape and footprint.bounds(shape) or nil
    if current then
      if not bounds then
        bounds = current
      else
        bounds.left = math.min(bounds.left, current.left)
        bounds.bottom = math.min(bounds.bottom, current.bottom)
        bounds.right = math.max(bounds.right, current.right)
        bounds.top = math.max(bounds.top, current.top)
      end
    end
  end
  if not bounds then return nil, { code = "INVALID_ALIGNMENT", message = "rooms have no usable geometry" } end
  local grid = options.grid_mm or 100
  local function grid_floor(value) return math.floor(value / grid) * grid end
  local function grid_ceil(value) return math.ceil(value / grid) * grid end
  local grid_candidates = {
    { grid_ceil(bounds.right + (options.gap_mm or 0) - offsets.left), number.round_to_grid(cursor[2], grid), "east" },
    {
      grid_ceil(bounds.right + (options.gap_mm or 0) - offsets.left),
      grid_floor(bounds.bottom - offsets.bottom),
      "east",
    },
    { grid_ceil(bounds.right + (options.gap_mm or 0) - offsets.left), grid_ceil(bounds.top - offsets.top), "east" },
    { grid_floor(bounds.left - (options.gap_mm or 0) - offsets.right), number.round_to_grid(cursor[2], grid), "west" },
    {
      grid_floor(bounds.left - (options.gap_mm or 0) - offsets.right),
      grid_floor(bounds.bottom - offsets.bottom),
      "west",
    },
    { grid_floor(bounds.left - (options.gap_mm or 0) - offsets.right), grid_ceil(bounds.top - offsets.top), "west" },
    { number.round_to_grid(cursor[1], grid), grid_ceil(bounds.top + (options.gap_mm or 0) - offsets.bottom), "north" },
    { grid_floor(bounds.left - offsets.left), grid_ceil(bounds.top + (options.gap_mm or 0) - offsets.bottom), "north" },
    {
      grid_ceil(bounds.right - offsets.right),
      grid_ceil(bounds.top + (options.gap_mm or 0) - offsets.bottom),
      "north",
    },
    { number.round_to_grid(cursor[1], grid), grid_floor(bounds.bottom - (options.gap_mm or 0) - offsets.top), "south" },
    {
      grid_floor(bounds.left - offsets.left),
      grid_floor(bounds.bottom - (options.gap_mm or 0) - offsets.top),
      "south",
    },
    {
      grid_ceil(bounds.right - offsets.right),
      grid_floor(bounds.bottom - (options.gap_mm or 0) - offsets.top),
      "south",
    },
  }
  local seen = {}
  for i = 1, #candidates do
    seen[candidates[i].origin_mm[1] .. ":" .. candidates[i].origin_mm[2]] = true
  end
  for i = 1, #grid_candidates do
    local raw = grid_candidates[i]
    local key = raw[1] .. ":" .. raw[2]
    if not seen[key] then
      local shape, shape_error = candidate_shape(raw)
      if not shape then return nil, shape_error end
      local overlaps = overlaps_rooms(shape)
      local distance = math.sqrt(squared_distance(raw[1], raw[2], cursor[1], cursor[2]))
      if not overlaps and (not maximum or distance <= maximum) then
        candidates[#candidates + 1] = {
          origin_mm = { raw[1], raw[2] },
          direction = raw[3],
          direction_rank = direction_rank[raw[3]],
          reference_id = nil,
          reference_index = #rooms + 1,
          cursor_distance2 = squared_distance(raw[1], raw[2], cursor[1], cursor[2]),
          origin_distance2 = squared_distance(raw[1], raw[2], 0, 0),
          grid_candidate = true,
        }
      end
      seen[key] = true
    end
  end
  table.sort(candidates, function(a, b)
    if a.cursor_distance2 ~= b.cursor_distance2 then return a.cursor_distance2 < b.cursor_distance2 end
    if a.origin_distance2 ~= b.origin_distance2 then return a.origin_distance2 < b.origin_distance2 end
    if a.direction_rank ~= b.direction_rank then return a.direction_rank < b.direction_rank end
    if a.reference_index ~= b.reference_index then return a.reference_index < b.reference_index end
    if a.origin_mm[1] ~= b.origin_mm[1] then return a.origin_mm[1] < b.origin_mm[1] end
    return a.origin_mm[2] < b.origin_mm[2]
  end)
  if candidates[1] then return candidates[1] end
  return nil, { code = "AUTO_PLACEMENT_FAILED", message = "no non-overlapping automatic placement was found" }
end

return M
