local adapter = require("roomplan.catalog.v2_adapter")
local json = require("roomplan.codec.json")
local schema_v2 = require("roomplan.schema.v2")

local function assert_valid_v2_template(template)
  local document = json.object({
    format = "roomplan.nvim",
    schema_version = 2,
    units = "mm",
    rooms = json.array(),
    doors = json.array(),
    furniture = json.array(),
    custom_templates = json.array({ template }),
  })
  local normalized, err = schema_v2.normalize(document)
  assert_true(normalized ~= nil, vim.inspect(err))
end

describe("external catalogue v1 conversion", function()
  it("creates the single canonical v2 template geometry authority", function()
    local converted = assert(adapter.from_external_v1({
      id = "custom:corner-seat",
      name = "Corner seat",
      category = "seating",
      shape = "rectangle",
      default_size_mm = { 1801, 601, 450 },
    }))

    assert_true(json.is_object(converted))
    assert_equal(nil, converted.shape)
    assert_equal(nil, converted.default_size_mm)
    assert_equal({ 1801, 601 }, converted.default_anchor2_mm)
    assert_equal(450, converted.default_height_mm)

    local footprint = converted.default_footprint
    assert_true(json.is_object(footprint))
    assert_equal("rect_union", footprint.kind)
    assert_true(json.is_array(footprint.parts))
    assert_equal(1, #footprint.parts)
    assert_equal("part-main", footprint.parts[1].id)
    assert_equal({ 0, 0 }, footprint.parts[1].origin_mm)
    assert_equal({ 1801, 601 }, footprint.parts[1].size_mm)
    assert_true(json.is_array(converted.default_anchor2_mm))
    assert_true(json.is_array(footprint.parts[1].origin_mm))
    assert_true(json.is_array(footprint.parts[1].size_mm))
    assert_valid_v2_template(converted)
  end)

  it("accepts the catalogue-v1 default rectangle shape without mutating input", function()
    local source = {
      id = "custom:desk",
      name = "Desk",
      category = "work",
      default_size_mm = { 1400, 700, 750 },
    }
    local converted = assert(adapter.from_external_v1(source))

    converted.default_footprint.parts[1].size_mm[1] = 1
    converted.default_anchor2_mm[1] = 2
    assert_equal({ 1400, 700, 750 }, source.default_size_mm)
    assert_equal(nil, source.shape)

    local second = assert(adapter.from_external_v1(source))
    assert_equal({ 1400, 700 }, second.default_footprint.parts[1].size_mm)
    assert_equal({ 1400, 700 }, second.default_anchor2_mm)
  end)

  it("rejects geometry that cannot be converted losslessly", function()
    local value, err = adapter.from_external_v1({
      id = "custom:round-table",
      name = "Round table",
      category = "dining",
      shape = "circle",
      default_size_mm = { 1000, 1000, 750 },
    })
    assert_equal(nil, value)
    assert_equal("CATALOG_V1_CONVERSION", err.code)
    assert_equal("$.shape", err.path)

    value, err = adapter.from_external_v1({
      id = "custom:bad",
      name = "Bad",
      category = "test",
      default_size_mm = { 1000, 0, 750 },
    })
    assert_equal(nil, value)
    assert_equal("$.default_size_mm[2]", err.path)

    value, err = adapter.from_external_v1({
      id = "custom:too-large",
      name = "Too large",
      category = "test",
      default_size_mm = { 1000000001, 500, 750 },
    })
    assert_equal(nil, value)
    assert_equal("$.default_size_mm[1]", err.path)

    value, err = adapter.from_external_v1({
      id = "not-custom",
      name = "Wrong ID",
      category = "test",
      default_size_mm = { 500, 500, 750 },
    })
    assert_equal(nil, value)
    assert_equal("$.id", err.path)

    value, err = adapter.from_external_v1({
      id = "custom:unsafe-label",
      name = "Unsafe\0label",
      category = "test",
      default_size_mm = { 500, 500, 750 },
    })
    assert_equal(nil, value)
    assert_equal("$.name", err.path)
  end)
end)
