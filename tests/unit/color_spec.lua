local color = require("roomplan.color")
local model = require("roomplan.model")
local schema = require("roomplan.schema")

describe("plan colors", function()
  it("provides copied palette choices and canonical color values", function()
    local first = color.choices()
    local second = color.choices()
    assert_equal("auto", first[1].value)
    assert_true(#first >= 10)
    first[2].label = "changed"
    assert_equal("Red", second[2].label)
    local custom = color.choices("#123456")
    assert_equal("#123456", custom[#custom].value)
    assert_equal("#AABBCC", color.normalize("#aabbcc"))
    assert_equal(nil, color.normalize("blue"))
  end)

  it("validates optional room and furniture colors without a schema migration", function()
    local plan = assert(model.new({ name = "Colored plan" }))
    plan.rooms[1] = model.new_room({
      id = "room-colored",
      name = "Colored room",
      origin_mm = { 0, 0 },
      size_mm = { 1000, 1000 },
      color = "#aabbcc",
    })
    local normalized, info = schema.normalize(plan)
    assert_true(normalized ~= nil, info and info.message)
    assert_equal("#AABBCC", normalized.rooms[1].color)
    assert_true(info.normalized)

    plan.rooms[1].color = "blue"
    local rejected, err = schema.normalize(plan)
    assert_equal(nil, rejected)
    assert_equal("SCHEMA_COLOR", err.code)
  end)
end)
