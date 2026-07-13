local M = {}

function M.width(value)
  value = tostring(value or "")
  if _G.vim and vim.fn and vim.fn.strdisplaywidth then return vim.fn.strdisplaywidth(value) end
  return #value
end

function M.truncate(value, width)
  value = tostring(value or ""):gsub("[\r\n]", " ")
  width = math.max(0, math.floor(width or 0))
  if M.width(value) <= width then return value end
  if width == 0 then return "" end
  if width == 1 then return "…" end
  if _G.vim and vim.fn and vim.fn.strcharpart then
    local result = ""
    local chars = vim.fn.strchars(value)
    for index = 0, chars - 1 do
      local candidate = result .. vim.fn.strcharpart(value, index, 1)
      if M.width(candidate) > width - 1 then break end
      result = candidate
    end
    return result .. "…"
  end
  return value:sub(1, width - 1) .. "…"
end

function M.pad(value, width)
  value = M.truncate(value, width)
  return value .. string.rep(" ", math.max(0, width - M.width(value)))
end

function M.fit(lines, width, height)
  local result = {}
  for index = 1, math.max(0, height or #lines) do
    result[index] = M.pad(lines[index] or "", width)
  end
  return result
end

function M.center(value, width)
  value = M.truncate(value, width)
  local padding = math.max(0, math.floor((width - M.width(value)) / 2))
  return string.rep(" ", padding) .. value
end

---Create a panel render result while keeping row metadata and highlights tied
---to the text that produced them. Highlight columns use Neovim's convention:
---one-based rows and zero-based, end-exclusive byte columns (`-1` means EOL).
function M.document(width)
  return {
    width = math.max(0, math.floor(width or 0)),
    lines = {},
    row_map = {},
    highlights = {},
  }
end

local function append_highlight(document, row, line, span)
  if type(span) ~= "table" or not span.hl_group then return end
  local start_col = math.max(0, math.floor(span.start_col or 0))
  if start_col >= #line and #line > 0 then return end
  local end_col = span.end_col == -1 and -1 or math.min(#line, math.max(start_col, math.floor(span.end_col or #line)))
  if end_col ~= -1 and end_col <= start_col then return end
  document.highlights[#document.highlights + 1] = {
    row = row,
    start_col = start_col,
    end_col = end_col,
    hl_group = span.hl_group,
  }
end

---Append one width-bounded line to a document.
---@return integer row
---@return string line
function M.line(document, value, opts)
  opts = opts or {}
  local line = M.truncate(value, document.width)
  document.lines[#document.lines + 1] = line
  local row = #document.lines
  if opts.row_map ~= nil then document.row_map[row] = opts.row_map end
  for _, span in ipairs(opts.highlights or {}) do append_highlight(document, row, line, span) end
  return row, line
end

---Pad a document to its window height and remove its private builder state.
function M.finish(document, height)
  -- Panel buffers are scrollable. A short document still fills its window,
  -- while a long document must retain every row instead of being clipped to
  -- the current viewport height.
  local target_height = math.max(#document.lines, math.max(0, height or 0))
  document.lines = M.fit(document.lines, document.width, target_height)
  document.width = nil
  return document
end

---Return a shallow copy of a list so pure renderers do not depend on
---`vim.deepcopy` when exercised outside Neovim.
function M.copy_list(values)
  local result = {}
  for index, value in ipairs(values or {}) do result[index] = value end
  return result
end

return M
