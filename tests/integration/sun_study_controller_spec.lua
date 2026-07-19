local h = require("tests.harness")
local json = require("roomplan.codec.json")
local model = require("roomplan.model")
local config = require("roomplan.config")
local controller = require("roomplan.controller")
local session_module = require("roomplan.session")

describe("sun-study controller", function()
  it("dismisses the popup for canvas playback and keeps contextual controls available", function()
    config.reset()
    config.setup({ sun_study = { playback = { step_minutes = 60, frame_duration_ms = 50 } } })
    local plan = h.truthy(model.new({ name = "Sun controller" }))
    plan.site = json.object({
      north_deg = 0, latitude_deg = 47, longitude_deg = 8, utc_offset_minutes = 60,
    })
    local source_buffer = vim.api.nvim_create_buf(false, true)
    local session = h.truthy(session_module.new({ bufnr = source_buffer, adapter = "standalone" }, plan, {
      durable = true,
    }))
    local handle = h.truthy(controller.sun_study(session))
    h.eq("sun-study", handle.spec.id)
    h.truthy(session.sun_study and session.sun_study.calculation)
    local form = require("roomplan.ui.form")
    local menu_date = session.sun_study.date
    local active_field = handle.state.active_key
    vim.api.nvim_set_current_win(handle.winid)
    vim.api.nvim_feedkeys("j", "x", false)
    h.eq(menu_date, session.sun_study.date)
    h.truthy(handle.state.active_key ~= active_field)
    vim.api.nvim_feedkeys("k", "x", false)
    h.eq(active_field, handle.state.active_key)
    h.truthy(form.set_value(handle, "date_preset", "june", { raw = false, trusted = true }))
    h.matches("%-06%-21$", session.sun_study.date)
    h.truthy(form.set_value(handle, "time", "12:00", { raw = false, trusted = true }))
    local before = session.sun_study.time
    vim.api.nvim_set_current_win(handle.winid)
    vim.api.nvim_feedkeys("l", "x", false)
    h.truthy(session.sun_study.time ~= before)
    local after_step = session.sun_study.time
    vim.api.nvim_feedkeys(" ", "x", false)
    h.truthy(vim.wait(500, function()
      return handle.closed and session.sun_study and session.sun_study.viewing
        and session.canvas and session.canvas.winid and vim.api.nvim_win_is_valid(session.canvas.winid)
    end, 10))
    h.falsy(vim.api.nvim_win_is_valid(handle.winid))
    h.eq(session.canvas.winid, vim.api.nvim_get_current_win())
    h.truthy(vim.wait(250, function()
      return session.sun_study and session.sun_study.playing
    end, 10))
    local start = session.sun_study.calculation
    h.truthy(math.abs(start.minutes - start.sunrise_minutes) <= session.sun_study.step_minutes + 1)
    h.truthy(vim.wait(250, function()
      return session.sun_study and session.sun_study.time ~= after_step
    end, 10))
    vim.api.nvim_feedkeys(" ", "x", false)
    h.eq(false, session.sun_study.playing)
    local paused = session.sun_study.time
    vim.api.nvim_feedkeys("l", "x", false)
    h.truthy(session.sun_study.time ~= paused)
    local before_season = session.sun_study.date
    vim.api.nvim_feedkeys("j", "x", false)
    h.eq(assert(require("roomplan.solar").shift_months(before_season, 3)), session.sun_study.date)
    vim.api.nvim_feedkeys("k", "x", false)
    h.eq(before_season, session.sun_study.date)
    vim.api.nvim_feedkeys(" ", "x", false)
    local completed = vim.wait(4000, function()
      return session.sun_study and session.sun_study.overlay == "daily"
        and session.sun_study.playback_state == "finished"
    end, 10)
    h.truthy(completed, vim.inspect({
      time = session.sun_study and session.sun_study.time,
      playing = session.sun_study and session.sun_study.playing,
      playback_state = session.sun_study and session.sun_study.playback_state,
      overlay = session.sun_study and session.sun_study.overlay,
    }))
    h.truthy(session.sun_study.daily_exposure and #session.sun_study.daily_exposure.samples > 0)
    vim.api.nvim_feedkeys("L", "x", false)
    h.truthy(vim.wait(500, function()
      return session.form and session.form.spec.id == "sun-study"
    end, 10))
    h.eq(session.sun_study.time, session.form.state.draft.time)
    h.truthy(form.cancel(session.form, "test complete"))
    h.eq(nil, session.sun_study)
    h.truthy(session:destroy({ force = true }))
    if vim.api.nvim_buf_is_valid(source_buffer) then vim.api.nvim_buf_delete(source_buffer, { force = true }) end
    config.reset()
  end)

  it("starts with the persisted site popup when a plan has no location", function()
    config.reset()
    local plan = h.truthy(model.new({ name = "Site first" }))
    local source_buffer = vim.api.nvim_create_buf(false, true)
    local session = h.truthy(session_module.new({ bufnr = source_buffer, adapter = "standalone" }, plan, {
      durable = true,
    }))
    local handle = h.truthy(controller.sun_study(session))
    h.eq("sun-site", handle.spec.id)
    h.eq(nil, session.sun_study)
    h.truthy(require("roomplan.ui.form").cancel(handle, "test complete"))
    h.truthy(session:destroy({ force = true }))
    if vim.api.nvim_buf_is_valid(source_buffer) then vim.api.nvim_buf_delete(source_buffer, { force = true }) end
  end)
end)
