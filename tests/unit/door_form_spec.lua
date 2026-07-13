local h = require("tests.harness")

local form_state = require("roomplan.ui.form.state")
local model = require("roomplan.model")

local function fixture()
  local plan = h.truthy(model.new({ name = "Door copy form" }))
  plan.rooms[1] = model.new_room({
    id = "room-living",
    name = "Living",
    origin_mm = { 0, 0 },
    size_mm = { 5000, 4000 },
  })
  plan.doors[1] = model.new_door({
    id = "door-living-east",
    room_id = "room-living",
    side = "east",
    offset_mm = 1000,
    width_mm = 900,
    hinge = "start",
    opens_into = "owner",
  })
  local session = { reserved_ids = {} }
  function session:model() return plan end
  function session:current_model() return plan end
  return session, plan
end

describe("door duplicate form", function()
  it("builds one atomic duplicate action and validates wall bounds", function()
    local session, plan = fixture()
    local spec = require("roomplan.ui.forms.door").duplicate(session, plan.doors[1])
    h.eq("DOOR DUPLICATE", spec.mode)

    local state, valid = form_state.validate_all(form_state.new(spec, spec.context))
    h.truthy(valid, vim.inspect(state.errors))
    state = form_state.reduce(state, { type = "set_raw", key = "offset_mm", value = "2m" })
    state = form_state.reduce(state, { type = "set_value", key = "hinge", value = "end" })
    local action = h.truthy(spec.build(state.draft, spec.context))
    h.eq("duplicate_door_from_draft", action.type)
    h.eq("door-living-east", action.id)
    h.eq("end", action.patch.hinge)
    h.eq(2000, action.patch.offset_mm)

    state = form_state.reduce(state, { type = "set_raw", key = "offset_mm", value = "3.2m" })
    local invalid, invalid_ok = form_state.validate_all(state)
    h.falsy(invalid_ok)
    h.truthy(invalid.errors.offset_mm)
  end)
end)
