local common = require("roomplan.controller.common")
local config = require("roomplan.config")
local solar = require("roomplan.solar")
local util = require("roomplan.util")

local M = {}

local function stop_timer(session)
  local study = session and session.sun_study
  if not study then return end
  study.playing = false
  if study.timer then
    pcall(study.timer.stop, study.timer)
    if not study.timer:is_closing() then pcall(study.timer.close, study.timer) end
    study.timer = nil
  end
end

local function clear_study(controller, session)
  stop_timer(session)
  session.sun_study = nil
  if not session.closed then controller.refresh(session) end
end

local function form_focus(controller, session)
  vim.schedule(function()
    if session.closed then return end
    controller.refresh(session)
    local ok, workspace = pcall(require, "roomplan.ui.workspace")
    if ok and workspace.is_visible(session) then workspace.focus(session, "canvas") end
  end)
end

local function study_spec(session, initial)
  local spec = {
    id = "sun-study",
    title = "Sun study",
    mode = "SUN STUDY",
    description = "Offline clear-sky sunlight from sunrise to sunset. h/l step; Space plays or pauses.",
    apply_label = "Close sun study",
    context = { session = session },
    initial = initial,
    fields = {
      { key = "date", label = "Date", type = "text", required = true, trim = true },
      { key = "time", label = "Local time", type = "text", required = true, trim = true },
      { key = "step_minutes", label = "Step size (minutes)", type = "integer", required = true, min = 1, max = 720 },
      { key = "frame_duration_ms", label = "Time per step (ms)", type = "integer", required = true, min = 50, max = 60000 },
      { key = "daylight", label = "Daylight", type = "readonly", value = function()
        local value = session.sun_study and session.sun_study.calculation
        if not value then return "Enter a valid date and time" end
        if value.daylight_state == "polar_night" then return "No sunrise on this date" end
        if value.daylight_state == "polar_day" then return "Sun stays above the horizon" end
        return solar.format_time(value.sunrise_minutes) .. " – " .. solar.format_time(value.sunset_minutes)
      end },
      { key = "position", label = "Sun position", type = "readonly", value = function()
        local value = session.sun_study and session.sun_study.calculation
        if not value then return "Unavailable" end
        return string.format("azimuth %.1f° · elevation %.1f°", value.azimuth_deg, value.elevation_deg)
      end },
      { key = "playback", label = "Playback", type = "readonly", value = function()
        return session.sun_study and session.sun_study.playing and "Running · Space pauses" or "Paused · Space plays"
      end },
      { key = "previous", label = "Previous step", type = "action", action = "previous" },
      { key = "play", label = "Play / pause", type = "action", action = "play" },
      { key = "next", label = "Next step", type = "action", action = "next" },
      { key = "edit_site", label = "Edit location and plan north", type = "action", action = "edit_site" },
    },
  }
  function spec.validate(draft)
    local errors = {}
    local date, date_error = solar.parse_date(draft.date)
    if not date then errors.date = date_error end
    local time, time_error = solar.parse_time(draft.time)
    if time == nil then errors.time = time_error end
    return errors
  end
  function spec.preview(draft)
    local value, reason = solar.position(session:model().site, draft.date, draft.time)
    if not value then return nil, reason end
    local light = value.elevation_deg > 0 and "Sunlight patches visible" or "Sun below the horizon"
    local estimate = session.sun_study and session.sun_study.assumed_count or 0
    return { lines = {
      light,
      estimate > 0 and string.format("%d lit window%s use configured heights", estimate, estimate == 1 and "" or "s")
        or "Window-specific heights used where available",
    } }
  end
  return spec
end

function M.close(session)
  stop_timer(session)
  if session then session.sun_study = nil end
end

function M.attach(controller)
  local resolve = common.resolve
  local notify_error = common.notify_error

  function controller.configure_sun_site(session, opts)
    opts = opts or {}
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    local form = require("roomplan.ui.form")
    local spec = require("roomplan.ui.forms").site.new(resolved)
    local handle, form_error = form.open(resolved, spec, {
      on_submit = function(draft, state)
        local action, build_error = spec.build(draft, state.context)
        if not action then return nil, build_error end
        local result, dispatch_error = controller.dispatch(resolved, action)
        if not result then return nil, dispatch_error end
        if opts.open_study then
          vim.schedule(function() if not resolved.closed then controller.sun_study(resolved) end end)
        else
          form_focus(controller, resolved)
        end
        return result
      end,
      on_cancel = function()
        if opts.open_study and resolved:model().site then
          vim.schedule(function() if not resolved.closed then controller.sun_study(resolved) end end)
        else
          form_focus(controller, resolved)
        end
      end,
    })
    if not handle then return notify_error(form_error) end
    return handle
  end

  function controller.sun_study(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if not resolved:model().site then
      return controller.configure_sun_site(resolved, { open_study = true })
    end
    local runtime = config.get().sun_study.playback
    local offset_minutes = solar.number(resolved:model().site.utc_offset_minutes) or 0
    local now = os.date("!*t", os.time() + offset_minutes * 60)
    local initial = {
      date = string.format("%04d-%02d-%02d", now.year, now.month, now.day),
      time = string.format("%02d:%02d", now.hour, now.min),
      step_minutes = runtime.step_minutes,
      frame_duration_ms = runtime.frame_duration_ms,
    }
    local first = solar.position(resolved:model().site, initial.date, initial.time)
    if first and first.daylight_state == "normal"
      and (first.minutes < first.sunrise_minutes or first.minutes > first.sunset_minutes)
    then
      initial.time = solar.format_time(first.sunrise_minutes)
    end
    resolved.sun_study = { active = true, playing = false, assumed_count = 0 }
    local form = require("roomplan.ui.form")
    local handle

    local function publish(draft)
      if not resolved.sun_study then return nil end
      local calculation = solar.position(resolved:model().site, draft.date, draft.time)
      resolved.sun_study.calculation = calculation
      resolved.sun_study.date = draft.date
      resolved.sun_study.time = draft.time
      resolved.sun_study.step_minutes = draft.step_minutes
      resolved.sun_study.frame_duration_ms = draft.frame_duration_ms
      controller.refresh(resolved)
      return calculation
    end

    local function advance(delta)
      if not handle or not form.is_current(handle) then return false end
      local draft = handle.state.draft
      local calculation = solar.position(resolved:model().site, draft.date, draft.time)
      if not calculation then return false end
      local next_time = calculation.minutes + delta * draft.step_minutes
      if calculation.daylight_state == "normal" then
        next_time = math.max(calculation.sunrise_minutes, math.min(calculation.sunset_minutes, next_time))
      else
        next_time = math.max(0, math.min(24 * 60 - 1, next_time))
      end
      form.set_value(handle, "time", solar.format_time(next_time), { raw = false, trusted = true })
      return next_time ~= calculation.minutes
    end

    local function render_playback()
      if handle and form.is_current(handle) then form.render(handle) end
    end

    local function toggle_play()
      if not resolved.sun_study then return false end
      if resolved.sun_study.playing then
        stop_timer(resolved)
        render_playback()
        return true
      end
      local calculation = solar.position(resolved:model().site, handle.state.draft.date, handle.state.draft.time)
      if calculation and calculation.daylight_state == "polar_night" then
        return nil, util.err("SUN_NO_DAYLIGHT", "there is no sunrise on this date")
      end
      local uv = vim.uv or vim.loop
      if not uv or not uv.new_timer then
        return nil, util.err("SUN_TIMER", "this Neovim build does not provide timers")
      end
      local duration = handle.state.draft.frame_duration_ms
      local timer = uv.new_timer()
      resolved.sun_study.timer = timer
      resolved.sun_study.playing = true
      timer:start(duration, duration, vim.schedule_wrap(function()
        if resolved.closed or not resolved.sun_study or not form.is_current(handle) then
          stop_timer(resolved)
          return
        end
        if not advance(1) then
          stop_timer(resolved)
          render_playback()
        end
      end))
      render_playback()
      return true
    end

    local spec = study_spec(resolved, initial)
    handle, err = form.open(resolved, spec, {
      on_submit = function() clear_study(controller, resolved); form_focus(controller, resolved); return true end,
      on_cancel = function() clear_study(controller, resolved); form_focus(controller, resolved) end,
      on_change = function(draft) publish(draft) end,
      on_reset = function(active) publish(active.state.draft) end,
      on_open = function(active)
        handle = active
        publish(active.state.draft)
        local mappings = require("roomplan.ui.mappings")
        mappings.set(active.bufnr, "h", function() advance(-1) end, "Previous sunlight step")
        mappings.set(active.bufnr, "l", function() advance(1) end, "Next sunlight step")
        mappings.set(active.bufnr, "<Space>", toggle_play, "Play or pause sunlight study")
      end,
      on_action = function(action)
        if action == "previous" then return advance(-1) end
        if action == "next" then return advance(1) end
        if action == "play" then return toggle_play() end
        if action == "edit_site" then
          stop_timer(resolved)
          if not form.transition(handle, "edit-sun-site") then return false end
          clear_study(controller, resolved)
          vim.schedule(function()
            if not resolved.closed then controller.configure_sun_site(resolved, { open_study = true }) end
          end)
          return true
        end
        return nil, util.err("SUN_ACTION", "unsupported sun-study action")
      end,
    })
    if not handle then
      clear_study(controller, resolved)
      return notify_error(err)
    end
    return handle
  end
end

return M
