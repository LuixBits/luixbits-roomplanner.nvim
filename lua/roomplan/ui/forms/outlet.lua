local model = require("roomplan.model")
local outlet_types = require("roomplan.outlet_types")
local common = require("roomplan.ui.forms.common")
local wall = require("roomplan.ui.forms.wall_attachment")

local M = {}

local type_labels = {
  power = "Power", usb = "USB", ethernet = "Ethernet",
  coax = "TV / coax", phone = "Phone", other = "Other",
}

M.type_choices = {}
for _, value in ipairs(outlet_types.values) do
  M.type_choices[#M.type_choices + 1] = { value = value, label = type_labels[value] or value }
end

local function schema_version(context)
  local plan = common.model(context)
  return plan and plan.schema_version or 3
end

local function fields(editing)
  local result = {
    { key = "room_id", label = "Owner room", type = "object_ref", required = true,
      choices = function(ctx) return common.rooms(ctx) end },
    { key = "part_id", label = "Footprint part", type = "object_ref", required = true,
      choices = wall.part_choices },
    { key = "side", label = "Wall", type = "enum", required = true, choices = wall.side_choices },
    { key = "outlet_type", label = "Type", type = "enum", required = true, choices = M.type_choices },
    { key = "slots", label = "Slots", type = "integer", required = true, min = 1, max = 32 },
    { key = "placement", label = "Placement", type = "enum", required = true, choices = {
      { value = "centre", label = "Wall centre" },
      { value = "cursor", label = "At canvas cursor" },
      { value = "exact", label = "Exact offset" },
    } },
    { key = "offset_mm", label = "Offset", type = "measurement", allow_zero = true,
      visible = function(_, draft) return draft.placement == "exact" end },
    { key = "resolved_offset", label = "Resolved offset", type = "readonly",
      value = function(ctx, draft) return wall.resolve_offset(draft, ctx, 0) end,
      format = function(value) return value and (tostring(value) .. " mm") or "unavailable" end },
  }
  if editing then
    result[#result + 1] = {
      key = "summary", label = "Result", type = "readonly",
      value = function(_, draft)
        return string.format("%s wall, %s outlet, %d slot%s", draft.side, draft.outlet_type,
          draft.slots, draft.slots == 1 and "" or "s")
      end,
    }
  end
  return result
end

local function validate(draft, context, id)
  local errors = {}
  if id and not common.find(context, "outlet", id) then errors._form = "the outlet no longer exists" end
  local owner = wall.owner(draft, context)
  if not owner then errors.room_id = "owner room no longer exists" end
  if owner and not wall.selected_part(owner, draft.part_id) then
    errors.part_id = "owner footprint part no longer exists"
  end
  local bounds = wall.bounds_error(draft, context, 0, true)
  if bounds then
    if draft.placement == "exact" then errors.offset_mm = bounds else errors.placement = bounds end
  end
  local exterior = wall.exterior_error(draft, context, 0)
  if exterior then errors.side = exterior end
  return errors
end

local function preview(draft, context)
  local offset, err = wall.resolve_offset(draft, context, 0)
  if offset == nil then return nil, err end
  local owner = wall.owner(draft, context)
  if not owner then return nil, { code = "ROOM_REQUIRED", message = "choose an owner room" } end
  return { lines = {
    string.format("%s wall of %s: offset %d mm", draft.side, owner.name or owner.id, offset),
    string.format("%s outlet · %d slot%s", draft.outlet_type, draft.slots, draft.slots == 1 and "" or "s"),
  } }
end

local function on_change(key, value, _, _, context)
  if key == "room_id" then
    return { part_id = wall.first_part_id(common.find(context, "room", value)) }
  end
end

function M.add(session, opts)
  opts = opts or {}
  local context = { session = session, cursor_mm = opts.cursor_mm }
  local room_id = opts.room_id or common.selected_room(context)
  local room = room_id and common.find(context, "room", room_id) or nil
  local spec = {
    id = "add-outlet",
    title = "Add outlet",
    mode = "OUTLET CREATE",
    description = "Offset is measured from the wall's canonical start.",
    apply_label = "Create outlet",
    context = context,
    initial = {
      room_id = room_id,
      part_id = opts.part_id or wall.first_part_id(room),
      side = opts.side or "north",
      outlet_type = opts.outlet_type or outlet_types.default,
      slots = opts.slots or 2,
      placement = opts.placement or "centre",
      offset_mm = opts.offset_mm or 0,
    },
    fields = fields(false),
    on_change = on_change,
    preview = preview,
  }
  function spec.validate(draft, ctx) return validate(draft, ctx) end
  function spec.build(draft, ctx)
    ctx = ctx or context
    local offset, err = wall.resolve_offset(draft, ctx, 0)
    if offset == nil then return nil, err end
    local owner = wall.owner(draft, ctx)
    if not owner then return nil, { code = "ROOM_REQUIRED", message = "the owner room no longer exists" } end
    local id, id_err = common.generate_id(ctx, "outlet", (owner.name or owner.id) .. " " .. draft.outlet_type)
    if not id then return nil, id_err end
    return {
      type = "add_outlet",
      outlet = model.new_outlet({
        id = id,
        room_id = draft.room_id,
        part_id = draft.part_id,
        side = draft.side,
        offset_mm = offset,
        outlet_type = draft.outlet_type,
        slots = draft.slots,
      }, { schema_version = schema_version(ctx) }),
    }
  end
  return spec
end

function M.edit(session, outlet, opts)
  opts = opts or {}
  if type(outlet) == "string" then outlet = model.find(session:model(), "outlet", outlet) end
  assert(type(outlet) == "table" and type(outlet.id) == "string", "outlet.edit requires an outlet")
  local context = { session = session, outlet_id = outlet.id, cursor_mm = opts.cursor_mm }
  local spec = {
    id = "edit-outlet",
    title = "Edit outlet",
    mode = "OUTLET EDIT",
    description = "Every outlet property is applied atomically.",
    apply_label = "Apply outlet changes",
    context = context,
    initial = {
      room_id = outlet.room_id,
      part_id = outlet.part_id,
      side = outlet.side,
      outlet_type = outlet.outlet_type,
      slots = outlet.slots,
      placement = opts.placement or "exact",
      offset_mm = outlet.offset_mm,
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
    local offset, err = wall.resolve_offset(draft, ctx, 0)
    if offset == nil then return nil, err end
    return {
      type = "edit_outlet",
      id = ctx.outlet_id,
      exact = true,
      patch = {
        room_id = draft.room_id,
        part_id = draft.part_id,
        side = draft.side,
        offset_mm = offset,
        outlet_type = draft.outlet_type,
        slots = draft.slots,
      },
    }
  end
  return spec
end

M.new = M.add

return M
