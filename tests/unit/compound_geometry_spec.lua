local footprint = require("roomplan.geometry.footprint")

local function l_shape()
  return assert(footprint.compound({
    { id = "part-main", left2 = 0, bottom2 = 0, right2 = 8, top2 = 12 },
    { id = "part-east", left2 = 8, bottom2 = 0, right2 = 16, top2 = 4 },
  }))
end

describe("compound geometry kernel", function()
  it("assigns stable local IDs and enforces supported topology", function()
    local shape = assert(footprint.compound({
      { left2 = 8, bottom2 = 0, right2 = 16, top2 = 4 },
      { left2 = 0, bottom2 = 0, right2 = 8, top2 = 12 },
    }))
    assert_equal("part-2", shape.parts[1].id)
    assert_equal("part-1", shape.parts[2].id)
    assert_true(footprint.is_connected(shape))

    local still_assigned = assert(footprint.compound({
      { left2 = 0, bottom2 = 0, right2 = 4, top2 = 4 },
      { left2 = 4, bottom2 = 0, right2 = 8, top2 = 4 },
    }, { assign_ids = false }))
    assert_equal("part-1", still_assigned.parts[1].id)
    assert_equal("part-2", still_assigned.parts[2].id)

    local invalid, err = footprint.compound({
      { id = "part-main", left2 = 0, bottom2 = 0, right2 = 4, top2 = 4 },
      { id = "part-other", left2 = 4, bottom2 = 4, right2 = 8, top2 = 8 },
    }, { require_connected = false })
    assert_equal(nil, invalid)
    assert_equal("FOOTPRINT_DISCONNECTED", err.code)

    invalid, err = footprint.compound({
      { id = "part-main", left2 = 0, bottom2 = 0, right2 = 2, top2 = 10 },
      { id = "part-right", left2 = 8, bottom2 = 0, right2 = 10, top2 = 10 },
      { id = "part-bottom", left2 = 2, bottom2 = 0, right2 = 8, top2 = 2 },
      { id = "part-top", left2 = 2, bottom2 = 8, right2 = 8, top2 = 10 },
    }, { reject_holes = false })
    assert_equal(nil, invalid)
    assert_equal("FOOTPRINT_HOLE", err.code)

    invalid, err = footprint.normalize({
      kind = "rect_union",
      parts = { [1] = { left2 = 0, bottom2 = 0, right2 = 2, top2 = 2 }, [3] = {} },
    })
    assert_equal(nil, invalid)
    assert_equal("FOOTPRINT_PARTS_ARRAY", err.code)

    invalid, err = footprint.compound({
      { id = "part-main", left2 = 0, bottom2 = 0, right2 = 2, top2 = 2 },
      { id = "part-main", left2 = 2, bottom2 = 0, right2 = 4, top2 = 2 },
    })
    assert_equal(nil, invalid)
    assert_equal("FOOTPRINT_PART_ID_DUPLICATE", err.code)

    local too_many = {}
    for index = 1, footprint.DEFAULT_MAX_PARTS + 1 do
      too_many[index] = {
        id = "part-" .. index,
        left2 = index - 1,
        bottom2 = 0,
        right2 = index,
        top2 = 2,
      }
    end
    invalid, err = footprint.compound(too_many, { max_parts = #too_many })
    assert_equal(nil, invalid)
    assert_equal("FOOTPRINT_PART_LIMIT", err.code)
  end)

  it("distinguishes open, enclosed, and corner-pinched complements", function()
    local open_u = assert(footprint.compound({
      { id = "part-left", left2 = 0, bottom2 = 0, right2 = 2, top2 = 10 },
      { id = "part-right", left2 = 8, bottom2 = 0, right2 = 10, top2 = 10 },
      { id = "part-bottom", left2 = 2, bottom2 = 0, right2 = 8, top2 = 2 },
    }))
    assert_equal(false, footprint.has_holes(open_u))

    local pinched, err = footprint.compound({
      { id = "part-bottom", left2 = 0, bottom2 = 0, right2 = 10, top2 = 2 },
      { id = "part-left", left2 = 0, bottom2 = 2, right2 = 2, top2 = 10 },
      { id = "part-top", left2 = 2, bottom2 = 8, right2 = 8, top2 = 10 },
      { id = "part-right", left2 = 8, bottom2 = 2, right2 = 10, top2 = 8 },
    })
    assert_equal(nil, pinched)
    assert_equal("FOOTPRINT_HOLE", err.code)
  end)

  it("computes exact area, perimeter, containment, and complete intersections", function()
    local shape = l_shape()
    assert_equal(128, footprint.area4(shape))
    assert_equal(32, footprint.area(shape))
    assert_equal(56, footprint.perimeter2(shape))
    assert_equal(28, footprint.perimeter(shape))

    local across_seam = assert(footprint.rectangle2(6, 1, 10, 3))
    local in_notch = assert(footprint.rectangle2(10, 6, 14, 10))
    assert_true(footprint.contains(shape, across_seam))
    assert_equal(false, footprint.contains(shape, in_notch))

    local cutter = assert(footprint.rectangle2(6, 2, 12, 8))
    local intersection, provenance = footprint.intersection2(shape, cutter)
    assert_equal(2, #intersection.parts)
    assert_equal(20, footprint.area4(intersection))
    assert_equal(20, footprint.intersection_area4(shape, cutter))
    assert_equal("part-main", provenance[1].left.part_id)
    assert_equal("part-east", provenance[2].left.part_id)

    local miss = assert(footprint.rectangle2(20, 20, 22, 22))
    assert_equal(nil, footprint.intersection2(shape, miss))
    assert_equal(0, footprint.intersection_area4(shape, miss))

    local open_u = assert(footprint.compound({
      { id = "part-left", left2 = 0, bottom2 = 0, right2 = 2, top2 = 10 },
      { id = "part-right", left2 = 8, bottom2 = 0, right2 = 10, top2 = 10 },
      { id = "part-bottom", left2 = 2, bottom2 = 0, right2 = 8, top2 = 2 },
    }))
    local crossbar = assert(footprint.rectangle2(0, 6, 10, 8))
    local disconnected = assert(footprint.intersection2(open_u, crossbar))
    assert_equal(2, #disconnected.parts)
    assert_equal(false, footprint.is_connected(disconnected))
  end)

  it("extracts a seam-free boundary with part provenance", function()
    local boundary = assert(footprint.exterior_boundary2(l_shape()))
    assert_equal(6, #boundary)
    local total = 0
    local south
    for _, segment in ipairs(boundary) do
      total = total + segment.length2
      if segment.side == "south" then south = segment end
    end
    assert_equal(56, total)
    assert_equal(0, south.start2)
    assert_equal(16, south.finish2)
    assert_equal({ "part-east", "part-main" }, south.part_ids)
  end)

  it("keeps distinct boundary lines at large exact coordinates", function()
    local shape = assert(footprint.rectangle2(1000000000000000, 0, 1000000000000001, 2))
    local boundary = assert(footprint.boundary2(shape))
    assert_equal(4, #boundary)
    assert_equal(6, footprint.perimeter2(shape))
  end)

  it("returns deterministic interior anchors and hit provenance", function()
    local shape = l_shape()
    assert_equal({ x2 = 4, y2 = 6, part_id = "part-main", part_index = 1 }, footprint.label_anchor2(shape))

    local hits = assert(footprint.hit_test2(shape, 8, 2))
    assert_equal(2, #hits)
    assert_equal("part-main", hits[1].part_id)
    assert_equal("part-east", hits[2].part_id)
    assert_true(hits[1].on_boundary)
    assert_true(hits[2].on_boundary)

    local strict_hits = assert(footprint.hit_test2(shape, 8, 2, { include_boundary = false }))
    assert_equal(0, #strict_hits)

    assert_equal(false, footprint.contains_point2(shape, 12, 8))
    assert_true(footprint.contains_point2(shape, 2, 2))
  end)

  it("keeps local frames and part identity stable through transforms", function()
    local room = { origin_mm = { -100, 25 }, size_mm = { 301, 199 } }
    local local_shape, frame = footprint.local_from_room(room, "part-main")
    assert_equal({ origin_x2 = -200, origin_y2 = 50 }, frame)
    assert_equal({
      id = "part-main",
      left2 = 0,
      bottom2 = 0,
      right2 = 602,
      top2 = 398,
    }, local_shape.parts[1])

    local world = assert(footprint.from_local(local_shape, frame))
    assert_equal(footprint.bounds2(footprint.from_room(room)), footprint.bounds2(world))
    local round_trip = assert(footprint.to_local(world, frame))
    assert_equal(local_shape, round_trip)

    local rotated = assert(footprint.rotate_quarter(l_shape(), 90, 0, 0))
    local translated = assert(footprint.translate2(rotated, 100, -50))
    assert_equal("part-main", translated.parts[1].id)
    assert_equal("part-east", translated.parts[2].id)
    assert_true(footprint.is_connected(translated))
    assert_equal(footprint.area4(local_shape), footprint.area4(world))
    assert_equal(footprint.perimeter2(local_shape), footprint.perimeter2(world))

    local original = l_shape()
    local snapshot = vim.deepcopy(original)
    local transformed = assert(footprint.transform2(original, {
      rotation_deg = 270,
      pivot_x2 = 4,
      pivot_y2 = 2,
      delta_x2 = -20,
      delta_y2 = 30,
    }))
    assert_equal(snapshot, original)
    assert_equal(footprint.area4(original), footprint.area4(transformed))
    assert_equal(footprint.perimeter2(original), footprint.perimeter2(transformed))
  end)

  it("adapts persisted v2 rooms and anchored furniture through one geometry authority", function()
    local persisted = {
      kind = "rect_union",
      parts = {
        { id = "part-main", origin_mm = { 0, 0 }, size_mm = { 4, 6 } },
        { id = "part-east", origin_mm = { 4, 0 }, size_mm = { 4, 2 } },
      },
    }
    local room = { id = "room-l", origin_mm = { 100, 200 }, footprint = persisted }
    local local_shape, frame = assert(footprint.local_from_room(room))
    assert_equal({ origin_x2 = 200, origin_y2 = 400 }, frame)
    assert_equal({ "part-main", "part-east" }, {
      local_shape.parts[1].id,
      local_shape.parts[2].id,
    })
    assert_equal({
      left2 = 200,
      bottom2 = 400,
      right2 = 216,
      top2 = 412,
      width2 = 16,
      depth2 = 12,
      center_x2 = 208,
      center_y2 = 406,
    }, assert(footprint.bounds2(footprint.from_room(room))))

    local furniture = {
      id = "furniture-l",
      room_id = room.id,
      position_mm = { 10, 20 },
      anchor2_mm = { 4, 2 },
      footprint = persisted,
      height_mm = 10,
      rotation_deg = 90,
    }
    local world = assert(footprint.from_furniture(room, furniture))
    assert_equal({
      left2 = 210,
      bottom2 = 436,
      right2 = 222,
      top2 = 452,
      width2 = 12,
      depth2 = 16,
      center_x2 = 216,
      center_y2 = 444,
    }, assert(footprint.bounds2(world)))
    assert_equal({ "part-main", "part-east" }, {
      world.parts[1].id,
      world.parts[2].id,
    })
  end)

  it("fails instead of silently rounding inexact aggregate geometry", function()
    local limit = footprint.MAX_ABS_COORDINATE2
    local shape = assert(footprint.rectangle2(-limit, 0, limit, 2))
    local area, err = footprint.area4(shape)
    assert_equal(nil, area)
    assert_equal("FOOTPRINT_RANGE", err.code)

    local perimeter
    perimeter, err = footprint.perimeter2(shape)
    assert_equal(nil, perimeter)
    assert_equal("FOOTPRINT_RANGE", err.code)
  end)

  it("checks transforms, frames, bounds, and anchors at the exact coordinate limit", function()
    local limit = footprint.MAX_ABS_COORDINATE2
    local near = assert(footprint.rectangle2(limit - 4, -2, limit - 2, 2))
    local bounds = assert(footprint.bounds2(near))
    assert_equal(limit - 3, bounds.center_x2)
    assert_equal(limit - 3, footprint.label_anchor2(near).x2)

    local translated = assert(footprint.translate2(near, 2, 0))
    assert_equal(limit, footprint.bounds2(translated).right2)
    local invalid, err = footprint.translate2(near, 3, 0)
    assert_equal(nil, invalid)
    assert_equal("FOOTPRINT_RANGE", err.code)

    local negative = assert(footprint.rectangle2(-limit + 2, -2, -limit + 4, 2))
    invalid, err = footprint.translate2(negative, -3, 0)
    assert_equal(nil, invalid)
    assert_equal("FOOTPRINT_RANGE", err.code)

    assert_equal({ origin_x2 = limit, origin_y2 = -limit }, footprint.frame(limit, -limit))
    invalid, err = footprint.frame(limit + 1, 0)
    assert_equal(nil, invalid)
    assert_equal("FOOTPRINT_RANGE", err.code)

    invalid, err = footprint.rotate_quarter(near, 90, limit + 1, 0)
    assert_equal(nil, invalid)
    assert_equal("FOOTPRINT_RANGE", err.code)
  end)
end)
