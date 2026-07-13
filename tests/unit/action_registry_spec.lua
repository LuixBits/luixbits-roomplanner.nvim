local registry = require("roomplan.ui.action_registry")

local function ids(actions)
  local result = {}
  for _, action in ipairs(actions) do result[#result + 1] = action.id end
  return result
end

local function context(focus, selection)
  local focused_row = focus == "objects" and {
    kind = "room", id = "room-1", expandable = true, expanded = true,
  } or focus == "issues" and {
    kind = "room", id = "room-1", index = 1,
  } or focus == "properties" and {
    kind = "section", section = "geometry", expanded = false,
  } or nil
  return {
    model = { rooms = { { id = "room-1" }, { id = "room-2" } } },
    mode = "NAV",
    focus = focus,
    selection = selection,
    can_undo = true,
    can_redo = false,
    focused_row = focused_row,
  }
end

describe("action registry", function()
  it("keeps persistent actions compact and sensitive to pane and selection", function()
    local furniture = { kind = "furniture", id = "chair-1" }
    local canvas = registry.primary(context("canvas", furniture))
    assert_equal({ "edit", "move", "rotate", "delete", "help" }, ids(canvas))
    assert_true(canvas[#canvas].count > 0)

    local objects = registry.primary(context("objects", furniture))
    assert_equal({
      "activate_focused", "collapse_focused", "filter_focused", "help",
    }, ids(objects))
    assert_equal("select_focused", objects[1].workspace_action)
    assert_equal("objects", objects[1].scopes[1])
    assert_equal("Enter", objects[1].key_label)

    assert_equal(
      { "activate_focused", "filter_focused", "validate", "help" },
      ids(registry.primary(context("issues", furniture)))
    )
    assert_equal(
      { "toggle_details_section", "edit", "help" },
      ids(registry.primary(context("properties", furniture)))
    )
  end)

  it("returns a complete grouped action set with disabled reasons", function()
    local ctx = context("objects", { kind = "room", id = "room-1" })
    ctx.can_redo = false
    local full = registry.full(ctx)
    local present = {}
    for _, action in ipairs(full) do present[action.id] = action end

    assert_true(present.activate_focused.primary)
    assert_true(present.edit.primary == false)
    assert_equal("Nothing to redo", present.redo.reason)
    assert_equal("Current panel", present.activate_focused.group_label)
    assert_true(present.objects ~= nil)
    assert_true(present.canvas ~= nil)
    assert_true(present.properties ~= nil)
    assert_true(present.issues ~= nil)
    for _, id in ipairs({
      "add", "add_door", "add_furniture", "pan", "align", "rotate",
      "zoom_in", "zoom_out", "rotate_view_clockwise", "rotate_view_counterclockwise", "reset_view",
      "toggle_snap", "bypass_snap", "save_as", "next_issue", "previous_issue",
      "aspect", "reload", "close",
    }) do
      assert_true(present[id] ~= nil, "missing full action " .. id)
      assert_true(present[id].primary == false)
    end
    assert_equal("zoom", present.zoom_in.handler)
    assert_equal("in", present.zoom_in.args[1])
    assert_equal("rotate_view", present.rotate_view_clockwise.handler)
    assert_equal("clockwise", present.rotate_view_clockwise.args[1])
    assert_equal("]r", present.rotate_view_clockwise.key)
    assert_equal("counterclockwise", present.rotate_view_counterclockwise.args[1])
    assert_equal("reset", present.reset_view.args[1])
    assert_equal("next_issue", present.previous_issue.handler)
    assert_equal(-1, present.previous_issue.args[1])
    assert_equal("Source and session", present.reload.group_label)
    assert_equal("Disable snapping", present.toggle_snap.label)
    local controller = require("roomplan.controller")
    for _, id in ipairs({
      "zoom_in", "zoom_out", "rotate_view_clockwise", "rotate_view_counterclockwise", "reset_view",
      "toggle_snap", "bypass_snap", "save_as", "next_issue", "previous_issue",
      "aspect", "reload", "close",
    }) do
      assert_equal("function", type(controller[present[id].handler]))
    end

    local grouped = registry.grouped(ctx, { exclude = { "help" } })
    assert_equal("pane", grouped[1].id)
    assert_equal("Current panel", grouped[1].label)
    for _, group in ipairs(grouped) do
      for _, action in ipairs(group.actions) do assert_true(action.id ~= "help") end
    end
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
    local enter = vim.api.nvim_buf_call(handle.bufnr, function()
      return vim.fn.maparg("<CR>", "n", false, true)
    end)
    assert_equal("Run RoomPlan action", enter.desc)

    local edit
    for _, action in pairs(handle.row_map) do
      if action.id == "edit" then edit = action; break end
    end
    assert_true(require("roomplan.ui.palette").choose(handle, edit))
    assert_true(vim.wait(200, function() return chosen == "edit" end, 10))
  end)
end)
