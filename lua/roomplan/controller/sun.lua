local common = require("roomplan.controller.common")
local config = require("roomplan.config")
local solar = require("roomplan.solar")
local util = require("roomplan.util")

local M = {}

local DATE_PRESETS = {
  { value = "custom", label = "Custom date" },
  { value = "today", label = "Today" },
  { value = "march", label = "March equinox" },
  { value = "june", label = "June solstice" },
  { value = "september", label = "September equinox" },
  { value = "december", label = "December solstice" },
}

local PRESET_MONTH_DAY = {
  march = { 3, 20 },
  june = { 6, 21 },
  september = { 9, 22 },
  december = { 12, 21 },
}

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

local function reset_playback(study)
  if not study then return end
  study.playback_state = "idle"
  study.overlay = "instant"
end

local function build_daily_exposure(session)
  local study = session and session.sun_study
  if not study then return nil, "the sunlight study is not active" end
  local model = session:model()
  local wall_scene = require("roomplan.scene.walls").build(
    model.rooms or {}, model.doors or {}, model.windows or {}, model.outlets or {})
  local exposure, reason = require("roomplan.analysis.sunlight").build_day(
    model, wall_scene, model.site, study.date, study.step_minutes,
    config.get().sun_study.window_defaults)
  if not exposure then return nil, reason end
  study.daily_exposure = exposure
  study.overlay = "daily"
  study.assumed_count = exposure.assumed_count or 0
  return exposure
end

local function clear_study(controller, session)
  stop_timer(session)
  session.sun_study = nil
  if not session.closed then controller.refresh(session) end
end

local function publish(controller, session, values, opts)
  opts = opts or {}
  local study = session and session.sun_study
  if not study then return nil, util.err("SUN_INACTIVE", "the sunlight study is not active") end
  local calculation, reason = solar.position(session:model().site, values.date, values.time)
  if not calculation then return nil, util.err("SUN_INVALID_TIME", reason) end
  study.calculation = calculation
  study.date = values.date
  study.time = values.time
  study.step_minutes = values.step_minutes
  study.frame_duration_ms = values.frame_duration_ms
  if not opts.preserve_overlay then
    study.daily_exposure = nil
    reset_playback(study)
  end
  controller.refresh(session)
  return calculation
end

local function advance(controller, session, delta, opts)
  opts = opts or {}
  local study = session and session.sun_study
  if not study then return nil, util.err("SUN_INACTIVE", "the sunlight study is not active") end
  local calculation, reason = solar.position(session:model().site, study.date, study.time)
  if not calculation then return nil, util.err("SUN_INVALID_TIME", reason) end
  local next_time = calculation.minutes + delta * study.step_minutes
  if calculation.daylight_state == "normal" then
    next_time = math.max(calculation.sunrise_minutes, math.min(calculation.sunset_minutes, next_time))
  else
    next_time = math.max(0, math.min(24 * 60 - 1, next_time))
  end
  local next_text = solar.format_time(next_time)
  if next_text == study.time then return false end
  study.time = next_text
  local updated, update_error = publish(controller, session, study, { preserve_overlay = opts.playback == true })
  if not updated then return nil, update_error end
  return true
end

local function advance_season(controller, session, delta)
  local study = session and session.sun_study
  if not study then return nil, util.err("SUN_INACTIVE", "the sunlight study is not active") end
  local date, reason = solar.shift_months(study.date, (delta < 0 and -1 or 1) * 3)
  if not date then return nil, util.err("SUN_INVALID_DATE", reason) end
  stop_timer(session)
  study.date = date
  local calculation, publish_error = publish(controller, session, study)
  if not calculation then return nil, publish_error end
  return true
end

local function toggle_playback(controller, session)
  local study = session and session.sun_study
  if not study then return nil, util.err("SUN_INACTIVE", "the sunlight study is not active") end
  if not study.viewing then
    return nil, util.err("SUN_NOT_VIEWING", "view the sunlight study on the canvas before starting playback")
  end
  if study.playing then
    stop_timer(session)
    study.playback_state = "paused"
    controller.refresh(session)
    return false
  end
  if study.calculation and study.calculation.daylight_state == "polar_night" then
    return nil, util.err("SUN_NO_DAYLIGHT", "there is no sunrise on this date")
  end
  local uv = vim.uv or vim.loop
  if not uv or not uv.new_timer then
    return nil, util.err("SUN_TIMER", "this Neovim build does not provide timers")
  end
  if study.playback_state ~= "paused" then
    local calculation = study.calculation
    if calculation and calculation.daylight_state ~= "polar_night" then
      local first = calculation.daylight_state == "polar_day" and 0 or calculation.sunrise_minutes
      study.time = solar.format_time(first)
      local updated, update_error = publish(controller, session, study, { preserve_overlay = true })
      if not updated then return nil, update_error end
    end
  end
  study.overlay = "instant"
  local timer = uv.new_timer()
  study.timer = timer
  study.playing = true
  study.playback_state = "playing"
  timer:start(study.frame_duration_ms, study.frame_duration_ms, vim.schedule_wrap(function()
    local current = session.sun_study
    if session.closed or not current or not current.viewing then
      stop_timer(session)
      return
    end
    local changed = advance(controller, session, 1, { playback = true })
    if changed == nil then
      stop_timer(session)
      current.playback_state = "idle"
      current.overlay = "instant"
      controller.refresh(session)
    elseif not changed then
      stop_timer(session)
      current.playback_state = "finished"
      build_daily_exposure(session)
      controller.refresh(session)
    end
  end))
  controller.refresh(session)
  return true
end

local function form_focus(controller, session)
  vim.schedule(function()
    if session.closed then return end
    controller.refresh(session)
    local ok, workspace = pcall(require, "roomplan.ui.workspace")
    if ok and workspace.is_visible(session) then workspace.focus(session, "canvas") end
  end)
end

local function study_spec(session, initial, local_today)
  local spec = {
    id = "sun-study",
    title = "Sun study",
    mode = "SUN STUDY",
    description = "h/l change time; Space plays the whole day. Canvas j/k compare three-month seasons.",
    apply_label = "View on canvas",
    context = { session = session },
    initial = initial,
    fields = {
      {
        key = "date_preset", label = "Date preset", type = "enum", required = true,
        choices = DATE_PRESETS,
      },
      { key = "date", label = "Date", type = "text", required = true, trim = true },
      { key = "utc_offset", label = "UTC offset", type = "readonly", value = function()
        local offset = solar.number(session:model().site and session:model().site.utc_offset_minutes)
        return offset and (solar.format_utc_offset(offset) .. " · fixed; must match this date") or "Unavailable"
      end },
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
        return session.sun_study and session.sun_study.playing and "Running · Space pauses"
          or "Paused · Space plays whole day"
      end },
      { key = "previous", label = "Earlier time", type = "action", action = "previous" },
      { key = "view", label = "View current time on canvas", type = "action", action = "view" },
      { key = "play", label = "Play whole day on canvas", type = "action", action = "play" },
      { key = "exposure", label = "View daily exposure", type = "action", action = "exposure" },
      { key = "next", label = "Later time", type = "action", action = "next" },
      { key = "edit_site", label = "Edit location and plan north", type = "action", action = "edit_site" },
    },
  }
  function spec.on_change(key, value, _, draft)
    if key == "date" then return { date_preset = "custom" } end
    if key ~= "date_preset" or value == "custom" then return nil end
    if value == "today" then return { date = local_today } end
    local date = solar.parse_date(draft.date)
    local month_day = PRESET_MONTH_DAY[value]
    if date and month_day then
      return { date = string.format("%04d-%02d-%02d", date.year, month_day[1], month_day[2]) }
    end
  end
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
  local base_direction = controller.direction
  local base_escape = controller.escape
  local base_hide = controller.hide

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
    if resolved.mode ~= "NAV" or resolved.shape_edit then
      return notify_error(util.err("SUN_BUSY", "finish the current interaction before opening the sunlight study"))
    end
    if not resolved:model().site then
      return controller.configure_sun_site(resolved, { open_study = true })
    end
    local runtime = config.get().sun_study.playback
    local offset_minutes = solar.number(resolved:model().site.utc_offset_minutes) or 0
    local now = os.date("!*t", os.time() + offset_minutes * 60)
    local local_today = string.format("%04d-%02d-%02d", now.year, now.month, now.day)
    local initial
    if resolved.sun_study then
      stop_timer(resolved)
      resolved.sun_study.viewing = false
      initial = {
        date_preset = "custom",
        date = resolved.sun_study.date,
        time = resolved.sun_study.time,
        step_minutes = resolved.sun_study.step_minutes,
        frame_duration_ms = resolved.sun_study.frame_duration_ms,
      }
    else
      initial = {
        date_preset = "custom",
        date = local_today,
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
      resolved.sun_study = {
        active = true, viewing = false, playing = false, playback_state = "idle",
        overlay = "instant", assumed_count = 0,
      }
    end
    local form = require("roomplan.ui.form")
    local handle
    local play_after_submit = false
    local overlay_after_submit = "instant"

    local function advance_form(delta)
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
      local next_text = solar.format_time(next_time)
      if next_text == draft.time then return false end
      form.set_value(handle, "time", next_text, { raw = false, trusted = true })
      return true
    end

    local function view_on_canvas(play, overlay)
      play_after_submit = play == true
      overlay_after_submit = overlay or "instant"
      return form.apply(handle)
    end

    local spec = study_spec(resolved, initial, local_today)
    handle, err = form.open(resolved, spec, {
      on_submit = function(draft)
        local calculation, publish_error = publish(controller, resolved, draft)
        if not calculation then return nil, publish_error end
        resolved.sun_study.overlay = overlay_after_submit
        if overlay_after_submit == "daily" then
          local exposure, exposure_error = build_daily_exposure(resolved)
          if not exposure then return nil, util.err("SUN_EXPOSURE", exposure_error) end
        end
        resolved.sun_study.viewing = true
        local start_playback = play_after_submit
        play_after_submit = false
        overlay_after_submit = "instant"
        vim.schedule(function()
          if resolved.closed or not resolved.sun_study then return end
          controller.focus_canvas(resolved)
          if start_playback then controller.sun_toggle(resolved) end
        end)
        return true
      end,
      on_cancel = function() clear_study(controller, resolved); form_focus(controller, resolved) end,
      on_change = function(draft) publish(controller, resolved, draft) end,
      on_reset = function(active) publish(controller, resolved, active.state.draft) end,
      on_open = function(active)
        handle = active
        publish(controller, resolved, active.state.draft)
        local mappings = require("roomplan.ui.mappings")
        mappings.set(active.bufnr, "h", function() advance_form(-1) end, "Previous sunlight step")
        mappings.set(active.bufnr, "l", function() advance_form(1) end, "Next sunlight step")
        mappings.set(active.bufnr, "<Space>", function() view_on_canvas(true) end,
          "Play the whole sunlight day on the canvas")
      end,
      on_action = function(action)
        if action == "previous" then return advance_form(-1) end
        if action == "next" then return advance_form(1) end
        if action == "view" then return view_on_canvas(false) end
        if action == "play" then return view_on_canvas(true) end
        if action == "exposure" then return view_on_canvas(false, "daily") end
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

  function controller.sun_step(session, delta)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if not resolved.sun_study or not resolved.sun_study.viewing then
      return notify_error(util.err("SUN_NOT_VIEWING", "open the sunlight study with S first"))
    end
    stop_timer(resolved)
    reset_playback(resolved.sun_study)
    local changed, step_error = advance(controller, resolved, delta and delta < 0 and -1 or 1)
    if changed == nil then return notify_error(step_error) end
    return changed
  end


  function controller.sun_season(session, delta)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if not resolved.sun_study or not resolved.sun_study.viewing then
      return notify_error(util.err("SUN_NOT_VIEWING", "open the sunlight study with S first"))
    end
    local changed, season_error = advance_season(controller, resolved, delta and delta < 0 and -1 or 1)
    if changed == nil then return notify_error(season_error) end
    return changed
  end

  function controller.sun_toggle(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    local playing, playback_error = toggle_playback(controller, resolved)
    if playing == nil then return notify_error(playback_error) end
    return playing
  end

  function controller.close_sun_study(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if not resolved.sun_study then return false end
    clear_study(controller, resolved)
    return true
  end

  controller.direction = function(session, dx, dy, scale)
    if session and session.sun_study and session.sun_study.viewing and scale == "normal" then
      if dy == 0 and dx ~= 0 then return controller.sun_step(session, dx) end
      if dx == 0 and dy ~= 0 then return controller.sun_season(session, dy > 0 and -1 or 1) end
    end
    return base_direction(session, dx, dy, scale)
  end

  controller.escape = function(session)
    if session and session.sun_study and session.sun_study.viewing then
      return controller.close_sun_study(session)
    end
    return base_escape(session)
  end

  controller.hide = function(session, opts)
    if session and session.sun_study then clear_study(controller, session) end
    return base_hide(session, opts)
  end
end

return M
