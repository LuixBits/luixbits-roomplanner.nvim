local number = require("roomplan.geometry.number")
local footprint = require("roomplan.geometry.footprint")

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

function M.feature(axis, value2, kind, id, name, span)
  local result = { axis = axis, value2 = value2, kind = kind or "grid", id = id or "", name = name or "" }
  if type(span) == "table" then
    result.start2, result.finish2 = span.start2 or span[1], span.finish2 or span[2]
  end
  return result
end

local function normalized_feature(feature)
  return {
    axis = feature.axis,
    value2 = feature.value2 or (feature.value_mm and 2 * feature.value_mm) or 0,
    kind = feature.kind or "grid",
    id = feature.id or "",
    name = feature.name or "",
    start2 = feature.start2,
    finish2 = feature.finish2,
  }
end

local function spans_overlap(left, right)
  if left.start2 == nil or left.finish2 == nil or right.start2 == nil or right.finish2 == nil then
    return true
  end
  return math.max(left.start2, right.start2) < math.min(left.finish2, right.finish2)
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
      if (not options.axis or (moving.axis == options.axis and target.axis == options.axis))
        and (not options.require_overlap or spans_overlap(moving, target))
      then
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

local function axis_tolerance(tolerance, axis)
  if type(tolerance) ~= "table" then return tolerance or 0 end
  return axis == "x" and (tolerance.x or tolerance[1] or 0)
    or (tolerance.y or tolerance[2] or 0)
end

local function active_exclusions(exclusions, moving_x, moving_y, tolerance)
  local features = { x = moving_x or {}, y = moving_y or {} }
  local result = {}
  for _, exclusion in ipairs(exclusions or {}) do
    local maximum = axis_tolerance(tolerance, exclusion.axis) * 2
    for _, raw in ipairs(features[exclusion.axis] or {}) do
      local moving = normalized_feature(raw)
      if moving.id == exclusion.moving_id and moving.name == exclusion.moving_name
        and math.abs(moving.value2 - exclusion.value2) <= maximum
      then
        result[#result + 1] = exclusion
        break
      end
    end
  end
  return result
end

local function released_axis(exclusions, axis)
  for _, exclusion in ipairs(exclusions or {}) do
    if exclusion.axis == axis then return true end
  end
  return false
end

---Keep an axis released while its previously snapped edge remains inside the
---snap tolerance. This lets fine-step movement escape without snapping back
---to the old target or sideways to a nearby grid line.
function M.release_targets(exclusions, guides, axes)
  local result = {}
  for _, exclusion in ipairs(exclusions or {}) do result[#result + 1] = exclusion end
  for _, guide in ipairs(guides or {}) do
    if not axes or axes[guide.axis] then
      local next_exclusion = {
        axis = guide.axis,
        value2 = guide.value2 or (guide.value_mm and 2 * guide.value_mm),
        moving_id = guide.moving_id,
        moving_name = guide.moving_label,
      }
      local replaced = false
      for index, exclusion in ipairs(result) do
        if exclusion.axis == next_exclusion.axis
          and exclusion.moving_id == next_exclusion.moving_id
          and exclusion.moving_name == next_exclusion.moving_name
        then
          result[index] = next_exclusion
          replaced = true
          break
        end
      end
      if not replaced then result[#result + 1] = next_exclusion end
    end
  end
  return result
end

function M.guide(candidate)
  if not candidate then return nil end
  local result = {
    axis = candidate.target.axis,
    value2 = candidate.target.value2,
    value_mm = candidate.target.value2 / 2,
    target_kind = candidate.target.kind,
    target_id = candidate.target.id,
    target_label = candidate.target.name,
    moving_id = candidate.moving.id,
    moving_label = candidate.moving.name,
    delta_mm = candidate.delta_mm,
  }
  if candidate.moving.start2 ~= nil and candidate.target.start2 ~= nil then
    local start2 = math.max(candidate.moving.start2, candidate.target.start2)
    local finish2 = math.min(candidate.moving.finish2, candidate.target.finish2)
    if start2 < finish2 then
      result.overlap_start_mm = start2 / 2
      result.overlap_finish_mm = finish2 / 2
    end
  end
  return result
end

function M.guides(resolved)
  local result = {}
  -- Do not iterate `{ resolved.x, resolved.y }` with ipairs: a Y-only snap
  -- leaves index 1 nil, which ends the iteration before the Y guide.
  for _, axis in ipairs({ "x", "y" }) do
    local candidate = resolved and resolved[axis]
    local value = M.guide(candidate)
    if value then result[#result + 1] = value end
  end
  return result
end

function M.summary(guides)
  local labels = {}
  for _, guide in ipairs(guides or {}) do
    labels[#labels + 1] = string.format("%s → %s", guide.axis:upper(), guide.target_label)
  end
  return #labels > 0 and table.concat(labels, " · ") or nil
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
  local exclusions = active_exclusions(
    parameters.exclude_targets, parameters.moving_x, parameters.moving_y, tolerance
  )
  local xbest = not released_axis(exclusions, "x") and M.choose_axis(
    parameters.moving_x, parameters.target_x, tolerance_x, {
      axis = "x", priority = parameters.priority,
      mm_per_screen_unit = type(scale) == "table" and (scale.x or scale[1] or 1) or scale,
      require_overlap = parameters.require_overlap,
    }) or nil
  local ybest = not released_axis(exclusions, "y") and M.choose_axis(
    parameters.moving_y, parameters.target_y, tolerance_y, {
      axis = "y", priority = parameters.priority,
      mm_per_screen_unit = type(scale) == "table" and (scale.y or scale[2] or 1) or scale,
      require_overlap = parameters.require_overlap,
    }) or nil
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
    snap_exclusions = exclusions,
  }
end

local function add_grid_target(targets, moving_value2, axis, grid)
  if not grid or grid <= 0 then return end
  local nearest = number.round_to_grid(moving_value2 / 2, grid)
  targets[#targets + 1] = M.feature(axis, 2 * nearest, "grid", "grid", tostring(nearest))
end

local function room_features(room)
  local shape, shape_error = footprint.from_room(room)
  if not shape then return nil, shape_error end
  local bounds, bounds_error = footprint.bounds2(shape)
  if not bounds then return nil, bounds_error end
  local id = room.id or ""
  local label = tostring(room.name or id)
  return {
    x = {
      M.feature("x", bounds.left2, "room_edge", id, label .. " west wall", { bounds.bottom2, bounds.top2 }),
      M.feature("x", bounds.right2, "room_edge", id, label .. " east wall", { bounds.bottom2, bounds.top2 }),
      M.feature("x", bounds.center_x2, "room_center", id, label .. " horizontal centre"),
    },
    y = {
      M.feature("y", bounds.bottom2, "room_edge", id, label .. " south wall", { bounds.left2, bounds.right2 }),
      M.feature("y", bounds.top2, "room_edge", id, label .. " north wall", { bounds.left2, bounds.right2 }),
      M.feature("y", bounds.center_y2, "room_center", id, label .. " vertical centre"),
    },
  }
end

local function unsnapped(field, point, geometry_error)
  point = type(point) == "table" and point or { 0, 0 }
  return {
    [field] = { point[1], point[2] },
    delta_mm = { 0, 0 },
    delta2 = { 0, 0 },
    residual_mm = { 0, 0 },
    snapped = false,
    candidates = { x = nil, y = nil },
    geometry_error = geometry_error,
  }
end

function M.snap_room(proposed_room, other_rooms, options)
  options = options or {}
  local moving, moving_error = room_features(proposed_room)
  if not moving then return unsnapped("origin_mm", proposed_room.origin_mm, moving_error) end
  local tx, ty = {}, {}
  local geometry_error
  local i, j
  for i = 1, #(other_rooms or {}) do
    local other = other_rooms[i]
    if other.id ~= proposed_room.id then
      local features, feature_error = room_features(other)
      if features then
        for j = 1, #features.x do tx[#tx + 1] = features.x[j] end
        for j = 1, #features.y do ty[#ty + 1] = features.y[j] end
      else
        geometry_error = geometry_error or feature_error
      end
    end
  end
  for i = 1, #moving.x do add_grid_target(tx, moving.x[i].value2, "x", options.grid_mm) end
  for i = 1, #moving.y do add_grid_target(ty, moving.y[i].value2, "y", options.grid_mm) end
  local result = M.resolve({
    moving_x = moving.x, moving_y = moving.y, target_x = tx, target_y = ty,
    tolerance_mm = options.tolerance_mm, mm_per_screen_unit = options.mm_per_screen_unit,
    priority = options.priority, bypass = options.bypass,
    exclude_targets = options.exclude_targets,
  })
  result.origin_mm = {
    proposed_room.origin_mm[1] + result.delta_mm[1],
    proposed_room.origin_mm[2] + result.delta_mm[2],
  }
  result.geometry_error = geometry_error
  return result
end

local function furniture_features(room, furniture)
  local shape, shape_error = footprint.from_furniture(room, furniture)
  if not shape then return nil, shape_error end
  local bounds, bounds_error = footprint.bounds2(shape)
  if not bounds then return nil, bounds_error end
  local id = furniture.id or ""
  local label = tostring(furniture.name or id)
  return {
    x = {
      M.feature("x", bounds.left2, "furniture_edge", id, label .. " west edge", { bounds.bottom2, bounds.top2 }),
      M.feature("x", bounds.right2, "furniture_edge", id, label .. " east edge", { bounds.bottom2, bounds.top2 }),
      M.feature("x", bounds.center_x2, "furniture_center", id, label .. " horizontal centre"),
    },
    y = {
      M.feature("y", bounds.bottom2, "furniture_edge", id, label .. " south edge", { bounds.left2, bounds.right2 }),
      M.feature("y", bounds.top2, "furniture_edge", id, label .. " north edge", { bounds.left2, bounds.right2 }),
      M.feature("y", bounds.center_y2, "furniture_center", id, label .. " vertical centre"),
    },
  }
end

local function furniture_position(furniture)
  if furniture.position_mm ~= nil or furniture.footprint ~= nil then
    return "position_mm", furniture.position_mm
  end
  return "center_mm", furniture.center_mm
end

function M.snap_furniture(room, proposed, furniture_with_rooms, door_apertures, options)
  options = options or {}
  local position_field, position = furniture_position(proposed)
  local moving, moving_error = furniture_features(room, proposed)
  if not moving then return unsnapped(position_field, position, moving_error) end
  local tx, ty = {}, {}
  local geometry_error
  local room_target, room_error = room_features(room)
  local i, j
  if room_target then
    for i = 1, #room_target.x do tx[#tx + 1] = room_target.x[i] end
    for i = 1, #room_target.y do ty[#ty + 1] = room_target.y[i] end
  else
    geometry_error = room_error
  end
  for i = 1, #(furniture_with_rooms or {}) do
    local item = furniture_with_rooms[i]
    local furniture = item.furniture or item[1]
    local owner = item.room or item[2]
    if furniture and owner and furniture.id ~= proposed.id then
      local features, feature_error = furniture_features(owner, furniture)
      if features then
        for j = 1, #features.x do tx[#tx + 1] = features.x[j] end
        for j = 1, #features.y do ty[#ty + 1] = features.y[j] end
      else
        geometry_error = geometry_error or feature_error
      end
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
    exclude_targets = options.exclude_targets,
  })
  result[position_field] = {
    position[1] + result.delta_mm[1],
    position[2] + result.delta_mm[2],
  }
  result.geometry_error = geometry_error
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

return M
