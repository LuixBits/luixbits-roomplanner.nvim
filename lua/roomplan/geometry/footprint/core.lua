-- Rect-union construction, normalization, and topology invariants.

local M = {}

M.KIND = "rect_union"
M.DEFAULT_MAX_PARTS = 256

local MAX_SAFE_INTEGER = 9007199254740991
M.MAX_ABS_COORDINATE2 = math.floor(MAX_SAFE_INTEGER / 2)

local MAX_ABS_COORDINATE2 = M.MAX_ABS_COORDINATE2
local ROTATIONS = { [0] = true, [90] = true, [180] = true, [270] = true }

local function valid_part_id(value)
  return type(value) == "string"
    and #value <= 128
    and value:match("^part%-%w[%w._-]*$") ~= nil
end

local function failure(code, message, details)
  return nil, { code = code, message = message, details = details or {} }
end

local function finite_integer(value)
  return type(value) == "number"
    and value == value
    and value ~= math.huge
    and value ~= -math.huge
    and value == math.floor(value)
end

local function integer(value)
  return finite_integer(value) and math.abs(value) <= MAX_SAFE_INTEGER
end

local function positive_integer(value)
  return integer(value) and value > 0
end

local function finite_number(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function range_failure(operation, details)
  details = details or {}
  details.max_safe_integer = MAX_SAFE_INTEGER
  details.max_abs_coordinate2 = MAX_ABS_COORDINATE2
  return failure("FOOTPRINT_RANGE", operation .. " exceeds the exact footprint coordinate domain", details)
end

local function coordinate2(value, operation, details)
  if not integer(value) or math.abs(value) > MAX_ABS_COORDINATE2 then
    details = details or {}
    details.value = value
    return range_failure(operation or "doubled-millimetre coordinate", details)
  end
  return value
end

local function coordinate_number2(value, operation, details)
  if not finite_number(value) or math.abs(value) > MAX_ABS_COORDINATE2 then
    details = details or {}
    details.value = value
    return range_failure(operation or "doubled-millimetre coordinate", details)
  end
  return value
end

local function checked_add(left, right, operation)
  if not integer(left) or not integer(right) then return range_failure(operation) end
  if (right > 0 and left > MAX_SAFE_INTEGER - right)
    or (right < 0 and left < -MAX_SAFE_INTEGER - right)
  then
    return range_failure(operation)
  end
  return left + right
end

local function checked_subtract(left, right, operation)
  if not integer(left) or not integer(right) then return range_failure(operation) end
  if (right > 0 and left < -MAX_SAFE_INTEGER + right)
    or (right < 0 and left > MAX_SAFE_INTEGER + right)
  then
    return range_failure(operation)
  end
  return left - right
end

local function checked_double(value, operation)
  if not integer(value) or math.abs(value) > math.floor(MAX_SAFE_INTEGER / 2) then
    return range_failure(operation)
  end
  return value + value
end

local function checked_midpoint(left, right, operation)
  local sum, err = checked_add(left, right, operation)
  if sum == nil then return nil, err end
  return sum / 2
end

local function checked_double_coordinate_number(value, operation)
  if not finite_number(value) or math.abs(value) > MAX_ABS_COORDINATE2 / 2 then
    return range_failure(operation)
  end
  return value + value
end

local function safe_product(left, right, operation)
  if not integer(left) or not integer(right) or left < 0 or right < 0 then
    return range_failure(operation)
  end
  if left ~= 0 and right > math.floor(MAX_SAFE_INTEGER / left) then
    return range_failure(operation)
  end
  return left * right
end

local function safe_sum(total, value, operation)
  if not integer(total) or not integer(value) or total < 0 or value < 0 then
    return range_failure(operation)
  end
  if value > MAX_SAFE_INTEGER - total then
    return range_failure(operation)
  end
  return total + value
end

local function part_copy(part, index)
  if type(part) ~= "table" then
    return failure("FOOTPRINT_PART", "footprint part " .. index .. " must be a table", { index = index })
  end
  local left2, bottom2 = part.left2, part.bottom2
  local right2, top2 = part.right2, part.top2
  if not finite_integer(left2) or not finite_integer(bottom2)
    or not finite_integer(right2) or not finite_integer(top2)
  then
    return failure("FOOTPRINT_COORDINATE", "footprint part coordinates must be exact doubled-millimetre integers", {
      index = index,
    })
  end
  local coordinates = {
    { "left2", left2 }, { "bottom2", bottom2 }, { "right2", right2 }, { "top2", top2 },
  }
  for coordinate_index = 1, #coordinates do
    local coordinate = coordinates[coordinate_index]
    local _, range_error = coordinate2(coordinate[2], "footprint part coordinate", {
      index = index,
      field = coordinate[1],
    })
    if range_error then return nil, range_error end
  end
  if left2 >= right2 or bottom2 >= top2 then
    return failure("FOOTPRINT_DIMENSION", "footprint parts must have positive width and depth", { index = index })
  end
  local _, width_error = checked_subtract(right2, left2, "footprint part width")
  if width_error then return nil, width_error end
  local _, depth_error = checked_subtract(top2, bottom2, "footprint part depth")
  if depth_error then return nil, depth_error end
  if part.id ~= nil and not valid_part_id(part.id) then
    return failure("FOOTPRINT_PART_ID", "footprint part IDs must match part-<name>; names start with a letter, digit, or underscore, use only letters, digits, '.', '_', or '-', and are at most 128 bytes", {
      index = index,
    })
  end
  local result = { left2 = left2, bottom2 = bottom2, right2 = right2, top2 = top2 }
  if part.id ~= nil then result.id = part.id end
  return result
end

local function overlaps_positive(a, b)
  return math.max(a.left2, b.left2) < math.min(a.right2, b.right2)
    and math.max(a.bottom2, b.bottom2) < math.min(a.top2, b.top2)
end

local function shared_edge2(a, b)
  if a.right2 == b.left2 or b.right2 == a.left2 then
    local start2 = math.max(a.bottom2, b.bottom2)
    local finish2 = math.min(a.top2, b.top2)
    if start2 < finish2 then
      local a_west_of_b = a.right2 == b.left2
      local length2, length_error = checked_subtract(finish2, start2, "shared-edge length")
      if length2 == nil then return nil, length_error end
      return {
        axis = "y",
        fixed2 = a_west_of_b and a.right2 or b.right2,
        start2 = start2,
        finish2 = finish2,
        length2 = length2,
        a_side = a_west_of_b and "east" or "west",
        b_side = a_west_of_b and "west" or "east",
      }
    end
  end
  if a.top2 == b.bottom2 or b.top2 == a.bottom2 then
    local start2 = math.max(a.left2, b.left2)
    local finish2 = math.min(a.right2, b.right2)
    if start2 < finish2 then
      local a_south_of_b = a.top2 == b.bottom2
      local length2, length_error = checked_subtract(finish2, start2, "shared-edge length")
      if length2 == nil then return nil, length_error end
      return {
        axis = "x",
        fixed2 = a_south_of_b and a.top2 or b.top2,
        start2 = start2,
        finish2 = finish2,
        length2 = length2,
        a_side = a_south_of_b and "north" or "south",
        b_side = a_south_of_b and "south" or "north",
      }
    end
  end
  return nil
end

local function connected_components_parts(parts)
  local adjacency = {}
  for index = 1, #parts do adjacency[index] = {} end
  for left = 1, #parts do
    for right = left + 1, #parts do
      local edge, edge_error = shared_edge2(parts[left], parts[right])
      if edge_error then return nil, edge_error end
      if edge then
        adjacency[left][#adjacency[left] + 1] = right
        adjacency[right][#adjacency[right] + 1] = left
      end
    end
  end

  local seen, components = {}, {}
  for first = 1, #parts do
    if not seen[first] then
      local component, queue, cursor = {}, { first }, 1
      seen[first] = true
      while cursor <= #queue do
        local index = queue[cursor]
        cursor = cursor + 1
        component[#component + 1] = index
        for _, neighbour in ipairs(adjacency[index]) do
          if not seen[neighbour] then
            seen[neighbour] = true
            queue[#queue + 1] = neighbour
          end
        end
      end
      table.sort(component)
      components[#components + 1] = component
    end
  end
  return components
end

local function dense_count(values)
  local count, maximum = 0, 0
  for key in pairs(values) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then return nil end
    count = count + 1
    maximum = math.max(maximum, key)
  end
  if count ~= maximum then return nil end
  return count
end

local function unique_sorted(values)
  table.sort(values)
  local result = {}
  for index = 1, #values do
    if index == 1 or values[index] ~= values[index - 1] then result[#result + 1] = values[index] end
  end
  return result
end

local function covering_part(parts, left2, bottom2, right2, top2)
  for index = 1, #parts do
    local part = parts[index]
    if part.left2 <= left2 and part.bottom2 <= bottom2 and part.right2 >= right2 and part.top2 >= top2 then
      return index
    end
  end
  return nil
end

-- Coordinate-compressed complement traversal. Empty cells on the bounds are
-- outside; any positive-area empty cell not reachable from them is a hole.
local function has_holes_parts(parts)
  local xs, ys = {}, {}
  for index = 1, #parts do
    local part = parts[index]
    xs[#xs + 1] = part.left2
    xs[#xs + 1] = part.right2
    ys[#ys + 1] = part.bottom2
    ys[#ys + 1] = part.top2
  end
  xs, ys = unique_sorted(xs), unique_sorted(ys)
  if #xs < 2 or #ys < 2 then return false end

  local empty, outside, queue = {}, {}, {}
  local x_cells, y_cells = #xs - 1, #ys - 1
  local function key(x, y) return x .. ":" .. y end
  for x = 1, x_cells do
    for y = 1, y_cells do
      if not covering_part(parts, xs[x], ys[y], xs[x + 1], ys[y + 1]) then
        local cell_key = key(x, y)
        empty[cell_key] = true
        if x == 1 or x == x_cells or y == 1 or y == y_cells then
          outside[cell_key] = true
          queue[#queue + 1] = { x, y }
        end
      end
    end
  end

  local cursor = 1
  while cursor <= #queue do
    local cell = queue[cursor]
    cursor = cursor + 1
    local neighbours = {
      { cell[1] - 1, cell[2] },
      { cell[1] + 1, cell[2] },
      { cell[1], cell[2] - 1 },
      { cell[1], cell[2] + 1 },
    }
    for index = 1, #neighbours do
      local x, y = neighbours[index][1], neighbours[index][2]
      if x >= 1 and x <= x_cells and y >= 1 and y <= y_cells then
        local neighbour_key = key(x, y)
        if empty[neighbour_key] and not outside[neighbour_key] then
          outside[neighbour_key] = true
          queue[#queue + 1] = { x, y }
        end
      end
    end
  end

  for cell_key in pairs(empty) do
    if not outside[cell_key] then return true end
  end
  return false
end

local function assign_missing_ids(parts, prefix)
  prefix = prefix or "part-"
  if type(prefix) ~= "string" or prefix == "" then
    return failure("FOOTPRINT_PART_ID", "part ID prefixes must be non-empty strings")
  end
  local used, missing = {}, {}
  for index = 1, #parts do
    local id = parts[index].id
    if id then
      if used[id] then
        return failure("FOOTPRINT_PART_ID_DUPLICATE", "footprint part IDs must be unique", {
          id = id,
          first_index = used[id],
          second_index = index,
        })
      end
      used[id] = index
    else
      missing[#missing + 1] = index
    end
  end
  table.sort(missing, function(left_index, right_index)
    local left, right = parts[left_index], parts[right_index]
    if left.left2 ~= right.left2 then return left.left2 < right.left2 end
    if left.bottom2 ~= right.bottom2 then return left.bottom2 < right.bottom2 end
    if left.right2 ~= right.right2 then return left.right2 < right.right2 end
    if left.top2 ~= right.top2 then return left.top2 < right.top2 end
    return left_index < right_index
  end)
  local serial = 1
  for _, index in ipairs(missing) do
    local candidate
    repeat
      candidate = prefix .. tostring(serial)
      serial = serial + 1
    until not used[candidate]
    if not valid_part_id(candidate) then
      return failure("FOOTPRINT_PART_ID", "generated footprint part ID does not match the part-<name> contract", {
        id = candidate,
      })
    end
    parts[index].id = candidate
    used[candidate] = index
  end
  return parts
end

---Normalize a runtime footprint into an owned, non-overlapping rect union.
---Touching parts are allowed; positive-area overlaps are rejected so later
---area, containment, and boundary operations have one unambiguous invariant.
---@param value table
---@return table|nil footprint
---@return table|nil error
function M.normalize(value, options)
  if type(value) ~= "table" or value.kind ~= M.KIND or type(value.parts) ~= "table" then
    return failure("FOOTPRINT_SHAPE", "footprint must be a rect_union with a parts array")
  end
  local part_count = dense_count(value.parts)
  if not part_count then
    return failure("FOOTPRINT_PARTS_ARRAY", "footprint parts must be a dense positive-integer array")
  end
  if part_count == 0 then
    return failure("FOOTPRINT_EMPTY", "footprint must contain at least one rectangle")
  end

  options = options or {}
  if options.max_parts and part_count > options.max_parts then
    return failure("FOOTPRINT_PART_LIMIT", "footprint contains too many parts", {
      count = part_count,
      maximum = options.max_parts,
    })
  end
  local result = { kind = M.KIND, parts = {} }
  local ids = {}
  for index = 1, #value.parts do
    local part, err = part_copy(value.parts[index], index)
    if not part then return nil, err end
    if part.id then
      if ids[part.id] then
        return failure("FOOTPRINT_PART_ID_DUPLICATE", "footprint part IDs must be unique", {
          id = part.id,
          first_index = ids[part.id],
          second_index = index,
        })
      end
      ids[part.id] = index
    elseif options.require_ids then
      return failure("FOOTPRINT_PART_ID", "every footprint part requires a stable ID matching the part-<name> contract", {
        index = index,
      })
    end
    for previous = 1, #result.parts do
      if overlaps_positive(part, result.parts[previous]) then
        return failure("FOOTPRINT_PART_OVERLAP", "footprint parts must not overlap with positive area", {
          first_index = previous,
          second_index = index,
        })
      end
    end
    result.parts[index] = part
  end
  if options.assign_ids then
    local assigned, assign_error = assign_missing_ids(result.parts, options.id_prefix)
    if not assigned then return nil, assign_error end
  end
  if options.require_connected then
    local components, components_error = connected_components_parts(result.parts)
    if not components then return nil, components_error end
    if #components ~= 1 then
      return failure("FOOTPRINT_DISCONNECTED", "footprint parts must form one component through positive shared edges")
    end
  end
  if options.reject_holes and has_holes_parts(result.parts) then
    return failure("FOOTPRINT_HOLE", "footprint parts must not enclose holes")
  end
  return result
end

---Construct one rectangular footprint from exact doubled-mm bounds.
function M.rectangle2(left2, bottom2, right2, top2)
  return M.normalize({
    kind = M.KIND,
    parts = {
      { left2 = left2, bottom2 = bottom2, right2 = right2, top2 = top2 },
    },
  })
end

---Construct one rectangular footprint from integer-mm origin and dimensions.
function M.rectangle(left, bottom, width, depth)
  if not finite_integer(left) or not finite_integer(bottom)
    or not finite_integer(width) or not finite_integer(depth) or width <= 0 or depth <= 0
  then
    return failure("FOOTPRINT_RECTANGLE", "rectangle origin and dimensions must use integer millimetres")
  end
  local left2, left_error = checked_double(left, "rectangle left coordinate")
  if left2 == nil then return nil, left_error end
  local _, left_range_error = coordinate2(left2, "rectangle left coordinate")
  if left_range_error then return nil, left_range_error end
  local bottom2, bottom_error = checked_double(bottom, "rectangle bottom coordinate")
  if bottom2 == nil then return nil, bottom_error end
  local _, bottom_range_error = coordinate2(bottom2, "rectangle bottom coordinate")
  if bottom_range_error then return nil, bottom_range_error end
  local width2, width_error = checked_double(width, "rectangle width")
  if width2 == nil then return nil, width_error end
  local depth2, depth_error = checked_double(depth, "rectangle depth")
  if depth2 == nil then return nil, depth_error end
  local right2, right_error = checked_add(left2, width2, "rectangle right coordinate")
  if right2 == nil then return nil, right_error end
  local _, right_range_error = coordinate2(right2, "rectangle right coordinate")
  if right_range_error then return nil, right_range_error end
  local top2, top_error = checked_add(bottom2, depth2, "rectangle top coordinate")
  if top2 == nil then return nil, top_error end
  local _, top_range_error = coordinate2(top2, "rectangle top coordinate")
  if top_range_error then return nil, top_range_error end
  return M.rectangle2(left2, bottom2, right2, top2)
end

---Normalize authored compound parts with stable IDs and one connected
---positive-edge component. Missing IDs are assigned deterministically from
---the local geometry and then survive every transform.
function M.compound(parts, options)
  options = options or {}
  local maximum = M.DEFAULT_MAX_PARTS
  if options.max_parts ~= nil then
    if not finite_integer(options.max_parts) or options.max_parts < 0 then
      return failure("FOOTPRINT_PART_LIMIT", "compound max_parts must be a non-negative integer")
    end
    maximum = math.min(options.max_parts, maximum)
  end
  local require_ids = options.require_ids == true
  return M.normalize({ kind = M.KIND, parts = parts }, {
    assign_ids = not require_ids,
    require_ids = require_ids,
    require_connected = true,
    reject_holes = true,
    max_parts = maximum,
    id_prefix = options.id_prefix,
  })
end

function M.with_part_ids(value, prefix)
  return M.normalize(value, { assign_ids = true, id_prefix = prefix })
end

function M.part_id(part, index)
  if type(part) == "table" and valid_part_id(part.id) then return part.id end
  return "part-" .. tostring(index)
end

function M.shared_edge2(left, right)
  local a, a_error = part_copy(left, 1)
  if not a then return nil, a_error end
  local b, b_error = part_copy(right, 2)
  if not b then return nil, b_error end
  return shared_edge2(a, b)
end

function M.connected_components(value)
  local normalized, err = M.normalize(value)
  if not normalized then return nil, err end
  local raw, raw_error = connected_components_parts(normalized.parts)
  if not raw then return nil, raw_error end
  local result = {}
  for component_index = 1, #raw do
    local indexes, ids = {}, {}
    for _, part_index in ipairs(raw[component_index]) do
      indexes[#indexes + 1] = part_index
      ids[#ids + 1] = M.part_id(normalized.parts[part_index], part_index)
    end
    result[component_index] = { indexes = indexes, part_ids = ids }
  end
  return result
end

function M.is_connected(value)
  local components, err = M.connected_components(value)
  if not components then return nil, err end
  return #components == 1, components
end

function M.validate_connected(value, options)
  options = options or {}
  return M.normalize(value, {
    assign_ids = options.assign_ids == true,
    require_ids = options.require_ids == true,
    require_connected = true,
    reject_holes = options.reject_holes == true,
    max_parts = options.max_parts,
    id_prefix = options.id_prefix,
  })
end

function M.has_holes(value)
  local normalized, err = M.normalize(value)
  if not normalized then return nil, err end
  return has_holes_parts(normalized.parts)
end

-- Private helpers shared by the other footprint modules. They are deliberately
-- kept off the public facade in geometry/footprint.lua.
M._internal = {
  rotations = ROTATIONS,
  failure = failure,
  finite_integer = finite_integer,
  integer = integer,
  positive_integer = positive_integer,
  finite_number = finite_number,
  coordinate2 = coordinate2,
  coordinate_number2 = coordinate_number2,
  checked_add = checked_add,
  checked_subtract = checked_subtract,
  checked_double = checked_double,
  checked_midpoint = checked_midpoint,
  checked_double_coordinate_number = checked_double_coordinate_number,
  safe_product = safe_product,
  safe_sum = safe_sum,
  overlaps_positive = overlaps_positive,
  unique_sorted = unique_sorted,
  has_holes_parts = has_holes_parts,
}

return M
