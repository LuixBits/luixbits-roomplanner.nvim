local footprint = require("roomplan.geometry.footprint")
local number = require("roomplan.geometry.number")
local model = require("roomplan.model")
local outlet_types = require("roomplan.outlet_types")
local common = require("roomplan.ui.forms.common")
local wall = require("roomplan.ui.forms.wall_attachment")
local directions = require("roomplan.directions")

local M = {}

local type_labels = {
  power = "Power",
  usb = "USB",
  ethernet = "Ethernet",
  coax = "TV / coax",
  phone = "Phone",
  other = "Other",
}

M.type_choices = {}
for _, value in ipairs(outlet_types.values) do
  M.type_choices[#M.type_choices + 1] = { value = value, label = type_labels[value] or value }
end

local function schema_version(context)
  local plan = common.model(context)
  return plan and plan.schema_version or 4
end

local function is_wall(draft) return draft.placement ~= "floor" end

local function room_centre(room)
  local shape = room and footprint.local_from_room(room) or nil
  local anchor = shape and footprint.label_anchor2(shape) or nil
  if not anchor then return nil end
  return { number.from_doubled(anchor.x2), number.from_doubled(anchor.y2) }
end

local function floor_position(draft, context)
  local owner = common.find(context, "room", draft.room_id)
  if not owner then return nil, { code = "ROOM_REQUIRED", message = "choose an owner room" } end
  if draft.floor_positioning == "exact" then
    if type(draft.local_x_mm) ~= "number" or type(draft.local_y_mm) ~= "number" then
      return nil, { code = "OUTLET_FLOOR_POSITION", message = "enter exact room-local coordinates" }
    end
    return { draft.local_x_mm, draft.local_y_mm }
  elseif draft.floor_positioning == "cursor" then
    local cursor = common.cursor(context)
    if not cursor then
      return nil, { code = "CURSOR_UNAVAILABLE", message = "the canvas cursor position is unavailable" }
    end
    return { cursor[1] - owner.origin_mm[1], cursor[2] - owner.origin_mm[2] }
  end
  local position = room_centre(owner)
  if not position then return nil, { code = "ROOM_GEOMETRY", message = "the room footprint is unavailable" } end
  return position
end

local function floor_position_error(draft, context)
  local owner = common.find(context, "room", draft.room_id)
  if not owner then return "owner room no longer exists" end
  local position, err = floor_position(draft, context)
  if not position then return err.message end
  local shape = footprint.local_from_room(owner)
  local inside = shape
      and footprint.contains_point2(shape, 2 * position[1], 2 * position[2], { include_boundary = false })
    or false
  if not inside then return "floor outlet must lie strictly inside the owner room" end
end

local function fields(editing)
  local result = {
    {
      key = "room_id",
      label = "Owner room",
      type = "object_ref",
      required = true,
      choices = function(ctx) return common.rooms(ctx) end,
    },
    {
      key = "placement",
      label = "Location",
      type = "enum",
      required = true,
      choices = {
        { value = "wall", label = "On a wall" },
        { value = "floor", label = "On the floor" },
      },
    },
    { key = "outlet_type", label = "Type", type = "enum", required = true, choices = M.type_choices },
    { key = "slots", label = "Slots", type = "integer", required = true, min = 1, max = 32 },
    {
      key = "part_id",
      label = "Footprint part",
      type = "object_ref",
      required = true,
      choices = wall.part_choices,
      visible = function(_, draft) return is_wall(draft) end,
    },
    {
      key = "side",
      label = "Wall",
      type = "enum",
      required = true,
      choices = wall.side_choices,
      visible = function(_, draft) return is_wall(draft) end,
    },
    {
      key = "wall_positioning",
      label = "Wall position",
      type = "enum",
      required = true,
      choices = {
        { value = "centre", label = "Wall centre" },
        { value = "cursor", label = "At canvas cursor" },
        { value = "exact", label = "Exact offset" },
      },
      visible = function(_, draft) return is_wall(draft) end,
    },
    {
      key = "offset_mm",
      label = "Offset",
      type = "measurement",
      allow_zero = true,
      visible = function(_, draft) return is_wall(draft) and draft.wall_positioning == "exact" end,
    },
    {
      key = "resolved_offset",
      label = "Resolved offset",
      type = "readonly",
      visible = function(_, draft) return is_wall(draft) end,
      value = function(ctx, draft)
        local wall_draft = vim.tbl_extend("force", {}, draft, { placement = draft.wall_positioning })
        return wall.resolve_offset(wall_draft, ctx, 0)
      end,
      format = function(value) return value and (tostring(value) .. " mm") or "unavailable" end,
    },
    {
      key = "floor_positioning",
      label = "Floor position",
      type = "enum",
      required = true,
      choices = {
        { value = "centre", label = "Room centre" },
        { value = "cursor", label = "At canvas cursor" },
        { value = "exact", label = "Exact room-local coordinates" },
      },
      visible = function(_, draft) return not is_wall(draft) end,
    },
    {
      key = "local_x_mm",
      label = "Room-local X",
      type = "measurement",
      allow_negative = true,
      allow_zero = true,
      visible = function(_, draft) return not is_wall(draft) and draft.floor_positioning == "exact" end,
    },
    {
      key = "local_y_mm",
      label = "Room-local Y",
      type = "measurement",
      allow_negative = true,
      allow_zero = true,
      visible = function(_, draft) return not is_wall(draft) and draft.floor_positioning == "exact" end,
    },
    {
      key = "resolved_position",
      label = "Resolved position",
      type = "readonly",
      visible = function(_, draft) return not is_wall(draft) end,
      value = function(ctx, draft) return floor_position(draft, ctx) end,
      format = function(value) return common.point_text(value) end,
    },
  }
  if editing then
    result[#result + 1] = {
      key = "summary",
      label = "Result",
      type = "readonly",
      value = function(_, draft)
        return string.format(
          "%s outlet · %d slot%s · %s",
          draft.outlet_type,
          draft.slots,
          draft.slots == 1 and "" or "s",
          is_wall(draft) and "wall" or "floor"
        )
      end,
    }
  end
  return result
end

local function wall_draft(draft) return vim.tbl_extend("force", {}, draft, { placement = draft.wall_positioning }) end

local function validate(draft, context, id)
  local errors = {}
  if id and not common.find(context, "outlet", id) then errors._form = "the outlet no longer exists" end
  local owner = common.find(context, "room", draft.room_id)
  if not owner then errors.room_id = "owner room no longer exists" end
  if not is_wall(draft) then
    local position_error = floor_position_error(draft, context)
    if position_error then
      local key = draft.floor_positioning == "exact" and "local_x_mm" or "floor_positioning"
      errors[key] = position_error
    end
    return errors
  end
  if owner and not wall.selected_part(owner, draft.part_id) then
    errors.part_id = "owner footprint part no longer exists"
  end
  local resolved = wall_draft(draft)
  local bounds = wall.bounds_error(resolved, context, 0, true)
  if bounds then
    if draft.wall_positioning == "exact" then
      errors.offset_mm = bounds
    else
      errors.wall_positioning = bounds
    end
  end
  local exterior = wall.exterior_error(resolved, context, 0)
  if exterior then errors.side = exterior end
  return errors
end

local function preview(draft, context)
  local owner = common.find(context, "room", draft.room_id)
  if not owner then return nil, { code = "ROOM_REQUIRED", message = "choose an owner room" } end
  local first
  if is_wall(draft) then
    local offset, err = wall.resolve_offset(wall_draft(draft), context, 0)
    if offset == nil then return nil, err end
    first = string.format(
      "%s wall of %s: offset %d mm",
      directions.label(draft.side, context),
      owner.name or owner.id,
      offset
    )
  else
    local position, err = floor_position(draft, context)
    if not position then return nil, err end
    first = string.format("Floor of %s at %s", owner.name or owner.id, common.point_text(position))
  end
  return {
    lines = {
      first,
      string.format("%s outlet · %d slot%s", draft.outlet_type, draft.slots, draft.slots == 1 and "" or "s"),
    },
  }
end

local function on_change(key, value, draft, _, context)
  if key == "room_id" then
    local owner = common.find(context, "room", value)
    local centre = room_centre(owner) or { 0, 0 }
    return { part_id = wall.first_part_id(owner), local_x_mm = centre[1], local_y_mm = centre[2] }
  elseif key == "placement" and value == "floor" and draft.floor_positioning == nil then
    return { floor_positioning = "centre" }
  end
end

local function placement_options(opts, existing)
  local requested = opts.outlet_placement
  if requested == nil and (opts.placement == "wall" or opts.placement == "floor") then requested = opts.placement end
  local placement = requested or existing or "wall"
  local legacy_position = opts.placement == "centre" or opts.placement == "cursor" or opts.placement == "exact"
  return placement,
    opts.wall_positioning or (legacy_position and opts.placement) or "centre",
    opts.floor_positioning or (legacy_position and opts.placement) or "centre"
end

function M.add(session, opts)
  opts = opts or {}
  local context = { session = session, cursor_mm = opts.cursor_mm }
  local room_id = opts.room_id or common.selected_room(context)
  local room = room_id and common.find(context, "room", room_id) or nil
  local centre = room_centre(room) or { 0, 0 }
  local placement, wall_positioning, floor_positioning = placement_options(opts)
  local spec = {
    id = "add-outlet",
    title = "Add outlet",
    mode = "OUTLET CREATE",
    description = "Wall outlets use an inward semicircle; floor outlets use a full circle.",
    apply_label = "Create outlet",
    context = context,
    initial = {
      room_id = room_id,
      placement = placement,
      part_id = opts.part_id or wall.first_part_id(room),
      side = opts.side or "north",
      outlet_type = opts.outlet_type or outlet_types.default,
      slots = opts.slots or 2,
      wall_positioning = wall_positioning,
      offset_mm = opts.offset_mm or 0,
      floor_positioning = floor_positioning,
      local_x_mm = opts.local_x_mm or centre[1],
      local_y_mm = opts.local_y_mm or centre[2],
    },
    fields = fields(false),
    on_change = on_change,
    preview = preview,
  }
  function spec.validate(draft, ctx) return validate(draft, ctx) end
  function spec.build(draft, ctx)
    ctx = ctx or context
    local owner = common.find(ctx, "room", draft.room_id)
    if not owner then return nil, { code = "ROOM_REQUIRED", message = "the owner room no longer exists" } end
    local id, id_err = common.generate_id(ctx, "outlet", (owner.name or owner.id) .. " " .. draft.outlet_type)
    if not id then return nil, id_err end
    local outlet = {
      id = id,
      room_id = draft.room_id,
      placement = is_wall(draft) and "wall" or "floor",
      outlet_type = draft.outlet_type,
      slots = draft.slots,
    }
    if is_wall(draft) then
      local offset, err = wall.resolve_offset(wall_draft(draft), ctx, 0)
      if offset == nil then return nil, err end
      outlet.part_id, outlet.side, outlet.offset_mm = draft.part_id, draft.side, offset
    else
      local position, err = floor_position(draft, ctx)
      if not position then return nil, err end
      outlet.position_mm = position
    end
    return { type = "add_outlet", outlet = model.new_outlet(outlet, { schema_version = schema_version(ctx) }) }
  end
  return spec
end

function M.edit(session, outlet, opts)
  opts = opts or {}
  if type(outlet) == "string" then outlet = model.find(session:model(), "outlet", outlet) end
  assert(type(outlet) == "table" and type(outlet.id) == "string", "outlet.edit requires an outlet")
  local context = { session = session, outlet_id = outlet.id, cursor_mm = opts.cursor_mm }
  local placement, wall_positioning, floor_positioning = placement_options(opts, outlet.placement or "wall")
  local position = outlet.position_mm or { 0, 0 }
  local spec = {
    id = "edit-outlet",
    title = "Edit outlet",
    mode = "OUTLET EDIT",
    description = "Location, type, slots and position are applied atomically.",
    apply_label = "Apply outlet changes",
    context = context,
    initial = {
      room_id = outlet.room_id,
      placement = placement,
      part_id = outlet.part_id or wall.first_part_id(common.find(context, "room", outlet.room_id)),
      side = outlet.side or "north",
      outlet_type = outlet.outlet_type,
      slots = outlet.slots,
      wall_positioning = opts.wall_positioning or (outlet.placement == "floor" and wall_positioning or "exact"),
      offset_mm = outlet.offset_mm or 0,
      floor_positioning = opts.floor_positioning or (outlet.placement == "floor" and "exact" or floor_positioning),
      local_x_mm = position[1],
      local_y_mm = position[2],
    },
    fields = fields(true),
    on_change = on_change,
    preview = preview,
  }
  function spec.validate(draft, ctx) return validate(draft, ctx, ctx.outlet_id) end
  function spec.build(draft, ctx)
    ctx = ctx or context
    if not common.find(ctx, "outlet", ctx.outlet_id) then
      return nil, { code = "NOT_FOUND", message = "the outlet no longer exists" }
    end
    local patch = {
      room_id = draft.room_id,
      placement = is_wall(draft) and "wall" or "floor",
      outlet_type = draft.outlet_type,
      slots = draft.slots,
    }
    if is_wall(draft) then
      local offset, err = wall.resolve_offset(wall_draft(draft), ctx, 0)
      if offset == nil then return nil, err end
      patch.part_id, patch.side, patch.offset_mm = draft.part_id, draft.side, offset
    else
      local position_value, err = floor_position(draft, ctx)
      if not position_value then return nil, err end
      patch.position_mm = position_value
    end
    return { type = "edit_outlet", id = ctx.outlet_id, exact = true, patch = patch }
  end
  return spec
end

M.new = M.add

return M
