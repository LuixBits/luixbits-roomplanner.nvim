local number = require("roomplan.geometry.number")

local M = {}

local function point(x, y)
  return { x = x, y = y, [1] = x, [2] = y }
end

M.point = point

local function xy(value)
  return value.x or value[1], value.y or value[2]
end

function M.cross(ax, ay, bx, by)
  return ax * by - ay * bx
end

function M.orientation(a, b, c)
  local ax, ay = xy(a)
  local bx, by = xy(b)
  local cx, cy = xy(c)
  return M.cross(bx - ax, by - ay, cx - ax, cy - ay)
end

function M.point_on_segment(p, a, b, epsilon)
  local px, py = xy(p)
  local ax, ay = xy(a)
  local bx, by = xy(b)
  epsilon = epsilon or number.local_epsilon(bx - ax, by - ay)
  if math.abs(M.cross(bx - ax, by - ay, px - ax, py - ay)) > epsilon then
    return false
  end
  return px >= math.min(ax, bx) - epsilon and px <= math.max(ax, bx) + epsilon
    and py >= math.min(ay, by) - epsilon and py <= math.max(ay, by) + epsilon
end

-- Returns whether closed segments intersect, plus a classification and point
-- when the unique intersection can be represented.
function M.intersection(a, b, c, d, epsilon)
  local ax, ay = xy(a)
  local bx, by = xy(b)
  local cx, cy = xy(c)
  local dx, dy = xy(d)
  local rx, ry = bx - ax, by - ay
  local sx, sy = dx - cx, dy - cy
  epsilon = epsilon or number.local_epsilon(rx, ry, sx, sy)
  local denominator = M.cross(rx, ry, sx, sy)
  local qpx, qpy = cx - ax, cy - ay
  local qpr = M.cross(qpx, qpy, rx, ry)

  if math.abs(denominator) <= epsilon then
    if math.abs(qpr) > epsilon then
      return false, "parallel"
    end
    local rr = rx * rx + ry * ry
    if rr <= epsilon * epsilon then
      if M.point_on_segment(a, c, d, epsilon) then
        return true, "point", point(ax, ay)
      end
      return false, "degenerate"
    end
    local t0 = (qpx * rx + qpy * ry) / rr
    local t1 = t0 + (sx * rx + sy * ry) / rr
    if t0 > t1 then t0, t1 = t1, t0 end
    local lo = math.max(0, t0)
    local hi = math.min(1, t1)
    if lo > hi + epsilon then
      return false, "collinear-disjoint"
    elseif math.abs(lo - hi) <= epsilon then
      return true, "point", point(ax + lo * rx, ay + lo * ry)
    end
    return true, "overlap", {
      point(ax + lo * rx, ay + lo * ry),
      point(ax + hi * rx, ay + hi * ry),
    }
  end

  local t = M.cross(qpx, qpy, sx, sy) / denominator
  local u = M.cross(qpx, qpy, rx, ry) / denominator
  if t >= -epsilon and t <= 1 + epsilon and u >= -epsilon and u <= 1 + epsilon then
    return true, "point", point(ax + t * rx, ay + t * ry), t, u
  end
  return false, "disjoint"
end

function M.intersects(a, b, c, d, epsilon)
  local hit = M.intersection(a, b, c, d, epsilon)
  return hit
end

function M.aabb(a, b)
  local ax, ay = xy(a)
  local bx, by = xy(b)
  return { left = math.min(ax, bx), right = math.max(ax, bx), bottom = math.min(ay, by), top = math.max(ay, by) }
end

function M.intersects_rect(a, b, rect, epsilon)
  local left = rect.left
  local right = rect.right
  local bottom = rect.bottom
  local top = rect.top
  local ax, ay = xy(a)
  local bx, by = xy(b)
  epsilon = epsilon or number.local_epsilon(bx - ax, by - ay, right - left, top - bottom)
  if (ax >= left - epsilon and ax <= right + epsilon and ay >= bottom - epsilon and ay <= top + epsilon)
    or (bx >= left - epsilon and bx <= right + epsilon and by >= bottom - epsilon and by <= top + epsilon)
  then
    return true
  end
  local sw = point(left, bottom)
  local se = point(right, bottom)
  local ne = point(right, top)
  local nw = point(left, top)
  return M.intersects(a, b, sw, se, epsilon)
    or M.intersects(a, b, se, ne, epsilon)
    or M.intersects(a, b, ne, nw, epsilon)
    or M.intersects(a, b, nw, sw, epsilon)
end

function M.distance_point(p, a, b)
  local px, py = xy(p)
  local ax, ay = xy(a)
  local bx, by = xy(b)
  local dx, dy = bx - ax, by - ay
  local length2 = dx * dx + dy * dy
  if length2 == 0 then
    local ox, oy = px - ax, py - ay
    return math.sqrt(ox * ox + oy * oy), point(ax, ay), 0
  end
  local t = ((px - ax) * dx + (py - ay) * dy) / length2
  t = number.clamp(t, 0, 1)
  local qx, qy = ax + t * dx, ay + t * dy
  local ox, oy = px - qx, py - qy
  return math.sqrt(ox * ox + oy * oy), point(qx, qy), t
end

M.intersects_closed = M.intersects
M.segment_rect_intersects = M.intersects_rect

return M
