-- Integer-safe numeric helpers used by roomplan's pure geometry modules.
-- This module intentionally has no dependency on Neovim or LuaJIT extensions.

local M = {}

M.MAX_SAFE_COORDINATE = 2 ^ 50
M.MAX_LOCAL_DIMENSION = 1000000000

function M.is_finite(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function M.is_integer(value)
  return M.is_finite(value) and value == math.floor(value)
end

function M.sign(value)
  if value < 0 then
    return -1
  elseif value > 0 then
    return 1
  end
  return 0
end

function M.clamp(value, minimum, maximum)
  if value < minimum then
    return minimum
  elseif value > maximum then
    return maximum
  end
  return value
end

-- Round to the nearest integer, resolving exact halves away from zero.
function M.round_half_away(value)
  if value < 0 then
    return -math.floor(-value + 0.5)
  end
  return math.floor(value + 0.5)
end

-- Convert an exact doubled-millimetre coordinate to the persisted integer
-- lattice. Returns the rounded millimetres and its signed residual in mm.
function M.from_doubled(value2)
  local rounded = M.round_half_away(value2 / 2)
  return rounded, rounded - value2 / 2
end

-- Deterministic grid rounding, including negative values and negative halves.
function M.round_to_grid(value, grid)
  if not M.is_integer(grid) or grid <= 0 then
    return nil, "grid must be a positive integer"
  end
  return M.round_half_away(value / grid) * grid
end

function M.local_epsilon(...)
  local scale = 1
  local values = { ... }
  local i
  for i = 1, #values do
    local value = values[i]
    if M.is_finite(value) and math.abs(value) > scale then
      scale = math.abs(value)
    end
  end
  local machine_scaled = 128 * 2 ^ -52 * scale
  return math.max(1e-7, machine_scaled)
end

function M.almost_equal(a, b, epsilon)
  epsilon = epsilon or M.local_epsilon(a, b)
  return math.abs(a - b) <= epsilon
end

return M
