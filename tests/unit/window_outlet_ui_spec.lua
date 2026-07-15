local h = require("tests.harness")

local json = require("roomplan.codec.json")
local model = require("roomplan.model")
local presenter = require("roomplan.ui.presenter")
local raster = require("roomplan.render.raster")
local scene_builder = require("roomplan.scene.build")
local viewport = require("roomplan.render.viewport")

local function plan_with_features()
  local plan = h.truthy(model.new({ name = "Wall features" }))
  plan.rooms[1] = model.new_room({
    id = "room-main",
    name = "Living",
    origin_mm = { 0, 0 },
    size_mm = { 4000, 3000 },
  })
  plan.windows[1] = model.new_window({
    id = "window-north",
    room_id = "room-main",
    connects_to_room_id = json.null,
    part_id = "part-main",
    side = "north",
    offset_mm = 1000,
    width_mm = 1200,
  })
  plan.outlets[1] = model.new_outlet({
    id = "outlet-east",
    room_id = "room-main",
    part_id = "part-main",
    side = "east",
    offset_mm = 1000,
    outlet_type = "power",
    slots = 2,
  })
  return plan
end

local function primitives(scene, kind)
  local result = {}
  for _, primitive in ipairs(scene.primitives or {}) do
    if primitive.kind == kind then result[#result + 1] = primitive end
  end
  return result
end

describe("window and outlet presentation", function()
  it("extracts visible selectable primitives with detail-aware annotations", function()
    local plan = plan_with_features()
    local high = scene_builder.build(plan, {}, { detail_level = "high" })
    h.eq(1, #primitives(high, "window_aperture"))
    h.eq("window", primitives(high, "window_aperture")[1].ref.type)
    h.eq(1, #primitives(high, "outlet_marker"))
    h.eq("outlet", primitives(high, "outlet_marker")[1].ref.type)

    local outlet_labels, window_dimensions = 0, 0
    for _, primitive in ipairs(high.primitives) do
      if primitive.kind == "label" and primitive.ref and primitive.ref.type == "outlet" then
        outlet_labels = outlet_labels + 1
        h.eq("Power · 2 slots", primitive.text)
      elseif primitive.kind == "dimension" and primitive.ref and primitive.ref.type == "window" then
        window_dimensions = window_dimensions + 1
        h.eq("1.2m", primitive.text)
      end
    end
    h.eq(1, outlet_labels)
    h.eq(1, window_dimensions)

    local none = scene_builder.build(plan, {}, { detail_level = "none" })
    h.eq(1, #primitives(none, "window_aperture"))
    h.eq(1, #primitives(none, "outlet_marker"))
    for _, primitive in ipairs(none.primitives) do
      h.falsy(primitive.ref and (primitive.ref.type == "window" or primitive.ref.type == "outlet")
        and (primitive.kind == "label" or primitive.kind == "dimension"))
    end
  end)

  it("rasterizes distinct glyphs and typed hit targets", function()
    local scene = scene_builder.build(plan_with_features(), {}, { detail_level = "none" })
    local view = viewport.new({
      world_left_mm = 0,
      world_top_mm = 3000,
      mm_per_column = 200,
      mm_per_row = 200,
    })
    local output = raster.rasterize(scene, view, {
      width = 21,
      height = 16,
      glyph_mode = "ascii",
      width_fn = function(value) return #value end,
    })
    h.eq("=", output.cells[1][7].char)
    h.eq("window", output.hit_map[1][7][1].type)
    h.eq("O", output.cells[11][21].char)
    h.eq("outlet", output.hit_map[11][21][1].type)
  end)

  it("lists and describes both feature kinds in the workspace", function()
    local plan = plan_with_features()
    local objects = presenter.objects(plan)
    h.eq(1, objects.counts.windows)
    h.eq(1, objects.counts.outlets)
    h.matches("1 windows", objects.summary)
    h.eq("window", objects.rows[3].kind)
    h.eq("outlet", objects.rows[4].kind)

    local window = presenter.properties(plan, { selection = { kind = "window", id = "window-north" } })
    h.eq("window", window.kind)
    h.eq("Window", window.title)
    local outlet = presenter.properties(plan, { selection = { kind = "outlet", id = "outlet-east" } })
    h.eq("outlet", outlet.kind)
    h.eq("Power outlet", outlet.title)
  end)
end)
