local h = require("tests.harness")

local actions = require("roomplan.actions")
local forms = require("roomplan.ui.forms")
local geometry = require("roomplan.geometry")
local model = require("roomplan.model")

local function fixture()
  local plan = h.truthy(model.new({ name = "Placement tools" }))
  plan.rooms[1] = model.new_room({
    id = "room-main",
    name = "Main",
    origin_mm = { 0, 0 },
    size_mm = { 4000, 3000 },
  })
  plan.rooms[2] = model.new_room({
    id = "room-east",
    name = "East",
    origin_mm = { 4500, 0 },
    size_mm = { 2000, 3000 },
  })
  plan.furniture[1] = model.new_furniture({
    id = "furniture-desk",
    room_id = "room-main",
    template_id = "builtin:desk",
    name = "Desk",
    category = "work",
    position_mm = { 2000, 1500 },
    size_mm = { 1000, 500, 750 },
    rotation_deg = 0,
  })
  return plan
end

local function session(plan, selection)
  return {
    selection = selection,
    model = function() return plan end,
    current_model = function() return plan end,
  }
end

describe("measurement and wall placement", function()
  it("measures exact axis clearance and closest points", function()
    local plan = fixture()
    local missing, missing_error = geometry.measurement.between(plan, nil, nil)
    h.eq(nil, missing)
    h.eq("MEASUREMENT_REFERENCE", missing_error.code)
    local value = h.truthy(
      geometry.measurement.between(plan, { kind = "room", id = "room-main" }, { kind = "room", id = "room-east" })
    )
    h.eq(500, value.nearest_mm)
    h.eq(500, value.horizontal_gap_mm)
    h.eq(nil, value.vertical_gap_mm)
    h.eq({ 4000, 0 }, value.closest.from)
    h.eq({ 4500, 0 }, value.closest.to)

    local reversed = h.truthy(
      geometry.measurement.between(plan, { kind = "room", id = "room-east" }, { kind = "room", id = "room-main" })
    )
    h.eq(500, reversed.horizontal_gap_mm)
    h.eq({ 4500, 0 }, reversed.closest.from)
    h.eq({ 4000, 0 }, reversed.closest.to)
  end)

  it("builds a popup proposal against an exact exterior wall segment", function()
    local plan = fixture()
    local spec = forms.placement.new(session(plan, { kind = "furniture", id = "furniture-desk" }), plan.furniture[1])
    local west
    for _, wall in ipairs(spec.context.walls) do
      if wall.side == "west" then
        west = wall
        break
      end
    end
    local draft = { wall_id = h.truthy(west).id, alignment = "center", clearance_mm = 100 }
    local proposal = h.truthy(forms.placement.proposal(draft, spec.context))
    h.eq({ 600, 1500 }, proposal.position_mm)
    local action = h.truthy(spec.build(draft, spec.context))
    h.eq("move_furniture", action.type)
    h.eq(true, action.exact)
    local changed = h.truthy(actions.apply(plan, action))
    local shape = h.truthy(geometry.footprint.from_furniture(changed.rooms[1], changed.furniture[1]))
    h.eq(100, h.truthy(geometry.footprint.bounds(shape)).left)
  end)

  it("builds a live two-object measurement form", function()
    local plan = fixture()
    local spec = forms.measurement.new(session(plan, { kind = "room", id = "room-main" }))
    h.eq("measure-clearance", spec.id)
    local value = h.truthy(spec.result(spec.initial, spec.context))
    h.eq(500, value.nearest_mm)
  end)

  it("keeps the plan fine step inside the magnetic range at deep zoom", function()
    local plan = fixture()
    plan.settings.fine_step_mm = 10
    local fake = {
      snap_enabled = true,
      snap_exclusions = {},
      viewport = require("roomplan.render.viewport").new({ mm_per_column = 1, cell_aspect = 2 }),
      model = function() return plan end,
    }
    local options = require("roomplan.controller.common").snapping_options(fake)
    h.eq({ x = 10, y = 10 }, options.tolerance_mm)
  end)
end)
