local M = {}
local mappings = require("roomplan.ui.mappings")

local function map(buf, lhs, rhs, desc, name)
  return mappings.set(buf, lhs, rhs, desc, name)
end

function M.apply(buf, session)
  local function controller(method, ...)
    local args = { ... }
    return function()
      local module = require("roomplan.controller")
      return module[method](session, unpack(args))
    end
  end
  map(buf, "q", controller("hide"), "Hide RoomPlan canvas", "hide")
  map(buf, "<CR>", controller("select_under_cursor"), "Select RoomPlan object", "select")
  map(buf, "<Tab>", controller("select_next", 1), "Next RoomPlan object", "select_next")
  map(buf, "<S-Tab>", controller("select_next", -1), "Previous RoomPlan object", "select_previous")
  map(buf, "m", controller("set_mode", "MOVE"), "Move selected RoomPlan object", "move_mode")
  map(buf, "p", controller("set_mode", "PAN"), "Pan RoomPlan viewport", "pan_mode")
  for _, entry in ipairs({ { "h", -1, 0 }, { "j", 0, -1 }, { "k", 0, 1 }, { "l", 1, 0 } }) do
    map(buf, entry[1], controller("direction", entry[2], entry[3], "normal"), "RoomPlan direction")
  end
  for _, entry in ipairs({ { "H", -1, 0 }, { "J", 0, -1 }, { "K", 0, 1 } }) do
    map(buf, entry[1], controller("direction", entry[2], entry[3], "coarse"), "RoomPlan coarse direction")
  end
  map(buf, "L", controller("direction", 1, 0, "coarse"), "RoomPlan coarse direction", "coarse_right")
  map(buf, "L", function()
    if session.mode == "NAV" and not session.shape_edit then
      return require("roomplan.controller").sun_study(session)
    end
    return require("roomplan.controller").direction(session, 1, 0, "coarse")
  end, "Open RoomPlan sun study or move right coarsely", "sun_study")
  map(buf, "<Space>", function()
    if session.sun_study and session.sun_study.viewing then
      return require("roomplan.controller").sun_toggle(session)
    end
    return false
  end, "Play or pause the visible RoomPlan sunlight study")
  for _, entry in ipairs({ { "<C-h>", -1, 0 }, { "<C-j>", 0, -1 }, { "<C-k>", 0, 1 }, { "<C-l>", 1, 0 } }) do
    map(buf, entry[1], controller("direction", entry[2], entry[3], "fine"), "RoomPlan fine direction")
  end
  map(buf, "a", controller("add_menu"), "Add RoomPlan object", "add")
  map(buf, "D", controller("add_door"), "Add RoomPlan door", "add_door")
  map(buf, "W", controller("add_window"), "Add RoomPlan window", "add_window")
  map(buf, "O", controller("add_outlet"), "Add RoomPlan outlet", "add_outlet")
  map(buf, "F", controller("add_furniture"), "Add RoomPlan furniture", "add_furniture")
  map(buf, "A", controller("align_room"), "Align selected RoomPlan room", "align")
  map(buf, "e", controller("edit_selected"), "Edit RoomPlan selection", "edit")
  map(buf, "r", controller("edit_selected_shape"), "Resize selected RoomPlan dimensions", "resize_dimensions")
  map(buf, "d", controller("delete_selected"), "Delete RoomPlan selection", "delete")
  map(buf, "y", controller("duplicate_selected"), "Duplicate RoomPlan selection", "duplicate")
  map(buf, "R", controller("rotate_selected"), "Rotate RoomPlan furniture", "rotate")
  map(buf, "i", controller("inspect"), "Toggle RoomPlan details", "inspector")
  map(buf, "o", controller("objects"), "RoomPlan objects", "objects")
  map(buf, "v", controller("validate", true), "Validate RoomPlan", "validate")
  map(buf, "<A-j>", controller("next_issue", 1), "Next RoomPlan issue", "next_issue")
  map(buf, "<A-k>", controller("next_issue", -1), "Previous RoomPlan issue", "previous_issue")
  map(buf, "u", controller("undo"), "Undo RoomPlan action", "undo")
  map(buf, "<C-r>", controller("redo"), "Redo RoomPlan action", "redo")
  map(buf, "U", controller("redo"), "Redo RoomPlan action")
  map(buf, ".", controller("zoom", "in"), "Zoom RoomPlan in", "zoom_in")
  map(buf, ",", controller("zoom", "out"), "Zoom RoomPlan out", "zoom_out")
  map(buf, "<A-l>", controller("rotate_view", "clockwise"), "Rotate RoomPlan view clockwise", "rotate_view_clockwise")
  map(buf, "<A-h>", controller("rotate_view", "counterclockwise"),
    "Rotate RoomPlan view counter-clockwise", "rotate_view_counterclockwise")
  map(buf, "g0", controller("rotate_view", "reset"), "Reset RoomPlan plan view/up", "reset_view")
  map(buf, "f", controller("fit"), "Fit RoomPlan", "fit")
  map(buf, "M", controller("toggle_minimap"), "Toggle RoomPlan minimap", "toggle_minimap")
  map(buf, "t", controller("set_detail_level", "cycle"), "Cycle RoomPlan canvas detail", "cycle_detail_level")
  map(buf, "zf", controller("fit"), "Fit RoomPlan")
  for _, entry in ipairs({ { "zh", -1, 0 }, { "zj", 0, -1 }, { "zk", 0, 1 }, { "zl", 1, 0 } }) do
    map(buf, entry[1], controller("pan", entry[2], entry[3]), "Pan RoomPlan viewport")
  end
  map(buf, "gs", controller("toggle_snap"), "Toggle RoomPlan snapping", "toggle_snap")
  map(buf, "g!", controller("bypass_snap"), "Bypass next RoomPlan snap", "bypass_snap")
  map(buf, "s", controller("save"), "Apply RoomPlan resize and save", "save")
  map(buf, "S", controller("save_as_prompt"), "Save RoomPlan As", "save_as")
  map(buf, "?", function() require("roomplan.ui.help").open(session) end, "RoomPlan help", "help")
  map(buf, "<Esc>", controller("escape"), "Cancel RoomPlan mode", "escape")
end

return M
