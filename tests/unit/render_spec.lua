local json = require("roomplan.codec.json")
local walls = require("roomplan.scene.walls")
local scene_builder = require("roomplan.scene.build")
local viewport = require("roomplan.render.viewport")
local glyphs = require("roomplan.render.glyphs")
local text = require("roomplan.render.text")
local raster = require("roomplan.render.raster")

local function assert_close(expected, actual, message)
  assert_true(math.abs(expected - actual) < 1e-8,
    (message or "values differ") .. string.format(": expected %.12g, got %.12g", expected, actual))
end

local function has_segment_at(segments, orientation, fixed, scalar)
  for _, segment in ipairs(segments) do
    if segment.orientation == orientation
      and segment.fixed == fixed
      and segment.start < scalar
      and segment.finish > scalar
    then
      return segment
    end
  end
  return nil
end

local function fixed_view(left, top, column_scale, row_scale)
  return viewport.new({
    world_left_mm = left,
    world_top_mm = top,
    mm_per_column = column_scale,
    mm_per_row = row_scale,
  })
end

describe("scene extraction and rendering", function()
  it("groups coincident walls while retaining both contributors", function()
    local result = walls.build({
      { id = "room-a", origin_mm = { 0, 0 }, size_mm = { 1000, 1000 } },
      { id = "room-b", origin_mm = { 1000, 0 }, size_mm = { 1000, 1000 } },
    }, {})
    local shared = assert(has_segment_at(result.segments, "vertical", 1000, 500))
    assert_equal(2, #shared.contributors)
    assert_equal("room-a", shared.contributors[1].room_id)
    assert_equal("east", shared.contributors[1].side)
    assert_equal("room-b", shared.contributors[2].room_id)
    assert_equal("west", shared.contributors[2].side)
  end)

  it("subtracts a connected aperture from both shared contributors", function()
    local result = walls.build({
      { id = "room-a", origin_mm = { 0, 0 }, size_mm = { 1000, 1000 } },
      { id = "room-b", origin_mm = { 1000, 0 }, size_mm = { 1000, 1000 } },
    }, {
      {
        id = "door-ab",
        room_id = "room-a",
        connects_to_room_id = "room-b",
        side = "east",
        offset_mm = 200,
        width_mm = 400,
      },
    })
    assert_equal(true, result.apertures[1].connection_valid)
    assert_equal(nil, has_segment_at(result.segments, "vertical", 1000, 400))
    assert_true(has_segment_at(result.segments, "vertical", 1000, 100) ~= nil)
    assert_true(has_segment_at(result.segments, "vertical", 1000, 800) ~= nil)
  end)

  it("keeps the opposite contribution closed for a broken connection", function()
    local result = walls.build({
      { id = "room-a", origin_mm = { 0, 0 }, size_mm = { 1000, 1000 } },
      { id = "room-b", origin_mm = { 1000, 0 }, size_mm = { 1000, 1000 } },
      { id = "room-c", origin_mm = { 4000, 0 }, size_mm = { 1000, 1000 } },
    }, {
      {
        id = "door-ac",
        room_id = "room-a",
        connects_to_room_id = "room-c",
        side = "east",
        offset_mm = 200,
        width_mm = 400,
      },
    })
    assert_equal(false, result.apertures[1].connection_valid)
    local closed = assert(has_segment_at(result.segments, "vertical", 1000, 400))
    assert_equal(1, #closed.contributors)
    assert_equal("room-b", closed.contributors[1].room_id)
  end)

  it("treats the strict codec null sentinel as no connection", function()
    local result = walls.build({
      { id = "room-a", origin_mm = { 0, 0 }, size_mm = { 1000, 1000 } },
    }, {
      {
        id = "door-outside",
        room_id = "room-a",
        connects_to_room_id = json.null,
        side = "south",
        offset_mm = 200,
        width_mm = 400,
      },
    })
    assert_equal(false, result.apertures[1].connection_requested)
    assert_equal(nil, has_segment_at(result.segments, "horizontal", 0, 400))
  end)

  it("includes furniture and complete door sweep extents in scene bounds", function()
    local scene = scene_builder.build({
      rooms = {
        { id = "room-a", name = "A", origin_mm = { 0, 0 }, size_mm = { 1000, 1000 } },
      },
      furniture = {
        {
          id = "furniture-a",
          room_id = "room-a",
          name = "Desk",
          center_mm = { 1200, 500 },
          size_mm = { 401, 201, 700 },
          rotation_deg = 0,
        },
      },
      doors = {
        {
          id = "door-a",
          room_id = "room-a",
          connects_to_room_id = json.null,
          side = "south",
          offset_mm = 0,
          width_mm = 500,
          hinge = "start",
          opens_into = "outside",
          open_angle_deg = 90,
        },
      },
    })
    assert_true(scene.bounds.right >= 1400.5)
    assert_true(scene.bounds.left <= 0)
    assert_true(scene.bounds.bottom <= -500)
  end)

  it("switches cleanly between all, wall-only, and hidden canvas details", function()
    local plan = {
      rooms = {
        { id = "room-a", name = "Living room", origin_mm = { 0, 0 }, size_mm = { 1000, 800 } },
      },
      furniture = {
        {
          id = "furniture-a",
          room_id = "room-a",
          name = "Sofa",
          center_mm = { 500, 400 },
          size_mm = { 200, 100, 700 },
          rotation_deg = 0,
        },
      },
      doors = {
        {
          id = "door-a",
          room_id = "room-a",
          connects_to_room_id = json.null,
          side = "south",
          offset_mm = 100,
          width_mm = 300,
          hinge = "start",
          opens_into = "outside",
          open_angle_deg = 90,
        },
      },
    }

    local function detail_counts(level)
      local scene = scene_builder.build(plan, nil, { detail_level = level })
      local counts = { labels = 0, room = 0, furniture = 0, door = 0 }
      for _, primitive in ipairs(scene.primitives) do
        if primitive.kind == "label" then
          counts.labels = counts.labels + 1
        elseif primitive.kind == "dimension" then
          counts[primitive.ref.type] = counts[primitive.ref.type] + 1
        end
      end
      return scene, counts
    end

    local high, high_counts = detail_counts("high")
    local middle, middle_counts = detail_counts("middle")
    local none, none_counts = detail_counts("none")
    assert_equal({ labels = 2, room = 4, furniture = 2, door = 1 }, high_counts)
    assert_equal({ labels = 2, room = 4, furniture = 0, door = 0 }, middle_counts)
    assert_equal({ labels = 0, room = 0, furniture = 0, door = 0 }, none_counts)
    assert_true(vim.deep_equal(high.bounds, middle.bounds) and vim.deep_equal(middle.bounds, none.bounds))
    assert_true(vim.deep_equal(high.objects, middle.objects) and vim.deep_equal(middle.objects, none.objects))
  end)

  it("keeps finite repair geometry renderable through strict footprint adapters", function()
    for _, rotation in ipairs({ 45, "invalid", math.huge, 0 / 0 }) do
      local scene = scene_builder.build({
        rooms = {
          { id = "room-repair", name = "Repair", origin_mm = { 0.25, -0.5 }, size_mm = { 10.5, 20.25 } },
        },
        furniture = {
          {
            id = "furniture-repair",
            room_id = "room-repair",
            name = "Repair item",
            center_mm = { 5.25, 6.5 },
            size_mm = { 7.5, 9.25 },
            rotation_deg = rotation,
          },
        },
        doors = {},
      })
      local interior
      for _, primitive in ipairs(scene.primitives) do
        if primitive.kind == "furniture_interior" then interior = primitive end
      end
      assert_true(interior ~= nil)
      assert_equal(1.75, interior.left)
      assert_equal(9.25, interior.right)
      assert_equal(1.375, interior.bottom)
      assert_equal(10.625, interior.top)
    end
  end)

  it("emits the same handed leaf for every side, hinge, and swing half-plane", function()
    local geometry_door = require("roomplan.geometry.door")
    local room = { id = "room-a", origin_mm = { 0, 0 }, size_mm = { 1000, 1000 } }
    for _, side in ipairs({ "north", "east", "south", "west" }) do
      for _, hinge in ipairs({ "start", "end" }) do
        for _, target in ipairs({ "owner", "outside" }) do
          local door = {
            id = "door-a",
            room_id = "room-a",
            connects_to_room_id = json.null,
            side = side,
            offset_mm = 100,
            width_mm = 300,
            hinge = hinge,
            opens_into = target,
            open_angle_deg = 90,
          }
          local classified = walls.classify_door(door, { [room.id] = room }, { [room.id] = 1 }, 1)
          local rendered = assert(scene_builder.door_swing(classified))
          local canonical = assert(geometry_door.swing(room, door))
          assert_true(math.abs(rendered.hinge_x - canonical.hinge.x) < 1e-8)
          assert_true(math.abs(rendered.hinge_y - canonical.hinge.y) < 1e-8)
          assert_true(math.abs(rendered.open_x - canonical.open_endpoint.x) < 1e-8)
          assert_true(math.abs(rendered.open_y - canonical.open_endpoint.y) < 1e-8)
        end
      end
    end
  end)

  it("fits, zooms around an anchor, and pans without changing aspect", function()
    local fitted = viewport.fit({ left = 0, bottom = 0, right = 1000, top = 1000 }, 20, 10, {
      mm_per_column = 100,
      cell_aspect = 2,
      fit_margin_cells = 2,
    })
    assert_equal(2, fitted.mm_per_row / fitted.mm_per_column)
    local world_x, world_y = viewport.screen_to_world(fitted, 7, 3)
    local zoomed = viewport.zoom_in(fitted, 1.25, { screen_x = 7, screen_y = 3 })
    local anchored_x, anchored_y = viewport.screen_to_world(zoomed, 7, 3)
    assert_true(math.abs(world_x - anchored_x) < 1e-8)
    assert_true(math.abs(world_y - anchored_y) < 1e-8)
    assert_equal(2, zoomed.mm_per_row / zoomed.mm_per_column)
    local panned = viewport.pan_cells(zoomed, 2, -3)
    assert_equal(zoomed.world_left_mm + 2 * zoomed.mm_per_column, panned.world_left_mm)
    assert_equal(zoomed.world_top_mm - 3 * zoomed.mm_per_row, panned.world_top_mm)
  end)

  it("keeps a followed world point inside a symmetric scrolloff", function()
    local original = viewport.new({
      world_left_mm = 0,
      world_top_mm = 0,
      mm_per_column = 100,
      mm_per_row = 200,
    })
    local inside_x, inside_y = viewport.screen_to_world(original, 6, 4)
    local unchanged = viewport.ensure_visible(original, inside_x, inside_y, 10, 8, 2)
    assert_equal(original.world_left_mm, unchanged.world_left_mm)
    assert_equal(original.world_top_mm, unchanged.world_top_mm)

    local target_x, target_y = viewport.screen_to_world(original, 11, 9)
    local followed = viewport.ensure_visible(original, target_x, target_y, 10, 8, 2)
    local column, row = viewport.world_to_screen(followed, target_x, target_y)
    assert_close(7, column)
    assert_close(5, row)

    local tiny = viewport.ensure_visible(original, target_x, target_y, 4, 3, 20)
    column, row = viewport.world_to_screen(tiny, target_x, target_y)
    assert_close(2, column)
    assert_close(1, row)

    for rotation = 0, 3 do
      local turned = viewport.new({
        world_left_mm = -300,
        world_top_mm = 700,
        mm_per_column = 80,
        mm_per_row = 160,
        rotation_quarters = rotation,
      })
      for _, screen in ipairs({ { -4, 3 }, { 15, 3 }, { 4, -5 }, { 4, 12 } }) do
        local world_x, world_y = viewport.screen_to_world(turned, screen[1], screen[2])
        local visible = viewport.ensure_visible(turned, world_x, world_y, 10, 8, 2)
        local visible_column, visible_row = viewport.world_to_screen(visible, world_x, world_y)
        assert_true(visible_column >= 2 and visible_column <= 7)
        assert_true(visible_row >= 2 and visible_row <= 5)
      end
    end
  end)

  it("round-trips screen coordinates and maps cardinals through every view rotation", function()
    local east = {
      [0] = { 1, 0 }, [1] = { 0, 1 }, [2] = { -1, 0 }, [3] = { 0, -1 },
    }
    local north = {
      [0] = { 0, -1 }, [1] = { 1, 0 }, [2] = { 0, 1 }, [3] = { -1, 0 },
    }
    local world_deltas = {
      [0] = { 3, 2 }, [1] = { -2, 3 }, [2] = { -3, -2 }, [3] = { 2, -3 },
    }

    for rotation = 0, 3 do
      local cardinal_view = viewport.new({
        world_left_mm = 0,
        world_top_mm = 0,
        mm_per_column = 100,
        mm_per_row = 100,
        rotation_quarters = rotation,
      })
      local east_column, east_row = viewport.world_to_screen(cardinal_view, 100, 0)
      local north_column, north_row = viewport.world_to_screen(cardinal_view, 0, 100)
      assert_close(east[rotation][1], east_column)
      assert_close(east[rotation][2], east_row)
      assert_close(north[rotation][1], north_column)
      assert_close(north[rotation][2], north_row)
      local world_dx, world_dy = viewport.view_delta_to_world(cardinal_view, 3, 2)
      assert_equal(world_deltas[rotation], { world_dx, world_dy })
      local view_dx, view_dy = viewport.world_delta_to_view(cardinal_view, world_dx, world_dy)
      assert_equal({ 3, 2 }, { view_dx, view_dy })

      local view = viewport.new({
        world_left_mm = -370,
        world_top_mm = 910,
        mm_per_column = 80,
        mm_per_row = 160,
        rotation_quarters = rotation,
      })
      for _, point in ipairs({ { 0, 0 }, { 7.25, 3.5 }, { -2, 11 } }) do
        local world_x, world_y = viewport.screen_to_world(view, point[1], point[2])
        local column, row = viewport.world_to_screen(view, world_x, world_y)
        assert_close(point[1], column, "column round-trip")
        assert_close(point[2], row, "row round-trip")
      end
    end
  end)

  it("preserves rotated fit, zoom, and rotation anchors", function()
    local fitted = viewport.fit({ left = -200, bottom = 100, right = 1800, top = 900 }, 24, 12, {
      mm_per_column = 100,
      cell_aspect = 2,
      fit_margin_cells = 2,
      rotation_quarters = 1,
    })
    assert_equal(1, viewport.rotation(fitted))
    local center_column, center_row = viewport.world_to_screen(fitted, 800, 500)
    assert_close(11.5, center_column)
    assert_close(5.5, center_row)

    local anchor_column, anchor_row = 7, 3
    local anchor_x, anchor_y = viewport.screen_to_world(fitted, anchor_column, anchor_row)
    local zoomed = viewport.zoom_in(fitted, 1.25, {
      world_x = anchor_x,
      world_y = anchor_y,
      screen_x = anchor_column,
      screen_y = anchor_row,
    })
    local zoomed_column, zoomed_row = viewport.world_to_screen(zoomed, anchor_x, anchor_y)
    assert_close(anchor_column, zoomed_column)
    assert_close(anchor_row, zoomed_row)
    assert_equal(1, viewport.rotation(zoomed))

    local rotated = viewport.rotate(zoomed, 1, {
      world_x = anchor_x,
      world_y = anchor_y,
      screen_x = anchor_column,
      screen_y = anchor_row,
    })
    local rotated_column, rotated_row = viewport.world_to_screen(rotated, anchor_x, anchor_y)
    assert_close(anchor_column, rotated_column)
    assert_close(anchor_row, rotated_row)
    assert_equal(2, viewport.rotation(rotated))
  end)

  it("returns to north-up after four turns and pans in visible screen axes", function()
    local original = viewport.new({
      world_left_mm = -500,
      world_top_mm = 700,
      mm_per_column = 100,
      mm_per_row = 200,
    })
    local center_x, center_y = viewport.screen_to_world(original, 9.5, 4.5)
    local turned = original
    for expected = 1, 4 do
      turned = viewport.rotate(turned, 1, nil, { columns = 20, rows = 10 })
      assert_equal(expected % 4, viewport.rotation(turned))
      local current_x, current_y = viewport.screen_to_world(turned, 9.5, 4.5)
      assert_close(center_x, current_x)
      assert_close(center_y, current_y)
    end
    assert_close(original.world_left_mm, turned.world_left_mm)
    assert_close(original.world_top_mm, turned.world_top_mm)

    local east_at_right = viewport.new({
      world_left_mm = 10,
      world_top_mm = 20,
      mm_per_column = 100,
      mm_per_row = 200,
      rotation_quarters = 1,
    })
    local panned = viewport.pan_cells(east_at_right, 2, 3)
    assert_close(-590, panned.world_left_mm)
    assert_close(220, panned.world_top_mm)
    local scale_x, scale_y = viewport.world_axis_scales(east_at_right)
    assert_equal({ 200, 100 }, { scale_x, scale_y })
    assert_equal(200, viewport.visible_move_step(east_at_right, 1, 0, 100))
    assert_equal(100, viewport.visible_move_step(east_at_right, 0, 1, 100))
    assert_equal(250, viewport.visible_move_step(east_at_right, 1, 0, 250))
  end)

  it("maps every structural direction mask in Unicode and ASCII", function()
    local unicode = glyphs.builtin("unicode")
    assert_equal("└", unicode.wall[glyphs.N + glyphs.E])
    assert_equal("┼", unicode.wall[15])
    local ascii = glyphs.builtin("ascii")
    for mask = 0, 15 do
      assert_equal(1, #ascii.wall[mask])
    end
    assert_equal("+", ascii.wall[15])
  end)

  it("renders a stable single-room ASCII snapshot", function()
    local scene = scene_builder.build({
      rooms = {
        { id = "room-a", name = "A", origin_mm = { 0, 0 }, size_mm = { 400, 400 } },
      },
      doors = {},
      furniture = {},
    })
    local pristine_scene = vim.deepcopy(scene)
    local output = raster.rasterize(scene, fixed_view(-100, 500, 100, 100), {
      width = 7,
      height = 7,
      glyph_mode = "ascii",
    })
    assert_true(vim.deep_equal(pristine_scene, scene), "rasterization must not mutate its semantic scene")
    assert_equal(table.concat({
      "       ",
      " +---+ ",
      " |   | ",
      " | A | ",
      " |   | ",
      " +---+ ",
      "       ",
    }, "\n"), table.concat(output.lines, "\n"))
  end)

  it("applies object color accents while diagnostics retain priority", function()
    local model = {
      rooms = {
        {
          id = "room-a",
          name = "A",
          origin_mm = { 0, 0 },
          size_mm = { 400, 400 },
          color = "#61AFEF",
        },
      },
      doors = {},
      furniture = {},
    }
    local colored = raster.rasterize(
      scene_builder.build(model),
      fixed_view(-100, 500, 100, 100),
      { width = 7, height = 7, glyph_mode = "ascii" }
    )
    local found_color = false
    for _, span in ipairs(colored.highlight_spans) do
      if span.color == "#61AFEF" then found_color = true end
    end
    assert_true(found_color)

    local diagnosed = raster.rasterize(scene_builder.build(model, {
      { severity = "error", object = { kind = "room", id = "room-a" } },
    }), fixed_view(-100, 500, 100, 100), {
      width = 7,
      height = 7,
      glyph_mode = "ascii",
    })
    local found_error = false
    for _, span in ipairs(diagnosed.highlight_spans) do
      if span.role == "error" then
        found_error = true
        assert_equal(nil, span.color)
      end
    end
    assert_true(found_error)
  end)

  it("keeps names readable without overlapping or clipping partial dimensions", function()
    local view = fixed_view(0, 200, 100, 100)
    local names = raster.rasterize({
      primitives = {
        {
          kind = "label", layer = 70, text = "Alpha", x = 0, y = 0,
          ref = { type = "room", id = "room-alpha" }, order = 1,
        },
        {
          kind = "label", layer = 70, text = "Beta", x = 0, y = 0,
          ref = { type = "furniture", id = "furniture-beta" }, order = 2,
        },
      },
      warnings = {},
    }, view, { width = 9, height = 3, glyph_mode = "ascii" })
    local rendered_names = table.concat(names.lines, "\n")
    assert_true(rendered_names:find("Alpha", 1, true) ~= nil)
    assert_true(rendered_names:find("Beta", 1, true) ~= nil)

    local abbreviated = raster.rasterize({
      primitives = {
        {
          kind = "label", layer = 70, text = "Very long sofa label", x = 0, y = 0,
          ref = { type = "furniture", id = "furniture-long" },
        },
      },
      warnings = {},
    }, view, { width = 7, height = 3, glyph_mode = "unicode" })
    local abbreviated_text = table.concat(abbreviated.lines, "\n")
    assert_true(abbreviated_text:find("…", 1, true) ~= nil)
    assert_true(abbreviated_text:find("bel", 1, true) ~= nil)
    assert_equal("LABEL_ABBREVIATED", abbreviated.warnings[1].code)

    local dimension = raster.rasterize({
      primitives = {
        {
          kind = "dimension", layer = 70, text = "123456mm", x = 0, y = 0,
          allow_truncate = false,
          ref = { type = "room", id = "room-alpha" },
        },
      },
      warnings = {},
    }, view, { width = 4, height = 3, glyph_mode = "ascii" })
    assert_true(table.concat(dimension.lines, ""):match("%d") == nil)
    assert_equal("LABEL_NOT_RENDERED", dimension.warnings[1].code)
  end)

  it("reduces text density as objects shrink on screen", function()
    local primitive = {
      kind = "label",
      layer = 70,
      text = "Living room",
      x = 500,
      y = 400,
      fit_bounds = { left = 0, right = 1000, bottom = 0, top = 800 },
      scale_policy = "room_name",
      ref = { type = "room", id = "room-living" },
    }
    local near = raster.rasterize({ primitives = { primitive }, warnings = {} },
      fixed_view(0, 1000, 50, 100), { width = 24, height = 12, glyph_mode = "ascii" })
    assert_true(table.concat(near.lines, "\n"):find("Living room", 1, true) ~= nil)

    local far = raster.rasterize({ primitives = { primitive }, warnings = {} },
      fixed_view(0, 1000, 500, 500), { width = 6, height = 4, glyph_mode = "ascii" })
    assert_true(table.concat(far.lines, "\n"):find("Living", 1, true) == nil)
    assert_equal(0, #far.warnings)

    local dimension_primitive = {
      kind = "dimension",
      layer = 70,
      text = "1m",
      x = 500,
      y = 0,
      fit_span = { x1 = 0, y1 = 0, x2 = 1000, y2 = 0 },
      scale_policy = "dimension",
      allow_truncate = false,
    }
    local crowded = raster.rasterize({ primitives = { dimension_primitive }, warnings = {} },
      fixed_view(0, 500, 250, 500), { width = 6, height = 3, glyph_mode = "ascii" })
    assert_true(table.concat(crowded.lines, ""):find("1m", 1, true) == nil)
  end)

  it("merges only structural walls into junction glyphs", function()
    local ref = { type = "room", id = "room-a", order = 1 }
    local scene = {
      primitives = {
        { kind = "wall", layer = 50, orientation = "horizontal", x1 = 0, y1 = 200, x2 = 400, y2 = 200, refs = { ref } },
        { kind = "wall", layer = 50, orientation = "vertical", x1 = 200, y1 = 0, x2 = 200, y2 = 400, refs = { ref } },
        {
          kind = "furniture_outline",
          layer = 31,
          left = 100,
          right = 300,
          bottom = 100,
          top = 300,
          ref = { type = "furniture", id = "furniture-a", order = 1 },
        },
      },
      warnings = {},
    }
    local output = raster.rasterize(scene, fixed_view(0, 400, 100, 100), {
      width = 5,
      height = 5,
      glyph_mode = "unicode",
    })
    assert_equal("┼", output.cells[3][3].char)
    assert_equal(15, output.cells[3][3].wall_mask)
  end)

  it("keeps ordered hit candidates beneath visual overlap", function()
    local scene = {
      primitives = {
        { kind = "room_interior", layer = 20, left = 0, bottom = 0, right = 400, top = 400, ref = { type = "room", id = "room-a", order = 1 } },
        { kind = "furniture_interior", layer = 30, left = 100, bottom = 100, right = 300, top = 300, ref = { type = "furniture", id = "furniture-a", order = 1 } },
        { kind = "wall", layer = 50, orientation = "horizontal", x1 = 0, y1 = 200, x2 = 400, y2 = 200, refs = { { type = "room", id = "room-a", order = 1 } } },
        { kind = "door_hinge", layer = 61, x = 200, y = 200, ref = { type = "door", id = "door-a", order = 1 } },
      },
      warnings = {},
    }
    local output = raster.rasterize(scene, fixed_view(0, 400, 100, 100), {
      width = 5,
      height = 5,
      glyph_mode = "ascii",
    })
    local hits = output.hit_map[3][3]
    assert_equal(3, #hits)
    assert_equal("door", hits[1].type)
    assert_equal("furniture", hits[2].type)
    assert_equal("room", hits[3].type)
    assert_equal("wall", hits[3].context)
  end)

  it("rotates walls, grid points, and ordered hits together", function()
    local room_ref = { type = "room", id = "room-a", order = 1 }
    local scene = {
      primitives = {
        { kind = "grid", layer = 10, spacing_mm = 200 },
        {
          kind = "wall", layer = 50, orientation = "horizontal",
          x1 = 100, y1 = 200, x2 = 300, y2 = 200, refs = { room_ref },
        },
        {
          kind = "door_hinge", layer = 61, x = 200, y = 200,
          ref = { type = "door", id = "door-a", order = 1 },
        },
      },
      warnings = {},
    }
    local output = raster.rasterize(scene, viewport.new({
      world_left_mm = 0,
      world_top_mm = 0,
      mm_per_column = 100,
      mm_per_row = 100,
      rotation_quarters = 1,
    }), {
      width = 5,
      height = 5,
      glyph_mode = "ascii",
    })

    assert_equal(table.concat({
      ". . .",
      "  |  ",
      ". o .",
      "  |  ",
      ". . .",
    }, "\n"), table.concat(output.lines, "\n"))
    assert_equal("room-a", output.hit_map[2][3][1].id)
    assert_equal("wall", output.hit_map[2][3][1].context)
    assert_equal("door", output.hit_map[3][3][1].type)
    assert_equal("room", output.hit_map[3][3][2].type)
  end)

  it("uses a semantic low-resolution door marker", function()
    local scene = scene_builder.build({
      rooms = {
        { id = "room-a", name = "A", origin_mm = { 0, 0 }, size_mm = { 1000, 1000 } },
      },
      doors = {
        {
          id = "door-a",
          room_id = "room-a",
          connects_to_room_id = json.null,
          side = "south",
          offset_mm = 300,
          width_mm = 100,
          hinge = "start",
          opens_into = "owner",
          open_angle_deg = 90,
        },
      },
      furniture = {},
    })
    local output = raster.rasterize(scene, fixed_view(0, 1000, 500, 500), {
      width = 4,
      height = 4,
      glyph_mode = "ascii",
    })
    local found = false
    for row = 1, output.height do
      for column = 1, output.width do
        if output.cells[row][column].char == "D" then
          found = true
          assert_equal("door-a", output.hit_map[row][column][1].id)
        end
      end
    end
    assert_true(found)
  end)

  it("clips fully offscreen geometry without boundary ghosts", function()
    local scene = {
      primitives = {
        { kind = "wall", layer = 50, orientation = "horizontal", x1 = -1000, y1 = 200, x2 = -500, y2 = 200, refs = {} },
        { kind = "wall", layer = 50, orientation = "vertical", x1 = 700, y1 = 0, x2 = 700, y2 = 400, refs = {} },
        { kind = "door_aperture", layer = 60, x1 = -1000, y1 = 100, x2 = -950, y2 = 100,
          ref = { type = "door", id = "door-offscreen", order = 1 } },
      },
      warnings = {},
    }
    local output = raster.rasterize(scene, fixed_view(0, 400, 100, 100), {
      width = 5,
      height = 5,
      glyph_mode = "ascii",
    })
    assert_equal(string.rep("     \n", 4) .. "     ", table.concat(output.lines, "\n"))
  end)

  it("keeps Unicode backing cells byte-safe and replaces wide clusters", function()
    local combining = "e\204\129"
    local cells, metadata = assert(text.sanitize_cells("A界" .. combining .. "😀", 10, vim.fn.strdisplaywidth, "?"))
    assert_equal(4, #cells)
    assert_equal("A", cells[1])
    assert_equal("?", cells[2])
    assert_equal(combining, cells[3])
    assert_equal("?", cells[4])
    assert_equal(2, metadata.replaced)

    local offsets = text.byte_offsets({ "─", combining, "?" })
    assert_equal(0, offsets[1])
    assert_equal(3, offsets[2])
    assert_equal(6, offsets[3])
    assert_equal(7, offsets[4])
    assert_equal(2, text.byte_to_cell(offsets, 4))
    local invalid, err = text.sanitize_cells("\255", 10, vim.fn.strdisplaywidth, "?")
    assert_equal(nil, invalid)
    assert_true(type(err) == "string")
  end)

  it("falls back atomically when one custom glyph is not one cell", function()
    local custom = glyphs.builtin("ascii")
    custom.door_hinge = "界"
    local resolved, warning = glyphs.resolve("auto", custom, vim.fn.strdisplaywidth)
    assert_equal("ascii", resolved.mode)
    assert_true(type(warning) == "string")
    assert_equal("o", resolved.door_hinge)
  end)

  it("keeps existing custom glyph sets valid without directional wall outlets", function()
    local custom = glyphs.builtin("ascii")
    custom.outlet_wall_north = nil
    custom.outlet_wall_east = nil
    custom.outlet_wall_south = nil
    custom.outlet_wall_west = nil
    custom.outlet_marker = "x"
    local resolved, warning = glyphs.resolve("auto", custom, vim.fn.strdisplaywidth)
    assert_equal("custom", resolved.mode)
    assert_equal(nil, warning)
    assert_equal("x", resolved.outlet_marker)
    assert_equal("v", resolved.outlet_wall_north)
    assert_equal("<", resolved.outlet_wall_east)
  end)

  it("recognizes validator object refs and kind-based selection roles", function()
    local model = {
      rooms = {
        { id = "room-a", name = "A", origin_mm = { 0, 0 }, size_mm = { 1000, 1000 } },
      },
      doors = {},
      furniture = {},
    }
    local scene = scene_builder.build(model, {
      {
        code = "ROOM_OVERLAP",
        severity = "error",
        object = { kind = "room", id = "room-a" },
        related = {},
      },
    }, { selected = { kind = "room", id = "room-a" } })
    local interior
    for _, primitive in ipairs(scene.primitives) do
      if primitive.kind == "room_interior" then interior = primitive; break end
    end
    assert_equal("error", assert(interior).role)
  end)

  it("draws transient snap guides and emphasizes their overlapping edge", function()
    local output = raster.rasterize({
      primitives = {
        { kind = "wall", layer = 50, x1 = 100, y1 = 0, x2 = 100, y2 = 400 },
        { kind = "snap_guide", layer = 85, role = "snap", x1 = 100, y1 = 0, x2 = 100, y2 = 400 },
        { kind = "snap_overlap", layer = 88, role = "snap_overlap", x1 = 100, y1 = 100, x2 = 100, y2 = 300 },
        { kind = "snap_guide", layer = 85, role = "snap", x1 = 0, y1 = 200, x2 = 200, y2 = 200 },
        { kind = "snap_overlap", layer = 88, role = "snap_overlap", x1 = 0, y1 = 200, x2 = 100, y2 = 200 },
      },
      warnings = {},
    }, fixed_view(0, 400, 100, 100), {
      width = 3,
      height = 5,
      glyph_mode = "ascii",
    })
    assert_true(table.concat(output.lines, "\n"):find(":", 1, true) ~= nil)
    assert_equal("snap", output.roles[1][2])
    assert_equal("snap_overlap", output.roles[2][2])
    assert_equal("#", output.cells[2][2].char)
    assert_equal("snap_overlap", output.roles[3][1])
    assert_equal("=", output.cells[3][1].char)
    assert_equal("snap", output.roles[3][3])
    assert_equal(".", output.cells[3][3].char)
  end)

  it("keeps every overlap when contacts share one guide line", function()
    local scene = scene_builder.build({
      rooms = {
        { id = "room-a", name = "A", origin_mm = { 0, 0 }, size_mm = { 1000, 1000 } },
      },
      doors = {},
      windows = {},
      outlets = {},
      furniture = {},
    }, {}, {
      snap_guides = {
        {
          axis = "x",
          value2 = 2000,
          value_mm = 1000,
          overlap_start_mm = 0,
          overlap_finish_mm = 500,
          target_label = "Lower wall",
        },
        {
          axis = "x",
          value2 = 2000,
          value_mm = 1000,
          overlap_start_mm = 500,
          overlap_finish_mm = 1000,
          target_label = "Upper wall",
        },
      },
    })
    local lines, overlaps = 0, 0
    for _, primitive in ipairs(scene.primitives) do
      if primitive.kind == "snap_guide" then
        lines = lines + 1
      end
      if primitive.kind == "snap_overlap" then
        overlaps = overlaps + 1
      end
    end
    assert_equal(1, lines)
    assert_equal(2, overlaps)
  end)

  it("draws exact contacts without filling the canvas with guide lines", function()
    local scene = scene_builder.build({
      rooms = {
        { id = "room-a", name = "A", origin_mm = { 0, 0 }, size_mm = { 1000, 1000 } },
      },
      doors = {}, windows = {}, outlets = {}, furniture = {},
    }, {}, {
      snap_guides = {
        {
          axis = "y",
          value2 = 2000,
          value_mm = 1000,
          overlap_start_mm = 0,
          overlap_finish_mm = 1000,
          target_label = "North wall",
          contact_only = true,
        },
      },
    })
    local lines, overlaps = 0, 0
    for _, primitive_value in ipairs(scene.primitives) do
      if primitive_value.kind == "snap_guide" then lines = lines + 1 end
      if primitive_value.kind == "snap_overlap" then overlaps = overlaps + 1 end
    end
    assert_equal(0, lines)
    assert_equal(1, overlaps)
  end)

  it("opens, redraws, maps byte columns, and wipes a scratch canvas", function()
    local canvas = require("roomplan.render.canvas")
    local closed = false
    local scene = scene_builder.build({
      rooms = {
        { id = "room-a", name = "A", origin_mm = { 0, 0 }, size_mm = { 1000, 1000 } },
      },
      doors = {},
      furniture = {},
    })
    local handle = canvas.open({
      open = "split",
      scene = scene,
      header_lines = 2,
      glyph_mode = "unicode",
      on_close = function()
        closed = true
      end,
    })
    assert_true(vim.api.nvim_buf_is_valid(handle.buf))
    assert_equal("nofile", vim.bo[handle.buf].buftype)
    assert_equal(false, vim.bo[handle.buf].modifiable)
    assert_true(handle.last_raster ~= nil)
    assert_true(canvas.set_logical_cursor(handle, 2, 2))
    local cursor = assert(canvas.logical_cursor(handle))
    assert_equal(2, cursor.row)
    assert_equal(2, cursor.column)
    assert_true(canvas.close(handle))
    assert_equal(false, vim.api.nvim_buf_is_valid(handle.buf))
    assert_equal(true, closed)
  end)

  it("renders the rotated compass as Unicode and ASCII header chrome", function()
    local canvas = require("roomplan.render.canvas")
    local scene = { primitives = {}, warnings = {}, bounds = { empty = true } }
    local function compass_text(handle)
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(
        handle.buf, handle.namespace, 0, 1, { details = true }
      )) do
        local details = mark[4]
        if details.virt_text and details.virt_text[1] then
          return details.virt_text[1][1]
        end
      end
    end

    local handle = canvas.open({
      open = "split",
      scene = scene,
      viewport = viewport.new({
        world_left_mm = 0,
        world_top_mm = 0,
        mm_per_column = 100,
        mm_per_row = 200,
        rotation_quarters = 1,
      }),
      fit_on_open = false,
      header_lines = 1,
      show_compass = true,
      glyph_mode = "unicode",
    })
    assert_equal("N→", compass_text(handle))

    handle.opts.glyph_mode = "ascii"
    assert(canvas.redraw(handle, scene, viewport.new({
      world_left_mm = 0,
      world_top_mm = 0,
      mm_per_column = 100,
      mm_per_row = 200,
      rotation_quarters = 3,
    })))
    assert_equal("N<", compass_text(handle))
    assert_true(canvas.close(handle))
  end)

  it("renders an actionable empty state with a drawable initial cursor and footer", function()
    local config = require("roomplan.config")
    local canvas = require("roomplan.render.canvas")
    config.setup({ canvas = { open = "split" } })
    local plan = { rooms = {}, doors = {}, furniture = {}, settings = { grid_mm = 100 } }
    local session = {
      id = "session-empty-canvas",
      source = { path = "/tmp/empty-canvas.roomplan.json", bufnr = vim.api.nvim_get_current_buf() },
      canvas = {}, validation = {}, selection = nil, mode = "NAV", snap_enabled = true,
      workflow = { generation = 0, kind = nil },
    }
    function session:model() return plan end
    function session:status_text() return "[SAVED]" end

    local handle = canvas.open(session)
    local lines = vim.api.nvim_buf_get_lines(handle.buf, 0, -1, false)
    assert_true(table.concat(lines, "\n"):find("Empty floor plan", 1, true) ~= nil)
    assert_true(lines[#lines]:find("[a] Add first room", 1, true) ~= nil)
    local cursor = assert(canvas.logical_cursor(session))
    assert_true(cursor.row >= 0 and cursor.row < handle.last_raster.height)
    assert_true(cursor.column >= 0 and cursor.column < handle.last_raster.width)
    local has_fit_mapping = false
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(handle.buf, "n")) do
      if mapping.lhs == "f" and mapping.desc == "Fit RoomPlan" then has_fit_mapping = true end
    end
    assert_true(has_fit_mapping)
    local function mapping(lhs)
      return vim.api.nvim_buf_call(handle.buf, function()
        return vim.fn.maparg(lhs, "n", false, true)
      end)
    end
    assert_equal("Rotate RoomPlan view clockwise", mapping("<A-l>").desc)
    assert_equal("Rotate RoomPlan view counter-clockwise", mapping("<A-h>").desc)
    assert_equal("Next RoomPlan issue", mapping("<A-j>").desc)
    assert_equal("Previous RoomPlan issue", mapping("<A-k>").desc)
    assert_equal("Cycle RoomPlan canvas detail", mapping("t").desc)
    assert_equal(nil, next(mapping("]r")))
    assert_equal(nil, next(mapping("[r")))
    assert_equal(nil, next(mapping("]e")))
    assert_equal(nil, next(mapping("[e")))
    assert_true(canvas.close(session))
    config.reset()
  end)

  it("shows contextual actions and diagnoses an offscreen populated plan", function()
    local config = require("roomplan.config")
    local canvas = require("roomplan.render.canvas")
    config.setup({ canvas = { open = "split" } })
    local plan = {
      rooms = {
        { id = "room-far", name = "Far room", origin_mm = { 0, 0 }, size_mm = { 5000, 4000 } },
      },
      doors = {}, furniture = {}, settings = { grid_mm = 100 },
    }
    local session = {
      id = "session-offscreen-canvas",
      source = { path = "/tmp/offscreen-canvas.roomplan.json", bufnr = vim.api.nvim_get_current_buf() },
      canvas = {}, validation = {}, selection = { kind = "room", id = "room-far" },
      mode = "NAV", snap_enabled = true, workflow = { generation = 0, kind = nil },
      viewport = fixed_view(100000, 100000, 100, 200),
    }
    function session:model() return plan end
    function session:status_text() return "[SAVED]" end

    local handle = canvas.open(session)
    local lines = vim.api.nvim_buf_get_lines(handle.buf, 0, -1, false)
    assert_true(table.concat(lines, "\n"):find("outside the viewport", 1, true) ~= nil)
    assert_true(lines[1]:find("room: Far room", 1, true) ~= nil)
    assert_true(lines[#lines]:find("ROOM", 1, true) ~= nil)
    assert_true(lines[#lines]:find("[A] Align", 1, true) ~= nil)

    local output = assert(canvas.redraw(handle, nil, nil, { fit = true, focus_selection = true }))
    assert_equal(nil, output.chrome_state)
    assert_true(#canvas.hit_candidates(session) > 0)
    session.mode = "MOVE"
    canvas.redraw(handle)
    lines = vim.api.nvim_buf_get_lines(handle.buf, 0, -1, false)
    assert_true(lines[#lines]:find("MOVE", 1, true) ~= nil)
    assert_true(lines[#lines]:find("[Ctrl-h/j/k/l] Fine", 1, true) ~= nil)
    assert_true(canvas.close(session))
    config.reset()
  end)

  it("adapts the controller session API without importing state", function()
    local config = require("roomplan.config")
    local canvas = require("roomplan.render.canvas")
    config.setup({ canvas = { open = "split" } })
    local model = {
      rooms = {
        { id = "room-a", name = "A", origin_mm = { 0, 0 }, size_mm = { 1000, 1000 } },
      },
      doors = {},
      furniture = {},
      settings = { grid_mm = 100 },
    }
    local wiped = false
    local source_buffer = vim.api.nvim_get_current_buf()
    local source_window = vim.api.nvim_get_current_win()
    local session = {
      id = "session-render-test",
      source = { path = "/tmp/render-test.roomplan.json", bufnr = source_buffer },
      canvas = {},
      validation = {},
      selection = { kind = "room", id = "room-a" },
      mode = "NAV",
      snap_enabled = true,
    }
    function session:model() return model end
    function session:status_text() return "[SAVED]" end
    local handle = canvas.open(session, { on_wipe = function() wiped = true end })
    assert_equal(handle.buf, session.canvas.bufnr)
    assert_equal(handle.win, session.canvas.winid)
    assert_true(session.viewport ~= nil)
    assert_true(canvas.set_logical_cursor(handle, 2, 2))
    local controller_cursor = assert(canvas.logical_cursor(session))
    assert_equal(1, controller_cursor.row)
    assert_equal(1, controller_cursor.column)
    assert_true(canvas.set_logical_cursor(session, 0, 0))
    controller_cursor = assert(canvas.logical_cursor(session))
    assert_equal(0, controller_cursor.row)
    assert_equal(0, controller_cursor.column)
    -- Leave only the canvas window. Closing it must reveal the source buffer,
    -- never a session guard, because Neovim cannot close its final window.
    vim.api.nvim_win_close(source_window, true)
    assert_equal(1, #vim.api.nvim_list_wins())
    assert_true(canvas.close(session))
    assert_equal(source_buffer, vim.api.nvim_get_current_buf())
    assert_equal(true, wiped)
    assert_equal(nil, session.canvas.bufnr)
    config.reset()
  end)
end)
