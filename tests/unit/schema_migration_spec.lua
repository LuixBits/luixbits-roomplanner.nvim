local h = require("tests.harness")

local json = require("roomplan.codec.json")
local footprint = require("roomplan.geometry.footprint")
local schema = require("roomplan.schema")
local schema_v2 = require("roomplan.schema.v2")
local schema_v1 = require("roomplan.schema.v1")

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

local function part(id, x, y, width, depth)
  return json.object({
    id = id,
    origin_mm = json.array({ x, y }),
    size_mm = json.array({ width, depth }),
  })
end

local function v2_furniture_footprint(room, item)
  local parts = {}
  for index, source_part in ipairs(item.footprint.parts) do
    local left2 = 2 * source_part.origin_mm[1]
    local bottom2 = 2 * source_part.origin_mm[2]
    parts[index] = {
      id = source_part.id,
      left2 = left2,
      bottom2 = bottom2,
      right2 = left2 + 2 * source_part.size_mm[1],
      top2 = bottom2 + 2 * source_part.size_mm[2],
    }
  end
  local local_shape = h.truthy(footprint.compound(parts, { require_ids = true }))
  local rotated =
    h.truthy(footprint.rotate_quarter(local_shape, item.rotation_deg, item.anchor2_mm[1], item.anchor2_mm[2]))
  local anchor_world_x2 = 2 * (room.origin_mm[1] + item.position_mm[1])
  local anchor_world_y2 = 2 * (room.origin_mm[2] + item.position_mm[2])
  return h.truthy(
    footprint.translate2(rotated, anchor_world_x2 - item.anchor2_mm[1], anchor_world_y2 - item.anchor2_mm[2])
  )
end

describe("schema v1 to v2 migration", function()
  it("matches the golden mapping and preserves odd centres exactly", function()
    local document = fixture("migration-v1.roomplan.json")
    local expected_source = fixture("migration-v1.expected-v2.roomplan.json")
    local expected, expected_err = schema_v2.normalize(expected_source)
    h.truthy(expected, vim.inspect(expected_err))
    local original = json.deep_copy(document)

    local migrated, err = schema.migrate(document, 2)
    h.truthy(migrated, vim.inspect(err))
    h.truthy(json.deep_equal(expected, migrated), "migrated document differs from the v2 golden fixture")
    h.truthy(json.deep_equal(original, document), "migration mutated its v1 input")

    h.eq(2, migrated.schema_version)
    h.eq(json.array({ 417, 503 }), migrated.furniture[1].position_mm)
    h.eq(json.array({ 501, 499 }), migrated.furniture[1].anchor2_mm)
    h.eq(777, migrated.furniture[1].height_mm)
    h.eq(json.array({ 701, 401 }), migrated.custom_templates[1].default_anchor2_mm)
    h.eq(733, migrated.custom_templates[1].default_height_mm)
    h.eq("part-main", migrated.rooms[1].footprint.parts[1].id)
    h.eq("part-main", migrated.doors[1].part_id)

    h.eq(nil, migrated.rooms[1].size_mm)
    h.eq(nil, migrated.furniture[1].center_mm)
    h.eq(nil, migrated.furniture[1].size_mm)
    h.eq(nil, migrated.custom_templates[1].shape)
    h.eq(nil, migrated.custom_templates[1].default_size_mm)
  end)

  it("preserves every tagged unknown subtree", function()
    local document = fixture("migration-v1.roomplan.json")
    local migrated = h.truthy(schema.migrate(document, 2))

    h.truthy(json.deep_equal(document.metadata.vendor, migrated.metadata.vendor))
    h.truthy(json.deep_equal(document.rooms[1].vendor, migrated.rooms[1].vendor))
    h.truthy(json.deep_equal(document.doors[1].vendor, migrated.doors[1].vendor))
    h.truthy(json.deep_equal(document.furniture[1].vendor, migrated.furniture[1].vendor))
    h.truthy(json.deep_equal(document.custom_templates[1].vendor, migrated.custom_templates[1].vendor))
    h.truthy(json.deep_equal(document.extensions, migrated.extensions))
    h.truthy(json.deep_equal(document["vendor-root"], migrated["vendor-root"]))

    local vendor = migrated.metadata.vendor
    h.truthy(json.is_object(vendor.empty_object))
    h.truthy(json.is_array(vendor.empty_array))
    h.truthy(json.is_null(vendor.nothing))
    h.truthy(json.is_decimal(vendor.exact_decimal))
    h.eq(false, migrated.settings.vendor_enabled)
  end)

  it("preserves odd furniture geometry through every quarter turn", function()
    for _, rotation in ipairs({ 0, 90, 180, 270 }) do
      local document = fixture("migration-v1.roomplan.json")
      document.furniture[1].rotation_deg = rotation
      local v1, v1_err = schema_v1.normalize(document)
      h.truthy(v1, vim.inspect(v1_err))
      local v2, v2_err = schema.migrate(document, 2)
      h.truthy(v2, vim.inspect(v2_err))

      local before = h.truthy(footprint.from_furniture(v1.rooms[1], v1.furniture[1]))
      local after = v2_furniture_footprint(v2.rooms[1], v2.furniture[1])
      h.eq(footprint.bounds2(before), footprint.bounds2(after))
      h.eq(footprint.area4(before), footprint.area4(after))
      h.eq(true, footprint.contains(before, after))
      h.eq(true, footprint.contains(after, before))
    end
  end)

  it("rejects every generated-field collision without mutating input", function()
    local cases = {
      { collection = "rooms", key = "footprint", path = "$.rooms[1].footprint" },
      { collection = "doors", key = "part_id", path = "$.doors[1].part_id" },
      { collection = "furniture", key = "position_mm", path = "$.furniture[1].position_mm" },
      { collection = "furniture", key = "anchor2_mm", path = "$.furniture[1].anchor2_mm" },
      { collection = "furniture", key = "footprint", path = "$.furniture[1].footprint" },
      { collection = "furniture", key = "height_mm", path = "$.furniture[1].height_mm" },
      {
        collection = "custom_templates",
        key = "default_footprint",
        path = "$.custom_templates[1].default_footprint",
      },
      {
        collection = "custom_templates",
        key = "default_anchor2_mm",
        path = "$.custom_templates[1].default_anchor2_mm",
      },
      {
        collection = "custom_templates",
        key = "default_height_mm",
        path = "$.custom_templates[1].default_height_mm",
      },
    }

    for _, case in ipairs(cases) do
      local document = fixture("migration-v1.roomplan.json")
      document[case.collection][1][case.key] = json.null
      local original = json.deep_copy(document)
      expect_failure(function() return schema.migrate(document, 2) end, "SCHEMA_MIGRATION_COLLISION", case.path)
      h.truthy(json.deep_equal(original, document), case.path .. " collision mutated its input")
    end
  end)

  it("rejects a collision even when its value matches the generated field", function()
    local document = fixture("migration-v1.roomplan.json")
    document.rooms[1].footprint = json.object({
      kind = "rect_union",
      parts = json.array({ part("part-main", 0, 0, 3001, 1999) }),
    })
    local original = json.deep_copy(document)
    expect_failure(
      function() return schema.migrate(document, 2) end,
      "SCHEMA_MIGRATION_COLLISION",
      "$.rooms[1].footprint"
    )
    h.truthy(json.deep_equal(original, document))
  end)

  it("normalizes v1 before transforming it", function()
    local document = h.truthy(json.decode([[
      {
        "format":"roomplan.nvim",
        "schema_version":1,
        "units":"mm",
        "rooms":[],
        "doors":[],
        "furniture":[],
        "custom_templates":[]
      }
    ]]))
    local migrated, err = schema.migrate(document, 2)
    h.truthy(migrated, vim.inspect(err))
    h.eq("Untitled plan", migrated.metadata.name)
    h.eq("", migrated.metadata.notes)
    h.eq(100, migrated.settings.grid_mm)
    h.eq(900, migrated.settings.default_door_width_mm)
    h.truthy(json.is_object(migrated.extensions))

    local malformed = fixture("migration-v1.roomplan.json")
    malformed.rooms[1].size_mm[1] = 0
    local original = json.deep_copy(malformed)
    expect_failure(function() return schema.migrate(malformed, 2) end, "SCHEMA_INTEGER_MIN", "$.rooms[1].size_mm[1]")
    h.truthy(json.deep_equal(original, malformed))
  end)

  it("rejects a future version and refuses a downgrade", function()
    local future = fixture("migration-v1.expected-v2.roomplan.json")
    future.schema_version = 5
    local future_original = json.deep_copy(future)
    expect_failure(function() return schema.migrate(future, 2) end, "SCHEMA_FUTURE_VERSION", "$.schema_version")
    h.truthy(json.deep_equal(future_original, future))

    local current = fixture("compound-v2.roomplan.json")
    local current_original = json.deep_copy(current)
    expect_failure(function() return schema.migrate(current, 1) end, "SCHEMA_DOWNGRADE_UNSUPPORTED", "$.schema_version")
    h.truthy(json.deep_equal(current_original, current))
  end)

  it("writes active schema v4 and rejects older unmigrated snapshots", function()
    local document = h.truthy(schema.load(fixture("windows-outlets-v3.roomplan.json")))
    local encoded, encode_info = schema.encode(document)
    h.truthy(encoded, vim.inspect(encode_info))
    local decoded, decode_err = schema.decode(encoded)
    h.truthy(decoded, vim.inspect(decode_err))
    h.eq(4, decoded.schema_version)
    local normalized, normalize_err = schema.normalize(document)
    h.truthy(normalized, vim.inspect(normalize_err))
    h.truthy(json.deep_equal(normalized, decoded))

    local v2 = fixture("compound-v2.roomplan.json")
    expect_failure(function() return schema.encode(v2) end, "SCHEMA_VERSION", "$.schema_version")

    local legacy = fixture("migration-v1.roomplan.json")
    expect_failure(function() return schema.encode(legacy) end, "SCHEMA_VERSION", "$.schema_version")
  end)
end)

describe("schema v2 normalization", function()
  it("accepts and canonically round-trips the compound fixture", function()
    local document = fixture("compound-v2.roomplan.json")
    local normalized, info = schema_v2.normalize(document)
    h.truthy(normalized, vim.inspect(info))
    h.eq(false, info.normalized)
    h.eq(2, normalized.schema_version)
    h.eq(2, #normalized.rooms[1].footprint.parts)
    h.eq("part-east", normalized.rooms[1].footprint.parts[2].id)
    h.eq(json.array({ 1000, 500 }), normalized.furniture[1].anchor2_mm)

    local encoded, encode_err = json.encode(normalized, { key_order = schema_v2.KEY_ORDER })
    h.truthy(encoded, vim.inspect(encode_err))
    local decoded, decode_err = json.decode(encoded)
    h.truthy(decoded, vim.inspect(decode_err))
    local reloaded, reload_info = schema_v2.normalize(decoded)
    h.truthy(reloaded, vim.inspect(reload_info))
    h.truthy(json.deep_equal(normalized, reloaded))
  end)

  it("rejects stale v1 geometry fields instead of retaining two authorities", function()
    local cases = {
      {
        collection = "rooms",
        key = "size_mm",
        value = json.array({ 4000, 3000 }),
        path = "$.rooms[1].size_mm",
      },
      {
        collection = "furniture",
        key = "center_mm",
        value = json.array({ 1200, 1000 }),
        path = "$.furniture[1].center_mm",
      },
      {
        collection = "furniture",
        key = "size_mm",
        value = json.array({ 1000, 1000, 850 }),
        path = "$.furniture[1].size_mm",
      },
      {
        collection = "custom_templates",
        key = "shape",
        value = "rectangle",
        path = "$.custom_templates[1].shape",
      },
      {
        collection = "custom_templates",
        key = "default_size_mm",
        value = json.array({ 1000, 1000, 850 }),
        path = "$.custom_templates[1].default_size_mm",
      },
    }

    for _, case in ipairs(cases) do
      local document = fixture("compound-v2.roomplan.json")
      document[case.collection][1][case.key] = case.value
      expect_failure(function() return schema_v2.normalize(document) end, "SCHEMA_STALE_FIELD", case.path)
    end
  end)

  it("reports compound topology failures at the owning footprint", function()
    local cases = {
      {
        label = "duplicate part ID",
        parts = json.array({
          part("part-main", 0, 0, 4000, 3000),
          part("part-main", 4000, 0, 1500, 1000),
        }),
      },
      {
        label = "positive overlap",
        parts = json.array({
          part("part-main", 0, 0, 4000, 3000),
          part("part-east", 3500, 0, 1500, 1000),
        }),
      },
      {
        label = "disconnected component",
        parts = json.array({
          part("part-main", 0, 0, 4000, 3000),
          part("part-east", 6000, 0, 1500, 1000),
        }),
      },
      {
        label = "enclosed hole",
        parts = json.array({
          part("part-south", 0, 0, 3000, 1000),
          part("part-north", 0, 2000, 3000, 1000),
          part("part-west", 0, 1000, 1000, 1000),
          part("part-east", 2000, 1000, 1000, 1000),
        }),
      },
    }

    for _, case in ipairs(cases) do
      local document = fixture("compound-v2.roomplan.json")
      document.rooms[1].footprint.parts = case.parts
      expect_failure(
        function() return schema_v2.normalize(document) end,
        "SCHEMA_FOOTPRINT_TOPOLOGY",
        "$.rooms[1].footprint"
      )
    end
  end)

  it("keeps malformed footprint scalar paths precise", function()
    local document = fixture("compound-v2.roomplan.json")
    document.rooms[1].footprint.parts[2].size_mm[1] = 0
    expect_failure(
      function() return schema_v2.normalize(document) end,
      "SCHEMA_INTEGER_MIN",
      "$.rooms[1].footprint.parts[2].size_mm[1]"
    )
  end)

  it("requires a real referenced part but keeps aperture repair drafts loadable", function()
    local missing = fixture("compound-v2.roomplan.json")
    missing.doors[1].part_id = "part-missing"
    expect_failure(function() return schema_v2.normalize(missing) end, "SCHEMA_DOOR_PART", "$.doors[1].part_id")

    local absent = fixture("compound-v2.roomplan.json")
    absent.doors[1].part_id = nil
    expect_failure(function() return schema_v2.normalize(absent) end, "SCHEMA_REQUIRED", "$.doors[1].part_id")

    local internal = fixture("compound-v2.roomplan.json")
    internal.doors[1].part_id = "part-main"
    internal.doors[1].side = "east"
    internal.doors[1].offset_mm = 100
    internal.doors[1].width_mm = 800
    local internal_plan, internal_info = schema_v2.normalize(internal)
    h.truthy(internal_plan, vim.inspect(internal_info))

    local overrun = fixture("compound-v2.roomplan.json")
    overrun.doors[1].part_id = "part-main"
    overrun.doors[1].side = "north"
    overrun.doors[1].offset_mm = 3500
    overrun.doors[1].width_mm = 900
    local overrun_plan, overrun_info = schema_v2.normalize(overrun)
    h.truthy(overrun_plan, vim.inspect(overrun_info))
  end)

  it("requires anchors to lie on or inside their footprints", function()
    local boundary = fixture("compound-v2.roomplan.json")
    boundary.furniture[1].anchor2_mm = json.array({ 0, 0 })
    local boundary_plan, boundary_info = schema_v2.normalize(boundary)
    h.truthy(boundary_plan, vim.inspect(boundary_info))

    local outside = fixture("compound-v2.roomplan.json")
    outside.furniture[1].anchor2_mm = json.array({ -1, 0 })
    expect_failure(
      function() return schema_v2.normalize(outside) end,
      "SCHEMA_ANCHOR_OUTSIDE",
      "$.furniture[1].anchor2_mm"
    )

    local template = fixture("compound-v2.roomplan.json")
    template.custom_templates[1].default_anchor2_mm = json.array({ 3000, 3000 })
    expect_failure(
      function() return schema_v2.normalize(template) end,
      "SCHEMA_ANCHOR_OUTSIDE",
      "$.custom_templates[1].default_anchor2_mm"
    )
  end)
end)
