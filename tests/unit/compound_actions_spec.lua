local actions = require("roomplan.actions")
local catalog = require("roomplan.catalog")
local geometry = require("roomplan.geometry")
local json = require("roomplan.codec.json")
local model = require("roomplan.model")
local room_footprints = require("roomplan.model.room_footprints")

local V2 = { schema_version = 2 }

local function part(id, x, y, width, depth)
  return {
    id = id,
    origin_mm = { x, y },
    size_mm = { width, depth },
  }
end

local function footprint(parts) return { kind = "rect_union", parts = parts } end

local function tagged_footprint(value)
  local parts = json.array()
  for index, value_part in ipairs(value.parts) do
    parts[index] = json.object({
      id = value_part.id,
      origin_mm = json.array({ value_part.origin_mm[1], value_part.origin_mm[2] }),
      size_mm = json.array({ value_part.size_mm[1], value_part.size_mm[2] }),
    })
  end
  return json.object({ kind = value.kind, parts = parts })
end

local function plan_v2()
  local value = assert(model.new({ name = "Compound actions" }))
  value.schema_version = 2
  return value
end

local function add_room(value, fields)
  if fields.footprint then fields.footprint = tagged_footprint(fields.footprint) end
  value.rooms[#value.rooms + 1] = model.new_room(fields, V2)
  return value.rooms[#value.rooms]
end

local function add_furniture(value, fields)
  if fields.footprint then fields.footprint = tagged_footprint(fields.footprint) end
  value.furniture[#value.furniture + 1] = model.new_furniture(fields, V2)
  return value.furniture[#value.furniture]
end

local function apply(value, action, context)
  local changed, result = actions.apply(value, action, context)
  assert_true(changed ~= nil, result and vim.inspect(result))
  return changed, result
end

describe("schema-v2 compound actions", function()
  it("constructs action drafts with v2 geometry and tagged tuples", function()
    local value = plan_v2()
    value = apply(value, {
      type = "add_room",
      room = {
        id = "room-l",
        name = "L room",
        origin_mm = { 0, 0 },
        footprint = footprint({
          part("part-main", 0, 0, 1000, 800),
          part("part-east", 1000, 0, 300, 300),
        }),
      },
    })
    value = apply(value, {
      type = "add_furniture",
      furniture = {
        id = "furniture-l",
        room_id = "room-l",
        template_id = "custom:sectional",
        name = "Sectional",
        category = "seating",
        position_mm = { 300, 300 },
        anchor2_mm = { 100, 100 },
        height_mm = 850,
        rotation_deg = 0,
        footprint = footprint({
          part("part-main", 0, 0, 200, 100),
          part("part-return", 0, 100, 100, 100),
        }),
      },
      custom_template = {
        id = "custom:sectional",
        name = "Sectional",
        category = "seating",
        default_anchor2_mm = { 100, 100 },
        default_height_mm = 850,
        default_footprint = footprint({
          part("part-main", 0, 0, 200, 100),
          part("part-return", 0, 100, 100, 100),
        }),
      },
    })

    local room = value.rooms[1]
    local furniture = value.furniture[1]
    local template = value.custom_templates[1]
    assert_equal(nil, room.size_mm)
    assert_equal(nil, furniture.center_mm)
    assert_equal(nil, furniture.size_mm)
    assert_true(json.is_array(room.origin_mm))
    assert_true(json.is_array(room.footprint.parts))
    assert_true(json.is_array(room.footprint.parts[2].origin_mm))
    assert_true(json.is_array(furniture.position_mm))
    assert_true(json.is_array(furniture.anchor2_mm))
    assert_true(json.is_array(template.default_anchor2_mm))
    assert_equal(2, #furniture.footprint.parts)
  end)

  it("moves and duplicates furniture through position_mm without flattening it", function()
    local value = plan_v2()
    add_room(value, {
      id = "room-main",
      name = "Main",
      origin_mm = { 0, 0 },
      footprint = footprint({ part("part-main", 0, 0, 2000, 2000) }),
    })
    local source = add_furniture(value, {
      id = "furniture-source",
      room_id = "room-main",
      template_id = "builtin:custom-rectangle",
      name = "L couch",
      category = "seating",
      position_mm = { 500, 500 },
      anchor2_mm = { 100, 100 },
      height_mm = 800,
      rotation_deg = 0,
      footprint = footprint({
        part("part-main", 0, 0, 200, 100),
        part("part-return", 0, 100, 100, 100),
      }),
    })
    local original_footprint = model.deep_copy(source.footprint)
    local original_anchor = model.deep_copy(source.anchor2_mm)

    value = apply(value, {
      type = "move_furniture",
      id = source.id,
      position_mm = { 600, 650 },
      exact = true,
    })
    assert_equal({ 600, 650 }, value.furniture[1].position_mm)
    assert_equal(nil, value.furniture[1].center_mm)

    local rejected, err = actions.apply(value, {
      type = "move_furniture",
      id = source.id,
      center_mm = { 1, 2 },
      exact = true,
    })
    assert_equal(nil, rejected)
    assert_equal("INVALID_ACTION", err.code)

    value = apply(value, {
      type = "duplicate_furniture",
      id = source.id,
      new_id = "furniture-copy",
      step_mm = 50,
    })
    local clone = value.furniture[2]
    assert_equal({ 650, 700 }, clone.position_mm)
    assert_equal(nil, clone.center_mm)
    assert_true(model.deep_equal(original_footprint, clone.footprint))
    assert_true(model.deep_equal(original_anchor, clone.anchor2_mm))
    assert_true(clone.footprint ~= value.furniture[1].footprint)

    local snapped = geometry.snapping.snap_furniture(value.rooms[1], clone, {}, {}, {
      grid_mm = 100,
      tolerance_mm = 100,
    })
    assert_true(snapped.position_mm ~= nil)
    assert_equal(nil, snapped.center_mm)
  end)

  it("updates one item and its project template atomically without propagating to peers", function()
    local value = assert(model.new({ name = "Template propagation" }))
    value.rooms[1] = model.new_room({
      id = "room-main",
      name = "Main",
      origin_mm = { 0, 0 },
      size_mm = { 4000, 3000 },
    })
    value.custom_templates[1] = model.new_custom_template({
      id = "custom:sectional",
      name = "Sectional",
      category = "seating",
      default_anchor2_mm = { 1000, 500 },
      default_height_mm = 800,
      default_footprint = model.rectangle_footprint({ 1000, 500 }),
    })
    for index, id in ipairs({ "furniture-edited", "furniture-peer" }) do
      value.furniture[index] = model.new_furniture({
        id = id,
        room_id = "room-main",
        template_id = "custom:sectional",
        name = id,
        category = "seating",
        position_mm = { index * 1200, 1000 },
        anchor2_mm = { 1000, 500 },
        height_mm = 800,
        footprint = model.rectangle_footprint({ 1000, 500 }),
      })
    end
    local changed, result = apply(value, {
      type = "edit_furniture_template_shape",
      id = "furniture-edited",
      template_id = "custom:sectional",
      footprint = footprint({
        part("part-main", 0, 0, 1100, 500),
        part("part-return", 0, 500, 500, 300),
      }),
    })
    assert_equal({ kind = "furniture", id = "furniture-edited" }, result.touched[1])
    assert_equal({ kind = "template", id = "custom:sectional" }, result.touched[2])
    assert_equal(2, #changed.furniture[1].footprint.parts)
    assert_equal(2, #changed.custom_templates[1].default_footprint.parts)
    assert_equal(1, #changed.furniture[2].footprint.parts)
    assert_equal(1000, changed.furniture[2].footprint.parts[1].size_mm[1])
    assert_equal(value.furniture[2].position_mm, changed.furniture[2].position_mm)

    local encoded = assert(model.encode(changed))
    local reopened = assert(model.decode(encoded))
    local resolved = assert(catalog.resolve(reopened, "custom:sectional"))
    assert_equal(2, #resolved.default_footprint.parts)
    assert_equal(1100, resolved.default_footprint.parts[1].size_mm[1])

    local stale, stale_err = actions.apply(value, {
      type = "edit_furniture_template_shape",
      id = "furniture-edited",
      template_id = "custom:missing",
      footprint = model.rectangle_footprint({ 1100, 500 }),
    })
    assert_equal(nil, stale)
    assert_equal("NOT_FOUND", stale_err.code)
    assert_equal(1000, value.furniture[1].footprint.parts[1].size_mm[1])
  end)

  it("auto-places a duplicated compound room from the complete footprint", function()
    local value = plan_v2()
    local source = add_room(value, {
      id = "room-source",
      name = "L room",
      origin_mm = { 0, 0 },
      footprint = footprint({
        part("part-main", 0, 0, 1000, 800),
        part("part-east", 1000, 0, 300, 300),
      }),
    })
    local original = model.deep_copy(source.footprint)

    value = apply(value, {
      type = "duplicate_room",
      id = source.id,
      new_id = "room-copy",
      cursor_mm = { 1500, 0 },
    })
    local clone = value.rooms[2]
    assert_true(model.deep_equal(original, clone.footprint))
    assert_true(clone.footprint ~= value.rooms[1].footprint)
    assert_equal(nil, clone.size_mm)
    local first = assert(geometry.footprint.from_room(value.rooms[1]))
    local second = assert(geometry.footprint.from_room(clone))
    assert_equal(false, geometry.footprint.overlaps_positive(first, second))
  end)

  it("snaps compound doors only against doors on the same room part", function()
    local value = plan_v2()
    add_room(value, {
      id = "room-main",
      name = "Main",
      origin_mm = { 0, 0 },
      footprint = footprint({
        part("part-main", 0, 0, 1000, 500),
        part("part-east", 1000, 0, 1000, 500),
      }),
    })
    value.doors[1] = model.new_door({
      id = "door-main",
      room_id = "room-main",
      part_id = "part-main",
      side = "south",
      offset_mm = 80,
      width_mm = 100,
    }, V2)
    value.doors[2] = model.new_door({
      id = "door-east",
      room_id = "room-main",
      part_id = "part-east",
      side = "south",
      offset_mm = 100,
      width_mm = 100,
    }, V2)

    value = apply(value, {
      type = "edit_door",
      id = "door-main",
      patch = { offset_mm = 90 },
      snap = { tolerance_mm = 20, grid_mm = 0 },
    })
    assert_equal(90, value.doors[1].offset_mm)
  end)

  it("resizes canonical rectangles and rejects compound or custom-anchor geometry", function()
    local value = plan_v2()
    add_room(value, {
      id = "room-main",
      name = "Main",
      origin_mm = { 0, 0 },
      size_mm = { 2000, 2000 },
    })
    add_furniture(value, {
      id = "furniture-main",
      room_id = "room-main",
      template_id = "builtin:custom-rectangle",
      name = "Desk",
      category = "work",
      position_mm = { 500, 500 },
      size_mm = { 200, 100, 700 },
      rotation_deg = 0,
    })

    value = apply(value, { type = "resize_room", id = "room-main", size_mm = { 2200, 2100 } })
    assert_equal({ 2200, 2100 }, value.rooms[1].footprint.parts[1].size_mm)
    assert_equal(nil, value.rooms[1].size_mm)
    value = apply(value, { type = "resize_furniture", id = "furniture-main", size_mm = { 300, 150, 750 } })
    assert_equal({ 300, 150 }, value.furniture[1].footprint.parts[1].size_mm)
    assert_equal({ 300, 150 }, value.furniture[1].anchor2_mm)
    assert_equal(750, value.furniture[1].height_mm)
    assert_equal(nil, value.furniture[1].size_mm)

    local compound = plan_v2()
    add_room(compound, {
      id = "room-l",
      name = "L",
      origin_mm = { 0, 0 },
      footprint = footprint({
        part("part-main", 0, 0, 1000, 800),
        part("part-east", 1000, 0, 300, 300),
      }),
    })
    local changed, err = actions.apply(compound, {
      type = "resize_room",
      id = "room-l",
      size_mm = { 100, 100 },
    })
    assert_equal(nil, changed)
    assert_equal("COMPOUND_RESIZE_UNSUPPORTED", err.code)
    assert_equal(2, #compound.rooms[1].footprint.parts)

    local custom_anchor = plan_v2()
    add_room(custom_anchor, {
      id = "room-main",
      name = "Main",
      origin_mm = { 0, 0 },
      size_mm = { 1000, 1000 },
    })
    add_furniture(custom_anchor, {
      id = "furniture-corner",
      room_id = "room-main",
      template_id = "builtin:custom-rectangle",
      name = "Corner anchored",
      category = "custom",
      position_mm = { 100, 100 },
      anchor2_mm = { 0, 0 },
      height_mm = 100,
      rotation_deg = 0,
      footprint = footprint({ part("part-main", 0, 0, 100, 100) }),
    })
    changed, err = actions.apply(custom_anchor, {
      type = "resize_furniture",
      id = "furniture-corner",
      size_mm = { 200, 200, 100 },
    })
    assert_equal(nil, changed)
    assert_equal("COMPOUND_RESIZE_UNSUPPORTED", err.code)
    assert_equal({ 100, 100 }, custom_anchor.furniture[1].footprint.parts[1].size_mm)
  end)

  it("keeps attached doors stable and blocks unsafe L-room edits atomically", function()
    local value = plan_v2()
    add_room(value, {
      id = "room-l",
      name = "L",
      origin_mm = { 0, 0 },
      footprint = assert(room_footprints.build({
        shape = "l_shape",
        width_mm = 4000,
        depth_mm = 3000,
        leg_width_mm = 1500,
        leg_depth_mm = 1200,
        missing_corner = "northeast",
      })),
    })
    value.doors[1] = model.new_door({
      id = "door-l",
      room_id = "room-l",
      part_id = "part-horizontal",
      side = "north",
      offset_mm = 3000,
      width_mm = 900,
    }, V2)
    local original_door = model.deep_copy(value.doors[1])
    local original_room = model.deep_copy(value.rooms[1])

    local enlarged = apply(value, {
      type = "edit_room",
      id = "room-l",
      patch = {
        footprint = assert(room_footprints.build({
          shape = "l_shape",
          width_mm = 4500,
          depth_mm = 3000,
          leg_width_mm = 1500,
          leg_depth_mm = 1200,
          missing_corner = "northeast",
        })),
      },
    })
    assert_true(model.deep_equal(original_door, enlarged.doors[1]))

    local blocked, err = actions.apply(value, {
      type = "edit_room",
      id = "room-l",
      patch = {
        footprint = assert(room_footprints.build({
          shape = "l_shape",
          width_mm = 3500,
          depth_mm = 3000,
          leg_width_mm = 1500,
          leg_depth_mm = 1200,
          missing_corner = "northeast",
        })),
      },
    })
    assert_equal(nil, blocked)
    assert_equal("LAYOUT_BLOCKED", err.code)
    assert_equal("DOOR_OUTSIDE_EDGE", err.details.diagnostics[1].code)
    assert_true(model.deep_equal(original_room, value.rooms[1]))
    assert_true(model.deep_equal(original_door, value.doors[1]))

    blocked, err = actions.apply(value, {
      type = "edit_room",
      id = "room-l",
      patch = {
        footprint = assert(room_footprints.build({
          shape = "l_shape",
          width_mm = 4000,
          depth_mm = 3000,
          leg_width_mm = 1500,
          leg_depth_mm = 1200,
          missing_corner = "northwest",
        })),
      },
    })
    assert_equal(nil, blocked)
    assert_equal("LAYOUT_BLOCKED", err.code)
    assert_equal("DOOR_NOT_EXTERIOR", err.details.diagnostics[1].code)
    assert_true(model.deep_equal(original_room, value.rooms[1]))
    assert_true(model.deep_equal(original_door, value.doors[1]))
  end)
end)
