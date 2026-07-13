describe("commands", function()
  it("retains the public aspect compatibility alias", function()
    local roomplan = require("roomplan")
    assert_equal(roomplan.set_aspect, roomplan.aspect)
  end)

  it("registers idempotently without global maps", function()
    local before = vim.api.nvim_get_keymap("n")
    require("roomplan.commands").register()
    require("roomplan.commands").register()
    assert_equal(vim.fn.exists(":RoomPlanOpen"), 2)
    assert_equal(vim.fn.exists(":RoomPlanSaveAs"), 2)
    assert_equal(vim.fn.exists(":RoomPlanAspect"), 2)
    assert_equal(vim.fn.exists(":RoomPlanRotateView"), 2)
    assert_equal("function", type(require("roomplan").rotate_view))
    assert_equal(vim.api.nvim_get_keymap("n"), before)
  end)

  it("calibrates aspect through command input and the Lua API without a session", function()
    local config = require("roomplan.config")
    config.reset()
    vim.cmd("RoomPlanAspect 1.75")
    assert_equal(1.75, config.get().canvas.cell_aspect)

    local original_input = vim.ui.input
    local prompt
    vim.ui.input = function(opts, done)
      prompt = opts.prompt
      done("2.2")
    end
    local ok, err = xpcall(function() vim.cmd("RoomPlanAspect") end, debug.traceback)
    vim.ui.input = original_input
    if not ok then error(err, 0) end
    assert_true(prompt:match("height/width") ~= nil)
    assert_equal(2.2, config.get().canvas.cell_aspect)

    assert_equal(1.9, require("roomplan").set_aspect(1.9, { quiet = true }))
    assert_equal(1.9, config.get().canvas.cell_aspect)
    config.reset()
  end)
end)
