-- Pure draft operations for direct compound room, placed-furniture, and
-- project-template shape editing. Drafts retain the complete tagged footprint
-- and become one semantic edit action on commit. The legacy module name is
-- kept as an internal import path while all object kinds share this single
-- implementation authority.

local geometry = require("roomplan.geometry.footprint")
local shape_snapping = require("roomplan.room_shape.snapping")
local json = require("roomplan.codec.json")
local util = require("roomplan.util")

local M = {}

local function failure(code, message, details)
  return nil, { code = code, message = message, details = details or {} }
end

local function entity(model, kind, id)
  local collection = kind == "furniture" and model.furniture
    or kind == "template" and model.custom_templates
    or model.rooms
  for _, candidate in ipairs(collection or {}) do
    if candidate.id == id then return candidate end
  end
end

local function noun(edit)
  if edit.kind == "furniture" then return "furniture" end
  if edit.kind == "template" then return "project template" end
  return "room"
end

local function selected(edit)
  for index, part in ipairs(edit.footprint.parts or {}) do
    if part.id == edit.selected_part_id then return part, index end
  end
end

local function valid_footprint(edit, value)
  local runtime, err = geometry.from_persisted(value)
  if err then return failure(err.code or "ROOM_SHAPE_INVALID", err.message or "the room shape is invalid", err.details) end
  if edit.kind == "furniture" or edit.kind == "template" then
    local anchor = edit.anchor2_mm
    local contains, anchor_err = type(anchor) == "table"
      and geometry.contains_point2(runtime, anchor[1], anchor[2]) or false
    if not contains then
      return failure("FURNITURE_SHAPE_ANCHOR", anchor_err and anchor_err.message
        or "the furniture anchor must remain on or inside its footprint")
    end
  end
  return true
end

local function with_footprint(edit, footprint, selected_id)
  local valid, err = valid_footprint(edit, footprint)
  if not valid then return nil, err end
  local result = util.deepcopy(edit)
  result.footprint = footprint
  result.selected_part_id = selected_id or result.selected_part_id
  return result
end

local function clear_feedback(edit)
  edit.snap_guides = {}
  edit.snap_exclusions = {}
  return edit
end

local function reset_handles(edit)
  clear_feedback(edit)
  edit.resize_edges = {}
  edit.move_feedback = nil
  return edit
end

function M.start(model, entity_id, revision_id, kind)
  kind = kind or "room"
  if kind ~= "room" and kind ~= "furniture" and kind ~= "template" then
    return failure("SHAPE_KIND", "shape editing supports rooms, placed furniture, and project templates")
  end
  local source = entity(model, kind, entity_id)
  local source_footprint = kind == "template" and source and source.default_footprint
    or source and source.footprint
  if not source or type(source_footprint) ~= "table" or not source_footprint.parts[1] then
    return failure("SHAPE_UNAVAILABLE", "select a compound-schema " .. kind .. " before editing its shape")
  end
  local anchor = kind == "furniture" and source.anchor2_mm
    or kind == "template" and source.default_anchor2_mm
  return {
    kind = kind,
    entity_id = entity_id,
    room_id = kind == "room" and entity_id or source.room_id,
    base_revision_id = revision_id,
    original_footprint = util.deepcopy(source_footprint),
    footprint = util.deepcopy(source_footprint),
    anchor2_mm = anchor and util.deepcopy(anchor) or nil,
    template_id = kind == "furniture" and source.template_id or nil,
    rotation_deg = kind == "furniture" and (source.rotation_deg or 0) or 0,
    selected_part_id = source_footprint.parts[1].id,
    snap_guides = {},
    snap_exclusions = {},
    resize_edges = {},
  }
end

function M.preview_model(model, edit)
  local result = util.deepcopy(model)
  local target = entity(result, edit.kind or "room", edit.entity_id or edit.room_id)
  if not target then return failure("SHAPE_STALE", "the edited " .. noun(edit) .. " no longer exists") end
  if edit.kind == "template" then target.default_footprint = util.deepcopy(edit.footprint)
  else target.footprint = util.deepcopy(edit.footprint) end
  return result
end

function M.selected(edit)
  local part, index = selected(edit)
  return part and util.deepcopy(part) or nil, index
end

function M.clear_feedback(edit)
  return clear_feedback(util.deepcopy(edit))
end

function M.select_world(edit, origin_or_shape, world_mm)
  local shape, err
  if type(origin_or_shape) == "table" and type(origin_or_shape.parts) == "table"
    and type(origin_or_shape.parts[1]) == "table" and origin_or_shape.parts[1].left2 ~= nil
  then
    shape = origin_or_shape
  else
    shape, err = geometry.from_persisted(edit.footprint)
    if shape and type(origin_or_shape) == "table" then
      shape, err = geometry.translate(shape, origin_or_shape[1], origin_or_shape[2])
    end
  end
  if not shape then return nil, err end
  local hits, hit_error = geometry.hit_test(shape, world_mm[1], world_mm[2], { include_boundary = true })
  if not hits then return nil, hit_error end
  if #hits == 0 then
    return failure("SHAPE_MISS", "place the cursor inside the " .. noun(edit) .. " section you want to select")
  end
  local result = reset_handles(util.deepcopy(edit))
  result.selected_part_id = hits[1].part_id
  return result
end

function M.cycle(edit, direction)
  local _, index = selected(edit)
  if not index then return failure("SHAPE_SELECTION", "the selected section no longer exists") end
  local count = #edit.footprint.parts
  local next_index = ((index - 1 + (direction < 0 and -1 or 1)) % count) + 1
  local result = reset_handles(util.deepcopy(edit))
  result.selected_part_id = result.footprint.parts[next_index].id
  return result
end

local function valid_size(part, limits)
  if part.size_mm[1] <= 0 or part.size_mm[2] <= 0 then
    return failure("SHAPE_SIZE", "a shape section must keep a positive width and depth")
  end
  if limits and (part.size_mm[1] > limits.max_dimension_mm or part.size_mm[2] > limits.max_dimension_mm) then
    return failure("SHAPE_SIZE", "the shape section exceeds the configured maximum dimension")
  end
  return true
end

function M.direction(edit, dx, dy, step_mm, limits, snap_context)
  local result = shape_snapping.release(util.deepcopy(edit), dx, dy)
  local part = selected(result)
  if not part then return failure("SHAPE_SELECTION", "the selected section no longer exists") end
  result.resize_edges = result.resize_edges or {}
  local chose_edge = false
  if dx ~= 0 then
    if not result.resize_edges.x then
      result.resize_edges.x = dx < 0 and "west" or "east"
      chose_edge = true
    end
    if result.resize_edges.x == "west" then
      part.origin_mm[1] = part.origin_mm[1] + dx * step_mm
      part.size_mm[1] = part.size_mm[1] - dx * step_mm
    else
      part.size_mm[1] = part.size_mm[1] + dx * step_mm
    end
  end
  if dy ~= 0 then
    if not result.resize_edges.y then
      result.resize_edges.y = dy < 0 and "south" or "north"
      chose_edge = true
    end
    if result.resize_edges.y == "south" then
      part.origin_mm[2] = part.origin_mm[2] + dy * step_mm
      part.size_mm[2] = part.size_mm[2] - dy * step_mm
    else
      part.size_mm[2] = part.size_mm[2] + dy * step_mm
    end
  end
  local handle_only = util.deepcopy(result)
  handle_only.footprint = util.deepcopy(edit.footprint)
  local size_ok, size_err = valid_size(part, limits)
  if not size_ok then return chose_edge and handle_only or nil, size_err end

  local unsnapped = util.deepcopy(result)
  result = shape_snapping.apply(result, part, dx, dy, step_mm, snap_context)
  local snapped_part = selected(result)
  size_ok, size_err = valid_size(snapped_part, limits)
  if size_ok then
    local snapped, snapped_err = with_footprint(result, result.footprint)
    if snapped then return snapped end
    local fallback, fallback_err = with_footprint(unsnapped, unsnapped.footprint)
    if fallback then return fallback end
    if chose_edge then return handle_only end
    return nil, fallback_err or snapped_err
  end
  local fallback, fallback_err = with_footprint(unsnapped, unsnapped.footprint)
  if fallback then return fallback end
  if chose_edge then return handle_only end
  return nil, fallback_err or size_err
end

local function next_part_id(footprint)
  local used = {}
  for _, part in ipairs(footprint.parts or {}) do used[part.id] = true end
  local serial = 1
  while used["part-" .. serial] do serial = serial + 1 end
  return "part-" .. serial
end

local function new_part(id, x, y, width, depth)
  return json.object({
    id = id,
    origin_mm = json.array({ x, y }),
    size_mm = json.array({ width, depth }),
  })
end

function M.add(edit, preferred_dx, preferred_dy)
  if #edit.footprint.parts >= geometry.DEFAULT_MAX_PARTS then
    return failure("SHAPE_PART_LIMIT", "the shape already has the maximum number of sections")
  end
  local part = selected(edit)
  if not part then return failure("SHAPE_SELECTION", "the selected section no longer exists") end
  local width, depth = part.size_mm[1], part.size_mm[2]
  local x, y = part.origin_mm[1], part.origin_mm[2]
  local directions = {
    { 1, 0, x + width, y }, { 0, 1, x, y + depth },
    { -1, 0, x - width, y }, { 0, -1, x, y - depth },
  }
  if preferred_dx ~= 0 or preferred_dy ~= 0 then
    table.sort(directions, function(left, right)
      return left[1] * preferred_dx + left[2] * preferred_dy
        > right[1] * preferred_dx + right[2] * preferred_dy
    end)
  end
  local id = next_part_id(edit.footprint)
  for _, direction in ipairs(directions) do
    local footprint = util.deepcopy(edit.footprint)
    footprint.parts[#footprint.parts + 1] = new_part(id, direction[3], direction[4], width, depth)
    local result = with_footprint(edit, footprint, id)
    if result then return reset_handles(result) end
  end
  return failure("SHAPE_ADD", "no clear adjoining side is available for a new section")
end

local function references(model, room_id, part_id)
  local result = {}
  for _, entry in ipairs({
    { values = model.doors, kind = "door" },
    { values = model.windows, kind = "window" },
    { values = model.outlets, kind = "outlet" },
  }) do
    for _, object in ipairs(entry.values or {}) do
      if object.room_id == room_id and object.part_id == part_id then
        result[#result + 1] = entry.kind .. " " .. tostring(object.id)
      end
    end
  end
  return result
end

function M.remove(edit, model)
  if #edit.footprint.parts <= 1 then
    return failure("SHAPE_EMPTY", "a shape must keep at least one section")
  end
  local _, index = selected(edit)
  if not index then return failure("SHAPE_SELECTION", "the selected section no longer exists") end
  local used = edit.kind == "room" and references(model, edit.room_id, edit.selected_part_id) or {}
  if #used > 0 then
    return failure("ROOM_SHAPE_PART_IN_USE", "move or remove attached objects first: " .. table.concat(used, ", "))
  end
  local footprint = util.deepcopy(edit.footprint)
  table.remove(footprint.parts, index)
  local next_index = math.min(index, #footprint.parts)
  local result, err = with_footprint(edit, footprint, footprint.parts[next_index].id)
  return result and reset_handles(result) or nil, err
end

function M.snap_summary(edit)
  return shape_snapping.summary(edit)
end

function M.edge_summary(edit)
  local edges = edit and edit.resize_edges or {}
  local rotation = edit and edit.rotation_deg or 0
  local sides = {
    [0] = { west = "west", east = "east", south = "south", north = "north" },
    [90] = { west = "south", east = "north", south = "east", north = "west" },
    [180] = { west = "east", east = "west", south = "north", north = "south" },
    [270] = { west = "north", east = "south", south = "west", north = "east" },
  }
  local visible = sides[rotation] or sides[0]
  local horizontal = edges.x and visible[edges.x] or nil
  local vertical = edges.y and visible[edges.y] or nil
  if horizontal and vertical then return horizontal .. "/" .. vertical end
  return horizontal or vertical
end

function M.is_changed(edit)
  return not json.deep_equal(edit.original_footprint, edit.footprint)
end

function M.action(edit, scope)
  if edit.kind == "template" then
    return {
      type = "edit_custom_template",
      id = edit.entity_id,
      patch = { default_footprint = util.deepcopy(edit.footprint) },
    }
  end
  if edit.kind == "furniture" and scope == "template" then
    return {
      type = "edit_furniture_template_shape",
      id = edit.entity_id,
      template_id = edit.template_id,
      footprint = util.deepcopy(edit.footprint),
    }
  end
  return {
    type = edit.kind == "furniture" and "edit_furniture" or "edit_room",
    id = edit.entity_id or edit.room_id,
    patch = { footprint = util.deepcopy(edit.footprint) },
  }
end

---Convert a world-plan direction into the edited object's local axes. Rooms
---are north-up; furniture uses its persisted quarter-turn around the explicit
---anchor, which remains unchanged during shape edits.
function M.local_delta(edit, dx, dy)
  local rotation = edit and edit.rotation_deg or 0
  if rotation == 90 then return dy, -dx end
  if rotation == 180 then return -dx, -dy end
  if rotation == 270 then return -dy, dx end
  return dx, dy
end

return M
