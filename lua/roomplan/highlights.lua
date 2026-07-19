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

local function highlight(name)
  local ok, value = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  return ok and type(value) == "table" and value or {}
end

local function first_color(groups, attributes, different_from)
  for _, name in ipairs(groups) do
    local definition = highlight(name)
    for _, attribute in ipairs(attributes) do
      local value = definition[attribute]
      if type(value) == "number" and value ~= different_from then return value end
    end
  end
end

local function theme()
  local normal = highlight("Normal")
  local foreground = normal.fg or first_color({ "NormalFloat", "StatusLine", "Comment" }, { "fg" })
  local background = normal.bg or first_color({ "NormalFloat", "Pmenu", "CursorLine", "StatusLine" }, { "bg" })
  local sun_start = first_color({ "DiagnosticWarn", "WarningMsg", "Special", "Search" }, { "fg", "bg" }) or foreground
  local sun_finish = first_color(
    { "WarningMsg", "DiagnosticError", "ErrorMsg", "Special", "IncSearch" },
    { "fg", "bg" },
    sun_start
  ) or sun_start
  return {
    foreground = foreground,
    background = background,
    sun_start = sun_start,
    sun_finish = sun_finish,
    minimap_room = first_color({ "Function", "DiagnosticInfo", "Type", "Identifier" }, { "fg", "bg" }) or foreground,
    minimap_viewport = first_color({ "IncSearch", "Search", "DiagnosticWarn", "WarningMsg" }, { "bg", "fg" })
      or sun_start
      or foreground,
  }
end

local function blend(background, target, amount)
  local br, bg, bb = rgb(background)
  local tr, tg, tb = rgb(target)
  if not tr then return nil end
  if not br then return string.format("#%06x", target) end
  local function channel(base, top) return math.floor(base + (top - base) * amount + 0.5) end
  return string.format("#%02x%02x%02x", channel(br, tr), channel(bg, tg), channel(bb, tb))
end

local function interpolate(first, last, amount)
  local fr, fg, fb = rgb(first)
  local lr, lg, lb = rgb(last)
  if not fr then return last end
  if not lr then return first end
  local function channel(start, finish) return math.floor(start + (finish - start) * amount + 0.5) end
  return channel(fr, lr) * 65536 + channel(fg, lg) * 256 + channel(fb, lb)
end

local function define_default(name, definition)
  local value = { default = true }
  for key, field in pairs(definition) do
    if field ~= nil then value[key] = field end
  end
  vim.api.nvim_set_hl(0, name, value)
end

function M.tint(value, light_amount, dark_amount)
  local target = type(value) == "number" and value
    or type(value) == "string" and value:match("^#%x%x%x%x%x%x$") and tonumber(value:sub(2), 16)
  local colors = theme()
  return {
    bg = blend(colors.background, target, vim.o.background == "light" and light_amount or dark_amount),
    fg = colors.foreground,
  }
end

function M.setup()
  local colors = theme()
  local light_amounts = { 0.18, 0.25, 0.32, 0.39, 0.46 }
  local dark_amounts = { 0.24, 0.34, 0.44, 0.54, 0.64 }
  for index = 1, 5 do
    local target = interpolate(colors.sun_start, colors.sun_finish, (index - 1) / 4)
    local amount = vim.o.background == "light" and light_amounts[index] or dark_amounts[index]
    if target then
      define_default("RoomPlanSunlight" .. index, {
        bg = blend(colors.background, target, amount),
        fg = colors.foreground,
      })
    else
      define_default("RoomPlanSunlight" .. index, { link = "Visual" })
    end
  end
  define_default(
    "RoomPlanSunWall",
    colors.sun_finish and { fg = colors.sun_finish, bold = true } or { link = "DiagnosticWarn" }
  )
  define_default(
    "RoomPlanSunWindow",
    colors.sun_start and { fg = colors.sun_start, bold = true } or { link = "DiagnosticWarn" }
  )
  local minimap_room = M.tint(colors.minimap_room, 0.12, 0.20)
  define_default("RoomPlanMinimapRoom", minimap_room.bg and minimap_room or { link = "Function" })
  local minimap_viewport = M.tint(colors.minimap_viewport, 0.22, 0.32)
  if minimap_viewport.bg then
    minimap_viewport.fg = colors.minimap_viewport or minimap_viewport.fg
    minimap_viewport.bold = true
  end
  define_default("RoomPlanMinimapViewport", minimap_viewport.bg and minimap_viewport or { link = "IncSearch" })
  for name, link in pairs(links) do
    define_default(name, { link = link })
  end
end

return M
