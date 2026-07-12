local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
require("roomplan").setup({})

local controller = require("roomplan.controller")
local model = require("roomplan.model")
local session = assert(controller.init_source(nil, {
  path = assert(vim.env.ROOMPLAN_GUARD_PLAN),
  noninteractive = true,
}))
assert(controller.dispatch(session, {
  type = "add_room",
  room = model.new_room({
    id = "room-quit-guard",
    name = "Quit guard",
    origin_mm = { 0, 0 },
    size_mm = { 1000, 1000 },
  }),
}))
assert(vim.bo[session.guard_bufnr].modified)
