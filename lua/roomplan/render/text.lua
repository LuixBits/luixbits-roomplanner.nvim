-- UTF-8 validation and conversion to one-display-cell backing clusters.
-- No Neovim global is referenced; callers inject strdisplaywidth when present.

local M = {}

local function continuation(byte) return byte and byte >= 0x80 and byte <= 0xBF end

---Decode UTF-8 into byte-ranged codepoint records, rejecting overlong encodings,
---surrogates, truncation, and values beyond U+10FFFF.
function M.decode(value)
  if type(value) ~= "string" then return nil, "text must be a string" end
  local result = {}
  local index = 1
  while index <= #value do
    local first = value:byte(index)
    local codepoint
    local length
    if first <= 0x7F then
      codepoint, length = first, 1
    elseif first >= 0xC2 and first <= 0xDF then
      local b2 = value:byte(index + 1)
      if not continuation(b2) then return nil, "invalid UTF-8 continuation at byte " .. index end
      codepoint = (first - 0xC0) * 0x40 + (b2 - 0x80)
      length = 2
    elseif first >= 0xE0 and first <= 0xEF then
      local b2, b3 = value:byte(index + 1, index + 2)
      if not continuation(b2) or not continuation(b3) then
        return nil, "invalid UTF-8 continuation at byte " .. index
      end
      if first == 0xE0 and b2 < 0xA0 then return nil, "overlong UTF-8 sequence at byte " .. index end
      if first == 0xED and b2 >= 0xA0 then return nil, "UTF-8 surrogate at byte " .. index end
      codepoint = (first - 0xE0) * 0x1000 + (b2 - 0x80) * 0x40 + (b3 - 0x80)
      length = 3
    elseif first >= 0xF0 and first <= 0xF4 then
      local b2, b3, b4 = value:byte(index + 1, index + 3)
      if not continuation(b2) or not continuation(b3) or not continuation(b4) then
        return nil, "invalid UTF-8 continuation at byte " .. index
      end
      if first == 0xF0 and b2 < 0x90 then return nil, "overlong UTF-8 sequence at byte " .. index end
      if first == 0xF4 and b2 > 0x8F then return nil, "UTF-8 codepoint beyond U+10FFFF at byte " .. index end
      codepoint = (first - 0xF0) * 0x40000 + (b2 - 0x80) * 0x1000 + (b3 - 0x80) * 0x40 + (b4 - 0x80)
      length = 4
    else
      return nil, "invalid UTF-8 leading byte at byte " .. index
    end

    result[#result + 1] = {
      codepoint = codepoint,
      start_byte = index,
      finish_byte = index + length - 1,
    }
    index = index + length
  end
  return result
end

local function in_range(value, first, last) return value >= first and value <= last end

function M.is_combining(codepoint)
  return in_range(codepoint, 0x0300, 0x036F)
    or in_range(codepoint, 0x0483, 0x0489)
    or in_range(codepoint, 0x0591, 0x05BD)
    or codepoint == 0x05BF
    or in_range(codepoint, 0x05C1, 0x05C2)
    or in_range(codepoint, 0x0610, 0x061A)
    or in_range(codepoint, 0x064B, 0x065F)
    or in_range(codepoint, 0x06D6, 0x06ED)
    or in_range(codepoint, 0x0711, 0x0711)
    or in_range(codepoint, 0x0730, 0x074A)
    or in_range(codepoint, 0x07A6, 0x07B0)
    or in_range(codepoint, 0x07EB, 0x07F3)
    or in_range(codepoint, 0x0816, 0x082D)
    or in_range(codepoint, 0x08D3, 0x0903)
    or in_range(codepoint, 0x093A, 0x094F)
    or in_range(codepoint, 0x0951, 0x0957)
    or in_range(codepoint, 0x0962, 0x0963)
    or in_range(codepoint, 0x0981, 0x0983)
    or codepoint == 0x09BC
    or in_range(codepoint, 0x09BE, 0x09C4)
    or in_range(codepoint, 0x09C7, 0x09C8)
    or in_range(codepoint, 0x09CB, 0x09CD)
    or codepoint == 0x09D7
    or in_range(codepoint, 0x09E2, 0x09E3)
    or in_range(codepoint, 0x0A01, 0x0A03)
    or codepoint == 0x0A3C
    or in_range(codepoint, 0x0A3E, 0x0A42)
    or in_range(codepoint, 0x0A47, 0x0A48)
    or in_range(codepoint, 0x0A4B, 0x0A4D)
    or in_range(codepoint, 0x0A70, 0x0A71)
    or in_range(codepoint, 0x0A81, 0x0A83)
    or codepoint == 0x0ABC
    or in_range(codepoint, 0x0ABE, 0x0AC5)
    or in_range(codepoint, 0x0AC7, 0x0AC9)
    or in_range(codepoint, 0x0ACB, 0x0ACD)
    or in_range(codepoint, 0x0B01, 0x0B03)
    or codepoint == 0x0B3C
    or in_range(codepoint, 0x0B3E, 0x0B44)
    or in_range(codepoint, 0x0B47, 0x0B48)
    or in_range(codepoint, 0x0B4B, 0x0B4D)
    or in_range(codepoint, 0x0B56, 0x0B57)
    or codepoint == 0x0B82
    or in_range(codepoint, 0x0BBE, 0x0BC2)
    or in_range(codepoint, 0x0BC6, 0x0BC8)
    or in_range(codepoint, 0x0BCA, 0x0BCD)
    or codepoint == 0x0BD7
    or in_range(codepoint, 0x0C00, 0x0C04)
    or in_range(codepoint, 0x0C3E, 0x0C44)
    or in_range(codepoint, 0x0C46, 0x0C48)
    or in_range(codepoint, 0x0C4A, 0x0C4D)
    or in_range(codepoint, 0x0C55, 0x0C56)
    or in_range(codepoint, 0x0C81, 0x0C83)
    or codepoint == 0x0CBC
    or in_range(codepoint, 0x0CBE, 0x0CC4)
    or in_range(codepoint, 0x0CC6, 0x0CC8)
    or in_range(codepoint, 0x0CCA, 0x0CCD)
    or in_range(codepoint, 0x0CD5, 0x0CD6)
    or in_range(codepoint, 0x0D00, 0x0D03)
    or in_range(codepoint, 0x0D3B, 0x0D44)
    or in_range(codepoint, 0x0D46, 0x0D48)
    or in_range(codepoint, 0x0D4A, 0x0D4D)
    or codepoint == 0x0D57
    or codepoint == 0x0E31
    or in_range(codepoint, 0x0E34, 0x0E3A)
    or in_range(codepoint, 0x0E47, 0x0E4E)
    or codepoint == 0x0EB1
    or in_range(codepoint, 0x0EB4, 0x0EBC)
    or in_range(codepoint, 0x0EC8, 0x0ECD)
    or in_range(codepoint, 0x0F18, 0x0F19)
    or codepoint == 0x0F35
    or codepoint == 0x0F37
    or codepoint == 0x0F39
    or in_range(codepoint, 0x0F71, 0x0F84)
    or in_range(codepoint, 0x0F86, 0x0F87)
    or in_range(codepoint, 0x102B, 0x103E)
    or in_range(codepoint, 0x1AB0, 0x1AFF)
    or in_range(codepoint, 0x1DC0, 0x1DFF)
    or in_range(codepoint, 0x20D0, 0x20FF)
    or in_range(codepoint, 0xFE00, 0xFE0F)
    or in_range(codepoint, 0xFE20, 0xFE2F)
    or in_range(codepoint, 0x1F3FB, 0x1F3FF)
    or in_range(codepoint, 0xE0100, 0xE01EF)
end

local function is_regional_indicator(codepoint) return in_range(codepoint, 0x1F1E6, 0x1F1FF) end

---Split into conservative display clusters.  It handles combining sequences,
---variation selectors, regional pairs, and complete ZWJ chains; complex emoji
---are later replaced with one addressable marker.
function M.clusters(value)
  local decoded, err = M.decode(value)
  if not decoded then return nil, err end
  local clusters = {}
  local index = 1
  while index <= #decoded do
    local first_index = index
    local has_zwj = false
    if
      is_regional_indicator(decoded[index].codepoint)
      and decoded[index + 1]
      and is_regional_indicator(decoded[index + 1].codepoint)
    then
      index = index + 2
    else
      index = index + 1
      while decoded[index] and M.is_combining(decoded[index].codepoint) do
        index = index + 1
      end
      while decoded[index] and decoded[index].codepoint == 0x200D do
        has_zwj = true
        index = index + 1
        if decoded[index] then
          index = index + 1
          while decoded[index] and M.is_combining(decoded[index].codepoint) do
            index = index + 1
          end
        end
      end
    end
    local first = decoded[first_index]
    local last = decoded[index - 1]
    clusters[#clusters + 1] = {
      text = value:sub(first.start_byte, last.finish_byte),
      codepoints = decoded,
      first_index = first_index,
      last_index = index - 1,
      has_zwj = has_zwj,
    }
  end
  return clusters
end

local function codepoint_width(codepoint)
  if codepoint == 0 then return 0 end
  if codepoint < 32 or in_range(codepoint, 0x7F, 0x9F) then return 0 end
  if M.is_combining(codepoint) then return 0 end
  if
    in_range(codepoint, 0x1100, 0x115F)
    or codepoint == 0x2329
    or codepoint == 0x232A
    or in_range(codepoint, 0x2E80, 0xA4CF)
    or in_range(codepoint, 0xAC00, 0xD7A3)
    or in_range(codepoint, 0xF900, 0xFAFF)
    or in_range(codepoint, 0xFE10, 0xFE19)
    or in_range(codepoint, 0xFE30, 0xFE6F)
    or in_range(codepoint, 0xFF00, 0xFF60)
    or in_range(codepoint, 0xFFE0, 0xFFE6)
    or in_range(codepoint, 0x1F000, 0x1FAFF)
    or in_range(codepoint, 0x20000, 0x3FFFD)
  then
    return 2
  end
  return 1
end

---Portable approximation for tests.  Canvas presentation injects Neovim's
---strdisplaywidth for authoritative runtime behavior.
function M.default_width(value)
  local decoded = M.decode(value)
  if not decoded then return -1 end
  local width = 0
  local has_zwj = false
  for i = 1, #decoded do
    if decoded[i].codepoint == 0x200D then
      has_zwj = true
    else
      width = width + codepoint_width(decoded[i].codepoint)
    end
  end
  if has_zwj then return math.max(2, width > 0 and 2 or 0) end
  if #decoded == 2 and is_regional_indicator(decoded[1].codepoint) and is_regional_indicator(decoded[2].codepoint) then
    return 2
  end
  return width
end

local function validated_replacement(replacement, width_fn)
  replacement = type(replacement) == "string" and replacement or "?"
  local decoded = M.decode(replacement)
  if not decoded or width_fn(replacement) ~= 1 then replacement = "?" end
  if width_fn(replacement) ~= 1 then return nil, "replacement glyph does not occupy one display cell" end
  return replacement
end

---Convert arbitrary valid UTF-8 into addressable one-cell clusters.
---@return table|nil cells
---@return table|string metadata_or_error
function M.sanitize_cells(value, max_cells, width_fn, replacement)
  width_fn = width_fn or M.default_width
  local parsed, err = M.clusters(value)
  if not parsed then return nil, err end
  local safe_replacement, replacement_err = validated_replacement(replacement, width_fn)
  if not safe_replacement then return nil, replacement_err end

  max_cells = max_cells == nil and math.huge or math.max(0, math.floor(max_cells))
  local cells = {}
  local replaced = 0
  local omitted = 0
  for i = 1, #parsed do
    if #cells >= max_cells then
      omitted = omitted + 1
    else
      local cluster = parsed[i]
      local width = width_fn(cluster.text)
      if cluster.has_zwj or width > 1 or width < 0 then
        cells[#cells + 1] = safe_replacement
        replaced = replaced + 1
      elseif width == 1 then
        cells[#cells + 1] = cluster.text
      elseif width == 0 then
        if #cells > 0 then
          local combined = cells[#cells] .. cluster.text
          if width_fn(combined) == 1 then
            cells[#cells] = combined
          else
            omitted = omitted + 1
          end
        else
          omitted = omitted + 1
        end
      else
        cells[#cells + 1] = safe_replacement
        replaced = replaced + 1
      end
    end
  end
  return cells, {
    replaced = replaced,
    omitted = omitted,
    truncated = omitted > 0,
  }
end

function M.sanitize(value, max_cells, width_fn, replacement)
  local cells, metadata = M.sanitize_cells(value, max_cells, width_fn, replacement)
  if not cells then return nil, metadata end
  return table.concat(cells), metadata
end

---Build zero-based byte offsets for the start of each one-cell cluster.  The
---final sentinel at #cells + 1 equals the line byte length.
function M.byte_offsets(cells)
  local offsets = {}
  local offset = 0
  for i = 1, #cells do
    offsets[i] = offset
    offset = offset + #cells[i]
  end
  offsets[#cells + 1] = offset
  return offsets
end

---Convert a zero-based byte column to a one-based logical cell.
function M.byte_to_cell(offsets, byte_column)
  if type(offsets) ~= "table" or #offsets < 2 then return nil end
  byte_column = math.max(0, byte_column or 0)
  local count = #offsets - 1
  if byte_column >= offsets[count + 1] then return count end
  local low, high = 1, count
  while low <= high do
    local middle = math.floor((low + high) / 2)
    if offsets[middle] <= byte_column and byte_column < offsets[middle + 1] then
      return middle
    elseif byte_column < offsets[middle] then
      high = middle - 1
    else
      low = middle + 1
    end
  end
  return nil
end

return M
