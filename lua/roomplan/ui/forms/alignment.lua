local alignment = require("roomplan.geometry.alignment")
local common = require("roomplan.ui.forms.common")
local directions = require("roomplan.directions")

local M = {}

local function operations(context)
  local result = {
    { value = "align_left", label = "Align " .. directions.label("west", context):lower() .. " edges" },
    { value = "align_right", label = "Align " .. directions.label("east", context):lower() .. " edges" },
    { value = "align_top", label = "Align " .. directions.label("north", context):lower() .. " edges" },
    { value = "align_bottom", label = "Align " .. directions.label("south", context):lower() .. " edges" },
    { value = "align_center_x", label = "Align horizontal centres" },
    { value = "align_center_y", label = "Align vertical centres" },
    { value = "snap_corner", label = "Snap corners" },
  }
  for _, choice in ipairs(directions.choices(context)) do
    result[#result + 1] = { value = "place_" .. choice.value, label = "Place " .. choice.label:lower() }
  end
  return result
end

local function corners(context)
  local result = {}
  for _, value in ipairs({ "southwest", "southeast", "northwest", "northeast" }) do
    result[#result + 1] = { value = value, label = directions.corner_label(value, context) }
  end
  return result
end

local function is_place(operation) return type(operation) == "string" and operation:sub(1, 6) == "place_" end

local function proposal(draft, context)
  local moving = common.find(context, "room", draft.moving_room_id)
  local reference = common.find(context, "room", draft.reference_room_id)
  if not moving then return nil, { code = "MOVING_ROOM_REQUIRED", message = "choose a moving room" } end
  if not reference then return nil, { code = "REFERENCE_ROOM_REQUIRED", message = "choose a reference room" } end
  if moving.id == reference.id then
    return nil, { code = "ALIGNMENT_SAME_ROOM", message = "moving and reference rooms must differ" }
  end
  return alignment.propose(moving, reference, draft.operation, {
    gap_mm = is_place(draft.operation) and (draft.gap_mm or 0) or 0,
    moving_corner = draft.moving_corner,
    reference_corner = draft.reference_corner,
  })
end

function M.new(session, opts)
  opts = opts or {}
  local context = { session = session }
  local moving_id = opts.moving_room_id or common.selected_room(context)
  local reference_id = opts.reference_room_id
  if not reference_id then
    local alternatives = common.rooms(context, moving_id)
    reference_id = alternatives[1] and alternatives[1].value or nil
  end
  local spec = {
    id = "align-room",
    title = "Align rooms",
    mode = "ROOM ALIGN",
    description = "The reference room remains fixed; applying creates one undo entry.",
    apply_label = "Align room",
    context = context,
    initial = {
      moving_room_id = moving_id,
      reference_room_id = reference_id,
      operation = opts.operation or "place_east",
      gap_mm = opts.gap_mm or 0,
      moving_corner = opts.moving_corner or "southwest",
      reference_corner = opts.reference_corner or "southwest",
      force = opts.force == true,
    },
    fields = {
      {
        key = "moving_room_id",
        label = "Moving room",
        type = "object_ref",
        required = true,
        choices = function(ctx) return common.rooms(ctx) end,
      },
      {
        key = "reference_room_id",
        label = "Reference room",
        type = "object_ref",
        required = true,
        choices = function(ctx, draft) return common.rooms(ctx, draft.moving_room_id) end,
      },
      { key = "operation", label = "Operation", type = "enum", required = true, choices = operations },
      {
        key = "gap_mm",
        label = "Gap",
        type = "measurement",
        allow_zero = true,
        visible = function(_, draft) return is_place(draft.operation) end,
      },
      {
        key = "moving_corner",
        label = "Moving corner",
        type = "enum",
        choices = corners,
        visible = function(_, draft) return draft.operation == "snap_corner" end,
      },
      {
        key = "reference_corner",
        label = "Reference corner",
        type = "enum",
        choices = corners,
        visible = function(_, draft) return draft.operation == "snap_corner" end,
      },
      { key = "force", label = "Allow invalid draft", type = "toggle", default = false },
      {
        key = "resolved_origin",
        label = "Resulting origin",
        type = "readonly",
        value = function(ctx, draft)
          local result = proposal(draft, ctx)
          return result and result.origin_mm or nil
        end,
        format = function(value) return common.point_text(value) end,
      },
    },
    on_change = function(key, value, _, draft, ctx)
      if key == "moving_room_id" and value == draft.reference_room_id then
        local alternatives = common.rooms(ctx, value)
        return { reference_room_id = alternatives[1] and alternatives[1].value or draft.reference_room_id }
      end
    end,
    preview = function(draft, ctx)
      local result, err = proposal(draft, ctx)
      if not result then return nil, err end
      local moving = common.find(ctx, "room", draft.moving_room_id)
      local reference = common.find(ctx, "room", draft.reference_room_id)
      local rounding = result.rounded and " (rounded to integer millimetres)" or ""
      return {
        lines = {
          string.format(
            "%s relative to %s -> %s%s",
            moving.name or moving.id,
            reference.name or reference.id,
            common.point_text(result.origin_mm),
            rounding
          ),
        },
      }
    end,
  }
  function spec.validate(draft, ctx)
    if draft.moving_room_id == draft.reference_room_id then
      return { reference_room_id = "must differ from the moving room" }
    end
    return {}
  end
  function spec.build(draft, ctx)
    ctx = ctx or context
    local result, err = proposal(draft, ctx)
    if not result then return nil, err end
    return {
      type = "align_room",
      id = draft.moving_room_id,
      reference_room_id = draft.reference_room_id,
      operation = draft.operation,
      gap_mm = is_place(draft.operation) and (draft.gap_mm or 0) or 0,
      moving_corner = draft.moving_corner,
      reference_corner = draft.reference_corner,
      force = draft.force == true,
    }
  end
  return spec
end

M.align = M.new
M.proposal = proposal

return M
