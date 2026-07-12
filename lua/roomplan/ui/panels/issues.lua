local common = require("roomplan.ui.panels.common")

local M = {}

function M.render(view, width, height)
  local counts = view.counts or {}
  local lines = {
    string.format("Issues · %d error · %d warn", counts.errors or 0, counts.warnings or 0),
    " Objects  [Issues]",
  }
  if view.filter and view.filter ~= "" then lines[#lines + 1] = "Filter: " .. view.filter end
  lines[#lines + 1] = ""
  local row_map = {}
  if #(view.rows or {}) == 0 then
    lines[#lines + 1] = "No validation problems."
  else
    for _, row in ipairs(view.rows) do
      local object = row.id and string.format(" %s:%s", row.kind or "object", row.id) or ""
      lines[#lines + 1] = common.truncate(string.format("%s %s%s", row.severity:upper(), row.code, object), width)
      row_map[#lines] = row
      if #lines < height then
        lines[#lines + 1] = common.truncate("  " .. row.message, width)
        row_map[#lines] = row
      end
    end
  end
  return { lines = common.fit(lines, width, height), row_map = row_map }
end

return M
