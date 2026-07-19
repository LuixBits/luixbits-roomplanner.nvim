local h = require("tests.harness")

local highlights = require("roomplan.highlights")

local source_groups = {
  "Normal",
  "NormalFloat",
  "Pmenu",
  "CursorLine",
  "StatusLine",
  "Comment",
  "DiagnosticWarn",
  "WarningMsg",
  "DiagnosticError",
  "ErrorMsg",
  "Special",
  "Search",
  "Function",
  "DiagnosticInfo",
  "Type",
  "Identifier",
  "IncSearch",
}

local generated_groups = {
  "RoomPlanSunWall",
  "RoomPlanSunWindow",
  "RoomPlanSunlight1",
  "RoomPlanSunlight2",
  "RoomPlanSunlight3",
  "RoomPlanSunlight4",
  "RoomPlanSunlight5",
  "RoomPlanMinimapRoom",
  "RoomPlanMinimapViewport",
}

local function definition(name, resolve) return vim.api.nvim_get_hl(0, { name = name, link = resolve ~= true }) end

local function clear_groups(groups)
  for _, name in ipairs(groups) do
    vim.api.nvim_set_hl(0, name, {})
  end
end

describe("colorscheme-linked highlights", function()
  it("derives generated accents from the theme and preserves RoomPlan overrides", function()
    local saved, background = {}, vim.o.background
    for _, name in ipairs(vim.list_extend(vim.deepcopy(source_groups), generated_groups)) do
      saved[name] = definition(name)
    end
    local ok, err = xpcall(function()
      vim.o.background = "dark"
      vim.api.nvim_set_hl(0, "Normal", { bg = "#101820", fg = "#DDEEFF" })
      vim.api.nvim_set_hl(0, "DiagnosticWarn", { fg = "#E0A020" })
      vim.api.nvim_set_hl(0, "WarningMsg", { fg = "#E0A020" })
      vim.api.nvim_set_hl(0, "DiagnosticError", { fg = "#C04020" })
      vim.api.nvim_set_hl(0, "Function", { fg = "#4080C0" })
      vim.api.nvim_set_hl(0, "IncSearch", { bg = "#B06020", fg = "#101820" })
      clear_groups(generated_groups)
      highlights.setup()

      h.eq(0xE0A020, definition("RoomPlanSunWindow", true).fg)
      h.eq(0xC04020, definition("RoomPlanSunWall", true).fg)
      h.eq(0xB06020, definition("RoomPlanMinimapViewport", true).fg)
      local bands = {}
      for index = 1, 5 do
        bands[definition("RoomPlanSunlight" .. index, true).bg] = true
      end
      local band_count = 0
      for _ in pairs(bands) do
        band_count = band_count + 1
      end
      h.eq(5, band_count)

      local dark_band = definition("RoomPlanSunlight1", true).bg
      local first_room_tint = definition("RoomPlanMinimapRoom", true).bg
      vim.o.background = "light"
      vim.api.nvim_set_hl(0, "Function", { fg = "#A040C0" })
      clear_groups(generated_groups)
      highlights.setup()
      h.truthy(dark_band ~= definition("RoomPlanSunlight1", true).bg)
      h.truthy(first_room_tint ~= definition("RoomPlanMinimapRoom", true).bg)

      vim.api.nvim_set_hl(0, "Normal", { fg = "#DDEEFF" })
      vim.api.nvim_set_hl(0, "NormalFloat", { bg = "#202830", fg = "#DDEEFF" })
      clear_groups(generated_groups)
      highlights.setup()
      h.truthy(definition("RoomPlanSunlight1", true).bg)
      h.truthy(definition("RoomPlanMinimapRoom", true).bg)

      vim.api.nvim_set_hl(0, "RoomPlanSunWall", { fg = "#123456" })
      vim.api.nvim_set_hl(0, "RoomPlanSunlight3", { bg = "#654321" })
      vim.api.nvim_set_hl(0, "RoomPlanMinimapViewport", { fg = "#ABCDEF", bold = true })
      highlights.setup()
      h.eq(0x123456, definition("RoomPlanSunWall", true).fg)
      h.eq(0x654321, definition("RoomPlanSunlight3", true).bg)
      h.eq(0xABCDEF, definition("RoomPlanMinimapViewport", true).fg)
    end, debug.traceback)
    vim.o.background = background
    for name, value in pairs(saved) do
      vim.api.nvim_set_hl(0, name, value)
    end
    if not ok then error(err, 0) end
  end)
end)
