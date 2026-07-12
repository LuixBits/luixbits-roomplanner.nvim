local number = require("roomplan.geometry.number")
local rect = require("roomplan.geometry.rect")

local M = {}

local default_priority = {
  door = 1,
  room_edge = 2,
  room_corner = 2,
  room_center = 3,
  furniture = 4,
  furniture_edge = 4,
  furniture_center = 4,
  grid = 5,
}

local function priority_map(value)
  if type(value) ~= "table" then return default_priority end
  if #value > 0 then
    local result = {}
    local i
    for i = 1, #value do result[value[i]] = i end
    if result.furniture then
      result.furniture_edge = result.furniture_edge or result.furniture
      result.furniture_center = result.furniture_center or result.furniture
    end
    if result.room_edge then result.room_corner = result.room_corner or result.room_edge end
    return result
  end
  return value
end

function M.feature(axis, value2, kind, id, name)
  return { axis = axis, value2 = value2, kind = kind or "grid", id = id or "", name = name or "" }
end

local function normalized_feature(feature)
  return {
    axis = feature.axis,
    value2 = feature.value2 or (feature.value_mm and 2 * feature.value_mm) or 0,
    kind = feature.kind or "grid",
    id = feature.id or "",
    name = feature.name or "",
  }
end

local function candidate_less(a, b)
  if a.screen_distance ~= b.screen_distance then return a.screen_distance < b.screen_distance end
  if a.priority ~= b.priority then return a.priority < b.priority end
  if a.target.id ~= b.target.id then return a.target.id < b.target.id end
  if a.target.name ~= b.target.name then return a.target.name < b.target.name end
  if a.delta2 ~= b.delta2 then return a.delta2 < b.delta2 end
  if a.moving.name ~= b.moving.name then return a.moving.name < b.moving.name end
  return a.moving.id < b.moving.id
end

function M.choose_axis(moving_features, target_features, tolerance_mm, options)
  options = options or {}
  tolerance_mm = tolerance_mm or 0
  local scale = options.mm_per_screen_unit or 1
  if scale <= 0 then scale = 1 end
  local priorities = priority_map(options.priority)
  local candidates = {}
  local i, j
  for i = 1, #(moving_features or {}) do
    local moving = normalized_feature(moving_features[i])
    for j = 1, #(target_features or {}) do
      local target = normalized_feature(target_features[j])
      if not options.axis or (moving.axis == options.axis and target.axis == options.axis) then
        local delta2 = target.value2 - moving.value2
        if math.abs(delta2) <= tolerance_mm * 2 then
          candidates[#candidates + 1] = {
            moving = moving,
            target = target,
            delta2 = delta2,
            delta_mm = delta2 / 2,
            screen_distance = math.abs(delta2 / 2) / scale,
            priority = priorities[target.kind] or 1000,
          }
        end
      end
    end
  end
  table.sort(candidates, candidate_less)
  return candidates[1], candidates
end

-- Resolve independent X/Y corrections. Features use exact doubled-mm values,
-- allowing odd-width furniture edges and centres without floating drift.
function M.resolve(parameters)
  parameters = parameters or {}
  if parameters.bypass then
    return {
      delta_mm = { 0, 0 }, delta2 = { 0, 0 }, residual_mm = { 0, 0 },
      snapped = false, candidates = {},
    }
  end
  local tolerance = parameters.tolerance_mm or 0
  local tolerance_x = type(tolerance) == "table" and (tolerance.x or tolerance[1]) or tolerance
  local tolerance_y = type(tolerance) == "table" and (tolerance.y or tolerance[2]) or tolerance
  local scale = parameters.mm_per_screen_unit or {}
  local xbest = M.choose_axis(parameters.moving_x, parameters.target_x, tolerance_x, {
    axis = "x", priority = parameters.priority,
    mm_per_screen_unit = type(scale) == "table" and (scale.x or scale[1] or 1) or scale,
  })
  local ybest = M.choose_axis(parameters.moving_y, parameters.target_y, tolerance_y, {
    axis = "y", priority = parameters.priority,
    mm_per_screen_unit = type(scale) == "table" and (scale.y or scale[2] or 1) or scale,
  })
  local dx2 = xbest and xbest.delta2 or 0
  local dy2 = ybest and ybest.delta2 or 0
  local dx, rx = number.from_doubled(dx2)
  local dy, ry = number.from_doubled(dy2)
  return {
    delta_mm = { dx, dy },
    delta2 = { dx2, dy2 },
    residual_mm = { rx, ry },
    snapped = xbest ~= nil or ybest ~= nil,
    x = xbest,
    y = ybest,
    candidates = { x = xbest, y = ybest },
  }
end

local function add_grid_target(targets, moving_value2, axis, grid)
  if not grid or grid <= 0 then return end
  local nearest = number.round_to_grid(moving_value2 / 2, grid)
  targets[#targets + 1] = M.feature(axis, 2 * nearest, "grid", "grid", tostring(nearest))
end

local function room_features(room)
  local x2 = 2 * room.origin_mm[1]
  local y2 = 2 * room.origin_mm[2]
  local width2 = 2 * room.size_mm[1]
  local depth2 = 2 * room.size_mm[2]
  local id = room.id or ""
  return {
    x = {
      M.feature("x", x2, "room_edge", id, "west"),
      M.feature("x", x2 + width2, "room_edge", id, "east"),
      M.feature("x", x2 + room.size_mm[1], "room_center", id, "center-x"),
    },
    y = {
      M.feature("y", y2, "room_edge", id, "south"),
      M.feature("y", y2 + depth2, "room_edge", id, "north"),
      M.feature("y", y2 + room.size_mm[2], "room_center", id, "center-y"),
    },
  }
end

M.room_features = room_features

function M.snap_room(proposed_room, other_rooms, options)
  options = options or {}
  local moving = room_features(proposed_room)
  local tx, ty = {}, {}
  local i, j
  for i = 1, #(other_rooms or {}) do
    local other = other_rooms[i]
    if other.id ~= proposed_room.id then
      local features = room_features(other)
      for j = 1, #features.x do tx[#tx + 1] = features.x[j] end
      for j = 1, #features.y do ty[#ty + 1] = features.y[j] end
    end
  end
  for i = 1, #moving.x do add_grid_target(tx, moving.x[i].value2, "x", options.grid_mm) end
  for i = 1, #moving.y do add_grid_target(ty, moving.y[i].value2, "y", options.grid_mm) end
  local result = M.resolve({
    moving_x = moving.x, moving_y = moving.y, target_x = tx, target_y = ty,
    tolerance_mm = options.tolerance_mm, mm_per_screen_unit = options.mm_per_screen_unit,
    priority = options.priority, bypass = options.bypass,
  })
  result.origin_mm = {
    proposed_room.origin_mm[1] + result.delta_mm[1],
    proposed_room.origin_mm[2] + result.delta_mm[2],
  }
  return result
end

function M.furniture_features(room, furniture)
  local bounds = rect.furniture_rect2(room, furniture)
  local id = furniture.id or ""
  return {
    x = {
      M.feature("x", bounds.left2, "furniture_edge", id, "west"),
      M.feature("x", bounds.right2, "furniture_edge", id, "east"),
      M.feature("x", bounds.center_x2, "furniture_center", id, "center-x"),
    },
    y = {
      M.feature("y", bounds.bottom2, "furniture_edge", id, "south"),
      M.feature("y", bounds.top2, "furniture_edge", id, "north"),
      M.feature("y", bounds.center_y2, "furniture_center", id, "center-y"),
    },
  }
end

function M.snap_furniture(room, proposed, furniture_with_rooms, door_apertures, options)
  options = options or {}
  local moving = M.furniture_features(room, proposed)
  local tx, ty = {}, {}
  local room_target = room_features(room)
  local i, j
  for i = 1, #room_target.x do tx[#tx + 1] = room_target.x[i] end
  for i = 1, #room_target.y do ty[#ty + 1] = room_target.y[i] end
  for i = 1, #(furniture_with_rooms or {}) do
    local item = furniture_with_rooms[i]
    local furniture = item.furniture or item[1]
    local owner = item.room or item[2]
    if furniture and owner and furniture.id ~= proposed.id then
      local features = M.furniture_features(owner, furniture)
      for j = 1, #features.x do tx[#tx + 1] = features.x[j] end
      for j = 1, #features.y do ty[#ty + 1] = features.y[j] end
    end
  end
  for i = 1, #(door_apertures or {}) do
    local aperture = door_apertures[i]
    local id = aperture.id or ""
    if aperture.axis == "x" then
      tx[#tx + 1] = M.feature("x", 2 * aperture.start_mm, "door", id, "start")
      tx[#tx + 1] = M.feature("x", 2 * aperture.finish_mm, "door", id, "finish")
      ty[#ty + 1] = M.feature("y", 2 * aperture.fixed_mm, "door", id, "wall")
    else
      ty[#ty + 1] = M.feature("y", 2 * aperture.start_mm, "door", id, "start")
      ty[#ty + 1] = M.feature("y", 2 * aperture.finish_mm, "door", id, "finish")
      tx[#tx + 1] = M.feature("x", 2 * aperture.fixed_mm, "door", id, "wall")
    end
  end
  for i = 1, #moving.x do add_grid_target(tx, moving.x[i].value2, "x", options.grid_mm) end
  for i = 1, #moving.y do add_grid_target(ty, moving.y[i].value2, "y", options.grid_mm) end
  local result = M.resolve({
    moving_x = moving.x, moving_y = moving.y, target_x = tx, target_y = ty,
    tolerance_mm = options.tolerance_mm, mm_per_screen_unit = options.mm_per_screen_unit,
    priority = options.priority, bypass = options.bypass,
  })
  result.center_mm = {
    proposed.center_mm[1] + result.delta_mm[1],
    proposed.center_mm[2] + result.delta_mm[2],
  }
  return result
end

function M.snap_door_offset(offset_mm, width_mm, edge_length_mm, targets_mm, options)
  options = options or {}
  if options.bypass then
    return { offset_mm = offset_mm, delta_mm = 0, snapped = false }
  end
  local moving = {
    M.feature("offset", 2 * offset_mm, "door", options.id or "", "start"),
    M.feature("offset", 2 * (offset_mm + width_mm), "door", options.id or "", "finish"),
  }
  local targets = {
    M.feature("offset", 0, "room_edge", "wall", "start"),
    M.feature("offset", 2 * edge_length_mm, "room_edge", "wall", "finish"),
  }
  local i
  for i = 1, #(targets_mm or {}) do
    local target = targets_mm[i]
    targets[#targets + 1] = M.feature("offset", 2 * (target.value_mm or target[1] or target),
      target.kind or "door", target.id or "", target.name or tostring(i))
  end
  if options.grid_mm and options.grid_mm > 0 then
    for i = 1, #moving do add_grid_target(targets, moving[i].value2, "offset", options.grid_mm) end
  end
  local best = M.choose_axis(moving, targets, options.tolerance_mm or 0, {
    axis = "offset", priority = options.priority, mm_per_screen_unit = options.mm_per_screen_unit,
  })
  local delta2 = best and best.delta2 or 0
  local delta, residual = number.from_doubled(delta2)
  local proposed = number.clamp(offset_mm + delta, 0, math.max(0, edge_length_mm - width_mm))
  return { offset_mm = proposed, delta_mm = proposed - offset_mm, residual_mm = residual,
    snapped = best ~= nil, candidate = best }
end

M.room = M.snap_room
M.furniture = M.snap_furniture
M.door_offset = M.snap_door_offset
M.snap = M.resolve
M.grid = number.round_to_grid

return M
