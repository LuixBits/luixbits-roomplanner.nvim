local M = {}

local links = {
  RoomPlanWall = "LineNr",
  RoomPlanDoor = "Special",
  RoomPlanFurniture = "Identifier",
  RoomPlanRoomLabel = "Title",
  RoomPlanFurnitureLabel = "Normal",
  RoomPlanSelected = "Visual",
  RoomPlanError = "DiagnosticError",
  RoomPlanWarning = "DiagnosticWarn",
  RoomPlanGrid = "NonText",
  RoomPlanStatus = "StatusLine",
  RoomPlanMuted = "Comment",
}

function M.setup()
  for name, link in pairs(links) do
    vim.api.nvim_set_hl(0, name, { default = true, link = link })
  end
end

return M
