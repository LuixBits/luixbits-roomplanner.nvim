local common = require("roomplan.ui.panels.common")

local M = {}

local function count_suffix(counts)
  counts = counts or {}
  local values = {}
  if (counts.errors or 0) > 0 then values[#values + 1] = "E" .. counts.errors end
  if (counts.warnings or 0) > 0 then values[#values + 1] = "W" .. counts.warnings end
  return #values > 0 and (" [" .. table.concat(values, " ") .. "]") or ""
end

function M.render(view, width, height, opts)
  opts = opts or {}
  local ascii = opts.ascii == true
  local lines = {
    common.truncate(view.title or "Untitled plan", width),
    common.truncate(view.summary or "", width),
    common.truncate(opts.active == "issues" and " Objects  [Issues]" or "[Objects]  Issues", width),
  }
  if view.filter and view.filter ~= "" then lines[#lines + 1] = common.truncate("Filter: " .. view.filter, width) end
  lines[#lines + 1] = ""
  local row_map = {}
  for _, row in ipairs(view.rows or {}) do
    local branch = " "
    if row.expandable then
      branch = row.expanded and (ascii and "v" or "▾") or (ascii and ">" or "▸")
    elseif (row.depth or 0) > 0 then
      branch = ascii and "-" or "├"
    end
    local marker = row.selected and ">" or " "
    local indent = string.rep("  ", row.depth or 0)
    local orphan = row.orphan and "[orphan] " or ""
    local line = string.format("%s%s%s%s %s%s", marker, indent, branch, row.kind == "plan" and "" or " ", orphan .. (row.label or row.name or row.id or "?"), count_suffix(row.counts))
    lines[#lines + 1] = common.truncate(line, width)
    row_map[#lines] = row
  end
  if (view.room_count or 0) == 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "No rooms yet."
    lines[#lines + 1] = "[a] Add first room"
  end
  return { lines = common.fit(lines, width, height), row_map = row_map }
end

return M
