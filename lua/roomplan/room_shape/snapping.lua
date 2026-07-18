-- Pure snapping for transient room, furniture, and project-template section
-- drafts. All matching happens in world space; resolved deltas are converted
-- back to the edited object's local quarter-turned axes before changing
-- persisted geometry.

local footprint = require("roomplan.geometry.footprint")
local number = require("roomplan.geometry.number")
local snapping = require("roomplan.geometry.snapping")

local M = {}

local function part_features(part, kind, id, label)
  local left2, bottom2, right2, top2 = part.left2, part.bottom2, part.right2, part.top2
  kind = kind or "room_edge"
  return {
    west = snapping.feature("x", left2, kind, id, label .. " west edge", { bottom2, top2 }),
    east = snapping.feature("x", right2, kind, id, label .. " east edge", { bottom2, top2 }),
    south = snapping.feature("y", bottom2, kind, id, label .. " south edge", { left2, right2 }),
    north = snapping.feature("y", top2, kind, id, label .. " north edge", { left2, right2 }),
  }
end

local function append(target, values)
  for _, value in ipairs(values or {}) do target[#target + 1] = value end
end

local function persisted_world_shape(edit, context)
  if context and type(context.world_shape) == "function" then return context.world_shape(edit) end
  local shape = footprint.from_persisted(edit.footprint)
  local origin = context and context.origin_mm
  if shape and type(origin) == "table" then shape = footprint.translate(shape, origin[1], origin[2]) end
  return shape
end

local function runtime_part(shape, id)
  for _, part in ipairs(shape and shape.parts or {}) do
    if part.id == id then return part end
  end
end

local function append_edges(targets, features)
  append(targets.x, { features.west, features.east })
  append(targets.y, { features.south, features.north })
end

local function append_bounds(targets, bounds, kind, id, label)
  if not bounds then return end
  append_edges(targets, part_features(bounds, kind, id, label))
end

local function target_features(edit, model, context)
  local targets = { x = {}, y = {} }
  local current_shape = persisted_world_shape(edit, context)
  for index, part in ipairs(current_shape and current_shape.parts or {}) do
    if part.id ~= edit.selected_part_id then
      append_edges(targets, part_features(
        part,
        edit.kind == "furniture" and "furniture_edge"
          or edit.kind == "template" and "template_edge" or "room_edge",
        tostring(edit.entity_id or edit.room_id) .. "/" .. tostring(part.id),
        "Section " .. index
      ))
    end
  end
  -- A project template is edited in an isolated local preview. Its own section
  -- boundaries and the grid are meaningful; plan walls and placed objects are
  -- deliberately not presented as template geometry constraints.
  if edit.kind == "template" then return targets end
  for _, other in ipairs(model.rooms or {}) do
    if edit.kind ~= "room" or other.id ~= (edit.entity_id or edit.room_id) then
      local shape = footprint.from_room(other)
      local boundary = shape and footprint.exterior_boundary2(shape) or nil
      for _, segment in ipairs(boundary or {}) do
        local axis = segment.axis == "x" and "y" or "x"
        local label = tostring(other.name or other.id) .. " " .. tostring(segment.side) .. " wall"
        targets[axis][#targets[axis] + 1] = snapping.feature(
          axis, segment.fixed2, "room_edge", other.id, label, { segment.start2, segment.finish2 }
        )
      end
    end
  end
  for _, other in ipairs(model.furniture or {}) do
    if edit.kind ~= "furniture" or other.id ~= edit.entity_id then
      local owner
      for _, candidate in ipairs(model.rooms or {}) do
        if candidate.id == other.room_id then owner = candidate; break end
      end
      local shape = owner and footprint.from_furniture(owner, other) or nil
      append_bounds(targets, shape and footprint.bounds2(shape), "furniture_edge", other.id,
        tostring(other.name or other.id))
    end
  end
  return targets
end

local rotated_sides = {
  [0] = { west = "west", east = "east", south = "south", north = "north" },
  [90] = { west = "south", east = "north", south = "east", north = "west" },
  [180] = { west = "east", east = "west", south = "north", north = "south" },
  [270] = { west = "north", east = "south", south = "west", north = "east" },
}

local function moving_features(edit, context, dx, dy)
  local shape = persisted_world_shape(edit, context)
  local part = runtime_part(shape, edit.selected_part_id)
  if not part then return { x = {}, y = {} } end
  local features = part_features(part,
    edit.kind == "furniture" and "furniture_edge"
      or edit.kind == "template" and "template_edge" or "room_edge",
    tostring(edit.entity_id or edit.room_id) .. "/" .. tostring(part.id), "Selected section")
  local edges = edit.resize_edges or {}
  local side_map = rotated_sides[edit.rotation_deg or 0] or rotated_sides[0]
  local result = { x = {}, y = {} }
  local sides = {}
  if dx ~= 0 then sides[#sides + 1] = edges.x end
  if dy ~= 0 then sides[#sides + 1] = edges.y end
  for _, side in ipairs(sides) do
    local feature = side and features[side_map[side]] or nil
    if feature then result[feature.axis][#result[feature.axis] + 1] = feature end
  end
  return result
end

local function add_grid_targets(targets, moving, grid_mm)
  if type(grid_mm) ~= "number" or grid_mm <= 0 then return end
  for axis, features in pairs(moving) do
    for _, feature in ipairs(features) do
      local nearest = number.round_to_grid(feature.value2 / 2, grid_mm)
      targets[axis][#targets[axis] + 1] = snapping.feature(
        axis, 2 * nearest, "grid", "grid", "Grid " .. tostring(nearest) .. " mm"
      )
    end
  end
end

local function local_delta(edit, dx, dy)
  local rotation = edit.rotation_deg or 0
  if rotation == 90 then return dy, -dx end
  if rotation == 180 then return -dx, -dy end
  if rotation == 270 then return -dy, dx end
  return dx, dy
end

local function world_delta(edit, dx, dy)
  local rotation = edit.rotation_deg or 0
  if rotation == 90 then return -dy, dx end
  if rotation == 180 then return -dx, -dy end
  if rotation == 270 then return dy, -dx end
  return dx, dy
end

function M.apply(edit, part, dx, dy, context)
  local options = context and context.options
  if type(options) ~= "table" then return edit end
  local model = context.model
  if type(model) ~= "table" then return edit end

  local moving = moving_features(edit, context, dx, dy)
  local targets = target_features(edit, model, context)
  local function resolve()
    return snapping.resolve({
      moving_x = moving.x,
      moving_y = moving.y,
      target_x = targets.x,
      target_y = targets.y,
      tolerance_mm = options.tolerance_mm,
      mm_per_screen_unit = options.mm_per_screen_unit,
      priority = options.priority,
      bypass = options.bypass,
      require_overlap = true,
      exclude_targets = edit.snap_exclusions,
    })
  end

  local resolved = resolve()
  if not resolved.snapped then
    add_grid_targets(targets, moving, options.grid_mm)
    resolved = resolve()
  end
  local delta_x, delta_y = local_delta(edit, resolved.delta_mm[1], resolved.delta_mm[2])
  local edges = edit.resize_edges or {}
  if edges.x == "west" then
    part.origin_mm[1] = part.origin_mm[1] + delta_x
    part.size_mm[1] = part.size_mm[1] - delta_x
  else
    part.size_mm[1] = part.size_mm[1] + delta_x
  end
  if edges.y == "south" then
    part.origin_mm[2] = part.origin_mm[2] + delta_y
    part.size_mm[2] = part.size_mm[2] - delta_y
  else
    part.size_mm[2] = part.size_mm[2] + delta_y
  end
  edit.snap_exclusions = resolved.snap_exclusions or {}
  edit.snap_guides = snapping.guides(resolved)
  return edit
end

function M.release(edit, dx, dy)
  dx, dy = world_delta(edit, dx, dy)
  edit.snap_exclusions = snapping.release_targets(edit.snap_exclusions, edit.snap_guides, {
    x = dx ~= 0,
    y = dy ~= 0,
  })
  edit.snap_guides = {}
  return edit
end

function M.summary(edit)
  return snapping.summary(edit.snap_guides)
end

return M
