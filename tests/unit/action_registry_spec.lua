local registry = require("roomplan.ui.action_registry")

local function ids(actions)
  local result = {}
  for _, action in ipairs(actions) do
    result[#result + 1] = action.id
  end
  return result
end

local function context(focus, selection)
  local focused_row = focus == "objects"
      and {
        kind = "room",
        id = "room-1",
        expandable = true,
        expanded = true,
      }
    or focus == "issues" and {
      kind = "room",
      id = "room-1",
      index = 1,
    }
    or focus == "properties" and {
      kind = "section",
      section = "geometry",
      expanded = false,
    }
    or nil
  return {
    model = { rooms = { { id = "room-1" }, { id = "room-2" } } },
    mode = "NAV",
    focus = focus,
    selection = selection,
    can_undo = true,
    can_redo = false,
    detail_level = "middle",
    focused_row = focused_row,
  }
end

describe("action registry", function()
  it("keeps persistent actions compact and sensitive to pane and selection", function()
    local furniture = { kind = "furniture", id = "chair-1" }
    local canvas = registry.primary(context("canvas", furniture))
    assert_equal({ "edit", "resize_dimensions", "move", "rotate", "delete", "help" }, ids(canvas))
    assert_true(canvas[#canvas].count > 0)

    local objects = registry.primary(context("objects", furniture))
    assert_equal({
      "activate_focused",
      "toggle_mark",
      "collapse_focused",
      "filter_focused",
      "help",
    }, ids(objects))
    assert_equal("select_focused", objects[1].workspace_action)
    assert_equal("objects", objects[1].scopes[1])
    assert_equal("Enter", objects[1].key_label)

    assert_equal(
      { "activate_focused", "filter_focused", "validate", "help" },
      ids(registry.primary(context("issues", furniture)))
    )
    assert_equal({ "toggle_details_section", "edit", "help" }, ids(registry.primary(context("properties", furniture))))
  end)

  it("publishes direct room resize controls as one focused mode", function()
    local ctx = context("canvas", { kind = "room", id = "room-1" })
    ctx.mode = "RESIZE"
    ctx.shape_section_index = 2
    ctx.shape_section_count = 3
    ctx.shape_edge = "west"
    ctx.shape_snap = "X → Kitchen west wall"
    assert_equal({
      "shape_apply",
      "select",
      "shape_next",
      "add",
      "delete",
      "toggle_snap",
      "leave_mode",
      "help",
    }, ids(registry.primary(ctx)))
    local resize = registry.get("resize_dimensions", context("canvas", { kind = "room", id = "room-1" }))
    assert_equal("Resize dimensions", resize.label)
    assert_equal("r", resize.key)
    assert_equal("s", registry.get("shape_apply", ctx).key_label)
    assert_true(registry.mode_label(ctx):find("RESIZE · section 2/3", 1, true) ~= nil)
    assert_true(registry.mode_label(ctx):find("edge west", 1, true) ~= nil)
    assert_true(registry.mode_label(ctx):find("Kitchen west wall", 1, true) ~= nil)
  end)

  it("includes the last visible movement in MOVE status", function()
    local ctx = context("canvas", { kind = "room", id = "room-1" })
    ctx.mode = "MOVE"
    ctx.move_feedback = "up 200 mm"
    assert_true(registry.mode_label(ctx):find("up 200 mm", 1, true) ~= nil)
  end)

  it("shares exact contextual controls across modes and always exposes their exit", function()
    local move = context("canvas", { kind = "furniture", id = "chair-1" })
    move.mode = "MOVE"
    local move_controls = registry.context_controls(move)
    assert_equal({
      "move_normal",
      "move_coarse",
      "move_fine",
      "toggle_snap",
      "save",
      "leave_mode",
    }, ids(move_controls))
    assert_equal("h/j/k/l", move_controls[1].key_label)
    assert_equal("Finish moving", move_controls[#move_controls].label)
    assert_equal("Esc", move_controls[#move_controls].key_label)

    local resize = context("canvas", { kind = "room", id = "room-1" })
    resize.mode = "RESIZE"
    resize.shape_section_index = 2
    resize.shape_section_count = 3
    resize.shape_edge = "west"
    assert_equal("RESIZE · SECTION 2/3 · WEST EDGE", registry.context_title(resize))
    assert_equal("Cancel resize", registry.context_controls(resize)[8].label)

    local sun = context("canvas", { kind = "room", id = "room-1" })
    sun.mode = "SUN STUDY"
    sun.sun_study = { time = "14:00", playing = true }
    assert_equal({
      "sun_previous",
      "sun_next",
      "sun_previous_season",
      "sun_next_season",
      "sun_toggle_playback",
      "sun_study",
      "sun_close",
    }, ids(registry.context_controls(sun)))
    assert_equal("Pause", registry.get("sun_toggle_playback", sun).label)
    assert_equal("SUN STUDY · 14:00 · PLAYING", registry.context_title(sun))
    assert_equal("Close study", registry.context_controls(sun)[7].label)

    sun.keymaps = {
      enabled = true,
      mappings = { h = "gH", sun_study = "gL", escape = "Q" },
    }
    assert_equal("gH", registry.get("sun_previous", sun).key)
    assert_equal("gL", registry.get("sun_study", sun).key)
    assert_equal("Q", registry.get("sun_close", sun).key)
  end)

  it("returns a complete grouped action set with disabled reasons", function()
    local ctx = context("objects", { kind = "room", id = "room-1" })
    ctx.can_redo = false
    local full = registry.full(ctx)
    local present = {}
    for _, action in ipairs(full) do
      present[action.id] = action
    end

    assert_true(present.activate_focused.primary)
    assert_true(present.edit.primary == false)
    assert_equal("Nothing to redo", present.redo.reason)
    assert_equal("Current panel", present.activate_focused.group_label)
    assert_true(present.objects ~= nil)
    assert_true(present.canvas ~= nil)
    assert_true(present.properties ~= nil)
    assert_true(present.issues ~= nil)
    for _, id in ipairs({
      "add",
      "add_door",
      "add_window",
      "add_outlet",
      "add_furniture",
      "pan",
      "align",
      "rotate",
      "cycle_detail_level",
      "zoom_in",
      "zoom_out",
      "rotate_view_clockwise",
      "rotate_view_counterclockwise",
      "reset_view",
      "toggle_minimap",
      "toggle_snap",
      "bypass_snap",
      "save_as",
      "next_issue",
      "previous_issue",
      "measure",
      "history_list",
      "aspect",
      "reload",
      "close",
    }) do
      assert_true(present[id] ~= nil, "missing full action " .. id)
      assert_true(present[id].primary == false)
    end
    assert_equal("zoom", present.zoom_in.handler)
    assert_equal(".", present.zoom_in.key)
    assert_equal(",", present.zoom_out.key)
    assert_equal("t", present.cycle_detail_level.key)
    assert_equal("M", present.toggle_minimap.key)
    assert_equal("Show minimap", present.toggle_minimap.label)
    assert_equal("S", present.sun_study.key)
    assert_equal("gS", present.save_as.key)
    ctx.minimap_enabled = true
    assert_equal("Hide minimap", registry.get("toggle_minimap", ctx).label)
    assert_equal("set_detail_level", present.cycle_detail_level.handler)
    assert_equal("cycle", present.cycle_detail_level.args[1])
    assert_equal("Canvas detail: middle → none", present.cycle_detail_level.label)
    assert_equal("in", present.zoom_in.args[1])
    assert_equal("rotate_view", present.rotate_view_clockwise.handler)
    assert_equal("clockwise", present.rotate_view_clockwise.args[1])
    assert_equal("<A-l>", present.rotate_view_clockwise.key)
    assert_equal("Alt-l", present.rotate_view_clockwise.key_label)
    assert_equal("counterclockwise", present.rotate_view_counterclockwise.args[1])
    assert_equal("<A-h>", present.rotate_view_counterclockwise.key)
    assert_equal("<A-j>", present.next_issue.key)
    assert_equal("Alt-j", present.next_issue.key_label)
    assert_equal("reset", present.reset_view.args[1])
    assert_equal("next_issue", present.previous_issue.handler)
    assert_equal(-1, present.previous_issue.args[1])
    assert_equal("<A-k>", present.previous_issue.key)
    assert_equal("Source and session", present.reload.group_label)
    assert_equal("Disable snapping", present.toggle_snap.label)
    assert_equal("W", present.add_window.key)
    assert_equal("add_window", present.add_window.handler)
    assert_equal("O", present.add_outlet.key)
    assert_equal("add_outlet", present.add_outlet.handler)
    local controller = require("roomplan.controller")
    for _, id in ipairs({
      "cycle_detail_level",
      "zoom_in",
      "zoom_out",
      "rotate_view_clockwise",
      "rotate_view_counterclockwise",
      "reset_view",
      "toggle_minimap",
      "toggle_snap",
      "bypass_snap",
      "save_as",
      "next_issue",
      "previous_issue",
      "aspect",
      "reload",
      "close",
    }) do
      assert_equal("function", type(controller[present[id].handler]))
    end

    local grouped = registry.grouped(ctx, { exclude = { "help" } })
    assert_equal("pane", grouped[1].id)
    assert_equal("Current panel", grouped[1].label)
    for _, group in ipairs(grouped) do
      for _, action in ipairs(group.actions) do
        assert_true(action.id ~= "help")
      end
    end
  end)

  it("keeps window and outlet selection actions movable and duplicable", function()
    for _, kind in ipairs({ "window", "outlet" }) do
      local ctx = context("canvas", { kind = kind, id = kind .. "-1" })
      assert_equal({ "edit", "move", "delete", "help" }, ids(registry.primary(ctx)))
      local present = {}
      for _, action in ipairs(registry.full(ctx)) do
        present[action.id] = action
      end
      for _, id in ipairs({ "edit", "move", "duplicate", "delete" }) do
        assert_true(present[id] ~= nil, kind .. " is missing " .. id)
        assert_true(present[id].enabled, kind .. " unexpectedly disables " .. id)
      end
    end

    local empty = context("canvas", nil)
    empty.model.rooms = {}
    assert_equal("Add a room first", registry.get("add_window", empty).reason)
    assert_equal("Add a room first", registry.get("add_outlet", empty).reason)
  end)

  it("publishes one direct dimension shortcut without restoring the old hidden shape action", function()
    assert_equal(
      nil,
      registry.get(
        "edit_shape",
        context("canvas", {
          kind = "furniture",
          id = "sofa-1",
        })
      )
    )
    for _, selection in ipairs({
      { kind = "room", id = "room-main" },
      { kind = "furniture", id = "sofa-1" },
      { kind = "template", id = "custom:sectional" },
    }) do
      local ctx = context("canvas", selection)
      local resize = registry.get("resize_dimensions", ctx)
      assert_equal(true, resize.enabled)
      assert_equal("r", resize.key)
      assert_equal("edit_selected_shape", resize.handler)
      local found = false
      for _, candidate in ipairs(registry.full(ctx)) do
        assert_true(candidate.id ~= "edit_shape")
        if candidate.id == "resize_dimensions" then found = true end
      end
      assert_equal(true, found)
    end
    local rotate = registry.get("rotate", context("canvas", { kind = "furniture", id = "sofa-1" }))
    assert_equal("R", rotate.key)
    assert_equal(true, rotate.enabled)
    assert_equal(false, registry.get("rotate", context("canvas", { kind = "room", id = "room-main" })).enabled)
  end)

  it("prioritizes pane-local keys and respects mapping overrides", function()
    local ctx = context("objects", nil)
    local original_count = registry.more_count(ctx)
    ctx.keymaps = {
      enabled = true,
      mappings = { workspace_activate_focused = "o", workspace_filter_focused = false },
    }
    assert_equal("o", registry.get("activate_focused", ctx).key)
    assert_equal(nil, registry.get("filter_focused", ctx).key)
    assert_equal("activate_focused", registry.by_key(ctx, "o").id)
    assert_equal(original_count + 1, registry.more_count(ctx))
    local full_ids = ids(registry.full(ctx))
    assert_true(not vim.tbl_contains(full_ids, "select"))
    local canvas_ids = ids(registry.full(context("canvas", { kind = "furniture", id = "chair-1" })))
    for _, id in ipairs({ "select", "add", "pan", "align", "rotate" }) do
      assert_true(vim.tbl_contains(canvas_ids, id), "missing canvas action " .. id)
    end
  end)

  it("opens More as a grouped registry-backed palette", function()
    local chosen
    local session = {
      id = "registry-help-test",
      model = context("objects").model,
      selection = { kind = "room", id = "room-1" },
      validation = {},
      mode = "NAV",
      snap_enabled = true,
      workspace = {
        state = { focused_pane = "objects" },
        opts = { border = "single" },
      },
      current_model = function(self) return self.model end,
      model_dirty = function() return false end,
    }
    local handle = assert(require("roomplan.ui.help").open(session, {
      on_action = function(action) chosen = action.id end,
    }))
    local lines = table.concat(vim.api.nvim_buf_get_lines(handle.bufnr, 0, -1, false), "\n")
    assert_true(lines:match("Current panel") ~= nil)
    assert_true(lines:match("Save and history") ~= nil)
    assert_true(lines:match("Calibrate terminal aspect") ~= nil)
    assert_true(lines:match("Open") ~= nil)
    assert_true(lines:match("%[Enter%] Open") == nil)
    assert_true(lines:match("%[q%] Hide") == nil)
    assert_true(lines:match("%[%?%] More") == nil)
    local enter = vim.api.nvim_buf_call(handle.bufnr, function() return vim.fn.maparg("<CR>", "n", false, true) end)
    assert_equal("Run RoomPlan action", enter.desc)

    local edit
    for _, action in pairs(handle.row_map) do
      if action.id == "edit" then
        edit = action
        break
      end
    end
    assert_true(require("roomplan.ui.palette").choose(handle, edit))
    assert_true(vim.wait(200, function() return chosen == "edit" end, 10))
  end)

  it("shows grouped mode controls in More without treating composite hints as actions", function()
    local session = {
      id = "registry-mode-help-test",
      model = context("canvas").model,
      selection = { kind = "room", id = "room-1" },
      validation = {},
      mode = "MOVE",
      snap_enabled = true,
      workspace = {
        state = { focused_pane = "canvas", interaction = "MOVE" },
        opts = { border = "single" },
      },
      current_model = function(self) return self.model end,
      model_dirty = function() return false end,
    }
    local handle = assert(require("roomplan.ui.help").open(session))
    local lines = table.concat(vim.api.nvim_buf_get_lines(handle.bufnr, 0, -1, false), "\n")
    assert_true(lines:find("[h/j/k/l] Move", 1, true) ~= nil)
    assert_true(lines:find("[Esc] Finish moving", 1, true) ~= nil)
    for _, action in pairs(handle.row_map) do
      assert_true(action.id ~= "move_normal")
    end
    require("roomplan.ui.palette").close(handle, "test cleanup")
  end)
end)
