-- User-facing screen directions. Persisted wall sides remain plan-coordinate
-- values; this module is the single conversion boundary for rotated views.

local viewport = require("roomplan.render.viewport")
local json = require("roomplan.codec.json")

local M = {}

local VECTORS = {
  north = { 0, 1 },
  east = { 1, 0 },
  south = { 0, -1 },
  west = { -1, 0 },
}

local SCREEN_RANK = { top = 1, right = 2, bottom = 3, left = 4 }

local function active_viewport(value)
  if type(value) ~= "table" then return nil end
  if value.rotation_quarters ~= nil then return value end
  if value.viewport then return value.viewport end
  if value.session then return value.session.viewport end
  return nil
end

function M.screen_side(side, value)
  local vector = VECTORS[side]
  if not vector then return tostring(side or "wall") end
  local dx, dy = viewport.world_delta_to_view(active_viewport(value), vector[1], vector[2])
  if math.abs(dx) > math.abs(dy) then return dx > 0 and "right" or "left" end
  return dy > 0 and "top" or "bottom"
end

function M.label(side, value)
  local label = M.screen_side(side, value)
  return label:sub(1, 1):upper() .. label:sub(2)
end

function M.choices(value)
  local result = {}
  for side in pairs(VECTORS) do
    local screen = M.screen_side(side, value)
    result[#result + 1] = { value = side, label = M.label(side, value), screen_side = screen }
  end
  table.sort(result, function(a, b) return SCREEN_RANK[a.screen_side] < SCREEN_RANK[b.screen_side] end)
  return result
end

function M.corner_label(corner, value)
  local x = corner and (corner:find("east", 1, true) and 1 or corner:find("west", 1, true) and -1) or 0
  local y = corner and (corner:find("north", 1, true) and 1 or corner:find("south", 1, true) and -1) or 0
  if x == 0 or y == 0 then return tostring(corner or "corner") end
  local dx, dy = viewport.world_delta_to_view(active_viewport(value), x, y)
  return (dy > 0 and "Top" or "Bottom") .. "-" .. (dx > 0 and "right" or "left")
end

function M.replace_cardinals(text, value)
  if text == nil then return nil end
  text = tostring(text)
  local replacements = {
    northwest = M.corner_label("northwest", value),
    northeast = M.corner_label("northeast", value),
    southwest = M.corner_label("southwest", value),
    southeast = M.corner_label("southeast", value),
    north = M.label("north", value),
    east = M.label("east", value),
    south = M.label("south", value),
    west = M.label("west", value),
  }
  for _, word in ipairs({ "northwest", "northeast", "southwest", "southeast", "north", "east", "south", "west" }) do
    text = text:gsub(word, replacements[word]:lower())
    text = text:gsub(word:sub(1, 1):upper() .. word:sub(2), replacements[word])
  end
  return text
end

function M.compass(north_deg, value, ascii)
  local angle = json.number_value(north_deg)
  if angle == nil then
    local arrows = ascii and { "^", ">", "v", "<" } or { "↑", "→", "↓", "←" }
    return "P" .. arrows[viewport.rotation(active_viewport(value)) + 1]
  end
  local radians = math.rad(angle)
  local dx, dy = viewport.world_delta_to_view(active_viewport(value), math.sin(radians), math.cos(radians))
  local visible = (math.deg(math.atan2(dx, dy)) % 360 + 360) % 360
  local index = math.floor((visible + 22.5) / 45) % 8 + 1
  local arrows = ascii and { "^", "/", ">", "\\", "v", "/", "<", "\\" }
    or { "↑", "↗", "→", "↘", "↓", "↙", "←", "↖" }
  return "N" .. arrows[index]
end

return M
