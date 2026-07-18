-- Exact clearance measurements between room and furniture footprints.

local footprint = require("roomplan.geometry.footprint")
local model_helpers = require("roomplan.model")

local M = {}

local function owner_room(model, furniture)
  return furniture and model_helpers.find(model, "room", furniture.room_id) or nil
end

function M.shape(model, reference)
  if type(model) ~= "table" or type(reference) ~= "table" then
    return nil, { code = "MEASUREMENT_REFERENCE", message = "measurement requires an object reference" }
  end
  local object = model_helpers.find(model, reference.kind, reference.id)
  if not object then
    return nil, { code = "MEASUREMENT_NOT_FOUND", message = "the measured object no longer exists" }
  end
  if reference.kind == "room" then
    local shape, err = footprint.from_room(object)
    if not shape then
      return nil, err
    end
    return shape, object
  end
  if reference.kind == "furniture" then
    local owner = owner_room(model, object)
    if not owner then
      return nil, { code = "MEASUREMENT_OWNER", message = "the furniture owner room no longer exists" }
    end
    local shape, err = footprint.from_furniture(owner, object)
    if not shape then
      return nil, err
    end
    return shape, object
  end
  return nil, { code = "MEASUREMENT_KIND", message = "measurements support rooms and furniture" }
end

local function axis_points(a0, a1, b0, b1)
  if a1 < b0 then
    return a1, b0, b0 - a1
  end
  if b1 < a0 then
    return a0, b1, a0 - b1
  end
  local contact = math.max(a0, b0)
  return contact, contact, 0
end

local function positive_overlap(a0, a1, b0, b1)
  return math.max(a0, b0) < math.min(a1, b1)
end

local function better(candidate, current)
  if not current or candidate.distance2_squared < current.distance2_squared then
    return true
  end
  if candidate.distance2_squared ~= current.distance2_squared then
    return false
  end
  for _, key in ipairs({ "ax2", "ay2", "bx2", "by2" }) do
    if candidate[key] ~= current[key] then
      return candidate[key] < current[key]
    end
  end
  return false
end

function M.between(model, left_reference, right_reference)
  if type(left_reference) ~= "table" or type(right_reference) ~= "table" then
    return nil, { code = "MEASUREMENT_REFERENCE", message = "measurement requires two object references" }
  end
  if left_reference.kind == right_reference.kind and left_reference.id == right_reference.id then
    return nil, { code = "MEASUREMENT_SAME_OBJECT", message = "choose two different objects" }
  end
  local left, left_object_or_error = M.shape(model, left_reference)
  if not left then
    return nil, left_object_or_error
  end
  local right, right_object_or_error = M.shape(model, right_reference)
  if not right then
    return nil, right_object_or_error
  end
  local best, horizontal_gap2, vertical_gap2
  for _, a in ipairs(left.parts or {}) do
    for _, b in ipairs(right.parts or {}) do
      local ax2, bx2, gap_x2 = axis_points(a.left2, a.right2, b.left2, b.right2)
      local ay2, by2, gap_y2 = axis_points(a.bottom2, a.top2, b.bottom2, b.top2)
      local dx2, dy2 = bx2 - ax2, by2 - ay2
      local candidate = {
        ax2 = ax2,
        ay2 = ay2,
        bx2 = bx2,
        by2 = by2,
        dx2 = bx2 - ax2,
        dy2 = by2 - ay2,
        distance2_squared = dx2 * dx2 + dy2 * dy2,
      }
      if better(candidate, best) then
        best = candidate
      end
      if positive_overlap(a.bottom2, a.top2, b.bottom2, b.top2) then
        horizontal_gap2 = horizontal_gap2 and math.min(horizontal_gap2, gap_x2) or gap_x2
      end
      if positive_overlap(a.left2, a.right2, b.left2, b.right2) then
        vertical_gap2 = vertical_gap2 and math.min(vertical_gap2, gap_y2) or gap_y2
      end
    end
  end
  local left_bounds = assert(footprint.bounds2(left))
  local right_bounds = assert(footprint.bounds2(right))
  return {
    left = left_reference,
    right = right_reference,
    left_object = left_object_or_error,
    right_object = right_object_or_error,
    nearest_mm = math.sqrt(best.distance2_squared) / 2,
    horizontal_gap_mm = horizontal_gap2 and horizontal_gap2 / 2 or nil,
    vertical_gap_mm = vertical_gap2 and vertical_gap2 / 2 or nil,
    center_delta_mm = {
      (right_bounds.center_x2 - left_bounds.center_x2) / 2,
      (right_bounds.center_y2 - left_bounds.center_y2) / 2,
    },
    closest = {
      from = { best.ax2 / 2, best.ay2 / 2 },
      to = { best.bx2 / 2, best.by2 / 2 },
    },
  }
end

function M.format_mm(value)
  if value == nil then
    return "not aligned on this axis"
  end
  if value == math.floor(value) then
    return string.format("%d mm", value)
  end
  return string.format("%.2f mm", value):gsub("0+ mm$", " mm"):gsub("%. mm$", " mm")
end

return M
