-- Exact footprint transforms and stable local/world frame conversion.

local core = require("roomplan.geometry.footprint.core")
local internal = core._internal

local M = {}

local function translated_coordinate(value, delta, operation)
  local result, add_error = internal.checked_add(value, delta, operation)
  if result == nil then return nil, add_error end
  return internal.coordinate2(result, operation)
end

---Return a translated copy. Deltas are expressed in doubled millimetres.
function M.translate2(value, delta_x2, delta_y2)
  local normalized, err = core.normalize(value)
  if not normalized then return nil, err end
  if not internal.finite_integer(delta_x2) or not internal.finite_integer(delta_y2) then
    return internal.failure("FOOTPRINT_TRANSLATION", "footprint translation must use exact doubled-millimetre integers")
  end
  local _, delta_x_error = internal.checked_add(delta_x2, 0, "footprint translation X delta")
  if delta_x_error then return nil, delta_x_error end
  local _, delta_y_error = internal.checked_add(delta_y2, 0, "footprint translation Y delta")
  if delta_y_error then return nil, delta_y_error end
  local parts = {}
  for index = 1, #normalized.parts do
    local part = normalized.parts[index]
    local left2, left_error = translated_coordinate(part.left2, delta_x2, "translated left coordinate")
    if left2 == nil then return nil, left_error end
    local bottom2, bottom_error = translated_coordinate(part.bottom2, delta_y2, "translated bottom coordinate")
    if bottom2 == nil then return nil, bottom_error end
    local right2, right_error = translated_coordinate(part.right2, delta_x2, "translated right coordinate")
    if right2 == nil then return nil, right_error end
    local top2, top_error = translated_coordinate(part.top2, delta_y2, "translated top coordinate")
    if top2 == nil then return nil, top_error end
    parts[index] = {
      left2 = left2,
      bottom2 = bottom2,
      right2 = right2,
      top2 = top2,
    }
    if part.id then parts[index].id = part.id end
  end
  return core.normalize({ kind = core.KIND, parts = parts })
end

local function rotate_point2(x2, y2, rotation_deg, pivot_x2, pivot_y2)
  local dx, dx_error = internal.checked_subtract(x2, pivot_x2, "rotation X offset")
  if dx == nil then return nil, nil, dx_error end
  local dy, dy_error = internal.checked_subtract(y2, pivot_y2, "rotation Y offset")
  if dy == nil then return nil, nil, dy_error end
  local rotated_x2, rotated_y2
  if rotation_deg == 90 then
    rotated_x2, dx_error = internal.checked_subtract(pivot_x2, dy, "rotated X coordinate")
    rotated_y2, dy_error = internal.checked_add(pivot_y2, dx, "rotated Y coordinate")
  elseif rotation_deg == 180 then
    rotated_x2, dx_error = internal.checked_subtract(pivot_x2, dx, "rotated X coordinate")
    rotated_y2, dy_error = internal.checked_subtract(pivot_y2, dy, "rotated Y coordinate")
  elseif rotation_deg == 270 then
    rotated_x2, dx_error = internal.checked_add(pivot_x2, dy, "rotated X coordinate")
    rotated_y2, dy_error = internal.checked_subtract(pivot_y2, dx, "rotated Y coordinate")
  else
    rotated_x2, rotated_y2 = x2, y2
  end
  if rotated_x2 == nil then return nil, nil, dx_error end
  if rotated_y2 == nil then return nil, nil, dy_error end
  local _, x_range_error = internal.coordinate2(rotated_x2, "rotated X coordinate")
  if x_range_error then return nil, nil, x_range_error end
  local _, y_range_error = internal.coordinate2(rotated_y2, "rotated Y coordinate")
  if y_range_error then return nil, nil, y_range_error end
  return rotated_x2, rotated_y2
end

---Rotate a copy by a quarter turn around an exact doubled-mm pivot.
function M.rotate_quarter(value, rotation_deg, pivot_x2, pivot_y2)
  local normalized, err = core.normalize(value)
  if not normalized then return nil, err end
  rotation_deg = rotation_deg or 0
  pivot_x2, pivot_y2 = pivot_x2 or 0, pivot_y2 or 0
  if not internal.rotations[rotation_deg]
    or not internal.finite_integer(pivot_x2) or not internal.finite_integer(pivot_y2)
  then
    return internal.failure("FOOTPRINT_ROTATION", "rotation must be 0, 90, 180, or 270 around an exact doubled-mm pivot")
  end
  local _, pivot_x_error = internal.coordinate2(pivot_x2, "rotation pivot X")
  if pivot_x_error then return nil, pivot_x_error end
  local _, pivot_y_error = internal.coordinate2(pivot_y2, "rotation pivot Y")
  if pivot_y_error then return nil, pivot_y_error end
  local parts = {}
  for index = 1, #normalized.parts do
    local part = normalized.parts[index]
    local source_corners = {
      { part.left2, part.bottom2 },
      { part.right2, part.bottom2 },
      { part.right2, part.top2 },
      { part.left2, part.top2 },
    }
    local corners = {}
    for corner = 1, #source_corners do
      local x2, y2, corner_error = rotate_point2(
        source_corners[corner][1],
        source_corners[corner][2],
        rotation_deg,
        pivot_x2,
        pivot_y2
      )
      if x2 == nil then return nil, corner_error end
      corners[corner] = { x2, y2 }
    end
    local left2, right2 = corners[1][1], corners[1][1]
    local bottom2, top2 = corners[1][2], corners[1][2]
    for corner = 2, #corners do
      left2, right2 = math.min(left2, corners[corner][1]), math.max(right2, corners[corner][1])
      bottom2, top2 = math.min(bottom2, corners[corner][2]), math.max(top2, corners[corner][2])
    end
    parts[index] = { left2 = left2, bottom2 = bottom2, right2 = right2, top2 = top2 }
    if part.id then parts[index].id = part.id end
  end
  return core.normalize({ kind = core.KIND, parts = parts })
end

function M.translate(value, delta_x_mm, delta_y_mm)
  if not internal.finite_integer(delta_x_mm) or not internal.finite_integer(delta_y_mm) then
    return internal.failure("FOOTPRINT_TRANSLATION", "millimetre translation must use integers")
  end
  local delta_x2, delta_x_error = internal.checked_double(delta_x_mm, "footprint translation X delta")
  if delta_x2 == nil then return nil, delta_x_error end
  local delta_y2, delta_y_error = internal.checked_double(delta_y_mm, "footprint translation Y delta")
  if delta_y2 == nil then return nil, delta_y_error end
  return M.translate2(value, delta_x2, delta_y2)
end

---Apply a quarter turn and then a translation, preserving part IDs.
function M.transform2(value, options)
  options = options or {}
  local rotation = options.rotation_deg or 0
  local pivot_x2 = options.pivot_x2 or 0
  local pivot_y2 = options.pivot_y2 or 0
  local delta_x2 = options.delta_x2 or 0
  local delta_y2 = options.delta_y2 or 0
  local rotated, rotate_error = M.rotate_quarter(value, rotation, pivot_x2, pivot_y2)
  if not rotated then return nil, rotate_error end
  return M.translate2(rotated, delta_x2, delta_y2)
end

local function frame_coordinates(frame_or_x2, origin_y2)
  if type(frame_or_x2) == "table" then
    return frame_or_x2.origin_x2 or frame_or_x2.x2 or frame_or_x2[1],
      frame_or_x2.origin_y2 or frame_or_x2.y2 or frame_or_x2[2]
  end
  return frame_or_x2, origin_y2
end

function M.frame(origin_x2, origin_y2)
  if not internal.finite_integer(origin_x2) or not internal.finite_integer(origin_y2) then
    return internal.failure("FOOTPRINT_FRAME", "local-frame origins must use exact doubled-millimetre integers")
  end
  local _, origin_x_error = internal.coordinate2(origin_x2, "local-frame X origin")
  if origin_x_error then return nil, origin_x_error end
  local _, origin_y_error = internal.coordinate2(origin_y2, "local-frame Y origin")
  if origin_y_error then return nil, origin_y_error end
  return { origin_x2 = origin_x2, origin_y2 = origin_y2 }
end

---Express a world footprint relative to a stable object-local frame.
---Returns both the local footprint and the owned frame descriptor.
function M.to_local(value, frame_or_x2, origin_y2)
  local origin_x2
  origin_x2, origin_y2 = frame_coordinates(frame_or_x2, origin_y2)
  local frame, frame_error = M.frame(origin_x2, origin_y2)
  if not frame then return nil, frame_error end
  local delta_x2, delta_x_error = internal.checked_subtract(0, origin_x2, "local-frame X inverse")
  if delta_x2 == nil then return nil, delta_x_error end
  local delta_y2, delta_y_error = internal.checked_subtract(0, origin_y2, "local-frame Y inverse")
  if delta_y2 == nil then return nil, delta_y_error end
  local local_shape, err = M.translate2(value, delta_x2, delta_y2)
  if not local_shape then return nil, err end
  return local_shape, frame
end

function M.from_local(value, frame_or_x2, origin_y2)
  local origin_x2
  origin_x2, origin_y2 = frame_coordinates(frame_or_x2, origin_y2)
  local frame, frame_error = M.frame(origin_x2, origin_y2)
  if not frame then return nil, frame_error end
  return M.translate2(value, frame.origin_x2, frame.origin_y2)
end

return M
