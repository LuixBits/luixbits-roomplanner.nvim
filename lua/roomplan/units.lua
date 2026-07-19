-- Exact metric input parsing for RoomPlan.
-- Stored values are integer millimetres; this module never converts user
-- decimals through binary floating point.

local M = {}

local HARD_MAX_ABS_MM = 2 ^ 50 - 1

M.HARD_MAX_ABS_MM = HARD_MAX_ABS_MM

local UNIT_POWER = {
  [""] = 0,
  mm = 0,
  cm = 1,
  m = 3,
}

local function failure(code, message, input) return nil, { code = code, message = message, input = input } end

local function trim_ascii(value) return (value:gsub("^[ \t\r\n]+", ""):gsub("[ \t\r\n]+$", "")) end

local function decimal_digits_to_number(digits, maximum)
  local value = 0
  local index = 1
  while index <= #digits do
    local digit = digits:byte(index) - 48
    if value > math.floor((maximum - digit) / 10) then return nil end
    value = value * 10 + digit
    index = index + 1
  end
  return value
end

-- Parse the intentionally small RoomPlan input grammar:
--   [+-]? DIGIT+ ('.' DIGIT+)? (mm|cm|m)?
-- Surrounding ASCII whitespace is allowed; internal whitespace and exponents
-- are deliberately rejected.
function M.parse(input, options)
  options = options or {}
  if type(input) ~= "string" then return failure("UNIT_INPUT_TYPE", "measurement must be entered as text", input) end
  local original = input
  input = trim_ascii(input)
  if input == "" then return failure("UNIT_EMPTY", "measurement is empty", original) end
  if #input > 1024 then
    return failure("UNIT_INPUT_LIMIT", "measurement exceeds the 1024 byte input limit", original)
  end

  local cursor = 1
  local sign = 1
  local first = input:sub(cursor, cursor)
  if first == "+" or first == "-" then
    if first == "-" then sign = -1 end
    cursor = cursor + 1
  end

  local integer_start = cursor
  while cursor <= #input do
    local byte = input:byte(cursor)
    if byte < 48 or byte > 57 then break end
    cursor = cursor + 1
  end
  if cursor == integer_start then
    return failure("UNIT_NUMBER_SYNTAX", "expected one or more digits before the decimal point", original)
  end
  local integer_digits = input:sub(integer_start, cursor - 1)

  local fraction_digits = ""
  if input:sub(cursor, cursor) == "." then
    cursor = cursor + 1
    local fraction_start = cursor
    while cursor <= #input do
      local byte = input:byte(cursor)
      if byte < 48 or byte > 57 then break end
      cursor = cursor + 1
    end
    if cursor == fraction_start then
      return failure("UNIT_NUMBER_SYNTAX", "expected one or more digits after the decimal point", original)
    end
    fraction_digits = input:sub(fraction_start, cursor - 1)
  end

  local suffix = input:sub(cursor)
  if suffix ~= "" and not suffix:match("^[A-Za-z]+$") then
    return failure("UNIT_SUFFIX_SYNTAX", "unit suffix must be adjacent ASCII letters (mm, cm, or m)", original)
  end
  suffix = suffix:lower()
  local unit_power = UNIT_POWER[suffix]
  if unit_power == nil then
    return failure("UNIT_UNSUPPORTED", "supported units are mm, cm, and m; no suffix also means mm", original)
  end

  local coefficient = (integer_digits .. fraction_digits):gsub("^0+", "")
  if coefficient == "" then coefficient = "0" end
  local shift = unit_power - #fraction_digits
  if shift < 0 then
    local discarded = -shift
    if discarded >= #coefficient then
      local required_zeroes = discarded - #coefficient
      if coefficient ~= "0" then
        return failure("UNIT_FRACTIONAL_MM", "measurement does not resolve to a whole millimetre", original)
      end
      coefficient = "0"
      shift = 0
    else
      local tail = coefficient:sub(#coefficient - discarded + 1)
      if not tail:match("^0+$") then
        return failure("UNIT_FRACTIONAL_MM", "measurement does not resolve to a whole millimetre", original)
      end
      coefficient = coefficient:sub(1, #coefficient - discarded)
      shift = 0
    end
  end
  if shift > 0 and coefficient ~= "0" then
    if #coefficient + shift > 32 then
      return failure("UNIT_RANGE", "measurement exceeds the supported millimetre range", original)
    end
    coefficient = coefficient .. string.rep("0", shift)
  end

  local maximum = options.max_abs
  if maximum == nil and type(options.max) == "number" then maximum = math.abs(options.max) end
  if maximum == nil and type(options.min) == "number" then
    maximum = math.abs(options.min)
  elseif type(maximum) == "number" and type(options.min) == "number" then
    maximum = math.max(maximum, math.abs(options.min))
  end
  if type(maximum) ~= "number" or maximum <= 0 or maximum > HARD_MAX_ABS_MM then
    maximum = HARD_MAX_ABS_MM
  else
    maximum = math.floor(maximum)
  end
  local magnitude = decimal_digits_to_number(coefficient, maximum)
  if magnitude == nil then
    return failure("UNIT_RANGE", "measurement exceeds the allowed millimetre range", original)
  end
  local value = sign * magnitude
  if value < 0 and options.allow_negative ~= true and not (type(options.min) == "number" and options.min < 0) then
    return failure("UNIT_NEGATIVE", "negative measurements are not allowed here", original)
  end
  if value == 0 and options.allow_zero ~= true and not (type(options.min) == "number" and options.min <= 0) then
    return failure("UNIT_ZERO", "zero is not allowed here", original)
  end
  if type(options.min) == "number" and value < options.min then
    return failure("UNIT_MIN", "measurement must be at least " .. tostring(options.min) .. " mm", original)
  end
  if type(options.max) == "number" and value > options.max then
    return failure("UNIT_MAX", "measurement must be at most " .. tostring(options.max) .. " mm", original)
  end
  return value
end

function M.parse_coordinate(input, options)
  options = options or {}
  local copied = {}
  for key, value in pairs(options) do
    copied[key] = value
  end
  copied.allow_negative = true
  copied.allow_zero = true
  return M.parse(input, copied)
end

function M.parse_dimension(input, options) return M.parse(input, options) end

function M.format_mm(value)
  if type(value) ~= "number" or value ~= math.floor(value) or math.abs(value) > HARD_MAX_ABS_MM then
    return nil, { code = "UNIT_VALUE", message = "millimetre value must be a safe integer" }
  end
  return string.format("%.0f mm", value)
end

-- Compact exact formatting intended for prompts and Details summaries.
function M.format_metric(value)
  if type(value) ~= "number" or value ~= math.floor(value) or math.abs(value) > HARD_MAX_ABS_MM then
    return nil, { code = "UNIT_VALUE", message = "millimetre value must be a safe integer" }
  end
  local sign = value < 0 and "-" or ""
  local magnitude = math.abs(value)
  if magnitude >= 1000 and magnitude % 1000 == 0 then
    return sign .. string.format("%.0f", magnitude / 1000) .. "m"
  elseif magnitude >= 1000 and magnitude % 100 == 0 then
    local whole = math.floor(magnitude / 1000)
    local tenths = math.floor((magnitude % 1000) / 100)
    return sign .. string.format("%.0f.%d", whole, tenths) .. "m"
  elseif magnitude >= 10 and magnitude % 10 == 0 then
    return sign .. string.format("%.0f", magnitude / 10) .. "cm"
  end
  return sign .. string.format("%.0f", magnitude) .. "mm"
end

return M
