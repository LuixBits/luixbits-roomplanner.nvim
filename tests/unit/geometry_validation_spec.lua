local actions = require("roomplan.actions")
local geometry = require("roomplan.geometry")
local json = require("roomplan.codec.json")
local model = require("roomplan.model")
local validate = require("roomplan.validate")

local function base_model()
  return assert(model.new({ name = "Geometry test" }))
end

local function room(id, x, y, width, depth)
  return model.new_room({ id = id, name = id, origin_mm = { x, y }, size_mm = { width, depth } })
end

local function add(model_value, collection, entity)
  model_value[collection][#model_value[collection] + 1] = entity
  return entity
end

local function codes(diagnostics)
  local result = {}
  for _, value in ipairs(diagnostics) do result[value.code] = (result[value.code] or 0) + 1 end
  return result
end

local function approximate(actual, expected, epsilon)
  if math.abs(actual - expected) > (epsilon or 1e-6) then
    error(string.format("expected %.12g to approximate %.12g", actual, expected), 2)
  end
end

describe("pure geometry", function()
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
      id = "furniture-odd", room_id = owner.id, name = "Odd", category = "test",
      center_mm = { 10, 11 }, size_mm = { 5, 7, 10 }, rotation_deg = 0,
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
      align_min_x = { 100, 30 }, align_max_x = { 140, 30 },
      align_min_y = { 20, 200 }, align_max_y = { 20, 240 },
      place_east = { 185, 200 }, place_west = { 55, 200 },
      place_north = { 100, 265 }, place_south = { 100, 175 },
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
    local best = geometry.snapping.choose_axis(
      { geometry.snapping.feature("x", 0, "room_edge", "moving", "west") },
      {
        geometry.snapping.feature("x", 10, "grid", "grid", "5"),
        geometry.snapping.feature("x", -10, "door", "door-a", "start"),
      },
      5,
      { axis = "x", priority = { "door", "grid" } }
    )
    assert_equal(best.target.kind, "door")
    assert_equal(best.delta2, -10)
    local bypass = geometry.snapping.resolve({ bypass = true })
    assert_true(not bypass.snapped)
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
            id = "door-test", room_id = owner.id, side = side, offset_mm = 100,
            width_mm = 300, hinge = hinge, opens_into = target, open_angle_deg = 90,
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
      left = origin + 400.5, right = origin + 500.5,
      bottom = -origin + 400.5, top = -origin + 500.5,
    })
    local local_hit = geometry.sector.intersects_rect(local_sector, {
      left = 400.5, right = 500.5, bottom = 400.5, top = 500.5,
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
    add(value, "furniture", model.new_furniture({
      id = "furniture-a", room_id = "room-a", template_id = "builtin:sofa",
      name = "A", category = "test", center_mm = { 5, 5 }, size_mm = { 20, 20, 10 }, rotation_deg = 0,
    }))
    add(value, "furniture", model.new_furniture({
      id = "furniture-b", room_id = "room-a", template_id = "custom:missing",
      name = "B", category = "test", center_mm = { 10, 10 }, size_mm = { 20, 20, 10 }, rotation_deg = 0,
    }))
    add(value, "furniture", model.new_furniture({
      id = "furniture-orphan", room_id = "room-missing", template_id = "builtin:chair",
      name = "Orphan", category = "test", center_mm = { 0, 0 }, size_mm = { 20, 20, 10 }, rotation_deg = 0,
    }))
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
    add(value, "doors", model.new_door({
      id = "door-missing", room_id = "room-a", side = "east", offset_mm = 100,
      width_mm = 300, hinge = "start", opens_into = "owner", open_angle_deg = 90,
    }))
    add(value, "doors", model.new_door({
      id = "door-connected", room_id = "room-b", connects_to_room_id = "room-a", side = "west", offset_mm = 200,
      width_mm = 300, hinge = "end", opens_into = "connected", open_angle_deg = 90,
    }))
    local found = codes(validate.run(value))
    assert_equal(found.DOOR_CONNECTION_MISSING, 1)
    assert_equal(found.DOOR_OPENING_OVERLAP, 1)
  end)

  it("preserves JSON null as an exterior connection", function()
    local value = base_model()
    add(value, "rooms", room("room-a", 0, 0, 1000, 1000))
    local door = model.new_door({
      id = "door-outside", room_id = "room-a", side = "south", offset_mm = 100,
      width_mm = 300, hinge = "start", opens_into = "outside", open_angle_deg = 90,
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
    add(value, "doors", model.new_door({
      id = "door-a", room_id = "room-a", side = "south", offset_mm = 100,
      width_mm = 300, hinge = "start", opens_into = "owner", open_angle_deg = 90,
    }))
    add(value, "furniture", model.new_furniture({
      id = "furniture-a", room_id = "room-a", template_id = "builtin:chair",
      name = "Chair", category = "seating", center_mm = { 200, 150 },
      size_mm = { 100, 100, 100 }, rotation_deg = 0,
    }))
    local found = codes(validate.run(value))
    assert_equal(found.DOOR_SWING_FURNITURE, 1)
  end)

  it("classifies structural duplicate IDs and unsupported rotations", function()
    local value = base_model()
    add(value, "rooms", room("room-duplicate", 0, 0, 100, 100))
    add(value, "rooms", room("room-duplicate", 100, 0, 100, 100))
    add(value, "furniture", model.new_furniture({
      id = "furniture-bad", room_id = "room-duplicate", template_id = "builtin:chair",
      name = "Bad", category = "test", center_mm = { 10, 10 }, size_mm = { 10, 10, 10 }, rotation_deg = 0,
    }))
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
    add(value, "doors", model.new_door({
      id = "door-obstructed", room_id = "room-a", side = "east", offset_mm = 100,
      width_mm = 500, hinge = "start", opens_into = "outside", open_angle_deg = 90,
    }))
    add(value, "doors", model.new_door({
      id = "door-outside", room_id = "room-a", side = "north", offset_mm = 900,
      width_mm = 200, hinge = "start", opens_into = "outside", open_angle_deg = 90,
    }))
    add(value, "doors", model.new_door({
      id = "door-invalid-connection", room_id = "room-a", connects_to_room_id = "room-partial",
      side = "north", offset_mm = 100, width_mm = 200, hinge = "start",
      opens_into = "outside", open_angle_deg = 90,
    }))
    local found = codes(validate.run(value))
    assert_equal(found.DOOR_EXTERIOR_OBSTRUCTED, 1)
    assert_equal(found.DOOR_OUTSIDE_EDGE, 1)
    assert_equal(found.DOOR_CONNECTION_INVALID, 1)
    assert_equal(found.DOOR_SWING_TARGET_INVALID, 1)
  end)

  it("warns for wall tangency and pairwise door sweep interference", function()
    local value = base_model()
    add(value, "rooms", room("room-a", 0, 0, 1000, 1000))
    add(value, "doors", model.new_door({
      id = "door-south", room_id = "room-a", side = "south", offset_mm = 0,
      width_mm = 1000, hinge = "start", opens_into = "owner", open_angle_deg = 90,
    }))
    add(value, "doors", model.new_door({
      id = "door-west", room_id = "room-a", side = "west", offset_mm = 0,
      width_mm = 300, hinge = "start", opens_into = "owner", open_angle_deg = 90,
    }))
    local found = codes(validate.run(value))
    assert_true((found.DOOR_SWING_WALL or 0) >= 1)
    assert_equal(found.DOOR_SWING_DOOR, 1)
  end)

  it("enforces configured soft geometry limits separately from hard structure", function()
    local value = base_model()
    add(value, "rooms", room("room-a", 900, 0, 200, 100))
    add(value, "furniture", model.new_furniture({
      id = "furniture-a", room_id = "room-a", template_id = "builtin:chair",
      name = "Large", category = "test", center_mm = { 100, 50 },
      size_mm = { 150, 50, 50 }, rotation_deg = 0,
    }))
    local diagnostics, summary = validate.run(value, {
      limits = { max_dimension_mm = 100, max_abs_coordinate_mm = 1000, max_plan_span_mm = 100 },
    })
    assert_true((codes(diagnostics).PLAN_LIMIT_EXCEEDED or 0) >= 3)
    assert_equal(summary.structural_errors, 0)
  end)
end)

describe("atomic actions", function()
  it("canonicalizes plain UI drafts into safely encodable tagged JSON", function()
    local value = base_model()
    local changed, result = actions.apply(value, {
      type = "add_room",
      room = {
        id = "room-plain", name = "Plain", origin_mm = { 0, 0 }, size_mm = { 100, 100 },
        vendor = { flags = { "a", "b" }, empty = {} },
      },
    })
    assert_true(changed ~= nil, result and result.message)
    assert_true(json.is_object(changed.rooms[1]))
    assert_true(json.is_array(changed.rooms[1].origin_mm))
    assert_true(json.is_object(changed.rooms[1].vendor))
    assert_true(json.is_array(changed.rooms[1].vendor.flags))
    assert_true(json.is_object(changed.rooms[1].vendor.empty))
    assert_true(model.encode(changed) ~= nil)
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
    add(value, "furniture", model.new_furniture({
      id = "furniture-a", room_id = "room-a", template_id = "builtin:chair",
      name = "Chair", category = "seating", center_mm = { 50, 50 },
      size_mm = { 50, 50, 50 }, rotation_deg = 0,
    }))
    local changed, result = actions.apply(value, {
      type = "move_furniture", id = "furniture-a", center_mm = { -100, -100 }, exact = true,
    })
    assert_true(changed ~= nil)
    assert_equal(codes(result.validation).FURNITURE_OUTSIDE_ROOM, 1)
    changed, result = actions.apply(value, {
      type = "move_furniture", id = "furniture-a", center_mm = { 50, 50 }, exact = true,
    })
    assert_equal(changed, nil)
    assert_equal(result.code, "NO_CHANGE")
  end)

  it("cascade-deletes every room dependant in one result", function()
    local value = base_model()
    add(value, "rooms", room("room-a", 0, 0, 1000, 1000))
    add(value, "rooms", room("room-b", 1000, 0, 1000, 1000))
    add(value, "furniture", model.new_furniture({
      id = "furniture-a", room_id = "room-a", template_id = "builtin:chair",
      name = "Chair", category = "seating", center_mm = { 500, 500 }, size_mm = { 100, 100, 100 }, rotation_deg = 0,
    }))
    add(value, "doors", model.new_door({
      id = "door-a", room_id = "room-b", connects_to_room_id = "room-a", side = "west",
      offset_mm = 100, width_mm = 300, hinge = "start", opens_into = "connected", open_angle_deg = 90,
    }))
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
    add(value, "custom_templates", model.new_custom_template({
      id = "custom:chair", name = "Chair", category = "test", default_size_mm = { 100, 100, 100 },
    }))
    add(value, "furniture", model.new_furniture({
      id = "furniture-a", room_id = "room-a", template_id = "custom:chair",
      name = "Chair", category = "test", center_mm = { 500, 500 },
      size_mm = { 100, 100, 100 }, rotation_deg = 0,
    }))
    local changed, err = actions.apply(value, { type = "delete_custom_template", id = "custom:chair" })
    assert_equal(changed, nil)
    assert_equal(err.code, "TEMPLATE_IN_USE")
    assert_equal(err.details.references, { "furniture-a" })
  end)

  it("commits door, furniture, template, metadata, and settings edits atomically", function()
    local value = base_model()
    add(value, "rooms", room("room-a", 0, 0, 1000, 1000))
    add(value, "rooms", room("room-b", 1000, 0, 1000, 1000))
    add(value, "doors", model.new_door({
      id = "door-a", room_id = "room-a", connects_to_room_id = "room-b", side = "east",
      offset_mm = 100, width_mm = 300, hinge = "start", opens_into = "connected", open_angle_deg = 90,
    }))
    add(value, "furniture", model.new_furniture({
      id = "furniture-a", room_id = "room-a", template_id = "builtin:chair",
      name = "Chair", category = "seating", center_mm = { 500, 500 },
      size_mm = { 100, 100, 100 }, rotation_deg = 0,
    }))
    add(value, "custom_templates", model.new_custom_template({
      id = "custom:desk", name = "Desk", category = "work", default_size_mm = { 100, 100, 100 },
    }))

    local result
    value, result = actions.apply(value, { type = "toggle_door_hinge", id = "door-a" })
    assert_equal(value.doors[1].hinge, "end")
    value, result = actions.apply(value, { type = "toggle_door_swing", id = "door-a" })
    assert_equal(value.doors[1].opens_into, "owner")
    value, result = actions.apply(value, { type = "rotate_furniture", id = "furniture-a" })
    assert_equal(value.furniture[1].rotation_deg, 90)
    value, result = actions.apply(value, {
      type = "change_furniture_template", id = "furniture-a", template_id = "custom:desk", category = "work",
    })
    assert_equal(value.furniture[1].size_mm, { 100, 100, 100 })
    assert_equal(value.furniture[1].template_id, "custom:desk")
    value, result = actions.apply(value, {
      type = "edit_custom_template", id = "custom:desk", patch = { default_size_mm = { 200, 100, 100 } },
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
    assert_true(model.encode(value) ~= nil)
  end)
end)
