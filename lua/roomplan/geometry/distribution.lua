-- Deterministic equal-gap distribution for placed furniture. Geometry is
-- measured from exact doubled-millimetre world bounds, while persisted anchor
-- positions remain on RoomPlan's integer-millimetre lattice.

local footprint = require("roomplan.geometry.footprint")

local M = {}

local function failure(code, message, details)
  return nil, { code = code, message = message, details = details or {} }
end

local function find(values, id)
  for _, value in ipairs(values or {}) do
    if value.id == id then return value end
  end
end

local axes = {
  horizontal = {
    position_index = 1,
    minimum = "left2",
    maximum = "right2",
    size = "width2",
  },
  vertical = {
    position_index = 2,
    minimum = "bottom2",
    maximum = "top2",
    size = "depth2",
  },
}

local function balanced_gaps(items, axis, free2)
  local count = #items - 1
  local parities, minimum_total = {}, 0
  for index = 1, count do
    local parity = (items[index + 1].bounds[axis.minimum] - items[index].bounds[axis.maximum]) % 2
    parities[index] = parity
    minimum_total = minimum_total + parity
  end
  if free2 < minimum_total then
    return failure(
      "DISTRIBUTION_SPAN",
      "the outer furniture does not leave enough representable space between every item",
      { free2 = free2, minimum_free2 = minimum_total }
    )
  end

  local quotient = math.floor(free2 / count)
  local gaps, used = {}, 0
  for index = 1, count do
    local parity = parities[index]
    local gap2
    if quotient < parity then
      gap2 = parity
    else
      gap2 = quotient - ((quotient - parity) % 2)
    end
    gaps[index] = gap2
    used = used + gap2
  end

  local remainder = free2 - used
  if remainder < 0 or remainder % 2 ~= 0 then
    return failure("DISTRIBUTION_GEOMETRY", "furniture gaps cannot be represented on the integer-millimetre lattice")
  end
  while remainder > 0 do
    local candidate = 1
    for index = 2, count do
      if gaps[index] < gaps[candidate] then candidate = index end
    end
    gaps[candidate] = gaps[candidate] + 2
    remainder = remainder - 2
  end
  return gaps
end

---Propose equal clear spacing for every furniture item in one room.
---The first and last items in the chosen visual order remain fixed.
function M.propose(model, room_id, axis_name, options)
  options = options or {}
  if type(model) ~= "table" then return failure("DISTRIBUTION_MODEL", "a plan is required") end
  local axis = axes[axis_name]
  if not axis then
    return failure("DISTRIBUTION_AXIS", "axis must be horizontal or vertical", { axis = axis_name })
  end
  local room = find(model.rooms, room_id)
  if not room then return failure("DISTRIBUTION_ROOM_REQUIRED", "choose an existing room", { room_id = room_id }) end
  if options.selected_id then
    local selected = find(model.furniture, options.selected_id)
    if not selected or selected.room_id ~= room.id then
      return failure("DISTRIBUTION_SELECTION", "the selected furniture is no longer in this room", {
        selected_id = options.selected_id,
        room_id = room.id,
      })
    end
  end

  local position_field = (model.schema_version or 1) >= 2 and "position_mm" or "center_mm"
  local items = {}
  for _, furniture in ipairs(model.furniture or {}) do
    if furniture.room_id == room.id then
      local shape, shape_error = footprint.from_furniture(room, furniture)
      if not shape then return nil, shape_error end
      local bounds, bounds_error = footprint.bounds2(shape)
      if not bounds then return nil, bounds_error end
      local position = furniture[position_field]
      if type(position) ~= "table" or type(position[1]) ~= "number" or type(position[2]) ~= "number" then
        return failure("DISTRIBUTION_GEOMETRY", "furniture is missing its placement coordinates", {
          id = furniture.id,
          field = position_field,
        })
      end
      items[#items + 1] = {
        id = furniture.id,
        name = furniture.name or furniture.id,
        bounds = bounds,
        position = { position[1], position[2] },
      }
    end
  end
  if #items < 3 then
    return failure("DISTRIBUTION_COUNT", "add at least three furniture items to this room", {
      room_id = room.id,
      count = #items,
    })
  end

  table.sort(items, function(left, right)
    local left_center = left.bounds[axis.minimum] + left.bounds[axis.maximum]
    local right_center = right.bounds[axis.minimum] + right.bounds[axis.maximum]
    if left_center ~= right_center then return left_center < right_center end
    if left.bounds[axis.minimum] ~= right.bounds[axis.minimum] then
      return left.bounds[axis.minimum] < right.bounds[axis.minimum]
    end
    return left.id < right.id
  end)

  local first, last = items[1], items[#items]
  local span2 = last.bounds[axis.maximum] - first.bounds[axis.minimum]
  local total_size2 = 0
  for _, item in ipairs(items) do
    local size2 = item.bounds[axis.size]
    if size2 > span2 - total_size2 then
      return failure(
        "DISTRIBUTION_SPAN",
        "the outer furniture does not leave enough space for non-overlapping equal gaps",
        { room_id = room.id, axis = axis_name, span2 = span2 }
      )
    end
    total_size2 = total_size2 + size2
  end
  local free2 = span2 - total_size2
  local gaps, gap_error = balanced_gaps(items, axis, free2)
  if not gaps then return nil, gap_error end

  local target_min2 = first.bounds[axis.minimum]
  local changed_count, minimum_gap2, maximum_gap2 = 0, gaps[1], gaps[1]
  for index, item in ipairs(items) do
    if index > 1 then
      target_min2 = target_min2 + gaps[index - 1]
    end
    local delta2 = target_min2 - item.bounds[axis.minimum]
    if delta2 % 2 ~= 0 then
      return failure("DISTRIBUTION_GEOMETRY", "a distributed position fell outside the integer-millimetre lattice", {
        id = item.id,
        delta2 = delta2,
      })
    end
    local delta_mm = delta2 / 2
    item.delta_mm = delta_mm
    item.target_position = { item.position[1], item.position[2] }
    item.target_position[axis.position_index] = item.target_position[axis.position_index] + delta_mm
    if delta_mm ~= 0 then changed_count = changed_count + 1 end
    target_min2 = target_min2 + item.bounds[axis.size]
    if index <= #gaps then
      minimum_gap2 = math.min(minimum_gap2, gaps[index])
      maximum_gap2 = math.max(maximum_gap2, gaps[index])
    end
  end

  return {
    axis = axis_name,
    room_id = room.id,
    room_name = room.name or room.id,
    position_field = position_field,
    items = items,
    gaps2 = gaps,
    minimum_gap2 = minimum_gap2,
    maximum_gap2 = maximum_gap2,
    exact = minimum_gap2 == maximum_gap2,
    changed_count = changed_count,
    first_id = first.id,
    last_id = last.id,
  }
end

return M
