local number = require("roomplan.geometry.number")
local rect = require("roomplan.geometry.rect")

local M = {}

local corner_aliases = {
  southwest = "southwest", sw = "southwest", bottom_left = "southwest",
  southeast = "southeast", se = "southeast", bottom_right = "southeast",
  northwest = "northwest", nw = "northwest", top_left = "northwest",
  northeast = "northeast", ne = "northeast", top_right = "northeast",
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
  name = corner_aliases[name]
  if not name then return nil end
  local x2 = 2 * room.origin_mm[1]
  local y2 = 2 * room.origin_mm[2]
  if name == "southeast" or name == "northeast" then x2 = x2 + 2 * room.size_mm[1] end
  if name == "northwest" or name == "northeast" then y2 = y2 + 2 * room.size_mm[2] end
  return x2, y2
end

function M.propose(moving, reference, operation, options)
  options = options or {}
  local mx, my = moving.origin_mm[1], moving.origin_mm[2]
  local mw, md = moving.size_mm[1], moving.size_mm[2]
  local rx, ry = reference.origin_mm[1], reference.origin_mm[2]
  local rw, rd = reference.size_mm[1], reference.size_mm[2]
  local gap = options.gap_mm or 0
  if type(gap) ~= "number" or gap ~= math.floor(gap) or gap < 0 then
    return nil, { code = "INVALID_ALIGNMENT", message = "alignment gap must be a non-negative integer" }
  end
  local x2, y2 = 2 * mx, 2 * my
  if operation == "align_min_x" or operation == "align_left" then
    x2 = 2 * rx
  elseif operation == "align_max_x" or operation == "align_right" then
    x2 = 2 * (rx + rw - mw)
  elseif operation == "align_min_y" or operation == "align_bottom" or operation == "align_south" then
    y2 = 2 * ry
  elseif operation == "align_max_y" or operation == "align_top" or operation == "align_north" then
    y2 = 2 * (ry + rd - md)
  elseif operation == "align_center_x" then
    x2 = 2 * rx + rw - mw
  elseif operation == "align_center_y" then
    y2 = 2 * ry + rd - md
  elseif operation == "place_east" then
    x2, y2 = 2 * (rx + rw + gap), 2 * ry
  elseif operation == "place_west" then
    x2, y2 = 2 * (rx - mw - gap), 2 * ry
  elseif operation == "place_north" then
    x2, y2 = 2 * rx, 2 * (ry + rd + gap)
  elseif operation == "place_south" then
    x2, y2 = 2 * rx, 2 * (ry - md - gap)
  elseif operation == "snap_corner" then
    local moving_corner = corner_aliases[options.moving_corner]
    local reference_corner = corner_aliases[options.reference_corner]
    if not moving_corner or not reference_corner then
      return nil, { code = "INVALID_ALIGNMENT", message = "snap_corner requires valid moving and reference corners" }
    end
    local mcx2, mcy2 = corner2(moving, moving_corner)
    local rcx2, rcy2 = corner2(reference, reference_corner)
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

function M.auto_place(size_mm, rooms, options)
  options = options or {}
  rooms = rooms or {}
  if #rooms == 0 then
    return { origin_mm = { 0, 0 }, direction = "origin", reference_id = nil }
  end
  local moving = { origin_mm = { 0, 0 }, size_mm = size_mm }
  local cursor = options.cursor_mm or options.plan_center_mm or { 0, 0 }
  local maximum = options.max_distance_mm
  local candidates = {}
  local operations = {
    { "place_east", "east" }, { "place_north", "north" },
    { "place_west", "west" }, { "place_south", "south" },
  }
  local i, j
  for i = 1, #rooms do
    for j = 1, #operations do
      local proposed = M.propose(moving, rooms[i], operations[j][1], { gap_mm = options.gap_mm or 0 })
      local candidate_rect = rect.new(proposed.origin_mm[1], proposed.origin_mm[2], size_mm[1], size_mm[2])
      local overlaps = false
      local k
      for k = 1, #rooms do
        if rect.overlaps_positive(candidate_rect, rect.from_room(rooms[k])) then overlaps = true break end
      end
      if not overlaps then
        local x, y = proposed.origin_mm[1], proposed.origin_mm[2]
        local distance = math.sqrt(squared_distance(x, y, cursor[1], cursor[2]))
        if not maximum or distance <= maximum then
          candidates[#candidates + 1] = {
            origin_mm = { x, y }, direction = operations[j][2], direction_rank = direction_rank[operations[j][2]],
            reference_id = rooms[i].id, reference_index = i,
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
  local boxes = {}
  for i = 1, #rooms do boxes[i] = rect.from_room(rooms[i]) end
  local bounds = rect.union(boxes)
  local grid = options.grid_mm or 100
  local function grid_floor(value) return math.floor(value / grid) * grid end
  local function grid_ceil(value) return math.ceil(value / grid) * grid end
  local width, depth = size_mm[1], size_mm[2]
  local grid_candidates = {
    { grid_ceil(bounds.right + (options.gap_mm or 0)), number.round_to_grid(cursor[2], grid), "east" },
    { grid_ceil(bounds.right + (options.gap_mm or 0)), grid_floor(bounds.bottom), "east" },
    { grid_ceil(bounds.right + (options.gap_mm or 0)), grid_ceil(bounds.top - depth), "east" },
    { grid_floor(bounds.left - width - (options.gap_mm or 0)), number.round_to_grid(cursor[2], grid), "west" },
    { grid_floor(bounds.left - width - (options.gap_mm or 0)), grid_floor(bounds.bottom), "west" },
    { grid_floor(bounds.left - width - (options.gap_mm or 0)), grid_ceil(bounds.top - depth), "west" },
    { number.round_to_grid(cursor[1], grid), grid_ceil(bounds.top + (options.gap_mm or 0)), "north" },
    { grid_floor(bounds.left), grid_ceil(bounds.top + (options.gap_mm or 0)), "north" },
    { grid_ceil(bounds.right - width), grid_ceil(bounds.top + (options.gap_mm or 0)), "north" },
    { number.round_to_grid(cursor[1], grid), grid_floor(bounds.bottom - depth - (options.gap_mm or 0)), "south" },
    { grid_floor(bounds.left), grid_floor(bounds.bottom - depth - (options.gap_mm or 0)), "south" },
    { grid_ceil(bounds.right - width), grid_floor(bounds.bottom - depth - (options.gap_mm or 0)), "south" },
  }
  local seen = {}
  for i = 1, #candidates do seen[candidates[i].origin_mm[1] .. ":" .. candidates[i].origin_mm[2]] = true end
  for i = 1, #grid_candidates do
    local raw = grid_candidates[i]
    local key = raw[1] .. ":" .. raw[2]
    if not seen[key] then
      local candidate_rect = rect.new(raw[1], raw[2], width, depth)
      local overlaps = false
      for j = 1, #rooms do
        if rect.overlaps_positive(candidate_rect, rect.from_room(rooms[j])) then overlaps = true break end
      end
      local distance = math.sqrt(squared_distance(raw[1], raw[2], cursor[1], cursor[2]))
      if not overlaps and (not maximum or distance <= maximum) then
        candidates[#candidates + 1] = {
          origin_mm = { raw[1], raw[2] }, direction = raw[3], direction_rank = direction_rank[raw[3]],
          reference_id = nil, reference_index = #rooms + 1,
          cursor_distance2 = squared_distance(raw[1], raw[2], cursor[1], cursor[2]),
          origin_distance2 = squared_distance(raw[1], raw[2], 0, 0), grid_candidate = true,
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

local operation_names = {
  "align_min_x", "align_max_x", "align_min_y", "align_max_y", "align_center_x", "align_center_y",
  "place_north", "place_east", "place_south", "place_west",
}
local operation_index
for operation_index = 1, #operation_names do
  local name = operation_names[operation_index]
  M[name] = function(moving, reference, options)
    return M.propose(moving, reference, name, options)
  end
end
M.align_left = M.align_min_x
M.align_right = M.align_max_x
M.align_bottom = M.align_min_y
M.align_top = M.align_max_y

return M
