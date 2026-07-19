local json = require("roomplan.codec.json")
local model = require("roomplan.model")
local validate = require("roomplan.validate")

local function add(plan, collection, entity)
  plan[collection][#plan[collection] + 1] = entity
  return entity
end

local function room(id, x, y, width, depth)
  return model.new_room({
    id = id,
    name = id,
    origin_mm = { x, y },
    size_mm = { width, depth },
  })
end

local function plan_with_owner()
  local plan = assert(model.new({ name = "Wall attachment validation" }))
  add(plan, "rooms", room("room-owner", 0, 0, 4000, 3000))
  return plan
end

local function l_footprint()
  return json.object({
    kind = "rect_union",
    parts = json.array({
      json.object({
        id = "part-main",
        origin_mm = json.array({ 0, 0 }),
        size_mm = json.array({ 4000, 2000 }),
      }),
      json.object({
        id = "part-upper",
        origin_mm = json.array({ 0, 2000 }),
        size_mm = json.array({ 2000, 2000 }),
      }),
    }),
  })
end

local function codes(diagnostics)
  local result = {}
  for _, value in ipairs(diagnostics) do
    result[value.code] = (result[value.code] or 0) + 1
  end
  return result
end

local function diagnostic_for(diagnostics, code, kind)
  for _, value in ipairs(diagnostics) do
    if value.code == code and (kind == nil or value.object.kind == kind) then return value end
  end
end

local function window(fields)
  fields = fields or {}
  return model.new_window({
    id = fields.id or "window-main",
    room_id = fields.room_id or "room-owner",
    connects_to_room_id = fields.connects_to_room_id,
    part_id = fields.part_id or "part-main",
    side = fields.side or "south",
    offset_mm = fields.offset_mm or 500,
    width_mm = fields.width_mm or 1000,
  })
end

local function outlet(fields)
  fields = fields or {}
  return model.new_outlet({
    id = fields.id or "outlet-main",
    room_id = fields.room_id or "room-owner",
    part_id = fields.part_id or "part-main",
    side = fields.side or "south",
    offset_mm = fields.offset_mm == nil and 500 or fields.offset_mm,
    outlet_type = fields.outlet_type or "power",
    slots = fields.slots or 2,
  })
end

describe("window and outlet validation", function()
  it("dispatches schema v3 and attributes structural errors to the entity", function()
    local plan = plan_with_owner()
    local invalid_window = add(plan, "windows", window({}))
    local invalid_outlet = add(plan, "outlets", outlet({}))
    invalid_window.width_mm = 0
    invalid_outlet.slots = 33

    local diagnostics = validate.run(plan)
    assert_true(diagnostic_for(diagnostics, "SCHEMA_INTEGER_MIN", "window"))
    assert_true(diagnostic_for(diagnostics, "SCHEMA_INTEGER_MAX", "outlet"))
  end)

  it("validates references and accepts valid wall attachments", function()
    local valid = plan_with_owner()
    add(valid, "rooms", room("room-connected", 4000, 0, 3000, 3000))
    add(
      valid,
      "windows",
      window({
        side = "east",
        offset_mm = 1000,
        connects_to_room_id = "room-connected",
      })
    )
    add(valid, "outlets", outlet({}))
    local valid_diagnostics = validate.run(valid)
    assert_equal(0, #valid_diagnostics)

    local orphaned = plan_with_owner()
    add(orphaned, "windows", window({ connects_to_room_id = "room-missing" }))
    add(orphaned, "outlets", outlet({ id = "outlet-orphan", room_id = "room-missing" }))
    local diagnostics = validate.run(orphaned)
    assert_true(diagnostic_for(diagnostics, "INVALID_REFERENCE", "window"))
    assert_true(diagnostic_for(diagnostics, "INVALID_REFERENCE", "outlet"))
  end)

  it("checks window edge, exterior, and room connection geometry", function()
    local outside = plan_with_owner()
    add(outside, "windows", window({ offset_mm = 3500, width_mm = 1000 }))
    assert_true(codes(validate.run(outside)).WINDOW_OUTSIDE_EDGE)

    local compound = assert(model.new())
    add(
      compound,
      "rooms",
      model.new_room({
        id = "room-owner",
        name = "L room",
        origin_mm = { 0, 0 },
        footprint = l_footprint(),
      })
    )
    add(compound, "windows", window({ side = "north", offset_mm = 500, width_mm = 1000 }))
    assert_true(codes(validate.run(compound)).WINDOW_NOT_EXTERIOR)

    local invalid_connection = plan_with_owner()
    add(invalid_connection, "rooms", room("room-other", 10000, 0, 3000, 3000))
    add(invalid_connection, "windows", window({ connects_to_room_id = "room-other" }))
    assert_true(codes(validate.run(invalid_connection)).WINDOW_CONNECTION_INVALID)

    local missing_connection = plan_with_owner()
    add(missing_connection, "rooms", room("room-connected", 4000, 0, 3000, 3000))
    add(missing_connection, "windows", window({ side = "east", offset_mm = 1000 }))
    assert_true(codes(validate.run(missing_connection)).WINDOW_CONNECTION_MISSING)

    local obstructed = plan_with_owner()
    add(obstructed, "rooms", room("room-partial", 4000, 1500, 3000, 1000))
    add(obstructed, "windows", window({ side = "east", offset_mm = 1000 }))
    assert_true(codes(validate.run(obstructed)).WINDOW_EXTERIOR_OBSTRUCTED)
  end)

  it("rejects outlet corners and internal compound-room seams", function()
    local corner = plan_with_owner()
    add(corner, "outlets", outlet({ offset_mm = 0 }))
    assert_true(codes(validate.run(corner)).OUTLET_OUTSIDE_EDGE)

    local compound = assert(model.new())
    add(
      compound,
      "rooms",
      model.new_room({
        id = "room-owner",
        name = "L room",
        origin_mm = { 0, 0 },
        footprint = l_footprint(),
      })
    )
    add(compound, "outlets", outlet({ side = "north", offset_mm = 500 }))
    assert_true(codes(validate.run(compound)).OUTLET_NOT_EXTERIOR)
  end)

  it("accepts interior floor outlets and rejects room boundaries and outside points", function()
    local valid = plan_with_owner()
    add(
      valid,
      "outlets",
      model.new_outlet({
        id = "outlet-floor",
        room_id = "room-owner",
        placement = "floor",
        position_mm = { 2000, 1500 },
        outlet_type = "power",
        slots = 2,
      })
    )
    assert_equal(0, #validate.run(valid))

    local boundary = plan_with_owner()
    add(
      boundary,
      "outlets",
      model.new_outlet({
        id = "outlet-boundary",
        room_id = "room-owner",
        placement = "floor",
        position_mm = { 0, 1500 },
        outlet_type = "power",
        slots = 2,
      })
    )
    assert_true(codes(validate.run(boundary)).OUTLET_OUTSIDE_ROOM)

    local outside = plan_with_owner()
    add(
      outside,
      "outlets",
      model.new_outlet({
        id = "outlet-outside",
        room_id = "room-owner",
        placement = "floor",
        position_mm = { 5000, 1500 },
        outlet_type = "power",
        slots = 2,
      })
    )
    assert_true(codes(validate.run(outside)).OUTLET_OUTSIDE_ROOM)
  end)

  it("keeps door overlap compatibility and detects every window opening overlap", function()
    local doors = plan_with_owner()
    add(
      doors,
      "doors",
      model.new_door({
        id = "door-one",
        room_id = "room-owner",
        part_id = "part-main",
        side = "south",
        offset_mm = 500,
        width_mm = 1000,
      })
    )
    add(
      doors,
      "doors",
      model.new_door({
        id = "door-two",
        room_id = "room-owner",
        part_id = "part-main",
        side = "south",
        offset_mm = 1000,
        width_mm = 1000,
      })
    )
    assert_true(codes(validate.run(doors)).DOOR_OPENING_OVERLAP)

    local mixed = plan_with_owner()
    add(
      mixed,
      "doors",
      model.new_door({
        id = "door-main",
        room_id = "room-owner",
        part_id = "part-main",
        side = "south",
        offset_mm = 500,
        width_mm = 1000,
      })
    )
    add(mixed, "windows", window({ offset_mm = 750, width_mm = 500 }))
    assert_true(codes(validate.run(mixed)).WALL_OPENING_OVERLAP)

    local windows = plan_with_owner()
    add(windows, "windows", window({ id = "window-one", offset_mm = 500, width_mm = 1000 }))
    add(windows, "windows", window({ id = "window-two", offset_mm = 1000, width_mm = 1000 }))
    assert_true(codes(validate.run(windows)).WALL_OPENING_OVERLAP)
  end)
end)
