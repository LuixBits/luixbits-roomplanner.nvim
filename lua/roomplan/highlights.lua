local M = {}

local links = {
  RoomPlanWall = "LineNr",
  RoomPlanDoor = "Special",
  RoomPlanWindow = "Type",
  RoomPlanOutlet = "Constant",
  RoomPlanFurniture = "Identifier",
  RoomPlanRoomLabel = "Title",
  RoomPlanFurnitureLabel = "Normal",
  RoomPlanSelected = "Visual",
  RoomPlanError = "DiagnosticError",
  RoomPlanWarning = "DiagnosticWarn",
  RoomPlanGrid = "NonText",
  RoomPlanStatus = "StatusLine",
  RoomPlanMuted = "Comment",
  RoomPlanCompass = "Special",
  RoomPlanWorkspaceTitle = "Title",
  RoomPlanWorkspaceActiveTitle = "Title",
  RoomPlanWorkspaceInactiveTitle = "Comment",
  RoomPlanWorkspaceBorder = "WinSeparator",
  RoomPlanWorkspaceActiveBorder = "Special",
  RoomPlanWorkspaceCursorLine = "CursorLine",
  RoomPlanWorkspaceSelected = "Visual",
  RoomPlanWorkspaceMuted = "Comment",
  RoomPlanWorkspaceStatus = "StatusLine",
  RoomPlanWorkspaceKey = "Special",
  RoomPlanWorkspaceValue = "String",
  RoomPlanWorkspaceRoom = "Function",
  RoomPlanWorkspaceDoor = "Special",
  RoomPlanWorkspaceWindow = "Type",
  RoomPlanWorkspaceOutlet = "Constant",
  RoomPlanWorkspaceFurniture = "Identifier",
  RoomPlanWorkspacePlan = "Title",
  RoomPlanWorkspaceSection = "Title",
  RoomPlanWorkspaceError = "DiagnosticError",
  RoomPlanWorkspaceWarning = "DiagnosticWarn",
  RoomPlanWorkspaceInfo = "DiagnosticInfo",
}

function M.setup()
  for name, link in pairs(links) do
    vim.api.nvim_set_hl(0, name, { default = true, link = link })
  end
end

return M
