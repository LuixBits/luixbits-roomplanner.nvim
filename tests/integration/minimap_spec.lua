local h = require("tests.harness")

local controller = require("roomplan.controller")
local model = require("roomplan.model")

describe("minimap", function()
  it("tracks the exact canvas field of view without stealing focus or editing the plan", function()
    local path = vim.fn.tempname() .. ".roomplan.json"
    local session = h.truthy(controller.init_source(nil, { path = path }))
    h.truthy(controller.dispatch(session, {
      type = "add_room",
      room = model.new_room({
        id = "room-map-left",
        name = "Left",
        origin_mm = { 0, 0 },
        size_mm = { 4000, 3000 },
        color = "#61AFEF",
      }),
    }))
    h.truthy(controller.dispatch(session, {
      type = "add_room",
      room = model.new_room({
        id = "room-map-right",
        name = "Right",
        origin_mm = { 4000, 0 },
        size_mm = { 3000, 3000 },
        color = "#E5C07B",
      }),
    }))
    h.truthy(controller.focus_canvas(session))

    local canvas_win = session.canvas.winid
    local revision = session:revision_id()
    local dirty = session:model_dirty()
    h.eq(canvas_win, vim.api.nvim_get_current_win())
    h.eq(true, controller.toggle_minimap(session))
    h.eq(canvas_win, vim.api.nvim_get_current_win(), "opening the minimap must preserve canvas focus")
    h.truthy(session.minimap.enabled)
    h.truthy(vim.api.nvim_win_is_valid(session.minimap.winid))

    local window_config = vim.api.nvim_win_get_config(session.minimap.winid)
    h.eq("win", window_config.relative)
    h.eq(canvas_win, window_config.win)
    h.eq(false, window_config.focusable)
    local initial = h.truthy(session.minimap.last_raster)
    local roles, colors = {}, {}
    for _, span in ipairs(initial.highlight_spans) do
      roles[span.role] = true
      if span.color then
        colors[span.color] = true
      end
    end
    h.truthy(roles.wall)
    h.truthy(roles.room)
    h.truthy(roles.selected, "the field-of-view rectangle must be visible")
    h.truthy(colors["#61AFEF"])
    h.truthy(colors["#E5C07B"])

    local initial_width = initial.field_of_view.right - initial.field_of_view.left
    h.truthy(controller.zoom(session, "in"))
    h.truthy(vim.wait(500, function()
      local current = session.minimap.last_raster
      return current and current.field_of_view.right - current.field_of_view.left < initial_width
    end, 10))
    h.eq(canvas_win, vim.api.nvim_get_current_win(), "redrawing the minimap must preserve canvas focus")

    h.eq(false, controller.toggle_minimap(session))
    h.eq(canvas_win, vim.api.nvim_get_current_win(), "closing the minimap must preserve canvas focus")
    h.falsy(session.minimap.enabled)
    h.eq(nil, session.minimap.winid)
    h.eq(revision, session:revision_id())
    h.eq(dirty, session:model_dirty())

    h.truthy(controller.close(session, { bang = true }))
    pcall(vim.uv.fs_unlink, path)
  end)
end)
