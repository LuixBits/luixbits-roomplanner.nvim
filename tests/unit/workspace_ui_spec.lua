local workspace_state = require("roomplan.ui.workspace_state")
local presenter = require("roomplan.ui.presenter")
local registry = require("roomplan.ui.action_registry")
local objects_panel = require("roomplan.ui.panels.objects")
local action_bar = require("roomplan.ui.panels.action_bar")

local function fixture()
  return {
    format = "roomplan.nvim",
    schema_version = 1,
    units = "mm",
    metadata = { name = "Test flat", notes = "" },
    settings = { grid_mm = 100, fine_step_mm = 10 },
    rooms = {
      { id = "room-living", name = "Living", origin_mm = { 0, 0 }, size_mm = { 5000, 4000 } },
      { id = "room-bed", name = "Bedroom", origin_mm = { 5000, 0 }, size_mm = { 3000, 3000 } },
    },
    doors = {
      {
        id = "door-shared", room_id = "room-living", connects_to_room_id = "room-bed",
        side = "east", offset_mm = 500, width_mm = 900, hinge = "start", opens_into = "room-bed",
        open_angle_deg = 90,
      },
    },
    furniture = {
      {
        id = "sofa-1", room_id = "room-living", name = "Sofa", template_id = "sofa",
        center_mm = { 1500, 1000 }, size_mm = { 2100, 900, 800 }, rotation_deg = 0,
      },
    },
    custom_templates = {},
  }
end

describe("workspace UI", function()
  it("selects responsive layouts at every boundary and preserves the canvas budget", function()
    local wide = workspace_state.calculate_layout(120, 40)
    assert_equal("wide", wide.kind)
    assert_true(wide.panes.canvas.width >= 55)
    assert_equal(120, wide.panes.left.width + wide.panes.canvas.width + wide.panes.properties.width + 2)

    local medium = workspace_state.calculate_layout(119, 35)
    assert_equal("medium", medium.kind)
    assert_true(medium.panes.canvas.width >= 55)
    assert_equal(false, medium.panes.properties.persistent)

    assert_equal("medium", workspace_state.calculate_layout(90, 24).kind)
    assert_equal("compact", workspace_state.calculate_layout(89, 24).kind)
    assert_equal("compact", workspace_state.calculate_layout(160, 21).kind)
    assert_equal("compact", workspace_state.calculate_layout(160, 13, {
      compact_min_rows = 5, min_canvas_height = 12, footer_height = 2,
    }).kind)
    assert_true(workspace_state.calculate_layout(80, 24).compact_reason:match("width") ~= nil)
  end)

  it("reduces focus, drawers, expansion and escape without mutating prior state", function()
    local first = workspace_state.initial()
    first = workspace_state.reduce(first, { type = "layout", kind = "compact" })
    local drawer = workspace_state.reduce(first, { type = "focus", pane = "objects" })
    assert_equal("canvas", first.focused_pane)
    assert_equal("objects", drawer.focused_pane)
    assert_equal("objects", drawer.drawer)

    local expanded = workspace_state.reduce(drawer, { type = "toggle_expanded", id = "room-living" })
    assert_equal(nil, drawer.expanded["room-living"])
    assert_equal(false, expanded.expanded["room-living"])
    local escaped = workspace_state.reduce(expanded, { type = "escape" })
    assert_equal(nil, escaped.drawer)
    assert_equal("canvas", escaped.focused_pane)

    local cycled = workspace_state.reduce(escaped, { type = "cycle_focus", direction = -1 })
    assert_equal("issues", cycled.focused_pane)
  end)

  it("presents a hierarchical object tree with selection and diagnostics", function()
    local model = fixture()
    local view = presenter.objects(model, {
      selection = { kind = "furniture", id = "sofa-1" },
      diagnostics = {
        {
          severity = "warning", code = "DOOR_SWING_COLLISION", message = "Sofa intersects swing",
          object = { kind = "furniture", id = "sofa-1" },
        },
      },
    })
    assert_equal("2 rooms · 1 doors · 1 items", view.summary)
    assert_equal("plan", view.rows[1].kind)
    assert_equal("room", view.rows[2].kind)
    assert_equal("door", view.rows[3].kind)
    assert_equal("furniture", view.rows[4].kind)
    assert_equal(true, view.rows[4].selected)
    assert_equal(1, view.rows[4].counts.warnings)
    assert_equal("room", view.rows[5].kind)

    local collapsed = presenter.objects(model, { expanded = { ["room-living"] = false } })
    assert_equal(3, #collapsed.rows)
    local filtered = presenter.objects(model, { filter = "sofa" })
    assert_equal(3, #filtered.rows)
    assert_equal("room-living", filtered.rows[2].id)
    assert_equal("sofa-1", filtered.rows[3].id)

    model.custom_templates[1] = {
      id = "custom:desk", name = "My desk", category = "work",
      default_size_mm = { 1600, 800, 740 },
    }
    local with_template = presenter.objects(model, { selection = { kind = "template", id = "custom:desk" } })
    assert_equal("template", with_template.rows[#with_template.rows].kind)
    assert_equal(true, with_template.rows[#with_template.rows].selected)
    assert_true(with_template.summary:match("1 templates") ~= nil)
  end)

  it("groups human-readable properties instead of exposing raw JSON", function()
    local session = {
      model = fixture(),
      selection = { kind = "room", id = "room-living" },
      validation = {},
      source = { adapter = "json", path = "/tmp/test.roomplan.json" },
    }
    local view = presenter.properties(session)
    assert_equal("Living", view.title)
    assert_equal("room", view.kind)
    assert_equal("Position", view.groups[2].title)
    assert_equal("0 mm", view.groups[2].fields[1].value)
    assert_equal("5000 mm (5 m)", view.groups[3].fields[1].value)
    assert_equal("20.00 m²", view.groups[3].fields[3].value)
  end)

  it("reports contextual actions, disabled reasons, and explicit interaction modes", function()
    local empty = { model = { rooms = {} }, mode = "NAV", focus = "canvas", snap_enabled = true }
    local actions = registry.contextual(empty)
    assert_equal("add_room", actions[1].id)
    assert_equal(true, actions[1].enabled)
    assert_equal(false, actions[2].enabled)
    assert_equal("Add a room first", actions[2].reason)

    local room = {
      model = fixture(), selection = { kind = "room", id = "room-living" }, mode = "NAV",
      focus = "canvas", snap_enabled = true,
    }
    local room_actions = registry.contextual(room)
    assert_equal("edit", room_actions[1].id)
    assert_equal(true, registry.get("align", room).enabled)
    assert_equal(false, registry.get("rotate", room).enabled)
    assert_equal("Select furniture first", registry.get("rotate", room).reason)

    local form = vim.tbl_extend("force", room, { mode = "ROOM_CREATE", form = { kind = "room" } })
    local form_actions = registry.contextual(form)
    assert_equal("previous_field", form_actions[1].id)
    assert_equal("apply", form_actions[4].id)
    assert_equal("ROOM CREATE", registry.mode_label(form))
    assert_true(registry.mode_label(vim.tbl_extend("force", room, { mode = "MOVE" })):match("h/j/k/l") ~= nil)

    local plan = vim.tbl_extend("force", room, { selection = { kind = "plan" } })
    assert_equal("edit", registry.contextual(plan)[1].id)
    assert_equal("edit_plan", registry.get("edit", plan).handler)
  end)

  it("uses the same configured keys in mappings and contextual hints", function()
    local resolver = require("roomplan.ui.mappings")
    local options = {
      enabled = true,
      mappings = { add = "<leader>a", form_apply = "<leader>s", form_cancel = false },
    }
    assert_equal("<leader>a", resolver.resolve("a", "add", options))
    assert_equal("<leader>s", registry.get("apply", { keymaps = options }).key)
    assert_equal(registry.get("cancel", { keymaps = options }).key, nil)
    assert_equal(resolver.resolve("a", "add", { enabled = false, mappings = {} }), nil)
  end)

  it("opens a native action palette without numbered prompt chains", function()
    local palette = require("roomplan.ui.palette")
    local chosen
    local handle = assert(palette.open({
      title = "Add to plan",
      items = {
        { key = "r", label = "Room", description = "Create a room", callback = function() chosen = "room" end },
        { key = "d", label = "Door", description = "Create a door" },
      },
    }))
    local lines = vim.api.nvim_buf_get_lines(handle.bufnr, 0, -1, false)
    assert_true(table.concat(lines, "\n"):match("%[r%] Room") ~= nil)
    assert_true(table.concat(lines, "\n"):match("1%.") == nil)
    assert_true(palette.choose(handle, handle.row_map[4]))
    assert_true(vim.wait(200, function() return chosen == "room" end, 10))
    assert_equal(false, vim.api.nvim_buf_is_valid(handle.bufnr))
  end)

  it("renders stable pane rows and a width-bounded persistent action bar", function()
    local view = presenter.objects(fixture(), { selection = { kind = "room", id = "room-living" } })
    local panel = objects_panel.render(view, 32, 12)
    assert_equal(12, #panel.lines)
    assert_equal("room", panel.row_map[6].kind)
    assert_true(vim.fn.strdisplaywidth(panel.lines[6]) <= 32)

    local ctx = {
      model = fixture(), selection = { kind = "furniture", id = "sofa-1" },
      mode = "FURNITURE_EDIT", form = { kind = "furniture" }, focus = "properties",
      dirty = true, snap_enabled = true,
    }
    local bar = action_bar.render(ctx, 72, { height = 2 })
    assert_equal(2, #bar.lines)
    assert_true(bar.lines[1]:match("Apply") ~= nil)
    assert_true(bar.lines[2]:match("FURNITURE EDIT") ~= nil)
    assert_true(bar.lines[2]:match("DIRTY") ~= nil)
    assert_true(vim.fn.strdisplaywidth(bar.lines[1]) <= 72)
  end)

  it("mounts around but never assumes ownership of the canonical canvas", function()
    local workspace = require("roomplan.ui.workspace")
    local canvas = vim.api.nvim_create_buf(false, true)
    vim.bo[canvas].buftype = "nofile"
    vim.api.nvim_set_current_buf(canvas)
    local canvas_window = vim.api.nvim_get_current_win()
    local model = fixture()
    local session = {
      id = "workspace-shell-test",
      canvas = { bufnr = canvas, winid = canvas_window },
      source = { adapter = "json", path = "/tmp/workspace.roomplan.json" },
      selection = nil,
      validation = {},
      mode = "NAV",
      snap_enabled = true,
      workflow = { generation = 0 },
      current_model = function() return model end,
      model_dirty = function() return false end,
      status_text = function() return "[SAVED]" end,
      history = { can_undo = function() return false end, can_redo = function() return false end },
    }
    local shell = workspace.mount(session, {
      layout = "wide", columns = 120, lines = 40, cycle_tabs = false,
    })
    assert_equal(true, shell.owns_footer)
    assert_equal("wide", shell.layout.kind)
    assert_equal(false, workspace.owns_window(session, canvas_window))
    assert_true(vim.api.nvim_win_is_valid(canvas_window))
    assert_true(vim.api.nvim_win_is_valid(shell.windows.left))
    assert_true(vim.api.nvim_win_is_valid(shell.windows.properties))

    assert_true(workspace.focus(session, "properties"))
    workspace.reflow(session, true)
    assert_equal(shell.windows.properties, vim.api.nvim_get_current_win())
    assert_equal(shell.buffers.objects, vim.api.nvim_win_get_buf(shell.windows.left))
    workspace.focus(session, "canvas")

    -- Native window commands and mouse focus do not pass through
    -- workspace.focus(), but the persistent pane state must still follow them.
    vim.api.nvim_set_current_win(shell.windows.left)
    assert_true(vim.wait(100, function() return shell.state.focused_pane == "objects" end, 5))
    local room_row
    for line, row in pairs(shell.rendered.objects.row_map) do
      if row.kind == "room" then room_row = line; break end
    end
    assert_true(room_row ~= nil)
    vim.api.nvim_win_set_cursor(shell.windows.left, { room_row, 0 })
    assert_equal({ kind = "room", id = "room-living" }, workspace.select_focused(session))

    -- Contextual modes entered from a side pane must transfer control to the
    -- canvas, where their directional mappings actually operate.
    assert_true(workspace.focus(session, "properties"))
    assert_equal("MOVE", workspace.invoke(session, "move"))
    assert_equal("MOVE", session.mode)
    assert_equal("MOVE", shell.state.interaction)
    assert_equal(canvas_window, vim.api.nvim_get_current_win())
    require("roomplan.controller").escape(session)
    assert_equal("NAV", shell.state.interaction)

    -- A user may close a split directly with :close. A same-size reflow still
    -- has to recreate required panes instead of treating the layout as valid.
    local closed_left = shell.windows.left
    vim.api.nvim_win_close(closed_left, true)
    workspace.reflow(session)
    assert_true(vim.api.nvim_win_is_valid(shell.windows.left))
    assert_true(shell.windows.left ~= closed_left)

    shell.opts.layout = "compact"
    shell.opts.columns = 80
    shell.opts.lines = 24
    workspace.reflow(session, true)
    assert_equal("compact", shell.layout.kind)
    assert_true(workspace.focus(session, "objects"))
    assert_true(vim.api.nvim_win_is_valid(shell.windows.drawer))
    workspace.focus(session, "canvas")
    assert_equal(nil, shell.windows.drawer)

    assert_true(workspace.close(session))
    assert_true(vim.api.nvim_win_is_valid(canvas_window))
    assert_true(vim.api.nvim_buf_is_valid(canvas))
    vim.api.nvim_buf_delete(canvas, { force = true })
  end)
end)
