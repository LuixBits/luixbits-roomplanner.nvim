local h = require("tests.harness")

local controller = require("roomplan.controller")
local model = require("roomplan.model")
local source = require("roomplan.storage.source")
local state = require("roomplan.state")

local temporary = {}

local function temp(suffix)
  local path = vim.fn.tempname() .. suffix
  temporary[#temporary + 1] = path
  return path
end

local function cleanup()
  for _, session in ipairs(state.list()) do session:destroy({ force = true }) end
  for _, path in ipairs(temporary) do pcall(vim.uv.fs_unlink, path) end
  temporary = {}
end

local function write_bytes(path, bytes)
  local fd = assert(vim.uv.fs_open(path, "w", 420))
  assert(vim.uv.fs_write(fd, bytes, 0))
  assert(vim.uv.fs_close(fd))
end

local function drive_ui(inputs, selections, callback)
  local original_input, original_select = vim.ui.input, vim.ui.select
  local input_index, selection_index = 0, 0
  vim.ui.input = function(_, done)
    input_index = input_index + 1
    done(inputs[input_index])
  end
  vim.ui.select = function(items, _, done)
    selection_index = selection_index + 1
    local wanted = selections[selection_index]
    local chosen
    for _, item in ipairs(items) do
      if item == wanted or (type(item) == "table"
        and (item.id == wanted or item.label == wanted or item.name == wanted or item.value == wanted)) then
        chosen = item
        break
      end
    end
    done(chosen)
  end
  local ok, err = xpcall(callback, debug.traceback)
  vim.ui.input, vim.ui.select = original_input, original_select
  if not ok then error(err, 0) end
  h.eq(#inputs, input_index, "not every scripted input was consumed")
  h.eq(#selections, selection_index, "not every scripted selection was consumed")
end

describe("controller lifecycle", function()
  it("debounces opt-in standalone autosave and advances the savepoint", function()
    cleanup()
    local runtime_config = require("roomplan.config")
    runtime_config.setup({ autosave = { enabled = true, debounce_ms = 10 } })
    local path = temp(".roomplan.json")
    local session = h.truthy(controller.init_source(nil, { path = path }))
    h.truthy(controller.dispatch(session, {
      type = "add_room",
      room = model.new_room({ id = "room-autosave", name = "Autosave", origin_mm = { 0, 0 }, size_mm = { 1000, 1000 } }),
    }))
    h.truthy(vim.wait(1000, function() return not session:model_dirty() end, 10))
    h.eq("room-autosave", h.truthy(model.decode(source.read_file(path))).rooms[1].id)
    controller.close(session, { bang = true })
    runtime_config.reset()
    cleanup()
  end)

  it("completes structured room, furniture, and connected-door workflows", function()
    cleanup()
    local path = temp(".roomplan.json")
    local session = h.truthy(controller.init_source(nil, { path = path }))
    local form = require("roomplan.ui.form")
    local room_form = h.truthy(controller.add_room(session))
    h.eq("Living room", h.truthy(form.set_value(room_form, "name", "Living room")))
    h.eq(5000, h.truthy(form.set_value(room_form, "width_mm", "5m")))
    h.eq(4000, h.truthy(form.set_value(room_form, "depth_mm", "4m")))
    h.eq("origin", h.truthy(form.set_value(room_form, "placement", "origin", { raw = false })))
    h.truthy(form.apply(room_form))
    h.eq("room-living-room", session:model().rooms[1].id)
    h.truthy(controller.dispatch(session, {
      type = "add_room",
      room = model.new_room({
        id = "room-bedroom", name = "Bedroom",
        origin_mm = { 5000, 0 }, size_mm = { 3000, 3000 },
      }),
    }))
    local furniture_form = h.truthy(controller.add_furniture(session))
    h.eq("room-living-room", h.truthy(form.set_value(
      furniture_form, "room_id", "room-living-room", { raw = false }
    )))
    h.eq("builtin:sofa", h.truthy(form.set_value(
      furniture_form, "template_id", "builtin:sofa", { raw = false }
    )))
    h.eq(2100, h.truthy(form.set_value(furniture_form, "width_mm", "2100")))
    h.eq(900, h.truthy(form.set_value(furniture_form, "depth_mm", "900")))
    h.eq(800, h.truthy(form.set_value(furniture_form, "height_mm", "800")))
    h.eq("Sofa", h.truthy(form.set_value(furniture_form, "name", "Sofa")))
    h.eq("centre", h.truthy(form.set_value(furniture_form, "placement", "centre", { raw = false })))
    h.truthy(form.apply(furniture_form))
    h.eq("builtin:sofa", session:model().furniture[1].template_id)
    session.selection = { kind = "room", id = "room-living-room" }
    local door_form = h.truthy(controller.add_door(session))
    h.eq("room-living-room", h.truthy(form.set_value(
      door_form, "room_id", "room-living-room", { raw = false }
    )))
    h.eq("east", h.truthy(form.set_value(door_form, "side", "east", { raw = false })))
    h.eq(900, h.truthy(form.set_value(door_form, "width_mm", "900")))
    h.eq("exact", h.truthy(form.set_value(door_form, "placement", "exact", { raw = false })))
    h.eq(1000, h.truthy(form.set_value(door_form, "offset_mm", "1000")))
    h.eq("room-bedroom", h.truthy(form.set_value(
      door_form, "connects_to_room_id", "room-bedroom", { raw = false }
    )))
    h.eq("connected", h.truthy(form.set_value(door_form, "opens_into", "connected", { raw = false })))
    h.truthy(form.apply(door_form))
    h.eq("room-bedroom", session:model().doors[1].connects_to_room_id)
    h.truthy(controller.dispatch(session, {
      type = "toggle_door_hinge", id = session:model().doors[1].id,
    }))
    h.eq("end", session:model().doors[1].hinge)
    h.truthy(controller.dispatch(session, {
      type = "rotate_furniture", id = session:model().furniture[1].id, delta_deg = 90,
    }))
    h.truthy(controller.dispatch(session, {
      type = "move_furniture", id = session:model().furniture[1].id,
      center_mm = { 4900, 3900 }, exact = true,
    }))
    local _, invalid_summary = controller.validate(session)
    h.truthy(invalid_summary.errors > 0)
    h.truthy(controller.undo(session))
    h.truthy(controller.redo(session))
    h.truthy(controller.undo(session))
    local _, repaired_summary = controller.validate(session)
    h.eq(0, repaired_summary.errors)
    local saved, err = controller.save(session, { quiet = true, noninteractive = true })
    h.truthy(saved, vim.inspect(err))
    local reopened_model = h.truthy(model.decode(source.read_file(path)))
    h.eq(2, #reopened_model.rooms)
    h.eq(1, #reopened_model.furniture)
    h.eq(1, #reopened_model.doors)
    controller.close(session, { bang = true })
    cleanup()
  end)

  it("opens workspace Issues when an invalid save is reviewed", function()
    cleanup()
    local session = h.truthy(controller.init_source(nil, { path = temp(".roomplan.json") }))
    for index = 1, 2 do
      local result, err = controller.dispatch(session, {
        type = "add_room",
        room = model.new_room({
          id = "room-overlap-" .. index,
          name = "Overlap " .. index,
          origin_mm = { 0, 0 },
          size_mm = { 2000, 2000 },
        }),
        force = index == 2,
      })
      h.truthy(result, vim.inspect(err))
    end

    local saved, save_err
    drive_ui({}, { "Review errors" }, function()
      controller.save(session, { interactive = true }, function(result, err)
        saved, save_err = result, err
      end)
    end)
    h.falsy(saved)
    h.eq("SAVE_CANCELLED", h.truthy(save_err).code)
    h.eq("issues", session.workspace.state.focused_pane)

    controller.close(session, { bang = true })
    cleanup()
  end)

  it("opens the first-room flow directly and fits, selects, and focuses its result", function()
    cleanup()
    local path = temp(".roomplan.json")
    local session = h.truthy(controller.init_source(nil, { path = path }))
    local canvas = require("roomplan.render.canvas")
    h.truthy(canvas.logical_cursor(session), "empty canvas cursor must start in the drawable area")

    local form = require("roomplan.ui.form")
    local room_form = h.truthy(controller.add_menu(session))
    h.eq("ROOM CREATE", room_form.spec.mode)
    h.eq("Living room", h.truthy(form.set_value(room_form, "name", "Living room")))
    h.eq(5000, h.truthy(form.set_value(room_form, "width_mm", "5m")))
    h.eq(4000, h.truthy(form.set_value(room_form, "depth_mm", "4m")))
    h.eq("origin", h.truthy(form.set_value(room_form, "placement", "origin", { raw = false })))
    h.truthy(form.apply(room_form))

    h.eq({ kind = "room", id = "room-living-room" }, session.selection)
    local handle = h.truthy(session.canvas.handle)
    local output = h.truthy(handle.last_raster)
    h.falsy(output.chrome_state)
    local selected_hit = false
    for _, hit in ipairs(canvas.hit_candidates(session)) do
      if hit.type == "room" and hit.id == "room-living-room" then selected_hit = true end
    end
    h.truthy(selected_hit, "first room should receive cursor focus after fitting")

    session.selection = nil
    controller.refresh(session)
    local workspace = require("roomplan.ui.workspace")
    h.truthy(workspace.focus(session, "objects"))
    local room_row
    for row, item in pairs(session.workspace.rendered.objects.row_map) do
      if item.id == "room-living-room" then room_row = row; break end
    end
    h.truthy(room_row)
    local navigator_window = session.workspace.windows.left or session.workspace.windows.drawer
    h.truthy(navigator_window)
    vim.api.nvim_win_set_cursor(navigator_window, { room_row, 0 })
    h.eq({ kind = "room", id = "room-living-room" }, workspace.select_focused(session))
    h.truthy(vim.wait(200, function()
      local header = vim.api.nvim_buf_get_lines(handle.buf, 0, 1, false)[1] or ""
      return header:find("room: Living room", 1, true) ~= nil
    end, 5), "workspace selection should redraw the canvas header and highlight")
    h.eq(handle.win, vim.api.nvim_get_current_win())
    local footer_buf = session.workspace and session.workspace.buffers.action_bar or handle.buf
    local footer = table.concat(vim.api.nvim_buf_get_lines(footer_buf, 0, -1, false), " ")
    h.matches("%[e%] Edit", footer)
    h.matches("%[%?%] More", footer)
    controller.close(session, { bang = true })
    cleanup()
  end)

  it("publishes structured create, edit, and alignment modes end to end", function()
    cleanup()
    local path = temp(".roomplan.json")
    local session = h.truthy(controller.init_source(nil, { path = path }))
    local form = require("roomplan.ui.form")
    local function expect_mode(handle, mode)
      h.eq(mode, handle.spec.mode)
      local lines = vim.api.nvim_buf_get_lines(session.workspace.buffers.action_bar, 0, -1, false)
      h.matches(mode, table.concat(lines, " "))
    end

    local room_create = h.truthy(controller.add_room(session))
    expect_mode(room_create, "ROOM CREATE")
    local applied, apply_err = form.apply(room_create)
    h.truthy(applied, vim.inspect(apply_err))
    h.eq(1, #session:model().rooms)

    session.selection = { kind = "plan" }
    local plan_edit = h.truthy(controller.edit_selected(session))
    expect_mode(plan_edit, "PLAN EDIT")
    h.truthy(form.cancel(plan_edit))

    local second_room, second_room_err = controller.dispatch(session, {
      type = "add_room",
      room = model.new_room({
        id = "room-bedroom", name = "Bedroom",
        origin_mm = { 4000, 0 }, size_mm = { 3000, 3000 },
      }),
    })
    h.truthy(second_room, vim.inspect(second_room_err))
    session.selection = { kind = "room", id = "room-bedroom" }
    local align = h.truthy(controller.align_room(session))
    expect_mode(align, "ROOM ALIGN")
    h.truthy(form.cancel(align))

    session.selection = { kind = "room", id = session:model().rooms[1].id }
    local room_edit = h.truthy(controller.edit_selected(session))
    expect_mode(room_edit, "ROOM EDIT")
    h.truthy(form.cancel(room_edit))

    local furniture_create = h.truthy(controller.add_furniture(session))
    expect_mode(furniture_create, "FURNITURE CREATE")
    applied, apply_err = form.apply(furniture_create)
    h.truthy(applied, vim.inspect(apply_err))
    h.eq(1, #session:model().furniture)
    local furniture_edit = h.truthy(controller.edit_selected(session))
    expect_mode(furniture_edit, "FURNITURE EDIT")
    h.truthy(form.cancel(furniture_edit))

    session.selection = { kind = "room", id = session:model().rooms[1].id }
    local door_create = h.truthy(controller.add_door(session))
    expect_mode(door_create, "DOOR CREATE")
    applied, apply_err = form.apply(door_create)
    h.truthy(applied, vim.inspect(apply_err))
    h.eq(1, #session:model().doors)
    local door_edit = h.truthy(controller.edit_selected(session))
    expect_mode(door_edit, "DOOR EDIT")
    h.truthy(form.cancel(door_edit))

    local door_duplicate = h.truthy(controller.duplicate_selected(session))
    expect_mode(door_duplicate, "DOOR DUPLICATE")
    h.eq("end", h.truthy(form.set_value(door_duplicate, "hinge", "end", { raw = false })))
    applied, apply_err = form.apply(door_duplicate)
    h.truthy(applied, vim.inspect(apply_err))
    h.eq(2, #session:model().doors)
    h.eq("end", session:model().doors[2].hinge)
    h.eq(session:model().doors[1].connects_to_room_id, session:model().doors[2].connects_to_room_id)

    h.truthy(vim.wait(200, function()
      local footer = vim.api.nvim_buf_get_lines(session.workspace.buffers.action_bar, 0, 1, false)[1] or ""
      return footer:find("NAV", 1, true) ~= nil
    end, 10), "canvas mode label should return to NAV after forms close")
    controller.close(session, { bang = true })
    cleanup()
  end)

  it("refits the active canvas after runtime aspect calibration without editing the plan", function()
    cleanup()
    local runtime_config = require("roomplan.config")
    runtime_config.setup({ canvas = { cell_aspect = 2 } })
    local path = temp(".roomplan.json")
    local session = h.truthy(controller.init_source(nil, { path = path }))
    local revision = session:revision_id()

    h.eq(2.4, controller.set_aspect(session, { ratio = "2.4", quiet = true }))
    h.eq(2.4, runtime_config.get().canvas.cell_aspect)
    h.eq(2.4, session.viewport.mm_per_row / session.viewport.mm_per_column)
    local rendered = h.truthy(h.truthy(session.canvas.handle).last_raster)
    h.eq(2.4, rendered.viewport.mm_per_row / rendered.viewport.mm_per_column)
    h.eq(revision, session:revision_id())
    h.falsy(session:model_dirty())

    controller.close(session, { bang = true })
    runtime_config.reset()
    cleanup()
  end)

  it("refits every live canvas after process-wide aspect calibration", function()
    cleanup()
    local runtime_config = require("roomplan.config")
    runtime_config.setup({ canvas = { cell_aspect = 2 } })
    local first = h.truthy(controller.init_source(nil, { path = temp(".roomplan.json") }))
    local second = h.truthy(controller.init_source(nil, { path = temp(".roomplan.json") }))
    local first_revision, second_revision = first:revision_id(), second:revision_id()

    h.eq(2.3, controller.set_aspect(first, { ratio = 2.3, quiet = true }))
    for _, session in ipairs({ first, second }) do
      h.eq(2.3, session.viewport.mm_per_row / session.viewport.mm_per_column)
      local rendered = h.truthy(h.truthy(session.canvas.handle).last_raster)
      h.eq(2.3, rendered.viewport.mm_per_row / rendered.viewport.mm_per_column)
      h.falsy(session:model_dirty())
    end
    h.eq(first_revision, first:revision_id())
    h.eq(second_revision, second:revision_id())

    controller.close(second, { bang = true })
    controller.close(first, { bang = true })
    runtime_config.reset()
    cleanup()
  end)

  it("keeps view rotation transient across fit, aspect calibration, commands, and reset", function()
    cleanup()
    local runtime_config = require("roomplan.config")
    local viewport = require("roomplan.render.viewport")
    runtime_config.setup({ canvas = { cell_aspect = 2 } })
    require("roomplan.commands").register()
    local path = temp(".roomplan.json")
    local session = h.truthy(controller.init_source(nil, { path = path }))
    local revision = session:revision_id()
    local plan = vim.deepcopy(session:model())
    local history = session.history:stats()
    local dirty = session:model_dirty()

    local function unchanged()
      h.eq(revision, session:revision_id())
      h.eq(plan, session:model())
      h.eq(history, session.history:stats())
      h.eq(dirty, session:model_dirty())
    end

    h.eq(1, viewport.rotation(h.truthy(controller.rotate_view(session, {
      direction = "clockwise", quiet = true,
    }))))
    unchanged()

    h.truthy(controller.fit(session, { immediate = true }))
    h.eq(1, viewport.rotation(session.viewport))
    h.eq(1, viewport.rotation(h.truthy(session.canvas.handle).last_raster.viewport))
    unchanged()

    h.eq(2.25, controller.set_aspect(session, { ratio = 2.25, quiet = true }))
    h.eq(1, viewport.rotation(session.viewport))
    h.eq(1, viewport.rotation(session.canvas.handle.last_raster.viewport))
    unchanged()

    vim.cmd("RoomPlanRotateView counterclockwise")
    h.eq(0, viewport.rotation(session.viewport))
    h.eq(1, viewport.rotation(h.truthy(controller.rotate_view(session, {
      direction = "clockwise", quiet = true,
    }))))
    h.eq(0, viewport.rotation(h.truthy(controller.rotate_view(session, {
      direction = "reset", quiet = true,
    }))))
    unchanged()

    local before_invalid = viewport.copy(session.viewport)
    local invalid, invalid_err = controller.rotate_view(session, {
      direction = "diagonal", quiet = true,
    })
    h.eq(nil, invalid)
    h.eq("VIEW_ROTATION_INVALID", h.truthy(invalid_err).code)
    h.eq(before_invalid, session.viewport)
    unchanged()

    controller.close(session, { bang = true })
    runtime_config.reset()
    cleanup()
  end)

  it("uses a hidden modified acwrite buffer to block ordinary qall", function()
    cleanup()
    local plan_path = temp(".roomplan.json")
    local marker = temp(".guard-marker")
    local previous_plan, previous_marker = vim.env.ROOMPLAN_GUARD_PLAN, vim.env.ROOMPLAN_GUARD_MARKER
    vim.env.ROOMPLAN_GUARD_PLAN = plan_path
    vim.env.ROOMPLAN_GUARD_MARKER = marker
    local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
    vim.fn.system({
      vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-n",
      "-c", "lua dofile(" .. string.format("%q", root .. "/tests/guard_child.lua") .. ")",
      "-c", "qall",
      "-c", "lua vim.fn.writefile({'ordinary qall was blocked'}, vim.env.ROOMPLAN_GUARD_MARKER)",
      "-c", "qall!",
    })
    vim.env.ROOMPLAN_GUARD_PLAN, vim.env.ROOMPLAN_GUARD_MARKER = previous_plan, previous_marker
    h.truthy(vim.uv.fs_lstat(marker), "ordinary qall exited before the guard marker command")
    cleanup()
  end)

  it("initializes, edits, saves, reuses, and reopens standalone plans", function()
    cleanup()
    local path = temp(".roomplan.json")
    local session, err = controller.init_source(nil, { path = path })
    h.truthy(session, vim.inspect(err))
    h.falsy(session:model_dirty())

    local room = model.new_room({
      id = "room-living", name = "Living room",
      origin_mm = { 0, 0 }, size_mm = { 5000, 4000 },
    })
    local result, action_err = controller.dispatch(session, { type = "add_room", room = room })
    h.truthy(result, vim.inspect(action_err))
    h.truthy(session:model_dirty())
    h.truthy(vim.bo[session.guard_bufnr].modified)

    local saved, save_err = controller.save(session, { quiet = true })
    h.truthy(saved, vim.inspect(save_err))
    h.falsy(session:model_dirty())
    h.falsy(vim.bo[session.guard_bufnr].modified)
    local bytes = h.truthy(source.read_file(path))
    local decoded = h.truthy(model.decode(bytes))
    h.eq("room-living", decoded.rooms[1].id)

    local reused = controller.open(nil, { path = path })
    h.eq(session.id, reused.id)
    controller.close(session, { bang = true })

    local reopened, reopen_err = controller.open(nil, { path = path })
    h.truthy(reopened, vim.inspect(reopen_err))
    h.eq(1, #reopened:model().rooms)
    controller.close(reopened, { bang = true })
    cleanup()
  end)

  it("initializes Norg without writing and preserves outside text on save", function()
    cleanup()
    local path = temp(".norg")
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, path)
    vim.bo[bufnr].filetype = "norg"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "* Notes", "Keep this exact text." })
    local session, err = controller.init_source(nil, { bufnr = bufnr })
    h.truthy(session, vim.inspect(err))
    h.truthy(vim.bo[bufnr].modified)
    h.truthy(session:model_dirty())
    local before = source.buffer_text(bufnr)
    h.matches("Keep this exact text%.", before)
    h.matches("@code json roomplan%.nvim", before)
    h.truthy(controller.dispatch(session, {
      type = "add_room",
      room = model.new_room({ id = "room-norg", name = "Norg room", origin_mm = { 0, 0 }, size_mm = { 2500, 2000 } }),
    }))

    local saved, save_err = controller.save(session, { quiet = true })
    h.truthy(saved, vim.inspect(save_err))
    local after = source.buffer_text(bufnr)
    h.matches("^%* Notes\nKeep this exact text%.", after)
    h.matches("room%-norg", after)
    h.falsy(vim.bo[bufnr].modified)
    controller.close(session, { bang = true })
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    cleanup()
  end)

  it("requires an explicit choice when a Norg note has multiple Floor plan headings", function()
    cleanup()
    local path = temp(".norg")
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, path)
    vim.bo[bufnr].filetype = "norg"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "* Floor plan", "first", "* Floor plan", "second" })
    local before = source.buffer_text(bufnr)
    local session, err = controller.init_source(nil, { bufnr = bufnr, noninteractive = true })
    h.falsy(session)
    h.eq("NORG_MULTIPLE_HEADINGS", err.code)
    h.eq(before, source.buffer_text(bufnr))
    local initialized, init_err = controller.init_source(nil, { bufnr = bufnr, heading_line = 3, noninteractive = true })
    h.truthy(initialized, vim.inspect(init_err))
    h.matches("second\n\n@code json roomplan%.nvim", source.buffer_text(bufnr))
    controller.close(initialized, { bang = true })
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    cleanup()
  end)

  it("detects a manual payload conflict before save", function()
    cleanup()
    local path = temp(".roomplan.json")
    local session = h.truthy(controller.init_source(nil, { path = path }))
    local bufnr = session.source.bufnr
    local original = source.buffer_text(bufnr)
    local changed = original:gsub('"grid_mm": 100', '"grid_mm": 101', 1)
    h.falsy(changed == original, "fixture edit must alter the payload")
    source.set_buffer_text(bufnr, changed)
    local ok, conflict = controller.check_source(session)
    h.falsy(ok)
    h.eq("SOURCE_CONFLICT", conflict.code)
    h.truthy(session.source_conflicted)
    local saved, save_err = controller.save(session, { quiet = true, noninteractive = true })
    h.falsy(saved)
    h.eq("SOURCE_CONFLICT", save_err.code)
    h.eq(changed, source.buffer_text(bufnr))
    controller.close(session, { bang = true })
    cleanup()
  end)

  it("expires conflict-overwrite confirmation when the source changes again", function()
    cleanup()
    local path = temp(".roomplan.json")
    local session = h.truthy(controller.init_source(nil, { path = path }))
    local bufnr = session.source.bufnr
    local original = source.buffer_text(bufnr)
    local first_edit = original:gsub('"grid_mm": 100', '"grid_mm": 101', 1)
    local second_edit = original:gsub('"grid_mm": 100', '"grid_mm": 102', 1)
    source.set_buffer_text(bufnr, first_edit)
    h.falsy(controller.check_source(session))

    local original_select = vim.ui.select
    local compatibility = require("roomplan.compat")
    local original_notify = compatibility.notify
    local callbacks = {}
    vim.ui.select = function(_, _, done) callbacks[#callbacks + 1] = done end
    compatibility.notify = function() end
    local ok, test_err = xpcall(function()
      controller.resolve_conflict(session)
      h.eq(1, #callbacks)
      callbacks[1]("Overwrite current payload")
      h.eq(2, #callbacks)
      source.set_buffer_text(bufnr, second_edit)
      callbacks[2]("Overwrite payload")
      h.eq(second_edit, source.buffer_text(bufnr))
      h.eq(original, source.read_file(path))
      h.truthy(session.source_conflicted)
      h.eq(100, session:model().settings.grid_mm)
    end, debug.traceback)
    vim.ui.select = original_select
    compatibility.notify = original_notify
    if not ok then error(test_err, 0) end

    controller.close(session, { bang = true })
    cleanup()
  end)

  it("keeps the retained model guarded after a hook corrupts the source", function()
    cleanup()
    local path = temp(".roomplan.json")
    local session = h.truthy(controller.init_source(nil, { path = path }))
    local adapter = require("roomplan.storage.json")
    local original_commit = adapter.commit
    adapter.commit = function(context)
      source.set_buffer_text(context.bufnr, "malformed after hook\n")
      return nil, { code = "SOURCE_POST_WRITE_INVALID", message = "intentional hook corruption" }
    end
    local saved, err = controller.save(session, { quiet = true, noninteractive = true })
    adapter.commit = original_commit
    h.falsy(saved)
    h.eq("SOURCE_POST_WRITE_INVALID", err.code)
    h.truthy(session.source_conflicted)
    h.truthy(session.retained_model_at_risk)
    h.truthy(vim.bo[session.guard_bufnr].modified)
    controller.close(session, { bang = true })
    cleanup()
  end)

  it("detects an external disk edit before patching a clean source buffer", function()
    cleanup()
    local path = temp(".roomplan.json")
    local session = h.truthy(controller.init_source(nil, { path = path }))
    local original = h.truthy(source.read_file(path))
    local external = original:gsub('"grid_mm": 100', '"grid_mm": 125', 1)
    h.falsy(external == original)
    write_bytes(path, external)
    local saved, save_err = controller.save(session, { quiet = true, noninteractive = true })
    h.falsy(saved)
    h.eq("SOURCE_CONFLICT", save_err.code)
    h.eq(original, source.buffer_text(session.source.bufnr))
    h.eq(external, source.read_file(path))
    controller.close(session, { bang = true })
    cleanup()
  end)

  it("reloads an externally changed disk file instead of rebasing a stale buffer", function()
    cleanup()
    local path = temp(".roomplan.json")
    local session = h.truthy(controller.init_source(nil, { path = path }))
    local original = h.truthy(source.read_file(path))
    local external = original:gsub('"grid_mm": 100', '"grid_mm": 175', 1)
    write_bytes(path, external)
    local saved, conflict = controller.save(session, { quiet = true, noninteractive = true })
    h.falsy(saved)
    h.eq("SOURCE_CONFLICT", conflict.code)
    local reloaded, reload_err = controller.reload(session, { bang = true, noninteractive = true })
    h.truthy(reloaded, vim.inspect(reload_err))
    h.eq(175, session:model().settings.grid_mm)
    local saved_after, save_err = controller.save(session, { quiet = true, noninteractive = true })
    h.truthy(saved_after, vim.inspect(save_err))
    h.eq(175, h.truthy(model.decode(source.read_file(path))).settings.grid_mm)
    controller.close(session, { bang = true })
    cleanup()
  end)

  it("guards the retained model when an external reload target becomes malformed", function()
    cleanup()
    local path = temp(".roomplan.json")
    local session = h.truthy(controller.init_source(nil, { path = path }))
    local retained = h.truthy(model.encode(session:model()))
    write_bytes(path, "not json after external replacement\n")
    local reloaded, reload_err = controller.reload(session, { bang = true, noninteractive = true })
    h.falsy(reloaded)
    h.truthy(reload_err)
    h.eq(retained, h.truthy(model.encode(session:model())))
    h.truthy(session.source_conflicted)
    h.truthy(session.retained_model_at_risk)
    h.falsy(session.durable_source_matches_savepoint)
    h.truthy(session:requires_protection())
    h.truthy(vim.bo[session.guard_bufnr].modified)
    controller.close(session, { bang = true })
    cleanup()
  end)

  it("initializes an existing empty standalone file through its buffer", function()
    cleanup()
    local path = temp(".roomplan.json")
    write_bytes(path, "")
    local session, err = controller.init_source(nil, { path = path })
    h.truthy(session, vim.inspect(err))
    h.falsy(session:model_dirty())
    h.truthy(#source.read_file(path) > 0)
    controller.close(session, { bang = true })
    cleanup()
  end)

  it("retains a protected staged session when initialization cannot write", function()
    cleanup()
    local path = temp(".roomplan.json")
    write_bytes(path, "")
    local bufnr = vim.fn.bufadd(path)
    vim.fn.bufload(bufnr)
    local original_write = source.write_buffer
    source.write_buffer = function()
      return nil, { code = "SOURCE_WRITE_FAILED", message = "intentional init write failure" }
    end
    local session, err = controller.init_source(nil, { bufnr = bufnr, noninteractive = true })
    source.write_buffer = original_write
    h.truthy(session, vim.inspect(err))
    h.truthy(err)
    h.truthy(session.pending_disk_write)
    h.truthy(session:model_dirty())
    h.truthy(vim.bo[session.guard_bufnr].modified)
    h.eq("", source.read_file(path))
    controller.close(session, { bang = true })
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    cleanup()
  end)

  it("replaces a recognized staged payload after more model edits", function()
    cleanup()
    local path = temp(".roomplan.json")
    local session = h.truthy(controller.init_source(nil, { path = path }))
    local bufnr = session.source.bufnr
    local original_write = source.write_buffer
    source.write_buffer = function()
      return nil, { code = "SOURCE_WRITE_FAILED", message = "intentional save failure" }
    end
    local room = model.new_room({ id = "room-staged", name = "Staged", origin_mm = { 0, 0 }, size_mm = { 2000, 2000 } })
    h.truthy(controller.dispatch(session, { type = "add_room", room = room }))
    local saved, save_err = controller.save(session, { quiet = true, noninteractive = true })
    h.falsy(saved)
    h.eq("SOURCE_WRITE_FAILED", save_err.code)
    source.write_buffer = original_write
    h.truthy(session.pending_disk_write)
    h.truthy(controller.dispatch(session, { type = "edit_metadata", patch = { name = "Revision three" } }))
    local retried, retry_err = controller.save(session, { quiet = true, noninteractive = true })
    h.truthy(retried, vim.inspect(retry_err))
    local durable = h.truthy(model.decode(source.read_file(path)))
    h.eq("Revision three", durable.metadata.name)
    h.eq("room-staged", durable.rooms[1].id)
    controller.close(session, { bang = true })
    cleanup()
  end)

  it("promotes the exact staged revision after a later native write", function()
    cleanup()
    local path = temp(".roomplan.json")
    local session = h.truthy(controller.init_source(nil, { path = path }))
    h.truthy(controller.dispatch(session, {
      type = "add_room",
      room = model.new_room({ id = "room-native-write", name = "Native write", origin_mm = { 0, 0 }, size_mm = { 1200, 900 } }),
    }))
    local original_write = source.write_buffer
    source.write_buffer = function()
      return nil, { code = "SOURCE_WRITE_FAILED", message = "intentional staged write" }
    end
    local saved = controller.save(session, { quiet = true, noninteractive = true })
    source.write_buffer = original_write
    h.falsy(saved)
    h.truthy(session.pending_disk_write)
    h.truthy(original_write(session.source.bufnr))
    h.truthy(vim.wait(500, function() return not session.pending_disk_write end, 10))
    h.falsy(session:model_dirty())
    h.falsy(vim.bo[session.guard_bufnr].modified)
    h.eq("room-native-write", h.truthy(model.decode(source.read_file(path))).rooms[1].id)
    controller.close(session, { bang = true })
    cleanup()
  end)

  it("reattaches a wiped named source before saving", function()
    cleanup()
    local path = temp(".roomplan.json")
    local session = h.truthy(controller.init_source(nil, { path = path }))
    local old_bufnr = session.source.bufnr
    h.truthy(controller.dispatch(session, {
      type = "add_room",
      room = model.new_room({ id = "room-after-wipe", name = "After wipe", origin_mm = { 0, 0 }, size_mm = { 1000, 1000 } }),
    }))
    vim.api.nvim_buf_delete(old_bufnr, { force = true })
    h.eq(nil, session.source.bufnr)
    local reopened = h.truthy(controller.open(nil, { path = path, noninteractive = true }))
    h.eq(session.id, reopened.id)
    h.truthy(session.source.bufnr and vim.api.nvim_buf_is_valid(session.source.bufnr))
    local saved, err = controller.save(session, { quiet = true, noninteractive = true })
    h.truthy(saved, vim.inspect(err))
    h.truthy(session.source.bufnr ~= old_bufnr)
    h.eq("room-after-wipe", h.truthy(model.decode(source.read_file(path))).rooms[1].id)
    controller.close(session, { bang = true })
    cleanup()
  end)

  it("applies the standalone Save As destination safety matrix", function()
    cleanup()
    local source_path = temp(".roomplan.json")
    local session = h.truthy(controller.init_source(nil, { path = source_path }))
    h.truthy(controller.dispatch(session, {
      type = "edit_metadata", patch = { name = "Save As model" },
    }))

    local existing = temp(".roomplan.json")
    local old_model = h.truthy(model.new({ name = "Existing destination" }))
    write_bytes(existing, h.truthy(model.encode(old_model)))
    local refused, confirm_err = controller.save_as(session, {
      path = existing, noninteractive = true,
    })
    h.falsy(refused)
    h.eq("SAVE_AS_CONFIRM_REQUIRED", confirm_err.code)
    h.eq("Existing destination", h.truthy(model.decode(source.read_file(existing))).metadata.name)
    local replaced, replace_err = controller.save_as(session, {
      path = existing, bang = true, noninteractive = true,
    })
    h.truthy(replaced, vim.inspect(replace_err))
    h.eq("Save As model", h.truthy(model.decode(source.read_file(existing))).metadata.name)

    h.truthy(controller.dispatch(session, {
      type = "add_room",
      room = model.new_room({ id = "room-invalid-save-as", name = "Room", origin_mm = { 0, 0 }, size_mm = { 1000, 1000 } }),
    }))
    h.truthy(controller.dispatch(session, {
      type = "add_furniture",
      furniture = model.new_furniture({
        id = "furniture-invalid-save-as", room_id = "room-invalid-save-as",
        template_id = "builtin:chair", name = "Outside", category = "seating",
        center_mm = { 5000, 5000 }, size_mm = { 500, 500, 800 }, rotation_deg = 0,
      }),
    }))
    local invalid_target = temp(".roomplan.json")
    write_bytes(invalid_target, h.truthy(model.encode(old_model)))
    local invalid_saved, invalid_err = controller.save_as(session, {
      path = invalid_target, bang = true, noninteractive = true,
    })
    h.falsy(invalid_saved)
    h.eq("MODEL_LAYOUT_INVALID", invalid_err.code)
    h.eq("Existing destination", h.truthy(model.decode(source.read_file(invalid_target))).metadata.name)

    local malformed = temp(".roomplan.json")
    write_bytes(malformed, "not json\n")
    local malformed_result, malformed_err = controller.save_as(session, {
      path = malformed, bang = true, allow_invalid = true, noninteractive = true,
    })
    h.falsy(malformed_result)
    h.truthy(malformed_err)
    h.eq("not json\n", source.read_file(malformed))
    controller.close(session, { bang = true })
    cleanup()
  end)

  it("does not reuse Save As confirmation after the destination buffer changes", function()
    cleanup()
    local source_path = temp(".roomplan.json")
    local session = h.truthy(controller.init_source(nil, { path = source_path }))
    h.truthy(controller.dispatch(session, {
      type = "edit_metadata", patch = { name = "Incoming model" },
    }))
    local destination = temp(".roomplan.json")
    local original = h.truthy(model.new({ name = "Original destination" }))
    local replacement = h.truthy(model.new({ name = "Edited while prompting" }))
    local original_text = h.truthy(model.encode(original))
    local replacement_text = h.truthy(model.encode(replacement))
    write_bytes(destination, original_text)

    local original_select = vim.ui.select
    local continue_prompt
    vim.ui.select = function(_, _, done) continue_prompt = done end
    local callback_result, callback_err
    controller.save_as(session, { path = destination, interactive = true }, function(result, err)
      callback_result, callback_err = result, err
    end)
    vim.ui.select = original_select
    h.truthy(continue_prompt)

    local destination_bufnr = vim.fn.bufnr(destination)
    h.truthy(destination_bufnr ~= -1)
    source.set_buffer_text(destination_bufnr, replacement_text)
    continue_prompt("Continue")

    h.falsy(callback_result)
    h.eq("SAVE_AS_DESTINATION_CHANGED", h.truthy(callback_err).code)
    h.eq(replacement_text, source.buffer_text(destination_bufnr))
    h.eq(original_text, source.read_file(destination))
    h.eq(source_path, session.source.path)
    controller.close(session, { bang = true })
    pcall(vim.api.nvim_buf_delete, destination_bufnr, { force = true })
    cleanup()
  end)

  it("refuses to overwrite a Save As destination through a symbolic link", function()
    cleanup()
    local source_path = temp(".roomplan.json")
    local session = h.truthy(controller.init_source(nil, { path = source_path }))
    h.truthy(controller.dispatch(session, {
      type = "edit_metadata", patch = { name = "Incoming through link" },
    }))
    local target = temp(".roomplan.json")
    local link = temp(".roomplan.json")
    local target_model = h.truthy(model.new({ name = "Keep target" }))
    local target_text = h.truthy(model.encode(target_model))
    write_bytes(target, target_text)
    local linked = vim.uv.fs_symlink(target, link)
    if linked then
      local compatibility = require("roomplan.compat")
      local original_notify = compatibility.notify
      compatibility.notify = function() end
      local saved, save_err = controller.save_as(session, {
        path = link, bang = true, noninteractive = true,
      })
      compatibility.notify = original_notify
      h.falsy(saved)
      h.eq("SAVE_AS_UNSAFE_TARGET", h.truthy(save_err).code)
      h.eq(target_text, source.read_file(target))
      h.eq(source_path, session.source.path)
    end
    controller.close(session, { bang = true })
    cleanup()
  end)

  it("initializes and replaces existing Norg Save As targets only after authorization", function()
    cleanup()
    local source_path = temp(".roomplan.json")
    local session = h.truthy(controller.init_source(nil, { path = source_path }))
    h.truthy(controller.dispatch(session, { type = "edit_metadata", patch = { name = "Norg destination model" } }))
    local note_path = temp(".norg")
    write_bytes(note_path, "* Notes\nPreserve me.\n")
    local refused, confirm_err = controller.save_as(session, { path = note_path, noninteractive = true })
    h.falsy(refused)
    h.eq("SAVE_AS_CONFIRM_REQUIRED", confirm_err.code)
    h.eq("* Notes\nPreserve me.\n", source.read_file(note_path))
    local initialized, init_err
    drive_ui({}, { "Continue" }, function()
      controller.save_as(session, { path = note_path, interactive = true }, function(result, err)
        initialized, init_err = result, err
      end)
    end)
    h.truthy(initialized, vim.inspect(init_err))
    local initialized_text = source.read_file(note_path)
    h.matches("Preserve me", initialized_text)
    h.matches("@code json roomplan%.nvim", initialized_text)
    controller.close(session, { bang = true })

    local replacement_source = temp(".roomplan.json")
    local other = h.truthy(controller.init_source(nil, { path = replacement_source }))
    h.truthy(controller.dispatch(other, { type = "edit_metadata", patch = { name = "Replacement model" } }))
    local replace_refused, replace_confirm = controller.save_as(other, { path = note_path, noninteractive = true })
    h.falsy(replace_refused)
    h.eq("SAVE_AS_CONFIRM_REQUIRED", replace_confirm.code)
    local replaced, replace_err
    drive_ui({}, { "Continue" }, function()
      controller.save_as(other, { path = note_path, interactive = true }, function(result, err)
        replaced, replace_err = result, err
      end)
    end)
    h.truthy(replaced, vim.inspect(replace_err))
    local replaced_text = source.read_file(note_path)
    h.matches("Preserve me", replaced_text)
    h.matches("Replacement model", replaced_text)
    controller.close(other, { bang = true })
    cleanup()
  end)
end)
