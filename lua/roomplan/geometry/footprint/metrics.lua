-- Bounds, area, silhouette, point provenance, and label placement.

local core = require("roomplan.geometry.footprint.core")
local internal = core._internal

local M = {}

function M.bounds2(value)
  local normalized, err = core.normalize(value)
  if not normalized then return nil, err end
  local first = normalized.parts[1]
  local left2, bottom2, right2, top2 = first.left2, first.bottom2, first.right2, first.top2
  for index = 2, #normalized.parts do
    local part = normalized.parts[index]
    left2, bottom2 = math.min(left2, part.left2), math.min(bottom2, part.bottom2)
    right2, top2 = math.max(right2, part.right2), math.max(top2, part.top2)
  end
  local width2, width_error = internal.checked_subtract(right2, left2, "footprint bounds width")
  if width2 == nil then return nil, width_error end
  local depth2, depth_error = internal.checked_subtract(top2, bottom2, "footprint bounds depth")
  if depth2 == nil then return nil, depth_error end
  local center_x2, center_x_error = internal.checked_midpoint(left2, right2, "footprint bounds X midpoint")
  if center_x2 == nil then return nil, center_x_error end
  local center_y2, center_y_error = internal.checked_midpoint(bottom2, top2, "footprint bounds Y midpoint")
  if center_y2 == nil then return nil, center_y_error end
  return {
    left2 = left2,
    bottom2 = bottom2,
    right2 = right2,
    top2 = top2,
    width2 = width2,
    depth2 = depth2,
    center_x2 = center_x2,
    center_y2 = center_y2,
  }
end

function M.bounds(value)
  local bounds2, err = M.bounds2(value)
  if not bounds2 then return nil, err end
  return {
    left = bounds2.left2 / 2,
    bottom = bounds2.bottom2 / 2,
    right = bounds2.right2 / 2,
    top = bounds2.top2 / 2,
    width = bounds2.width2 / 2,
    depth = bounds2.depth2 / 2,
    center_x = bounds2.center_x2 / 2,
    center_y = bounds2.center_y2 / 2,
  }
end

---Return ordinary-mm rectangles for rendering. Values may end in .5.
function M.rectangles(value)
  local normalized, err = core.normalize(value)
  if not normalized then return nil, err end
  local result = {}
  for index = 1, #normalized.parts do
    local part = normalized.parts[index]
    local width2, width_error = internal.checked_subtract(part.right2, part.left2, "footprint rectangle width")
    if width2 == nil then return nil, width_error end
    local depth2, depth_error = internal.checked_subtract(part.top2, part.bottom2, "footprint rectangle depth")
    if depth2 == nil then return nil, depth_error end
    result[index] = {
      left = part.left2 / 2,
      bottom = part.bottom2 / 2,
      right = part.right2 / 2,
      top = part.top2 / 2,
      width = width2 / 2,
      depth = depth2 / 2,
    }
  end
  return result
end

---Return exact union area in quarter-square-millimetre units. Using area4
---keeps the result integral for doubled-coordinate geometry.
function M.area4(value)
  local normalized, err = core.normalize(value)
  if not normalized then return nil, err end
  local total = 0
  for index = 1, #normalized.parts do
    local part = normalized.parts[index]
    local width2, width_error = internal.checked_subtract(part.right2, part.left2, "footprint area width")
    if width2 == nil then return nil, width_error end
    local depth2, depth_error = internal.checked_subtract(part.top2, part.bottom2, "footprint area depth")
    if depth2 == nil then return nil, depth_error end
    local area, area_error = internal.safe_product(width2, depth2, "footprint area")
    if not area then return nil, area_error end
    local next_total, total_error = internal.safe_sum(total, area, "footprint area")
    if not next_total then return nil, total_error end
    total = next_total
  end
  return total
end

function M.area(value)
  local area4, err = M.area4(value)
  if not area4 then return nil, err end
  return area4 / 4
end

local function append_part_id(target, seen, id)
  if not seen[id] then
    seen[id] = true
    target[#target + 1] = id
  end
end

local function boundary_contributions(normalized)
  -- Keep doubled-mm coordinates as numeric keys. Lua 5.1's tostring formatting
  -- can collapse distinct large exact integers (for example 1e15 and 1e15+1).
  local lines = { x = {}, y = {} }
  local function add(axis, fixed2, start2, finish2, side, part, part_index)
    local axis_lines = lines[axis]
    if not axis_lines[fixed2] then axis_lines[fixed2] = { axis = axis, fixed2 = fixed2, contributions = {} } end
    axis_lines[fixed2].contributions[#axis_lines[fixed2].contributions + 1] = {
      start2 = start2,
      finish2 = finish2,
      side = side,
      part_id = core.part_id(part, part_index),
    }
  end
  for index = 1, #normalized.parts do
    local part = normalized.parts[index]
    add("x", part.bottom2, part.left2, part.right2, "south", part, index)
    add("y", part.right2, part.bottom2, part.top2, "east", part, index)
    add("x", part.top2, part.left2, part.right2, "north", part, index)
    add("y", part.left2, part.bottom2, part.top2, "west", part, index)
  end
  local result = {}
  for _, axis in ipairs({ "x", "y" }) do
    for _, line in pairs(lines[axis]) do
      result[#result + 1] = line
    end
  end
  table.sort(result, function(left, right)
    if left.axis ~= right.axis then return left.axis < right.axis end
    return left.fixed2 < right.fixed2
  end)
  return result
end

local function segment_coordinates(segment)
  if segment.axis == "x" then
    segment.x1, segment.y1 = segment.start2, segment.fixed2
    segment.x2, segment.y2 = segment.finish2, segment.fixed2
  else
    segment.x1, segment.y1 = segment.fixed2, segment.start2
    segment.x2, segment.y2 = segment.fixed2, segment.finish2
  end
end

---Return the rect-union silhouette as deterministic doubled-mm segments.
---Coincident opposing contributions cancel, so internal seams disappear.
function M.boundary2(value)
  local normalized, err = core.normalize(value)
  if not normalized then return nil, err end
  local result = {}
  for _, line in ipairs(boundary_contributions(normalized)) do
    local endpoints = {}
    for _, contribution in ipairs(line.contributions) do
      endpoints[#endpoints + 1] = contribution.start2
      endpoints[#endpoints + 1] = contribution.finish2
    end
    endpoints = internal.unique_sorted(endpoints)
    local line_segments = {}
    for interval = 1, #endpoints - 1 do
      local start2, finish2 = endpoints[interval], endpoints[interval + 1]
      if start2 < finish2 then
        local sides = {}
        for _, contribution in ipairs(line.contributions) do
          if contribution.start2 <= start2 and contribution.finish2 >= finish2 then
            local bucket = sides[contribution.side]
            if not bucket then
              bucket = {}
              sides[contribution.side] = bucket
            end
            bucket[#bucket + 1] = contribution.part_id
          end
        end
        local negative = line.axis == "x" and sides.south or sides.west
        local positive = line.axis == "x" and sides.north or sides.east
        local side, ids
        if negative and not positive then
          side, ids = line.axis == "x" and "south" or "west", negative
        elseif positive and not negative then
          side, ids = line.axis == "x" and "north" or "east", positive
        end
        if side then
          table.sort(ids)
          local previous = line_segments[#line_segments]
          if previous and previous.side == side and previous.finish2 == start2 then
            local length2, length_error = internal.checked_subtract(finish2, previous.start2, "boundary length")
            if length2 == nil then return nil, length_error end
            previous.finish2 = finish2
            previous.length2 = length2
            local seen = {}
            for _, id in ipairs(previous.part_ids) do
              seen[id] = true
            end
            for _, id in ipairs(ids) do
              append_part_id(previous.part_ids, seen, id)
            end
            table.sort(previous.part_ids)
            segment_coordinates(previous)
          else
            local length2, length_error = internal.checked_subtract(finish2, start2, "boundary length")
            if length2 == nil then return nil, length_error end
            local segment = {
              axis = line.axis,
              fixed2 = line.fixed2,
              start2 = start2,
              finish2 = finish2,
              length2 = length2,
              side = side,
              part_ids = ids,
            }
            segment_coordinates(segment)
            line_segments[#line_segments + 1] = segment
          end
        end
      end
    end
    for _, segment in ipairs(line_segments) do
      result[#result + 1] = segment
    end
  end
  return result
end

function M.exterior_boundary2(value)
  local normalized, err = core.normalize(value)
  if not normalized then return nil, err end
  if internal.has_holes_parts(normalized.parts) then
    return internal.failure("FOOTPRINT_HOLE", "an exterior-only boundary is undefined for unsupported holes")
  end
  return M.boundary2(normalized)
end

---Return exact union perimeter in half-millimetre units.
function M.perimeter2(value)
  local segments, err = M.boundary2(value)
  if not segments then return nil, err end
  local total = 0
  for index = 1, #segments do
    local next_total, total_error = internal.safe_sum(total, segments[index].length2, "footprint perimeter")
    if not next_total then return nil, total_error end
    total = next_total
  end
  return total
end

function M.perimeter(value)
  local perimeter2, err = M.perimeter2(value)
  if not perimeter2 then return nil, err end
  return perimeter2 / 2
end

---Return every part under a doubled-mm point. Boundary hits are included by
---default and keep object-local part provenance without changing selection.
function M.hit_test2(value, x2, y2, options)
  local normalized, err = core.normalize(value)
  if not normalized then return nil, err end
  if not internal.finite_number(x2) or not internal.finite_number(y2) then
    return internal.failure("FOOTPRINT_POINT", "hit-test coordinates must be finite doubled-millimetre numbers")
  end
  local _, x_range_error = internal.coordinate_number2(x2, "hit-test X coordinate")
  if x_range_error then return nil, x_range_error end
  local _, y_range_error = internal.coordinate_number2(y2, "hit-test Y coordinate")
  if y_range_error then return nil, y_range_error end
  options = options or {}
  local include_boundary = options.include_boundary ~= false
  local result = {}
  for index = 1, #normalized.parts do
    local part = normalized.parts[index]
    local on_boundary = x2 == part.left2 or x2 == part.right2 or y2 == part.bottom2 or y2 == part.top2
    local inside = include_boundary
        and x2 >= part.left2
        and x2 <= part.right2
        and y2 >= part.bottom2
        and y2 <= part.top2
      or x2 > part.left2 and x2 < part.right2 and y2 > part.bottom2 and y2 < part.top2
    if inside then
      result[#result + 1] = {
        part_index = index,
        part_id = core.part_id(part, index),
        on_boundary = on_boundary,
      }
    end
  end
  return result
end

function M.contains_point2(value, x2, y2, options)
  local hits, err = M.hit_test2(value, x2, y2, options)
  if not hits then return nil, err end
  return #hits > 0, hits
end

function M.hit_test(value, x_mm, y_mm, options)
  if not internal.finite_number(x_mm) or not internal.finite_number(y_mm) then
    return internal.failure("FOOTPRINT_POINT", "hit-test coordinates must be finite millimetre numbers")
  end
  local x2, x_error = internal.checked_double_coordinate_number(x_mm, "hit-test X coordinate")
  if x2 == nil then return nil, x_error end
  local y2, y_error = internal.checked_double_coordinate_number(y_mm, "hit-test Y coordinate")
  if y2 == nil then return nil, y_error end
  return M.hit_test2(value, x2, y2, options)
end

---Choose a deterministic point guaranteed to be inside one part. The largest
---part wins; stable ID and source order resolve ties.
function M.label_anchor2(value)
  local normalized, err = core.normalize(value)
  if not normalized then return nil, err end
  local best, best_area
  for index = 1, #normalized.parts do
    local part = normalized.parts[index]
    local width2, width_error = internal.checked_subtract(part.right2, part.left2, "label-anchor width")
    if width2 == nil then return nil, width_error end
    local depth2, depth_error = internal.checked_subtract(part.top2, part.bottom2, "label-anchor depth")
    if depth2 == nil then return nil, depth_error end
    local area, area_error = internal.safe_product(width2, depth2, "label anchor")
    if not area then return nil, area_error end
    local id = core.part_id(part, index)
    if
      not best
      or area > best_area
      or (area == best_area and (id < best.part_id or (id == best.part_id and index < best.part_index)))
    then
      local x2, x_error = internal.checked_midpoint(part.left2, part.right2, "label-anchor X midpoint")
      if x2 == nil then return nil, x_error end
      local y2, y_error = internal.checked_midpoint(part.bottom2, part.top2, "label-anchor Y midpoint")
      if y2 == nil then return nil, y_error end
      best = {
        x2 = x2,
        y2 = y2,
        part_id = id,
        part_index = index,
      }
      best_area = area
    end
  end
  return best
end

function M.label_anchor(value)
  local anchor, err = M.label_anchor2(value)
  if not anchor then return nil, err end
  return {
    x = anchor.x2 / 2,
    y = anchor.y2 / 2,
    part_id = anchor.part_id,
    part_index = anchor.part_index,
  }
end

return M
