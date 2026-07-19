-- Canvas/workspace presentation, viewport transforms, selection, and modes.
local compat = require("roomplan.compat")
local config = require("roomplan.config")
local snapping = require("roomplan.geometry.snapping")
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

  function controller.toggle_minimap(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if not resolved.canvas or not resolved.canvas.winid or not vim.api.nvim_win_is_valid(resolved.canvas.winid) then
      local opened, open_err = open_canvas(resolved)
      if not opened then return notify_error(open_err) end
    end
    local enabled, minimap_err = require("roomplan.ui.minimap").toggle(resolved)
    if minimap_err then compat.notify(minimap_err, vim.log.levels.WARN) end
    local workspace_ok, workspace = pcall(require, "roomplan.ui.workspace")
    if workspace_ok and resolved.workspace then workspace.refresh(resolved) end
    return enabled
  end

  function controller.next_issue(session, direction)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if type(direction) == "table" then direction = direction.direction end
    direction = direction == -1 and -1 or 1
    local diagnostics = controller.validate(resolved)
    if #diagnostics == 0 then compat.notify("RoomPlan has no validation issues") return end
    resolved.validation_index = ((resolved.validation_index or (direction < 0 and 1 or 0)) - 1 + direction) % #diagnostics + 1
    local diagnostic = diagnostics[resolved.validation_index]
    if diagnostic.object then resolved.selection = { kind = diagnostic.object.kind, id = diagnostic.object.id } end
    controller.reveal_selection(resolved)
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

  -- Centre the selected object without changing zoom or view rotation. Issue
  -- navigation uses this instead of fitting the complete plan, so inspecting a
  -- distant diagnostic does not destroy the user's working scale.
  function controller.reveal_selection(session, selection)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if type(selection) == "table" then
      resolved.selection = { kind = selection.kind, id = selection.id }
    end
    local focused, focus_err = controller.focus_canvas(resolved)
    if not focused then return nil, focus_err end
    local selected = resolved.selection
    if not selected or type(selected.id) ~= "string" then return selected or true end

    local handle = resolved.canvas and resolved.canvas.handle
    local scene
    if handle and handle.opts and type(handle.opts.get_scene) == "function" then
      scene = handle.opts.get_scene(handle)
    else
      local options = config.get()
      scene = require("roomplan.scene.build").build(resolved:current_model(), resolved.validation, {
        selected = selected,
        shape_edit = resolved.shape_edit,
        snap_guides = resolved.shape_edit and resolved.shape_edit.snap_guides or resolved.snap_guides,
        measurement = resolved.measurement,
        show_grid = options.canvas.show_grid,
        detail_level = resolved.canvas_detail_level or options.canvas.detail_level,
        sun_study = resolved.sun_study,
        sun_config = options.sun_study,
      })
    end
    local point = scene and scene.focus_points and scene.focus_points[selected.id] or nil
    if not point then return selected end

    local width, height = canvas_size(resolved)
    local viewport_module = require("roomplan.render.viewport")
    local current = ensure_viewport(resolved)
    local centre_x, centre_y = viewport_module.screen_to_world(
      current, math.max(0, (width - 1) / 2), math.max(0, (height - 1) / 2)
    )
    resolved.viewport = viewport_module.pan(current, point[1] - centre_x, point[2] - centre_y)
    local canvas_ok, canvas = pcall(require, "roomplan.render.canvas")
    if canvas_ok and handle and canvas.redraw then
      canvas.redraw(handle, scene, resolved.viewport, {
        focus_selection = true,
        reason = "reveal-selection",
      })
    else
      controller.refresh(resolved)
    end
    return selected
  end

  function controller.fit(session, opts)
    opts = type(opts) == "table" and opts or {}
    local resolved, err = resolve(session, opts)
    if not resolved then return notify_error(err) end
    local width, height = canvas_size(resolved)
    local options = config.get().canvas
    local scene = require("roomplan.scene.build").build(resolved:current_model(), resolved.validation, {
      selected = resolved.shape_edit and nil or resolved.selection,
      shape_edit = resolved.shape_edit,
      snap_guides = resolved.shape_edit and resolved.shape_edit.snap_guides or resolved.snap_guides,
      show_grid = options.show_grid,
      detail_level = resolved.canvas_detail_level or options.detail_level,
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

  ---Set or cycle the per-session presentation detail. This never enters the
  ---saved model or semantic history.
  function controller.set_detail_level(session, value)
    local opts = type(value) == "table" and value or {}
    if type(value) == "table" then value = value.level or value.detail_level or value.args end
    local resolved, err = resolve(session, opts)
    if not resolved then return notify_error(err) end
    local detail = require("roomplan.canvas_detail")
    if value == nil or value == "" or value == "cycle" then
      value = detail.next(resolved.canvas_detail_level)
    else
      value = detail.normalize(value)
      if not value then
        return notify_error(util.err("CANVAS_DETAIL_INVALID", "canvas detail must be high, middle, or none"))
      end
    end
    resolved.canvas_detail_level = value
    controller.refresh(resolved)
    if not opts.quiet then
      compat.notify(string.format("RoomPlan detail: %s (%s)", value, detail.description(value)))
    end
    return value
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
      compat.notify("RoomPlan view rotated: plan top points " .. rotation_labels[viewport_module.rotation(resolved.viewport)])
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
      return notify_error(util.err(
        "SELECTION_REQUIRED",
        "select a room, door, window, outlet, or furniture before entering MOVE mode"
      ))
    end
    if mode ~= "NAV" and mode ~= "MOVE" and mode ~= "PAN" then
      return notify_error(util.err("MODE_INVALID", "unsupported RoomPlan mode " .. tostring(mode)))
    end
    common.clear_snap_feedback(resolved)
    resolved.move_feedback = nil
    if mode ~= "MOVE" then
      resolved.batch_move = nil
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
    local target_row = cursor.row - dy * step
    local target_column = cursor.column + dx * step
    local viewport_module = require("roomplan.render.viewport")
    local current = ensure_viewport(session)
    local world_x, world_y = viewport_module.screen_to_world(current, target_column, target_row)
    local next_viewport = viewport_module.ensure_visible(
      current,
      world_x,
      world_y,
      width,
      height,
      config.get().canvas.scrolloff
    )
    local scrolled = next_viewport.world_left_mm ~= current.world_left_mm
      or next_viewport.world_top_mm ~= current.world_top_mm
    if scrolled then
      session.viewport = next_viewport
      local handle = session.canvas and session.canvas.handle
      if handle and canvas.redraw then
        local rendered = canvas.redraw(handle, nil, next_viewport, { reason = "scrolloff" })
        if not rendered then controller.refresh(session) end
      else
        controller.refresh(session)
      end
      target_column, target_row = viewport_module.world_to_screen(next_viewport, world_x, world_y)
    end
    canvas.set_logical_cursor(
      session,
      util.clamp(util.round(target_row), 0, height - 1),
      util.clamp(util.round(target_column), 0, width - 1)
    )
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
    local direction_label = dx < 0 and "left" or dx > 0 and "right" or dy < 0 and "down" or "up"
    local viewport_module = require("roomplan.render.viewport")
    local viewport = ensure_viewport(resolved)
    dx, dy = viewport_module.view_delta_to_world(viewport, dx, dy)
    if scale ~= "fine" then step = viewport_module.visible_move_step(viewport, dx, dy, step) end
    resolved.snap_exclusions = snapping.release_targets(resolved.snap_exclusions, resolved.snap_guides, {
      x = dx ~= 0,
      y = dy ~= 0,
    })
    resolved.snap_guides = {}
    local action
    local batch_snap
    if resolved.batch_move and #resolved.batch_move > 0 then
      local raw_delta = { dx * step, dy * step }
      local plan = resolved:model()
      local anchor = resolved.batch_move[1]
      local marked_rooms, marked_furniture = {}, {}
      for _, reference in ipairs(resolved.batch_move) do
        if reference.kind == "room" then
          marked_rooms[reference.id] = true
        end
        if reference.kind == "furniture" then
          marked_furniture[reference.id] = true
        end
      end
      local snap_options = common.snapping_options(resolved)
      local feedback_options = snap_options or { bypass = true }
      if anchor.kind == "room" then
        local room = model.find(plan, "room", anchor.id)
        local proposed = room and util.deepcopy(room) or nil
        if proposed then
          proposed.origin_mm = { proposed.origin_mm[1] + raw_delta[1], proposed.origin_mm[2] + raw_delta[2] }
          local targets = {}
          for _, candidate in ipairs(plan.rooms or {}) do
            if not marked_rooms[candidate.id] then
              targets[#targets + 1] = candidate
            end
          end
          batch_snap = snapping.snap_room(proposed, targets, feedback_options)
          raw_delta = {
            batch_snap.origin_mm[1] - room.origin_mm[1],
            batch_snap.origin_mm[2] - room.origin_mm[2],
          }
        end
      elseif anchor.kind == "furniture" then
        local furniture = model.find(plan, "furniture", anchor.id)
        local owner = furniture and model.find(plan, "room", furniture.room_id) or nil
        local proposed = furniture and util.deepcopy(furniture) or nil
        if owner and proposed then
          local field = (proposed.position_mm ~= nil or proposed.footprint ~= nil) and "position_mm" or "center_mm"
          proposed[field] = { proposed[field][1] + raw_delta[1], proposed[field][2] + raw_delta[2] }
          local pairs, apertures = {}, {}
          for _, candidate in ipairs(plan.furniture or {}) do
            if not marked_furniture[candidate.id] then
              local candidate_owner = model.find(plan, "room", candidate.room_id)
              if candidate_owner then
                pairs[#pairs + 1] = { furniture = candidate, room = candidate_owner }
              end
            end
          end
          local door_geometry = require("roomplan.geometry.door")
          for _, door in ipairs(plan.doors or {}) do
            local door_owner = model.find(plan, "room", door.room_id)
            if door_owner then
              apertures[#apertures + 1] = door_geometry.aperture(door_owner, door)
            end
          end
          batch_snap = snapping.snap_furniture(owner, proposed, pairs, apertures, feedback_options)
          raw_delta = {
            batch_snap[field][1] - furniture[field][1],
            batch_snap[field][2] - furniture[field][2],
          }
        end
      end
      local actions = {}
      for _, reference in ipairs(resolved.batch_move) do
        actions[#actions + 1] = {
          type = reference.kind == "room" and "move_room" or "move_furniture",
          id = reference.id,
          delta_mm = raw_delta,
          exact = true,
        }
      end
      action = {
        type = "batch",
        actions = actions,
        label = string.format("Move %d marked objects", #actions),
      }
    elseif selection.kind == "room" then
      action = { type = "move_room", id = selection.id, delta_mm = { dx * step, dy * step } }
    elseif selection.kind == "furniture" then
      action = { type = "move_furniture", id = selection.id, delta_mm = { dx * step, dy * step } }
    elseif selection.kind == "door" then
      local door = model.find(resolved:model(), "door", selection.id)
      if not door then return notify_error(util.err("SELECTION_STALE", "selected door no longer exists")) end
      local delta = (door.side == "north" or door.side == "south") and dx * step or dy * step
      action = { type = "edit_door", id = door.id, patch = { offset_mm = door.offset_mm + delta } }
    elseif selection.kind == "window" or selection.kind == "outlet" then
      local fixture = model.find(resolved:model(), selection.kind, selection.id)
      if not fixture then
        return notify_error(util.err("SELECTION_STALE", "selected wall object no longer exists"))
      end
      if selection.kind == "outlet" and fixture.placement == "floor" then
        action = {
          type = "edit_outlet",
          id = fixture.id,
          patch = { position_mm = {
            fixture.position_mm[1] + dx * step,
            fixture.position_mm[2] + dy * step,
          } },
        }
      else
        local delta = (fixture.side == "north" or fixture.side == "south") and dx * step or dy * step
        action = {
          type = selection.kind == "window" and "edit_window" or "edit_outlet",
          id = fixture.id,
          patch = { offset_mm = fixture.offset_mm + delta },
        }
      end
    else
      return notify_error(util.err("SELECTION_NOT_MOVABLE", "selected object cannot be moved"))
    end
    local result, action_err = controller.dispatch(resolved, action)
    if not result then return notify_error(action_err) end
    local snap_result = batch_snap or result.result and result.result.metadata and result.result.metadata.snapping
    if snap_result then
      resolved.snap_exclusions = snap_result.snap_exclusions or {}
      resolved.snap_guides = snapping.guides(snap_result)
    else
      common.clear_snap_feedback(resolved)
    end
    resolved.move_feedback = string.format(
      "%s %d mm%s", direction_label, step,
      resolved.batch_move and string.format(" · %d marked", #resolved.batch_move) or "")
    controller.refresh(resolved)
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
    common.clear_snap_feedback(resolved)
    resolved.move_feedback = nil
    hits = hits or {}
    if #hits == 0 then resolved.selection = nil controller.refresh(resolved) return end
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
    common.clear_snap_feedback(resolved)
    resolved.move_feedback = nil
    local scene = require("roomplan.scene.build").build(resolved:model(), resolved.validation, { selected = resolved.selection })
    local objects = scene.objects or {}
    if #objects == 0 then resolved.selection = nil return nil end
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
    common.clear_snap_feedback(resolved)
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
    resolved.move_feedback = nil
    if resolved.form then
      require("roomplan.ui.form").cancel(resolved.form, "cancelled")
    elseif resolved.workflow and resolved.workflow.kind then
      require("roomplan.ui.flow").cancel(resolved, "cancelled")
    elseif resolved.mode ~= "NAV" then
      common.clear_snap_feedback(resolved)
      resolved.mode = "NAV"
      resolved.batch_move = nil
    else
      common.clear_snap_feedback(resolved)
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
