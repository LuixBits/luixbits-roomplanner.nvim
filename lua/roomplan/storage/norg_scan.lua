local util = require("roomplan.util")

local M = {}

local function split_lines(text)
  local lines = {}
  local function append(line)
    -- Raw CRLF disk bytes may reach the conservative scanner during durable
    -- verification; Neovim buffers expose the same text without CR bytes.
    if line:sub(-1) == "\r" then line = line:sub(1, -2) end
    lines[#lines + 1] = line
  end
  local start = 1
  while true do
    local finish = text:find("\n", start, true)
    if not finish then
      append(text:sub(start))
      break
    end
    append(text:sub(start, finish - 1))
    start = finish + 1
    if start > #text then
      lines[#lines + 1] = ""
      break
    end
  end
  return lines
end

local function parse_params(rest)
  local params = {}
  local current = {}
  local escaped = false
  local started = false
  for index = 1, #rest do
    local char = rest:sub(index, index)
    if escaped then
      current[#current + 1] = char
      escaped = false
      started = true
    elseif char == "\\" then
      escaped = true
      started = true
    elseif char == " " or char == "\t" then
      if started then
        params[#params + 1] = table.concat(current)
        current = {}
        started = false
      end
    else
      current[#current + 1] = char
      started = true
    end
  end
  if escaped then current[#current + 1] = "\\" end
  if started then params[#params + 1] = table.concat(current) end
  return params
end

function M.scan(text)
  local without_crlf = text:gsub("\r\n", "")
  local has_crlf = text:find("\r\n", 1, true) ~= nil
  local has_lf = without_crlf:find("\n", 1, true) ~= nil
  local has_lone_cr = without_crlf:find("\r", 1, true) ~= nil
  if (has_crlf and has_lf) or has_lone_cr then
    return nil, util.err("NORG_MIXED_LINE_ENDINGS", "Norg source has mixed or unsupported line endings")
  end
  local lines = split_lines(text)
  local blocks = {}
  local index = 1
  while index <= #lines do
    local indent, name, rest = lines[index]:match("^([ \t]*)@([%w_.%-]+)(.*)$")
    if name and name ~= "end" then
      local close_line
      for candidate = index + 1, #lines do
        if lines[candidate]:match("^[ \t]*@end[ \t]*$") then
          close_line = candidate
          break
        end
      end
      local params = parse_params(rest or "")
      local block = {
        name = name,
        params = params,
        indent = indent,
        start_line = index,
        content_start_line = index + 1,
        content_end_line = close_line and (close_line - 1) or #lines,
        end_line = close_line,
        opener = lines[index],
        closed = close_line ~= nil,
      }
      local content = {}
      for line = block.content_start_line, block.content_end_line do
        content[#content + 1] = lines[line]
      end
      block.content = table.concat(content, "\n")
      blocks[#blocks + 1] = block
      if close_line then
        index = close_line + 1
      else
        index = #lines + 1
      end
    else
      index = index + 1
    end
  end
  return blocks, lines
end

local function is_roomplan_document(document) return type(document) == "table" and document.format == "roomplan.nvim" end

function M.discover(text, decode)
  local blocks, scan_err = M.scan(text)
  if not blocks then return nil, scan_err end
  local candidates = {}
  local malformed_json = {}
  local marked_count = 0

  for _, block in ipairs(blocks) do
    if block.name == "code" and block.params[1] and block.params[1]:lower() == "json" then
      local marked = block.params[2] == "roomplan.nvim"
      if marked then
        marked_count = marked_count + 1
        if not block.closed then
          return nil,
            util.err("NORG_MARKED_UNTERMINATED", "marked RoomPlan block has no @end", {
              line = block.start_line,
            })
        end
      end
      local ok, document = pcall(decode, block.content)
      if ok and is_roomplan_document(document) then
        block.document = document
        block.marked = marked
        candidates[#candidates + 1] = block
      elseif marked then
        return nil,
          util.err("NORG_MARKED_MALFORMED", "marked RoomPlan JSON is malformed", {
            line = block.start_line,
            cause = ok and "format marker missing" or tostring(document),
          })
      elseif not ok then
        malformed_json[#malformed_json + 1] = block
      end
    end
  end

  if marked_count > 1 then
    return nil, util.err("NORG_MULTIPLE_MARKED", "more than one marked RoomPlan block exists", { count = marked_count })
  end
  if #candidates > 1 then
    return nil, util.err("NORG_MULTIPLE_PLANS", "more than one RoomPlan JSON block exists", { count = #candidates })
  end
  if #candidates == 1 then return { kind = "found", block = candidates[1], blocks = blocks } end

  for _, block in ipairs(malformed_json) do
    if block.content:find('"roomplan%.nvim"') then
      return nil,
        util.err("NORG_SUSPECTED_DAMAGED_PLAN", "malformed JSON block may be a damaged RoomPlan", {
          line = block.start_line,
        })
    end
  end
  return { kind = "missing", malformed_json = malformed_json, blocks = blocks }
end

function M.replace(text, block, payload)
  if not block or not block.closed then
    return nil, util.err("NORG_BLOCK_INVALID", "cannot replace an invalid or unterminated block")
  end
  local lines = split_lines(text)
  local replacement = split_lines(payload:gsub("\n$", ""))
  local output = {}
  for index = 1, block.start_line do
    output[#output + 1] = lines[index]
  end
  for _, line in ipairs(replacement) do
    output[#output + 1] = line
  end
  for index = block.end_line, #lines do
    output[#output + 1] = lines[index]
  end
  return table.concat(output, "\n")
end

function M.initialize(text, payload, heading_line)
  local lines = split_lines(text)
  local block_lines = {
    "@code json roomplan.nvim",
  }
  for _, line in ipairs(split_lines(payload:gsub("\n$", ""))) do
    block_lines[#block_lines + 1] = line
  end
  block_lines[#block_lines + 1] = "@end"

  if heading_line then
    local insert_at = #lines + 1
    for index = heading_line + 1, #lines do
      if lines[index]:match("^%*%s+") then
        insert_at = index
        break
      end
    end
    local output = {}
    for index = 1, insert_at - 1 do
      output[#output + 1] = lines[index]
    end
    if output[#output] ~= "" then output[#output + 1] = "" end
    vim.list_extend(output, block_lines)
    output[#output + 1] = ""
    for index = insert_at, #lines do
      output[#output + 1] = lines[index]
    end
    return table.concat(output, "\n")
  end

  while #lines > 0 and lines[#lines] == "" do
    table.remove(lines)
  end
  if #lines > 0 then lines[#lines + 1] = "" end
  lines[#lines + 1] = "* Floor plan"
  lines[#lines + 1] = ""
  vim.list_extend(lines, block_lines)
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

function M.floor_plan_headings(text)
  local blocks, lines = M.scan(text)
  if not blocks then return nil, lines end
  local result = {}
  for index, line in ipairs(lines) do
    if line:match("^%*%s+Floor plan%s*$") then result[#result + 1] = index end
  end
  return result
end

return M
