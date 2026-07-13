-- Canonical workspace configuration defaults. Keep this module pure so the
-- layout reducer can be tested without Neovim.

local defaults = {
  layout = "auto",
  left_width = 26,
  right_width = 30,
  navigator_visible = true,
  details_visible = false,
  wide_min_columns = 120,
  compact_max_columns = 89,
  compact_min_rows = 22,
  min_canvas_width = 55,
  min_canvas_height = 10,
  footer_height = 1,
  cycle_tabs = true,
  ascii = false,
  border = "rounded",
}

local function copy(value)
  local result = {}
  for key, item in pairs(value) do result[key] = item end
  return result
end

return {
  get = function() return copy(defaults) end,
}
