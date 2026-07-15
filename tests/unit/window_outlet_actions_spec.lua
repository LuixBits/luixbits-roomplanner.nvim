local h = require("tests.harness")

local actions = require("roomplan.actions")
local json = require("roomplan.codec.json")
local model = require("roomplan.model")
local schema = require("roomplan.schema")
local validate = require("roomplan.validate")

local function room(id, x, y, width, depth)
  return model.new_room({
    id = id,
    name = id,
    origin_mm = { x, y },
    size_mm = { width, depth },
  })
end

local function normalized(value)
  local valid, err, result = schema.validate(value)
  return h.truthy(valid, vim.inspect(err)) and result
end

local function base_model()
  local value = h.truthy(model.new({ name = "Wall action test" }))
  value.rooms[1] = room("room-main", 0, 0, 6000, 4000)
  return normalized(value)
end

local function apply(value, action)
  local changed, result = actions.apply(value, action)
  return h.truthy(changed, vim.inspect(result)), h.truthy(result)
end

local function touched_set(values)
  local result = {}
  for _, value in ipairs(values or {}) do result[value.kind .. ":" .. value.id] = true end
  return result
end

describe("window and outlet atomic actions", function()
  it("adds, edits, and moves wall features through canonical edit patches", function()
    local initial = base_model()
    local value, result = apply(initial, {
      type = "add_window",
      window = {
        id = "window-south",
        room_id = "room-main",
        side = "south",
        offset_mm = 500,
        width_mm = 1000,
        vendor = json.object({ exact = json.decimal(1, "125", -2) }),
      },
    })
    h.eq(0, #initial.windows)
    h.eq({ { kind = "window", id = "window-south" } }, result.touched)
    h.truthy(json.is_object(value.windows[1]))
    h.truthy(json.is_null(value.windows[1].connects_to_room_id))
    h.truthy(json.is_decimal(value.windows[1].vendor.exact))

    value, result = apply(value, {
      type = "edit_window",
      id = "window-south",
      patch = { offset_mm = 1800 },
    })
    h.eq(1800, value.windows[1].offset_mm)
    h.eq({ { kind = "window", id = "window-south" } }, result.touched)

    value, result = apply(value, {
      type = "add_outlet",
      outlet = {
        id = "outlet-west",
        room_id = "room-main",
        side = "west",
        offset_mm = 600,
      },
    })
    h.eq("power", value.outlets[1].outlet_type)
    h.eq(2, value.outlets[1].slots)
    h.eq({ { kind = "outlet", id = "outlet-west" } }, result.touched)

    value, result = apply(value, {
      type = "edit_outlet",
      id = "outlet-west",
      patch = { offset_mm = 900, outlet_type = "usb", slots = 4 },
    })
    h.eq(900, value.outlets[1].offset_mm)
    h.eq("usb", value.outlets[1].outlet_type)
    h.eq(4, value.outlets[1].slots)
    h.eq({ { kind = "outlet", id = "outlet-west" } }, result.touched)

    local _, summary = validate.run(value)
    h.truthy(summary.valid)
  end)

  it("duplicates and deletes both feature kinds without mutating prior snapshots", function()
    local value = base_model()
    value = apply(value, {
      type = "add_window",
      window = {
        id = "window-source", room_id = "room-main", side = "north",
        offset_mm = 500, width_mm = 1000,
      },
    })
    local before_window_duplicate = value
    local window_result
    value, window_result = apply(value, {
      type = "duplicate_window", id = "window-source", new_id = "window-copy",
    })
    h.eq(1, #before_window_duplicate.windows)
    h.eq(2, #value.windows)
    h.eq(1500, value.windows[2].offset_mm)
    h.eq("window-source", window_result.metadata.source_id)
    h.eq({ { kind = "window", id = "window-copy" } }, window_result.touched)

    value = apply(value, {
      type = "add_outlet",
      outlet = {
        id = "outlet-source", room_id = "room-main", side = "east",
        offset_mm = 700, outlet_type = "ethernet", slots = 2,
      },
    })
    local outlet_result
    value, outlet_result = apply(value, {
      type = "duplicate_outlet", id = "outlet-source", new_id = "outlet-copy",
    })
    h.eq(2, #value.outlets)
    h.eq(800, value.outlets[2].offset_mm)
    h.eq("outlet-source", outlet_result.metadata.source_id)
    h.eq({ { kind = "outlet", id = "outlet-copy" } }, outlet_result.touched)

    local before_window_delete = value
    local delete_result
    value, delete_result = apply(value, { type = "delete_window", id = "window-copy" })
    h.eq(2, #before_window_delete.windows)
    h.eq(1, #value.windows)
    h.eq({ { kind = "window", id = "window-copy" } }, delete_result.touched)

    local before_outlet_delete = value
    value, delete_result = apply(value, { type = "delete_outlet", id = "outlet-copy" })
    h.eq(2, #before_outlet_delete.outlets)
    h.eq(1, #value.outlets)
    h.eq({ { kind = "outlet", id = "outlet-copy" } }, delete_result.touched)
  end)

  it("cascade-deletes owner and connected features while retaining unrelated ones", function()
    local value = h.truthy(model.new({ name = "Cascade" }))
    value.rooms[1] = room("room-main", 0, 0, 4000, 3000)
    value.rooms[2] = room("room-annex", 4000, 0, 3000, 3000)
    value.windows[1] = model.new_window({
      id = "window-main", room_id = "room-main", side = "south",
      offset_mm = 200, width_mm = 700,
    })
    value.windows[2] = model.new_window({
      id = "window-connected", room_id = "room-annex", connects_to_room_id = "room-main",
      side = "west", offset_mm = 1000, width_mm = 700,
    })
    value.windows[3] = model.new_window({
      id = "window-keep", room_id = "room-annex", side = "east",
      offset_mm = 1200, width_mm = 700,
    })
    value.outlets[1] = model.new_outlet({
      id = "outlet-main", room_id = "room-main", side = "north", offset_mm = 500,
    })
    value.outlets[2] = model.new_outlet({
      id = "outlet-keep", room_id = "room-annex", side = "south", offset_mm = 500,
    })
    value = normalized(value)
    local _, before_summary = validate.run(value)
    h.truthy(before_summary.valid)

    local dependencies = actions.room_dependencies(value, "room-main")
    h.eq({ "window-main" }, dependencies.owner_windows)
    h.eq({ "window-connected" }, dependencies.connected_windows)
    h.eq({ "outlet-main" }, dependencies.outlets)

    local original = value
    local result
    value, result = apply(value, { type = "delete_room_cascade", id = "room-main" })
    h.eq(2, #original.rooms)
    h.eq(3, #original.windows)
    h.eq(2, #original.outlets)
    h.eq(1, #value.rooms)
    h.eq("room-annex", value.rooms[1].id)
    h.eq({ "window-keep" }, vim.tbl_map(function(item) return item.id end, value.windows))
    h.eq({ "outlet-keep" }, vim.tbl_map(function(item) return item.id end, value.outlets))

    local touched = touched_set(result.touched)
    for _, key in ipairs({
      "room:room-main", "window:window-main", "window:window-connected", "outlet:outlet-main",
    }) do
      h.truthy(touched[key], "missing touched dependency " .. key)
    end
  end)

  it("rejects malformed and unsafe wall-feature mutations atomically", function()
    local value = base_model()
    local changed, err = actions.apply(value, {
      type = "add_outlet",
      outlet = {
        id = "outlet-invalid", room_id = "room-main", side = "east",
        offset_mm = 500, outlet_type = "power", slots = 33,
      },
    })
    h.eq(nil, changed)
    h.eq("STRUCTURAL_INVALID", h.truthy(err).code)
    h.eq(0, #value.outlets)

    changed, err = actions.apply(value, {
      type = "add_window",
      window = {
        id = "window-overrun", room_id = "room-main", side = "north",
        offset_mm = 5500, width_mm = 1000,
      },
    })
    h.eq(nil, changed)
    h.eq("LAYOUT_BLOCKED", h.truthy(err).code)
    h.eq(0, #value.windows)
  end)
end)
