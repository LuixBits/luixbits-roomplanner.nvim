-- Direct canvas room resizing. It previews a complete shape but commits
-- exactly one semantic room edit when the user applies it.

local config = require("roomplan.config")
local model = require("roomplan.model")
local room_shape = require("roomplan.room_shape")
local util = require("roomplan.util")

local common = require("roomplan.controller.common")

local M = {}

function M.attach(controller)
  local resolve = common.resolve
  local notify_error = common.notify_error
  local ensure_viewport = common.ensure_viewport

  local base = {
    add_menu = controller.add_menu,
    align_room = controller.align_room,
    delete_selected = controller.delete_selected,
    direction = controller.direction,
    duplicate_selected = controller.duplicate_selected,
    edit_selected = controller.edit_selected,
    escape = controller.escape,
    hide = controller.hide,
    redo = controller.redo,
    rotate_selected = controller.rotate_selected,
    save = controller.save,
    select_next = controller.select_next,
    select_under_cursor = controller.select_under_cursor,
    set_mode = controller.set_mode,
    toggle_snap = controller.toggle_snap,
    undo = controller.undo,
  }

  local function active(session)
    return session and session.room_shape_edit or nil
  end

  local function workspace_mode(session, mode)
    local ok, workspace = pcall(require, "roomplan.ui.workspace")
    if ok and session.workspace then workspace.set_interaction(session, mode, nil) end
  end

  local function publish(session, edit)
    local preview, err = room_shape.preview_model(session:model(), edit)
    if not preview then return nil, err end
    session.room_shape_edit = edit
    session.preview_model = preview
    session.mode = "RESIZE"
    session.selection = { kind = "room", id = edit.room_id }
    workspace_mode(session, session.mode)
    controller.refresh(session)
    return edit
  end

  local function clear(session)
    session.room_shape_edit = nil
    session.preview_model = nil
    common.clear_snap_feedback(session)
    session.move_feedback = nil
    session.mode = "NAV"
    workspace_mode(session, session.mode)
    controller.refresh(session)
  end

  local function room_for(session, edit)
    return model.find(session:model(), "room", edit.room_id)
  end

  local function cursor_world(session)
    local ok, canvas = pcall(require, "roomplan.render.canvas")
    local point = ok and canvas.world_at_cursor and canvas.world_at_cursor(session) or nil
    if not point then return nil end
    return { point.x, point.y }
  end

  local function update(session, next_edit, err)
    if not next_edit then return notify_error(err) end
    local result, publish_err = publish(session, next_edit)
    if not result then return notify_error(publish_err) end
    return result
  end

  function controller.start_room_resize(session, room_id)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if active(resolved) then return active(resolved) end
    common.clear_snap_feedback(resolved)
    resolved.move_feedback = nil
    local selection = resolved.selection
    room_id = room_id or (selection and selection.kind == "room" and selection.id)
    if not room_id then return notify_error(util.err("ROOM_REQUIRED", "select a room before editing its shape")) end
    local edit, start_err = room_shape.start(resolved:model(), room_id, resolved:revision_id())
    if not edit then return notify_error(start_err) end
    local result, publish_err = publish(resolved, edit)
    if not result then return notify_error(publish_err) end
    controller.focus_canvas(resolved)
    return result
  end

  function controller.select_room_shape_part(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    local edit = active(resolved)
    if not edit then return notify_error(util.err("ROOM_SHAPE_INACTIVE", "room resizing is not active")) end
    local owner = room_for(resolved, edit)
    local point = cursor_world(resolved)
    if not owner or not point then
      return notify_error(util.err("ROOM_SHAPE_CURSOR", "place the canvas cursor over a room section"))
    end
    return update(resolved, room_shape.select_world(edit, owner.origin_mm, point))
  end

  function controller.cycle_room_shape_part(session, direction)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    local edit = active(resolved)
    if not edit then return notify_error(util.err("ROOM_SHAPE_INACTIVE", "room resizing is not active")) end
    return update(resolved, room_shape.cycle(edit, direction or 1))
  end

  function controller.resize_room_shape_part(session, dx, dy, scale)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    local edit = active(resolved)
    if not edit then return notify_error(util.err("ROOM_SHAPE_INACTIVE", "room resizing is not active")) end
    local settings = resolved:model().settings
    local step = scale == "fine" and settings.fine_step_mm
      or scale == "coarse" and settings.coarse_step_mm
      or settings.normal_step_mm
    dx, dy = require("roomplan.render.viewport").view_delta_to_world(ensure_viewport(resolved), dx, dy)
    local owner = room_for(resolved, edit)
    local snap_options = common.snapping_options(resolved)
    local next_edit, shape_err = room_shape.direction(edit, dx, dy, step, config.get().limits, {
      model = resolved:model(),
      origin_mm = owner and owner.origin_mm,
      options = snap_options,
    })
    resolved.bypass_snap_once = false
    return update(resolved, next_edit, shape_err)
  end

  function controller.add_room_shape_part(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    local edit = active(resolved)
    if not edit then return notify_error(util.err("ROOM_SHAPE_INACTIVE", "room resizing is not active")) end
    local owner, part = room_for(resolved, edit), room_shape.selected(edit)
    local point = cursor_world(resolved)
    local dx, dy = 0, 0
    if owner and part and point then
      local center_x = owner.origin_mm[1] + part.origin_mm[1] + part.size_mm[1] / 2
      local center_y = owner.origin_mm[2] + part.origin_mm[2] + part.size_mm[2] / 2
      local relative_x, relative_y = point[1] - center_x, point[2] - center_y
      if math.abs(relative_x) >= math.abs(relative_y) then dx = relative_x < 0 and -1 or 1
      else dy = relative_y < 0 and -1 or 1 end
    end
    return update(resolved, room_shape.add(edit, dx, dy))
  end

  function controller.remove_room_shape_part(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    local edit = active(resolved)
    if not edit then return notify_error(util.err("ROOM_SHAPE_INACTIVE", "room resizing is not active")) end
    return update(resolved, room_shape.remove(edit, resolved:model()))
  end

  function controller.apply_room_shape_edit(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    local edit = active(resolved)
    if not edit then return base.save(resolved) end
    if resolved:revision_id() ~= edit.base_revision_id then
      return notify_error(util.err("ROOM_SHAPE_STALE", "the plan changed; cancel and restart resizing"))
    end
    if not room_shape.is_changed(edit) then clear(resolved); return true end
    local result, dispatch_err = controller.dispatch(resolved, room_shape.action(edit))
    if not result then return notify_error(dispatch_err) end
    clear(resolved)
    return result
  end

  function controller.cancel_room_shape_edit(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if not active(resolved) then return false end
    clear(resolved)
    return true
  end

  controller.direction = function(session, dx, dy, scale)
    if active(session) then return controller.resize_room_shape_part(session, dx, dy, scale) end
    return base.direction(session, dx, dy, scale)
  end
  controller.select_under_cursor = function(session)
    if active(session) then return controller.select_room_shape_part(session) end
    return base.select_under_cursor(session)
  end
  controller.select_next = function(session, direction)
    if active(session) then return controller.cycle_room_shape_part(session, direction) end
    return base.select_next(session, direction)
  end
  controller.set_mode = function(session, mode)
    if active(session) then
      return notify_error(util.err("ROOM_SHAPE_MODE", "apply or cancel resizing before changing canvas mode"))
    end
    return base.set_mode(session, mode)
  end
  controller.rotate_selected = function(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if active(resolved) then return active(resolved) end
    if resolved.selection and resolved.selection.kind == "room" then
      return controller.start_room_resize(resolved, resolved.selection.id)
    end
    return base.rotate_selected(resolved)
  end
  controller.add_menu = function(session)
    if active(session) then return controller.add_room_shape_part(session) end
    return base.add_menu(session)
  end
  controller.delete_selected = function(session)
    if active(session) then return controller.remove_room_shape_part(session) end
    return base.delete_selected(session)
  end
  controller.escape = function(session)
    if active(session) then return controller.cancel_room_shape_edit(session) end
    return base.escape(session)
  end
  controller.toggle_snap = function(session)
    if active(session) then session.room_shape_edit = room_shape.clear_feedback(active(session)) end
    return base.toggle_snap(session)
  end
  controller.hide = function(session, opts)
    if active(session) then controller.cancel_room_shape_edit(session) end
    return base.hide(session, opts)
  end
  controller.save = function(session, ...)
    if active(session) then
      local applied, err = controller.apply_room_shape_edit(session)
      if not applied then return nil, err end
    end
    return base.save(session, ...)
  end

  local function blocked(name, handler)
    return function(session, ...)
      if active(session) then
        return notify_error(util.err("ROOM_SHAPE_ACTIVE", name .. " is unavailable until resizing is applied or cancelled"))
      end
      return handler(session, ...)
    end
  end
  controller.align_room = blocked("alignment", base.align_room)
  controller.duplicate_selected = blocked("duplication", base.duplicate_selected)
  controller.edit_selected = blocked("another editor", base.edit_selected)
  controller.redo = blocked("redo", base.redo)
  controller.undo = blocked("undo", base.undo)
end

return M
