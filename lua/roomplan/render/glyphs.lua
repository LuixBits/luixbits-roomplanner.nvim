-- Structural direction masks and complete one-cell glyph sets.

local M = {}

M.N = 1
M.E = 2
M.S = 4
M.W = 8

local function clone(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, child in pairs(value) do
    result[key] = clone(child)
  end
  return result
end

local UNICODE = {
  mode = "unicode",
  wall = {
    [0] = " ",
    [1] = "│",
    [2] = "─",
    [3] = "└",
    [4] = "│",
    [5] = "│",
    [6] = "┌",
    [7] = "├",
    [8] = "─",
    [9] = "┘",
    [10] = "─",
    [11] = "┴",
    [12] = "┐",
    [13] = "┤",
    [14] = "┬",
    [15] = "┼",
  },
  furniture_horizontal = "─",
  furniture_vertical = "│",
  furniture_corner_nw = "┌",
  furniture_corner_ne = "┐",
  furniture_corner_sw = "└",
  furniture_corner_se = "┘",
  furniture_marker = "■",
  door_horizontal = "─",
  door_vertical = "│",
  door_slash = "╱",
  door_backslash = "╲",
  door_hinge = "●",
  door_arc = "·",
  door_marker = "D",
  window_horizontal = "═",
  window_vertical = "║",
  window_marker = "W",
  outlet_marker = "○",
  outlet_wall_north = "◒",
  outlet_wall_east = "◖",
  outlet_wall_south = "◓",
  outlet_wall_west = "◗",
  grid = "·",
  error = "!",
  warning = "?",
  replacement = "?",
}

local ASCII = {
  mode = "ascii",
  wall = {
    [0] = " ",
    [1] = "|",
    [2] = "-",
    [3] = "+",
    [4] = "|",
    [5] = "|",
    [6] = "+",
    [7] = "+",
    [8] = "-",
    [9] = "+",
    [10] = "-",
    [11] = "+",
    [12] = "+",
    [13] = "+",
    [14] = "+",
    [15] = "+",
  },
  furniture_horizontal = "-",
  furniture_vertical = "|",
  furniture_corner_nw = "+",
  furniture_corner_ne = "+",
  furniture_corner_sw = "+",
  furniture_corner_se = "+",
  furniture_marker = "#",
  door_horizontal = "-",
  door_vertical = "|",
  door_slash = "/",
  door_backslash = "\\",
  door_hinge = "o",
  door_arc = ".",
  door_marker = "D",
  window_horizontal = "=",
  window_vertical = "|",
  window_marker = "W",
  outlet_marker = "O",
  outlet_wall_north = "v",
  outlet_wall_east = "<",
  outlet_wall_south = "^",
  outlet_wall_west = ">",
  grid = ".",
  error = "!",
  warning = "?",
  replacement = "?",
}

local REQUIRED = {
  "furniture_horizontal",
  "furniture_vertical",
  "furniture_corner_nw",
  "furniture_corner_ne",
  "furniture_corner_sw",
  "furniture_corner_se",
  "furniture_marker",
  "door_horizontal",
  "door_vertical",
  "door_slash",
  "door_backslash",
  "door_hinge",
  "door_arc",
  "door_marker",
  "window_horizontal",
  "window_vertical",
  "window_marker",
  "outlet_marker",
  "grid",
  "error",
  "warning",
  "replacement",
}

function M.builtin(mode)
  if mode == "ascii" then return clone(ASCII) end
  return clone(UNICODE)
end

function M.has(mask, bit) return mask % (bit * 2) >= bit end

function M.add(mask, bit)
  if M.has(mask, bit) then return mask end
  return mask + bit
end

local function fallback_width(text)
  -- This is intentionally conservative and is used only when a caller asks to
  -- validate without Neovim.  ASCII is exact; non-ASCII needs an injected
  -- strdisplaywidth-compatible function for an authoritative answer.
  if #text == 1 then return 1 end
  return nil
end

local function validate_character(value, path, width_fn)
  if type(value) ~= "string" or value == "" then return nil, path .. " must be a non-empty string" end
  local width = width_fn(value)
  if width ~= 1 then return nil, path .. " must occupy exactly one display cell" end
  return true
end

---Validate a complete glyph set atomically.
function M.validate(set, width_fn)
  if type(set) ~= "table" then return nil, "glyph set must be a table" end
  if type(set.wall) ~= "table" then return nil, "glyphs.wall must be a table" end
  width_fn = width_fn or fallback_width
  for mask = 0, 15 do
    local ok, err = validate_character(set.wall[mask], "glyphs.wall[" .. mask .. "]", width_fn)
    if not ok then return nil, err end
  end
  for i = 1, #REQUIRED do
    local key = REQUIRED[i]
    local ok, err = validate_character(set[key], "glyphs." .. key, width_fn)
    if not ok then return nil, err end
  end
  return clone(set)
end

---Resolve configured glyph mode.  Invalid Unicode/custom sets fall back as one
---atomic operation to the built-in ASCII set.
function M.resolve(mode, custom, width_fn)
  mode = mode or "auto"
  local candidate
  if custom ~= nil then
    candidate = custom
  elseif mode == "ascii" then
    candidate = ASCII
  else
    candidate = UNICODE
  end

  local validated, err = M.validate(candidate, width_fn)
  if validated then
    validated.mode = custom and "custom" or candidate.mode
    -- A custom set predates these optional directional glyphs. Keep such sets
    -- portable by filling only the new fields from ASCII; built-in Unicode
    -- still receives the half-circle variants above.
    local extras = custom and ASCII or (candidate.mode == "ascii" and ASCII or UNICODE)
    for _, key in ipairs({ "outlet_wall_north", "outlet_wall_east", "outlet_wall_south", "outlet_wall_west" }) do
      local value = validated[key] or extras[key]
      validated[key] = (width_fn or fallback_width)(value) == 1 and value or validated.outlet_marker
    end
    return validated, nil
  end

  local fallback, fallback_err = M.validate(ASCII, width_fn or function(value) return #value end)
  if not fallback then
    -- An injected width function that rejects ASCII indicates a broken display
    -- environment.  Return the known addressable set and retain both reasons.
    fallback = clone(ASCII)
    err = err .. "; ASCII validation also failed: " .. tostring(fallback_err)
  end
  fallback.mode = "ascii"
  return fallback, err
end

M.unicode = UNICODE
M.ascii = ASCII

return M
