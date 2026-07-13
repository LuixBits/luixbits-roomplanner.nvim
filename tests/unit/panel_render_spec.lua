local common = require("roomplan.ui.panels.common")
local issues = require("roomplan.ui.panels.issues")
local properties = require("roomplan.ui.panels.properties")

local function section_rows(rendered)
  local result = {}
  for row, item in pairs(rendered.row_map) do
    if item.kind == "section" then result[item.section] = { row = row, item = item } end
  end
  return result
end

describe("compact panel rendering", function()
  it("pads short documents without clipping scrollable content", function()
    local short = common.document(8)
    common.line(short, "one")
    assert_equal(3, #common.finish(short, 3).lines)

    local long = common.document(8)
    common.line(long, "one")
    common.line(long, "two")
    common.line(long, "three")
    assert_equal(3, #common.finish(long, 1).lines)
  end)

  it("renders details as stateful bordered sections without duplicate actions", function()
    local rendered = properties.render({
      title = "Living room",
      subtitle = "room",
      groups = {
        { id = "summary", title = "Summary", default_expanded = true, fields = {
          { label = "Name", value = "Living room" },
        } },
        { id = "geometry", title = "Geometry", fields = {
          { label = "Width", value = "5 m" },
          { label = "Depth", value = "4 m" },
        } },
        { id = "advanced", title = "Advanced", fields = {
          { label = "Stable ID", value = "room-living" },
        } },
      },
      diagnostics = {
        { severity = "warning", message = "Door swing is obstructed" },
      },
    }, 32, 4, {
      collapsed_sections = { geometry = false, advanced = true },
    })

    local sections = section_rows(rendered)
    assert_equal(true, sections.summary.item.expanded)
    assert_equal(true, sections.geometry.item.expanded)
    assert_equal(false, sections.advanced.item.expanded)
    assert_equal(true, sections.validation.item.expanded)
    assert_true(#rendered.lines > 4, "details must remain scrollable")
    assert_true(table.concat(rendered.lines, "\n"):find("Actions", 1, true) == nil)
    assert_true(rendered.lines[2]:find("╭", 1, true) ~= nil)
    assert_true(#rendered.highlights > 0)
  end)

  it("keeps each issue on one selectable row", function()
    local rendered = issues.render({
      counts = { errors = 1, warnings = 1 },
      rows = {
        { severity = "error", code = "ROOM_OVERLAP", message = "Rooms overlap", kind = "room", id = "room-a" },
        { severity = "warning", code = "DOOR_SWING", message = "Door is blocked", kind = "door", id = "door-a" },
      },
    }, 36, 2)
    assert_equal(3, #rendered.lines)
    assert_equal("ROOM_OVERLAP", rendered.row_map[2].code)
    assert_equal("DOOR_SWING", rendered.row_map[3].code)
    assert_true(#rendered.highlights >= 4)
  end)
end)
