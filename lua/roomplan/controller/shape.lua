-- Direct canvas room, placed-furniture, and project-template shape editing. It
-- previews a complete shape but commits exactly one semantic history change
-- when the user applies it.

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
    return session and session.shape_edit or nil
  end

  local function workspace_mode(session, mode)
    local ok, workspace = pcall(require, "roomplan.ui.workspace")
    if ok and session.workspace then workspace.set_interaction(session, mode, nil) end
  end

  local function publish(session, edit)
    local preview, err = room_shape.preview_model(session:model(), edit)
    if not preview then return nil, err end
    session.shape_edit = edit
    session.preview_model = preview
    session.mode = "RESIZE"
    session.selection = { kind = edit.kind or "room", id = edit.entity_id or edit.room_id }
    workspace_mode(session, session.mode)
    controller.refresh(session)
    return edit
  end

  local function clear(session)
    local edit = active(session)
    if edit and edit.kind == "template" then
      session.viewport = edit.previous_viewport and util.deepcopy(edit.previous_viewport) or nil
    end
    session.shape_edit = nil
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

  local function entity_for(value, edit)
    return model.find(value, edit.kind or "room", edit.entity_id or edit.room_id)
  end

  local function world_shape(value, edit)
    local target = entity_for(value, edit)
    if not target then return nil end
    local geometry = require("roomplan.geometry.footprint")
    if edit.kind == "furniture" then
      local owner = model.find(value, "room", target.room_id)
      return owner and geometry.from_furniture(owner, target) or nil
    elseif edit.kind == "template" then
      return geometry.from_persisted(target.default_footprint)
    end
    return geometry.from_room(target)
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

  function controller.start_shape_resize(session, kind, entity_id)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if active(resolved) then return active(resolved) end
    common.clear_snap_feedback(resolved)
    resolved.move_feedback = nil
    local selection = resolved.selection
    kind = kind or (selection and selection.kind)
    entity_id = entity_id or (selection and selection.id)
    if kind ~= "room" and kind ~= "furniture" and kind ~= "template" then
      return notify_error(util.err("SHAPE_REQUIRED",
        "select a room, placed furniture item, or project template before editing its shape"))
    end
    if not entity_id then return notify_error(util.err("SHAPE_REQUIRED", "select an object before editing its shape")) end
    local edit, start_err = room_shape.start(resolved:model(), entity_id, resolved:revision_id(), kind)
    if not edit then return notify_error(start_err) end
    if kind == "template" then edit.previous_viewport = util.deepcopy(resolved.viewport) end
    local result, publish_err = publish(resolved, edit)
    if not result then return notify_error(publish_err) end
    controller.focus_canvas(resolved)
    if kind == "template" then controller.fit(resolved, { focus_selection = true, immediate = true }) end
    return result
  end

  function controller.start_room_resize(session, room_id)
    return controller.start_shape_resize(session, "room", room_id)
  end

  function controller.edit_selected_shape(session)
    return controller.start_shape_resize(session)
  end

  function controller.select_room_shape_part(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    local edit = active(resolved)
    if not edit then return notify_error(util.err("ROOM_SHAPE_INACTIVE", "room resizing is not active")) end
    local point = cursor_world(resolved)
    local shape = world_shape(resolved:current_model(), edit)
    if not shape or not point then
      return notify_error(util.err("SHAPE_CURSOR", "place the canvas cursor over a shape section"))
    end
    return update(resolved, room_shape.select_world(edit, shape, point))
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
    local direction_label = dx < 0 and "left" or dx > 0 and "right" or dy < 0 and "down" or "up"
    dx, dy = require("roomplan.render.viewport").view_delta_to_world(ensure_viewport(resolved), dx, dy)
    dx, dy = room_shape.local_delta(edit, dx, dy)
    local owner = room_for(resolved, edit)
    local snap_options = common.snapping_options(resolved)
    local next_edit, shape_err = room_shape.direction(edit, dx, dy, step, config.get().limits, {
      model = resolved:model(),
      origin_mm = owner and owner.origin_mm,
      options = snap_options,
      world_shape = function(candidate)
        local preview = room_shape.preview_model(resolved:model(), candidate)
        return preview and world_shape(preview, candidate) or nil
      end,
    })
    if next_edit then next_edit.move_feedback = string.format("%s %d mm", direction_label, step) end
    resolved.bypass_snap_once = false
    return update(resolved, next_edit, shape_err)
  end

  function controller.add_room_shape_part(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    local edit = active(resolved)
    if not edit then return notify_error(util.err("ROOM_SHAPE_INACTIVE", "room resizing is not active")) end
    local part = room_shape.selected(edit)
    local point = cursor_world(resolved)
    local dx, dy = 0, 0
    local shape = world_shape(resolved:current_model(), edit)
    local runtime_part
    for _, candidate in ipairs(shape and shape.parts or {}) do
      if part and candidate.id == part.id then runtime_part = candidate; break end
    end
    if runtime_part and point then
      local center_x = (runtime_part.left2 + runtime_part.right2) / 4
      local center_y = (runtime_part.bottom2 + runtime_part.top2) / 4
      local relative_x, relative_y = point[1] - center_x, point[2] - center_y
      if math.abs(relative_x) >= math.abs(relative_y) then dx = relative_x < 0 and -1 or 1
      else dy = relative_y < 0 and -1 or 1 end
      dx, dy = room_shape.local_delta(edit, dx, dy)
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

  function controller.apply_room_shape_edit(session, scope)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    local edit = active(resolved)
    if not edit then return base.save(resolved) end
    if resolved:revision_id() ~= edit.base_revision_id then
      return notify_error(util.err("SHAPE_STALE", "the plan changed; cancel and restart shape editing"))
    end
    if not room_shape.is_changed(edit) then clear(resolved); return true end
    local result, dispatch_err = controller.dispatch(resolved, room_shape.action(edit, scope))
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
    if active(session) then session.shape_edit = room_shape.clear_feedback(active(session)) end
    return base.toggle_snap(session)
  end
  controller.hide = function(session, opts)
    if active(session) then controller.cancel_room_shape_edit(session) end
    return base.hide(session, opts)
  end
  controller.save = function(session, ...)
    if active(session) then
      local edit = active(session)
      local source_template = edit.kind == "furniture" and edit.template_id
        and model.find(session:model(), "template", edit.template_id) or nil
      if room_shape.is_changed(edit) and source_template then
        local save_args = { ... }
        return require("roomplan.ui.palette").open({
          session = session,
          title = "Save furniture shape",
          items = {
            {
              key = "i",
              label = "This item only",
              description = "Keep the project template and every other placed item unchanged.",
              callback = function()
                local applied = controller.apply_room_shape_edit(session, "item")
                if applied then base.save(session, unpack(save_args)) end
              end,
            },
            {
              key = "t",
              label = "Item + project template",
              description = "Use this shape for future placements; existing other items stay unchanged.",
              callback = function()
                local applied = controller.apply_room_shape_edit(session, "template")
                if applied then base.save(session, unpack(save_args)) end
              end,
            },
          },
        })
      end
      local applied, err = controller.apply_room_shape_edit(session, "item")
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
