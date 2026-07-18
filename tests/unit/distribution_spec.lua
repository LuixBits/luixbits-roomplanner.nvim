local h = require("tests.harness")

local actions = require("roomplan.actions")
local distribution = require("roomplan.geometry.distribution")
local model = require("roomplan.model")
local room_footprints = require("roomplan.model.room_footprints")

local function plan()
  local value = h.truthy(model.new({ name = "Distribution" }))
  value.rooms[1] = model.new_room({
    id = "room-main", name = "Main", origin_mm = { 0, 0 }, size_mm = { 12000, 8000 },
  })
  return value
end

local function add(value, id, position, size, options)
  options = options or {}
  value.furniture[#value.furniture + 1] = model.new_furniture({
    id = id,
    room_id = options.room_id or "room-main",
    template_id = "builtin:custom-rectangle",
    name = options.name or id,
    category = "custom",
    position_mm = position,
    size_mm = size,
    rotation_deg = options.rotation_deg or 0,
    footprint = options.footprint,
    anchor2_mm = options.anchor2_mm,
    height_mm = size[3],
  })
  return value.furniture[#value.furniture]
end

local function by_id(result, id)
  for _, item in ipairs(result.items) do
    if item.id == id then return item end
  end
end

describe("furniture equal spacing", function()
  it("keeps the outer furniture fixed and computes exact horizontal gaps", function()
    local value = plan()
    add(value, "left", { 1000, 1000 }, { 1000, 600, 700 })
    add(value, "middle", { 3000, 1000 }, { 1000, 600, 700 })
    add(value, "right", { 8000, 1000 }, { 1000, 600, 700 })

    local result = h.truthy(distribution.propose(value, "room-main", "horizontal", {
      selected_id = "middle",
    }))
    h.eq("left", result.first_id)
    h.eq("right", result.last_id)
    h.eq(0, by_id(result, "left").delta_mm)
    h.eq(1500, by_id(result, "middle").delta_mm)
    h.eq(0, by_id(result, "right").delta_mm)
    h.eq({ 4500, 1000 }, by_id(result, "middle").target_position)
    h.eq(5000, result.minimum_gap2)
    h.eq(5000, result.maximum_gap2)
    h.eq(true, result.exact)
  end)

  it("balances half-millimetre edges without moving the anchors", function()
    local value = plan()
    add(value, "one", { 1000, 1000 }, { 501, 600, 700 })
    add(value, "two", { 2600, 1000 }, { 500, 600, 700 })
    add(value, "three", { 4300, 1000 }, { 501, 600, 700 })
    add(value, "four", { 7000, 1000 }, { 500, 600, 700 })

    local result = h.truthy(distribution.propose(value, "room-main", "horizontal"))
    h.eq(0, result.items[1].delta_mm)
    h.eq(0, result.items[#result.items].delta_mm)
    h.truthy(result.maximum_gap2 - result.minimum_gap2 <= 2)
    local total = 0
    for _, gap2 in ipairs(result.gaps2) do total = total + gap2 end
    h.eq(8997, total)
  end)

  it("uses rotated and compound world bounds for vertical distribution", function()
    local value = plan()
    add(value, "south", { 2000, 1000 }, { 1000, 400, 700 }, { rotation_deg = 90 })
    add(value, "compound", { 2000, 2600 }, { 1, 1, 700 }, {
      anchor2_mm = { 400, 300 },
      footprint = {
        kind = "rect_union",
        parts = {
          { id = "part-main", origin_mm = { 0, 0 }, size_mm = { 400, 300 } },
          { id = "part-east", origin_mm = { 400, 0 }, size_mm = { 200, 150 } },
        },
      },
    })
    add(value, "north", { 2000, 6500 }, { 800, 600, 700 })

    local result = h.truthy(distribution.propose(value, "room-main", "vertical"))
    h.eq("south", result.first_id)
    h.eq("north", result.last_id)
    h.eq(0, by_id(result, "south").delta_mm)
    h.eq(0, by_id(result, "north").delta_mm)
    h.eq(1, result.changed_count)
    h.eq(2000, by_id(result, "south").bounds.depth2)
    h.eq(600, by_id(result, "compound").bounds.depth2)
  end)

  it("applies every move atomically and preserves the selected item", function()
    local value = plan()
    add(value, "furniture-left", { 1000, 1000 }, { 1000, 600, 700 })
    add(value, "furniture-middle", { 3000, 1000 }, { 1000, 600, 700 })
    add(value, "furniture-right", { 8000, 1000 }, { 1000, 600, 700 })

    local changed, result = actions.apply(value, {
      type = "distribute_furniture",
      room_id = "room-main",
      selected_id = "furniture-middle",
      axis = "horizontal",
    })
    h.truthy(changed, result and vim.inspect(result))
    h.eq({ 4500, 1000 }, changed.furniture[2].position_mm)
    h.eq({ 3000, 1000 }, value.furniture[2].position_mm)
    h.eq({ kind = "furniture", id = "furniture-middle" }, result.touched[1])
    h.eq({ "furniture-middle" }, result.metadata.moved_ids)
    h.eq(1, result.metadata.distribution.changed_count)
  end)

  it("rejects undersized sets, stale selections, and insufficient spans", function()
    local value = plan()
    add(value, "one", { 1000, 1000 }, { 1000, 600, 700 })
    add(value, "two", { 3000, 1000 }, { 1000, 600, 700 })
    local result, err = distribution.propose(value, "room-main", "horizontal")
    h.eq(nil, result)
    h.eq("DISTRIBUTION_COUNT", err.code)

    add(value, "three", { 5000, 1000 }, { 1000, 600, 700 })
    result, err = distribution.propose(value, "room-main", "horizontal", { selected_id = "missing" })
    h.eq(nil, result)
    h.eq("DISTRIBUTION_SELECTION", err.code)

    value.furniture[1].footprint.parts[1].size_mm[1] = 5000
    value.furniture[2].footprint.parts[1].size_mm[1] = 5000
    value.furniture[3].footprint.parts[1].size_mm[1] = 5000
    result, err = distribution.propose(value, "room-main", "horizontal")
    h.eq(nil, result)
    h.eq("DISTRIBUTION_SPAN", err.code)
  end)

  it("blocks an atomic distribution that would move furniture into an L-room notch", function()
    local value = plan()
    value.rooms[1].footprint = h.truthy(room_footprints.build({
      shape = "l_shape",
      width_mm = 6000,
      depth_mm = 6000,
      leg_width_mm = 2000,
      leg_depth_mm = 2000,
      missing_corner = "northeast",
    }))
    add(value, "furniture-left", { 500, 500 }, { 500, 500, 700 })
    add(value, "furniture-upper", { 1500, 4500 }, { 500, 500, 700 })
    add(value, "furniture-right", { 5500, 500 }, { 500, 500, 700 })

    local changed, err = actions.apply(value, {
      type = "distribute_furniture",
      room_id = "room-main",
      selected_id = "furniture-upper",
      axis = "horizontal",
    })
    h.eq(nil, changed)
    h.eq("LAYOUT_BLOCKED", err.code)
    h.eq("FURNITURE_OUTSIDE_ROOM", err.details.diagnostics[1].code)
    h.eq({ 1500, 4500 }, value.furniture[2].position_mm)
  end)
end)
