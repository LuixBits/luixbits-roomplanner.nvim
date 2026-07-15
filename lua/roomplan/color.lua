-- Pure palette and persisted color semantics. Plan colors are canonical
-- #RRGGBB values; "auto" inherits the active colorscheme.

local M = {}

local PALETTE = {
  { value = "auto", label = "Theme default" },
  { value = "#E06C75", label = "Red" },
  { value = "#D19A66", label = "Orange" },
  { value = "#E5C07B", label = "Yellow" },
  { value = "#98C379", label = "Green" },
  { value = "#56B6C2", label = "Cyan" },
  { value = "#61AFEF", label = "Blue" },
  { value = "#C678DD", label = "Purple" },
  { value = "#FF75A0", label = "Pink" },
  { value = "#A97954", label = "Brown" },
  { value = "#7F848E", label = "Gray" },
  { value = "#E6E6E6", label = "Light" },
}

function M.normalize(value)
  if value == "auto" then return value end
  if type(value) ~= "string" or not value:match("^#%x%x%x%x%x%x$") then
    return nil, "must be 'auto' or a six-digit hexadecimal color"
  end
  return value:upper()
end

function M.resolve(value)
  local normalized = M.normalize(value)
  return normalized ~= "auto" and normalized or nil
end

function M.choices(current)
  local result = {}
  local current_value = M.normalize(current)
  local current_found = false
  for index, entry in ipairs(PALETTE) do
    if entry.value == current_value then current_found = true end
    result[index] = {
      value = entry.value,
      label = entry.label,
      description = entry.value ~= "auto" and entry.value or "Use the active colorscheme",
    }
  end
  if current_value and not current_found then
    result[#result + 1] = { value = current_value, label = "Custom", description = current_value }
  end
  return result
end

function M.label(value)
  local normalized = M.normalize(value)
  if not normalized or normalized == "auto" then return "Theme default" end
  for _, entry in ipairs(PALETTE) do
    if entry.value == normalized then return entry.label .. " " .. normalized end
  end
  return normalized
end

return M
