local config = require("roomplan.config")

describe("config", function()
  it("returns independent defaults", function()
    config.reset()
    local one = config.defaults()
    one.canvas.open = "split"
    one.ui.workspace.left_width = 99
    assert_equal(config.defaults().canvas.open, "tab")
    assert_equal(config.defaults().ui.workspace.left_width, 26)
    assert_equal(
      config.defaults().ui.workspace,
      require("roomplan.ui.workspace_state").defaults()
    )
    assert_equal(
      config.defaults().plan_defaults.settings,
      require("roomplan.schema").defaults.settings
    )
  end)

  it("rejects removed UI and canvas options", function()
    config.reset()
    for _, options in ipairs({
      { canvas = { show_rulers = true } },
      { ui = { experience = "classic" } },
      { ui = { inspector = "float" } },
    }) do
      local ok, err = pcall(config.setup, options)
      assert_true(not ok)
      assert_true(tostring(err):match("unknown option") ~= nil)
    end
  end)

  it("validates unknown keys without replacing prior config", function()
    config.reset()
    config.setup({ canvas = { open = "split" } })
    local ok = pcall(config.setup, { canvas = { typo = true } })
    assert_true(not ok)
    assert_equal(config.get().canvas.open, "split")
  end)

  it("accepts nullable defaults and per-action mapping overrides", function()
    config.reset()
    local effective = config.setup({
      plan_defaults = { metadata = { name = "My plan" } },
      keymaps = { mappings = { hide = "<leader>q", ["<C-h>"] = false } },
      glyphs = { marker = "x" },
    })
    assert_equal(effective.plan_defaults.metadata.name, "My plan")
    assert_equal(effective.keymaps.mappings.hide, "<leader>q")
    assert_equal(effective.keymaps.mappings["<C-h>"], false)
    assert_equal(effective.glyphs.marker, "x")
    config.reset()
  end)

  it("updates only the runtime cell-aspect calibration", function()
    config.reset()
    config.setup({
      canvas = { open = "split", cell_aspect = 1.8 },
      ui = { workspace = { left_width = 41 } },
    })
    assert_equal(2.25, assert(config.set_cell_aspect(2.25)))
    assert_equal(2.25, config.get().canvas.cell_aspect)
    assert_equal("split", config.get().canvas.open)
    assert_equal(41, config.get().ui.workspace.left_width)
    local rejected = config.set_cell_aspect(0)
    assert_equal(nil, rejected)
    assert_equal(2.25, config.get().canvas.cell_aspect)
    config.reset()
  end)
end)
