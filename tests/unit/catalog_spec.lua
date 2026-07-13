local catalog = require("roomplan.catalog")
local config = require("roomplan.config")

local function definition(overrides)
  return vim.tbl_extend("force", {
    id = "custom:standing-desk",
    name = "Standing desk",
    category = "work",
    default_size_mm = { 1600, 800, 1200 },
  }, overrides or {})
end

describe("furniture catalog imports", function()
  it("merges validated inline definitions without exposing mutable state", function()
    config.reset()
    config.setup({ furniture = { definitions = { definition() } } })

    assert_equal(14, #catalog.all())
    local imported = assert(catalog.get("custom:standing-desk"))
    assert_equal("Standing desk", imported.name)
    assert_equal(false, imported.builtin)
    imported.default_size_mm[1] = 1
    assert_equal(1600, catalog.get("custom:standing-desk").default_size_mm[1])
    assert_equal(2100, catalog.get("builtin:sofa").default_size_mm[1])

    local plan_local = catalog.resolve({ custom_templates = {
      definition({ name = "Project desk", default_size_mm = { 1000, 500, 700 } }),
    } }, "custom:standing-desk")
    assert_equal("Project desk", plan_local.name)
    config.reset()
  end)

  it("loads the versioned JSON catalog schema", function()
    config.reset()
    local path = vim.fn.tempname() .. ".json"
    vim.fn.writefile({
      "{",
      '  "version": 1,',
      '  "furniture": [',
      '    {"id":"custom:window-seat","name":"Window seat","category":"seating","default_size_mm":[1800,600,450]}',
      "  ]",
      "}",
    }, path)

    config.setup({ furniture = { include_builtins = false, files = { path } } })
    local imported = assert(catalog.resolve("custom:window-seat"))
    assert_equal("Window seat", imported.name)
    assert_equal({ 1800, 600, 450 }, imported.default_size_mm)
    assert_equal({ "custom:window-seat" }, vim.tbl_map(function(item) return item.id end, catalog.all()))

    vim.fn.delete(path)
    config.reset()
  end)

  it("can replace the visible defaults without breaking existing built-in references", function()
    config.reset()
    config.setup({
      furniture = {
        include_builtins = false,
        definitions = { definition() },
      },
    })

    local visible = catalog.all()
    assert_equal(1, #visible)
    assert_equal("custom:standing-desk", visible[1].id)
    assert_equal({ "work" }, catalog.categories())

    local empty_plan = { rooms = {}, custom_templates = {}, furniture = {} }
    local session = { model = function() return empty_plan end }
    local add_spec = require("roomplan.ui.forms.furniture").add(session)
    assert_equal("custom:standing-desk", add_spec.initial.template_id)

    -- Hiding defaults affects new choices only. Existing plans using stable
    -- builtin IDs must keep resolving and validating normally.
    assert_equal("Sofa", assert(catalog.resolve("builtin:sofa")).name)
    assert_true(catalog.exists("builtin:sofa"))

    empty_plan.furniture = {
      {
        id = "furniture-sofa", room_id = "room-a", template_id = "builtin:sofa",
        name = "Old sofa", category = "seating", center_mm = { 100, 100 },
        size_mm = { 2100, 900, 850 }, rotation_deg = 0,
      },
    }
    local edit_spec = require("roomplan.ui.forms.furniture").edit(session, empty_plan.furniture[1])
    local edit_choices = edit_spec.fields[2].choices(edit_spec.context)
    local found_builtin = false
    for _, choice in ipairs(edit_choices) do
      if choice.value == "builtin:sofa" then found_builtin = true; break end
    end
    assert_true(found_builtin)

    local changed = pcall(config.setup, {
      furniture = {
        include_builtins = true,
        definitions = { definition({ default_size_mm = { 0, 800, 1200 } }) },
      },
    })
    assert_true(not changed)
    assert_equal(1, #catalog.all())
    config.reset()
    assert_true(#catalog.all() > 1)
  end)

  it("rejects an empty replacement catalogue", function()
    config.reset()
    local ok, err = pcall(config.setup, {
      furniture = { include_builtins = false },
    })
    assert_true(not ok)
    assert_true(tostring(err):find("requires at least one imported definition", 1, true) ~= nil)
    assert_true(#catalog.all() > 1)
    config.reset()
  end)

  it("rejects unsafe definitions atomically", function()
    config.reset()
    config.setup({ furniture = { definitions = { definition() } } })

    local ok, err = pcall(config.setup, { furniture = { definitions = {
      definition({
        id = "builtin:sofa",
        default_size_mm = { 0, 800, 1200 },
        typo = true,
      }),
    } } })
    assert_true(not ok)
    assert_true(tostring(err):find("cannot replace built%-in templates") ~= nil)
    assert_true(tostring(err):find("unknown field") ~= nil)
    assert_equal("Standing desk", catalog.get("custom:standing-desk").name)
    assert_equal(2100, catalog.get("builtin:sofa").default_size_mm[1])
    config.reset()
  end)

  it("enforces the plan text contract for inline and JSON labels", function()
    config.reset()
    local ok, err = pcall(config.setup, { furniture = { definitions = {
      definition({ category = "bad\0category", name = string.rep("x", 513) }),
    } } })
    assert_true(not ok)
    assert_true(tostring(err):find("disallowed control character", 1, true) ~= nil)
    assert_true(tostring(err):find("512 byte limit", 1, true) ~= nil)

    local path = vim.fn.tempname() .. ".json"
    vim.fn.writefile({
      '{"version":1,"furniture":[',
      '{"id":"custom:unsafe","name":"Unsafe","category":"bad\\u0000category","default_size_mm":[1,1,1]}',
      "]}",
    }, path)
    ok, err = pcall(config.setup, { furniture = { files = { path } } })
    assert_true(not ok)
    assert_true(tostring(err):find("disallowed control character", 1, true) ~= nil)
    vim.fn.delete(path)
    config.reset()
  end)

  it("rejects an oversized catalog before decoding it", function()
    config.reset()
    local path = vim.fn.tempname() .. ".json"
    vim.fn.writefile({ string.rep(" ", 1024 * 1024 + 1) }, path, "b")
    local ok, err = pcall(config.setup, { furniture = { files = { path } } })
    assert_true(not ok)
    assert_true(tostring(err):find("exceeds the 1 MiB catalog limit", 1, true) ~= nil)
    vim.fn.delete(path)
    config.reset()
  end)

  it("shows one plan-local choice when an imported ID is overridden", function()
    config.reset()
    config.setup({ furniture = { definitions = { definition() } } })
    local local_template = definition({ name = "Project desk", default_size_mm = { 1000, 500, 700 } })
    local plan = { rooms = {}, custom_templates = { local_template } }
    local session = {}
    function session:model() return plan end
    local spec = require("roomplan.ui.forms.furniture").add(session)
    local choices = spec.fields[2].choices(spec.context)
    local matches = {}
    for _, choice in ipairs(choices) do
      if choice.value == local_template.id then matches[#matches + 1] = choice end
    end
    assert_equal(1, #matches)
    assert_equal("Project desk", matches[1].raw.name)
    config.reset()
  end)

  it("rejects duplicate IDs across inline and file sources", function()
    config.reset()
    local path = vim.fn.tempname() .. ".json"
    vim.fn.writefile({
      '{"version":1,"furniture":[',
      '{"id":"custom:standing-desk","name":"Other desk","category":"work","default_size_mm":[1000,500,700]}',
      "]}",
    }, path)

    local ok, err = pcall(config.setup, {
      furniture = { definitions = { definition() }, files = { path } },
    })
    assert_true(not ok)
    assert_true(tostring(err):find("duplicate imported template ID") ~= nil)
    assert_true(not catalog.exists("custom:standing-desk"))

    vim.fn.delete(path)
    config.reset()
  end)
end)
