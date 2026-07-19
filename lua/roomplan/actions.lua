-- Atomic, pure model mutations. The controller owns history/revisions; this
-- module returns one complete copied model or no model at all.

local alignment = require("roomplan.geometry.alignment")
local adjacency = require("roomplan.geometry.adjacency")
local json = require("roomplan.codec.json")
local door_geometry = require("roomplan.geometry.door")
local model_helpers = require("roomplan.model")
local schema = require("roomplan.schema")
local snapping = require("roomplan.geometry.snapping")
local validate = require("roomplan.validate")

local M = {}

local function connected_id(door)
  local value = door and door.connects_to_room_id
  if value == nil or json.is_null(value) then return nil end
  return value
end

local deep_copy = json.deep_copy
local deep_equal = json.deep_equal

local function failure(code, message, details) return { code = code, message = message, details = details or {} } end

local function action_type(action) return action and action.type end

local function find(values, id)
  local i
  for i = 1, #(values or {}) do
    if values[i].id == id then return values[i], i end
  end
  return nil
end

local function find_room(model, id) return find(model.rooms, id) end

local function vector2(value, name)
  if
    type(value) ~= "table"
    or type(value[1]) ~= "number"
    or type(value[2]) ~= "number"
    or value[1] ~= math.floor(value[1])
    or value[2] ~= math.floor(value[2])
  then
    return nil, failure("INVALID_ACTION", (name or "coordinate") .. " must contain two integers")
  end
  return { value[1], value[2] }
end

local function touched(kind, id) return { kind = kind, id = id } end

local function table_is_array(value)
  local count, maximum = 0, 0
  local key
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then return false end
    count = count + 1
    maximum = math.max(maximum, key)
  end
  return count > 0 and count == maximum
end

-- Convert UI-authored ordinary Lua tables into tagged JSON values before they
-- enter a model. Empty unknown tables default to objects; every known tuple is
-- explicitly requested as an array by copy_patch/constructors.
local function action_json_value(value, preferred_kind, seen)
  if type(value) ~= "table" or json.is_null(value) or json.is_decimal(value) then return deep_copy(value) end
  if json.is_array(value) or json.is_object(value) then return deep_copy(value) end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local kind = preferred_kind or (table_is_array(value) and "array" or "object")
  local result = kind == "array" and json.array() or json.object()
  seen[value] = result
  local key, child
  for key, child in pairs(value) do
    result[key] = action_json_value(child, nil, seen)
  end
  return result
end

local tuple_fields = {
  origin_mm = true,
  size_mm = true,
  center_mm = true,
  default_size_mm = true,
  position_mm = true,
  anchor2_mm = true,
  default_anchor2_mm = true,
}

local function canonical_entity(kind, draft, schema_version)
  local prepared = action_json_value(draft, "object")
  local options = { schema_version = schema_version }
  if kind == "room" then
    return model_helpers.new_room(prepared, options)
  elseif kind == "door" then
    return model_helpers.new_door(prepared, options)
  elseif kind == "window" then
    return model_helpers.new_window(prepared, options)
  elseif kind == "outlet" then
    return model_helpers.new_outlet(prepared, options)
  elseif kind == "furniture" then
    return model_helpers.new_furniture(prepared, options)
  elseif kind == "template" then
    return model_helpers.new_custom_template(prepared, options)
  end
  return prepared
end

local function canonical_rectangle_part(entity)
  local footprint = entity and entity.footprint
  local parts = footprint and footprint.parts
  local part = parts and parts[1]
  if
    footprint == nil
    or footprint.kind ~= "rect_union"
    or type(parts) ~= "table"
    or #parts ~= 1
    or type(part) ~= "table"
    or part.id ~= "part-main"
    or type(part.origin_mm) ~= "table"
    or part.origin_mm[1] ~= 0
    or part.origin_mm[2] ~= 0
    or type(part.size_mm) ~= "table"
  then
    return nil
  end
  return part
end

local function unsupported_resize(kind, entity)
  return failure(
    "COMPOUND_RESIZE_UNSUPPORTED",
    "rectangle resize is unavailable for compound or noncanonical " .. kind .. " geometry",
    { id = entity.id }
  )
end

local function furniture_position_field(model) return model.schema_version >= 2 and "position_mm" or "center_mm" end

local function copy_patch(target, patch, immutable_id)
  if type(patch) ~= "table" then return nil, failure("INVALID_ACTION", "edit patch must be a table") end
  local key, value
  for key, value in pairs(patch) do
    if key == "id" and immutable_id and value ~= immutable_id then
      return nil, failure("IMMUTABLE_ID", "entity IDs cannot be edited", { id = immutable_id })
    end
    target[key] = action_json_value(value, tuple_fields[key] and "array" or nil)
  end
  return target
end

local handlers = {}

local function wall_feature_collection(model, key)
  local values = model.schema_version >= 3 and model[key] or nil
  if type(values) ~= "table" then
    return nil, failure("UNSUPPORTED_SCHEMA_VERSION", "windows and outlets require schema v3")
  end
  return values
end

function handlers.add_room(model, action)
  local room = action.room
  if type(room) ~= "table" then return nil, failure("INVALID_ACTION", "add_room requires a room draft") end
  room = canonical_entity("room", room, model.schema_version)
  model.rooms[#model.rooms + 1] = room
  return { label = "Add room " .. tostring(room.name or room.id), touched = { touched("room", room.id) } }
end

function handlers.edit_room(model, action)
  local room = find_room(model, action.id)
  if not room then return nil, failure("NOT_FOUND", "room was not found", { id = action.id }) end
  local _, err = copy_patch(room, action.patch, room.id)
  if err then return nil, err end
  return { label = "Edit room " .. tostring(room.name or room.id), touched = { touched("room", room.id) } }
end

function handlers.move_room(model, action, context)
  local room = find_room(model, action.id)
  if not room then return nil, failure("NOT_FOUND", "room was not found", { id = action.id }) end
  local previous_origin = { room.origin_mm[1], room.origin_mm[2] }
  local origin
  if action.origin_mm then
    local err
    origin, err = vector2(action.origin_mm, "origin_mm")
    if not origin then return nil, err end
  else
    local delta, err = vector2(action.delta_mm or { action.dx_mm, action.dy_mm }, "delta_mm")
    if not delta then return nil, err end
    origin = { room.origin_mm[1] + delta[1], room.origin_mm[2] + delta[2] }
  end
  room.origin_mm = action_json_value(origin, "array")
  local metadata = { requested_origin_mm = { origin[1], origin[2] } }
  local snap_options = action.snap or context.snapping
  if not action.exact then
    local feedback_options = snap_options and deep_copy(snap_options) or { bypass = true }
    feedback_options.bypass = action.bypass_snap or feedback_options.bypass
    feedback_options.grid_mm = feedback_options.grid_mm or (model.settings and model.settings.grid_mm)
    feedback_options.sweep_mm = {
      origin[1] - previous_origin[1],
      origin[2] - previous_origin[2],
    }
    local snap_result = snapping.snap_room(room, model.rooms, feedback_options)
    room.origin_mm = action_json_value(snap_result.origin_mm, "array")
    metadata.snapping = snap_result
  end
  return {
    label = "Move room " .. tostring(room.name or room.id),
    touched = { touched("room", room.id) },
    metadata = metadata,
  }
end

function handlers.resize_room(model, action)
  local room = find_room(model, action.id)
  if not room then return nil, failure("NOT_FOUND", "room was not found", { id = action.id }) end
  local size, err = vector2(action.size_mm, "size_mm")
  if not size then return nil, err end
  if model.schema_version >= 2 then
    local part = canonical_rectangle_part(room)
    if not part then return nil, unsupported_resize("room", room) end
    part.size_mm = action_json_value(size, "array")
  else
    room.size_mm = action_json_value(size, "array")
  end
  return { label = "Resize room " .. tostring(room.name or room.id), touched = { touched("room", room.id) } }
end

function handlers.align_room(model, action)
  local room = find_room(model, action.id)
  local reference = find_room(model, action.reference_room_id)
  if not room then return nil, failure("NOT_FOUND", "moving room was not found", { id = action.id }) end
  if not reference then
    return nil, failure("NOT_FOUND", "reference room was not found", { id = action.reference_room_id })
  end
  if room.id == reference.id then return nil, failure("INVALID_ACTION", "a room cannot be aligned to itself") end
  local proposed, err = alignment.propose(room, reference, action.operation, {
    gap_mm = action.gap_mm,
    moving_corner = action.moving_corner,
    reference_corner = action.reference_corner,
  })
  if not proposed then return nil, err end
  room.origin_mm = action_json_value(proposed.origin_mm, "array")
  return {
    label = "Align room " .. tostring(room.name or room.id) .. " " .. tostring(action.operation),
    touched = { touched("room", room.id) },
    diagnostics = proposed.diagnostics,
    metadata = { alignment = proposed },
  }
end

function handlers.duplicate_room(model, action, context)
  local source = find_room(model, action.id)
  if not source then return nil, failure("NOT_FOUND", "source room was not found", { id = action.id }) end
  if type(action.new_id) ~= "string" then return nil, failure("INVALID_ACTION", "duplicate_room requires new_id") end
  local clone = deep_copy(source)
  clone.id = action.new_id
  clone.name = action.name or (source.name .. " copy")
  if action.origin_mm then
    local origin, err = vector2(action.origin_mm, "origin_mm")
    if not origin then return nil, err end
    clone.origin_mm = action_json_value(origin, "array")
  else
    local placement, err = alignment.auto_place(clone, model.rooms, {
      cursor_mm = action.cursor_mm or context.cursor_mm,
      max_distance_mm = action.max_distance_mm or (context.limits and context.limits.max_auto_place_distance_mm),
      gap_mm = action.gap_mm or 0,
    })
    if not placement then return nil, err end
    clone.origin_mm = action_json_value(placement.origin_mm, "array")
  end
  model.rooms[#model.rooms + 1] = clone
  return {
    label = "Duplicate room " .. source.name,
    touched = { touched("room", clone.id) },
    metadata = { source_id = source.id, placement = { clone.origin_mm[1], clone.origin_mm[2] } },
  }
end

function M.room_dependencies(model, room_id)
  local result = {
    furniture = {},
    owner_doors = {},
    connected_doors = {},
    owner_windows = {},
    connected_windows = {},
    outlets = {},
    all = {},
  }
  local i
  for i = 1, #(model.furniture or {}) do
    if model.furniture[i].room_id == room_id then
      result.furniture[#result.furniture + 1] = model.furniture[i].id
      result.all[#result.all + 1] = touched("furniture", model.furniture[i].id)
    end
  end
  for i = 1, #(model.doors or {}) do
    if model.doors[i].room_id == room_id then
      result.owner_doors[#result.owner_doors + 1] = model.doors[i].id
      result.all[#result.all + 1] = touched("door", model.doors[i].id)
    elseif connected_id(model.doors[i]) == room_id then
      result.connected_doors[#result.connected_doors + 1] = model.doors[i].id
      result.all[#result.all + 1] = touched("door", model.doors[i].id)
    end
  end
  for i = 1, #(model.windows or {}) do
    if model.windows[i].room_id == room_id then
      result.owner_windows[#result.owner_windows + 1] = model.windows[i].id
      result.all[#result.all + 1] = touched("window", model.windows[i].id)
    elseif connected_id(model.windows[i]) == room_id then
      result.connected_windows[#result.connected_windows + 1] = model.windows[i].id
      result.all[#result.all + 1] = touched("window", model.windows[i].id)
    end
  end
  for i = 1, #(model.outlets or {}) do
    if model.outlets[i].room_id == room_id then
      result.outlets[#result.outlets + 1] = model.outlets[i].id
      result.all[#result.all + 1] = touched("outlet", model.outlets[i].id)
    end
  end
  return result
end

local function remove_if(values, predicate)
  local removed = {}
  local i = #values
  while i >= 1 do
    if predicate(values[i]) then table.insert(removed, 1, table.remove(values, i)) end
    i = i - 1
  end
  return removed
end

function handlers.delete_room_cascade(model, action)
  local room, index = find_room(model, action.id)
  if not room then return nil, failure("NOT_FOUND", "room was not found", { id = action.id }) end
  local dependencies = M.room_dependencies(model, room.id)
  table.remove(model.rooms, index)
  remove_if(model.furniture, function(value) return value.room_id == room.id end)
  remove_if(model.doors, function(value) return value.room_id == room.id or connected_id(value) == room.id end)
  remove_if(model.windows, function(value) return value.room_id == room.id or connected_id(value) == room.id end)
  remove_if(model.outlets, function(value) return value.room_id == room.id end)
  local all_touched = { touched("room", room.id) }
  local i
  for i = 1, #dependencies.all do
    all_touched[#all_touched + 1] = dependencies.all[i]
  end
  return {
    label = "Delete room " .. tostring(room.name or room.id),
    touched = all_touched,
    metadata = { deleted_dependencies = dependencies },
  }
end

function handlers.rename_room(model, action)
  local room = find_room(model, action.id)
  if not room then return nil, failure("NOT_FOUND", "room was not found", { id = action.id }) end
  room.name = action.name
  return { label = "Rename room " .. room.id, touched = { touched("room", room.id) } }
end

function handlers.add_furniture(model, action)
  local furniture = action.furniture
  if type(furniture) ~= "table" then
    return nil, failure("INVALID_ACTION", "add_furniture requires a furniture draft")
  end
  furniture = canonical_entity("furniture", furniture, model.schema_version)
  model.furniture[#model.furniture + 1] = furniture
  -- The first touched object becomes the session selection. Keep the placed
  -- item primary even when the same action also creates a reusable template.
  local result_touched = { touched("furniture", furniture.id) }
  if action.custom_template then
    local custom_template = canonical_entity("template", action.custom_template, model.schema_version)
    model.custom_templates[#model.custom_templates + 1] = custom_template
    result_touched[#result_touched + 1] = touched("template", custom_template.id)
  end
  return { label = "Add furniture " .. tostring(furniture.name or furniture.id), touched = result_touched }
end

function handlers.edit_furniture(model, action)
  local furniture = find(model.furniture, action.id)
  if not furniture then return nil, failure("NOT_FOUND", "furniture was not found", { id = action.id }) end
  local _, err = copy_patch(furniture, action.patch, furniture.id)
  if err then return nil, err end
  return {
    label = "Edit furniture " .. tostring(furniture.name or furniture.id),
    touched = { touched("furniture", furniture.id) },
  }
end

-- Update one placed item's explicit geometry and its project-template default
-- atomically. Other placed items intentionally retain their explicit shapes.
function handlers.edit_furniture_template_shape(model, action)
  local furniture = find(model.furniture, action.id)
  if not furniture then return nil, failure("NOT_FOUND", "furniture was not found", { id = action.id }) end
  if type(action.footprint) ~= "table" then
    return nil, failure("INVALID_ACTION", "edit_furniture_template_shape requires a footprint")
  end
  local template = find(model.custom_templates, action.template_id)
  if not template then
    return nil, failure("NOT_FOUND", "project template was not found", { id = action.template_id })
  end
  if furniture.template_id ~= template.id then
    return nil,
      failure("TEMPLATE_CHANGED", "the furniture no longer references that project template", {
        id = furniture.id,
        expected = template.id,
        actual = furniture.template_id,
      })
  end
  local _, furniture_err = copy_patch(furniture, { footprint = action.footprint }, furniture.id)
  if furniture_err then return nil, furniture_err end
  local _, template_err = copy_patch(template, {
    default_footprint = action.footprint,
    default_anchor2_mm = furniture.anchor2_mm,
  }, template.id)
  if template_err then return nil, template_err end
  return {
    label = "Edit furniture and template " .. tostring(template.name or template.id),
    touched = { touched("furniture", furniture.id), touched("template", template.id) },
  }
end

function handlers.move_furniture(model, action, context)
  local furniture = find(model.furniture, action.id)
  if not furniture then return nil, failure("NOT_FOUND", "furniture was not found", { id = action.id }) end
  local position_field = furniture_position_field(model)
  local requested_position = action[position_field]
  if model.schema_version >= 2 and action.center_mm ~= nil then
    return nil, failure("INVALID_ACTION", "compound furniture movement requires position_mm")
  end
  local current = furniture[position_field]
  if type(current) ~= "table" then
    return nil, failure("INVALID_ACTION", "furniture is missing " .. position_field, { id = furniture.id })
  end
  local position
  local previous_position = { current[1], current[2] }
  if requested_position then
    local err
    position, err = vector2(requested_position, position_field)
    if not position then return nil, err end
  else
    local delta, err = vector2(action.delta_mm or { action.dx_mm, action.dy_mm }, "delta_mm")
    if not delta then return nil, err end
    position = { current[1] + delta[1], current[2] + delta[2] }
  end
  furniture[position_field] = action_json_value(position, "array")
  local metadata_key = model.schema_version >= 2 and "requested_position_mm" or "requested_center_mm"
  local metadata = { [metadata_key] = { position[1], position[2] } }
  local snap_options = action.snap or context.snapping
  if not action.exact then
    local owner = find_room(model, furniture.room_id)
    if owner then
      local pairs, apertures = {}, {}
      local i
      for i = 1, #model.furniture do
        local other_owner = find_room(model, model.furniture[i].room_id)
        if other_owner then pairs[#pairs + 1] = { furniture = model.furniture[i], room = other_owner } end
      end
      for i = 1, #model.doors do
        local door_owner = find_room(model, model.doors[i].room_id)
        if door_owner then apertures[#apertures + 1] = door_geometry.aperture(door_owner, model.doors[i]) end
      end
      local feedback_options = snap_options and deep_copy(snap_options) or { bypass = true }
      feedback_options.bypass = action.bypass_snap or feedback_options.bypass
      feedback_options.grid_mm = feedback_options.grid_mm or (model.settings and model.settings.grid_mm)
      feedback_options.sweep_mm = {
        position[1] - previous_position[1],
        position[2] - previous_position[2],
      }
      local snap_result = snapping.snap_furniture(owner, furniture, pairs, apertures, feedback_options)
      furniture[position_field] = action_json_value(snap_result[position_field], "array")
      metadata.snapping = snap_result
    end
  end
  return {
    label = "Move furniture " .. tostring(furniture.name or furniture.id),
    touched = { touched("furniture", furniture.id) },
    metadata = metadata,
  }
end

function handlers.resize_furniture(model, action)
  local furniture = find(model.furniture, action.id)
  if not furniture then return nil, failure("NOT_FOUND", "furniture was not found", { id = action.id }) end
  if type(action.size_mm) ~= "table" or #action.size_mm < 3 then
    return nil, failure("INVALID_ACTION", "size_mm must contain width, depth, and height")
  end
  if model.schema_version >= 2 then
    local part = canonical_rectangle_part(furniture)
    local anchor = furniture.anchor2_mm
    if not part or type(anchor) ~= "table" or anchor[1] ~= part.size_mm[1] or anchor[2] ~= part.size_mm[2] then
      return nil, unsupported_resize("furniture", furniture)
    end
    part.size_mm = action_json_value({ action.size_mm[1], action.size_mm[2] }, "array")
    furniture.anchor2_mm = action_json_value({ action.size_mm[1], action.size_mm[2] }, "array")
    furniture.height_mm = action.size_mm[3]
  else
    furniture.size_mm = action_json_value(action.size_mm, "array")
  end
  return {
    label = "Resize furniture " .. tostring(furniture.name or furniture.id),
    touched = { touched("furniture", furniture.id) },
  }
end

function handlers.rotate_furniture(model, action)
  local furniture = find(model.furniture, action.id)
  if not furniture then return nil, failure("NOT_FOUND", "furniture was not found", { id = action.id }) end
  furniture.rotation_deg = action.rotation_deg ~= nil and action.rotation_deg
    or ((furniture.rotation_deg + (action.delta_deg or 90)) % 360)
  return {
    label = "Rotate furniture " .. tostring(furniture.name or furniture.id),
    touched = { touched("furniture", furniture.id) },
  }
end

function handlers.duplicate_furniture(model, action)
  local source = find(model.furniture, action.id)
  if not source then return nil, failure("NOT_FOUND", "source furniture was not found", { id = action.id }) end
  if type(action.new_id) ~= "string" then
    return nil, failure("INVALID_ACTION", "duplicate_furniture requires new_id")
  end
  local clone = deep_copy(source)
  clone.id = action.new_id
  if action.room_id ~= nil then clone.room_id = action.room_id end
  clone.name = action.name or (source.name .. " copy")
  local step = action.step_mm or (model.settings and model.settings.normal_step_mm) or 100
  local position_field = furniture_position_field(model)
  local position = source[position_field]
  if type(position) ~= "table" then
    return nil, failure("INVALID_ACTION", "source furniture is missing " .. position_field, { id = source.id })
  end
  clone[position_field] = action_json_value({ position[1] + step, position[2] + step }, "array")
  model.furniture[#model.furniture + 1] = clone
  return {
    label = "Duplicate furniture " .. source.name,
    touched = { touched("furniture", clone.id) },
    metadata = { source_id = source.id, delta_mm = { step, step } },
  }
end

function handlers.delete_furniture(model, action)
  local furniture, index = find(model.furniture, action.id)
  if not furniture then return nil, failure("NOT_FOUND", "furniture was not found", { id = action.id }) end
  table.remove(model.furniture, index)
  return {
    label = "Delete furniture " .. tostring(furniture.name or furniture.id),
    touched = { touched("furniture", furniture.id) },
  }
end

function handlers.rename_furniture(model, action)
  return handlers.edit_furniture(model, { id = action.id, patch = { name = action.name } })
end

function handlers.change_furniture_template(model, action)
  return handlers.edit_furniture(
    model,
    { id = action.id, patch = { template_id = action.template_id, category = action.category } }
  )
end

function handlers.add_door(model, action)
  local door = action.door
  if type(door) ~= "table" then return nil, failure("INVALID_ACTION", "add_door requires a door draft") end
  door = canonical_entity("door", door, model.schema_version)
  model.doors[#model.doors + 1] = door
  return { label = "Add door " .. tostring(door.id), touched = { touched("door", door.id) } }
end

function handlers.edit_door(model, action, context)
  local door = find(model.doors, action.id)
  if not door then return nil, failure("NOT_FOUND", "door was not found", { id = action.id }) end
  local _, err = copy_patch(door, action.patch, door.id)
  if err then return nil, err end
  local snap_options = action.snap or context.snapping
  if snap_options and not action.exact then
    local owner = find_room(model, door.room_id)
    if owner then
      local edge_length = door_geometry.edge_length(owner, door.side, door.part_id)
      local endpoints = {}
      local i
      for i = 1, #model.doors do
        local other = model.doors[i]
        local same_part = model.schema_version < 2 or other.part_id == door.part_id
        if other.id ~= door.id and other.room_id == door.room_id and other.side == door.side and same_part then
          endpoints[#endpoints + 1] = { value_mm = other.offset_mm, kind = "door", id = other.id, name = "start" }
          endpoints[#endpoints + 1] =
            { value_mm = other.offset_mm + other.width_mm, kind = "door", id = other.id, name = "finish" }
        end
      end
      local owner_edge = adjacency.edge(owner, door.side, door.part_id)
      for i = 1, #model.rooms do
        local other_room = model.rooms[i]
        if other_room.id ~= owner.id then
          local relation = adjacency.between(owner, other_room)
          if relation and relation.a_side == door.side then
            endpoints[#endpoints + 1] = {
              value_mm = relation.start_mm - owner_edge.start_mm,
              kind = "room_edge",
              id = other_room.id,
              name = "shared-start",
            }
            endpoints[#endpoints + 1] = {
              value_mm = relation.finish_mm - owner_edge.start_mm,
              kind = "room_edge",
              id = other_room.id,
              name = "shared-finish",
            }
          end
        end
      end
      snap_options = deep_copy(snap_options)
      snap_options.bypass = action.bypass_snap or snap_options.bypass
      snap_options.grid_mm = snap_options.grid_mm or (model.settings and model.settings.grid_mm)
      local snap_result = snapping.snap_door_offset(door.offset_mm, door.width_mm, edge_length, endpoints, snap_options)
      door.offset_mm = snap_result.offset_mm
    end
  end
  return { label = "Edit door " .. door.id, touched = { touched("door", door.id) } }
end

function handlers.toggle_door_hinge(model, action)
  local door = find(model.doors, action.id)
  if not door then return nil, failure("NOT_FOUND", "door was not found", { id = action.id }) end
  door.hinge = door.hinge == "start" and "end" or "start"
  return { label = "Toggle hinge " .. door.id, touched = { touched("door", door.id) } }
end

function handlers.toggle_door_swing(model, action)
  local door = find(model.doors, action.id)
  if not door then return nil, failure("NOT_FOUND", "door was not found", { id = action.id }) end
  if connected_id(door) then
    door.opens_into = door.opens_into == "owner" and "connected" or "owner"
  else
    door.opens_into = door.opens_into == "owner" and "outside" or "owner"
  end
  return { label = "Toggle swing " .. door.id, touched = { touched("door", door.id) } }
end

function handlers.delete_door(model, action)
  local door, index = find(model.doors, action.id)
  if not door then return nil, failure("NOT_FOUND", "door was not found", { id = action.id }) end
  table.remove(model.doors, index)
  return { label = "Delete door " .. door.id, touched = { touched("door", door.id) } }
end

function handlers.duplicate_door_from_draft(model, action)
  local source = find(model.doors, action.id)
  if not source then return nil, failure("NOT_FOUND", "source door was not found", { id = action.id }) end
  local clone = deep_copy(source)
  if type(action.new_id) ~= "string" then
    return nil, failure("INVALID_ACTION", "duplicate_door_from_draft requires new_id")
  end
  clone.id = action.new_id
  local _, err = copy_patch(clone, action.patch or {}, clone.id)
  if err then return nil, err end
  model.doors[#model.doors + 1] = clone
  return {
    label = "Duplicate door draft " .. source.id,
    touched = { touched("door", clone.id) },
    metadata = { source_id = source.id },
  }
end

function handlers.add_window(model, action)
  if type(action.window) ~= "table" then return nil, failure("INVALID_ACTION", "add_window requires a window draft") end
  local windows, collection_err = wall_feature_collection(model, "windows")
  if not windows then return nil, collection_err end
  local window = canonical_entity("window", action.window, model.schema_version)
  windows[#windows + 1] = window
  return { label = "Add window " .. tostring(window.id), touched = { touched("window", window.id) } }
end

function handlers.edit_window(model, action)
  local windows, collection_err = wall_feature_collection(model, "windows")
  if not windows then return nil, collection_err end
  local window = find(windows, action.id)
  if not window then return nil, failure("NOT_FOUND", "window was not found", { id = action.id }) end
  local _, err = copy_patch(window, action.patch, window.id)
  if err then return nil, err end
  if action.clear_heights then
    window.sill_height_mm = nil
    window.head_height_mm = nil
  end
  return { label = "Edit window " .. window.id, touched = { touched("window", window.id) } }
end

function handlers.duplicate_window(model, action)
  local windows, collection_err = wall_feature_collection(model, "windows")
  if not windows then return nil, collection_err end
  local source = find(windows, action.id)
  if not source then return nil, failure("NOT_FOUND", "source window was not found", { id = action.id }) end
  if type(action.new_id) ~= "string" then return nil, failure("INVALID_ACTION", "duplicate_window requires new_id") end
  local clone = deep_copy(source)
  clone.id = action.new_id
  if action.room_id ~= nil then clone.room_id = action.room_id end
  if action.connects_to_room_id ~= nil then
    clone.connects_to_room_id = action_json_value(action.connects_to_room_id)
  end
  clone.offset_mm = action.offset_mm or (source.offset_mm + source.width_mm)
  windows[#windows + 1] = clone
  return {
    label = "Duplicate window " .. source.id,
    touched = { touched("window", clone.id) },
    metadata = { source_id = source.id },
  }
end

function handlers.delete_window(model, action)
  local windows, collection_err = wall_feature_collection(model, "windows")
  if not windows then return nil, collection_err end
  local window, index = find(windows, action.id)
  if not window then return nil, failure("NOT_FOUND", "window was not found", { id = action.id }) end
  table.remove(windows, index)
  return { label = "Delete window " .. window.id, touched = { touched("window", window.id) } }
end

function handlers.add_outlet(model, action)
  if type(action.outlet) ~= "table" then
    return nil, failure("INVALID_ACTION", "add_outlet requires an outlet draft")
  end
  local outlets, collection_err = wall_feature_collection(model, "outlets")
  if not outlets then return nil, collection_err end
  local outlet = canonical_entity("outlet", action.outlet, model.schema_version)
  outlets[#outlets + 1] = outlet
  return { label = "Add outlet " .. tostring(outlet.id), touched = { touched("outlet", outlet.id) } }
end

function handlers.edit_outlet(model, action)
  local outlets, collection_err = wall_feature_collection(model, "outlets")
  if not outlets then return nil, collection_err end
  local outlet = find(outlets, action.id)
  if not outlet then return nil, failure("NOT_FOUND", "outlet was not found", { id = action.id }) end
  local _, err = copy_patch(outlet, action.patch, outlet.id)
  if err then return nil, err end
  local placement = outlet.placement or "wall"
  if placement == "floor" then
    outlet.part_id, outlet.side, outlet.offset_mm = nil, nil, nil
  else
    outlet.position_mm = nil
  end
  return { label = "Edit outlet " .. outlet.id, touched = { touched("outlet", outlet.id) } }
end

function handlers.duplicate_outlet(model, action)
  local outlets, collection_err = wall_feature_collection(model, "outlets")
  if not outlets then return nil, collection_err end
  local source = find(outlets, action.id)
  if not source then return nil, failure("NOT_FOUND", "source outlet was not found", { id = action.id }) end
  if type(action.new_id) ~= "string" then return nil, failure("INVALID_ACTION", "duplicate_outlet requires new_id") end
  local clone = deep_copy(source)
  clone.id = action.new_id
  if action.room_id ~= nil then clone.room_id = action.room_id end
  local step = action.step_mm ~= nil and action.step_mm or model.settings and model.settings.normal_step_mm or 100
  if (source.placement or "wall") == "floor" then
    clone.position_mm = action.position_mm and action_json_value(action.position_mm, "array")
      or action_json_value({ source.position_mm[1] + step, source.position_mm[2] + step }, "array")
  else
    clone.offset_mm = action.offset_mm or (source.offset_mm + step)
  end
  outlets[#outlets + 1] = clone
  return {
    label = "Duplicate outlet " .. source.id,
    touched = { touched("outlet", clone.id) },
    metadata = { source_id = source.id },
  }
end

function handlers.delete_outlet(model, action)
  local outlets, collection_err = wall_feature_collection(model, "outlets")
  if not outlets then return nil, collection_err end
  local outlet, index = find(outlets, action.id)
  if not outlet then return nil, failure("NOT_FOUND", "outlet was not found", { id = action.id }) end
  table.remove(outlets, index)
  return { label = "Delete outlet " .. outlet.id, touched = { touched("outlet", outlet.id) } }
end

function handlers.add_custom_template(model, action)
  local template = action.template
  if type(template) ~= "table" then
    return nil, failure("INVALID_ACTION", "add_custom_template requires a template draft")
  end
  template = canonical_entity("template", template, model.schema_version)
  model.custom_templates[#model.custom_templates + 1] = template
  return {
    label = "Add template " .. tostring(template.name or template.id),
    touched = { touched("template", template.id) },
  }
end

function handlers.edit_custom_template(model, action)
  local template = find(model.custom_templates, action.id)
  if not template then return nil, failure("NOT_FOUND", "custom template was not found", { id = action.id }) end
  local _, err = copy_patch(template, action.patch, template.id)
  if err then return nil, err end
  return {
    label = "Edit template " .. tostring(template.name or template.id),
    touched = { touched("template", template.id) },
  }
end

function handlers.duplicate_custom_template(model, action)
  local source = find(model.custom_templates, action.id)
  if not source then return nil, failure("NOT_FOUND", "custom template was not found", { id = action.id }) end
  if type(action.new_id) ~= "string" then
    return nil, failure("INVALID_ACTION", "duplicate_custom_template requires new_id")
  end
  local clone = deep_copy(source)
  clone.id, clone.name = action.new_id, action.name or (source.name .. " copy")
  model.custom_templates[#model.custom_templates + 1] = clone
  return {
    label = "Duplicate template " .. source.name,
    touched = { touched("template", clone.id) },
    metadata = { source_id = source.id },
  }
end

function handlers.delete_custom_template(model, action)
  local template, index = find(model.custom_templates, action.id)
  if not template then return nil, failure("NOT_FOUND", "custom template was not found", { id = action.id }) end
  local references = {}
  local i
  for i = 1, #model.furniture do
    if model.furniture[i].template_id == template.id then references[#references + 1] = model.furniture[i].id end
  end
  if #references > 0 then
    return nil,
      failure("TEMPLATE_IN_USE", "template " .. template.id .. " is still referenced", { references = references })
  end
  table.remove(model.custom_templates, index)
  return { label = "Delete template " .. template.name, touched = { touched("template", template.id) } }
end

function handlers.edit_metadata(model, action)
  model.metadata = model.metadata or {}
  local _, err = copy_patch(model.metadata, action.patch, nil)
  if err then return nil, err end
  return { label = "Edit plan metadata", touched = { touched("plan", "roomplan.nvim") } }
end

function handlers.edit_plan_settings(model, action)
  model.settings = model.settings or {}
  local _, err = copy_patch(model.settings, action.patch, nil)
  if err then return nil, err end
  return { label = "Edit plan settings", touched = { touched("settings", "settings") } }
end

function handlers.edit_plan(model, action)
  model.metadata = model.metadata or {}
  model.settings = model.settings or {}
  local _, metadata_err = copy_patch(model.metadata, action.metadata or {}, nil)
  if metadata_err then return nil, metadata_err end
  local _, settings_err = copy_patch(model.settings, action.settings or {}, nil)
  if settings_err then return nil, settings_err end
  return {
    label = "Edit plan",
    touched = { touched("plan", "roomplan.nvim"), touched("settings", "settings") },
  }
end

function handlers.edit_site(model, action)
  if type(action.site) ~= "table" then return nil, failure("INVALID_ACTION", "edit_site requires a site object") end
  model.site = action_json_value(action.site, "object")
  return { label = "Edit plan site", touched = { touched("plan", "roomplan.nvim") } }
end

function handlers.batch(model, action, context)
  if type(action.actions) ~= "table" or #action.actions == 0 then
    return nil, failure("INVALID_ACTION", "batch requires at least one child action")
  end
  if #action.actions > 256 then return nil, failure("INVALID_ACTION", "batch contains too many child actions") end
  local result_touched, seen_touched, summaries = {}, {}, {}
  for index, child in ipairs(action.actions) do
    local name = action_type(child)
    if name == "batch" or type(handlers[name]) ~= "function" then
      return nil,
        failure("INVALID_ACTION", "batch child uses an unsupported action", {
          index = index,
          action = name,
        })
    end
    local child_result, child_error = handlers[name](model, child, context)
    if not child_result then
      if type(child_error) ~= "table" then
        child_error = failure("BATCH_CHILD_FAILED", tostring(child_error or "batch child failed"))
      end
      child_error.details = child_error.details or {}
      child_error.details.batch_index = index
      child_error.details.batch_action = name
      return nil, child_error
    end
    summaries[#summaries + 1] = {
      type = name,
      label = child_result.label,
      metadata = child_result.metadata,
    }
    for _, reference in ipairs(child_result.touched or {}) do
      local key = tostring(reference.kind) .. "\31" .. tostring(reference.id)
      if not seen_touched[key] then
        seen_touched[key] = true
        result_touched[#result_touched + 1] = deep_copy(reference)
      end
    end
  end
  return {
    label = action.label or string.format("Batch edit %d objects", #action.actions),
    touched = result_touched,
    metadata = { batch = summaries },
  }
end

local room_actions = {
  add_room = true,
  edit_room = true,
  move_room = true,
  resize_room = true,
  align_room = true,
  duplicate_room = true,
}
local door_actions = {
  add_door = true,
  edit_door = true,
  toggle_door_hinge = true,
  toggle_door_swing = true,
  duplicate_door_from_draft = true,
}
local wall_fixture_actions = {
  add_window = true,
  edit_window = true,
  duplicate_window = true,
  add_outlet = true,
  edit_outlet = true,
  duplicate_outlet = true,
}

local function batch_must_block(action)
  for _, child in ipairs(action.actions or {}) do
    local child_name = action_type(child)
    if room_actions[child_name] or door_actions[child_name] or wall_fixture_actions[child_name] then return true end
  end
  return false
end

local function diagnostic_signature(value)
  local related = {}
  local i
  for i = 1, #(value.related or {}) do
    related[#related + 1] = tostring(value.related[i].kind) .. ":" .. tostring(value.related[i].id)
  end
  table.sort(related)
  return table.concat({
    value.code or "",
    value.object and value.object.kind or "",
    value.object and value.object.id or "",
    table.concat(related, ","),
  }, "|")
end

local function newly_introduced_errors(before, after)
  local counts = {}
  local i
  for i = 1, #before do
    if before[i].severity == "error" then
      local key = diagnostic_signature(before[i])
      counts[key] = (counts[key] or 0) + 1
    end
  end
  local result = {}
  for i = 1, #after do
    if after[i].severity == "error" then
      local key = diagnostic_signature(after[i])
      if (counts[key] or 0) > 0 then
        counts[key] = counts[key] - 1
      else
        result[#result + 1] = after[i]
      end
    end
  end
  return result
end

function M.apply(model, action, context)
  context = context or {}
  if type(model) ~= "table" then return nil, failure("INVALID_MODEL", "model must be a table") end
  if type(action) ~= "table" then return nil, failure("INVALID_ACTION", "action must be a table") end
  local name = action_type(action)
  local handler = handlers[name]
  if not handler then return nil, failure("UNKNOWN_ACTION", "unsupported action " .. tostring(name)) end
  -- A batch keeps each child's validation policy. For example, ordinary
  -- furniture movement/duplication may temporarily overlap while the user is
  -- arranging it, whereas room and wall-feature edits still reject newly
  -- introduced layout errors. Atomicity comes from mutating only `copy`, not
  -- from making every batch stricter than its standalone actions.
  local must_block = name == "batch" and batch_must_block(action)
    or room_actions[name]
    or door_actions[name]
    or wall_fixture_actions[name]

  local structurally_valid, structural = validate.is_structurally_valid(model)
  if not structurally_valid then
    return nil, failure("STRUCTURAL_INVALID", "current model is structurally invalid", { diagnostics = structural })
  end
  local before_diagnostics = context.current_diagnostics
  if must_block and type(before_diagnostics) ~= "table" then
    before_diagnostics = validate.run(model, context.validation or context)
  elseif type(before_diagnostics) ~= "table" then
    before_diagnostics = {}
  end
  local copy = deep_copy(model)
  local result, err = handler(copy, action, context)
  if not result then return nil, err end

  local valid_after, after_structural = validate.is_structurally_valid(copy)
  if not valid_after then
    return nil,
      failure(
        "STRUCTURAL_INVALID",
        "action would violate structural model invariants",
        { diagnostics = after_structural, action = name }
      )
  end
  -- The schema is also the authority for tagged JSON object/array state and
  -- unknown extension values. Constructors above make normal UI drafts valid;
  -- this final gate catches ambiguous/unrepresentable action payloads.
  local schema_valid, schema_info, normalized = schema.validate_versioned(copy)
  if not schema_valid then
    return nil,
      failure(
        "STRUCTURAL_INVALID",
        "action produced a model that cannot be encoded safely",
        { schema_error = schema_info, action = name }
      )
  end
  copy = normalized
  if deep_equal(model, copy) then
    return nil, failure("NO_CHANGE", "action did not change the model", { noop = true })
  end

  local after_diagnostics, after_summary = validate.run(copy, context.validation or context)
  local new_errors = newly_introduced_errors(before_diagnostics, after_diagnostics)
  local force = action.force == true or context.force == true
  if must_block and #new_errors > 0 and not force then
    return nil,
      failure("LAYOUT_BLOCKED", "action would introduce layout errors", {
        diagnostics = new_errors,
        action = name,
        forceable = true,
      })
  end
  result.label = result.label or name
  result.touched = result.touched or {}
  result.diagnostics = result.diagnostics or {}
  result.metadata = result.metadata or {}
  if force and #new_errors > 0 then
    result.metadata.forced = true
    result.metadata.accepted_diagnostics = deep_copy(new_errors)
  end
  result.validation = after_diagnostics
  result.validation_summary = after_summary
  return copy, result
end

return M
