local json = require("roomplan.codec.json")
local schema = require("roomplan.schema")
local model = require("roomplan.model")
local ids = require("roomplan.ids")
local units = require("roomplan.units")
local history = require("roomplan.history")
local catalog = require("roomplan.catalog")

local function assert_nil(value, message)
  if value ~= nil then
    error(message or "expected nil", 2)
  end
end

describe("pure model foundation", function()
  it("preserves every tagged JSON type", function()
    local value = assert(json.decode([[{"object":{},"array":[],"null":null,"decimal":1.250,"boolean":false}]]))
    assert_true(json.is_object(value))
    assert_true(json.is_object(value.object))
    assert_true(json.is_array(value.array))
    assert_true(json.is_null(value.null))
    assert_true(json.is_decimal(value.decimal))
    assert_equal(false, value.boolean)
    local copy = json.deep_copy(value)
    assert_true(json.deep_equal(value, copy))
    assert_true(json.is_decimal(copy.decimal))
  end)

  it("rejects duplicate decoded keys and non-strict JSON", function()
    local value, err = json.decode([[{"a":1,"\u0061":2}]])
    assert_nil(value)
    assert_equal("JSON_DUPLICATE_KEY", err.code)
    assert_equal(1, err.line)
    assert_true(err.column > 1)
    value, err = json.decode([[{"a":1,}]])
    assert_nil(value)
    assert_equal("JSON_TRAILING_COMMA", err.code)
    value, err = json.decode([[01]])
    assert_nil(value)
    assert_equal("JSON_INVALID_NUMBER", err.code)
  end)

  it("decodes surrogate pairs and rejects malformed Unicode", function()
    local value = assert(json.decode([["\uD83D\uDE00"]]))
    assert_equal("\240\159\152\128", value)
    local malformed, err = json.decode([["\uD83Dx"]])
    assert_nil(malformed)
    assert_equal("JSON_INVALID_SURROGATE", err.code)
    malformed, err = json.decode('"\255"')
    assert_nil(malformed)
    assert_equal("JSON_INVALID_UTF8", err.code)
  end)

  it("canonicalizes exact decimals without floating point", function()
    local cases = {
      ["1.2500"] = "1.25\n",
      ["100e-2"] = "1\n",
      ["0.000001"] = "0.000001\n",
      ["0.0000001"] = "1e-7\n",
      ["1e21"] = "1e21\n",
      ["-0.0"] = "0\n",
    }
    for source, expected in pairs(cases) do
      local decoded = assert(json.decode(source))
      assert_equal(expected, assert(json.encode(decoded)))
    end
  end)

  it("enforces codec resource ceilings", function()
    local value, err = json.decode("[[[]]]", { max_depth = 2 })
    assert_nil(value)
    assert_equal("JSON_DEPTH_LIMIT", err.code)
    value, err = json.decode("[1,2]", { max_values = 2 })
    assert_nil(value)
    assert_equal("JSON_VALUE_LIMIT", err.code)
    value, err = json.decode('"abcd"', { max_string_bytes = 3 })
    assert_nil(value)
    assert_equal("JSON_STRING_LIMIT", err.code)
  end)

  it("orders known fields first and unknown fields byte-lexicographically", function()
    local value = json.object({
      zebra = true,
      units = "mm",
      format = "roomplan.nvim",
      alpha = true,
      schema_version = 1,
    })
    local encoded = assert(json.encode(value))
    local format_at = assert(encoded:find('"format"', 1, true))
    local version_at = assert(encoded:find('"schema_version"', 1, true))
    local units_at = assert(encoded:find('"units"', 1, true))
    local alpha_at = assert(encoded:find('"alpha"', 1, true))
    local zebra_at = assert(encoded:find('"zebra"', 1, true))
    assert_true(format_at < version_at and version_at < units_at and units_at < alpha_at and alpha_at < zebra_at)
  end)

  it("constructs and deterministically round-trips an empty current model", function()
    local plan = assert(model.new({ name = "Test flat" }))
    assert_equal("roomplan.nvim", plan.format)
    assert_equal(schema.CURRENT_VERSION, plan.schema_version)
    assert_equal(100, plan.settings.normal_step_mm)
    assert_nil(plan.settings.default_wall_thickness_mm)
    assert_true(json.is_array(plan.rooms))
    assert_true(json.is_object(plan.extensions))
    local encoded = assert(model.encode(plan))
    assert_equal("\n", encoded:sub(-1))
    local loaded, info = model.decode(encoded)
    assert_true(loaded ~= nil, info and info.message)
    assert_true(model.deep_equal(plan, loaded))
    assert_equal(false, info.normalized)
    assert_equal(encoded, assert(model.encode(loaded)))
  end)

  it("loads explicit schema-v1 rectangles into the current footprint authority", function()
    local source = [=[
      {
        "format":"roomplan.nvim",
        "schema_version":1,
        "units":"mm",
        "metadata":{"name":"Footprint compatibility","notes":""},
        "settings":{},
        "rooms":[{"id":"room-a","name":"A","origin_mm":[-100,50],"size_mm":[1001,999]}],
        "doors":[],
        "furniture":[{
          "id":"furniture-a","room_id":"room-a","template_id":"builtin:chair",
          "name":"Chair","category":"seating","center_mm":[500,500],
          "size_mm":[501,499,800],"rotation_deg":90
        }],
        "custom_templates":[],
        "extensions":{}
      }
    ]=]
    local plan, info = model.decode(source)
    assert_true(plan ~= nil, vim.inspect(info))
    assert_equal(3, plan.schema_version)
    assert_true(info.migrated)
    assert_nil(plan.rooms[1].size_mm)
    assert_nil(plan.furniture[1].center_mm)
    assert_equal({ 1001, 999 }, plan.rooms[1].footprint.parts[1].size_mm)
    assert_equal({ 500, 500 }, plan.furniture[1].position_mm)
    local encoded = assert(model.encode(plan))
    assert_true(encoded:find('"footprint"', 1, true) ~= nil)
    assert_nil(encoded:find('"center_mm"', 1, true))
    assert_true(model.deep_equal(plan, assert(model.decode(encoded))))
  end)

  it("constructs canonical v2 entities without retaining v1 geometry", function()
    local options = { schema_version = 2 }
    local room = model.new_room({
      id = "room-a", name = "A", origin_mm = { 10, 20 }, size_mm = { 100, 200 },
    }, options)
    assert_nil(room.size_mm)
    assert_equal({ 100, 200 }, room.footprint.parts[1].size_mm)
    assert_true(json.is_array(room.footprint.parts))

    local furniture = model.new_furniture({
      id = "furniture-a", room_id = room.id, name = "Chair", category = "seating",
      position_mm = { 50, 60 }, size_mm = { 20, 30, 40 },
    }, options)
    assert_nil(furniture.center_mm)
    assert_nil(furniture.size_mm)
    assert_equal({ 50, 60 }, furniture.position_mm)
    assert_equal({ 20, 30 }, furniture.anchor2_mm)
    assert_equal(40, furniture.height_mm)

    local door = model.new_door({
      id = "door-a", room_id = room.id, side = "south", width_mm = 10,
    }, options)
    assert_equal("part-main", door.part_id)

    local template = model.new_custom_template({
      id = "custom:chair", name = "Chair", category = "seating",
      default_size_mm = { 20, 30, 40 },
    }, options)
    assert_nil(template.shape)
    assert_nil(template.default_size_mm)
    assert_equal({ 20, 30 }, template.default_anchor2_mm)
    assert_equal(40, template.default_height_mm)
  end)

  it("normalizes fixed defaults and preserves nested extension types", function()
    local source = [=[
      {
        "format":"roomplan.nvim",
        "schema_version":1,
        "units":"mm",
        "metadata":{"x-extra":{"empty":{},"nothing":null}},
        "settings":{"foreign":[1.25,[]],"default_wall_thickness_mm":123},
        "rooms":[{"id":"room-a","name":"A","origin_mm":[0,0],"size_mm":[1000,1000],"plugin":{"v":1.5}}],
        "doors":[],
        "furniture":[],
        "custom_templates":[]
      }
    ]=]
    local plan, info = schema.decode(source)
    assert_true(plan ~= nil, info and info.message)
    assert_true(info.normalized)
    assert_true(info.migrated)
    assert_equal(3, plan.schema_version)
    assert_equal("Untitled plan", plan.metadata.name)
    assert_equal(100, plan.settings.grid_mm)
    assert_true(json.is_object(plan.metadata["x-extra"].empty))
    assert_true(json.is_null(plan.metadata["x-extra"].nothing))
    assert_true(json.is_decimal(plan.settings.foreign[1]))
    assert_true(json.is_array(plan.settings.foreign[2]))
    -- Former schema fields are retained as ordinary unknown JSON data so old
    -- plans remain losslessly readable without keeping inert runtime settings.
    assert_true(json.is_decimal(plan.settings.default_wall_thickness_mm))
    local sign, coefficient, exponent = json.decimal_parts(plan.settings.default_wall_thickness_mm)
    assert_equal(sign, 1)
    assert_equal(coefficient, "123")
    assert_equal(exponent, 0)
    assert_true(json.is_decimal(plan.rooms[1].plugin.v))
    local reloaded = assert(schema.decode(assert(schema.encode(plan))))
    assert_true(json.deep_equal(plan, reloaded))
  end)

  it("accepts the current schema, migrates v2, and rejects missing, zero, and future versions", function()
    local function document(version_member, wall_collections)
      return '{"format":"roomplan.nvim"' .. version_member .. ',"units":"mm","rooms":[],"doors":[]'
        .. (wall_collections and ',"windows":[],"outlets":[]' or '')
        .. ',"furniture":[],"custom_templates":[]}'
    end
    local value, err = schema.decode(document(""))
    assert_nil(value)
    assert_equal("SCHEMA_VERSION_MISSING", err.code)
    value, err = schema.decode(document(',"schema_version":0'))
    assert_nil(value)
    assert_equal("SCHEMA_VERSION", err.code)
    value, err = schema.decode(document(',"schema_version":2'))
    assert_true(value ~= nil, vim.inspect(err))
    assert_equal(3, value.schema_version)
    value, err = schema.decode(document(',"schema_version":3', true))
    assert_true(value ~= nil, vim.inspect(err))
    assert_equal(3, value.schema_version)
    value, err = schema.decode(document(',"schema_version":4'))
    assert_nil(value)
    assert_equal("SCHEMA_FUTURE_VERSION", err.code)
  end)

  it("reports valid non-object JSON roots as schema errors", function()
    local value, err = schema.decode("false")
    assert_nil(value)
    assert_equal("SCHEMA_ROOT", err.code)
    value, err = schema.decode("null")
    assert_nil(value)
    assert_equal("SCHEMA_ROOT", err.code)
  end)

  it("enforces global prefixed IDs", function()
    local plan = assert(model.new())
    plan.rooms[1] = model.new_room({ id = "room-a", name = "A", size_mm = { 1000, 1000 } })
    plan.furniture[1] = model.new_furniture({
      id = "furniture-a",
      room_id = "room-a",
      name = "A",
      category = "custom",
      size_mm = { 100, 100, 100 },
    })
    local valid, err = schema.validate(plan)
    assert_true(valid, err and err.message)
    plan.furniture[1].id = "room-a"
    valid, err = schema.validate(plan)
    assert_equal(false, valid)
    assert_true(err.code == "ID_PREFIX" or err.code == "ID_DUPLICATE")
  end)

  it("generates readable collision-safe IDs", function()
    local used = { ["room-living-room"] = true, ["room-living-room-2"] = true }
    assert_equal("room-living-room-3", assert(ids.generate("room", "Living Room", used)))
    local valid = ids.validate("furniture-sofa-1", "furniture")
    assert_true(valid)
    valid = ids.validate("sofa-1", "furniture")
    assert_equal(false, valid)
  end)

  it("parses metric input exactly", function()
    assert_equal(2100, assert(units.parse("2100")))
    assert_equal(2100, assert(units.parse("2100mm")))
    assert_equal(2100, assert(units.parse("210cm")))
    assert_equal(2100, assert(units.parse("2.1m")))
    assert_equal(-1200, assert(units.parse_coordinate(" -1.2m ")))
    local value, err = units.parse("1.5mm")
    assert_nil(value)
    assert_equal("UNIT_FRACTIONAL_MM", err.code)
    value = units.parse("2 m")
    assert_nil(value)
    value = units.parse("2e3mm")
    assert_nil(value)
    value = units.parse(".5m")
    assert_nil(value)
  end)

  it("keeps semantic history and savepoint state", function()
    local initial = assert(model.new({ name = "Initial" }))
    local snapshots = history.new(initial)
    assert_equal(false, snapshots:is_dirty())
    local changed = model.deep_copy(initial)
    changed.metadata.name = "Changed"
    local node = assert(snapshots:push(changed, { label = "Rename plan" }))
    assert_equal("Rename plan", node.label)
    assert_true(snapshots:is_dirty())
    assert(snapshots:mark_saved())
    assert_equal(false, snapshots:is_dirty())
    assert(snapshots:undo())
    assert_true(snapshots:is_dirty())
    assert(snapshots:redo())
    assert_equal(false, snapshots:is_dirty())
    snapshots:dispose()
  end)

  it("preserves redo on no-op and drops it only on a real branch", function()
    local initial = assert(model.new({ name = "A" }))
    local snapshots = history.new(initial, { durable = false })
    local second = model.deep_copy(initial)
    second.metadata.name = "B"
    assert(snapshots:push(second))
    assert(snapshots:undo())
    local no_node, err = snapshots:push(initial)
    assert_nil(no_node)
    assert_equal("HISTORY_NO_CHANGE", err.code)
    assert_true(snapshots:can_redo())
    local branch = model.deep_copy(initial)
    branch.metadata.name = "C"
    assert(snapshots:push(branch))
    assert_equal(false, snapshots:can_redo())
    assert_true(snapshots:is_dirty())
    snapshots:dispose()
  end)

  it("bounds snapshot count without dropping the current model", function()
    local initial = assert(model.new({ name = "0" }))
    local snapshots = history.new(initial, { max_nodes = 3 })
    local index = 1
    while index <= 5 do
      local next_model = model.deep_copy(snapshots:current_model())
      next_model.metadata.name = tostring(index)
      assert(snapshots:push(next_model))
      index = index + 1
    end
    assert_equal(3, snapshots:stats().nodes)
    assert_equal("5", snapshots:current_model().metadata.name)
    snapshots:dispose()
  end)

  it("exposes the complete generic furniture catalogue as copies", function()
    local all = catalog.all()
    assert_equal(13, #all)
    local sofa = assert(catalog.get("builtin:sofa"))
    assert_equal(850, sofa.default_size_mm[3])
    sofa.default_size_mm[3] = 1
    assert_equal(850, catalog.get("builtin:sofa").default_size_mm[3])
    assert_true(catalog.exists("builtin:custom-rectangle"))
  end)
end)
