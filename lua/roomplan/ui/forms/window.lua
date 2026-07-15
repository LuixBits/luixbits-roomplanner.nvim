local json = require("roomplan.codec.json")
local config = require("roomplan.config")
local model = require("roomplan.model")
local common = require("roomplan.ui.forms.common")
local wall = require("roomplan.ui.forms.wall_attachment")

local M = {}

local DEFAULT_WIDTH_MM = 1200

local function schema_version(context)
  local plan = common.model(context)
  return plan and plan.schema_version or 3
end

local function connection_value(value)
  return value == "outside" and json.null or value
end

local function initial_connection(value)
  if value == nil or json.is_null(value) then return "outside" end
  return value
end

local function fields(runtime, editing)
  local result = {
    { key = "room_id", label = "Owner room", type = "object_ref", required = true,
      choices = function(ctx) return common.rooms(ctx) end },
    { key = "part_id", label = "Footprint part", type = "object_ref", required = true,
      choices = wall.part_choices },
    { key = "side", label = "Wall", type = "enum", required = true, choices = wall.side_choices },
    { key = "width_mm", label = "Width", type = "measurement", required = true,
      max = function(ctx, draft) return wall.edge_length(draft, ctx) or runtime.limits.max_dimension_mm end },
    { key = "placement", label = "Placement", type = "enum", required = true, choices = {
      { value = "centre", label = "Centred on wall" },
      { value = "cursor", label = "Centred at canvas cursor" },
      { value = "exact", label = "Exact offset" },
    } },
    { key = "offset_mm", label = "Offset", type = "measurement", allow_zero = true,
      visible = function(_, draft) return draft.placement == "exact" end },
    { key = "resolved_offset", label = "Resolved offset", type = "readonly",
      value = function(ctx, draft) return wall.resolve_offset(draft, ctx, draft.width_mm) end,
      format = function(value) return value and (tostring(value) .. " mm") or "unavailable" end },
    { key = "connects_to_room_id", label = "Connects to", type = "object_ref", required = true,
      choices = wall.connection_choices },
  }
  if editing then
    result[#result + 1] = {
      key = "summary", label = "Result", type = "readonly",
      value = function(_, draft)
        return string.format("%s wall, %d mm wide", draft.side, draft.width_mm)
      end,
    }
  end
  return result
end

local function validate(draft, context, id)
  local errors = {}
  if id and not common.find(context, "window", id) then errors._form = "the window no longer exists" end
  local owner = wall.owner(draft, context)
  if not owner then errors.room_id = "owner room no longer exists" end
  if owner and not wall.selected_part(owner, draft.part_id) then
    errors.part_id = "owner footprint part no longer exists"
  end
  local bounds = wall.bounds_error(draft, context, draft.width_mm)
  if bounds then
    if draft.placement == "exact" then errors.offset_mm = bounds else errors.placement = bounds end
  end
  local exterior = wall.exterior_error(draft, context, draft.width_mm)
  if exterior then errors.side = exterior end
  if not wall.connection_available(draft, context, draft.width_mm) then
    errors.connects_to_room_id = "connected room does not cover the complete opening"
  end
  return errors
end

local function preview(draft, context)
  local offset, err = wall.resolve_offset(draft, context, draft.width_mm)
  if offset == nil then return nil, err end
  local owner = wall.owner(draft, context)
  if not owner then return nil, { code = "ROOM_REQUIRED", message = "choose an owner room" } end
  local destination = draft.connects_to_room_id == "outside" and "outside"
    or ((common.find(context, "room", draft.connects_to_room_id) or {}).name or draft.connects_to_room_id)
  return { lines = {
    string.format("%s wall of %s: offset %d mm, width %d mm", draft.side, owner.name or owner.id,
      offset, draft.width_mm),
    "Connects to " .. tostring(destination),
  } }
end

local function on_change(key, value, _, _, context)
  if key == "room_id" then
    return {
      part_id = wall.first_part_id(common.find(context, "room", value)),
      connects_to_room_id = "outside",
    }
  end
end

function M.add(session, opts)
  opts = opts or {}
  local runtime = config.get()
  local context = { session = session, cursor_mm = opts.cursor_mm }
  local room_id = opts.room_id or common.selected_room(context)
  local room = room_id and common.find(context, "room", room_id) or nil
  local spec = {
    id = "add-window",
    title = "Add window",
    mode = "WINDOW CREATE",
    description = "Offset is measured from the wall's canonical start.",
    apply_label = "Create window",
    context = context,
    initial = {
      room_id = room_id,
      part_id = opts.part_id or wall.first_part_id(room),
      side = opts.side or "north",
      width_mm = opts.width_mm or DEFAULT_WIDTH_MM,
      placement = opts.placement or "centre",
      offset_mm = opts.offset_mm or 0,
      connects_to_room_id = initial_connection(opts.connects_to_room_id),
    },
    fields = fields(runtime, false),
    on_change = on_change,
    preview = preview,
  }
  function spec.validate(draft, ctx) return validate(draft, ctx) end
  function spec.build(draft, ctx)
    ctx = ctx or context
    local offset, err = wall.resolve_offset(draft, ctx, draft.width_mm)
    if offset == nil then return nil, err end
    local owner = wall.owner(draft, ctx)
    if not owner then return nil, { code = "ROOM_REQUIRED", message = "the owner room no longer exists" } end
    local id, id_err = common.generate_id(ctx, "window", (owner.name or owner.id) .. " " .. draft.side)
    if not id then return nil, id_err end
    return {
      type = "add_window",
      window = model.new_window({
        id = id,
        room_id = draft.room_id,
        connects_to_room_id = connection_value(draft.connects_to_room_id),
        part_id = draft.part_id,
        side = draft.side,
        offset_mm = offset,
        width_mm = draft.width_mm,
      }, { schema_version = schema_version(ctx) }),
    }
  end
  return spec
end

function M.edit(session, window, opts)
  opts = opts or {}
  if type(window) == "string" then window = model.find(session:model(), "window", window) end
  assert(type(window) == "table" and type(window.id) == "string", "window.edit requires a window")
  local runtime = config.get()
  local context = { session = session, window_id = window.id, cursor_mm = opts.cursor_mm }
  local spec = {
    id = "edit-window",
    title = "Edit window",
    mode = "WINDOW EDIT",
    description = "Every window property is applied atomically.",
    apply_label = "Apply window changes",
    context = context,
    initial = {
      room_id = window.room_id,
      part_id = window.part_id,
      side = window.side,
      width_mm = window.width_mm,
      placement = opts.placement or "exact",
      offset_mm = window.offset_mm,
      connects_to_room_id = initial_connection(window.connects_to_room_id),
    },
    fields = fields(runtime, true),
    on_change = on_change,
    preview = preview,
  }
  function spec.validate(draft, ctx) return validate(draft, ctx, ctx.window_id) end
  function spec.build(draft, ctx)
    ctx = ctx or context
    if not common.find(ctx, "window", ctx.window_id) then
      return nil, { code = "NOT_FOUND", message = "the window no longer exists" }
    end
    local offset, err = wall.resolve_offset(draft, ctx, draft.width_mm)
    if offset == nil then return nil, err end
    return {
      type = "edit_window",
      id = ctx.window_id,
      exact = true,
      patch = {
        room_id = draft.room_id,
        connects_to_room_id = connection_value(draft.connects_to_room_id),
        part_id = draft.part_id,
        side = draft.side,
        offset_mm = offset,
        width_mm = draft.width_mm,
      },
    }
  end
  return spec
end

M.new = M.add

return M
