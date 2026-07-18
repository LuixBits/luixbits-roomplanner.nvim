local distribution = require("roomplan.geometry.distribution")
local common = require("roomplan.ui.forms.common")

local M = {}

local AXES = {
  { value = "horizontal", label = "Horizontal (west to east)" },
  { value = "vertical", label = "Vertical (south to north)" },
}

local function half_mm(value2)
  local whole = math.floor(value2 / 2)
  return value2 % 2 == 0 and string.format("%d mm", whole) or string.format("%d.5 mm", whole)
end

local function proposal(draft, context)
  return distribution.propose(common.model(context), context.room_id, draft.axis, {
    selected_id = context.furniture_id,
  })
end

local function gap_text(result)
  if not result then return "unavailable" end
  if result.exact then return half_mm(result.minimum_gap2) end
  return string.format("%s–%s (balanced)", half_mm(result.minimum_gap2), half_mm(result.maximum_gap2))
end

local function anchor_text(result)
  if not result then return "unavailable" end
  local first, last = result.items[1], result.items[#result.items]
  return string.format("%s and %s stay fixed", first.name, last.name)
end

function M.new(session, opts)
  opts = opts or {}
  local furniture = common.find({ session = session }, "furniture", opts.furniture_id)
  local context = {
    session = session,
    furniture_id = furniture and furniture.id or opts.furniture_id,
    room_id = furniture and furniture.room_id or opts.room_id,
  }
  local spec = {
    id = "distribute-furniture",
    title = "Equal furniture spacing",
    mode = "FURNITURE DISTRIBUTE",
    description = "Uses every furniture item in this room. The outer two stay fixed; apply is one undo entry.",
    apply_label = "Distribute furniture",
    context = context,
    initial = { axis = opts.axis or "horizontal" },
    fields = {
      {
        key = "room", label = "Room", type = "readonly",
        value = function(ctx)
          local room = common.find(ctx, "room", ctx.room_id)
          return room and (room.name or room.id) or "unavailable"
        end,
      },
      { key = "axis", label = "Direction", type = "enum", required = true, choices = AXES },
      {
        key = "items", label = "Furniture", type = "readonly",
        value = function(ctx, draft)
          local result = proposal(draft, ctx)
          return result and string.format("%d items", #result.items) or "unavailable"
        end,
      },
      {
        key = "anchors", label = "Fixed anchors", type = "readonly",
        value = function(ctx, draft) return anchor_text(proposal(draft, ctx)) end,
      },
      {
        key = "gap", label = "Resulting gaps", type = "readonly",
        value = function(ctx, draft) return gap_text(proposal(draft, ctx)) end,
      },
    },
    preview = function(draft, ctx)
      local result, err = proposal(draft, ctx)
      if not result then return nil, err end
      local lines = {
        string.format("%s · %s", anchor_text(result), gap_text(result)),
      }
      local shown = 0
      for _, item in ipairs(result.items) do
        if item.delta_mm ~= 0 and shown < 5 then
          lines[#lines + 1] = string.format("%s: %+d mm", item.name, item.delta_mm)
          shown = shown + 1
        end
      end
      if result.changed_count > shown then
        lines[#lines + 1] = string.format("…and %d more move%s", result.changed_count - shown,
          result.changed_count - shown == 1 and "" or "s")
      elseif result.changed_count == 0 then
        lines[#lines + 1] = "Already equally spaced in this direction"
      end
      return { lines = lines }
    end,
  }

  function spec.validate(draft, ctx)
    ctx = ctx or context
    local result, err = proposal(draft, ctx)
    if not result then
      return { [err and err.code == "DISTRIBUTION_AXIS" and "axis" or "_form"] = common.error_message(err) }
    end
    if result.changed_count == 0 then return { _form = "furniture is already equally spaced in this direction" } end
    return {}
  end

  function spec.build(draft, ctx)
    ctx = ctx or context
    local result, err = proposal(draft, ctx)
    if not result then return nil, err end
    return {
      type = "distribute_furniture",
      room_id = ctx.room_id,
      selected_id = ctx.furniture_id,
      axis = draft.axis,
    }
  end

  return spec
end

M.proposal = proposal

return M
