-- Opt-in informational benchmark for RoomPlan's reference workload.
-- It intentionally has no pass/fail timing threshold: shared and CI machines
-- are too noisy for timing to be a reliable release gate.

local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h")
vim.opt.runtimepath:prepend(root)

local config = require("roomplan.config")
local model = require("roomplan.model")
local raster = require("roomplan.render.raster")
local viewport = require("roomplan.render.viewport")
local scene_builder = require("roomplan.scene.build")
local validate = require("roomplan.validate")

local WIDTH = 160
local HEIGHT = 50
local ROOM_COLUMNS = 5
local ROOM_ROWS = 4
local ROOM_WIDTH = 6000
local ROOM_DEPTH = 5000

local function room_id(column, row)
  return string.format("room-%02d", (row - 1) * ROOM_COLUMNS + column)
end

local function append(collection, value)
  collection[#collection + 1] = value
end

local function reference_model()
  local plan = assert(model.new({ name = "RoomPlan reference benchmark" }))

  for row = 1, ROOM_ROWS do
    for column = 1, ROOM_COLUMNS do
      append(plan.rooms, model.new_room({
        id = room_id(column, row),
        name = string.format("Room %d/%d", column, row),
        origin_mm = { (column - 1) * ROOM_WIDTH, (row - 1) * ROOM_DEPTH },
        size_mm = { ROOM_WIDTH, ROOM_DEPTH },
      }))
    end
  end

  local door_number = 0
  local shared_edges = {}
  for row = 1, ROOM_ROWS do
    for column = 1, ROOM_COLUMNS - 1 do
      shared_edges[#shared_edges + 1] = {
        owner = room_id(column, row),
        connected = room_id(column + 1, row),
        side = "east",
      }
    end
  end
  for row = 1, ROOM_ROWS - 1 do
    for column = 1, ROOM_COLUMNS do
      shared_edges[#shared_edges + 1] = {
        owner = room_id(column, row),
        connected = room_id(column, row + 1),
        side = "north",
      }
    end
  end
  for index, edge in ipairs(shared_edges) do
    door_number = door_number + 1
    append(plan.doors, model.new_door({
      id = string.format("door-%03d", door_number),
      room_id = edge.owner,
      connects_to_room_id = edge.connected,
      side = edge.side,
      offset_mm = 1000,
      width_mm = 800,
      hinge = index % 2 == 0 and "end" or "start",
      opens_into = "connected",
      open_angle_deg = 90,
    }))
  end
  for index = 1, 19 do
    local edge = shared_edges[index]
    door_number = door_number + 1
    append(plan.doors, model.new_door({
      id = string.format("door-%03d", door_number),
      room_id = edge.owner,
      connects_to_room_id = edge.connected,
      side = edge.side,
      offset_mm = 3200,
      width_mm = 800,
      hinge = index % 2 == 0 and "start" or "end",
      opens_into = "connected",
      open_angle_deg = 90,
    }))
  end

  local furniture_number = 0
  local centers_x = { 700, 1800, 2900, 4000, 5100 }
  local centers_y = { 1300, 3600 }
  for room_number = 1, #plan.rooms do
    for row = 1, #centers_y do
      for column = 1, #centers_x do
        furniture_number = furniture_number + 1
        append(plan.furniture, model.new_furniture({
          id = string.format("furniture-%03d", furniture_number),
          room_id = plan.rooms[room_number].id,
          template_id = "builtin:chair",
          name = "Chair " .. furniture_number,
          category = "seating",
          center_mm = { centers_x[column], centers_y[row] },
          size_mm = { 700, 600, 900 },
          rotation_deg = (furniture_number % 2) * 90,
        }))
      end
    end
  end

  assert(#plan.rooms == 20, "reference workload must contain 20 rooms")
  assert(#plan.doors == 50, "reference workload must contain 50 doors")
  assert(#plan.furniture == 200, "reference workload must contain 200 furniture items")
  return plan
end

local function percentile(sorted, fraction)
  return sorted[math.max(1, math.ceil(#sorted * fraction))]
end

local function benchmark(name, samples, callback)
  for _ = 1, 3 do callback() end
  collectgarbage("collect")
  local timings = {}
  for index = 1, samples do
    local started = vim.uv.hrtime()
    callback()
    timings[index] = (vim.uv.hrtime() - started) / 1000000
  end
  table.sort(timings)
  local result = {
    name = name,
    median = percentile(timings, 0.50),
    p95 = percentile(timings, 0.95),
  }
  io.stdout:write(string.format("%-18s median %8.2f ms  p95 %8.2f ms\n", result.name, result.median, result.p95))
  return result
end

local function sample_count()
  local value = tonumber(os.getenv("ROOMPLAN_BENCH_SAMPLES")) or 15
  value = math.floor(value)
  assert(value >= 5 and value <= 1000, "ROOMPLAN_BENCH_SAMPLES must be between 5 and 1000")
  return value
end

local function run()
  local plan = reference_model()
  local samples = sample_count()
  local limits = config.defaults().limits
  local diagnostics, summary = validate.run(plan, { limits = limits })
  assert(summary.structural_errors == 0, "reference workload is structurally invalid")

  local render_options = {
    show_grid = false,
    show_dimensions = true,
    show_labels = true,
  }
  local function redraw()
    local scene = scene_builder.build(plan, diagnostics, render_options)
    local view = viewport.fit_scene(scene, WIDTH, HEIGHT, {
      cell_aspect = 2,
      fit_margin_cells = 2,
    })
    return raster.rasterize(scene, view, {
      width = WIDTH,
      height = HEIGHT,
      glyph_mode = "ascii",
      width_fn = function(value) return #value end,
    })
  end

  io.stdout:write(string.format(
    "RoomPlan reference workload: %d rooms, %d doors, %d furniture, %dx%d canvas, %d samples\n",
    #plan.rooms, #plan.doors, #plan.furniture, WIDTH, HEIGHT, samples
  ))
  io.stdout:write(string.format(
    "Validation result: %d error(s), %d warning(s); timing targets are informational\n",
    summary.errors, summary.warnings
  ))
  benchmark("validation", samples, function() return validate.run(plan, { limits = limits }) end)
  benchmark("full redraw", samples, redraw)
  benchmark("serialization", samples, function() return assert(model.encode(plan, { final_newline = true })) end)
  benchmark("model copy", samples, function() return model.deep_copy(plan) end)

  local snapshot_bytes = model.estimate_size(plan)
  io.stdout:write(string.format(
    "Estimated snapshots: %.2f MiB each, %.2f MiB for 100 (conservative model estimate)\n",
    snapshot_bytes / 1024 / 1024,
    snapshot_bytes * 100 / 1024 / 1024
  ))
  io.stdout:write("Engineering targets: full redraw normally <100 ms; validation normally <200 ms\n")
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write("RoomPlan benchmark failed:\n" .. tostring(err) .. "\n")
  vim.cmd("cquit 1")
end
