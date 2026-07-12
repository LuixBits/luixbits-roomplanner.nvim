local list = require("roomplan.ui.list")

local M = {}

local lines = {
  "roomplan.nvim canvas help",
  "=========================",
  "NAV: h/j/k/l cursor, <Enter> select, <Tab>/<S-Tab> cycle",
  "m MOVE mode, p PAN mode, <Esc> cancel/mode/deselect",
  "a add, e edit, d delete, y duplicate, r rotate furniture",
  "i inspector, o objects, v validation, [e/]e issues",
  "<C-h/j/k/l> fine move; u undo, <C-r>/U redo",
  "z+/z- zoom, zf fit, zh/zj/zk/zl pan",
  "gs toggle snapping, g! bypass next snap, s save, S Save As",
  "q hides the canvas but keeps the RoomPlan session alive",
  "",
  "Mappings are buffer-local and may be changed in setup().",
}

function M.open(session)
  return list.open(session, { role = "help", filetype = "help", lines = lines })
end

return M
