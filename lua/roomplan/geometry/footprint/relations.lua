-- Exact overlap, intersection, containment, and overflow relations.

local core = require("roomplan.geometry.footprint.core")
local metrics = require("roomplan.geometry.footprint.metrics")
local internal = core._internal

local M = {}

function M.overlaps_positive(left, right)
  local a, a_error = core.normalize(left)
  if not a then return nil, a_error end
  local b, b_error = core.normalize(right)
  if not b then return nil, b_error end
  for a_index = 1, #a.parts do
    for b_index = 1, #b.parts do
      if internal.overlaps_positive(a.parts[a_index], b.parts[b_index]) then return true end
    end
  end
  return false
end

function M.first_intersection2(left, right)
  local a, a_error = core.normalize(left)
  if not a then return nil, a_error end
  local b, b_error = core.normalize(right)
  if not b then return nil, b_error end
  for a_index = 1, #a.parts do
    local a_part = a.parts[a_index]
    for b_index = 1, #b.parts do
      local b_part = b.parts[b_index]
      local left2 = math.max(a_part.left2, b_part.left2)
      local bottom2 = math.max(a_part.bottom2, b_part.bottom2)
      local right2 = math.min(a_part.right2, b_part.right2)
      local top2 = math.min(a_part.top2, b_part.top2)
      if left2 < right2 and bottom2 < top2 then
        return { left2 = left2, bottom2 = bottom2, right2 = right2, top2 = top2 }
      end
    end
  end
  return nil
end

---Return the complete positive-area intersection and pairwise provenance.
---A nil footprint with no error means the unions do not overlap.
function M.intersection2(left, right)
  local a, a_error = core.normalize(left)
  if not a then return nil, a_error end
  local b, b_error = core.normalize(right)
  if not b then return nil, b_error end
  local parts, provenance = {}, {}
  for a_index = 1, #a.parts do
    local a_part = a.parts[a_index]
    for b_index = 1, #b.parts do
      local b_part = b.parts[b_index]
      local left2 = math.max(a_part.left2, b_part.left2)
      local bottom2 = math.max(a_part.bottom2, b_part.bottom2)
      local right2 = math.min(a_part.right2, b_part.right2)
      local top2 = math.min(a_part.top2, b_part.top2)
      if left2 < right2 and bottom2 < top2 then
        local index = #parts + 1
        local id = "part-" .. tostring(index)
        parts[index] = { id = id, left2 = left2, bottom2 = bottom2, right2 = right2, top2 = top2 }
        provenance[index] = {
          part_id = id,
          left = { part_index = a_index, part_id = core.part_id(a_part, a_index) },
          right = { part_index = b_index, part_id = core.part_id(b_part, b_index) },
        }
      end
    end
  end
  if #parts == 0 then return nil end
  local result, normalize_error = core.normalize({ kind = core.KIND, parts = parts }, { require_ids = true })
  if not result then return nil, normalize_error end
  return result, provenance
end

function M.intersection_area4(left, right)
  local intersection, provenance_or_error = M.intersection2(left, right)
  if not intersection then
    if provenance_or_error then return nil, provenance_or_error end
    return 0
  end
  return metrics.area4(intersection)
end

local function covered_by(parts, left2, bottom2, right2, top2)
  for index = 1, #parts do
    local part = parts[index]
    if part.left2 <= left2 and part.bottom2 <= bottom2 and part.right2 >= right2 and part.top2 >= top2 then
      return true
    end
  end
  return false
end

---Return whether every positive-area cell in inner is covered by outer.
---Coordinate compression makes this exact for a non-overlapping rect union.
function M.contains(outer, inner)
  local outside, outer_error = core.normalize(outer)
  if not outside then return nil, outer_error end
  local inside, inner_error = core.normalize(inner)
  if not inside then return nil, inner_error end
  for inner_index = 1, #inside.parts do
    local part = inside.parts[inner_index]
    local xs, ys = { part.left2, part.right2 }, { part.bottom2, part.top2 }
    for outer_index = 1, #outside.parts do
      local cover = outside.parts[outer_index]
      if cover.left2 > part.left2 and cover.left2 < part.right2 then xs[#xs + 1] = cover.left2 end
      if cover.right2 > part.left2 and cover.right2 < part.right2 then xs[#xs + 1] = cover.right2 end
      if cover.bottom2 > part.bottom2 and cover.bottom2 < part.top2 then ys[#ys + 1] = cover.bottom2 end
      if cover.top2 > part.bottom2 and cover.top2 < part.top2 then ys[#ys + 1] = cover.top2 end
    end
    xs, ys = internal.unique_sorted(xs), internal.unique_sorted(ys)
    for x_index = 1, #xs - 1 do
      for y_index = 1, #ys - 1 do
        if not covered_by(outside.parts, xs[x_index], ys[y_index], xs[x_index + 1], ys[y_index + 1]) then
          return false
        end
      end
    end
  end
  return true
end

---Bounding overflow retained for v1 diagnostics. Compound notches will gain
---richer uncovered-region diagnostics in the compound validation phase.
function M.overflow2(outer, inner)
  local outer_bounds, outer_error = metrics.bounds2(outer)
  if not outer_bounds then return nil, outer_error end
  local inner_bounds, inner_error = metrics.bounds2(inner)
  if not inner_bounds then return nil, inner_error end
  local west, west_error = internal.checked_subtract(outer_bounds.left2, inner_bounds.left2, "west overflow")
  if west == nil then return nil, west_error end
  local east, east_error = internal.checked_subtract(inner_bounds.right2, outer_bounds.right2, "east overflow")
  if east == nil then return nil, east_error end
  local south, south_error = internal.checked_subtract(outer_bounds.bottom2, inner_bounds.bottom2, "south overflow")
  if south == nil then return nil, south_error end
  local north, north_error = internal.checked_subtract(inner_bounds.top2, outer_bounds.top2, "north overflow")
  if north == nil then return nil, north_error end
  return {
    west = math.max(0, west),
    east = math.max(0, east),
    south = math.max(0, south),
    north = math.max(0, north),
  }
end

return M
