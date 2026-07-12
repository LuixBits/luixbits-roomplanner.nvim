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

local collection_for_kind = {
  room = "rooms",
  door = "doors",
  furniture = "furniture",
  template = "custom_templates",
}

local function deep_copy(value, seen)
  if json and json.deep_copy then return json.deep_copy(value) end
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local result = {}
  seen[value] = result
  local key, child
  for key, child in pairs(value) do
    result[deep_copy(key, seen)] = deep_copy(child, seen)
  end
  return setmetatable(result, getmetatable(value))
end

local function deep_equal(a, b, seen)
  if json and json.deep_equal then return json.deep_equal(a, b) end
  if a == b then return true end
  if type(a) ~= type(b) or type(a) ~= "table" then return false end
  seen = seen or {}
  if seen[a] == b then return true end
  seen[a] = b
  local key, value
  for key, value in pairs(a) do
    if not deep_equal(value, b[key], seen) then return false end
  end
  for key in pairs(b) do
    if a[key] == nil then return false end
  end
  return true
end

M.deep_copy = deep_copy
M.deep_equal = deep_equal

local function failure(code, message, details)
  return { code = code, message = message, details = details or {} }
end

local function action_type(action)
  return action and (action.type or action.action or action.kind)
end

local function find(values, id)
  local i
  for i = 1, #(values or {}) do
    if values[i].id == id then return values[i], i end
  end
  return nil
end

local function find_room(model, id)
  return find(model.rooms, id)
end

local function vector2(value, name)
  if type(value) ~= "table" or type(value[1]) ~= "number" or type(value[2]) ~= "number"
    or value[1] ~= math.floor(value[1]) or value[2] ~= math.floor(value[2]) then
    return nil, failure("INVALID_ACTION", (name or "coordinate") .. " must contain two integers")
  end
  return { value[1], value[2] }
end

local function touched(kind, id)
  return { kind = kind, id = id }
end

local function entity_from(action, key)
  return action[key] or action.entity or action.value or action.draft
end

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
  for key, child in pairs(value) do result[key] = action_json_value(child, nil, seen) end
  return result
end

local tuple_fields = { origin_mm = true, size_mm = true, center_mm = true, default_size_mm = true }

local function canonical_entity(kind, draft)
  local prepared = action_json_value(draft, "object")
  if kind == "room" then return model_helpers.new_room(prepared)
  elseif kind == "door" then return model_helpers.new_door(prepared)
  elseif kind == "furniture" then return model_helpers.new_furniture(prepared)
  elseif kind == "template" then return model_helpers.new_custom_template(prepared) end
  return prepared
end

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

function handlers.add_room(model, action)
  local room = entity_from(action, "room")
  if type(room) ~= "table" then return nil, failure("INVALID_ACTION", "add_room requires a room draft") end
  room = canonical_entity("room", room)
  model.rooms[#model.rooms + 1] = room
  return { label = "Add room " .. tostring(room.name or room.id), touched = { touched("room", room.id) } }
end

function handlers.edit_room(model, action)
  local room = find_room(model, action.id or action.room_id)
  if not room then return nil, failure("NOT_FOUND", "room was not found", { id = action.id or action.room_id }) end
  local _, err = copy_patch(room, action.patch or action.changes, room.id)
  if err then return nil, err end
  return { label = "Edit room " .. tostring(room.name or room.id), touched = { touched("room", room.id) } }
end

function handlers.move_room(model, action, context)
  local room = find_room(model, action.id or action.room_id)
  if not room then return nil, failure("NOT_FOUND", "room was not found", { id = action.id or action.room_id }) end
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
  if snap_options and not action.exact then
    snap_options = deep_copy(snap_options)
    snap_options.bypass = action.bypass_snap or snap_options.bypass
    snap_options.grid_mm = snap_options.grid_mm or (model.settings and model.settings.grid_mm)
    local snap_result = snapping.snap_room(room, model.rooms, snap_options)
    room.origin_mm = action_json_value(snap_result.origin_mm, "array")
    metadata.snapping = snap_result
  end
  return { label = "Move room " .. tostring(room.name or room.id), touched = { touched("room", room.id) }, metadata = metadata }
end

function handlers.resize_room(model, action)
  local room = find_room(model, action.id or action.room_id)
  if not room then return nil, failure("NOT_FOUND", "room was not found", { id = action.id or action.room_id }) end
  local size, err = vector2(action.size_mm, "size_mm")
  if not size then return nil, err end
  room.size_mm = action_json_value(size, "array")
  return { label = "Resize room " .. tostring(room.name or room.id), touched = { touched("room", room.id) } }
end

function handlers.align_room(model, action)
  local room = find_room(model, action.id or action.room_id or action.moving_room_id)
  local reference = find_room(model, action.reference_room_id)
  if not room then return nil, failure("NOT_FOUND", "moving room was not found", { id = action.id or action.room_id }) end
  if not reference then return nil, failure("NOT_FOUND", "reference room was not found", { id = action.reference_room_id }) end
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
  local source = find_room(model, action.id or action.room_id)
  if not source then return nil, failure("NOT_FOUND", "source room was not found", { id = action.id or action.room_id }) end
  if type(action.new_id) ~= "string" then return nil, failure("INVALID_ACTION", "duplicate_room requires new_id") end
  local clone = deep_copy(source)
  clone.id = action.new_id
  clone.name = action.name or (source.name .. " copy")
  if action.origin_mm then
    local origin, err = vector2(action.origin_mm, "origin_mm")
    if not origin then return nil, err end
    clone.origin_mm = action_json_value(origin, "array")
  else
    local placement, err = alignment.auto_place(clone.size_mm, model.rooms, {
      cursor_mm = action.cursor_mm or context.cursor_mm,
      max_distance_mm = action.max_distance_mm or (context.limits and context.limits.max_auto_place_distance_mm),
      gap_mm = action.gap_mm or 0,
    })
    if not placement then return nil, err end
    clone.origin_mm = action_json_value(placement.origin_mm, "array")
  end
  model.rooms[#model.rooms + 1] = clone
  return { label = "Duplicate room " .. source.name, touched = { touched("room", clone.id) },
    metadata = { source_id = source.id, placement = { clone.origin_mm[1], clone.origin_mm[2] } } }
end

function M.room_dependencies(model, room_id)
  local result = { furniture = {}, owner_doors = {}, connected_doors = {}, all = {} }
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
  return result
end

local function remove_if(values, predicate)
  local removed = {}
  local i = #values
  while i >= 1 do
    if predicate(values[i]) then
      table.insert(removed, 1, table.remove(values, i))
    end
    i = i - 1
  end
  return removed
end

function handlers.delete_room_cascade(model, action)
  local room, index = find_room(model, action.id or action.room_id)
  if not room then return nil, failure("NOT_FOUND", "room was not found", { id = action.id or action.room_id }) end
  local dependencies = M.room_dependencies(model, room.id)
  table.remove(model.rooms, index)
  remove_if(model.furniture, function(value) return value.room_id == room.id end)
  remove_if(model.doors, function(value) return value.room_id == room.id or connected_id(value) == room.id end)
  local all_touched = { touched("room", room.id) }
  local i
  for i = 1, #dependencies.all do all_touched[#all_touched + 1] = dependencies.all[i] end
  return { label = "Delete room " .. tostring(room.name or room.id), touched = all_touched,
    metadata = { deleted_dependencies = dependencies } }
end

function handlers.rename_room(model, action)
  local room = find_room(model, action.id or action.room_id)
  if not room then return nil, failure("NOT_FOUND", "room was not found", { id = action.id or action.room_id }) end
  room.name = action.name
  return { label = "Rename room " .. room.id, touched = { touched("room", room.id) } }
end

function handlers.add_furniture(model, action)
  local furniture = entity_from(action, "furniture")
  if type(furniture) ~= "table" then return nil, failure("INVALID_ACTION", "add_furniture requires a furniture draft") end
  local result_touched = {}
  if action.custom_template then
    local custom_template = canonical_entity("template", action.custom_template)
    model.custom_templates[#model.custom_templates + 1] = custom_template
    result_touched[#result_touched + 1] = touched("template", action.custom_template.id)
  end
  furniture = canonical_entity("furniture", furniture)
  model.furniture[#model.furniture + 1] = furniture
  result_touched[#result_touched + 1] = touched("furniture", furniture.id)
  return { label = "Add furniture " .. tostring(furniture.name or furniture.id), touched = result_touched }
end

function handlers.edit_furniture(model, action)
  local furniture = find(model.furniture, action.id or action.furniture_id)
  if not furniture then return nil, failure("NOT_FOUND", "furniture was not found", { id = action.id or action.furniture_id }) end
  local _, err = copy_patch(furniture, action.patch or action.changes, furniture.id)
  if err then return nil, err end
  return { label = "Edit furniture " .. tostring(furniture.name or furniture.id),
    touched = { touched("furniture", furniture.id) } }
end

function handlers.move_furniture(model, action, context)
  local furniture = find(model.furniture, action.id or action.furniture_id)
  if not furniture then return nil, failure("NOT_FOUND", "furniture was not found", { id = action.id or action.furniture_id }) end
  local center
  if action.center_mm then
    local err
    center, err = vector2(action.center_mm, "center_mm")
    if not center then return nil, err end
  else
    local delta, err = vector2(action.delta_mm or { action.dx_mm, action.dy_mm }, "delta_mm")
    if not delta then return nil, err end
    center = { furniture.center_mm[1] + delta[1], furniture.center_mm[2] + delta[2] }
  end
  furniture.center_mm = action_json_value(center, "array")
  local metadata = { requested_center_mm = { center[1], center[2] } }
  local snap_options = action.snap or context.snapping
  if snap_options and not action.exact then
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
      snap_options = deep_copy(snap_options)
      snap_options.bypass = action.bypass_snap or snap_options.bypass
      snap_options.grid_mm = snap_options.grid_mm or (model.settings and model.settings.grid_mm)
      local snap_result = snapping.snap_furniture(owner, furniture, pairs, apertures, snap_options)
      furniture.center_mm = action_json_value(snap_result.center_mm, "array")
      metadata.snapping = snap_result
    end
  end
  return { label = "Move furniture " .. tostring(furniture.name or furniture.id),
    touched = { touched("furniture", furniture.id) }, metadata = metadata }
end

function handlers.resize_furniture(model, action)
  local furniture = find(model.furniture, action.id or action.furniture_id)
  if not furniture then return nil, failure("NOT_FOUND", "furniture was not found", { id = action.id or action.furniture_id }) end
  if type(action.size_mm) ~= "table" or #action.size_mm < 3 then
    return nil, failure("INVALID_ACTION", "size_mm must contain width, depth, and height")
  end
  furniture.size_mm = action_json_value(action.size_mm, "array")
  return { label = "Resize furniture " .. tostring(furniture.name or furniture.id),
    touched = { touched("furniture", furniture.id) } }
end

function handlers.rotate_furniture(model, action)
  local furniture = find(model.furniture, action.id or action.furniture_id)
  if not furniture then return nil, failure("NOT_FOUND", "furniture was not found", { id = action.id or action.furniture_id }) end
  furniture.rotation_deg = action.rotation_deg ~= nil and action.rotation_deg or ((furniture.rotation_deg + (action.delta_deg or 90)) % 360)
  return { label = "Rotate furniture " .. tostring(furniture.name or furniture.id),
    touched = { touched("furniture", furniture.id) } }
end

function handlers.duplicate_furniture(model, action)
  local source = find(model.furniture, action.id or action.furniture_id)
  if not source then return nil, failure("NOT_FOUND", "source furniture was not found", { id = action.id or action.furniture_id }) end
  if type(action.new_id) ~= "string" then return nil, failure("INVALID_ACTION", "duplicate_furniture requires new_id") end
  local clone = deep_copy(source)
  clone.id = action.new_id
  clone.name = action.name or (source.name .. " copy")
  local step = action.step_mm or (model.settings and model.settings.normal_step_mm) or 100
  clone.center_mm = action_json_value({ source.center_mm[1] + step, source.center_mm[2] + step }, "array")
  model.furniture[#model.furniture + 1] = clone
  return { label = "Duplicate furniture " .. source.name, touched = { touched("furniture", clone.id) },
    metadata = { source_id = source.id, delta_mm = { step, step } } }
end

function handlers.delete_furniture(model, action)
  local furniture, index = find(model.furniture, action.id or action.furniture_id)
  if not furniture then return nil, failure("NOT_FOUND", "furniture was not found", { id = action.id or action.furniture_id }) end
  table.remove(model.furniture, index)
  return { label = "Delete furniture " .. tostring(furniture.name or furniture.id),
    touched = { touched("furniture", furniture.id) } }
end

function handlers.rename_furniture(model, action)
  return handlers.edit_furniture(model, { id = action.id or action.furniture_id, patch = { name = action.name } })
end

function handlers.change_furniture_template(model, action)
  return handlers.edit_furniture(model, { id = action.id or action.furniture_id,
    patch = { template_id = action.template_id, category = action.category } })
end

function handlers.add_door(model, action)
  local door = entity_from(action, "door")
  if type(door) ~= "table" then return nil, failure("INVALID_ACTION", "add_door requires a door draft") end
  door = canonical_entity("door", door)
  model.doors[#model.doors + 1] = door
  return { label = "Add door " .. tostring(door.id), touched = { touched("door", door.id) } }
end

function handlers.edit_door(model, action, context)
  local door = find(model.doors, action.id or action.door_id)
  if not door then return nil, failure("NOT_FOUND", "door was not found", { id = action.id or action.door_id }) end
  local _, err = copy_patch(door, action.patch or action.changes, door.id)
  if err then return nil, err end
  local snap_options = action.snap or context.snapping
  if snap_options and not action.exact then
    local owner = find_room(model, door.room_id)
    if owner then
      local edge_length = door_geometry.edge_length(owner, door.side)
      local endpoints = {}
      local i
      for i = 1, #model.doors do
        local other = model.doors[i]
        if other.id ~= door.id and other.room_id == door.room_id and other.side == door.side then
          endpoints[#endpoints + 1] = { value_mm = other.offset_mm, kind = "door", id = other.id, name = "start" }
          endpoints[#endpoints + 1] = { value_mm = other.offset_mm + other.width_mm, kind = "door", id = other.id, name = "finish" }
        end
      end
      local owner_edge = adjacency.edge(owner, door.side)
      for i = 1, #model.rooms do
        local other_room = model.rooms[i]
        if other_room.id ~= owner.id then
          local relation = adjacency.between(owner, other_room)
          if relation and relation.a_side == door.side then
            endpoints[#endpoints + 1] = {
              value_mm = relation.start_mm - owner_edge.start_mm,
              kind = "room_edge", id = other_room.id, name = "shared-start",
            }
            endpoints[#endpoints + 1] = {
              value_mm = relation.finish_mm - owner_edge.start_mm,
              kind = "room_edge", id = other_room.id, name = "shared-finish",
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
  local door = find(model.doors, action.id or action.door_id)
  if not door then return nil, failure("NOT_FOUND", "door was not found", { id = action.id or action.door_id }) end
  door.hinge = door.hinge == "start" and "end" or "start"
  return { label = "Toggle hinge " .. door.id, touched = { touched("door", door.id) } }
end

function handlers.toggle_door_swing(model, action)
  local door = find(model.doors, action.id or action.door_id)
  if not door then return nil, failure("NOT_FOUND", "door was not found", { id = action.id or action.door_id }) end
  if connected_id(door) then
    door.opens_into = door.opens_into == "owner" and "connected" or "owner"
  else
    door.opens_into = door.opens_into == "owner" and "outside" or "owner"
  end
  return { label = "Toggle swing " .. door.id, touched = { touched("door", door.id) } }
end

function handlers.delete_door(model, action)
  local door, index = find(model.doors, action.id or action.door_id)
  if not door then return nil, failure("NOT_FOUND", "door was not found", { id = action.id or action.door_id }) end
  table.remove(model.doors, index)
  return { label = "Delete door " .. door.id, touched = { touched("door", door.id) } }
end

function handlers.duplicate_door_from_draft(model, action)
  local source = find(model.doors, action.id or action.door_id)
  if not source then return nil, failure("NOT_FOUND", "source door was not found", { id = action.id or action.door_id }) end
  local clone = deep_copy(source)
  if type(action.new_id) ~= "string" then return nil, failure("INVALID_ACTION", "duplicate_door_from_draft requires new_id") end
  clone.id = action.new_id
  local _, err = copy_patch(clone, action.patch or {}, clone.id)
  if err then return nil, err end
  model.doors[#model.doors + 1] = clone
  return { label = "Duplicate door draft " .. source.id, touched = { touched("door", clone.id) },
    metadata = { source_id = source.id } }
end

function handlers.add_custom_template(model, action)
  local template = entity_from(action, "template")
  if type(template) ~= "table" then return nil, failure("INVALID_ACTION", "add_custom_template requires a template draft") end
  template = canonical_entity("template", template)
  model.custom_templates[#model.custom_templates + 1] = template
  return { label = "Add template " .. tostring(template.name or template.id), touched = { touched("template", template.id) } }
end

function handlers.edit_custom_template(model, action)
  local template = find(model.custom_templates, action.id or action.template_id)
  if not template then return nil, failure("NOT_FOUND", "custom template was not found", { id = action.id or action.template_id }) end
  local _, err = copy_patch(template, action.patch or action.changes, template.id)
  if err then return nil, err end
  return { label = "Edit template " .. tostring(template.name or template.id), touched = { touched("template", template.id) } }
end

function handlers.duplicate_custom_template(model, action)
  local source = find(model.custom_templates, action.id or action.template_id)
  if not source then return nil, failure("NOT_FOUND", "custom template was not found", { id = action.id or action.template_id }) end
  if type(action.new_id) ~= "string" then return nil, failure("INVALID_ACTION", "duplicate_custom_template requires new_id") end
  local clone = deep_copy(source)
  clone.id, clone.name = action.new_id, action.name or (source.name .. " copy")
  model.custom_templates[#model.custom_templates + 1] = clone
  return { label = "Duplicate template " .. source.name, touched = { touched("template", clone.id) },
    metadata = { source_id = source.id } }
end

function handlers.delete_custom_template(model, action)
  local template, index = find(model.custom_templates, action.id or action.template_id)
  if not template then return nil, failure("NOT_FOUND", "custom template was not found", { id = action.id or action.template_id }) end
  local references = {}
  local i
  for i = 1, #model.furniture do
    if model.furniture[i].template_id == template.id then references[#references + 1] = model.furniture[i].id end
  end
  if #references > 0 then
    return nil, failure("TEMPLATE_IN_USE", "template " .. template.id .. " is still referenced", { references = references })
  end
  table.remove(model.custom_templates, index)
  return { label = "Delete template " .. template.name, touched = { touched("template", template.id) } }
end

function handlers.edit_metadata(model, action)
  model.metadata = model.metadata or {}
  local _, err = copy_patch(model.metadata, action.patch or action.changes, nil)
  if err then return nil, err end
  return { label = "Edit plan metadata", touched = { touched("plan", "roomplan.nvim") } }
end

function handlers.edit_plan_settings(model, action)
  model.settings = model.settings or {}
  local _, err = copy_patch(model.settings, action.patch or action.changes, nil)
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

handlers.delete_room = handlers.delete_room_cascade
handlers.rename_template = handlers.edit_custom_template

local room_actions = {
  add_room = true, edit_room = true, move_room = true, resize_room = true,
  align_room = true, duplicate_room = true,
}
local door_actions = {
  add_door = true, edit_door = true, toggle_door_hinge = true,
  toggle_door_swing = true, duplicate_door_from_draft = true,
}

local function diagnostic_signature(value)
  local related = {}
  local i
  for i = 1, #(value.related or {}) do
    related[#related + 1] = tostring(value.related[i].kind) .. ":" .. tostring(value.related[i].id)
  end
  table.sort(related)
  return table.concat({ value.code or "", value.object and value.object.kind or "",
    value.object and value.object.id or "", table.concat(related, ",") }, "|")
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
      if (counts[key] or 0) > 0 then counts[key] = counts[key] - 1
      else result[#result + 1] = after[i] end
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
  local must_block = room_actions[name] or door_actions[name]

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
    return nil, failure("STRUCTURAL_INVALID", "action would violate structural model invariants",
      { diagnostics = after_structural, action = name })
  end
  -- The schema is also the authority for tagged JSON object/array state and
  -- unknown extension values. Constructors above make normal UI drafts valid;
  -- this final gate catches ambiguous/unrepresentable action payloads.
  local schema_valid, schema_info, normalized = schema.validate(copy)
  if not schema_valid then
    return nil, failure("STRUCTURAL_INVALID", "action produced a model that cannot be encoded safely",
      { schema_error = schema_info, action = name })
  end
  copy = normalized
  if deep_equal(model, copy) then return nil, failure("NO_CHANGE", "action did not change the model", { noop = true }) end

  local after_diagnostics, after_summary = validate.run(copy, context.validation or context)
  local new_errors = newly_introduced_errors(before_diagnostics, after_diagnostics)
  local force = action.force == true or context.force == true
  if must_block and #new_errors > 0 and not force then
    return nil, failure("LAYOUT_BLOCKED", "action would introduce layout errors", {
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

M.handlers = handlers

return M
