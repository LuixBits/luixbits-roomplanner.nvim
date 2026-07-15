-- Atomic action dispatch, history, structured forms, and action menus.
local catalog = require("roomplan.catalog")
local config = require("roomplan.config")
local model = require("roomplan.model")
local state = require("roomplan.state")
local util = require("roomplan.util")

local common = require("roomplan.controller.common")

local M = {}

function M.attach(controller)
  local is_session = common.is_session
  local notify_error = common.notify_error
  local resolve = common.resolve
  local ensure_viewport = common.ensure_viewport

  local function spatial_object_count(plan)
    if type(plan) ~= "table" then return 0 end
    return #(plan.rooms or {}) + #(plan.doors or {}) + #(plan.windows or {})
      + #(plan.outlets or {}) + #(plan.furniture or {})
  end

  function controller.dispatch(session, action)
    local resolved, err = resolve(session)
    if not resolved then return nil, err end
    local was_spatially_empty = spatial_object_count(resolved:model()) == 0
    local current_diagnostics = controller.validate(resolved)
    local new_model, result = require("roomplan.actions").apply(resolved:model(), action, {
      limits = config.get().limits,
      catalog = catalog,
      snapping = common.snapping_options(resolved),
      current_diagnostics = current_diagnostics,
    })
    resolved.bypass_snap_once = false
    if not new_model then return nil, result end
    local node, history_info = resolved:commit(new_model, result)
    if not node then return nil, history_info end
    if result.validation then
      resolved.validation = result.validation
      resolved.validation_summary = result.validation_summary
      resolved.validation_revision_id = node.revision_id
    else
      controller.validate(resolved)
    end
    if was_spatially_empty and spatial_object_count(new_model) > 0 then
      -- The first object changes the canvas from an abstract empty viewport into
      -- a spatial scene. Fit exactly once and move the cursor to the selected
      -- object so the successful action cannot look like a no-op.
      controller.fit(resolved, { focus_selection = true, immediate = true })
      controller.focus_canvas(resolved)
    end
    return {
      session_id = resolved.id,
      revision_id = node.revision_id,
      model = new_model,
      result = result,
      history = history_info,
    }
  end

  function controller.undo(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    common.clear_snap_feedback(resolved)
    local snapshot, node = resolved:undo()
    if not snapshot then return notify_error(node) end
    controller.validate(resolved)
    return snapshot, node
  end

  function controller.redo(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    common.clear_snap_feedback(resolved)
    local snapshot, node = resolved:redo()
    if not snapshot then return notify_error(node) end
    controller.validate(resolved)
    return snapshot, node
  end

  local function find_entity(session, selection)
    if not selection then return nil end
    return model.find(session:model(), selection.kind, selection.id)
  end

  local function generate_id(session, kind, name)
    local ids = require("roomplan.ids")
    local id, err = ids.generate(kind, name, ids.used_set(session:model(), session.reserved_ids))
    if id then
      session.reserved_ids = session.reserved_ids or {}
      session.reserved_ids[id] = true
    end
    return id, err
  end

  local function focus_after_form(session)
    vim.schedule(function()
      if session and not session.closed then
        -- The submit action redraws while the form mode is still active, and
        -- the form closes immediately afterwards. Redraw once more so the
        -- canvas header cannot keep a stale "ROOM CREATE/EDIT" label.
        controller.refresh(session)
        local workspace_ok, workspace = pcall(require, "roomplan.ui.workspace")
        if workspace_ok and workspace.is_visible(session) then workspace.focus(session, "canvas")
        else controller.focus_canvas(session) end
      end
    end)
  end

  local function open_structured_form(session, spec)
    local form = require("roomplan.ui.form")
    local handle, err = form.open(session, spec, {
      on_submit = function(draft, form_state)
        local action, build_err = spec.build(draft, form_state.context)
        if not action then return nil, build_err end
        local result, dispatch_err = controller.dispatch(session, action)
        if not result then return nil, dispatch_err end
        focus_after_form(session)
        return result
      end,
      on_cancel = function() focus_after_form(session) end,
    })
    if not handle then return notify_error(err) end
    return handle
  end

  local function cursor_world(session)
    local ok, canvas = pcall(require, "roomplan.render.canvas")
    if not ok or not canvas.logical_cursor then return nil end
    local first, second = canvas.logical_cursor(session)
    local column, row
    if type(first) == "table" then
      column, row = first.column or first.col or first[1], first.row or first[2]
    else
      column, row = first, second
    end
    if type(column) ~= "number" or type(row) ~= "number" then return nil end
    local x, y = require("roomplan.render.viewport").screen_to_world(ensure_viewport(session), column, row)
    return { util.round(x), util.round(y) }
  end

  function controller.add_room(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    local spec = require("roomplan.ui.forms").room.add(resolved, { cursor_mm = cursor_world(resolved) })
    return open_structured_form(resolved, spec)
  end

  function controller.add_furniture(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if #resolved:model().rooms == 0 then
      return notify_error(util.err("ROOM_REQUIRED", "add a room before placing furniture"))
    end
    local spec = require("roomplan.ui.forms").furniture.add(resolved, { cursor_mm = cursor_world(resolved) })
    return open_structured_form(resolved, spec)
  end

  function controller.add_door(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if #resolved:model().rooms == 0 then
      return notify_error(util.err("ROOM_REQUIRED", "add a room before placing a door"))
    end
    local spec = require("roomplan.ui.forms").door.add(resolved, { cursor_mm = cursor_world(resolved) })
    return open_structured_form(resolved, spec)
  end

  function controller.add_window(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if #resolved:model().rooms == 0 then
      return notify_error(util.err("ROOM_REQUIRED", "add a room before placing a window"))
    end
    local spec = require("roomplan.ui.forms").window.add(resolved, { cursor_mm = cursor_world(resolved) })
    return open_structured_form(resolved, spec)
  end

  function controller.add_outlet(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if #resolved:model().rooms == 0 then
      return notify_error(util.err("ROOM_REQUIRED", "add a room before placing an outlet"))
    end
    local spec = require("roomplan.ui.forms").outlet.add(resolved, { cursor_mm = cursor_world(resolved) })
    return open_structured_form(resolved, spec)
  end

  function controller.align_room(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if #resolved:model().rooms < 2 then
      return notify_error(util.err("ROOM_REFERENCE_REQUIRED", "add at least two rooms before aligning them"))
    end
    return open_structured_form(resolved, require("roomplan.ui.forms").alignment.new(resolved))
  end

  function controller.rotate_selected(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if not resolved.selection or resolved.selection.kind ~= "furniture" then
      return notify_error(util.err("FURNITURE_REQUIRED", "select furniture to rotate"))
    end
    local result, action_err = controller.dispatch(resolved, { type = "rotate_furniture", id = resolved.selection.id, delta_deg = 90 })
    if not result then return notify_error(action_err) end
    return result
  end

  function controller.edit_selected(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if not resolved.selection then return notify_error(util.err("SELECTION_REQUIRED", "select an object to edit")) end
    if resolved.selection.kind == "plan" then return controller.edit_plan(resolved) end
    local entity = find_entity(resolved, resolved.selection)
    if not entity then return notify_error(util.err("SELECTION_STALE", "selected object no longer exists")) end
    local forms = require("roomplan.ui.forms")
    local spec
    if resolved.selection.kind == "room" then spec = forms.room.edit(resolved, entity)
    elseif resolved.selection.kind == "furniture" then spec = forms.furniture.edit(resolved, entity)
    elseif resolved.selection.kind == "door" then spec = forms.door.edit(resolved, entity)
    elseif resolved.selection.kind == "window" then
      spec = forms.window.edit(resolved, entity, { cursor_mm = cursor_world(resolved) })
    elseif resolved.selection.kind == "outlet" then
      spec = forms.outlet.edit(resolved, entity, { cursor_mm = cursor_world(resolved) })
    elseif resolved.selection.kind == "template" then spec = forms.template.edit(resolved, entity) end
    if not spec then return notify_error(util.err("EDIT_UNSUPPORTED", "selected object cannot be edited here")) end
    return open_structured_form(resolved, spec)
  end

  function controller.edit_plan(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    return open_structured_form(resolved, require("roomplan.ui.forms").plan.edit(resolved))
  end

  function controller.edit_template(session, id)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    local template = model.find(resolved:model(), "template", id)
    if not template then return notify_error(util.err("NOT_FOUND", "custom template was not found")) end
    return open_structured_form(resolved, require("roomplan.ui.forms").template.edit(resolved, template))
  end

  function controller.duplicate_selected(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    local selection = resolved.selection
    local entity = find_entity(resolved, selection)
    if not entity then return notify_error(util.err("SELECTION_REQUIRED", "select an object to duplicate")) end
    local id, id_err
    local action
    if selection.kind == "room" then
      id, id_err = generate_id(resolved, "room", entity.name .. " copy")
      action = { type = "duplicate_room", id = entity.id, new_id = id }
    elseif selection.kind == "furniture" then
      id, id_err = generate_id(resolved, "furniture", entity.name .. " copy")
      action = { type = "duplicate_furniture", id = entity.id, new_id = id }
    elseif selection.kind == "door" then
      return open_structured_form(resolved, require("roomplan.ui.forms").door.duplicate(resolved, entity))
    elseif selection.kind == "window" then
      id, id_err = generate_id(resolved, "window", entity.id .. " copy")
      action = { type = "duplicate_window", id = entity.id, new_id = id }
    elseif selection.kind == "outlet" then
      id, id_err = generate_id(resolved, "outlet", entity.id .. " copy")
      action = { type = "duplicate_outlet", id = entity.id, new_id = id }
    elseif selection.kind == "template" then
      id, id_err = generate_id(resolved, "custom_template", entity.name .. " copy")
      action = { type = "duplicate_custom_template", id = entity.id, new_id = id }
    else
      return notify_error(util.err("DUPLICATE_UNSUPPORTED", "selected object cannot be duplicated"))
    end
    if not id then return notify_error(id_err) end
    local result, action_err = controller.dispatch(resolved, action)
    if not result then return notify_error(action_err) end
    return result
  end

  local function deletion_action(selection)
    if selection.kind == "room" then return { type = "delete_room_cascade", id = selection.id } end
    if selection.kind == "furniture" then return { type = "delete_furniture", id = selection.id } end
    if selection.kind == "door" then return { type = "delete_door", id = selection.id } end
    if selection.kind == "window" then return { type = "delete_window", id = selection.id } end
    if selection.kind == "outlet" then return { type = "delete_outlet", id = selection.id } end
    if selection.kind == "template" then return { type = "delete_custom_template", id = selection.id } end
  end

  function controller.delete_selected(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    local selection = resolved.selection
    local entity = find_entity(resolved, selection)
    local action = selection and deletion_action(selection)
    if not entity or not action then return notify_error(util.err("SELECTION_REQUIRED", "select a deletable object")) end
    local function remove()
      local result, action_err = controller.dispatch(resolved, action)
      if not result then return notify_error(action_err) end
      resolved.selection = nil
      controller.refresh(resolved)
      return result
    end
    if not config.get().ui.confirm_delete then return remove() end
    local summary = entity.name or entity.id
    if selection.kind == "room" then
      local dependencies = require("roomplan.actions").room_dependencies(resolved:model(), entity.id)
      summary = string.format("%s and %d dependent object(s)", summary, #dependencies.all)
    end
    local flow, flow_err = require("roomplan.ui.prompts").confirm(
      resolved, "delete", "Delete " .. summary .. "?", { "Delete", "Cancel" },
      function(choice) if choice == "Delete" then remove() end end
    )
    if not flow then return notify_error(flow_err) end
    return flow
  end

  function controller.add_menu(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if #(resolved:model().rooms or {}) == 0 then
      return controller.add_room(resolved)
    end
    return require("roomplan.ui.palette").open({
      session = resolved,
      title = "Add to plan",
      items = {
        { key = "r", label = "Room", description = "Create and place a rectangular or L-shaped room", callback = function() controller.add_room(resolved) end },
        { key = "d", label = "Door", description = "Place a hinged door on a room wall", callback = function() controller.add_door(resolved) end },
        { key = "w", label = "Window", description = "Place a window opening on a room wall", callback = function() controller.add_window(resolved) end },
        { key = "o", label = "Outlet", description = "Place a typed outlet on a room wall", callback = function() controller.add_outlet(resolved) end },
        { key = "f", label = "Furniture", description = "Place a catalogue or custom furniture footprint", callback = function() controller.add_furniture(resolved) end },
      },
    })
  end

  local function active_menu(session)
    if session.workspace then
      return require("roomplan.ui.help").open(session, {
        title = "Plan actions · " .. session:status_text(),
      })
    end
    local actions = {
      { label = "Open/focus canvas", method = "focus_canvas" },
      { label = "Add room", method = "add_room" },
      { label = "Align rooms", method = "align_room" },
      { label = "Add door", method = "add_door" },
      { label = "Add window", method = "add_window" },
      { label = "Add outlet", method = "add_outlet" },
      { label = "Add furniture", method = "add_furniture" },
      { label = "Edit selected object", method = "edit_selected" },
      { label = "Duplicate selected object", method = "duplicate_selected" },
      { label = "Delete selected object", method = "delete_selected" },
      { label = "Toggle Navigator", method = "objects" },
      { label = "Validate plan", method = "validate", argument = true },
      { label = "Fit plan to viewport", method = "fit" },
      { label = "Calibrate terminal aspect", method = "set_aspect" },
      { label = "Save", method = "save" },
      { label = "Reload", method = "reload" },
      { label = "Hide canvas", method = "hide" },
      { label = "Close session", method = "close" },
    }
    local items = {}
    for _, action in ipairs(actions) do
      local selected = action
      items[#items + 1] = {
        label = selected.label,
        callback = function() controller[selected.method](session, selected.argument) end,
      }
    end
    return require("roomplan.ui.palette").open({
      session = session,
      title = "Plan actions · " .. session:status_text(),
      items = items,
    })
  end

  function controller.menu(session)
    local resolved = is_session(session) and session or state.for_buffer()
    if resolved then return active_menu(resolved) end
    local sessions = state.list()
    if #sessions == 1 then return active_menu(sessions[1]) end
    if #sessions > 1 then
      local items = {}
      for _, candidate in ipairs(sessions) do
        local selected = candidate
        items[#items + 1] = {
          label = selected.source.path or selected.id,
          description = selected:status_text(),
          callback = function() active_menu(selected) end,
        }
      end
      return require("roomplan.ui.palette").open({ title = "Choose RoomPlan session", items = items })
    end
    return require("roomplan.ui.palette").open({
      title = "Start RoomPlan",
      items = {
        {
          key = "o", label = "Open current source", description = "Load an existing .roomplan.json or Norg plan block",
          callback = function() controller.open(nil, { bufnr = 0, interactive = true }) end,
        },
        {
          key = "i", label = "Initialize current source", description = "Create an empty plan without overwriting other content",
          callback = function() controller.init_source(nil, { bufnr = 0, interactive = true }) end,
        },
      },
    })
  end
end

return M
