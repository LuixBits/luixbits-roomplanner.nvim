local measurement = require("roomplan.geometry.measurement")
local model_helpers = require("roomplan.model")
local common = require("roomplan.ui.forms.common")

local M = {}
local separator = "\31"

local function encode(kind, id) return tostring(kind) .. separator .. tostring(id) end

local function decode(value)
  local kind, id = tostring(value or ""):match("^([^" .. separator .. "]+)" .. separator .. "(.+)$")
  return kind and { kind = kind, id = id } or nil
end

local function choices(context)
  local plan = common.model(context)
  local rooms = {}
  for _, room in ipairs(plan and plan.rooms or {}) do
    rooms[room.id] = room
  end
  local result = {}
  for _, room in ipairs(plan and plan.rooms or {}) do
    result[#result + 1] = {
      value = encode("room", room.id),
      label = string.format("Room · %s", room.name or room.id),
    }
  end
  for _, furniture in ipairs(plan and plan.furniture or {}) do
    local owner = rooms[furniture.room_id]
    result[#result + 1] = {
      value = encode("furniture", furniture.id),
      label = string.format(
        "Furniture · %s · %s",
        owner and (owner.name or owner.id) or furniture.room_id,
        furniture.name or furniture.id
      ),
    }
  end
  return result
end

local function result(draft, context)
  local left, right = decode(draft.from_ref), decode(draft.to_ref)
  if not left or not right then return nil, { code = "MEASUREMENT_REFERENCE", message = "choose two objects" } end
  return measurement.between(common.model(context), left, right)
end

local function point(value)
  return value and string.format("(%s, %s) mm", tostring(value[1]), tostring(value[2])) or "unavailable"
end

function M.new(session)
  local context = { session = session }
  local available = choices(context)
  local selection = session.selection
  local selected_value = selection
      and (selection.kind == "room" or selection.kind == "furniture")
      and model_helpers.find(session:model(), selection.kind, selection.id)
      and encode(selection.kind, selection.id)
    or nil
  local from_ref = selected_value or (available[1] and available[1].value)
  local to_ref
  for _, choice in ipairs(available) do
    if choice.value ~= from_ref then
      to_ref = choice.value
      break
    end
  end
  local spec = {
    id = "measure-clearance",
    title = "Measure exact clearance",
    mode = "MEASURE",
    description = "Choose any two rooms or furniture items. Values update inside this popup.",
    apply_label = "Close",
    preview_title = "Closest path",
    context = context,
    initial = { from_ref = from_ref, to_ref = to_ref },
    fields = {
      { key = "from_ref", label = "From", type = "object_ref", required = true, choices = choices },
      { key = "to_ref", label = "To", type = "object_ref", required = true, choices = choices },
      {
        key = "nearest",
        label = "Nearest clearance",
        type = "readonly",
        value = function(ctx, draft)
          local value = result(draft, ctx)
          return value and measurement.format_mm(value.nearest_mm) or "unavailable"
        end,
      },
      {
        key = "horizontal",
        label = "Horizontal gap",
        type = "readonly",
        value = function(ctx, draft)
          local value = result(draft, ctx)
          return value and measurement.format_mm(value.horizontal_gap_mm) or "unavailable"
        end,
      },
      {
        key = "vertical",
        label = "Vertical gap",
        type = "readonly",
        value = function(ctx, draft)
          local value = result(draft, ctx)
          return value and measurement.format_mm(value.vertical_gap_mm) or "unavailable"
        end,
      },
      {
        key = "centres",
        label = "Centre offset",
        type = "readonly",
        value = function(ctx, draft)
          local value = result(draft, ctx)
          return value
              and string.format(
                "x %s · y %s",
                measurement.format_mm(value.center_delta_mm[1]),
                measurement.format_mm(value.center_delta_mm[2])
              )
            or "unavailable"
        end,
      },
    },
    on_change = function(key, value, _, draft, ctx)
      if (key == "from_ref" and value == draft.to_ref) or (key == "to_ref" and value == draft.from_ref) then
        for _, choice in ipairs(choices(ctx)) do
          if choice.value ~= value then return { [key == "from_ref" and "to_ref" or "from_ref"] = choice.value } end
        end
      end
    end,
    preview = function(draft, ctx)
      local value, err = result(draft, ctx)
      if not value then return nil, err end
      return {
        lines = {
          string.format("%s → %s", point(value.closest.from), point(value.closest.to)),
          "Nearest clearance: " .. measurement.format_mm(value.nearest_mm),
        },
      }
    end,
  }
  function spec.validate(draft)
    if draft.from_ref == draft.to_ref then return { to_ref = "must differ from the first object" } end
    return {}
  end
  spec.result = result
  return spec
end

M.encode = encode
M.decode = decode
M.choices = choices
M.result = result

return M
