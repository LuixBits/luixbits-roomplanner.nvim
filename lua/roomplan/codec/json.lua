-- roomplan.nvim strict JSON codec.
--
-- This module deliberately does not use vim.json: RoomPlan supports Neovim
-- versions whose encoders cannot provide the type and ordering guarantees the
-- file format needs.  Decoded objects, arrays, nulls, and numbers are tagged so
-- that JSON type distinctions survive model copies and history snapshots.

local M = {}

local OBJECT_MT = { __roomplan_json_kind = "object" }
local ARRAY_MT = { __roomplan_json_kind = "array" }
local NULL_MT = { __roomplan_json_kind = "null" }
local DECIMAL_MT = { __roomplan_json_kind = "decimal" }

local NULL = setmetatable({}, NULL_MT)

local HARD_LIMITS = {
  max_bytes = 10 * 1024 * 1024,
  max_depth = 64,
  max_values = 100000,
  max_string_bytes = 10 * 1024 * 1024,
  max_number_bytes = 1024,
  max_abs_exponent = 1000000,
}

M.null = NULL

local function raw_kind(value)
  local mt = getmetatable(value)
  if mt == OBJECT_MT then
    return "object"
  elseif mt == ARRAY_MT then
    return "array"
  elseif mt == NULL_MT then
    return "null"
  elseif mt == DECIMAL_MT then
    return "decimal"
  end
  return nil
end

function M.is_object(value) return raw_kind(value) == "object" end

function M.is_array(value) return raw_kind(value) == "array" end

function M.is_null(value) return value == NULL end

function M.is_decimal(value) return raw_kind(value) == "decimal" end

function M.object(value)
  value = value or {}
  if type(value) ~= "table" then error("JSON object storage must be a table", 2) end
  if getmetatable(value) ~= nil and getmetatable(value) ~= OBJECT_MT then
    error("JSON object storage already has a metatable", 2)
  end
  return setmetatable(value, OBJECT_MT)
end

function M.array(value)
  value = value or {}
  if type(value) ~= "table" then error("JSON array storage must be a table", 2) end
  if getmetatable(value) ~= nil and getmetatable(value) ~= ARRAY_MT then
    error("JSON array storage already has a metatable", 2)
  end
  return setmetatable(value, ARRAY_MT)
end

local function strip_leading_zeroes(digits)
  local stripped = digits:match("^0*(%d+)$")
  return stripped or "0"
end

local function normalize_decimal(sign, coefficient, exponent)
  coefficient = strip_leading_zeroes(coefficient)
  if coefficient == "0" then return 1, "0", 0 end
  while #coefficient > 1 and coefficient:sub(-1) == "0" do
    coefficient = coefficient:sub(1, -2)
    exponent = exponent + 1
  end
  return sign < 0 and -1 or 1, coefficient, exponent
end

function M.decimal(sign, coefficient, exponent)
  if sign ~= 1 and sign ~= -1 then error("decimal sign must be 1 or -1", 2) end
  if type(coefficient) ~= "string" or not coefficient:match("^%d+$") then
    error("decimal coefficient must contain ASCII digits", 2)
  end
  if #coefficient > HARD_LIMITS.max_number_bytes then error("decimal coefficient exceeds the hard byte limit", 2) end
  if type(exponent) ~= "number" or exponent ~= math.floor(exponent) then
    error("decimal exponent must be an integer", 2)
  end
  if math.abs(exponent) > HARD_LIMITS.max_abs_exponent then error("decimal exponent exceeds the hard limit", 2) end
  sign, coefficient, exponent = normalize_decimal(sign, coefficient, exponent)
  if math.abs(exponent) > HARD_LIMITS.max_abs_exponent then
    error("normalized decimal exponent exceeds the hard limit", 2)
  end
  return setmetatable({ sign = sign, coefficient = coefficient, exponent = exponent }, DECIMAL_MT)
end

function M.decimal_parts(value)
  if not M.is_decimal(value) then return nil end
  return value.sign, value.coefficient, value.exponent
end

---Create the codec's exact decimal representation from ordinary decimal text.
---Whole values remain ordinary safe Lua integers, matching decoded JSON.
function M.decimal_from_string(value)
  if type(value) ~= "string" then return nil, "expected decimal text" end
  value = value:match("^%s*(.-)%s*$")
  local mantissa, exponent_text = value:match("^(.-)[eE]([+-]?%d+)$")
  if not mantissa then
    if value:find("[eE]") then return nil, "expected a decimal number" end
    mantissa, exponent_text = value, "0"
  end
  local sign_text = mantissa:sub(1, 1)
  if sign_text == "+" or sign_text == "-" then
    mantissa = mantissa:sub(2)
  else
    sign_text = ""
  end
  local whole, fraction
  if mantissa:match("^%d+$") then
    whole, fraction = mantissa, ""
  else
    whole, fraction = mantissa:match("^(%d*)%.(%d+)$")
    if whole == "" then whole = "0" end
  end
  if not whole then return nil, "expected a decimal number" end
  local exponent = tonumber(exponent_text)
  if not exponent or math.abs(exponent) > HARD_LIMITS.max_abs_exponent then
    return nil, "decimal exponent exceeds the hard limit"
  end
  local coefficient = whole .. fraction
  exponent = exponent - #fraction
  local sign = sign_text == "-" and -1 or 1
  local decimal = M.decimal(sign, coefficient, exponent)
  local integer = nil
  if decimal.exponent >= 0 and #decimal.coefficient + decimal.exponent <= 15 then
    integer = tonumber(decimal.coefficient) * (10 ^ decimal.exponent) * decimal.sign
  end
  if integer and integer == math.floor(integer) and math.abs(integer) <= 9007199254740991 then return integer end
  return decimal
end

---Convert a tagged JSON decimal or finite Lua number for calculations.
function M.number_value(value)
  if type(value) == "number" then
    if value == value and value ~= math.huge and value ~= -math.huge then return value end
    return nil
  end
  if not M.is_decimal(value) then return nil end
  local sign, coefficient, exponent = M.decimal_parts(value)
  if #coefficient > 32 or math.abs(exponent) > 308 then return nil end
  local converted = tonumber(coefficient)
  if not converted then return nil end
  converted = sign * converted * (10 ^ exponent)
  if converted ~= converted or converted == math.huge or converted == -math.huge then return nil end
  return converted
end

local function effective_limit(options, name)
  local hard = HARD_LIMITS[name]
  local requested = options and options[name]
  if type(requested) ~= "number" or requested < 1 then return hard end
  requested = math.floor(requested)
  if requested > hard then return hard end
  return requested
end

local function utf8_error_position(text)
  local index = 1
  local length = #text
  while index <= length do
    local first = text:byte(index)
    if first < 0x80 then
      index = index + 1
    else
      local count
      local minimum
      local codepoint
      if first >= 0xC2 and first <= 0xDF then
        count, minimum, codepoint = 2, 0x80, first - 0xC0
      elseif first >= 0xE0 and first <= 0xEF then
        count, minimum, codepoint = 3, 0x800, first - 0xE0
      elseif first >= 0xF0 and first <= 0xF4 then
        count, minimum, codepoint = 4, 0x10000, first - 0xF0
      else
        return index, "invalid UTF-8 leading byte"
      end
      if index + count - 1 > length then return index, "truncated UTF-8 sequence" end
      local cursor = index + 1
      while cursor < index + count do
        local byte = text:byte(cursor)
        if byte < 0x80 or byte > 0xBF then return cursor, "invalid UTF-8 continuation byte" end
        codepoint = codepoint * 64 + byte - 0x80
        cursor = cursor + 1
      end
      if codepoint < minimum or codepoint > 0x10FFFF or (codepoint >= 0xD800 and codepoint <= 0xDFFF) then
        return index, "invalid UTF-8 code point"
      end
      index = index + count
    end
  end
  return nil
end

function M.valid_utf8(text)
  if type(text) ~= "string" then return false, 1, "expected a string" end
  local position, message = utf8_error_position(text)
  if position then return false, position, message end
  return true
end

local function location(text, position)
  local line = 1
  local column = 1
  local cursor = 1
  while cursor < position and cursor <= #text do
    if text:byte(cursor) == 10 then
      line = line + 1
      column = 1
    else
      column = column + 1
    end
    cursor = cursor + 1
  end
  return line, column
end

local function decode_error(state, code, message, position)
  position = position or state.position
  local line, column = location(state.text, position)
  return {
    code = code,
    message = message,
    offset = position,
    byte_offset = position - 1,
    line = line,
    column = column,
  }
end

local function encode_codepoint(codepoint)
  if codepoint <= 0x7F then
    return string.char(codepoint)
  elseif codepoint <= 0x7FF then
    return string.char(0xC0 + math.floor(codepoint / 0x40), 0x80 + codepoint % 0x40)
  elseif codepoint <= 0xFFFF then
    return string.char(
      0xE0 + math.floor(codepoint / 0x1000),
      0x80 + math.floor(codepoint / 0x40) % 0x40,
      0x80 + codepoint % 0x40
    )
  end
  return string.char(
    0xF0 + math.floor(codepoint / 0x40000),
    0x80 + math.floor(codepoint / 0x1000) % 0x40,
    0x80 + math.floor(codepoint / 0x40) % 0x40,
    0x80 + codepoint % 0x40
  )
end

local HEX = {}
do
  local index = 0
  while index <= 9 do
    HEX[string.char(48 + index)] = index
    index = index + 1
  end
  index = 0
  while index <= 5 do
    HEX[string.char(65 + index)] = 10 + index
    HEX[string.char(97 + index)] = 10 + index
    index = index + 1
  end
end

local function read_hex4(state, position)
  if position + 3 > state.length then
    return nil, decode_error(state, "JSON_INVALID_UNICODE_ESCAPE", "incomplete Unicode escape", position)
  end
  local value = 0
  local cursor = position
  while cursor < position + 4 do
    local digit = HEX[state.text:sub(cursor, cursor)]
    if digit == nil then
      return nil,
        decode_error(
          state,
          "JSON_INVALID_UNICODE_ESCAPE",
          "Unicode escape contains a non-hexadecimal character",
          cursor
        )
    end
    value = value * 16 + digit
    cursor = cursor + 1
  end
  return value
end

local ESCAPES = {
  ['"'] = '"',
  ["\\"] = "\\",
  ["/"] = "/",
  b = "\b",
  f = "\f",
  n = "\n",
  r = "\r",
  t = "\t",
}

local function parse_string(state)
  local start = state.position
  state.position = state.position + 1 -- opening quote
  local pieces = {}
  local piece_bytes = 0
  local raw_start = state.position

  local function append(piece)
    piece_bytes = piece_bytes + #piece
    if piece_bytes > state.max_string_bytes then
      return nil, decode_error(state, "JSON_STRING_LIMIT", "decoded string exceeds the byte limit", state.position)
    end
    pieces[#pieces + 1] = piece
    return true
  end

  while state.position <= state.length do
    local byte = state.text:byte(state.position)
    if byte == 34 then
      if state.position > raw_start then
        local ok, err = append(state.text:sub(raw_start, state.position - 1))
        if not ok then return nil, err end
      end
      state.position = state.position + 1
      return table.concat(pieces)
    elseif byte == 92 then
      if state.position > raw_start then
        local ok, err = append(state.text:sub(raw_start, state.position - 1))
        if not ok then return nil, err end
      end
      local escape_position = state.position
      state.position = state.position + 1
      if state.position > state.length then
        return nil, decode_error(state, "JSON_UNTERMINATED_STRING", "unterminated escape sequence", escape_position)
      end
      local escape = state.text:sub(state.position, state.position)
      if escape == "u" then
        local codepoint, err = read_hex4(state, state.position + 1)
        if not codepoint then return nil, err end
        state.position = state.position + 5
        if codepoint >= 0xD800 and codepoint <= 0xDBFF then
          if state.text:sub(state.position, state.position + 1) ~= "\\u" then
            return nil,
              decode_error(
                state,
                "JSON_INVALID_SURROGATE",
                "high surrogate is not followed by a low surrogate",
                escape_position
              )
          end
          local low
          low, err = read_hex4(state, state.position + 2)
          if not low then return nil, err end
          if low < 0xDC00 or low > 0xDFFF then
            return nil,
              decode_error(
                state,
                "JSON_INVALID_SURROGATE",
                "high surrogate is followed by an invalid low surrogate",
                state.position
              )
          end
          codepoint = 0x10000 + (codepoint - 0xD800) * 0x400 + (low - 0xDC00)
          state.position = state.position + 6
        elseif codepoint >= 0xDC00 and codepoint <= 0xDFFF then
          return nil, decode_error(state, "JSON_INVALID_SURROGATE", "unpaired low surrogate", escape_position)
        end
        local ok
        ok, err = append(encode_codepoint(codepoint))
        if not ok then return nil, err end
      else
        local replacement = ESCAPES[escape]
        if replacement == nil then
          return nil,
            decode_error(state, "JSON_INVALID_ESCAPE", "invalid JSON escape '\\" .. escape .. "'", escape_position)
        end
        local ok, err = append(replacement)
        if not ok then return nil, err end
        state.position = state.position + 1
      end
      raw_start = state.position
    elseif byte < 32 then
      return nil, decode_error(state, "JSON_CONTROL_IN_STRING", "unescaped control character in string", state.position)
    else
      state.position = state.position + 1
    end
  end
  return nil, decode_error(state, "JSON_UNTERMINATED_STRING", "unterminated string", start)
end

local function skip_whitespace(state)
  while state.position <= state.length do
    local byte = state.text:byte(state.position)
    if byte == 32 or byte == 9 or byte == 10 or byte == 13 then
      state.position = state.position + 1
    else
      return
    end
  end
end

local function decimal_from_components(negative, integer, fraction, exponent_sign, exponent_digits)
  local exponent = 0
  if exponent_digits and exponent_digits ~= "" then
    local cursor = 1
    while cursor <= #exponent_digits do
      exponent = exponent * 10 + exponent_digits:byte(cursor) - 48
      cursor = cursor + 1
    end
    if exponent_sign == "-" then exponent = -exponent end
  end
  local coefficient = integer .. (fraction or "")
  exponent = exponent - #(fraction or "")
  local sign = negative and -1 or 1
  sign, coefficient, exponent = normalize_decimal(sign, coefficient, exponent)
  return setmetatable({ sign = sign, coefficient = coefficient, exponent = exponent }, DECIMAL_MT)
end

local function parse_number(state)
  local start = state.position
  local negative = false
  if state.text:sub(state.position, state.position) == "-" then
    negative = true
    state.position = state.position + 1
  end
  local integer_start = state.position
  local first = state.text:byte(state.position)
  if first == 48 then
    state.position = state.position + 1
    local following = state.text:byte(state.position)
    if following and following >= 48 and following <= 57 then
      return nil, decode_error(state, "JSON_INVALID_NUMBER", "leading zero in number", state.position)
    end
  elseif first and first >= 49 and first <= 57 then
    repeat
      state.position = state.position + 1
      first = state.text:byte(state.position)
    until not first or first < 48 or first > 57
  else
    return nil, decode_error(state, "JSON_INVALID_NUMBER", "expected a digit after the sign", state.position)
  end
  local integer = state.text:sub(integer_start, state.position - 1)
  local fraction = ""
  if state.text:sub(state.position, state.position) == "." then
    state.position = state.position + 1
    local fraction_start = state.position
    local byte = state.text:byte(state.position)
    if not byte or byte < 48 or byte > 57 then
      return nil, decode_error(state, "JSON_INVALID_NUMBER", "fraction requires at least one digit", state.position)
    end
    repeat
      state.position = state.position + 1
      byte = state.text:byte(state.position)
    until not byte or byte < 48 or byte > 57
    fraction = state.text:sub(fraction_start, state.position - 1)
  end
  local exponent_sign = "+"
  local exponent_digits = ""
  local marker = state.text:sub(state.position, state.position)
  if marker == "e" or marker == "E" then
    state.position = state.position + 1
    local sign_character = state.text:sub(state.position, state.position)
    if sign_character == "+" or sign_character == "-" then
      exponent_sign = sign_character
      state.position = state.position + 1
    end
    local exponent_start = state.position
    local byte = state.text:byte(state.position)
    if not byte or byte < 48 or byte > 57 then
      return nil, decode_error(state, "JSON_INVALID_NUMBER", "exponent requires at least one digit", state.position)
    end
    local bounded = 0
    repeat
      if bounded <= state.max_abs_exponent then bounded = bounded * 10 + byte - 48 end
      state.position = state.position + 1
      byte = state.text:byte(state.position)
    until not byte or byte < 48 or byte > 57
    exponent_digits = state.text:sub(exponent_start, state.position - 1)
    if bounded > state.max_abs_exponent then
      return nil,
        decode_error(state, "JSON_EXPONENT_LIMIT", "number exponent exceeds the absolute limit", exponent_start)
    end
  end
  if state.position - start > state.max_number_bytes then
    return nil, decode_error(state, "JSON_NUMBER_LIMIT", "number lexeme exceeds the byte limit", start)
  end
  local value = decimal_from_components(negative, integer, fraction, exponent_sign, exponent_digits)
  if math.abs(value.exponent) > state.max_abs_exponent then
    return nil,
      decode_error(state, "JSON_EXPONENT_LIMIT", "normalized number exponent exceeds the absolute limit", start)
  end
  return value
end

local parse_value

local function count_value(state)
  state.values = state.values + 1
  if state.values > state.max_values then
    return nil, decode_error(state, "JSON_VALUE_LIMIT", "JSON value count exceeds the limit", state.position)
  end
  return true
end

local function parse_array(state, depth)
  if depth > state.max_depth then
    return nil, decode_error(state, "JSON_DEPTH_LIMIT", "JSON nesting depth exceeds the limit", state.position)
  end
  state.position = state.position + 1
  skip_whitespace(state)
  local result = M.array()
  if state.text:sub(state.position, state.position) == "]" then
    state.position = state.position + 1
    return result
  end
  while true do
    local value, err = parse_value(state, depth)
    if value == nil then return nil, err end
    result[#result + 1] = value
    skip_whitespace(state)
    local token = state.text:sub(state.position, state.position)
    if token == "]" then
      state.position = state.position + 1
      return result
    elseif token ~= "," then
      return nil,
        decode_error(state, "JSON_EXPECTED_ARRAY_DELIMITER", "expected ',' or ']' after array item", state.position)
    end
    state.position = state.position + 1
    skip_whitespace(state)
    if state.text:sub(state.position, state.position) == "]" then
      return nil, decode_error(state, "JSON_TRAILING_COMMA", "trailing comma in array", state.position)
    end
  end
end

local function parse_object(state, depth)
  if depth > state.max_depth then
    return nil, decode_error(state, "JSON_DEPTH_LIMIT", "JSON nesting depth exceeds the limit", state.position)
  end
  state.position = state.position + 1
  skip_whitespace(state)
  local result = M.object()
  local seen = {}
  if state.text:sub(state.position, state.position) == "}" then
    state.position = state.position + 1
    return result
  end
  while true do
    if state.text:sub(state.position, state.position) ~= '"' then
      return nil, decode_error(state, "JSON_EXPECTED_OBJECT_KEY", "expected a quoted object key", state.position)
    end
    local key_position = state.position
    local key, err = parse_string(state)
    if key == nil then return nil, err end
    if seen[key] then
      return nil, decode_error(state, "JSON_DUPLICATE_KEY", "duplicate object key '" .. key .. "'", key_position)
    end
    seen[key] = true
    skip_whitespace(state)
    if state.text:sub(state.position, state.position) ~= ":" then
      return nil, decode_error(state, "JSON_EXPECTED_COLON", "expected ':' after object key", state.position)
    end
    state.position = state.position + 1
    skip_whitespace(state)
    local value
    value, err = parse_value(state, depth)
    if value == nil then return nil, err end
    result[key] = value
    skip_whitespace(state)
    local token = state.text:sub(state.position, state.position)
    if token == "}" then
      state.position = state.position + 1
      return result
    elseif token ~= "," then
      return nil,
        decode_error(state, "JSON_EXPECTED_OBJECT_DELIMITER", "expected ',' or '}' after object member", state.position)
    end
    state.position = state.position + 1
    skip_whitespace(state)
    if state.text:sub(state.position, state.position) == "}" then
      return nil, decode_error(state, "JSON_TRAILING_COMMA", "trailing comma in object", state.position)
    end
  end
end

parse_value = function(state, depth)
  local ok, err = count_value(state)
  if not ok then return nil, err end
  skip_whitespace(state)
  local token = state.text:sub(state.position, state.position)
  if token == '"' then
    return parse_string(state)
  elseif token == "{" then
    return parse_object(state, depth + 1)
  elseif token == "[" then
    return parse_array(state, depth + 1)
  elseif token == "t" and state.text:sub(state.position, state.position + 3) == "true" then
    state.position = state.position + 4
    return true
  elseif token == "f" and state.text:sub(state.position, state.position + 4) == "false" then
    state.position = state.position + 5
    return false
  elseif token == "n" and state.text:sub(state.position, state.position + 3) == "null" then
    state.position = state.position + 4
    return NULL
  elseif token == "-" or (token >= "0" and token <= "9") then
    return parse_number(state)
  elseif token == "" then
    return nil, decode_error(state, "JSON_UNEXPECTED_EOF", "expected a JSON value", state.position)
  end
  return nil,
    decode_error(state, "JSON_UNEXPECTED_TOKEN", "unexpected token while parsing a JSON value", state.position)
end

function M.decode(text, options)
  if type(text) ~= "string" then
    return nil,
      {
        code = "JSON_INPUT_TYPE",
        message = "JSON input must be a string",
        offset = 1,
        byte_offset = 0,
        line = 1,
        column = 1,
      }
  end
  local max_bytes = effective_limit(options, "max_bytes")
  if #text > max_bytes then
    return nil,
      {
        code = "JSON_PAYLOAD_LIMIT",
        message = "JSON payload exceeds the byte limit",
        offset = max_bytes + 1,
        byte_offset = max_bytes,
        line = 1,
        column = 1,
      }
  end
  if text:sub(1, 3) == "\239\187\191" then
    return nil,
      {
        code = "JSON_BOM",
        message = "JSON payload must not start with a UTF-8 BOM",
        offset = 1,
        byte_offset = 0,
        line = 1,
        column = 1,
      }
  end
  local invalid_position, invalid_message = utf8_error_position(text)
  if invalid_position then
    local line, column = location(text, invalid_position)
    return nil,
      {
        code = "JSON_INVALID_UTF8",
        message = invalid_message,
        offset = invalid_position,
        byte_offset = invalid_position - 1,
        line = line,
        column = column,
      }
  end
  local state = {
    text = text,
    length = #text,
    position = 1,
    values = 0,
    max_depth = effective_limit(options, "max_depth"),
    max_values = effective_limit(options, "max_values"),
    max_string_bytes = effective_limit(options, "max_string_bytes"),
    max_number_bytes = effective_limit(options, "max_number_bytes"),
    max_abs_exponent = effective_limit(options, "max_abs_exponent"),
  }
  skip_whitespace(state)
  local value, err = parse_value(state, 0)
  if value == nil then return nil, err end
  skip_whitespace(state)
  if state.position <= state.length then
    return nil, decode_error(state, "JSON_TRAILING_CONTENT", "trailing content after the JSON value", state.position)
  end
  return value
end

local ORDER_BY_PATH = {
  ["$"] = {
    "format",
    "schema_version",
    "units",
    "metadata",
    "settings",
    "rooms",
    "doors",
    "furniture",
    "custom_templates",
    "extensions",
  },
  ["$.metadata"] = { "name", "notes" },
  ["$.settings"] = { "grid_mm", "fine_step_mm", "normal_step_mm", "coarse_step_mm", "default_door_width_mm" },
  ["$.rooms[]"] = { "id", "name", "origin_mm", "size_mm", "color" },
  ["$.doors[]"] = {
    "id",
    "kind",
    "room_id",
    "connects_to_room_id",
    "side",
    "offset_mm",
    "width_mm",
    "hinge",
    "opens_into",
    "open_angle_deg",
  },
  ["$.furniture[]"] = {
    "id",
    "room_id",
    "template_id",
    "name",
    "category",
    "center_mm",
    "size_mm",
    "rotation_deg",
    "color",
  },
  ["$.custom_templates[]"] = { "id", "name", "category", "shape", "default_size_mm" },
}

local function decimal_to_string(value)
  local sign = value.sign < 0 and "-" or ""
  local coefficient = value.coefficient
  local exponent = value.exponent
  if coefficient == "0" then return "0" end
  local adjusted = #coefficient - 1 + exponent
  if exponent >= 0 and adjusted <= 20 then
    return sign .. coefficient .. string.rep("0", exponent)
  elseif exponent < 0 and adjusted >= -6 and adjusted <= 20 then
    local point = #coefficient + exponent
    if point > 0 then return sign .. coefficient:sub(1, point) .. "." .. coefficient:sub(point + 1) end
    return sign .. "0." .. string.rep("0", -point) .. coefficient
  end
  local mantissa = coefficient:sub(1, 1)
  if #coefficient > 1 then mantissa = mantissa .. "." .. coefficient:sub(2) end
  return sign .. mantissa .. "e" .. tostring(adjusted)
end

local function integer_to_string(value)
  if value == 0 then return "0" end
  return string.format("%.0f", value)
end

local function escape_string(value)
  local pieces = { '"' }
  local start = 1
  local cursor = 1
  while cursor <= #value do
    local byte = value:byte(cursor)
    local replacement
    if byte == 34 then
      replacement = '\\"'
    elseif byte == 92 then
      replacement = "\\\\"
    elseif byte == 8 then
      replacement = "\\b"
    elseif byte == 12 then
      replacement = "\\f"
    elseif byte == 10 then
      replacement = "\\n"
    elseif byte == 13 then
      replacement = "\\r"
    elseif byte == 9 then
      replacement = "\\t"
    elseif byte < 32 then
      replacement = string.format("\\u%04x", byte)
    end
    if replacement then
      if cursor > start then pieces[#pieces + 1] = value:sub(start, cursor - 1) end
      pieces[#pieces + 1] = replacement
      start = cursor + 1
    end
    cursor = cursor + 1
  end
  if start <= #value then pieces[#pieces + 1] = value:sub(start) end
  pieces[#pieces + 1] = '"'
  return table.concat(pieces)
end

local function encode_error(code, message, path) return { code = code, message = message, path = path } end

local function ordered_keys(value, path, options)
  local keys = {}
  for key in pairs(value) do
    if type(key) ~= "string" then
      return nil, encode_error("JSON_OBJECT_KEY_TYPE", "JSON object keys must be strings", path)
    end
    local invalid_position, invalid_message = utf8_error_position(key)
    if invalid_position then
      return nil, encode_error("JSON_INVALID_UTF8", invalid_message .. " at object-key byte " .. invalid_position, path)
    end
    if #key > effective_limit(options, "max_string_bytes") then
      return nil, encode_error("JSON_STRING_LIMIT", "object key exceeds the byte limit", path)
    end
    keys[#keys + 1] = key
  end
  local specified
  if options and type(options.key_order) == "function" then
    specified = options.key_order(path, value)
  elseif options and type(options.key_order) == "table" then
    specified = options.key_order[path]
  else
    specified = ORDER_BY_PATH[path]
  end
  local result = {}
  local consumed = {}
  if specified then
    local index = 1
    while index <= #specified do
      local key = specified[index]
      if value[key] ~= nil then
        result[#result + 1] = key
        consumed[key] = true
      end
      index = index + 1
    end
  end
  local unknown = {}
  local index = 1
  while index <= #keys do
    local key = keys[index]
    if not consumed[key] then unknown[#unknown + 1] = key end
    index = index + 1
  end
  table.sort(unknown)
  index = 1
  while index <= #unknown do
    result[#result + 1] = unknown[index]
    index = index + 1
  end
  return result
end

local encode_value

local function indent(level) return string.rep("  ", level) end

local function encode_array(value, state, path, depth)
  local maximum = 0
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
      return nil, encode_error("JSON_ARRAY_KEY", "JSON array contains a non-positive-integer key", path)
    end
    count = count + 1
    if key > maximum then maximum = key end
  end
  if maximum ~= count then return nil, encode_error("JSON_SPARSE_ARRAY", "JSON array is sparse", path) end
  if count == 0 then return "[]" end
  local pieces = { "[\n" }
  local index = 1
  while index <= count do
    local encoded, err = encode_value(value[index], state, path .. "[]", depth + 1)
    if not encoded then return nil, err end
    pieces[#pieces + 1] = indent(depth + 1) .. encoded
    pieces[#pieces + 1] = index == count and "\n" or ",\n"
    index = index + 1
  end
  pieces[#pieces + 1] = indent(depth) .. "]"
  return table.concat(pieces)
end

local function encode_object(value, state, path, depth)
  local keys, err = ordered_keys(value, path, state.options)
  if not keys then return nil, err end
  if #keys == 0 then return "{}" end
  local pieces = { "{\n" }
  local index = 1
  while index <= #keys do
    local key = keys[index]
    local child_path = path .. "." .. key
    local encoded
    encoded, err = encode_value(value[key], state, child_path, depth + 1)
    if not encoded then return nil, err end
    pieces[#pieces + 1] = indent(depth + 1) .. escape_string(key) .. ": " .. encoded
    pieces[#pieces + 1] = index == #keys and "\n" or ",\n"
    index = index + 1
  end
  pieces[#pieces + 1] = indent(depth) .. "}"
  return table.concat(pieces)
end

encode_value = function(value, state, path, depth)
  if depth > state.max_depth then
    return nil, encode_error("JSON_DEPTH_LIMIT", "JSON nesting depth exceeds the limit", path)
  end
  state.values = state.values + 1
  if state.values > state.max_values then
    return nil, encode_error("JSON_VALUE_LIMIT", "JSON value count exceeds the limit", path)
  end
  local value_type = type(value)
  if value == NULL then
    return "null"
  elseif value_type == "string" then
    local position, message = utf8_error_position(value)
    if position then return nil, encode_error("JSON_INVALID_UTF8", message .. " at string byte " .. position, path) end
    if #value > state.max_string_bytes then
      return nil, encode_error("JSON_STRING_LIMIT", "string exceeds the byte limit", path)
    end
    return escape_string(value)
  elseif value_type == "boolean" then
    return value and "true" or "false"
  elseif value_type == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      return nil, encode_error("JSON_NONFINITE_NUMBER", "JSON cannot encode a non-finite number", path)
    end
    if value ~= math.floor(value) then
      return nil,
        encode_error("JSON_UNTAGGED_FRACTION", "non-integer Lua numbers must be represented as tagged decimals", path)
    end
    if math.abs(value) > 9007199254740991 then
      return nil, encode_error("JSON_UNSAFE_INTEGER", "Lua integer exceeds the exact JSON safety limit", path)
    end
    return integer_to_string(value)
  elseif M.is_decimal(value) then
    return decimal_to_string(value)
  elseif M.is_array(value) or M.is_object(value) then
    if state.active[value] then
      return nil, encode_error("JSON_CYCLE", "cyclic table cannot be encoded as JSON", path)
    end
    state.active[value] = true
    local encoded, err
    if M.is_array(value) then
      encoded, err = encode_array(value, state, path, depth)
    else
      encoded, err = encode_object(value, state, path, depth)
    end
    state.active[value] = nil
    return encoded, err
  elseif value_type == "table" then
    return nil, encode_error("JSON_UNTAGGED_TABLE", "table is not tagged as a JSON object or array", path)
  end
  return nil, encode_error("JSON_UNSUPPORTED_TYPE", "unsupported Lua value type '" .. value_type .. "'", path)
end

function M.encode(value, options)
  local state = {
    options = options or {},
    max_depth = effective_limit(options, "max_depth"),
    max_values = effective_limit(options, "max_values"),
    max_string_bytes = effective_limit(options, "max_string_bytes"),
    values = 0,
    active = {},
  }
  local encoded, err = encode_value(value, state, "$", 0)
  if not encoded then return nil, err end
  local final_newline = not options or options.final_newline ~= false
  if final_newline then encoded = encoded .. "\n" end
  if #encoded > effective_limit(options, "max_bytes") then
    return nil, encode_error("JSON_PAYLOAD_LIMIT", "encoded JSON exceeds the byte limit", "$")
  end
  return encoded
end

local function deep_copy(value, seen)
  local value_type = type(value)
  if value_type ~= "table" then return value end
  if value == NULL then return NULL end
  if M.is_decimal(value) then
    return setmetatable({ sign = value.sign, coefficient = value.coefficient, exponent = value.exponent }, DECIMAL_MT)
  end
  if seen[value] then return seen[value] end
  local result
  if M.is_array(value) then
    result = M.array()
  elseif M.is_object(value) then
    result = M.object()
  else
    result = {}
  end
  seen[value] = result
  for key, child in pairs(value) do
    result[deep_copy(key, seen)] = deep_copy(child, seen)
  end
  return result
end

function M.deep_copy(value) return deep_copy(value, {}) end

local function deep_equal(left, right, seen)
  if left == right then return true end
  if type(left) ~= type(right) then return false end
  if type(left) ~= "table" then return false end
  if raw_kind(left) ~= raw_kind(right) then return false end
  if M.is_decimal(left) then
    return left.sign == right.sign and left.coefficient == right.coefficient and left.exponent == right.exponent
  end
  if left == NULL or right == NULL then return false end
  seen[left] = seen[left] or {}
  if seen[left][right] then return true end
  seen[left][right] = true
  local count = 0
  for key, value in pairs(left) do
    count = count + 1
    if right[key] == nil or not deep_equal(value, right[key], seen) then return false end
  end
  local right_count = 0
  for _ in pairs(right) do
    right_count = right_count + 1
  end
  return count == right_count
end

function M.deep_equal(left, right) return deep_equal(left, right, {}) end

return M
