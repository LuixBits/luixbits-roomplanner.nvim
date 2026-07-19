local json = require("roomplan.codec.json")
local solar = require("roomplan.solar")
local directions = require("roomplan.directions")
local viewport = require("roomplan.render.viewport")
local walls = require("roomplan.scene.walls")
local sunlight = require("roomplan.analysis.sunlight")
local scene_builder = require("roomplan.scene.build")
local raster = require("roomplan.render.raster")

describe("offline sunlight study", function()
  it("parses exact site values and calculates a plausible equinox day", function()
    local exact = assert(json.decimal_from_string("47.3769001"))
    assert_true(json.is_decimal(exact))
    assert_equal("47.3769001\n", json.encode(exact))
    local value = assert(solar.position({
      north_deg = 0, latitude_deg = 0, longitude_deg = 0, utc_offset_minutes = 0,
    }, "2024-03-20", "12:00"))
    assert_true(value.elevation_deg > 87)
    assert_true(value.sunrise_minutes > 300 and value.sunrise_minutes < 420)
    assert_true(value.sunset_minutes > 1020 and value.sunset_minutes < 1140)
  end)

  it("moves between seasonal dates without spilling invalid month days", function()
    assert_equal("2025-02-28", assert(solar.shift_months("2024-10-31", 4)))
    assert_equal("2024-02-29", assert(solar.shift_months("2023-10-31", 4)))
    assert_equal("2023-11-30", assert(solar.shift_months("2024-03-31", -4)))
  end)

  it("translates stable plan sides into the rotated top/right/bottom/left UI", function()
    assert_equal("Top", directions.label("north"))
    assert_equal("Right", directions.label("east"))
    local rotated = viewport.new({ rotation_quarters = 1 })
    assert_equal("Right", directions.label("north", rotated))
    assert_equal("Bottom", directions.label("east", rotated))
    assert_equal("P→", directions.compass(nil, rotated, false))
    assert_equal("N↓", directions.compass(90, rotated, false))
    assert_equal("→", directions.arrow(0, 1, rotated, false))
  end)

  it("casts only exterior sun-facing windows and preserves assumed heights", function()
    local room = { id = "room-a", origin_mm = { 0, 0 }, size_mm = { 4000, 3000 } }
    local window = {
      id = "window-a", room_id = "room-a", connects_to_room_id = json.null,
      part_id = "part-main", side = "north", offset_mm = 1000, width_mm = 1200,
    }
    local wall_scene = walls.build({ room }, {}, { window }, {})
    local result = sunlight.build({ rooms = { room }, windows = { window } }, wall_scene, {
      elevation_deg = 45, sun_dx = 0, sun_dy = 1, incoming_dx = 0, incoming_dy = -1,
    }, { sill_height_mm = 900, head_height_mm = 2100 })
    assert_equal(1, #result.patches)
    assert_equal(1, result.assumed_count)
    assert_true(result.windows["window-a"])
    assert_true(result.patches[1].estimated)
    assert_true(math.abs(result.patches[1].near_distance - 900) < 1e-7)
    assert_true(math.abs(result.patches[1].far_distance - 2100) < 1e-7)

    local connected = vim.deepcopy(window)
    connected.connects_to_room_id = "room-b"
    local room_b = { id = "room-b", origin_mm = { 0, 3000 }, size_mm = { 4000, 3000 } }
    local connected_scene = walls.build({ room, room_b }, {}, { connected }, {})
    assert_equal(0, #sunlight.build({}, connected_scene, {
      elevation_deg = 45, sun_dx = 0, sun_dy = 1, incoming_dx = 0, incoming_dy = -1,
    }, { sill_height_mm = 900, head_height_mm = 2100 }).patches)
  end)

  it("rasterizes the clipped yellow-to-orange patch beneath walls and furniture", function()
    local model = {
      rooms = { { id = "room-a", name = "A", origin_mm = { 0, 0 }, size_mm = { 4000, 3000 } } },
      doors = {}, outlets = {}, furniture = {}, settings = { grid_mm = 100 },
      windows = { {
        id = "window-a", room_id = "room-a", connects_to_room_id = json.null,
        part_id = "part-main", side = "north", offset_mm = 1000, width_mm = 1200,
        sill_height_mm = 500, head_height_mm = 2500,
      } },
    }
    local scene = scene_builder.build(model, {}, {
      detail_level = "none",
      sun_study = { active = true, calculation = {
        elevation_deg = 45, sun_dx = 0, sun_dy = 1, incoming_dx = 0, incoming_dy = -1,
      } },
      sun_config = { window_defaults = { sill_height_mm = 900, head_height_mm = 2100 } },
    })
    assert_equal(1, #scene.sunlight.patches)
    local output = raster.rasterize(scene, viewport.new({
      world_left_mm = 0, world_top_mm = 3000, mm_per_column = 250, mm_per_row = 250,
    }), { width = 17, height = 13, glyph_mode = "ascii" })
    local levels = {}
    for row = 1, output.height do
      for column = 1, output.width do
        local role = output.roles[row][column]
        if role and role:match("^sunlight_") then levels[role] = true end
      end
    end
    assert_true(levels.sunlight_1 or levels.sunlight_2)
    assert_true(levels.sunlight_4 or levels.sunlight_5)
  end)

  it("accumulates one day into fixed comparable exposure bands", function()
    local model = {
      rooms = { { id = "room-a", name = "A", origin_mm = { 0, 0 }, size_mm = { 4000, 3000 } } },
      doors = {}, outlets = {}, furniture = {}, settings = { grid_mm = 100 },
      site = { north_deg = 0, latitude_deg = 47, longitude_deg = 8, utc_offset_minutes = 60 },
      windows = { {
        id = "window-a", room_id = "room-a", connects_to_room_id = json.null,
        part_id = "part-main", side = "south", offset_mm = 1000, width_mm = 1200,
        sill_height_mm = 500, head_height_mm = 2500,
      } },
    }
    local wall_scene = walls.build(model.rooms, model.doors, model.windows, model.outlets)
    local exposure = assert(sunlight.build_day(model, wall_scene, model.site, "2026-03-20", 60, {
      sill_height_mm = 900, head_height_mm = 2100,
    }))
    assert_true(#exposure.samples > 8)
    assert_true(exposure.total_minutes > 600)
    assert_true(exposure.room_minutes["room-a"] > 0)
    assert_true(exposure.window_minutes["window-a"] > 0)
    assert_equal(1, sunlight.exposure_level(30))
    assert_equal(3, sunlight.exposure_level(180))
    assert_equal(5, sunlight.exposure_level(420))

    local scene = scene_builder.build(model, {}, {
      detail_level = "none",
      sun_study = { active = true, overlay = "daily", daily_exposure = exposure },
      sun_config = { window_defaults = { sill_height_mm = 900, head_height_mm = 2100 } },
    })
    local output = raster.rasterize(scene, viewport.new({
      world_left_mm = 0, world_top_mm = 3000, mm_per_column = 250, mm_per_row = 250,
    }), { width = 17, height = 13, glyph_mode = "ascii" })
    local exposed = false
    for row = 1, output.height do
      for column = 1, output.width do
        if (output.roles[row][column] or ""):match("^sunlight_") then exposed = true end
      end
    end
    assert_true(exposed)
  end)
end)
