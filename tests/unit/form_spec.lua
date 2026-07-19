local h = require("tests.harness")

local fields = require("roomplan.ui.form.fields")
local form = require("roomplan.ui.form")
local render = require("roomplan.ui.form.render")
local form_state = require("roomplan.ui.form.state")
local model = require("roomplan.model")

local function line_contains(lines, needle)
  for _, line in ipairs(lines) do if line:find(needle, 1, true) then return true end end
  return false
end

local function plan_session()
  local plan = h.truthy(model.new({ name = "Form test" }))
  plan.rooms[1] = model.new_room({
    id = "room-living", name = "Living", origin_mm = { 0, 0 }, size_mm = { 5000, 4000 },
  })
  plan.rooms[2] = model.new_room({
    id = "room-bedroom", name = "Bedroom", origin_mm = { 5000, 0 }, size_mm = { 3000, 3000 },
  })
  plan.furniture[1] = model.new_furniture({
    id = "furniture-sofa", room_id = "room-living", template_id = "builtin:sofa",
    name = "Sofa", category = "seating", position_mm = { 2500, 2000 }, size_mm = { 2100, 900, 850 },
  })
  plan.doors[1] = model.new_door({
    id = "door-living-east", room_id = "room-living", connects_to_room_id = "room-bedroom",
    side = "east", offset_mm = 1000, width_mm = 900, hinge = "start", opens_into = "connected",
  })
  plan.custom_templates[1] = model.new_custom_template({
    id = "custom:desk", name = "My desk", category = "work",
    default_size_mm = { 1600, 800, 740 },
  })
  local revision = 1
  local session = {
    id = "form-test-" .. tostring(math.random(1000000)),
    selection = { kind = "room", id = "room-living" },
    workflow = { generation = 0, kind = nil },
    closed = false,
  }
  function session:model() return plan end
  function session:current_model() return plan end
  function session:revision_id() return revision end
  function session:set_revision(value) revision = value end
  return session, plan
end

describe("structured forms", function()
  it("reduces and renders every field kind with conditional validation", function()
    local spec = {
      id = "field-kinds",
      title = "Field kinds",
      mode = "TEST",
      apply_label = "Use values",
      initial = {
        name = "Desk", width = 1000, count = 2, kind = "simple",
        room = "room-a", enabled = false, detail = "",
      },
      fields = {
        { key = "name", label = "Name", type = "text", required = true },
        { key = "width", label = "Width", type = "measurement" },
        { key = "count", label = "Count", type = "integer", min = 1, max = 4 },
        { key = "kind", label = "Kind", type = "enum", choices = { "simple", "detailed" } },
        {
          key = "room", label = "Room", type = "object_ref",
          choices = { { value = "room-a", label = "Room A" }, { value = "room-b", label = "Room B" } },
        },
        { key = "enabled", label = "Enabled", type = "toggle" },
        {
          key = "detail", label = "Detail", type = "text", required = true,
          visible = function(_, draft) return draft.kind == "detailed" end,
        },
        {
          key = "edit_shape", label = "Footprint", type = "action",
          action = "edit_shape", action_label = "Edit sections", value = "Edit sections on canvas…",
        },
        { key = "summary", label = "Summary", type = "readonly", value = function(_, draft) return draft.name .. " x" .. draft.count end },
      },
      preview = function(draft) return { lines = { "Width is " .. draft.width .. " mm" } } end,
    }
    local state = form_state.new(spec, {})
    h.eq(8, #form_state.visible_fields(state))
    h.eq(nil, state.draft.edit_shape)
    state = form_state.reduce(state, { type = "set_raw", key = "width", value = "2.1m" })
    h.eq(2100, state.draft.width)
    state = form_state.reduce(state, { type = "set_value", key = "kind", value = "detailed" })
    h.eq(9, #form_state.visible_fields(state))
    state = form_state.reduce(state, { type = "set_raw", key = "count", value = "9" })
    h.matches("at most", state.errors.count)
    local checked, valid = form_state.validate_all(state)
    h.falsy(valid)
    h.truthy(checked.errors.detail)
    h.truthy(checked.errors.count)
    local output = render.build(checked, { width = 70 })
    h.truthy(line_contains(output.lines, "Field kinds  [TEST]"))
    h.truthy(line_contains(output.lines, "Width"))
    h.truthy(line_contains(output.lines, "Summary"))
    h.truthy(line_contains(output.lines, "Edit sections on canvas"))
    h.truthy(line_contains(output.lines, "9"), "invalid raw input should remain visible")
    h.truthy(line_contains(output.lines, "Ctrl-s] Use values"))
    h.truthy(next(output.meta.error_rows) ~= nil)
  end)

  it("parses scalar types and labels object choices without Neovim", function()
    local measurement = { key = "size", label = "Size", type = "measurement", max = 5000 }
    h.eq(2100, h.truthy(fields.parse(measurement, "210cm", {}, {}, {})))
    local integer = { key = "angle", type = "integer", min = 1, max = 180 }
    h.eq(90, h.truthy(fields.parse(integer, "90", {}, {}, {})))
    h.falsy(fields.parse(integer, "90.5", {}, {}, {}))
    local reference = {
      key = "room", type = "object_ref",
      choices = { { id = "room-a", name = "Living" } },
    }
    h.eq("room-a", h.truthy(fields.parse(reference, "room-a", {}, {}, {})))
    h.eq("Living", fields.format(reference, "room-a", {}, {}, {}))
    local toggle = { key = "enabled", type = "toggle" }
    h.eq(true, h.truthy(fields.parse(toggle, "yes", {}, {}, {})))
  end)

  it("builds room, furniture, door, and alignment actions from detached drafts", function()
    local session, plan = plan_session()
    local forms = require("roomplan.ui.forms")

    local room_spec = forms.room.add(session, {
      name = "Office", color = "#98C379", width_mm = 2500, depth_mm = 2000, placement = "origin", force = true,
    })
    h.eq("ROOM CREATE", room_spec.mode)
    h.eq("roomplan_color", room_spec.fields[2].kind)
    local room_state, room_valid = form_state.validate_all(form_state.new(room_spec, room_spec.context))
    h.truthy(room_valid, vim.inspect(room_state.errors))
    local room_action = h.truthy(room_spec.build(room_state.draft, room_spec.context))
    h.eq("add_room", room_action.type)
    h.eq("room-office", room_action.room.id)
    h.eq("#98C379", room_action.room.color)
    h.eq({ 2500, 2000 }, room_action.room.footprint.parts[1].size_mm)
    h.eq(true, room_action.force)

    local furniture_spec = forms.furniture.add(session, {
      room_id = "room-living", template_id = "builtin:sofa", placement = "centre", color = "#C678DD",
    })
    h.eq("FURNITURE CREATE", furniture_spec.mode)
    h.eq("roomplan_color", furniture_spec.fields[4].kind)
    local furniture_state, furniture_valid = form_state.validate_all(form_state.new(furniture_spec, furniture_spec.context))
    h.truthy(furniture_valid, vim.inspect(furniture_state.errors))
    local furniture_action = h.truthy(furniture_spec.build(furniture_state.draft, furniture_spec.context))
    h.eq("add_furniture", furniture_action.type)
    h.eq({ 2500, 2000 }, furniture_action.furniture.position_mm)
    h.eq("builtin:sofa", furniture_action.furniture.template_id)
    h.eq("#C678DD", furniture_action.furniture.color)
    h.eq("side", furniture_spec.preview_layout)
    h.eq("#C678DD", furniture_state.preview.accent)
    h.truthy(furniture_state.preview.graphic)
    h.truthy(line_contains(furniture_state.preview.lines, "################"))
    h.eq(1, #plan.furniture, "building a form preview must not mutate the plan")

    local door_spec = forms.door.add(session, {
      room_id = "room-living", side = "east", width_mm = 900,
      placement = "exact", offset_mm = 1000, connects_to_room_id = "room-bedroom",
      opens_into = "connected",
    })
    h.eq("DOOR CREATE", door_spec.mode)
    local door_state, door_valid = form_state.validate_all(form_state.new(door_spec, door_spec.context))
    h.truthy(door_valid, vim.inspect(door_state.errors))
    local door_action = h.truthy(door_spec.build(door_state.draft, door_spec.context))
    h.eq("add_door", door_action.type)
    h.eq("room-bedroom", door_action.door.connects_to_room_id)
    h.eq(1000, door_action.door.offset_mm)

    local alignment_spec = forms.alignment.new(session, {
      moving_room_id = "room-bedroom", reference_room_id = "room-living", operation = "place_north", gap_mm = 100,
      force = true,
    })
    h.eq("ROOM ALIGN", alignment_spec.mode)
    local alignment_state, alignment_valid = form_state.validate_all(form_state.new(alignment_spec, alignment_spec.context))
    h.truthy(alignment_valid, vim.inspect(alignment_state.errors))
    local alignment_action = h.truthy(alignment_spec.build(alignment_state.draft, alignment_spec.context))
    h.eq("align_room", alignment_action.type)
    h.eq("room-bedroom", alignment_action.id)
    h.eq(100, alignment_action.gap_mm)
    h.eq(true, alignment_action.force)
  end)

  it("provides full-field atomic edit specs for plans, rooms, furniture, doors, and templates", function()
    local session, plan = plan_session()
    local forms = require("roomplan.ui.forms")

    local plan_spec = forms.plan.edit(session)
    h.eq("PLAN EDIT", plan_spec.mode)
    local plan_state, plan_valid = form_state.validate_all(form_state.new(plan_spec, plan_spec.context))
    h.truthy(plan_valid, vim.inspect(plan_state.errors))
    plan_state = form_state.reduce(plan_state, { type = "set_raw", key = "name", value = "Renovation" })
    local plan_action = h.truthy(plan_spec.build(plan_state.draft, plan_spec.context))
    h.eq("edit_plan", plan_action.type)
    h.eq("Renovation", plan_action.metadata.name)
    h.eq(100, plan_action.settings.grid_mm)
    h.eq(nil, plan_action.settings.default_wall_thickness_mm)

    local room_spec = forms.room.edit(session, plan.rooms[1])
    h.eq("ROOM EDIT", room_spec.mode)
    local room_state, room_valid = form_state.validate_all(form_state.new(room_spec, room_spec.context))
    h.truthy(room_valid, vim.inspect(room_state.errors))
    room_state = form_state.reduce(room_state, { type = "set_raw", key = "name", value = "Living room" })
    room_state = form_state.reduce(room_state, { type = "set_raw", key = "width_mm", value = "5.2m" })
    room_state = form_state.reduce(room_state, { type = "set_value", key = "color", value = "#56B6C2" })
    local room_action = h.truthy(room_spec.build(room_state.draft, room_spec.context))
    h.eq("edit_room", room_action.type)
    h.eq("Living room", room_action.patch.name)
    h.eq("#56B6C2", room_action.patch.color)
    h.eq({ 5200, 4000 }, room_action.patch.footprint.parts[1].size_mm)

    local furniture_spec = forms.furniture.edit(session, plan.furniture[1])
    h.eq("FURNITURE EDIT", furniture_spec.mode)
    local furniture_state, furniture_valid = form_state.validate_all(form_state.new(furniture_spec, furniture_spec.context))
    h.truthy(furniture_valid, vim.inspect(furniture_state.errors))
    furniture_state = form_state.reduce(furniture_state, { type = "set_value", key = "template_id", value = "builtin:desk" })
    furniture_state = form_state.reduce(furniture_state, { type = "set_value", key = "color", value = "#E06C75" })
    -- Changing template metadata must retain explicit dimensions while editing.
    h.eq(2100, furniture_state.draft.width_mm)
    local furniture_action = h.truthy(furniture_spec.build(furniture_state.draft, furniture_spec.context))
    h.eq("edit_furniture", furniture_action.type)
    h.eq("builtin:desk", furniture_action.patch.template_id)
    h.eq("#E06C75", furniture_action.patch.color)
    h.eq({ 2100, 900 }, furniture_action.patch.footprint.parts[1].size_mm)
    h.eq({ 2100, 900 }, furniture_action.patch.anchor2_mm)
    h.eq(850, furniture_action.patch.height_mm)

    local door_spec = forms.door.edit(session, plan.doors[1])
    h.eq("DOOR EDIT", door_spec.mode)
    local door_state, door_valid = form_state.validate_all(form_state.new(door_spec, door_spec.context))
    h.truthy(door_valid, vim.inspect(door_state.errors))
    door_state = form_state.reduce(door_state, { type = "set_value", key = "hinge", value = "end" })
    local door_action = h.truthy(door_spec.build(door_state.draft, door_spec.context))
    h.eq("edit_door", door_action.type)
    h.eq("end", door_action.patch.hinge)
    h.eq(true, door_action.exact)

    local template_spec = forms.template.edit(session, plan.custom_templates[1])
    h.eq("TEMPLATE EDIT", template_spec.mode)
    local template_state, template_valid = form_state.validate_all(form_state.new(template_spec, template_spec.context))
    h.truthy(template_valid, vim.inspect(template_state.errors))
    template_state = form_state.reduce(template_state, { type = "set_raw", key = "width_mm", value = "1.8m" })
    local template_action = h.truthy(template_spec.build(template_state.draft, template_spec.context))
    h.eq("edit_custom_template", template_action.type)
    h.eq({ 1800, 800 }, template_action.patch.default_footprint.parts[1].size_mm)
    h.eq({ 1800, 800 }, template_action.patch.default_anchor2_mm)
    h.eq(740, template_action.patch.default_height_mm)
  end)

  it("opens a complete float, anchors editors, applies, and cancels", function()
    local session = plan_session()
    local submitted, cancelled, opened_action
    local spec = {
      id = "engine-test",
      title = "Structured editor",
      mode = "ADD",
      apply_label = "Create",
      initial = { name = "Old", size = 1000, choice = "one", enabled = false },
      fields = {
        { key = "name", label = "Name", type = "text", required = true },
        { key = "size", label = "Size", type = "measurement" },
        { key = "choice", label = "Choice", type = "enum", choices = { "one", "two" } },
        { key = "enabled", label = "Enabled", type = "toggle" },
        { key = "shape", label = "Footprint", type = "action", action = "edit_shape", value = "Edit sections on canvas…" },
        { key = "summary", label = "Summary", type = "readonly", value = function(_, draft) return draft.name end },
      },
    }
    local handle = h.truthy(form.open(session, spec, {
      on_submit = function(draft) submitted = draft; return { committed = true } end,
      on_cancel = function(reason) cancelled = reason end,
      on_action = function(action) opened_action = action; return true end,
    }))
    h.truthy(vim.api.nvim_win_is_valid(handle.winid))
    local lines = vim.api.nvim_buf_get_lines(handle.bufnr, 0, -1, false)
    h.truthy(line_contains(lines, "Structured editor  [ADD]"))
    h.truthy(line_contains(lines, "Name"))
    h.truthy(line_contains(lines, "Size"))
    h.truthy(line_contains(lines, "Choice"))
    h.truthy(line_contains(lines, "Edit sections on canvas"))
    h.truthy(line_contains(lines, "Summary"))
    local help_mapping = vim.api.nvim_buf_call(handle.bufnr, function()
      return vim.fn.maparg("?", "n", false, true)
    end)
    h.eq("Open RoomPlan form actions", help_mapping.desc)

    local original_input = vim.ui.input
    local pending, input_options
    vim.ui.input = function(opts, callback) input_options, pending = opts, callback end
    h.truthy(form.activate(handle, "name"))
    h.truthy(form.edit(handle))
    h.eq("window", input_options.scope)
    h.truthy(form.move(handle, 1))
    pending("Anchored name")
    vim.ui.input = original_input
    h.eq("Anchored name", handle.state.draft.name)
    -- The delayed editor remains anchored to Name even though focus moved in
    -- the meantime; it must never overwrite the newly active Size field.
    h.eq("name", handle.state.active_key)

    local original_select = vim.ui.select
    local pending_select, pending_choices, select_options
    vim.ui.select = function(items, opts, callback)
      pending_choices, select_options, pending_select = items, opts, callback
    end
    h.truthy(form.activate(handle, "choice"))
    h.truthy(form.edit(handle))
    h.eq("roomplan_form_choice", select_options.kind)
    h.truthy(form.move(handle, 1))
    pending_select(pending_choices[2])
    vim.ui.select = original_select
    h.eq("two", handle.state.draft.choice)
    h.eq("choice", handle.state.active_key)
    h.truthy(form.activate(handle, "shape"))
    h.truthy(form.edit(handle))
    h.eq("edit_shape", opened_action)
    h.eq(nil, handle.state.draft.shape)
    h.eq(true, h.truthy(form.set_value(handle, "enabled", true, { raw = false, trusted = true })))
    local applied = h.truthy(form.apply(handle))
    h.eq(true, applied.committed)
    h.eq("Anchored name", submitted.name)
    h.falsy(vim.api.nvim_buf_is_valid(handle.bufnr))
    h.eq(nil, cancelled)

    local second = h.truthy(form.open(session, spec, { on_cancel = function(reason) cancelled = reason end }))
    h.truthy(form.cancel(second, "test cancel"))
    h.eq("test cancel", cancelled)
  end)

  it("shows side previews only when they fit", function()
    local session, plan = plan_session()
    local spec = require("roomplan.ui.forms").room.edit(session, plan.rooms[1])
    local original_columns = vim.o.columns
    vim.o.columns = 100
    local handle = h.truthy(form.open(session, spec, {}))
    h.truthy(handle.preview_winid and vim.api.nvim_win_is_valid(handle.preview_winid))
    h.falsy(line_contains(handle.output.lines, "Room preview"))
    h.truthy(line_contains(handle.output.lines, "Ctrl-s] Apply room changes"))

    vim.o.columns = 80
    form.render(handle)
    h.eq(nil, handle.preview_winid)
    h.truthy(line_contains(handle.output.lines, "Room preview"))
    h.truthy(line_contains(handle.output.lines, "Ctrl-s] Apply room changes"))
    h.truthy(form.cancel(handle, "preview test"))
    vim.o.columns = original_columns
  end)

  it("shows a live furniture silhouette beside the form with a compact fallback", function()
    local session = plan_session()
    local spec = require("roomplan.ui.forms").furniture.add(session, {
      room_id = "room-living", template_id = "builtin:sofa", placement = "centre", color = "#C678DD",
    })
    local original_columns = vim.o.columns
    vim.o.columns = 100
    local handle = h.truthy(form.open(session, spec, {}))
    h.truthy(handle.preview_winid and vim.api.nvim_win_is_valid(handle.preview_winid))
    local side_lines = vim.api.nvim_buf_get_lines(handle.preview_bufnr, 0, -1, false)
    h.truthy(line_contains(side_lines, "Furniture preview"))
    h.truthy(line_contains(side_lines, "################"))
    h.falsy(line_contains(handle.output.lines, "Furniture preview"))

    h.eq(90, h.truthy(form.set_value(handle, "rotation_deg", 90, { raw = false })))
    local rotated_lines = vim.api.nvim_buf_get_lines(handle.preview_bufnr, 0, -1, false)
    h.falsy(vim.deep_equal(side_lines, rotated_lines), "rotation should visibly update the silhouette")

    vim.o.columns = 80
    form.render(handle)
    h.eq(nil, handle.preview_winid)
    h.truthy(line_contains(handle.output.lines, "Furniture preview"))
    h.truthy(line_contains(handle.output.lines, "##"))
    h.truthy(form.cancel(handle, "preview test"))
    vim.o.columns = original_columns
  end)

  it("rejects late scalar callbacks and Apply after the model revision changes", function()
    local session = plan_session()
    local spec = {
      id = "revision-test", title = "Revision guard", initial = { name = "Original" },
      fields = { { key = "name", label = "Name", type = "text" } },
    }
    local handle = h.truthy(form.open(session, spec, {}))
    local original_input = vim.ui.input
    local pending
    vim.ui.input = function(_, callback) pending = callback end
    h.truthy(form.edit(handle))
    session:set_revision(2)
    pending("Late value")
    vim.ui.input = original_input
    h.eq("Original", handle.state.draft.name)
    h.truthy(handle.state.stale)
    local result, err = form.apply(handle)
    h.eq(nil, result)
    h.eq("FORM_REVISION_STALE", err.code)
    h.truthy(form.cancel(handle, "stale"))
  end)
end)
