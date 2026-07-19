local M = {}

local links = {
  RoomPlanWall = "LineNr",
  RoomPlanDoor = "Special",
  RoomPlanWindow = "Type",
  RoomPlanSunWall = "DiagnosticWarn",
  RoomPlanSunWindow = "DiagnosticWarn",
  RoomPlanOutlet = "Constant",
  RoomPlanFurniture = "Identifier",
  RoomPlanRoomLabel = "Title",
  RoomPlanFurnitureLabel = "Normal",
  RoomPlanPreview = "DiffAdd",
  RoomPlanSelected = "Visual",
  RoomPlanSnap = "DiagnosticInfo",
  RoomPlanSnapOverlap = "IncSearch",
  RoomPlanError = "DiagnosticError",
  RoomPlanWarning = "DiagnosticWarn",
  RoomPlanGrid = "NonText",
  RoomPlanStatus = "StatusLine",
  RoomPlanActions = "StatusLine",
  RoomPlanEmptyTitle = "Title",
  RoomPlanChrome = "Comment",
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
  RoomPlanMinimapWall = "Function",
  RoomPlanMinimapBorder = "Special",
  RoomPlanMinimapTitle = "Title",
}

local function rgb(value)
  if type(value) ~= "number" then return nil end
  return math.floor(value / 65536) % 256, math.floor(value / 256) % 256, value % 256
end

local function blend(background, target, amount)
  local br, bg, bb = rgb(background)
  local tr, tg, tb = rgb(target)
  if not br then return string.format("#%06x", target) end
  local function channel(base, top) return math.floor(base + (top - base) * amount + 0.5) end
  return string.format("#%02x%02x%02x", channel(br, tr), channel(bg, tg), channel(bb, tb))
end

function M.setup()
  for name, link in pairs(links) do
    vim.api.nvim_set_hl(0, name, { default = true, link = link })
  end
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local background = normal.bg or (vim.o.background == "light" and 0xffffff or 0x101010)
  local targets = { 0xffed72, 0xffd54f, 0xffb43b, 0xff922b, 0xf76707 }
  for index, target in ipairs(targets) do
    vim.api.nvim_set_hl(0, "RoomPlanSunlight" .. index, {
      bg = blend(background, target, vim.o.background == "light" and 0.36 or 0.48),
      fg = normal.fg,
    })
  end
  vim.api.nvim_set_hl(0, "RoomPlanSunWall", { fg = "#ffb43b", bold = true })
  vim.api.nvim_set_hl(0, "RoomPlanSunWindow", { fg = "#ffed72", bold = true })
  vim.api.nvim_set_hl(0, "RoomPlanMinimapRoom", {
    bg = blend(background, 0x61afef, vim.o.background == "light" and 0.12 or 0.20),
    fg = normal.fg,
  })
  vim.api.nvim_set_hl(0, "RoomPlanMinimapViewport", {
    bg = blend(background, 0xffb43b, vim.o.background == "light" and 0.22 or 0.32),
    fg = "#ffb43b",
    bold = true,
  })
end

return M
