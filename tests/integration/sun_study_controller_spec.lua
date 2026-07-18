local h = require("tests.harness")
local json = require("roomplan.codec.json")
local model = require("roomplan.model")
local config = require("roomplan.config")
local controller = require("roomplan.controller")
local session_module = require("roomplan.session")

describe("sun-study controller", function()
  it("opens one structured popup, steps, plays, and clears all transient state", function()
    config.reset()
    config.setup({ sun_study = { playback = { step_minutes = 30, frame_duration_ms = 50 } } })
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
    local before = handle.state.draft.time
    vim.api.nvim_set_current_win(handle.winid)
    vim.api.nvim_feedkeys("l", "x", false)
    h.truthy(handle.state.draft.time ~= before)
    local after_step = handle.state.draft.time
    vim.api.nvim_feedkeys(" ", "x", false)
    h.truthy(vim.wait(250, function()
      return not session.sun_study or handle.state.draft.time ~= after_step
    end, 10))
    vim.api.nvim_feedkeys(" ", "x", false)
    h.eq(false, session.sun_study.playing)
    h.truthy(require("roomplan.ui.form").cancel(handle, "test complete"))
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
