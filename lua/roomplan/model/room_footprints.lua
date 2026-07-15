-- Small, canonical room-footprint presets for schema v2 authoring.

local json = require("roomplan.codec.json")
local number = require("roomplan.geometry.number")
local entities = require("roomplan.model.entities")

local M = {}

local CORNERS = {
  northeast = true,
  northwest = true,
  southeast = true,
  southwest = true,
}

local function invalid(field, message)
  return nil, { code = "ROOM_FOOTPRINT_PRESET", field = field, message = message }
end

local function dimension(value, field, label)
  if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge
    or value ~= math.floor(value) or value <= 0 or value > number.MAX_LOCAL_DIMENSION
  then
    return invalid(field, label .. " must be a positive whole number of millimetres")
  end
  return value
end

local function part(id, x, y, width, depth)
  return json.object({
    id = id,
    origin_mm = json.array({ x, y }),
    size_mm = json.array({ width, depth }),
  })
end

local function integer(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
    and value == math.floor(value)
end

local function persisted_dimension(value)
  return integer(value) and value > 0 and value <= number.MAX_LOCAL_DIMENSION
end

local function tuple2(value)
  if type(value) ~= "table" or not integer(value[1]) or not integer(value[2]) then return false end
  for key in pairs(value) do if key ~= 1 and key ~= 2 then return false end end
  return true
end

local function exact_keys(value, allowed)
  if type(value) ~= "table" then return false end
  for key in pairs(value) do if not allowed[key] then return false end end
  return true
end

local function l_shape(options, width, depth)
  local leg_width, err = dimension(options.leg_width_mm, "leg_width_mm", "Vertical leg width")
  if not leg_width then return nil, err end
  local leg_depth
  leg_depth, err = dimension(options.leg_depth_mm, "leg_depth_mm", "Horizontal leg depth")
  if not leg_depth then return nil, err end
  if leg_width >= width then
    return invalid("leg_width_mm", "Vertical leg width must be smaller than the overall width")
  end
  if leg_depth >= depth then
    return invalid("leg_depth_mm", "Horizontal leg depth must be smaller than the overall depth")
  end

  local corner = options.missing_corner or "northeast"
  if not CORNERS[corner] then return invalid("missing_corner", "Choose a valid missing corner") end

  local horizontal_y = (corner == "northeast" or corner == "northwest") and 0 or (depth - leg_depth)
  local vertical_x = (corner == "northeast" or corner == "southeast") and 0 or (width - leg_width)
  local vertical_y = (corner == "northeast" or corner == "northwest") and leg_depth or 0

  return json.object({
    kind = "rect_union",
    parts = json.array({
      part("part-horizontal", 0, horizontal_y, width, leg_depth),
      part("part-vertical", vertical_x, vertical_y, leg_width, depth - leg_depth),
    }),
  })
end

function M.build(options)
  options = options or {}
  local width, err = dimension(options.width_mm, "width_mm", "Overall width")
  if not width then return nil, err end
  local depth
  depth, err = dimension(options.depth_mm, "depth_mm", "Overall depth")
  if not depth then return nil, err end

  local shape = options.shape or "rectangle"
  if shape == "rectangle" then return entities.rectangle_footprint({ width, depth }) end
  if shape == "l_shape" then return l_shape(options, width, depth) end
  return invalid("shape", "Choose a supported room shape")
end

-- Recognize only the canonical presets emitted above. Unknown compound
-- footprints deliberately remain read-only in the ordinary room form.
function M.classify(value)
  if not exact_keys(value, { kind = true, parts = true })
    or value.kind ~= "rect_union" or not exact_keys(value.parts, { [1] = true, [2] = true })
  then
    return nil
  end
  if #value.parts == 1 then
    local main = value.parts[1]
    if not exact_keys(main, { id = true, origin_mm = true, size_mm = true }) or main.id ~= "part-main"
      or not tuple2(main.origin_mm) or not tuple2(main.size_mm)
      or main.origin_mm[1] ~= 0 or main.origin_mm[2] ~= 0
      or not persisted_dimension(main.size_mm[1]) or not persisted_dimension(main.size_mm[2])
    then
      return nil
    end
    return { shape = "rectangle", width_mm = main.size_mm[1], depth_mm = main.size_mm[2] }
  end
  if #value.parts ~= 2 then return nil end

  local horizontal, vertical = value.parts[1], value.parts[2]
  if not exact_keys(horizontal, { id = true, origin_mm = true, size_mm = true })
    or not exact_keys(vertical, { id = true, origin_mm = true, size_mm = true })
    or horizontal.id ~= "part-horizontal" or vertical.id ~= "part-vertical"
    or not tuple2(horizontal.origin_mm) or not tuple2(horizontal.size_mm)
    or not tuple2(vertical.origin_mm) or not tuple2(vertical.size_mm)
  then
    return nil
  end

  local width = horizontal.size_mm[1]
  local leg_depth = horizontal.size_mm[2]
  local leg_width = vertical.size_mm[1]
  local remainder_depth = vertical.size_mm[2]
  if horizontal.origin_mm[1] ~= 0
    or not persisted_dimension(width) or not persisted_dimension(leg_depth)
    or not persisted_dimension(leg_width) or not persisted_dimension(remainder_depth)
    or leg_width >= width
  then
    return nil
  end
  local depth = leg_depth + remainder_depth
  if depth > number.MAX_LOCAL_DIMENSION then return nil end
  local missing_vertical
  if horizontal.origin_mm[2] == 0 and vertical.origin_mm[2] == leg_depth then
    missing_vertical = "north"
  elseif vertical.origin_mm[2] == 0 and horizontal.origin_mm[2] == remainder_depth then
    missing_vertical = "south"
  else
    return nil
  end
  local missing_horizontal
  if vertical.origin_mm[1] == 0 then
    missing_horizontal = "east"
  elseif vertical.origin_mm[1] == width - leg_width then
    missing_horizontal = "west"
  else
    return nil
  end

  return {
    shape = "l_shape",
    width_mm = width,
    depth_mm = depth,
    leg_width_mm = leg_width,
    leg_depth_mm = leg_depth,
    missing_corner = missing_vertical .. missing_horizontal,
  }
end

return M
