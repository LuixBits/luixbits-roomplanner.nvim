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
      { id = "room-living", name = "Living", origin_mm = { 0, 0 }, size_mm = { 5000, 4000 }, color = "#61AFEF" },
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
    assert_equal(120, wide.panes.left.width + wide.panes.canvas.width + 1)
    assert_equal(false, wide.panes.properties.visible)

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

    local forced_wide = workspace_state.calculate_layout(40, 12, {
      layout = "wide", min_canvas_width = 55,
    })
    assert_equal(false, forced_wide.panes.left.persistent)
    assert_equal(false, forced_wide.panes.properties.persistent)
    assert_equal(40, forced_wide.panes.canvas.width)
    local forced_medium = workspace_state.calculate_layout(40, 12, {
      layout = "medium", min_canvas_width = 55,
    })
    assert_equal(false, forced_medium.panes.left.persistent)
    assert_equal(40, forced_medium.panes.canvas.width)
  end)

  it("gives hidden side panes back to the canvas without changing the layout kind", function()
    local state = workspace_state.initial()
    state = workspace_state.reduce(state, { type = "layout", kind = "wide" })
    local navigator = workspace_state.calculate_layout(120, 40, nil, state)
    assert_equal("wide", navigator.kind)
    assert_equal(true, navigator.panes.left.visible)
    assert_equal(false, navigator.panes.properties.visible)
    assert_equal(0, navigator.panes.properties.width)
    assert_equal(120, navigator.panes.left.width + navigator.panes.canvas.width + 1)

    local canvas_only = workspace_state.calculate_layout(120, 40, nil, {
      navigator = false, details = false,
    })
    assert_equal(120, canvas_only.panes.canvas.width)
    assert_equal(0, canvas_only.panes.left.width)
    assert_equal(0, canvas_only.panes.properties.width)

    local details = workspace_state.calculate_layout(119, 35, nil, {
      navigator = false, details = true,
    })
    assert_equal("medium", details.kind)
    assert_equal(false, details.panes.left.visible)
    assert_equal(true, details.panes.properties.visible)
    assert_equal(119, details.panes.properties.width + details.panes.canvas.width + 1)

    -- Calls without transient state use the same clean startup defaults as a
    -- mounted workspace: Navigator visible, Details hidden.
    local default_wide = workspace_state.calculate_layout(120, 40)
    assert_equal(true, default_wide.panes.left.visible)
    assert_equal(false, default_wide.panes.properties.visible)
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

  it("maintains adaptive pane visibility and cycles only reachable panes", function()
    local initial = workspace_state.initial()
    assert_equal(true, initial.visibility.navigator)
    assert_equal(false, initial.visibility.details)
    assert_equal(1, workspace_state.defaults().footer_height)

    local wide = workspace_state.reduce(initial, { type = "layout", kind = "wide" })
    assert_equal({ "objects", "issues", "canvas" }, workspace_state.focus_order(wide))

    local details = workspace_state.reduce(wide, { type = "focus", pane = "properties" })
    assert_equal(true, details.visibility.navigator)
    assert_equal(true, details.visibility.details)
    local hidden = workspace_state.reduce(details, { type = "toggle_pane", pane = "details" })
    assert_equal(false, hidden.visibility.details)
    assert_equal("canvas", hidden.focused_pane)
    assert_equal(true, details.visibility.details)

    local canvas_only = workspace_state.reduce(hidden, { type = "toggle_pane", pane = "navigator" })
    assert_equal({ "canvas" }, workspace_state.focus_order(canvas_only))
    assert_equal("canvas", workspace_state.next_focus(canvas_only, 1))

    local medium = workspace_state.reduce(details, { type = "layout", kind = "medium" })
    assert_equal(true, medium.visibility.navigator)
    assert_equal(true, medium.visibility.details)
    assert_equal("details", medium.active_side)
    local canvas_focused = workspace_state.reduce(medium, { type = "focus", pane = "canvas" })
    local medium_layout = workspace_state.calculate_layout(119, 35, nil, canvas_focused)
    assert_equal(true, medium_layout.panes.properties.visible)
    assert_equal(false, medium_layout.panes.left.visible)
    local navigator = workspace_state.reduce(medium, {
      type = "set_pane_visible", pane = "details", visible = false,
    })
    assert_equal(true, navigator.visibility.navigator)
    assert_equal(false, navigator.visibility.details)

    local compact = workspace_state.reduce(navigator, { type = "layout", kind = "compact" })
    local drawer = workspace_state.reduce(compact, { type = "toggle_pane", pane = "details" })
    assert_equal("properties", drawer.drawer)
    assert_equal("properties", drawer.focused_pane)
    assert_equal(navigator.visibility.navigator, drawer.visibility.navigator)
    assert_equal(navigator.visibility.details, drawer.visibility.details)
  end)

  it("keeps accordion expansion state independent and immutable", function()
    local initial = workspace_state.initial()
    assert_equal(true, initial.collapsed_sections.advanced)
    assert_equal(true, initial.collapsed_sections.source)

    local toggled = workspace_state.reduce(initial, { type = "toggle_section", key = "advanced" })
    assert_equal(false, toggled.collapsed_sections.advanced)
    assert_equal(true, initial.collapsed_sections.advanced)

    local collapsed = workspace_state.reduce(toggled, {
      type = "set_section", key = "geometry", expanded = false,
    })
    assert_equal(true, collapsed.collapsed_sections.geometry)
    local expanded = workspace_state.reduce(collapsed, {
      type = "set_section", key = "geometry", expanded = true,
    })
    assert_equal(false, expanded.collapsed_sections.geometry)
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
    assert_equal("2 rooms · 1 doors · 0 windows · 0 outlets · 1 items", view.summary)
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

    local reference = { kind = "furniture", id = "sofa-1" }
    local marked = { [require("roomplan.selection_set").key(reference)] = reference }
    local marked_view = presenter.objects(model, { marked = marked })
    assert_equal(1, marked_view.marked_count)
    assert_equal(true, marked_view.rows[4].marked)
    local marked_panel = objects_panel.render(marked_view, 48, 10)
    assert_true(marked_panel.lines[1]:find("1 marked", 1, true) ~= nil)
    assert_true(marked_panel.lines[5]:find("●", 1, true) ~= nil)

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
    assert_equal("Geometry", view.groups[1].title)
    assert_equal("0 mm", view.groups[1].fields[1].value)
    assert_equal("5 m", view.groups[1].fields[3].value)
    assert_equal("20.00 m²", view.groups[1].fields[5].value)
    assert_equal("Appearance", view.groups[2].title)
    assert_equal("Blue #61AFEF", view.groups[2].fields[1].value)
    assert_equal("1.234 m", presenter.compact_mm(1234))

    local ctx = presenter.context({
      model = fixture(), selection = nil, viewport = { mm_per_column = 50 },
      canvas = { handle = { opts = { mm_per_column = 100 } } },
    }, { focused_pane = "properties" })
    assert_equal("plan", ctx.selection.kind)
    assert_equal("edit_plan", registry.get("edit", ctx).handler)
    assert_equal(2, ctx.zoom)
  end)

  it("builds concise selection and interaction breadcrumbs from presenter data", function()
    local plan = fixture()
    plan.schema_version = 4
    plan.windows = {}
    plan.outlets = {
      {
        id = "outlet-floor", room_id = "room-living", placement = "floor",
        position_mm = { 500, 500 }, outlet_type = "power", slots = 2,
      },
    }
    plan.furniture[1].category = "seating"

    local outlet = presenter.context({
      model = plan,
      selection = { kind = "outlet", id = "outlet-floor" },
      mode = "NAV",
    })
    assert_equal("Living › Floor outlet · Power · 2 slots", outlet.breadcrumb.text)
    assert_equal("RoomPlanWorkspaceOutlet", outlet.breadcrumb.hl_group)

    assert_equal("Living › Door · East → Bedroom", presenter.context({
      model = plan,
      selection = { kind = "door", id = "door-shared" },
      mode = "NAV",
    }).breadcrumb.text)
    plan.windows[1] = {
      id = "window-north", room_id = "room-living", side = "north",
      connects_to_room_id = nil, offset_mm = 500, width_mm = 1200,
    }
    assert_equal("Living › Window · North → outside", presenter.context({
      model = plan,
      selection = { kind = "window", id = "window-north" },
      mode = "NAV",
    }).breadcrumb.text)
    plan.custom_templates[1] = {
      id = "custom:desk", name = "My desk", category = "work",
      default_size_mm = { 1600, 800, 740 },
    }
    assert_equal("Project template › My desk · work", presenter.context({
      model = plan,
      selection = { kind = "template", id = "custom:desk" },
      mode = "NAV",
    }).breadcrumb.text)

    local furniture = presenter.context({
      model = plan,
      selection = { kind = "furniture", id = "sofa-1" },
      mode = "MOVE",
      move_feedback = "right 100 mm",
    })
    furniture.snap_summary = "X → Bedroom west wall"
    furniture.breadcrumb = presenter.breadcrumb(plan, furniture)
    assert_equal(
      "Living › Sofa · seating · MOVE · right 100 mm · snap: X → Bedroom west wall",
      furniture.breadcrumb.text
    )

    local resize = presenter.breadcrumb(plan, {
      selection = { kind = "room", id = "room-living" },
      mode = "RESIZE",
      shape_section_index = 2,
      shape_section_count = 3,
      shape_edge = "west",
      shape_feedback = "left 10 mm",
      shape_snap = "X → Bedroom west wall",
    })
    assert_equal(
      "Living · RESIZE section 2/3 · west edge · left 10 mm · snap: X → Bedroom west wall",
      resize.text
    )
    assert_equal(nil, presenter.context({
      model = plan,
      selection = { kind = "plan" },
      mode = "NAV",
    }).breadcrumb)
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
    assert_equal(true, registry.get("resize_dimensions", room).enabled)
    assert_equal("r", registry.get("resize_dimensions", room).key)
    assert_equal(false, registry.get("rotate", room).enabled)

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

  it("filters only explicitly searchable action windows", function()
    local palette = require("roomplan.ui.palette")
    local handle = assert(palette.open({
      title = "RoomPlan actions",
      searchable = true,
      items = {
        { key = "r", label = "Room", description = "Create geometry" },
        { key = "d", label = "Door", description = "Add an opening" },
      },
    }))
    local initial = table.concat(vim.api.nvim_buf_get_lines(handle.bufnr, 0, -1, false), "\n")
    assert_true(initial:find("/ Search actions", 1, true) ~= nil)

    local original_input = vim.ui.input
    vim.ui.input = function() error("the action search must stay inside its popup") end
    assert_true(palette.prompt_search(handle))
    vim.ui.input = original_input
    assert_equal(true, handle.searching)
    assert_equal(false, vim.bo[handle.bufnr].modifiable)
    assert_true(vim.api.nvim_buf_is_valid(handle.search_bufnr))
    assert_true(vim.api.nvim_win_is_valid(handle.search_winid))
    assert_equal(vim.bo[handle.search_bufnr].buftype, "prompt")
    assert_equal(vim.b[handle.search_bufnr].completion, false)

    vim.api.nvim_buf_set_lines(handle.search_bufnr, 0, -1, false, { "/ opening" })
    vim.api.nvim_exec_autocmds("TextChangedI", { buffer = handle.search_bufnr, modeline = false })
    local filtered = table.concat(vim.api.nvim_buf_get_lines(handle.bufnr, 0, -1, false), "\n")
    assert_true(filtered:find("Door", 1, true) ~= nil)
    assert_true(filtered:find("Create geometry", 1, true) == nil)
    assert_true(filtered:find("/ opening", 1, true) ~= nil)
    assert_true(palette.finish_search(handle))
    assert_equal(false, handle.searching)
    assert_equal(false, vim.bo[handle.bufnr].modifiable)

    assert_true(palette.filter(handle, ""))
    local restored = table.concat(vim.api.nvim_buf_get_lines(handle.bufnr, 0, -1, false), "\n")
    assert_true(restored:find("Room", 1, true) ~= nil)
    palette.close(handle, "test complete")

    local compact = assert(palette.open({ items = { { label = "Room" } } }))
    assert_equal(false, palette.filter(compact, "room"))
    palette.close(compact, "test complete")

    local chosen
    local submit = assert(palette.open({
      searchable = true,
      items = {
        { label = "Room" },
        { label = "Door", description = "Add an opening", callback = function() chosen = "door" end },
      },
    }))
    assert_true(palette.prompt_search(submit))
    vim.api.nvim_buf_set_lines(submit.search_bufnr, 0, -1, false, { "/ opening" })
    vim.api.nvim_exec_autocmds("TextChangedI", { buffer = submit.search_bufnr, modeline = false })
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
    assert_true(vim.wait(200, function() return chosen == "door" end, 10))
  end)

  it("keeps its dedicated search prompt focused while results redraw", function()
    local palette = require("roomplan.ui.palette")
    local handle = assert(palette.open({
      title = "RoomPlan actions",
      searchable = true,
      items = {
        { label = "Edit room" },
        { label = "Edit furniture shape" },
      },
    }))
    local ok, err = xpcall(function()
      local initial_config = vim.api.nvim_win_get_config(handle.winid)
      vim.api.nvim_feedkeys("/", "x", false)
      assert_equal(true, handle.searching)
      assert_equal(false, vim.bo[handle.bufnr].modifiable)
      assert_equal(vim.api.nvim_get_current_win(), handle.search_winid)
      assert_equal(vim.bo[handle.search_bufnr].buftype, "prompt")
      assert_equal(vim.fn.getcmdtype(), "")
      for _, query in ipairs({ "s", "sh", "sha", "shape" }) do
        vim.api.nvim_buf_set_lines(handle.search_bufnr, 0, -1, false, { "/ " .. query })
        vim.api.nvim_exec_autocmds("TextChangedI", { buffer = handle.search_bufnr, modeline = false })
        assert_equal(handle.query, query)
        assert_equal(vim.api.nvim_get_current_win(), handle.search_winid)
        local current_config = vim.api.nvim_win_get_config(handle.winid)
        assert_equal(current_config.width, initial_config.width)
        assert_equal(current_config.height, initial_config.height)
      end
      assert_true(table.concat(vim.api.nvim_buf_get_lines(handle.bufnr, 0, -1, false), "\n")
        :find("Edit furniture shape", 1, true) ~= nil)
      local search_bufnr = handle.search_bufnr
      assert_true(palette.finish_search(handle))
      assert_equal(false, handle.searching)
      assert_equal(false, vim.api.nvim_buf_is_valid(search_bufnr))
      assert_equal(vim.api.nvim_get_current_win(), handle.winid)
      assert_equal(false, vim.bo[handle.bufnr].modifiable)
      vim.api.nvim_feedkeys("q", "x", false)
      assert_equal(true, handle.closed)
    end, debug.traceback)
    if not handle.closed then palette.close(handle, "test cleanup") end
    if not ok then error(err, 0) end
  end)

  it("renders stable pane rows and a width-bounded persistent action bar", function()
    local view = presenter.objects(fixture(), { selection = { kind = "room", id = "room-living" } })
    local panel = objects_panel.render(view, 32, 12)
    assert_equal(12, #panel.lines)
    assert_equal("room-living", panel.row_map[3].id)
    assert_true(vim.fn.strdisplaywidth(panel.lines[3]) <= 32)
    assert_true(#panel.highlights > 0)

    local ctx = {
      model = fixture(), selection = { kind = "furniture", id = "sofa-1" },
      mode = "FURNITURE_EDIT", form = { kind = "furniture" }, focus = "properties",
      dirty = true, snap_enabled = true,
    }
    local bar = action_bar.render(ctx, 72, { height = 2 })
    assert_equal(2, #bar.lines)
    assert_true(bar.lines[1]:match("Apply") ~= nil)
    assert_true(bar.lines[1]:match("More") ~= nil)
    assert_true(bar.lines[1]:match("FURNITURE EDIT") ~= nil)
    assert_true(bar.lines[1]:match("DIRTY") ~= nil)
    assert_true(bar.overflow_count > 0)
    assert_true(#bar.shown_actions <= 5)
    assert_true(vim.fn.strdisplaywidth(bar.lines[1]) <= 72)

    local nav_ctx = vim.deepcopy(ctx)
    nav_ctx.mode = "NAV"
    nav_ctx.form = nil
    nav_ctx.detail_level = "middle"
    local nav_bar = action_bar.render(nav_ctx, 100, { height = 1 })
    assert_true(nav_bar.lines[1]:find("DETAIL MIDDLE", 1, true) ~= nil)
  end)

  it("keeps contextual breadcrumbs useful in wide, medium, and compact action bars", function()
    local session = {
      model = fixture(),
      selection = { kind = "furniture", id = "sofa-1" },
      validation = {},
      mode = "MOVE",
      move_feedback = "right 100 mm",
      snap_enabled = true,
      model_dirty = function() return false end,
    }
    local ctx = presenter.context(session)
    ctx.can_undo = true
    ctx.can_redo = false
    ctx.focus = "canvas"

    for _, width in ipairs({ 120, 90, 55 }) do
      local bar = action_bar.render(ctx, width, { height = 1 })
      assert_equal(1, #bar.lines)
      assert_true(vim.fn.strdisplaywidth(bar.lines[1]) <= width)
      assert_true(bar.lines[1]:find("Living", 1, true) ~= nil, "missing breadcrumb at width " .. width)
      assert_equal(ctx.breadcrumb.text, bar.breadcrumb.text)
    end

    local wide = action_bar.render(ctx, 160, { height = 1 })
    local _, move_count = wide.status:gsub("MOVE", "")
    assert_equal(1, move_count)
    local furniture_highlight
    for _, highlight in ipairs(wide.highlights) do
      if highlight.hl_group == "RoomPlanWorkspaceFurniture" then furniture_highlight = highlight end
    end
    assert_true(furniture_highlight ~= nil)

    session.selection = nil
    local empty = action_bar.render(presenter.context(session), 90, { height = 1 })
    assert_equal(nil, empty.breadcrumb)
    assert_true(empty.lines[1]:find("›", 1, true) == nil)
  end)

  it("keeps the workspace facade API stable", function()
    local workspace = require("roomplan.ui.workspace")
    for _, name in ipairs({
      "action_context", "apply_canvas_keymaps", "attach", "close", "collapse_focused",
      "cycle_focus", "escape", "expand_focused", "filter_focused", "filter_prompt",
      "focus", "hide", "invoke", "invoke_key", "is_visible", "layout", "mount",
      "owns_window", "reflow", "refresh", "select_focused", "set_details_section",
      "set_filter", "set_interaction", "toggle", "toggle_details_section",
      "toggle_mark_focused", "update_cursor",
    }) do
      assert_equal("function", type(workspace[name]), "missing workspace method " .. name)
    end
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
    assert_equal(1, vim.api.nvim_win_get_height(shell.windows.action_bar))
    assert_true(#vim.api.nvim_buf_get_extmarks(
      shell.buffers.objects,
      shell.namespaces.objects,
      0,
      -1,
      {}
    ) > 0)
    assert_equal(nil, shell.windows.properties)
    assert_equal(false, shell.state.visibility.details)
    local side_tab = vim.api.nvim_buf_call(shell.buffers.objects, function()
      return vim.fn.maparg("<Tab>", "n", false, true)
    end)
    assert_equal(nil, next(side_tab))
    local issue_next = vim.api.nvim_buf_call(shell.buffers.issues, function()
      return vim.fn.maparg("<A-j>", "n", false, true)
    end)
    local issue_previous = vim.api.nvim_buf_call(shell.buffers.issues, function()
      return vim.fn.maparg("<A-k>", "n", false, true)
    end)
    local detail = vim.api.nvim_buf_call(shell.buffers.issues, function()
      return vim.fn.maparg("t", "n", false, true)
    end)
    assert_equal("RoomPlan next_issue", issue_next.desc)
    assert_equal("RoomPlan previous_issue", issue_previous.desc)
    assert_equal("RoomPlan cycle_detail_level", detail.desc)

    assert_true(workspace.focus(session, "properties"))
    assert_true(vim.api.nvim_win_is_valid(shell.windows.properties))
    assert_equal(true, shell.state.visibility.details)
    workspace.reflow(session, true)
    assert_equal(shell.windows.properties, vim.api.nvim_get_current_win())
    assert_equal(shell.buffers.objects, vim.api.nvim_win_get_buf(shell.windows.left))
    assert_true(workspace.toggle(session, "properties"))
    assert_equal(nil, shell.windows.properties)
    assert_equal(false, shell.state.visibility.details)
    assert_true(workspace.toggle(session, "properties"))
    assert_true(vim.api.nvim_win_is_valid(shell.windows.properties))
    local old_properties_buffer = shell.buffers.properties
    vim.api.nvim_buf_delete(old_properties_buffer, { force = true })
    assert_true(vim.wait(200, function()
      return type(shell.buffers.properties) == "number"
        and shell.buffers.properties ~= old_properties_buffer
        and vim.api.nvim_buf_is_valid(shell.buffers.properties)
        and shell.reflowing == false
    end, 5), "wiped workspace buffers should be repaired")
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
    workspace.refresh(session, "action_bar")
    local row_footer = vim.api.nvim_buf_get_lines(shell.buffers.action_bar, 0, 1, false)[1] or ""
    assert_true(row_footer:find("Mark", 1, true) ~= nil, "object footer: " .. row_footer)
    assert_true(row_footer:find("Expand", 1, true) == nil, "object footer: " .. row_footer)
    assert_equal({ kind = "room", id = "room-living" }, workspace.select_focused(session))

    -- Contextual modes entered from a side pane must transfer control to the
    -- canvas, where their directional mappings actually operate.
    assert_true(workspace.focus(session, "properties"))
    local geometry_row
    for line, row in pairs(shell.rendered.properties.row_map) do
      if row.kind == "section" and row.section == "geometry" then geometry_row = line; break end
    end
    assert_true(geometry_row ~= nil)
    assert_equal(true, shell.rendered.properties.row_map[geometry_row].expanded)
    vim.api.nvim_win_set_cursor(shell.windows.properties, { geometry_row, 0 })
    assert_true(workspace.toggle_details_section(session))
    assert_equal(true, shell.state.collapsed_sections.geometry)
    assert_equal(false, shell.rendered.properties.row_map[geometry_row].expanded)
    assert_equal("MOVE", workspace.invoke(session, "move"))
    assert_equal("MOVE", session.mode)
    assert_equal("MOVE", shell.state.interaction)
    assert_equal(canvas_window, vim.api.nvim_get_current_win())
    require("roomplan.controller").escape(session)
    assert_equal("NAV", shell.state.interaction)

    -- A manually closed side pane becomes a visibility preference instead of
    -- being resurrected by the next resize/reflow.
    local closed_left = shell.windows.left
    vim.api.nvim_win_close(closed_left, true)
    assert_true(vim.wait(100, function() return shell.state.visibility.navigator == false end, 5))
    workspace.reflow(session)
    assert_equal(nil, shell.windows.left)
    assert_true(workspace.toggle(session, "objects"))
    assert_true(vim.api.nvim_win_is_valid(shell.windows.left))
    assert_true(shell.windows.left ~= closed_left)

    shell.opts.layout = "compact"
    shell.opts.columns = 80
    shell.opts.lines = 24
    workspace.reflow(session, true)
    assert_equal("compact", shell.layout.kind)
    local workspace_tab = shell.tabpage
    vim.cmd("tabnew")
    local other_tab = vim.api.nvim_get_current_tabpage()
    assert_true(other_tab ~= workspace_tab)
    assert_true(workspace.focus(session, "objects"))
    assert_equal(workspace_tab, vim.api.nvim_get_current_tabpage())
    assert_true(vim.api.nvim_win_is_valid(shell.windows.drawer))
    workspace.focus(session, "canvas")
    assert_equal(nil, shell.windows.drawer)
    vim.api.nvim_set_current_tabpage(other_tab)
    vim.cmd("tabclose")
    vim.api.nvim_set_current_tabpage(workspace_tab)

    assert_true(workspace.close(session))
    assert_true(vim.api.nvim_win_is_valid(canvas_window))
    assert_true(vim.api.nvim_buf_is_valid(canvas))
    vim.api.nvim_buf_delete(canvas, { force = true })
  end)
end)
