local h = require("tests.harness")

local json = require("roomplan.codec.json")
local model = require("roomplan.model")
local schema = require("roomplan.schema")
local schema_v4 = require("roomplan.schema.v4")

local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h:h")

local function fixture(name)
  local text = table.concat(vim.fn.readfile(root .. "/tests/fixtures/" .. name, "b"), "\n")
  return h.truthy(json.decode(text))
end

local function room()
  return model.new_room({
    id = "room-main", name = "Living", origin_mm = { 0, 0 }, size_mm = { 4000, 3000 },
  })
end

describe("schema v4 outlet placement", function()
  it("migrates v3 outlets to explicit wall placement without mutating input", function()
    local source_document = fixture("windows-outlets-v3.roomplan.json")
    local original = json.deep_copy(source_document)
    local migrated, info = schema.load(source_document)
    h.truthy(migrated, vim.inspect(info))
    h.eq(4, migrated.schema_version)
    h.eq("wall", migrated.outlets[1].placement)
    h.eq("SCHEMA_MIGRATED_V3_TO_V4", info.migration_notes[#info.migration_notes].code)
    h.truthy(json.deep_equal(original, source_document))
  end)

  it("rejects a v3 extension collision at the new placement field", function()
    local source_document = fixture("windows-outlets-v3.roomplan.json")
    source_document.outlets[1].placement = "vendor-value"
    local original = json.deep_copy(source_document)
    local migrated, err = schema.migrate(source_document, 4)
    h.eq(nil, migrated)
    h.eq("SCHEMA_MIGRATION_COLLISION", h.truthy(err).code)
    h.eq("$.outlets[1].placement", err.path)
    h.truthy(json.deep_equal(original, source_document))
  end)

  it("round-trips mutually exclusive wall and floor outlet coordinates", function()
    local plan = h.truthy(model.new({ name = "Outlet placement" }))
    plan.rooms[1] = room()
    plan.outlets[1] = model.new_outlet({
      id = "outlet-wall", room_id = "room-main", placement = "wall",
      part_id = "part-main", side = "west", offset_mm = 1000,
      outlet_type = "power", slots = 2,
    })
    plan.outlets[2] = model.new_outlet({
      id = "outlet-floor", room_id = "room-main", placement = "floor",
      position_mm = { 2000, 1500 }, outlet_type = "usb", slots = 3,
    })
    local normalized, info = schema_v4.normalize(plan)
    h.truthy(normalized, vim.inspect(info))
    h.eq(nil, normalized.outlets[1].position_mm)
    h.eq(nil, normalized.outlets[2].side)
    h.eq({ 2000, 1500 }, normalized.outlets[2].position_mm)
    local encoded = h.truthy(schema.encode(normalized))
    local reloaded = h.truthy(schema.decode(encoded))
    h.truthy(json.deep_equal(normalized, reloaded))

    local mixed = json.deep_copy(normalized)
    mixed.outlets[2].side = "north"
    local rejected, err = schema_v4.normalize(mixed)
    h.eq(nil, rejected)
    h.eq("SCHEMA_OUTLET_PLACEMENT_FIELD", h.truthy(err).code)
    h.eq("$.outlets[2].side", err.path)
  end)

  it("publishes the current discriminated outlet schema", function()
    local text = table.concat(vim.fn.readfile(root .. "/schema/roomplan-v4.schema.json", "b"), "\n")
    local published = h.truthy(json.decode(text))
    local sign, coefficient, exponent = json.decimal_parts(published.properties.schema_version.const)
    h.eq({ 1, "4", 0 }, { sign, coefficient, exponent })
    h.eq({ "wall", "floor" }, published["$defs"].outlet.properties.placement.enum)
    h.eq(2, #published["$defs"].outlet.oneOf)
  end)
end)
