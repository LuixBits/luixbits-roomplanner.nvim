local h = require("tests.harness")

local ids = require("roomplan.ids")
local json = require("roomplan.codec.json")
local model = require("roomplan.model")
local outlet_types = require("roomplan.outlet_types")
local schema = require("roomplan.schema")
local schema_v2 = require("roomplan.schema.v2")
local schema_v3 = require("roomplan.schema.v3")

local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h:h")

local function fixture(name)
  local text = table.concat(vim.fn.readfile(root .. "/tests/fixtures/" .. name, "b"), "\n")
  local document, err = json.decode(text)
  return h.truthy(document, name .. ": " .. vim.inspect(err))
end

local function expect_failure(run, code, path)
  local value, err = run()
  h.falsy(value)
  err = h.truthy(err)
  h.eq(code, err.code)
  h.eq(path, err.path)
  return err
end

describe("schema v3 wall-feature foundation", function()
  it("constructs a current model with canonical wall-feature collections", function()
    local value = h.truthy(model.new({ name = "Features" }))
    h.eq(4, value.schema_version)
    h.truthy(json.is_array(value.windows))
    h.truthy(json.is_array(value.outlets))

    local window = model.new_window({
      id = "window-main",
      room_id = "room-main",
      side = "north",
      width_mm = 1200,
    })
    h.eq("part-main", window.part_id)
    h.eq(0, window.offset_mm)
    h.truthy(json.is_null(window.connects_to_room_id))
    h.eq(nil, window.height_mm)
    h.eq(nil, window.sill_height_mm)

    local outlet = model.new_outlet({
      id = "outlet-main",
      room_id = "room-main",
      side = "east",
    })
    h.eq("wall", outlet.placement)
    h.eq("part-main", outlet.part_id)
    h.eq("power", outlet.outlet_type)
    h.eq(2, outlet.slots)

    value.windows[1], value.outlets[1] = window, outlet
    h.eq(window, model.find(value, "window", window.id))
    h.eq(outlet, model.find(value, "outlet", outlet.id))
  end)

  it("round-trips v3 wall features and every tagged unknown value", function()
    local document = fixture("windows-outlets-v3.roomplan.json")
    local normalized, info = schema_v3.normalize(document)
    h.truthy(normalized, vim.inspect(info))
    h.eq(false, info.normalized)
    h.truthy(json.is_null(normalized.windows[1].connects_to_room_id))
    h.truthy(json.is_decimal(normalized.windows[1].vendor.exact))
    h.truthy(json.is_array(normalized.windows[1].vendor.empty))
    h.truthy(json.is_null(normalized.outlets[1].vendor.nothing))
    h.truthy(json.is_object(normalized.outlets[1].vendor.empty))

    local encoded = h.truthy(json.encode(normalized, { key_order = schema_v3.KEY_ORDER }))
    local windows_at = h.truthy(encoded:find('"windows"', 1, true))
    local outlets_at = h.truthy(encoded:find('"outlets"', 1, true))
    local furniture_at = h.truthy(encoded:find('"furniture"', 1, true))
    h.truthy(windows_at < outlets_at and outlets_at < furniture_at)
    local reloaded, reload_info = schema_v3.normalize(h.truthy(json.decode(encoded)))
    h.truthy(reloaded, vim.inspect(reload_info))
    h.truthy(json.deep_equal(normalized, reloaded))
    h.eq(encoded, h.truthy(json.encode(reloaded, { key_order = schema_v3.KEY_ORDER })))
  end)

  it("requires both v3 collections and validates their exact scalar contracts", function()
    local missing_windows = fixture("windows-outlets-v3.roomplan.json")
    missing_windows.windows = nil
    expect_failure(function()
      return schema_v3.normalize(missing_windows)
    end, "SCHEMA_REQUIRED", "$.windows")

    local cases = {
      { collection = "windows", key = "id", value = "door-wrong", code = "ID_PREFIX", path = "$.windows[1].id" },
      { collection = "windows", key = "connects_to_room_id", value = "outlet-wrong", code = "ID_PREFIX",
        path = "$.windows[1].connects_to_room_id" },
      { collection = "windows", key = "offset_mm", value = -1, code = "SCHEMA_INTEGER_MIN",
        path = "$.windows[1].offset_mm" },
      { collection = "windows", key = "width_mm", value = 0, code = "SCHEMA_INTEGER_MIN",
        path = "$.windows[1].width_mm" },
      { collection = "outlets", key = "id", value = "window-wrong", code = "ID_PREFIX",
        path = "$.outlets[1].id" },
      { collection = "outlets", key = "outlet_type", value = "mains", code = "SCHEMA_ENUM",
        path = "$.outlets[1].outlet_type" },
      { collection = "outlets", key = "slots", value = 0, code = "SCHEMA_INTEGER_MIN",
        path = "$.outlets[1].slots" },
      { collection = "outlets", key = "slots", value = 33, code = "SCHEMA_INTEGER_MAX",
        path = "$.outlets[1].slots" },
    }
    for _, case in ipairs(cases) do
      local document = fixture("windows-outlets-v3.roomplan.json")
      document[case.collection][1][case.key] = case.value
      expect_failure(function()
        return schema_v3.normalize(document)
      end, case.code, case.path)
    end
  end)

  it("accepts every centralized outlet type", function()
    h.eq("power", outlet_types.default)
    h.eq({ "power", "usb", "ethernet", "coax", "phone", "other" }, outlet_types.values)
    h.eq("Power", outlet_types.label("power"))
    h.eq("TV / coax", outlet_types.label("coax"))
    h.eq(nil, outlet_types.label("mains"))
    for _, outlet_type in ipairs(outlet_types.values) do
      h.truthy(outlet_types.valid(outlet_type))
      local document = fixture("windows-outlets-v3.roomplan.json")
      document.outlets[1].outlet_type = outlet_type
      h.truthy(schema_v3.normalize(document))
    end
    h.falsy(outlet_types.valid("mains"))

    local schema_text = table.concat(vim.fn.readfile(root .. "/schema/roomplan-v3.schema.json", "b"), "\n")
    local published, schema_err = json.decode(schema_text)
    h.truthy(published, vim.inspect(schema_err))
    h.eq(outlet_types.values, published["$defs"].outlet.properties.outlet_type.enum)
  end)

  it("requires window and outlet part IDs to exist in the owner room", function()
    local window = fixture("windows-outlets-v3.roomplan.json")
    window.windows[1].part_id = "part-missing"
    expect_failure(function()
      return schema_v3.normalize(window)
    end, "SCHEMA_WINDOW_PART", "$.windows[1].part_id")

    local outlet = fixture("windows-outlets-v3.roomplan.json")
    outlet.outlets[1].part_id = "part-missing"
    expect_failure(function()
      return schema_v3.normalize(outlet)
    end, "SCHEMA_OUTLET_PART", "$.outlets[1].part_id")
  end)

  it("indexes and generates globally reserved v3 IDs", function()
    h.eq("window-kitchen", h.truthy(ids.generate("window", "Kitchen", {})))
    h.eq("outlet-desk", h.truthy(ids.generate("outlet", "Desk", {})))

    local document = fixture("windows-outlets-v3.roomplan.json")
    document.windows[2] = json.deep_copy(document.windows[1])
    expect_failure(function()
      return schema_v3.normalize(document)
    end, "ID_DUPLICATE", "$")
  end)

  it("keeps v2 normalization immutable and migrates v2 to required empty collections", function()
    local source_document = fixture("compound-v2.roomplan.json")
    local original = json.deep_copy(source_document)
    local v2, v2_info = schema_v2.normalize(source_document)
    h.truthy(v2, vim.inspect(v2_info))
    h.eq(nil, v2.windows)
    h.eq(nil, v2.outlets)

    local migrated, info = schema.load(source_document)
    h.truthy(migrated, vim.inspect(info))
    h.eq(4, migrated.schema_version)
    h.truthy(info.migrated)
    h.truthy(json.is_array(migrated.windows))
    h.truthy(json.is_array(migrated.outlets))
    h.eq(0, #migrated.windows)
    h.eq(0, #migrated.outlets)
    h.truthy(json.deep_equal(original, source_document))
    h.eq("SCHEMA_MIGRATED_V3_TO_V4", info.migration_notes[#info.migration_notes].code)

    local explicit_v2 = h.truthy(schema.migrate(source_document, 2))
    h.eq(2, explicit_v2.schema_version)
    h.eq(nil, explicit_v2.windows)
    h.eq(nil, explicit_v2.outlets)
  end)

  it("rejects v2 root collisions without interpreting or mutating extension data", function()
    for _, field in ipairs({ "windows", "outlets" }) do
      local document = fixture("compound-v2.roomplan.json")
      document[field] = json.object({
        empty = json.array(),
        exact = json.decimal(1, "1250", -3),
        nothing = json.null,
      })
      local original = json.deep_copy(document)
      local normalized_v2, v2_info = schema_v2.normalize(document)
      h.truthy(normalized_v2, vim.inspect(v2_info))
      h.truthy(json.deep_equal(document[field], normalized_v2[field]))

      expect_failure(function()
        return schema.migrate(document, 3)
      end, "SCHEMA_MIGRATION_COLLISION", "$." .. field)
      h.truthy(json.deep_equal(original, document))
    end
  end)

  it("runs the complete v1-to-v3 migration chain", function()
    local document = fixture("migration-v1.roomplan.json")
    local migrated, notes, migrated_any = schema.migrate(document, 3)
    h.truthy(migrated, vim.inspect(notes))
    h.truthy(migrated_any)
    h.eq(3, migrated.schema_version)
    h.eq("part-main", migrated.rooms[1].footprint.parts[1].id)
    h.eq("part-main", migrated.doors[1].part_id)
    h.truthy(json.is_array(migrated.windows))
    h.truthy(json.is_array(migrated.outlets))
    h.eq("SCHEMA_MIGRATED_V1_TO_V2", notes[1].code)
    h.eq("SCHEMA_MIGRATED_V2_TO_V3", notes[2].code)
  end)
end)
