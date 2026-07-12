local number = require("roomplan.geometry.number")
local segment = require("roomplan.geometry.segment")

local M = {}
local pi = math.pi
local two_pi = 2 * pi

local function point(x, y)
  return { x = x, y = y, [1] = x, [2] = y }
end

local function xy(value)
  return value.x or value[1], value.y or value[2]
end

local function atan2(y, x)
  if x > 0 then return math.atan(y / x) end
  if x < 0 and y >= 0 then return math.atan(y / x) + pi end
  if x < 0 and y < 0 then return math.atan(y / x) - pi end
  if x == 0 and y > 0 then return pi / 2 end
  if x == 0 and y < 0 then return -pi / 2 end
  return 0
end

local function positive_angle(angle)
  angle = angle % two_pi
  if angle < 0 then angle = angle + two_pi end
  return angle
end

function M.new(hinge, closed_endpoint, sweep_radians)
  local hx, hy = xy(hinge)
  local cx, cy = xy(closed_endpoint)
  local vx, vy = cx - hx, cy - hy
  local radius = math.sqrt(vx * vx + vy * vy)
  local start_angle = atan2(vy, vx)
  local finish_angle = start_angle + sweep_radians
  local open_x = radius * math.cos(finish_angle)
  local open_y = radius * math.sin(finish_angle)
  return {
    hinge = point(hx, hy),
    closed_endpoint = point(cx, cy),
    open_endpoint = point(hx + open_x, hy + open_y),
    closed_vector = point(vx, vy),
    open_vector = point(open_x, open_y),
    radius = radius,
    start_angle = start_angle,
    finish_angle = finish_angle,
    sweep_radians = sweep_radians,
  }
end

local function vector_from_hinge(sector, endpoint, stored)
  if stored then return stored.x or stored[1], stored.y or stored[2] end
  local hx, hy = xy(sector.hinge)
  local ex, ey = xy(endpoint)
  return ex - hx, ey - hy
end


-- Translate a sector to a small local coordinate frame. Collision predicates
-- use this instead of subtracting already-rounded world-space trig endpoints,
-- which keeps results stable near the schema's large-coordinate ceiling.
function M.localize(sector, origin_x, origin_y)
  origin_x = origin_x or (sector.hinge.x or sector.hinge[1])
  origin_y = origin_y or (sector.hinge.y or sector.hinge[2])
  local hx, hy = xy(sector.hinge)
  local cvx, cvy = vector_from_hinge(sector, sector.closed_endpoint, sector.closed_vector)
  local ovx, ovy = vector_from_hinge(sector, sector.open_endpoint, sector.open_vector)
  local local_hinge = point(hx - origin_x, hy - origin_y)
  return {
    hinge = local_hinge,
    closed_endpoint = point(local_hinge.x + cvx, local_hinge.y + cvy),
    open_endpoint = point(local_hinge.x + ovx, local_hinge.y + ovy),
    closed_vector = point(cvx, cvy),
    open_vector = point(ovx, ovy),
    radius = sector.radius,
    start_angle = sector.start_angle,
    finish_angle = sector.finish_angle,
    sweep_radians = sector.sweep_radians,
    _local = true,
  }
end

local function translated_point(value, origin_x, origin_y)
  local x, y = xy(value)
  return point(x - origin_x, y - origin_y)
end

local function translated_options(options, origin_x, origin_y)
  local result = {}
  local key, value
  for key, value in pairs(options or {}) do result[key] = value end
  if options and options.exclude_points then
    result.exclude_points = {}
    local i
    for i = 1, #options.exclude_points do
      result.exclude_points[i] = translated_point(options.exclude_points[i], origin_x, origin_y)
    end
  end
  return result
end

function M.angle_in_sweep(sector, angle, epsilon)
  epsilon = epsilon or number.local_epsilon(sector.radius) / math.max(1, sector.radius)
  if sector.sweep_radians >= 0 then
    return positive_angle(angle - sector.start_angle) <= sector.sweep_radians + epsilon
  end
  return positive_angle(sector.start_angle - angle) <= -sector.sweep_radians + epsilon
end

function M.vector_in_sweep(sector, dx, dy, epsilon)
  if dx == 0 and dy == 0 then return true end
  return M.angle_in_sweep(sector, atan2(dy, dx), epsilon)
end

function M.contains_point(sector, value, include_boundary)
  local px, py = xy(value)
  local hx, hy = xy(sector.hinge)
  local dx, dy = px - hx, py - hy
  local radius2 = dx * dx + dy * dy
  local epsilon = number.local_epsilon(sector.radius, dx, dy)
  if include_boundary == false then
    if radius2 >= (sector.radius - epsilon) * (sector.radius - epsilon) then return false end
  elseif radius2 > (sector.radius + epsilon) * (sector.radius + epsilon) then
    return false
  end
  if radius2 <= epsilon * epsilon then return include_boundary ~= false end
  return M.vector_in_sweep(sector, dx, dy, epsilon / math.max(1, sector.radius))
end

function M.aabb(sector)
  local hx, hy = xy(sector.hinge)
  local points = { sector.hinge, sector.closed_endpoint, sector.open_endpoint }
  local cardinals = { 0, pi / 2, pi, 3 * pi / 2 }
  local i
  for i = 1, #cardinals do
    local angle = cardinals[i]
    if M.angle_in_sweep(sector, angle) then
      points[#points + 1] = point(hx + sector.radius * math.cos(angle), hy + sector.radius * math.sin(angle))
    end
  end
  local left, right, bottom, top = hx, hx, hy, hy
  for i = 1, #points do
    local x, y = xy(points[i])
    left, right = math.min(left, x), math.max(right, x)
    bottom, top = math.min(bottom, y), math.max(top, y)
  end
  return { left = left, right = right, bottom = bottom, top = top }
end

local function point_near(a, b, epsilon)
  local ax, ay = xy(a)
  local bx, by = xy(b)
  local dx, dy = ax - bx, ay - by
  return dx * dx + dy * dy <= epsilon * epsilon
end

local function excluded(value, exclusions, epsilon)
  local i
  for i = 1, #(exclusions or {}) do
    if point_near(value, exclusions[i], epsilon) then return true end
  end
  return false
end

function M.circle_segment_intersections(center, radius, a, b)
  local cx, cy = xy(center)
  local ax, ay = xy(a)
  local bx, by = xy(b)
  ax, ay, bx, by = ax - cx, ay - cy, bx - cx, by - cy
  local dx, dy = bx - ax, by - ay
  local aa = dx * dx + dy * dy
  if aa == 0 then return {} end
  local bb = 2 * (ax * dx + ay * dy)
  local cc = ax * ax + ay * ay - radius * radius
  local discriminant = bb * bb - 4 * aa * cc
  local epsilon = number.local_epsilon(radius, dx, dy)
  local discriminant_scale = math.abs(bb * bb) + math.abs(4 * aa * cc)
  local discriminant_epsilon = math.max(1e-12, 128 * 2 ^ -52 * math.max(1, discriminant_scale))
  if discriminant < -discriminant_epsilon then return {} end
  discriminant = math.max(0, discriminant)
  local root = math.sqrt(discriminant)
  local values = { (-bb - root) / (2 * aa) }
  if root > epsilon then values[#values + 1] = (-bb + root) / (2 * aa) end
  local result = {}
  local i
  for i = 1, #values do
    local t = values[i]
    if t >= -epsilon and t <= 1 + epsilon then
      result[#result + 1] = point(cx + ax + t * dx, cy + ay + t * dy)
    end
  end
  return result
end

-- Inclusive filled-sector/segment predicate. Optional exclude_points suppresses
-- designed contacts only when every detected contact is one of those points.
function M.intersects_segment(sector, a, b, options)
  options = options or {}
  if not sector._local then
    local hx, hy = xy(sector.hinge)
    return M.intersects_segment(M.localize(sector, hx, hy), translated_point(a, hx, hy),
      translated_point(b, hx, hy), translated_options(options, hx, hy))
  end
  local epsilon = number.local_epsilon(sector.radius)
  local contacts = {}
  local function add(value, kind)
    contacts[#contacts + 1] = { point = value, kind = kind }
  end
  if M.contains_point(sector, a, true) then add(a, "endpoint") end
  if M.contains_point(sector, b, true) then add(b, "endpoint") end
  local hit, kind, value = segment.intersection(a, b, sector.hinge, sector.closed_endpoint, epsilon)
  if hit then
    if kind == "overlap" then add(value[1], "closed-radial"); add(value[2], "closed-radial")
    else add(value, "closed-radial") end
  end
  hit, kind, value = segment.intersection(a, b, sector.hinge, sector.open_endpoint, epsilon)
  if hit then
    if kind == "overlap" then add(value[1], "open-radial"); add(value[2], "open-radial")
    else add(value, "open-radial") end
  end
  local circle_hits = M.circle_segment_intersections(sector.hinge, sector.radius, a, b)
  local i
  for i = 1, #circle_hits do
    local px, py = xy(circle_hits[i])
    local hx, hy = xy(sector.hinge)
    if M.vector_in_sweep(sector, px - hx, py - hy) then add(circle_hits[i], "arc") end
  end
  if #contacts == 0 then return false, { contacts = contacts } end
  for i = 1, #contacts do
    if not excluded(contacts[i].point, options.exclude_points, epsilon) then
      return true, { contacts = contacts, contact = contacts[i] }
    end
  end
  return false, { contacts = contacts, excluded = true }
end

function M.intersects_rect(sector, rectangle)
  if not sector._local then
    local hx, hy = xy(sector.hinge)
    return M.intersects_rect(M.localize(sector, hx, hy), {
      left = rectangle.left - hx,
      right = rectangle.right - hx,
      bottom = rectangle.bottom - hy,
      top = rectangle.top - hy,
    })
  end
  local box = M.aabb(sector)
  local epsilon = number.local_epsilon(sector.radius, rectangle.right - rectangle.left, rectangle.top - rectangle.bottom)
  if box.right < rectangle.left - epsilon or box.left > rectangle.right + epsilon
    or box.top < rectangle.bottom - epsilon or box.bottom > rectangle.top + epsilon
  then
    return false
  end
  local corners = {
    point(rectangle.left, rectangle.bottom), point(rectangle.right, rectangle.bottom),
    point(rectangle.right, rectangle.top), point(rectangle.left, rectangle.top),
  }
  local hx, hy = xy(sector.hinge)
  if hx >= rectangle.left - epsilon and hx <= rectangle.right + epsilon
    and hy >= rectangle.bottom - epsilon and hy <= rectangle.top + epsilon then
    return true, { kind = "hinge-inside" }
  end
  local i
  for i = 1, #corners do
    if M.contains_point(sector, corners[i], true) then return true, { kind = "corner", point = corners[i] } end
  end
  for i = 1, 4 do
    local a = corners[i]
    local b = corners[(i % 4) + 1]
    local hit, details = M.intersects_segment(sector, a, b)
    if hit then return true, { kind = "edge", edge = i, details = details } end
  end
  return false
end

local function circle_circle_intersections(c0, r0, c1, r1)
  local x0, y0 = xy(c0)
  local x1, y1 = xy(c1)
  local dx, dy = x1 - x0, y1 - y0
  local distance = math.sqrt(dx * dx + dy * dy)
  local epsilon = number.local_epsilon(r0, r1, distance)
  if distance > r0 + r1 + epsilon or distance < math.abs(r0 - r1) - epsilon or distance <= epsilon then
    return {}
  end
  local a = (r0 * r0 - r1 * r1 + distance * distance) / (2 * distance)
  local h2 = math.max(0, r0 * r0 - a * a)
  local h = math.sqrt(h2)
  local xm, ym = x0 + a * dx / distance, y0 + a * dy / distance
  local rx, ry = -dy * h / distance, dx * h / distance
  if h <= epsilon then return { point(xm, ym) } end
  return { point(xm + rx, ym + ry), point(xm - rx, ym - ry) }
end

function M.intersects_sector(a, b, options)
  options = options or {}
  if not a._local or not b._local then
    local origin_x, origin_y = xy(a.hinge)
    return M.intersects_sector(M.localize(a, origin_x, origin_y), M.localize(b, origin_x, origin_y),
      translated_options(options, origin_x, origin_y))
  end
  local abox, bbox = M.aabb(a), M.aabb(b)
  local epsilon = number.local_epsilon(a.radius, b.radius)
  if abox.right < bbox.left - epsilon or bbox.right < abox.left - epsilon
    or abox.top < bbox.bottom - epsilon or bbox.top < abox.bottom - epsilon then return false end
  local points_a = { a.hinge, a.closed_endpoint, a.open_endpoint }
  local points_b = { b.hinge, b.closed_endpoint, b.open_endpoint }
  local i
  for i = 1, #points_a do
    if M.contains_point(b, points_a[i], true) and not excluded(points_a[i], options.exclude_points, epsilon) then
      return true, { kind = "a-point-in-b", point = points_a[i] }
    end
  end
  for i = 1, #points_b do
    if M.contains_point(a, points_b[i], true) and not excluded(points_b[i], options.exclude_points, epsilon) then
      return true, { kind = "b-point-in-a", point = points_b[i] }
    end
  end
  local boundaries_a = { { a.hinge, a.closed_endpoint }, { a.hinge, a.open_endpoint } }
  for i = 1, #boundaries_a do
    local hit = M.intersects_segment(b, boundaries_a[i][1], boundaries_a[i][2], options)
    if hit then return true, { kind = "a-radial-in-b" } end
  end
  local boundaries_b = { { b.hinge, b.closed_endpoint }, { b.hinge, b.open_endpoint } }
  for i = 1, #boundaries_b do
    local hit = M.intersects_segment(a, boundaries_b[i][1], boundaries_b[i][2], options)
    if hit then return true, { kind = "b-radial-in-a" } end
  end
  local circle_hits = circle_circle_intersections(a.hinge, a.radius, b.hinge, b.radius)
  for i = 1, #circle_hits do
    local px, py = xy(circle_hits[i])
    local ahx, ahy = xy(a.hinge)
    local bhx, bhy = xy(b.hinge)
    if M.vector_in_sweep(a, px - ahx, py - ahy) and M.vector_in_sweep(b, px - bhx, py - bhy)
      and not excluded(circle_hits[i], options.exclude_points, epsilon) then
      return true, { kind = "arc-arc", point = circle_hits[i] }
    end
  end
  return false
end

M.atan2 = atan2
M.point = point
M.intersects_rectangle = M.intersects_rect
M.intersects_wall_segment = M.intersects_segment

return M
