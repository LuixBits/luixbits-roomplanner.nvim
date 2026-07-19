-- Stateless controller helpers shared across lifecycle, persistence, view, and
-- editing modules. The public facade is injected only where callbacks need it.
local compat = require("roomplan.compat")
local config = require("roomplan.config")
local state = require("roomplan.state")
local util = require("roomplan.util")

local M = {}

function M.message(err)
  if type(err) == "table" then return err.message or err.code or vim.inspect(err) end
  return tostring(err)
end

function M.notify_error(err)
  compat.notify(M.message(err), vim.log.levels.ERROR)
  return nil, err
end

function M.finish(callback, value, err)
  if callback then callback(value, err) end
  return value, err
end

function M.is_session(value) return type(value) == "table" and value.history and value.source and value.id end

function M.interactive_call(session, opts)
  return M.is_session(session) or (opts and (opts.interactive == true or opts.fargs ~= nil))
end

function M.resolve(session, opts)
  if M.is_session(session) then return session end
  return state.resolve(opts or {})
end

function M.ensure_viewport(session)
  if not session.viewport then
    local options = config.get().canvas
    session.viewport = require("roomplan.render.viewport").new({
      mm_per_column = options.mm_per_column,
      cell_aspect = options.cell_aspect,
    })
  end
  return session.viewport
end

function M.snapping_options(session)
  if not session.snap_enabled or session.bypass_snap_once then return false end
  local options = util.deepcopy(config.get().snapping)
  local viewport_module = require("roomplan.render.viewport")
  local world_x_scale, world_y_scale = viewport_module.world_axis_scales(M.ensure_viewport(session))
  local cap = options.max_distance_mm
  -- At deep zoom levels a cell can represent less than the plan's fine move
  -- step. Keep that step inside the magnetic range so a small millimetre
  -- remainder is cleaned up by ordinary movement instead of requiring
  -- repeated Ctrl-h/j/k/l corrections.
  local fine_step = session:model().settings.fine_step_mm or 0
  options.tolerance_mm = {
    x = math.min(cap, math.max(fine_step, options.tolerance_cells * world_x_scale)),
    y = math.min(cap, math.max(fine_step, options.tolerance_cells * world_y_scale)),
  }
  options.mm_per_screen_unit = { x = world_x_scale, y = world_y_scale }
  options.grid_mm = session:model().settings.grid_mm
  options.exclude_targets = util.deepcopy(session.snap_exclusions or {})
  return options
end

function M.clear_snap_feedback(session)
  session.snap_guides = {}
  session.snap_exclusions = {}
end

function M.open_canvas(controller, session)
  local ok, canvas = pcall(require, "roomplan.render.canvas")
  if not ok then
    return nil, util.err("CANVAS_UNAVAILABLE", "RoomPlan renderer is not available yet", { cause = canvas })
  end
  local opened, err = canvas.open(session, {
    on_select = function(hits) controller.select_hits(session, hits) end,
    on_cursor = function()
      local workspace_ok, workspace = pcall(require, "roomplan.ui.workspace")
      if workspace_ok and session.workspace then
        local world = canvas.world_at_cursor(session)
        local canvas_config = config.get().canvas
        local zoom = session.viewport
            and session.viewport.mm_per_column
            and canvas_config.mm_per_column / session.viewport.mm_per_column
          or 1
        workspace.update_cursor(session, world, zoom)
      end
    end,
    on_redraw = function(_, output)
      local minimap_ok, minimap = pcall(require, "roomplan.ui.minimap")
      if minimap_ok then pcall(minimap.refresh, session, output) end
    end,
    on_wipe = function(handle)
      local minimap_ok, minimap = pcall(require, "roomplan.ui.minimap")
      if minimap_ok then pcall(minimap.close, session) end
      if handle and handle.buf then state.detach_buffer(handle.buf) end
      session.canvas = { bufnr = nil, winid = nil }
    end,
  })
  if not opened then return nil, err end
  if opened.buf then state.attach_buffer(session, opened.buf, "canvas") end

  local workspace_ok, workspace = pcall(require, "roomplan.ui.workspace")
  if not workspace_ok then
    return nil, util.err("WORKSPACE_UNAVAILABLE", "RoomPlan workspace is unavailable", { cause = workspace })
  end
  local mounted_ok, mounted = pcall(workspace.mount, session, {
    on_form_action = function(active_session, action)
      local handle = active_session and active_session.form
      if not handle then return nil, util.err("FORM_UNAVAILABLE", "no structured RoomPlan form is active") end
      return require("roomplan.ui.form").perform(handle, action)
    end,
  })
  if not mounted_ok then return nil, util.err("WORKSPACE_OPEN_FAILED", tostring(mounted), { cause = mounted }) end
  workspace.set_interaction(session, session.mode or "NAV", session.form)
  canvas.redraw(opened, nil, nil, { reason = "workspace-mounted" })
  return session
end

return M
