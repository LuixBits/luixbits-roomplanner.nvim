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

return M
