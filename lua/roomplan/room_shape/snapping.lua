-- Pure snapping for transient room-section drafts. Structural edges are
-- resolved before the grid so visible room geometry remains the useful target.

local footprint = require("roomplan.geometry.footprint")
local number = require("roomplan.geometry.number")
local snapping = require("roomplan.geometry.snapping")

local M = {}

local function part_features(part, origin_mm, id, label)
  local left2 = 2 * (origin_mm[1] + part.origin_mm[1])
  local bottom2 = 2 * (origin_mm[2] + part.origin_mm[2])
  local right2 = left2 + 2 * part.size_mm[1]
  local top2 = bottom2 + 2 * part.size_mm[2]
  return {
    x = {
      snapping.feature("x", left2, "room_edge", id, label .. " west edge", { bottom2, top2 }),
      snapping.feature("x", right2, "room_edge", id, label .. " east edge", { bottom2, top2 }),
    },
    y = {
      snapping.feature("y", bottom2, "room_edge", id, label .. " south edge", { left2, right2 }),
      snapping.feature("y", top2, "room_edge", id, label .. " north edge", { left2, right2 }),
    },
  }
end

local function append(target, values)
  for _, value in ipairs(values or {}) do target[#target + 1] = value end
end

local function target_features(edit, model, origin_mm)
  local targets = { x = {}, y = {} }
  for index, part in ipairs(edit.footprint.parts or {}) do
    if part.id ~= edit.selected_part_id then
      local features = part_features(part, origin_mm, edit.room_id .. "/" .. part.id, "Section " .. index)
      append(targets.x, features.x)
      append(targets.y, features.y)
    end
  end
  for _, other in ipairs(model.rooms or {}) do
    if other.id ~= edit.room_id then
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
  return targets
end

local function moving_features(edit, part, origin_mm, dx, dy)
  local features = part_features(part, origin_mm, edit.room_id .. "/" .. part.id, "Selected section")
  local edges = edit.resize_edges or {}
  features.x = dx ~= 0 and { features.x[edges.x == "west" and 1 or 2] } or {}
  features.y = dy ~= 0 and { features.y[edges.y == "south" and 1 or 2] } or {}
  return features
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

function M.apply(edit, part, dx, dy, context)
  local options = context and context.options
  if type(options) ~= "table" then return edit end
  local origin_mm = context.origin_mm
  local model = context.model
  if type(origin_mm) ~= "table" or type(model) ~= "table" then return edit end

  local moving = moving_features(edit, part, origin_mm, dx, dy)
  local targets = target_features(edit, model, origin_mm)
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
  local edges = edit.resize_edges or {}
  if edges.x == "west" then
    part.origin_mm[1] = part.origin_mm[1] + resolved.delta_mm[1]
    part.size_mm[1] = part.size_mm[1] - resolved.delta_mm[1]
  else
    part.size_mm[1] = part.size_mm[1] + resolved.delta_mm[1]
  end
  if edges.y == "south" then
    part.origin_mm[2] = part.origin_mm[2] + resolved.delta_mm[2]
    part.size_mm[2] = part.size_mm[2] - resolved.delta_mm[2]
  else
    part.size_mm[2] = part.size_mm[2] + resolved.delta_mm[2]
  end
  edit.snap_exclusions = resolved.snap_exclusions or {}
  edit.snap_guides = snapping.guides(resolved)
  return edit
end

function M.release(edit, dx, dy)
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
