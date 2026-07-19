local footprint = require("roomplan.geometry.footprint")
local json = require("roomplan.codec.json")
local number = require("roomplan.geometry.number")
local presets = require("roomplan.model.room_footprints")

local layouts = {
  northeast = {
    { 0, 0, 4001, 1201 },
    { 0, 1201, 1501, 1800 },
    notch = { 4000, 3000 },
  },
  northwest = {
    { 0, 0, 4001, 1201 },
    { 2500, 1201, 1501, 1800 },
    notch = { 1, 3000 },
  },
  southeast = {
    { 0, 1800, 4001, 1201 },
    { 0, 0, 1501, 1800 },
    notch = { 4000, 1 },
  },
  southwest = {
    { 0, 1800, 4001, 1201 },
    { 2500, 0, 1501, 1800 },
    notch = { 1, 1 },
  },
}

describe("room footprint presets", function()
  it("keeps the rectangle preset canonical", function()
    local value = assert(presets.build({ shape = "rectangle", width_mm = 4001, depth_mm = 3001 }))
    assert_true(json.is_object(value))
    assert_true(json.is_array(value.parts))
    assert_equal("part-main", value.parts[1].id)
    assert_equal({ 4001, 3001 }, value.parts[1].size_mm)
  end)

  it("builds every exact L orientation without filling its notch", function()
    for corner, expected in pairs(layouts) do
      local value = assert(presets.build({
        shape = "l_shape",
        width_mm = 4001,
        depth_mm = 3001,
        leg_width_mm = 1501,
        leg_depth_mm = 1201,
        missing_corner = corner,
      }))
      assert_equal(2, #value.parts)
      assert_equal("part-horizontal", value.parts[1].id)
      assert_equal("part-vertical", value.parts[2].id)
      for index = 1, 2 do
        assert_equal({ expected[index][1], expected[index][2] }, value.parts[index].origin_mm)
        assert_equal({ expected[index][3], expected[index][4] }, value.parts[index].size_mm)
      end

      local runtime = assert(footprint.from_persisted(value))
      local bounds = assert(footprint.bounds(runtime))
      assert_equal(4001, bounds.width)
      assert_equal(3001, bounds.depth)
      assert_equal(false, footprint.contains_point2(runtime, 2 * expected.notch[1], 2 * expected.notch[2]))
      assert_true(footprint.contains_point2(runtime, 2 * 2000, 2 * (corner:find("north", 1, true) and 600 or 2400)))

      local classified = assert(presets.classify(value))
      assert_equal("l_shape", classified.shape)
      assert_equal(4001, classified.width_mm)
      assert_equal(3001, classified.depth_mm)
      assert_equal(1501, classified.leg_width_mm)
      assert_equal(1201, classified.leg_depth_mm)
      assert_equal(corner, classified.missing_corner)
      assert_true(json.deep_equal(value, assert(presets.build(classified))))
    end
  end)

  it("rejects degenerate L dimensions at the preset boundary", function()
    local value, err = presets.build({
      shape = "l_shape",
      width_mm = 4000,
      depth_mm = 3000,
      leg_width_mm = 4000,
      leg_depth_mm = 1200,
      missing_corner = "northeast",
    })
    assert_equal(nil, value)
    assert_equal("leg_width_mm", err.field)

    value, err = presets.build({
      shape = "l_shape",
      width_mm = 4000,
      depth_mm = 3000,
      leg_width_mm = 1500,
      leg_depth_mm = 3000,
      missing_corner = "northeast",
    })
    assert_equal(nil, value)
    assert_equal("leg_depth_mm", err.field)
  end)

  it("classifies only losslessly editable canonical presets", function()
    local canonical = assert(presets.build({
      shape = "l_shape",
      width_mm = 4000,
      depth_mm = 3000,
      leg_width_mm = 1500,
      leg_depth_mm = 1200,
      missing_corner = "northeast",
    }))
    local mutations = {
      function(value) value.parts[1].id = "part-other" end,
      function(value)
        value.parts[1], value.parts[2] = value.parts[2], value.parts[1]
      end,
      function(value) value.parts[3] = json.deep_copy(value.parts[2]) end,
      function(value) value.parts[1].origin_mm[1] = 1 end,
      function(value) value.parts[2].origin_mm[2] = 1202 end,
      function(value) value.parts[2].origin_mm[1] = 1 end,
      function(value) value.parts[1].vendor = "preserve-me" end,
      function(value) value.parts[1].size_mm.vendor = true end,
      function(value) value.vendor = "preserve-me" end,
      function(value) value.parts[1].size_mm[1] = 4000.5 end,
      function(value) value.parts[1].size_mm[1] = math.huge end,
      function(value) value.parts[1].size_mm[1] = number.MAX_LOCAL_DIMENSION + 1 end,
      function(value) value.parts[2].size_mm[1] = 0 end,
    }
    for _, mutate in ipairs(mutations) do
      local value = json.deep_copy(canonical)
      mutate(value)
      assert_equal(nil, presets.classify(value))
    end
    assert_true(presets.classify(canonical) ~= nil)

    local invalid, err = presets.build({ shape = "rectangle", width_mm = math.huge, depth_mm = 1000 })
    assert_equal(nil, invalid)
    assert_equal("width_mm", err.field)
  end)
end)
