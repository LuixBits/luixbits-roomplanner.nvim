local adjacency = require("roomplan.geometry.adjacency")
local json = require("roomplan.codec.json")
local config = require("roomplan.config")
local model_helpers = require("roomplan.model")
local util = require("roomplan.util")
local common = require("roomplan.ui.forms.common")
local directions = require("roomplan.directions")

local M = {}

local function schema_version(context)
  local plan = common.model(context)
  return plan and plan.schema_version or 1
end

local function owner(draft, context)
  return common.find(context, "room", draft.room_id)
end

local function selected_part(room, part_id)
  if not room or not room.footprint then return nil end
  for _, part in ipairs(room.footprint.parts or {}) do
    if part.id == part_id then return part end
  end
  return nil
end

local function part_choices(context, draft)
  local room = owner(draft, context)
  local result = {}
  for _, part in ipairs(room and room.footprint and room.footprint.parts or {}) do
    result[#result + 1] = {
      value = part.id,
      label = string.format("%s (%d x %d mm)", part.id, part.size_mm[1], part.size_mm[2]),
    }
  end
  return result
end

local function first_part_id(room)
  local part = room and room.footprint and room.footprint.parts and room.footprint.parts[1]
  return part and part.id or "part-main"
end

local function part_room(room, part_id)
  if not room or not room.footprint then return room end
  local part = selected_part(room, part_id)
  if not part then return nil end
  return {
    origin_mm = { room.origin_mm[1] + part.origin_mm[1], room.origin_mm[2] + part.origin_mm[2] },
    size_mm = { part.size_mm[1], part.size_mm[2] },
  }
end

local function rectangles(room)
  if not room or not room.footprint then return room and { room } or {} end
  local result = {}
  for _, part in ipairs(room.footprint.parts or {}) do
    result[#result + 1] = part_room(room, part.id)
  end
  return result
end

local function edge_length(draft, context)
  local room = owner(draft, context)
  if not room then return nil end
  local edge_owner = part_room(room, draft.part_id)
  if not edge_owner then return nil end
  return (draft.side == "north" or draft.side == "south") and edge_owner.size_mm[1] or edge_owner.size_mm[2]
end

local function connections(context, draft)
  local result = { { value = "outside", label = "Outside" } }
  local room = owner(draft, context)
  if not room then return result end
  local edge_owner = part_room(room, draft.part_id)
  if not edge_owner then return result end
  for _, other in ipairs(common.model(context).rooms or {}) do
    if other.id ~= room.id then
      local shares_side = false
      for _, other_rectangle in ipairs(rectangles(other)) do
        local shared = adjacency.between(edge_owner, other_rectangle)
        if shared and shared.a_side == draft.side then shares_side = true; break end
      end
      if shares_side then
        result[#result + 1] = {
          value = other.id,
          label = string.format("%s (%s)", other.name or other.id, other.id),
        }
      end
    end
  end
  return result
end

local function offset(draft, context)
  local length = edge_length(draft, context)
  if not length or type(draft.width_mm) ~= "number" then
    return nil, { code = "DOOR_EDGE", message = "choose an owner room, wall, and width" }
  end
  if draft.placement == "exact" then return draft.offset_mm end
  if draft.placement == "cursor" then
    local room = owner(draft, context)
    local cursor = common.cursor(context)
    if not cursor then return nil, { code = "CURSOR_UNAVAILABLE", message = "the canvas cursor position is unavailable" } end
    local edge_owner = part_room(room, draft.part_id)
    if not edge_owner then return nil, { code = "DOOR_PART", message = "choose an owner footprint part" } end
    local coordinate = (draft.side == "north" or draft.side == "south")
        and (cursor[1] - edge_owner.origin_mm[1])
      or (cursor[2] - edge_owner.origin_mm[2])
    return util.round(coordinate - draft.width_mm / 2)
  end
  return util.round((length - draft.width_mm) / 2)
end

local function opening_choices(_, draft)
  if draft.connects_to_room_id == "outside" then
    return {
      { value = "owner", label = "Into owner room" },
      { value = "outside", label = "To outside" },
    }
  end
  return {
    { value = "owner", label = "Into owner room" },
    { value = "connected", label = "Into connected room" },
  }
end

function M.add(session, opts)
  opts = opts or {}
  local runtime = config.get()
  local context = { session = session, cursor_mm = opts.cursor_mm }
  local room_id = opts.room_id or common.selected_room(context)
  local plan = common.model(context)
  local version = schema_version(context)
  local initial_room = room_id and common.find(context, "room", room_id) or nil
  local spec = {
    id = "add-door",
    title = "Add hinged door",
    mode = "DOOR CREATE",
    description = "Offset is measured from the wall's canonical start.",
    apply_label = "Create door",
    context = context,
    initial = {
      room_id = room_id,
      part_id = opts.part_id or first_part_id(initial_room),
      side = opts.side or "north",
      width_mm = opts.width_mm or (plan and plan.settings.default_door_width_mm) or 900,
      placement = opts.placement or "centre",
      offset_mm = opts.offset_mm or 0,
      hinge = opts.hinge or "start",
      connects_to_room_id = opts.connects_to_room_id or "outside",
      opens_into = opts.opens_into or "owner",
      open_angle_deg = opts.open_angle_deg or 90,
    },
    fields = {
      { key = "room_id", label = "Owner room", type = "object_ref", required = true, choices = function(ctx) return common.rooms(ctx) end },
      {
        key = "side", label = "Wall", type = "enum", required = true,
        choices = function(ctx) return directions.choices(ctx) end,
      },
      {
        key = "width_mm", label = "Width", type = "measurement", required = true,
        max = function(ctx, draft) return edge_length(draft, ctx) or runtime.limits.max_dimension_mm end,
      },
      {
        key = "placement", label = "Placement", type = "enum", required = true,
        choices = {
          { value = "centre", label = "Centred on wall" },
          { value = "cursor", label = "Centred at canvas cursor" },
          { value = "exact", label = "Exact offset" },
        },
      },
      {
        key = "offset_mm", label = "Offset", type = "measurement", allow_zero = true,
        visible = function(_, draft) return draft.placement == "exact" end,
      },
      {
        key = "resolved_offset", label = "Resolved offset", type = "readonly",
        value = function(ctx, draft) return offset(draft, ctx) end,
        format = function(value) return value and (tostring(value) .. " mm") or "unavailable" end,
      },
      {
        key = "hinge", label = "Hinge", type = "enum", required = true,
        choices = { { value = "start", label = "Canonical start" }, { value = "end", label = "Canonical end" } },
      },
      {
        key = "connects_to_room_id", label = "Connects to", type = "object_ref", required = true,
        choices = connections,
      },
      {
        key = "opens_into", label = "Opens", type = "enum", required = true,
        choices = opening_choices,
      },
      { key = "open_angle_deg", label = "Open angle", type = "integer", required = true, min = 1, max = 180 },
    },
    on_change = function(key, value, _, draft, ctx)
      if key == "room_id" and version >= 2 then
        return { part_id = first_part_id(common.find(ctx, "room", value)) }
      elseif key == "connects_to_room_id" then
        if value == "outside" and draft.opens_into == "connected" then return { opens_into = "owner" } end
        if value ~= "outside" and draft.opens_into == "outside" then return { opens_into = "owner" } end
      end
    end,
    preview = function(draft, ctx)
      local resolved, err = offset(draft, ctx)
      if resolved == nil then return nil, err end
      local room = owner(draft, ctx)
      local destination = draft.connects_to_room_id == "outside" and "outside"
        or (common.find(ctx, "room", draft.connects_to_room_id) or {}).name
        or draft.connects_to_room_id
      return {
        lines = {
          string.format("%s wall of %s: offset %d mm, width %d mm",
            directions.label(draft.side, ctx), room.name or room.id, resolved, draft.width_mm),
          string.format("Hinge at %s; opens %s; destination %s; angle %d degrees",
            draft.hinge, draft.opens_into, destination, draft.open_angle_deg),
        },
      }
    end,
  }
  if version >= 2 then
    table.insert(spec.fields, 2, {
      key = "part_id", label = "Footprint part", type = "object_ref", required = true,
      choices = part_choices,
    })
  end
  function spec.validate(draft, ctx)
    local errors = {}
    local room = owner(draft, ctx)
    if not room then errors.room_id = "owner room no longer exists" end
    if version >= 2 and room and not selected_part(room, draft.part_id) then
      errors.part_id = "owner footprint part no longer exists"
    end
    local resolved = offset(draft, ctx)
    local length = edge_length(draft, ctx)
    if resolved and length and (resolved < 0 or resolved + draft.width_mm > length) then
      errors.offset_mm = string.format("opening must fit within the %d mm wall", length)
      if draft.placement ~= "exact" then errors.placement = errors.offset_mm end
    end
    local available = false
    for _, choice in ipairs(connections(ctx, draft)) do
      if choice.value == draft.connects_to_room_id then available = true; break end
    end
    if not available then errors.connects_to_room_id = "connected room does not share that wall" end
    return errors
  end
  function spec.build(draft, ctx)
    ctx = ctx or context
    local resolved, err = offset(draft, ctx)
    if resolved == nil then return nil, err end
    local room = owner(draft, ctx)
    if not room then return nil, { code = "ROOM_REQUIRED", message = "the owner room no longer exists" } end
    local id, id_err = common.generate_id(ctx, "door", (room.name or room.id) .. "-" .. draft.side)
    if not id then return nil, id_err end
    local connection = draft.connects_to_room_id
    if connection == "outside" then connection = nil end
    local door_fields = {
      id = id,
      room_id = draft.room_id,
      connects_to_room_id = connection,
      side = draft.side,
      offset_mm = resolved,
      width_mm = draft.width_mm,
      hinge = draft.hinge,
      opens_into = draft.opens_into,
      open_angle_deg = draft.open_angle_deg,
    }
    if version >= 2 then door_fields.part_id = draft.part_id end
    return {
      type = "add_door",
      door = model_helpers.new_door(door_fields, { schema_version = version }),
    }
  end
  return spec
end

function M.edit(session, door, opts)
  opts = opts or {}
  if type(door) == "string" then door = model_helpers.find(session:model(), "door", door) end
  assert(type(door) == "table" and type(door.id) == "string", "door.edit requires a door")
  local context = { session = session, door_id = door.id }
  local version = schema_version(context)
  local connection = door.connects_to_room_id
  if connection == nil or json.is_null(connection) then connection = "outside" end
  local spec = {
    id = "edit-door",
    title = "Edit hinged door",
    mode = "DOOR EDIT",
    description = "Every door property is shown and applied atomically.",
    apply_label = "Apply door changes",
    context = context,
    initial = {
      room_id = door.room_id,
      part_id = door.part_id or "part-main",
      side = door.side,
      width_mm = door.width_mm,
      placement = "exact",
      offset_mm = door.offset_mm,
      hinge = door.hinge,
      connects_to_room_id = connection,
      opens_into = door.opens_into,
      open_angle_deg = door.open_angle_deg,
    },
    fields = {
      { key = "room_id", label = "Owner room", type = "object_ref", required = true, choices = function(ctx) return common.rooms(ctx) end },
      {
        key = "side", label = "Wall", type = "enum", required = true,
        choices = function(ctx) return directions.choices(ctx) end,
      },
      {
        key = "width_mm", label = "Width", type = "measurement",
        max = function(ctx, draft) return edge_length(draft, ctx) end,
      },
      { key = "offset_mm", label = "Offset", type = "measurement", allow_zero = true },
      {
        key = "hinge", label = "Hinge", type = "enum", required = true,
        choices = { { value = "start", label = "Canonical start" }, { value = "end", label = "Canonical end" } },
      },
      {
        key = "connects_to_room_id", label = "Connects to", type = "object_ref", required = true,
        choices = connections,
      },
      { key = "opens_into", label = "Opens", type = "enum", required = true, choices = opening_choices },
      { key = "open_angle_deg", label = "Open angle", type = "integer", min = 1, max = 180 },
      {
        key = "summary", label = "Result", type = "readonly",
        value = function(ctx, draft)
          return string.format("%s wall, offset %d mm, width %d mm",
            directions.label(draft.side, ctx), draft.offset_mm, draft.width_mm)
        end,
      },
    },
    on_change = function(key, value, _, draft, ctx)
      if key == "room_id" and version >= 2 then
        return { part_id = first_part_id(common.find(ctx, "room", value)) }
      elseif key == "connects_to_room_id" then
        if value == "outside" and draft.opens_into == "connected" then return { opens_into = "owner" } end
        if value ~= "outside" and draft.opens_into == "outside" then return { opens_into = "owner" } end
      end
    end,
    validate = function(draft, ctx)
      local errors = {}
      if not common.find(ctx, "door", ctx.door_id) then errors._form = "the door no longer exists" end
      local room = owner(draft, ctx)
      if not room then errors.room_id = "owner room no longer exists" end
      if version >= 2 and room and not selected_part(room, draft.part_id) then
        errors.part_id = "owner footprint part no longer exists"
      end
      local length = edge_length(draft, ctx)
      if length and (draft.offset_mm < 0 or draft.offset_mm + draft.width_mm > length) then
        errors.offset_mm = string.format("opening must fit within the %d mm wall", length)
      end
      local available = false
      for _, choice in ipairs(connections(ctx, draft)) do
        if choice.value == draft.connects_to_room_id then available = true; break end
      end
      if not available then errors.connects_to_room_id = "connected room does not share that wall" end
      return errors
    end,
    preview = function(draft, ctx)
      local room = owner(draft, ctx)
      if not room then return nil, { code = "ROOM_REQUIRED", message = "choose an owner room" } end
      return {
        lines = {
          string.format("%s wall of %s: offset %d mm, width %d mm",
            directions.label(draft.side, ctx), room.name or room.id, draft.offset_mm, draft.width_mm),
          string.format("Hinge %s; opens %s; angle %d degrees", draft.hinge, draft.opens_into, draft.open_angle_deg),
        },
      }
    end,
  }
  if version >= 2 then
    table.insert(spec.fields, 2, {
      key = "part_id", label = "Footprint part", type = "object_ref", required = true,
      choices = part_choices,
    })
  end
  function spec.build(draft, ctx)
    ctx = ctx or context
    if not common.find(ctx, "door", ctx.door_id) then
      return nil, { code = "NOT_FOUND", message = "the door no longer exists" }
    end
    local patch = {
      room_id = draft.room_id,
      side = draft.side,
      width_mm = draft.width_mm,
      offset_mm = draft.offset_mm,
      hinge = draft.hinge,
      connects_to_room_id = draft.connects_to_room_id == "outside" and json.null or draft.connects_to_room_id,
      opens_into = draft.opens_into,
      open_angle_deg = draft.open_angle_deg,
    }
    if version >= 2 then patch.part_id = draft.part_id end
    return {
      type = "edit_door",
      id = ctx.door_id,
      exact = true,
      patch = patch,
    }
  end
  return spec
end

---Build an atomic copy form for the three placement properties users choose
---when duplicating a door. The remaining connection and swing properties are
---copied unchanged by the action handler.
function M.duplicate(session, door, opts)
  opts = opts or {}
  if type(door) == "string" then door = model_helpers.find(session:model(), "door", door) end
  assert(type(door) == "table" and type(door.id) == "string", "door.duplicate requires a door")
  local context = { session = session, door_id = door.id }
  local spec = {
    id = "duplicate-door",
    title = "Duplicate hinged door",
    mode = "DOOR DUPLICATE",
    description = "Place a copy on the same wall; connection and swing are preserved.",
    apply_label = "Create door copy",
    context = context,
    initial = {
      offset_mm = opts.offset_mm or (door.offset_mm + door.width_mm),
      width_mm = opts.width_mm or door.width_mm,
      hinge = opts.hinge or door.hinge,
    },
    fields = {
      {
        key = "source", label = "Source", type = "readonly",
        value = function(ctx)
          local current = common.find(ctx, "door", ctx.door_id)
          if not current then return "unavailable" end
          return string.format("%s wall of %s", current.side, current.room_id)
        end,
      },
      { key = "offset_mm", label = "Copy offset", type = "measurement", required = true, allow_zero = true },
      { key = "width_mm", label = "Copy width", type = "measurement", required = true },
      {
        key = "hinge", label = "Copy hinge", type = "enum", required = true,
        choices = { { value = "start", label = "Canonical start" }, { value = "end", label = "Canonical end" } },
      },
    },
    validate = function(draft, ctx)
      local errors = {}
      local source = common.find(ctx, "door", ctx.door_id)
      if not source then
        errors._form = "the source door no longer exists"
        return errors
      end
      local length = edge_length({ room_id = source.room_id, part_id = source.part_id, side = source.side }, ctx)
      if length and draft.offset_mm + draft.width_mm > length then
        errors.offset_mm = string.format("opening must fit within the %d mm wall", length)
      end
      return errors
    end,
    preview = function(draft, ctx)
      local source = common.find(ctx, "door", ctx.door_id)
      if not source then return nil, { code = "NOT_FOUND", message = "the source door no longer exists" } end
      return {
        lines = {
          string.format("%s wall: offset %d mm, width %d mm", source.side, draft.offset_mm, draft.width_mm),
          string.format("Hinge %s; connection and swing copied from %s", draft.hinge, source.id),
        },
      }
    end,
  }
  function spec.build(draft, ctx)
    ctx = ctx or context
    local source = common.find(ctx, "door", ctx.door_id)
    if not source then return nil, { code = "NOT_FOUND", message = "the source door no longer exists" } end
    local id, id_err = common.generate_id(ctx, "door", source.id .. " copy")
    if not id then return nil, id_err end
    return {
      type = "duplicate_door_from_draft",
      id = source.id,
      new_id = id,
      patch = {
        offset_mm = draft.offset_mm,
        width_mm = draft.width_mm,
        hinge = draft.hinge,
      },
    }
  end
  return spec
end

M.new = M.add
M.offset = offset

return M
