local wall_attachment = require("roomplan.geometry.wall_attachment")
local walls = require("roomplan.scene.walls")

local function room(id, x, y, width, depth)
  return {
    id = id,
    name = id,
    origin_mm = { x, y },
    size_mm = { width, depth },
  }
end

local function covers(segments, orientation, fixed, scalar)
  for _, segment in ipairs(segments) do
    if
      segment.orientation == orientation
      and segment.fixed == fixed
      and segment.start < scalar
      and segment.finish > scalar
    then
      return true
    end
  end
  return false
end

describe("wall attachments", function()
  it("shares aperture, overlap, and connection geometry", function()
    local owner = room("owner", 0, 0, 1000, 1000)
    local connected = room("connected", 1000, 0, 500, 1000)
    local first = {
      id = "first",
      room_id = owner.id,
      side = "east",
      offset_mm = 100,
      width_mm = 200,
    }
    local second = {
      id = "second",
      room_id = owner.id,
      side = "east",
      offset_mm = 250,
      width_mm = 100,
    }

    assert_equal(1000, wall_attachment.edge_length(owner, "east"))
    local first_aperture = assert(wall_attachment.aperture(owner, first))
    local second_aperture = assert(wall_attachment.aperture(owner, second))
    assert_equal(100, first_aperture.start_mm)
    assert_equal(300, first_aperture.finish_mm)
    assert_equal({ 1000, 100 }, { first_aperture.p0[1], first_aperture.p0[2] })
    assert_equal(true, first_aperture.within_edge)
    assert_equal(true, first_aperture.on_exterior)
    assert_equal(true, wall_attachment.apertures_overlap(first_aperture, second_aperture))

    local connection = assert(wall_attachment.connection(owner, connected, first))
    assert_equal("east", connection.a_side)
    assert_equal("west", connection.b_side)
    -- Rectangle connections retain the established full shared-edge record.
    assert_equal(0, connection.start_mm)
    assert_equal(1000, connection.finish_mm)
  end)

  it("cuts owner and verified connected walls for windows", function()
    local owner = room("owner", 0, 0, 1000, 1000)
    local connected = room("connected", 1000, 0, 500, 1000)
    local result = walls.build({ owner, connected }, {}, {
      {
        id = "window",
        room_id = owner.id,
        connects_to_room_id = connected.id,
        side = "east",
        offset_mm = 200,
        width_mm = 300,
      },
    })

    assert_equal(0, #result.apertures)
    assert_equal(1, #result.window_apertures)
    assert_equal(true, result.window_apertures[1].owner_edge_valid)
    assert_equal(true, result.window_apertures[1].connection_valid)
    assert_equal(false, covers(result.segments, "vertical", 1000, 350))
  end)

  it("never cuts walls for invalid windows", function()
    local owner = room("owner", 0, 0, 1000, 1000)
    local result = walls.build({ owner }, {}, {
      {
        id = "invalid-window",
        room_id = owner.id,
        side = "east",
        offset_mm = 900,
        width_mm = 200,
      },
    })

    assert_equal(false, result.window_apertures[1].owner_edge_valid)
    assert_equal("aperture extends beyond owner edge", result.window_apertures[1].reason)
    assert_equal(true, covers(result.segments, "vertical", 1000, 950))
  end)

  it("classifies outlets without cutting and rejects edge endpoints", function()
    local owner = room("owner", 0, 0, 1000, 1000)
    local result = walls.build({ owner }, {}, {}, {
      {
        id = "middle",
        room_id = owner.id,
        side = "south",
        offset_mm = 500,
      },
      {
        id = "corner",
        room_id = owner.id,
        side = "south",
        offset_mm = 0,
      },
    })

    assert_equal(2, #result.outlet_markers)
    assert_equal(true, result.outlet_markers[1].owner_edge_valid)
    assert_equal({ 500, 0 }, result.outlet_markers[1].p)
    assert_equal(false, result.outlet_markers[2].owner_edge_valid)
    assert_equal("outlet position is ambiguous at an edge endpoint", result.outlet_markers[2].reason)
    assert_equal(true, covers(result.segments, "horizontal", 0, 500))
  end)
end)
