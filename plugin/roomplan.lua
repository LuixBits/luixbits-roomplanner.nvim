if vim.g.loaded_roomplan == 1 then return end
vim.g.loaded_roomplan = 1

require("roomplan.commands").register()
