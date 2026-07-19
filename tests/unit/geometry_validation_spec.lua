local actions = require("roomplan.actions")
local geometry = require("roomplan.geometry")
local json = require("roomplan.codec.json")
local current_model = require("roomplan.model")
local schema = require("roomplan.schema")
local validate = require("roomplan.validate")

-- This file is the schema-v1 geometry compatibility suite. Compound/current-
-- schema behavior lives in the focused compound specs, so keep these fixtures
-- explicitly on v1 instead of making them follow CURRENT_VERSION implicitly.
local V1 = { schema_version = 1 }
local model = setmetatable({
  new = function(options)
    local value, err = current_model.new(options)
    if not value then return nil, err end
    value.schema_version = 1
    return schema.normalize_versioned(value)
  end,
  new_room = function(fields) return current_model.new_room(fields, V1) end,
  new_door = function(fields) return current_model.new_door(fields, V1) end,
  new_furniture = function(fields) return current_model.new_furniture(fields, V1) end,
  new_custom_template = function(fields) return current_model.new_custom_template(fields, V1) end,
}, { __index = current_model })

local function base_model() return assert(model.new({ name = "Geometry test" })) end

local function room(id, x, y, width, depth)
  return model.new_room({ id = id, name = id, origin_mm = { x, y }, size_mm = { width, depth } })
end

local function add(model_value, collection, entity)
  model_value[collection][#model_value[collection] + 1] = entity
  return entity
end

local function codes(diagnostics)
  local result = {}
  for _, value in ipairs(diagnostics) do
    result[value.code] = (result[value.code] or 0) + 1
  end
  return result
end

local function approximate(actual, expected, epsilon)
  if math.abs(actual - expected) > (epsilon or 1e-6) then
    error(string.format("expected %.12g to approximate %.12g", actual, expected), 2)
  end
end

describe("pure geometry", function()
  it("normalizes v1 rectangles into exact one-part footprints", function()
    local owner = room("room-owner", -100, 25, 301, 199)
    local room_shape = assert(geometry.footprint.from_room(owner))
    assert_equal("rect_union", room_shape.kind)
    assert_equal(1, #room_shape.parts)
    assert_equal({
      id = "part-main",
      left2 = -200,
      bottom2 = 50,
      right2 = 402,
      top2 = 448,
    }, room_shape.parts[1])
    assert_equal({
      left2 = -200,
      bottom2 = 50,
      right2 = 402,
      top2 = 448,
      width2 = 602,
      depth2 = 398,
      center_x2 = 101,
      center_y2 = 249,
    }, assert(geometry.footprint.bounds2(room_shape)))

    local item = model.new_furniture({
      id = "furniture-odd",
      room_id = owner.id,
      name = "Odd",
      category = "test",
      center_mm = { -10, 11 },
      size_mm = { 5, 7, 99 },
      rotation_deg = 0,
    })
    local expected_sizes = {
      [0] = { 10, 14 },
      [90] = { 14, 10 },
      [180] = { 10, 14 },
      [270] = { 14, 10 },
    }
    for _, rotation in ipairs({ 0, 90, 180, 270 }) do
      item.rotation_deg = rotation
      local shape = assert(geometry.footprint.from_furniture(owner, item))
      local bounds = assert(geometry.footprint.bounds2(shape))
      assert_equal(expected_sizes[rotation][1], bounds.width2)
      assert_equal(expected_sizes[rotation][2], bounds.depth2)
      assert_equal(2 * (owner.origin_mm[1] + item.center_mm[1]), bounds.center_x2)
      assert_equal(2 * (owner.origin_mm[2] + item.center_mm[2]), bounds.center_y2)
      local legacy = geometry.rect.furniture_rect2(owner, item)
      assert_equal(bounds.left2, legacy.left2)
      assert_equal(bounds.right2, legacy.right2)
      assert_equal(bounds.bottom2, legacy.bottom2)
      assert_equal(bounds.top2, legacy.top2)
      assert_equal(bounds.center_x2, legacy.center_x2)
      assert_equal(bounds.center_y2, legacy.center_y2)
    end

    local asymmetric = assert(geometry.footprint.rectangle2(0, 0, 8, 4))
    local rotated = assert(geometry.footprint.rotate_quarter(asymmetric, 90, 0, 0))
    assert_equal({ left2 = -4, bottom2 = 0, right2 = 0, top2 = 8 }, rotated.parts[1])
    local translated = assert(geometry.footprint.translate2(rotated, 10, -6))
    assert_equal({ left2 = 6, bottom2 = -6, right2 = 10, top2 = 2 }, translated.parts[1])
  end)

  it("applies exact rect-union containment and contact semantics", function()
    local outer = assert(geometry.footprint.normalize({
      kind = "rect_union",
      parts = {
        { left2 = 0, bottom2 = 0, right2 = 10, top2 = 20 },
        { left2 = 10, bottom2 = 0, right2 = 20, top2 = 20 },
      },
    }))
    local across_seam = assert(geometry.footprint.rectangle2(5, 5, 15, 15))
    local touching = assert(geometry.footprint.rectangle2(20, 5, 24, 15))
    local overlapping = assert(geometry.footprint.rectangle2(19, 5, 24, 15))
    assert_true(geometry.footprint.contains(outer, across_seam))
    assert_equal(false, geometry.footprint.overlaps_positive(outer, touching))
    assert_true(geometry.footprint.overlaps_positive(outer, overlapping))

    local invalid, err = geometry.footprint.normalize({
      kind = "rect_union",
      parts = {
        { left2 = 0, bottom2 = 0, right2 = 10, top2 = 10 },
        { left2 = 5, bottom2 = 5, right2 = 15, top2 = 15 },
      },
    })
    assert_equal(nil, invalid)
    assert_equal("FOOTPRINT_PART_OVERLAP", err.code)
  end)

  it("distinguishes boundary contact from positive overlap", function()
    local a = geometry.rect.new(0, 0, 100, 100)
    local touching = geometry.rect.new(100, 0, 50, 50)
    local overlap = geometry.rect.new(99, 0, 50, 50)
    assert_true(not geometry.rect.overlaps_positive(a, touching))
    assert_true(geometry.rect.intersects_closed(a, touching))
    assert_true(geometry.rect.overlaps_positive(a, overlap))
    assert_true(geometry.rect.contains_point(a, 100, 50))
  end)

  it("keeps odd furniture edges exact in doubled coordinates", function()
    local owner = room("room-owner", -10, -20, 100, 100)
    local item = model.new_furniture({
      id = "furniture-odd",
      room_id = owner.id,
      name = "Odd",
      category = "test",
      center_mm = { 10, 11 },
      size_mm = { 5, 7, 10 },
      rotation_deg = 0,
    })
    local bounds = geometry.rect.furniture_rect2(owner, item)
    assert_equal(bounds.left2, -5)
    assert_equal(bounds.right2, 5)
    assert_equal(bounds.bottom2, -25)
    assert_equal(bounds.top2, -11)
    item.rotation_deg = 90
    bounds = geometry.rect.furniture_rect2(owner, item)
    assert_equal(bounds.right2 - bounds.left2, 14)
    assert_equal(bounds.top2 - bounds.bottom2, 10)
  end)

  it("keeps the rectangle facade tolerant for repair geometry", function()
    local owner = {
      id = "room-repair",
      origin_mm = { 0.25, -0.5 },
      size_mm = { 10.5, 20.25 },
    }
    assert_equal({
      left = 0.25,
      bottom = -0.5,
      right = 10.75,
      top = 19.75,
      width = 10.5,
      depth = 20.25,
    }, geometry.rect.from_room(owner))
    local item = {
      center_mm = { 5, 6 },
      size_mm = { 7, 9, 10 },
      rotation_deg = 45,
    }
    assert_equal({
      left2 = 3.5,
      right2 = 17.5,
      bottom2 = 2,
      top2 = 20,
      center_x2 = 10.5,
      center_y2 = 11,
    }, geometry.rect.furniture_rect2(owner, item))
  end)

  it("rounds parity-mismatched centre alignment away from zero", function()
    local moving = room("room-moving", 0, 0, 3, 2)
    local reference = room("room-reference", 0, 0, 4, 2)
    local proposed = assert(geometry.alignment.propose(moving, reference, "align_center_x"))
    assert_equal(proposed.origin_mm[1], 1)
    assert_equal(proposed.residual_mm.x, 0.5)
    assert_equal(proposed.diagnostics[1].code, "ALIGNMENT_ROUNDED")
    reference.origin_mm[1] = -4
    proposed = assert(geometry.alignment.propose(moving, reference, "align_center_x"))
    assert_equal(proposed.origin_mm[1], -4)
    assert_equal(proposed.residual_mm.x, -0.5)
  end)

  it("implements every directional and edge alignment operation", function()
    local moving = room("room-moving", 20, 30, 40, 20)
    local reference = room("room-reference", 100, 200, 80, 60)
    local cases = {
      align_min_x = { 100, 30 },
      align_max_x = { 140, 30 },
      align_min_y = { 20, 200 },
      align_max_y = { 20, 240 },
      place_east = { 185, 200 },
      place_west = { 55, 200 },
      place_north = { 100, 265 },
      place_south = { 100, 175 },
    }
    for operation, expected in pairs(cases) do
      local result = assert(geometry.alignment.propose(moving, reference, operation, { gap_mm = 5 }))
      assert_equal(result.origin_mm, expected, operation)
    end
    local corner = assert(geometry.alignment.snap_corner(moving, reference, "northeast", "southwest"))
    assert_equal(corner.origin_mm, { 60, 180 })
  end)

  it("detects positive shared edges but not corner-only contact", function()
    local a = room("room-a", 0, 0, 100, 100)
    local b = room("room-b", 100, 20, 50, 60)
    local relation = assert(geometry.adjacency.between(a, b))
    assert_equal(relation.a_side, "east")
    assert_equal(relation.start_mm, 20)
    assert_equal(relation.finish_mm, 80)
    b.origin_mm = { 100, 100 }
    assert_equal(geometry.adjacency.between(a, b), nil)
  end)

  it("ranks snapping deterministically and rounds negative grids", function()
    assert_equal(geometry.number.round_to_grid(-149, 100), -100)
    assert_equal(geometry.number.round_to_grid(-150, 100), -200)
    local best = geometry.snapping.choose_axis({ geometry.snapping.feature("x", 0, "room_edge", "moving", "west") }, {
      geometry.snapping.feature("x", 10, "grid", "grid", "5"),
      geometry.snapping.feature("x", -10, "door", "door-a", "start"),
    }, 5, { axis = "x", priority = { "door", "grid" } })
    assert_equal(best.target.kind, "door")
    assert_equal(best.delta2, -10)
    local bypass = geometry.snapping.resolve({ bypass = true })
    assert_true(not bypass.snapped)
  end)

  it("chooses the first wall crossed by a directional step", function()
    local moving = {
      geometry.snapping.feature("x", 4100, "room_edge", "moving", "east", { 0, 2000 }),
    }
    local targets = {
      geometry.snapping.feature("x", 4000, "room_edge", "far", "west", { 0, 2000 }),
      geometry.snapping.feature("x", 3960, "room_edge", "near", "west", { 0, 2000 }),
    }
    local best = geometry.snapping.choose_axis(moving, targets, 10, {
      axis = "x",
      sweep_mm = 100,
      require_overlap = true,
    })
    assert_equal("near", best.target.id)
    assert_equal(-70, best.delta_mm)

    local away = geometry.snapping.choose_axis(
      {
        geometry.snapping.feature("x", 3800, "room_edge", "moving", "east", { 0, 2000 }),
      },
      {
        geometry.snapping.feature("x", 4000, "room_edge", "touching", "west", { 0, 2000 }),
      },
      10,
      {
        axis = "x",
        sweep_mm = -100,
        require_overlap = true,
      }
    )
    assert_equal(nil, away)
  end)

  it("retains every coincident wall segment after one snap correction", function()
    local moving = room("room-moving", 993, 1000, 1000, 1000)
    local lower = room("room-lower", 2000, 1000, 500, 500)
    local upper = room("room-upper", 2000, 1500, 500, 500)
    local snapped = geometry.snapping.snap_room(moving, { lower, upper }, {
      tolerance_mm = { x = 10, y = 0 },
      priority = { "room_edge", "grid" },
    })
    assert_equal({ 1000, 1000 }, snapped.origin_mm)
    local guides = geometry.snapping.guides(snapped)
    assert_equal(2, #guides)
    assert_equal({ 1000, 1500 }, { guides[1].overlap_start_mm, guides[1].overlap_finish_mm })
    assert_equal({ 1500, 2000 }, { guides[2].overlap_start_mm, guides[2].overlap_finish_mm })
    assert_true(guides[1].target_label ~= guides[2].target_label)

    local vertical = geometry.snapping.snap_room(room("room-moving-y", 1000, 993, 1000, 1000), {
      room("room-left", 1000, 2000, 500, 500),
      room("room-right", 1500, 2000, 500, 500),
    }, {
      tolerance_mm = { x = 0, y = 10 },
      priority = { "room_edge", "grid" },
    })
    assert_equal({ 1000, 1000 }, vertical.origin_mm)
    local vertical_guides = geometry.snapping.guides(vertical)
    assert_equal(2, #vertical_guides)
    assert_equal("y", vertical_guides[1].axis)
    assert_equal({ 1000, 1500 }, {
      vertical_guides[1].overlap_start_mm,
      vertical_guides[1].overlap_finish_mm,
    })
    assert_equal({ 1500, 2000 }, {
      vertical_guides[2].overlap_start_mm,
      vertical_guides[2].overlap_finish_mm,
    })
  end)

  it("keeps exact contact feedback when magnetic snapping is disabled", function()
    local value = base_model()
    add(value, "rooms", room("room-south", 0, 0, 1000, 1000))
    add(value, "rooms", room("room-north", 0, 1100, 1000, 1000))
    local changed, result = actions.apply(value, {
      type = "move_room",
      id = "room-north",
      delta_mm = { 0, -100 },
    }, { snapping = false })
    assert_equal({ 0, 1000 }, assert(changed).rooms[2].origin_mm)
    local guides = geometry.snapping.guides(assert(result).metadata.snapping)
    assert_equal(1, #guides)
    assert_equal("y", guides[1].axis)
    assert_equal(true, guides[1].contact_only)
    assert_equal(nil, geometry.snapping.summary(guides))
  end)

  it("computes aperture and handed swing for every side and hinge", function()
    local owner = room("room-owner", 100, 200, 1000, 800)
    local sides = { "north", "east", "south", "west" }
    local hinges = { "start", "end" }
    local targets = { "owner", "outside" }
    for _, side in ipairs(sides) do
      for _, hinge in ipairs(hinges) do
        for _, target in ipairs(targets) do
          local door = model.new_door({
            id = "door-test",
            room_id = owner.id,
            side = side,
            offset_mm = 100,
            width_mm = 300,
            hinge = hinge,
            opens_into = target,
            open_angle_deg = 90,
          })
          local swing = assert(geometry.door.swing(owner, door))
          local normal = geometry.adjacency.normal(side, target ~= "owner")
          local dx = swing.open_endpoint.x - swing.hinge.x
          local dy = swing.open_endpoint.y - swing.hinge.y
          approximate(dx, normal[1] * 300)
          approximate(dy, normal[2] * 300)
          approximate(swing.radius, 300)
        end
      end
    end
  end)

  it("handles sector rectangle tangency and misses", function()
    local value = geometry.sector.new({ 0, 0 }, { 10, 0 }, math.pi / 2)
    assert_true(geometry.sector.intersects_rect(value, { left = 5, right = 6, bottom = 5, top = 6 }))
    assert_true(geometry.sector.intersects_rect(value, { left = 10, right = 11, bottom = 0, top = 1 }))
    assert_true(not geometry.sector.intersects_rect(value, { left = -6, right = -5, bottom = 5, top = 6 }))
  end)

  it("keeps sector predicates stable at huge world origins", function()
    local origin = 2 ^ 49
    local near = geometry.sector.new({ origin, -origin }, { origin + 900, -origin }, math.pi / 2)
    local local_sector = geometry.sector.new({ 0, 0 }, { 900, 0 }, math.pi / 2)
    local huge_hit = geometry.sector.intersects_rect(near, {
      left = origin + 400.5,
      right = origin + 500.5,
      bottom = -origin + 400.5,
      top = -origin + 500.5,
    })
    local local_hit = geometry.sector.intersects_rect(local_sector, {
      left = 400.5,
      right = 500.5,
      bottom = 400.5,
      top = 500.5,
    })
    assert_equal(huge_hit, local_hit)
    assert_true(huge_hit)
  end)
end)

describe("structured validation", function()
  it("accepts boundary-touching rooms and diagnoses positive overlap", function()
    local value = base_model()
    add(value, "rooms", room("room-a", 0, 0, 100, 100))
    add(value, "rooms", room("room-b", 100, 0, 100, 100))
    assert_equal(#validate.run(value), 0)
    value.rooms[2].origin_mm[1] = 99
    local diagnostics = validate.run(value)
    assert_equal(codes(diagnostics).ROOM_OVERLAP, 1)
    assert_equal(diagnostics[1].object.id, "room-a")
    assert_equal(diagnostics[1].related[1].id, "room-b")
  end)

  it("reports furniture containment, overlap, references, and template warnings", function()
    local value = base_model()
    add(value, "rooms", room("room-a", 0, 0, 100, 100))
    add(
      value,
      "furniture",
      model.new_furniture({
        id = "furniture-a",
        room_id = "room-a",
        template_id = "builtin:sofa",
        name = "A",
        category = "test",
        center_mm = { 5, 5 },
        size_mm = { 20, 20, 10 },
        rotation_deg = 0,
      })
    )
    add(
      value,
      "furniture",
      model.new_furniture({
        id = "furniture-b",
        room_id = "room-a",
        template_id = "custom:missing",
        name = "B",
        category = "test",
        center_mm = { 10, 10 },
        size_mm = { 20, 20, 10 },
        rotation_deg = 0,
      })
    )
    add(
      value,
      "furniture",
      model.new_furniture({
        id = "furniture-orphan",
        room_id = "room-missing",
        template_id = "builtin:chair",
        name = "Orphan",
        category = "test",
        center_mm = { 0, 0 },
        size_mm = { 20, 20, 10 },
        rotation_deg = 0,
      })
    )
    local found = codes(validate.run(value))
    -- The orphan has no safe world geometry, so it gets INVALID_REFERENCE but
    -- not an invented containment diagnostic.
    assert_equal(found.FURNITURE_OUTSIDE_ROOM, 1)
    assert_equal(found.FURNITURE_OVERLAP, 1)
    assert_equal(found.INVALID_REFERENCE, 1)
    assert_equal(found.TEMPLATE_UNRESOLVED, 1)
  end)

  it("validates connected, missing, exterior, and overlapping apertures", function()
    local value = base_model()
    add(value, "rooms", room("room-a", 0, 0, 1000, 1000))
    add(value, "rooms", room("room-b", 1000, 0, 1000, 1000))
    add(
      value,
      "doors",
      model.new_door({
        id = "door-missing",
        room_id = "room-a",
        side = "east",
        offset_mm = 100,
        width_mm = 300,
        hinge = "start",
        opens_into = "owner",
        open_angle_deg = 90,
      })
    )
    add(
      value,
      "doors",
      model.new_door({
        id = "door-connected",
        room_id = "room-b",
        connects_to_room_id = "room-a",
        side = "west",
        offset_mm = 200,
        width_mm = 300,
        hinge = "end",
        opens_into = "connected",
        open_angle_deg = 90,
      })
    )
    local found = codes(validate.run(value))
    assert_equal(found.DOOR_CONNECTION_MISSING, 1)
    assert_equal(found.DOOR_OPENING_OVERLAP, 1)
  end)

  it("preserves JSON null as an exterior connection", function()
    local value = base_model()
    add(value, "rooms", room("room-a", 0, 0, 1000, 1000))
    local door = model.new_door({
      id = "door-outside",
      room_id = "room-a",
      side = "south",
      offset_mm = 100,
      width_mm = 300,
      hinge = "start",
      opens_into = "outside",
      open_angle_deg = 90,
    })
    assert_true(json.is_null(door.connects_to_room_id))
    add(value, "doors", door)
    local diagnostics, summary = validate.run(value)
    assert_equal(summary.errors, 0)
    assert_equal(codes(diagnostics).INVALID_REFERENCE, nil)
  end)

  it("reports a swept-door furniture collision as a warning", function()
    local value = base_model()
    add(value, "rooms", room("room-a", 0, 0, 1000, 1000))
    add(
      value,
      "doors",
      model.new_door({
        id = "door-a",
        room_id = "room-a",
        side = "south",
        offset_mm = 100,
        width_mm = 300,
        hinge = "start",
        opens_into = "owner",
        open_angle_deg = 90,
      })
    )
    add(
      value,
      "furniture",
      model.new_furniture({
        id = "furniture-a",
        room_id = "room-a",
        template_id = "builtin:chair",
        name = "Chair",
        category = "seating",
        center_mm = { 200, 150 },
        size_mm = { 100, 100, 100 },
        rotation_deg = 0,
      })
    )
    local found = codes(validate.run(value))
    assert_equal(found.DOOR_SWING_FURNITURE, 1)
  end)

  it("classifies structural duplicate IDs and unsupported rotations", function()
    local value = base_model()
    add(value, "rooms", room("room-duplicate", 0, 0, 100, 100))
    add(value, "rooms", room("room-duplicate", 100, 0, 100, 100))
    add(
      value,
      "furniture",
      model.new_furniture({
        id = "furniture-bad",
        room_id = "room-duplicate",
        template_id = "builtin:chair",
        name = "Bad",
        category = "test",
        center_mm = { 10, 10 },
        size_mm = { 10, 10, 10 },
        rotation_deg = 0,
      })
    )
    value.furniture[1].rotation_deg = 45
    local diagnostics, summary = validate.run(value)
    local found = codes(diagnostics)
    assert_equal(found.DUPLICATE_ID, 1)
    assert_equal(found.UNSUPPORTED_ROTATION, 1)
    assert_equal(summary.structural_errors, 2)
  end)

  it("reports aperture bounds, invalid connection, obstruction, and swing target", function()
    local value = base_model()
    add(value, "rooms", room("room-a", 0, 0, 1000, 1000))
    add(value, "rooms", room("room-partial", 1000, 200, 500, 200))
    add(
      value,
      "doors",
      model.new_door({
        id = "door-obstructed",
        room_id = "room-a",
        side = "east",
        offset_mm = 100,
        width_mm = 500,
        hinge = "start",
        opens_into = "outside",
        open_angle_deg = 90,
      })
    )
    add(
      value,
      "doors",
      model.new_door({
        id = "door-outside",
        room_id = "room-a",
        side = "north",
        offset_mm = 900,
        width_mm = 200,
        hinge = "start",
        opens_into = "outside",
        open_angle_deg = 90,
      })
    )
    add(
      value,
      "doors",
      model.new_door({
        id = "door-invalid-connection",
        room_id = "room-a",
        connects_to_room_id = "room-partial",
        side = "north",
        offset_mm = 100,
        width_mm = 200,
        hinge = "start",
        opens_into = "outside",
        open_angle_deg = 90,
      })
    )
    local found = codes(validate.run(value))
    assert_equal(found.DOOR_EXTERIOR_OBSTRUCTED, 1)
    assert_equal(found.DOOR_OUTSIDE_EDGE, 1)
    assert_equal(found.DOOR_CONNECTION_INVALID, 1)
    assert_equal(found.DOOR_SWING_TARGET_INVALID, 1)
  end)

  it("warns for wall tangency and pairwise door sweep interference", function()
    local value = base_model()
    add(value, "rooms", room("room-a", 0, 0, 1000, 1000))
    add(
      value,
      "doors",
      model.new_door({
        id = "door-south",
        room_id = "room-a",
        side = "south",
        offset_mm = 0,
        width_mm = 1000,
        hinge = "start",
        opens_into = "owner",
        open_angle_deg = 90,
      })
    )
    add(
      value,
      "doors",
      model.new_door({
        id = "door-west",
        room_id = "room-a",
        side = "west",
        offset_mm = 0,
        width_mm = 300,
        hinge = "start",
        opens_into = "owner",
        open_angle_deg = 90,
      })
    )
    local found = codes(validate.run(value))
    assert_true((found.DOOR_SWING_WALL or 0) >= 1)
    assert_equal(found.DOOR_SWING_DOOR, 1)
  end)

  it("enforces configured soft geometry limits separately from hard structure", function()
    local value = base_model()
    add(value, "rooms", room("room-a", 900, 0, 200, 100))
    add(
      value,
      "furniture",
      model.new_furniture({
        id = "furniture-a",
        room_id = "room-a",
        template_id = "builtin:chair",
        name = "Large",
        category = "test",
        center_mm = { 100, 50 },
        size_mm = { 150, 50, 50 },
        rotation_deg = 0,
      })
    )
    local diagnostics, summary = validate.run(value, {
      limits = { max_dimension_mm = 100, max_abs_coordinate_mm = 1000, max_plan_span_mm = 100 },
    })
    assert_true((codes(diagnostics).PLAN_LIMIT_EXCEEDED or 0) >= 3)
    assert_equal(summary.structural_errors, 0)
  end)

  it("reports exact geometry range failures without crashing", function()
    local limit = 2 ^ 50 - 1
    local value = base_model()
    add(value, "rooms", room("room-a", limit, 0, 100, 100))
    add(
      value,
      "furniture",
      model.new_furniture({
        id = "furniture-a",
        room_id = "room-a",
        template_id = "builtin:chair",
        name = "Chair",
        category = "seating",
        center_mm = { limit, 50 },
        size_mm = { 100, 100, 100 },
        rotation_deg = 0,
      })
    )

    assert_true(schema.validate_versioned(value))
    local diagnostics, summary = validate.run(value)
    assert_equal(codes(diagnostics).GEOMETRY_RANGE, 1)
    assert_equal(summary.structural_errors, 0)
    assert_true(summary.errors >= 1)

    local snapped = geometry.snapping.snap_furniture(value.rooms[1], value.furniture[1], {}, {}, {
      tolerance_mm = 100,
    })
    assert_equal(false, snapped.snapped)
    assert_equal(limit, snapped.center_mm[1])
    assert_equal("FOOTPRINT_RANGE", snapped.geometry_error.code)
  end)
end)

describe("atomic actions", function()
  it("snaps room and furniture edges crossed by a non-divisible move step", function()
    local room_plan = base_model()
    add(room_plan, "rooms", room("room-moving", 950, 0, 1000, 1000))
    add(room_plan, "rooms", room("room-fixed", 2000, 0, 1000, 1000))
    local moved_room = assert(actions.apply(room_plan, {
      type = "move_room",
      id = "room-moving",
      delta_mm = { 100, 0 },
    }, {
      snapping = {
        tolerance_mm = { x = 10, y = 10 },
        priority = { "room_edge", "furniture", "grid" },
      },
    }))
    assert_equal({ 1000, 0 }, moved_room.rooms[1].origin_mm)

    local furniture_plan = base_model()
    add(furniture_plan, "rooms", room("room-owner", 0, 0, 2000, 2000))
    add(
      furniture_plan,
      "furniture",
      model.new_furniture({
        id = "furniture-moving",
        room_id = "room-owner",
        template_id = "builtin:chair",
        name = "Chair",
        category = "seating",
        center_mm = { 1700, 1000 },
        size_mm = { 500, 500, 800 },
        rotation_deg = 0,
      })
    )
    local moved_furniture = assert(actions.apply(furniture_plan, {
      type = "move_furniture",
      id = "furniture-moving",
      delta_mm = { 100, 0 },
    }, {
      snapping = {
        tolerance_mm = { x = 10, y = 10 },
        priority = { "room_edge", "furniture", "grid" },
      },
    }))
    assert_equal({ 1750, 1000 }, moved_furniture.furniture[1].center_mm)
  end)

  it("keeps newly placed furniture selected when also saving its template", function()
    local value = base_model()
    add(value, "rooms", room("room-a", 0, 0, 1000, 1000))
    local changed, result = actions.apply(value, {
      type = "add_furniture",
      furniture = {
        id = "furniture-desk",
        room_id = "room-a",
        template_id = "custom:desk",
        name = "Desk",
        category = "work",
        center_mm = { 500, 500 },
        size_mm = { 500, 300, 750 },
        rotation_deg = 0,
      },
      custom_template = {
        id = "custom:desk",
        name = "Desk",
        category = "work",
        shape = "rectangle",
        default_size_mm = { 500, 300, 750 },
      },
    })
    assert_true(changed ~= nil, result and result.message)
    assert_equal({ kind = "furniture", id = "furniture-desk" }, result.touched[1])
    assert_equal({ kind = "template", id = "custom:desk" }, result.touched[2])
  end)

  it("accepts only the canonical documented action shape", function()
    local value = base_model()
    local draft = { id = "room-a", name = "A", origin_mm = { 0, 0 }, size_mm = { 100, 100 } }
    local changed, err = actions.apply(value, { action = "add_room", room = draft })
    assert_equal(nil, changed)
    assert_equal("UNKNOWN_ACTION", err.code)
    changed, err = actions.apply(value, { type = "add_room", entity = draft })
    assert_equal(nil, changed)
    assert_equal("INVALID_ACTION", err.code)
  end)

  it("canonicalizes plain UI drafts into safely encodable tagged JSON", function()
    local value = base_model()
    local changed, result = actions.apply(value, {
      type = "add_room",
      room = {
        id = "room-plain",
        name = "Plain",
        origin_mm = { 0, 0 },
        size_mm = { 100, 100 },
        vendor = { flags = { "a", "b" }, empty = {} },
      },
    })
    assert_true(changed ~= nil, result and result.message)
    assert_true(json.is_object(changed.rooms[1]))
    assert_true(json.is_array(changed.rooms[1].origin_mm))
    assert_true(json.is_object(changed.rooms[1].vendor))
    assert_true(json.is_array(changed.rooms[1].vendor.flags))
    assert_true(json.is_object(changed.rooms[1].vendor.empty))
    assert_true(json.encode(changed) ~= nil)
  end)

  it("does not mutate input and blocks or records forced room overlap", function()
    local value = base_model()
    add(value, "rooms", room("room-a", 0, 0, 100, 100))
    add(value, "rooms", room("room-b", 100, 0, 100, 100))
    local changed, err = actions.apply(value, { type = "move_room", id = "room-b", delta_mm = { -1, 0 } })
    assert_equal(changed, nil)
    assert_equal(err.code, "LAYOUT_BLOCKED")
    assert_equal(value.rooms[2].origin_mm, { 100, 0 })
    changed, err = actions.apply(value, { type = "move_room", id = "room-b", delta_mm = { -1, 0 }, force = true })
    assert_true(changed ~= nil)
    assert_true(err.metadata.forced)
    assert_equal(changed.rooms[2].origin_mm, { 99, 0 })
    assert_equal(value.rooms[2].origin_mm, { 100, 0 })
  end)

  it("allows invalid furniture drafts and identifies no-op edits", function()
    local value = base_model()
    add(value, "rooms", room("room-a", 0, 0, 100, 100))
    add(
      value,
      "furniture",
      model.new_furniture({
        id = "furniture-a",
        room_id = "room-a",
        template_id = "builtin:chair",
        name = "Chair",
        category = "seating",
        center_mm = { 50, 50 },
        size_mm = { 50, 50, 50 },
        rotation_deg = 0,
      })
    )
    local changed, result = actions.apply(value, {
      type = "move_furniture",
      id = "furniture-a",
      center_mm = { -100, -100 },
      exact = true,
    })
    assert_true(changed ~= nil)
    assert_equal(codes(result.validation).FURNITURE_OUTSIDE_ROOM, 1)
    changed, result = actions.apply(value, {
      type = "move_furniture",
      id = "furniture-a",
      center_mm = { 50, 50 },
      exact = true,
    })
    assert_equal(changed, nil)
    assert_equal(result.code, "NO_CHANGE")
  end)

  it("cascade-deletes every room dependant in one result", function()
    local value = base_model()
    add(value, "rooms", room("room-a", 0, 0, 1000, 1000))
    add(value, "rooms", room("room-b", 1000, 0, 1000, 1000))
    add(
      value,
      "furniture",
      model.new_furniture({
        id = "furniture-a",
        room_id = "room-a",
        template_id = "builtin:chair",
        name = "Chair",
        category = "seating",
        center_mm = { 500, 500 },
        size_mm = { 100, 100, 100 },
        rotation_deg = 0,
      })
    )
    add(
      value,
      "doors",
      model.new_door({
        id = "door-a",
        room_id = "room-b",
        connects_to_room_id = "room-a",
        side = "west",
        offset_mm = 100,
        width_mm = 300,
        hinge = "start",
        opens_into = "connected",
        open_angle_deg = 90,
      })
    )
    local changed, result = actions.apply(value, { type = "delete_room_cascade", id = "room-a" })
    assert_true(changed ~= nil)
    assert_equal(#changed.rooms, 1)
    assert_equal(#changed.furniture, 0)
    assert_equal(#changed.doors, 0)
    assert_equal(result.metadata.deleted_dependencies.connected_doors, { "door-a" })
  end)

  it("blocks deleting a referenced custom template", function()
    local value = base_model()
    add(value, "rooms", room("room-a", 0, 0, 1000, 1000))
    add(
      value,
      "custom_templates",
      model.new_custom_template({
        id = "custom:chair",
        name = "Chair",
        category = "test",
        default_size_mm = { 100, 100, 100 },
      })
    )
    add(
      value,
      "furniture",
      model.new_furniture({
        id = "furniture-a",
        room_id = "room-a",
        template_id = "custom:chair",
        name = "Chair",
        category = "test",
        center_mm = { 500, 500 },
        size_mm = { 100, 100, 100 },
        rotation_deg = 0,
      })
    )
    local changed, err = actions.apply(value, { type = "delete_custom_template", id = "custom:chair" })
    assert_equal(changed, nil)
    assert_equal(err.code, "TEMPLATE_IN_USE")
    assert_equal(err.details.references, { "furniture-a" })
  end)

  it("commits door, furniture, template, metadata, and settings edits atomically", function()
    local value = base_model()
    value.settings.default_wall_thickness_mm = json.decimal(1, "120", 0)
    add(value, "rooms", room("room-a", 0, 0, 1000, 1000))
    add(value, "rooms", room("room-b", 1000, 0, 1000, 1000))
    add(
      value,
      "doors",
      model.new_door({
        id = "door-a",
        room_id = "room-a",
        connects_to_room_id = "room-b",
        side = "east",
        offset_mm = 100,
        width_mm = 300,
        hinge = "start",
        opens_into = "connected",
        open_angle_deg = 90,
      })
    )
    add(
      value,
      "furniture",
      model.new_furniture({
        id = "furniture-a",
        room_id = "room-a",
        template_id = "builtin:chair",
        name = "Chair",
        category = "seating",
        center_mm = { 500, 500 },
        size_mm = { 100, 100, 100 },
        rotation_deg = 0,
      })
    )
    add(
      value,
      "custom_templates",
      model.new_custom_template({
        id = "custom:desk",
        name = "Desk",
        category = "work",
        default_size_mm = { 100, 100, 100 },
      })
    )

    local result
    value, result = actions.apply(value, { type = "toggle_door_hinge", id = "door-a" })
    assert_equal(value.doors[1].hinge, "end")
    value, result = actions.apply(value, { type = "toggle_door_swing", id = "door-a" })
    assert_equal(value.doors[1].opens_into, "owner")
    value, result = actions.apply(value, { type = "rotate_furniture", id = "furniture-a" })
    assert_equal(value.furniture[1].rotation_deg, 90)
    value, result = actions.apply(value, {
      type = "change_furniture_template",
      id = "furniture-a",
      template_id = "custom:desk",
      category = "work",
    })
    assert_equal(value.furniture[1].size_mm, { 100, 100, 100 })
    assert_equal(value.furniture[1].template_id, "custom:desk")
    value, result = actions.apply(value, {
      type = "edit_custom_template",
      id = "custom:desk",
      patch = { default_size_mm = { 200, 100, 100 } },
    })
    assert_true(json.is_array(value.custom_templates[1].default_size_mm))
    value, result = actions.apply(value, { type = "edit_metadata", patch = { name = "Edited" } })
    assert_equal(value.metadata.name, "Edited")
    value, result = actions.apply(value, { type = "edit_plan_settings", patch = { grid_mm = 50 } })
    assert_equal(value.settings.grid_mm, 50)
    value, result = actions.apply(value, {
      type = "edit_plan",
      metadata = { name = "Atomic plan edit", notes = "one history entry" },
      settings = { grid_mm = 75, normal_step_mm = 150 },
    })
    assert_equal("Atomic plan edit", value.metadata.name)
    assert_equal(75, value.settings.grid_mm)
    assert_equal(150, value.settings.normal_step_mm)
    assert_true(json.is_decimal(value.settings.default_wall_thickness_mm))
    assert_true(json.encode(value) ~= nil)
  end)

  it("applies batch mutations atomically as one semantic result", function()
    local value = base_model()
    add(value, "rooms", room("room-a", 0, 0, 3000, 3000))
    for index, id in ipairs({ "furniture-a", "furniture-b" }) do
      add(
        value,
        "furniture",
        model.new_furniture({
          id = id,
          room_id = "room-a",
          template_id = "builtin:chair",
          name = id,
          category = "seating",
          center_mm = { index * 500, 1000 },
          size_mm = { 100, 100, 100 },
          rotation_deg = 0,
        })
      )
    end
    local changed, result = actions.apply(value, {
      type = "batch",
      label = "Move two chairs",
      actions = {
        { type = "move_furniture", id = "furniture-a", delta_mm = { 100, 0 }, exact = true },
        { type = "move_furniture", id = "furniture-b", delta_mm = { 100, 0 }, exact = true },
      },
    })
    assert_equal(600, changed.furniture[1].center_mm[1])
    assert_equal(1100, changed.furniture[2].center_mm[1])
    assert_equal("Move two chairs", result.label)
    assert_equal(2, #result.touched)

    local rejected, err = actions.apply(value, {
      type = "batch",
      actions = {
        { type = "move_furniture", id = "furniture-a", delta_mm = { 100, 0 }, exact = true },
        { type = "move_furniture", id = "missing", delta_mm = { 100, 0 }, exact = true },
      },
    })
    assert_equal(nil, rejected)
    assert_equal("NOT_FOUND", err.code)
    assert_equal(500, value.furniture[1].center_mm[1])
  end)
end)
