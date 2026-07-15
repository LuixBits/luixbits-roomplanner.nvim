-- Canvas/workspace presentation, viewport transforms, selection, and modes.
local compat = require("roomplan.compat")
local config = require("roomplan.config")
local model = require("roomplan.model")
local state = require("roomplan.state")
local util = require("roomplan.util")

local common = require("roomplan.controller.common")

local M = {}

function M.attach(controller)
  local finish = common.finish
  local is_session = common.is_session
  local notify_error = common.notify_error
  local resolve = common.resolve
  local ensure_viewport = common.ensure_viewport
  local open_canvas = function(session) return common.open_canvas(controller, session) end

  function controller.hide(session, opts)
    local resolved, err = resolve(session, opts)
    if not resolved then return notify_error(err) end
    local workspace_ok, workspace = pcall(require, "roomplan.ui.workspace")
    if workspace_ok and workspace.is_visible(resolved) then return workspace.hide(resolved) end
    local ok, canvas = pcall(require, "roomplan.render.canvas")
    if ok then return canvas.close(resolved) end
    return true
  end

  function controller.refresh(session)
    if not is_session(session) or session.closed then return end
    local workspace_ok, workspace = pcall(require, "roomplan.ui.workspace")
    if workspace_ok and session.workspace then workspace.refresh(session) end
    local ok, canvas = pcall(require, "roomplan.render.canvas")
    if ok and canvas.schedule_redraw then canvas.schedule_redraw(session) end
  end

  function controller.focus_canvas(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    local ok, canvas = pcall(require, "roomplan.render.canvas")
    if ok and canvas.focus and canvas.focus(resolved) then
      local workspace_ok, workspace = pcall(require, "roomplan.ui.workspace")
      if workspace_ok and workspace.is_visible(resolved) then workspace.focus(resolved, "canvas") end
      local handle = resolved.canvas and resolved.canvas.handle
      if handle and canvas.redraw then
        canvas.redraw(handle, nil, nil, { reason = "focus" })
      else
        controller.refresh(resolved)
      end
      return true
    end
    return open_canvas(resolved)
  end

  function controller.inspect(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if not resolved.canvas or not resolved.canvas.winid or not vim.api.nvim_win_is_valid(resolved.canvas.winid) then
      local opened, open_err = open_canvas(resolved)
      if not opened then return notify_error(open_err) end
    end
    return require("roomplan.ui.workspace").toggle(resolved, "properties")
  end

  function controller.objects(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if not resolved.canvas or not resolved.canvas.winid or not vim.api.nvim_win_is_valid(resolved.canvas.winid) then
      local opened, open_err = open_canvas(resolved)
      if not opened then return notify_error(open_err) end
    end
    return require("roomplan.ui.workspace").toggle(resolved, "objects")
  end

  -- Explicit aliases make pane toggles discoverable to commands and external
  -- integrations while retaining the established inspect()/objects() API.
  controller.toggle_details = controller.inspect
  controller.toggle_navigator = controller.objects

  function controller.next_issue(session, direction)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if type(direction) == "table" then direction = direction.direction end
    direction = direction == -1 and -1 or 1
    local diagnostics = controller.validate(resolved)
    if #diagnostics == 0 then compat.notify("RoomPlan has no validation issues"); return end
    resolved.validation_index = ((resolved.validation_index or (direction < 0 and 1 or 0)) - 1 + direction) % #diagnostics + 1
    local diagnostic = diagnostics[resolved.validation_index]
    if diagnostic.object then resolved.selection = { kind = diagnostic.object.kind, id = diagnostic.object.id } end
    controller.focus_canvas(resolved)
    compat.notify(string.format("%s: %s", diagnostic.code, diagnostic.message),
      diagnostic.severity == "error" and vim.log.levels.ERROR or vim.log.levels.WARN)
    return diagnostic
  end

  local function canvas_size(session)
    local winid = session.canvas and session.canvas.winid
    if not winid or not vim.api.nvim_win_is_valid(winid) then
      return math.max(1, vim.o.columns), math.max(1, vim.o.lines - config.get().canvas.header_lines - 3)
    end
    local local_footer = session.workspace and session.workspace.owns_footer and 0 or 1
    return vim.api.nvim_win_get_width(winid),
      math.max(1, vim.api.nvim_win_get_height(winid) - config.get().canvas.header_lines - local_footer)
  end

  function controller.fit(session, opts)
    opts = type(opts) == "table" and opts or {}
    local resolved, err = resolve(session, opts)
    if not resolved then return notify_error(err) end
    local width, height = canvas_size(resolved)
    local options = config.get().canvas
    local scene = require("roomplan.scene.build").build(resolved:model(), resolved.validation, {
      selected = resolved.selection,
      show_grid = options.show_grid,
      show_dimensions = options.show_dimensions,
    })
    local current_viewport = ensure_viewport(resolved)
    resolved.viewport = require("roomplan.render.viewport").fit_scene(scene, width, height, {
      mm_per_column = current_viewport.mm_per_column,
      cell_aspect = options.cell_aspect,
      rotation_quarters = current_viewport.rotation_quarters,
      fit_margin_cells = options.fit_margin_cells,
      min_mm_per_column = options.min_mm_per_column,
      max_mm_per_column = options.max_mm_per_column,
    })
    if opts.immediate then
      local ok, canvas = pcall(require, "roomplan.render.canvas")
      local handle = ok and resolved.canvas and resolved.canvas.handle
      if handle and canvas.redraw then
        canvas.redraw(handle, scene, resolved.viewport, {
          fit = true,
          focus_selection = opts.focus_selection == true,
          reason = "fit",
        })
      else
        controller.refresh(resolved)
      end
    else
      controller.refresh(resolved)
    end
    return resolved.viewport
  end

  ---Calibrate terminal cell height/width for this Neovim process. setup() stays
  ---the persistent configuration source; the runtime override refits every live
  ---session because all canvases share the same terminal cell geometry.
  function controller.set_aspect(session, opts, callback)
    if type(opts) ~= "table" then opts = { ratio = opts } end
    opts = opts or {}
    local raw = opts.ratio ~= nil and opts.ratio or opts.args
    if type(raw) == "string" and raw:match("^%s*$") then raw = nil end
    if raw == nil then
      vim.ui.input({
        prompt = "RoomPlan terminal cell height/width ratio: ",
        default = string.format("%.3g", config.get().canvas.cell_aspect),
        scope = "editor",
      }, function(value)
        if value == nil then
          finish(callback, nil, util.err("ASPECT_CANCELLED", "RoomPlan aspect calibration cancelled"))
          return
        end
        controller.set_aspect(session, vim.tbl_extend("force", opts, { ratio = value }), callback)
      end)
      return nil
    end

    local ratio = type(raw) == "number" and raw or tonumber(raw)
    local updated, config_err = config.set_cell_aspect(ratio)
    if not updated then return finish(callback, notify_error(config_err)) end

    for _, target in ipairs(state.list()) do
      if not target.closed then
        local handle = target.canvas and target.canvas.handle
        if handle and handle.opts then handle.opts.cell_aspect = updated end
        controller.fit(target, { immediate = true })
      end
    end
    if not opts.quiet then
      compat.notify(string.format("RoomPlan cell aspect set to %.3g (height / width)", updated))
    end
    return finish(callback, updated)
  end

  local rotation_labels = {
    [0] = "up",
    [1] = "right",
    [2] = "down",
    [3] = "left",
  }

  ---Rotate only the viewport projection. Saved room, door, and furniture
  ---coordinates stay unchanged.
  function controller.rotate_view(session, direction)
    local opts = type(direction) == "table" and direction or {}
    if type(direction) == "table" then direction = direction.direction or direction.args end
    if direction == nil or direction == "" then direction = "clockwise" end

    local resolved, err = resolve(session, opts)
    if not resolved then return notify_error(err) end
    local viewport_module = require("roomplan.render.viewport")
    local current = ensure_viewport(resolved)
    local normalized = type(direction) == "string" and direction:lower() or direction
    local delta
    if normalized == "clockwise" or normalized == "cw" or normalized == "right" or normalized == 1 then
      delta = 1
    elseif normalized == "counterclockwise" or normalized == "ccw" or normalized == "left" or normalized == -1 then
      delta = -1
    elseif normalized == "reset" or normalized == "north" or normalized == 0 then
      delta = -viewport_module.rotation(current)
    else
      return notify_error(util.err(
        "VIEW_ROTATION_INVALID",
        "view rotation must be clockwise, counterclockwise, or reset"
      ))
    end

    local width, height = canvas_size(resolved)
    local anchor
    local canvas_ok, canvas = pcall(require, "roomplan.render.canvas")
    if canvas_ok then
      local logical = canvas.logical_cursor(resolved)
      local world = canvas.world_at_cursor(resolved)
      if logical and world then
        anchor = {
          world_x = world.x, world_y = world.y,
          screen_x = logical.column, screen_y = logical.row,
        }
      end
    end
    resolved.viewport = viewport_module.rotate(current, delta, anchor, {
      columns = width,
      rows = height,
    })
    controller.refresh(resolved)
    if not opts.quiet then
      compat.notify("RoomPlan view rotated: north points " .. rotation_labels[viewport_module.rotation(resolved.viewport)])
    end
    return resolved.viewport
  end

  function controller.zoom(session, direction)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    local viewport = ensure_viewport(resolved)
    local width, height = canvas_size(resolved)
    local options = config.get().canvas
    local limits = {
      columns = width,
      rows = height,
      min_mm_per_column = options.min_mm_per_column,
      max_mm_per_column = options.max_mm_per_column,
    }
    local anchor
    local canvas_ok, canvas = pcall(require, "roomplan.render.canvas")
    if canvas_ok then
      local logical = canvas.logical_cursor(resolved)
      local world = canvas.world_at_cursor(resolved)
      if logical and world then
        anchor = {
          world_x = world.x, world_y = world.y,
          screen_x = logical.column, screen_y = logical.row,
        }
      end
    end
    if direction == "in" then
      resolved.viewport = require("roomplan.render.viewport").zoom_in(viewport, options.zoom_factor, anchor, limits)
    else
      resolved.viewport = require("roomplan.render.viewport").zoom_out(viewport, options.zoom_factor, anchor, limits)
    end
    controller.refresh(resolved)
    return resolved.viewport
  end

  function controller.set_mode(session, mode)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if mode == "MOVE" and not resolved.selection then
      return notify_error(util.err("SELECTION_REQUIRED", "select a room, door, or furniture before entering MOVE mode"))
    end
    if mode ~= "NAV" and mode ~= "MOVE" and mode ~= "PAN" then
      return notify_error(util.err("MODE_INVALID", "unsupported RoomPlan mode " .. tostring(mode)))
    end
    resolved.mode = mode
    local workspace_ok, workspace = pcall(require, "roomplan.ui.workspace")
    if workspace_ok and resolved.workspace then
      workspace.set_interaction(resolved, mode, resolved.form)
      if (mode == "MOVE" or mode == "PAN") and workspace.is_visible(resolved) then
        workspace.focus(resolved, "canvas")
      end
    end
    controller.refresh(resolved)
    return mode
  end

  local function move_canvas_cursor(session, dx, dy, coarse)
    local ok, canvas = pcall(require, "roomplan.render.canvas")
    if not ok then return end
    local cursor = canvas.logical_cursor(session)
    if not cursor then return end
    local step = coarse and 5 or 1
    local width, height = canvas_size(session)
    local row = util.clamp(cursor.row - dy * step, 0, height - 1)
    local column = util.clamp(cursor.column + dx * step, 0, width - 1)
    canvas.set_logical_cursor(session, row, column)
  end

  function controller.direction(session, dx, dy, scale)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if resolved.mode == "PAN" then
      local cells = scale == "coarse" and config.get().canvas.pan_coarse_step_cells or config.get().canvas.pan_step_cells
      resolved.viewport = require("roomplan.render.viewport").pan_cells(ensure_viewport(resolved), dx * cells, dy * cells)
      controller.refresh(resolved)
      return resolved.viewport
    elseif resolved.mode ~= "MOVE" then
      move_canvas_cursor(resolved, dx, dy, scale == "coarse")
      return true
    end
    local selection = resolved.selection
    if not selection then return notify_error(util.err("SELECTION_REQUIRED", "MOVE mode requires a selection")) end
    local settings = resolved:model().settings
    local step = scale == "fine" and settings.fine_step_mm
      or scale == "coarse" and settings.coarse_step_mm
      or settings.normal_step_mm
    dx, dy = require("roomplan.render.viewport").view_delta_to_world(ensure_viewport(resolved), dx, dy)
    local action
    if selection.kind == "room" then
      action = { type = "move_room", id = selection.id, delta_mm = { dx * step, dy * step } }
    elseif selection.kind == "furniture" then
      action = { type = "move_furniture", id = selection.id, delta_mm = { dx * step, dy * step } }
    elseif selection.kind == "door" then
      local door = model.find(resolved:model(), "door", selection.id)
      if not door then return notify_error(util.err("SELECTION_STALE", "selected door no longer exists")) end
      local delta = (door.side == "north" or door.side == "south") and dx * step or dy * step
      action = { type = "edit_door", id = door.id, patch = { offset_mm = door.offset_mm + delta } }
    else
      return notify_error(util.err("SELECTION_NOT_MOVABLE", "selected object cannot be moved"))
    end
    local result, action_err = controller.dispatch(resolved, action)
    if not result then return notify_error(action_err) end
    return result
  end

  function controller.pan(session, dx, dy, coarse)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    local cells = coarse and config.get().canvas.pan_coarse_step_cells or config.get().canvas.pan_step_cells
    resolved.viewport = require("roomplan.render.viewport").pan_cells(ensure_viewport(resolved), dx * cells, dy * cells)
    controller.refresh(resolved)
    return resolved.viewport
  end

  function controller.select_hits(session, hits, cycle_key)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    hits = hits or {}
    if #hits == 0 then resolved.selection = nil; controller.refresh(resolved); return end
    resolved.selection_cycle = resolved.selection_cycle or {}
    local current = resolved.selection_cycle.key == cycle_key and resolved.selection or nil
    local index = 1
    if current then
      for candidate_index, candidate in ipairs(hits) do
        if candidate.id == current.id and (candidate.type or candidate.kind) == current.kind then
          index = candidate_index % #hits + 1
          break
        end
      end
    end
    local candidate = hits[index]
    resolved.selection = { kind = candidate.type or candidate.kind, id = candidate.id }
    resolved.selection_cycle.key = cycle_key
    resolved.selection_cycle.index = index
    controller.refresh(resolved)
    return resolved.selection
  end

  function controller.select_under_cursor(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    local ok, canvas = pcall(require, "roomplan.render.canvas")
    if not ok or not canvas.hit_candidates then return nil end
    local cursor = canvas.logical_cursor(resolved)
    local key = cursor and string.format("%d:%d", cursor.row, cursor.column) or nil
    return controller.select_hits(resolved, canvas.hit_candidates(resolved) or {}, key)
  end

  function controller.select_next(session, direction)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    local scene = require("roomplan.scene.build").build(resolved:model(), resolved.validation, { selected = resolved.selection })
    local objects = scene.objects or {}
    if #objects == 0 then resolved.selection = nil; return nil end
    local current_index = direction < 0 and 1 or 0
    for index, object in ipairs(objects) do
      if resolved.selection and object.id == resolved.selection.id and object.type == resolved.selection.kind then
        current_index = index
        break
      end
    end
    local next_index = ((current_index - 1 + direction) % #objects) + 1
    resolved.selection = { kind = objects[next_index].type, id = objects[next_index].id }
    controller.refresh(resolved)
    return resolved.selection
  end

  function controller.toggle_snap(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    resolved.snap_enabled = not resolved.snap_enabled
    compat.notify("RoomPlan snapping " .. (resolved.snap_enabled and "enabled" or "disabled"))
    controller.refresh(resolved)
    return resolved.snap_enabled
  end

  function controller.bypass_snap(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    resolved.bypass_snap_once = true
    compat.notify("RoomPlan will bypass snapping for the next move")
    return true
  end

  function controller.escape(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if resolved.form then
      require("roomplan.ui.form").cancel(resolved.form, "cancelled")
    elseif resolved.workflow and resolved.workflow.kind then
      require("roomplan.ui.flow").cancel(resolved, "cancelled")
    elseif resolved.mode ~= "NAV" then
      resolved.mode = "NAV"
    else
      resolved.selection = nil
    end
    local workspace_ok, workspace = pcall(require, "roomplan.ui.workspace")
    if workspace_ok and resolved.workspace then
      workspace.set_interaction(resolved, resolved.mode or "NAV", resolved.form)
    end
    controller.refresh(resolved)
  end

end

return M
