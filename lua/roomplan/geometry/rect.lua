local footprint = require("roomplan.geometry.footprint")

local M = {}

local function unpack_rect(rect)
  local left = rect.left or rect.x or rect[1]
  local bottom = rect.bottom or rect.y or rect[2]
  local right = rect.right
  local top = rect.top
  if right == nil then
    right = left + (rect.width or rect.w or rect[3])
  end
  if top == nil then
    top = bottom + (rect.depth or rect.height or rect.h or rect[4])
  end
  return left, bottom, right, top
end

function M.new(left, bottom, width, depth)
  return {
    left = left,
    bottom = bottom,
    right = left + width,
    top = bottom + depth,
    width = width,
    depth = depth,
  }
end

function M.from_room(room)
  local shape = footprint.from_room(room)
  if shape then return M.from_rect2(footprint.bounds2(shape)) end
  return M.new(room.origin_mm[1], room.origin_mm[2], room.size_mm[1], room.size_mm[2])
end

function M.bounds(rect)
  return unpack_rect(rect)
end

function M.overlaps_positive(a, b)
  local al, ab, ar, at = unpack_rect(a)
  local bl, bb, br, bt = unpack_rect(b)
  return math.max(al, bl) < math.min(ar, br) and math.max(ab, bb) < math.min(at, bt)
end

function M.intersects_closed(a, b)
  local al, ab, ar, at = unpack_rect(a)
  local bl, bb, br, bt = unpack_rect(b)
  return math.max(al, bl) <= math.min(ar, br) and math.max(ab, bb) <= math.min(at, bt)
end

function M.contains_point(rect, x, y, include_boundary)
  local left, bottom, right, top = unpack_rect(rect)
  if include_boundary == false then
    return x > left and x < right and y > bottom and y < top
  end
  return x >= left and x <= right and y >= bottom and y <= top
end

function M.intersection(a, b)
  local al, ab, ar, at = unpack_rect(a)
  local bl, bb, br, bt = unpack_rect(b)
  local left = math.max(al, bl)
  local bottom = math.max(ab, bb)
  local right = math.min(ar, br)
  local top = math.min(at, bt)
  if left < right and bottom < top then
    return M.new(left, bottom, right - left, top - bottom)
  end
  return nil
end

function M.union(rectangles)
  if not rectangles or #rectangles == 0 then
    return nil
  end
  local left, bottom, right, top = unpack_rect(rectangles[1])
  local i
  for i = 2, #rectangles do
    local l, b, r, t = unpack_rect(rectangles[i])
    left = math.min(left, l)
    bottom = math.min(bottom, b)
    right = math.max(right, r)
    top = math.max(top, t)
  end
  return M.new(left, bottom, right - left, top - bottom)
end

function M.room_rect2(room)
  local shape = footprint.from_room(room)
  if shape then
    local bounds = footprint.bounds2(shape)
    return { left2 = bounds.left2, bottom2 = bounds.bottom2, right2 = bounds.right2, top2 = bounds.top2 }
  end
  local x, y = room.origin_mm[1], room.origin_mm[2]
  local width, depth = room.size_mm[1], room.size_mm[2]
  return { left2 = 2 * x, bottom2 = 2 * y, right2 = 2 * (x + width), top2 = 2 * (y + depth) }
end

function M.furniture_rect2(room, furniture)
  local shape = footprint.from_furniture(room, furniture)
  if shape then
    local bounds = footprint.bounds2(shape)
    return {
      left2 = bounds.left2,
      right2 = bounds.right2,
      bottom2 = bounds.bottom2,
      top2 = bounds.top2,
      center_x2 = bounds.center_x2,
      center_y2 = bounds.center_y2,
    }
  end
  local width, depth = furniture.size_mm[1], furniture.size_mm[2]
  if furniture.rotation_deg == 90 or furniture.rotation_deg == 270 then
    width, depth = depth, width
  end
  local center_x = room.origin_mm[1] + furniture.center_mm[1]
  local center_y = room.origin_mm[2] + furniture.center_mm[2]
  return {
    left2 = 2 * center_x - width,
    right2 = 2 * center_x + width,
    bottom2 = 2 * center_y - depth,
    top2 = 2 * center_y + depth,
    center_x2 = 2 * center_x,
    center_y2 = 2 * center_y,
  }
end

function M.from_rect2(rect2)
  return {
    left = rect2.left2 / 2,
    right = rect2.right2 / 2,
    bottom = rect2.bottom2 / 2,
    top = rect2.top2 / 2,
    width = (rect2.right2 - rect2.left2) / 2,
    depth = (rect2.top2 - rect2.bottom2) / 2,
  }
end

function M.overlaps_positive2(a, b)
  return math.max(a.left2, b.left2) < math.min(a.right2, b.right2)
    and math.max(a.bottom2, b.bottom2) < math.min(a.top2, b.top2)
end

function M.contains_rect2(outer, inner)
  return inner.left2 >= outer.left2 and inner.right2 <= outer.right2
    and inner.bottom2 >= outer.bottom2 and inner.top2 <= outer.top2
end

function M.intersection2(a, b)
  local left2 = math.max(a.left2, b.left2)
  local right2 = math.min(a.right2, b.right2)
  local bottom2 = math.max(a.bottom2, b.bottom2)
  local top2 = math.min(a.top2, b.top2)
  if left2 < right2 and bottom2 < top2 then
    return { left2 = left2, right2 = right2, bottom2 = bottom2, top2 = top2 }
  end
  return nil
end

function M.overflow2(outer, inner)
  return {
    west = math.max(0, outer.left2 - inner.left2),
    east = math.max(0, inner.right2 - outer.right2),
    south = math.max(0, outer.bottom2 - inner.bottom2),
    north = math.max(0, inner.top2 - outer.top2),
  }
end

function M.edges(rect)
  local left, bottom, right, top = unpack_rect(rect)
  return {
    { side = "south", x1 = left, y1 = bottom, x2 = right, y2 = bottom },
    { side = "east", x1 = right, y1 = bottom, x2 = right, y2 = top },
    { side = "north", x1 = left, y1 = top, x2 = right, y2 = top },
    { side = "west", x1 = left, y1 = bottom, x2 = left, y2 = top },
  }
end

return M
