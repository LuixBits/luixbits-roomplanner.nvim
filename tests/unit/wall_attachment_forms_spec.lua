local h = require("tests.harness")

local field_helpers = require("roomplan.ui.form.fields")
local form_state = require("roomplan.ui.form.state")
local json = require("roomplan.codec.json")
local model = require("roomplan.model")

local function fixture()
  local plan = h.truthy(model.new({ name = "Wall attachment forms" }))
  plan.rooms[1] = model.new_room({
    id = "room-living",
    name = "Living",
    origin_mm = { 0, 0 },
    footprint = {
      kind = "rect_union",
      parts = {
        { id = "part-main", origin_mm = { 0, 0 }, size_mm = { 5000, 2000 } },
        { id = "part-northwest", origin_mm = { 0, 2000 }, size_mm = { 2000, 2000 } },
      },
    },
  })
  plan.rooms[2] = model.new_room({
    id = "room-kitchen",
    name = "Kitchen",
    origin_mm = { 5000, 0 },
    size_mm = { 3000, 2000 },
  })
  local session = {
    selection = { kind = "room", id = "room-living" },
    reserved_ids = {},
  }
  function session:model() return plan end
  function session:current_model() return plan end
  return session, plan
end

local function field(spec, key)
  for _, candidate in ipairs(spec.fields) do
    if candidate.key == key then return candidate end
  end
end

describe("window and outlet forms", function()
  it("creates and edits a connected compound-room window", function()
    local session, plan = fixture()
    local forms = require("roomplan.ui.forms")
    local spec = forms.window.add(session, {
      room_id = "room-living",
      part_id = "part-main",
      side = "east",
      width_mm = 1000,
      placement = "centre",
      connects_to_room_id = "room-kitchen",
    })
    h.eq("WINDOW CREATE", spec.mode)
    local state = form_state.new(spec, spec.context)
    local parts = field_helpers.choices(field(spec, "part_id"), spec.context, state.draft, state)
    h.eq({ "part-main", "part-northwest" }, { parts[1].value, parts[2].value })
    local checked, valid = form_state.validate_all(state)
    h.truthy(valid, vim.inspect(checked.errors))

    local action = h.truthy(spec.build(checked.draft, spec.context))
    h.eq("add_window", action.type)
    h.eq("window-living-east", action.window.id)
    h.eq("room-kitchen", action.window.connects_to_room_id)
    h.eq("part-main", action.window.part_id)
    h.eq(500, action.window.offset_mm)
    h.eq(1000, action.window.width_mm)

    plan.windows[1] = action.window
    local edit = forms.window.edit(session, plan.windows[1], {
      placement = "cursor",
      cursor_mm = { 5000, 1000 },
    })
    local edit_state, edit_valid = form_state.validate_all(form_state.new(edit, edit.context))
    h.truthy(edit_valid, vim.inspect(edit_state.errors))
    local edit_action = h.truthy(edit.build(edit_state.draft, edit.context))
    h.eq("edit_window", edit_action.type)
    h.eq("window-living-east", edit_action.id)
    h.eq(500, edit_action.patch.offset_mm)
    h.eq(true, edit_action.exact)

    local outside = forms.window.add(session, {
      room_id = "room-living", part_id = "part-main", side = "south",
      width_mm = 1200, placement = "exact", offset_mm = 100,
    })
    local outside_action = h.truthy(outside.build(outside.initial, outside.context))
    h.truthy(json.is_null(outside_action.window.connects_to_room_id))
  end)

  it("creates and edits typed multi-slot outlets with cursor placement", function()
    local session, plan = fixture()
    local forms = require("roomplan.ui.forms")
    local spec = forms.outlet.add(session, {
      room_id = "room-living",
      part_id = "part-northwest",
      side = "north",
      outlet_type = "ethernet",
      slots = 4,
      placement = "cursor",
      cursor_mm = { 1000, 4000 },
    })
    h.eq("OUTLET CREATE", spec.mode)
    local state, valid = form_state.validate_all(form_state.new(spec, spec.context))
    h.truthy(valid, vim.inspect(state.errors))
    local action = h.truthy(spec.build(state.draft, spec.context))
    h.eq("add_outlet", action.type)
    h.eq("outlet-living-ethernet", action.outlet.id)
    h.eq("part-northwest", action.outlet.part_id)
    h.eq("ethernet", action.outlet.outlet_type)
    h.eq(4, action.outlet.slots)
    h.eq(1000, action.outlet.offset_mm)

    plan.outlets[1] = action.outlet
    local edit = forms.outlet.edit(session, plan.outlets[1])
    local edit_state = form_state.new(edit, edit.context)
    edit_state = form_state.reduce(edit_state, { type = "set_value", key = "outlet_type", value = "phone" })
    edit_state = form_state.reduce(edit_state, { type = "set_raw", key = "slots", value = "2" })
    local edit_action = h.truthy(edit.build(edit_state.draft, edit.context))
    h.eq("edit_outlet", edit_action.type)
    h.eq("phone", edit_action.patch.outlet_type)
    h.eq(2, edit_action.patch.slots)
    h.eq(true, edit_action.exact)
  end)

  it("keeps outlet choices canonical and rejects invalid slots and endpoints", function()
    local session = fixture()
    local outlet = require("roomplan.ui.forms.outlet")
    local values = {}
    for _, choice in ipairs(outlet.type_choices) do values[#values + 1] = choice.value end
    h.eq({ "power", "usb", "ethernet", "coax", "phone", "other" }, values)

    local spec = outlet.add(session, {
      room_id = "room-living", part_id = "part-main", side = "south",
      placement = "exact", offset_mm = 0,
    })
    local state = form_state.new(spec, spec.context)
    state = form_state.reduce(state, { type = "set_raw", key = "slots", value = "33" })
    local checked, valid = form_state.validate_all(state)
    h.falsy(valid)
    h.matches("at most", checked.errors.slots)
    h.truthy(checked.errors.offset_mm)

    local seam = outlet.add(session, {
      room_id = "room-living", part_id = "part-main", side = "north",
      placement = "exact", offset_mm = 1000,
    })
    local seam_state, seam_valid = form_state.validate_all(form_state.new(seam, seam.context))
    h.falsy(seam_valid)
    h.matches("internal footprint seam", seam_state.errors.side)
  end)

  it("creates, validates, and edits room-local floor outlets", function()
    local session, plan = fixture()
    local outlets = require("roomplan.ui.forms.outlet")
    local spec = outlets.add(session, {
      room_id = "room-living",
      placement = "floor",
      floor_positioning = "cursor",
      cursor_mm = { 1500, 1500 },
      outlet_type = "power",
      slots = 1,
    })
    local checked, valid = form_state.validate_all(form_state.new(spec, spec.context))
    h.truthy(valid, vim.inspect(checked.errors))
    local action = h.truthy(spec.build(checked.draft, spec.context))
    h.eq("floor", action.outlet.placement)
    h.eq({ 1500, 1500 }, action.outlet.position_mm)
    h.eq(nil, action.outlet.side)

    plan.outlets[1] = action.outlet
    local edit = outlets.edit(session, plan.outlets[1])
    local edit_state, edit_valid = form_state.validate_all(form_state.new(edit, edit.context))
    h.truthy(edit_valid, vim.inspect(edit_state.errors))
    local edit_action = h.truthy(edit.build(edit_state.draft, edit.context))
    h.eq("floor", edit_action.patch.placement)
    h.eq({ 1500, 1500 }, edit_action.patch.position_mm)

    local outside = outlets.add(session, {
      room_id = "room-living", placement = "floor", floor_positioning = "exact",
      local_x_mm = 7000, local_y_mm = 1000,
    })
    local outside_state, outside_valid = form_state.validate_all(form_state.new(outside, outside.context))
    h.falsy(outside_valid)
    h.matches("inside", outside_state.errors.local_x_mm)
  end)
end)
