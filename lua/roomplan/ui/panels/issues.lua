local common = require("roomplan.ui.panels.common")

local M = {}

local severity = {
  error = { marker = "E", highlight = "RoomPlanWorkspaceError" },
  warning = { marker = "W", highlight = "RoomPlanWorkspaceWarning" },
  info = { marker = "i", highlight = "RoomPlanWorkspaceInfo" },
}

local function add_header(document, view)
  local counts = view.counts or {}
  local text = string.format("Objects  [Issues] · %dE %dW", counts.errors or 0, counts.warnings or 0)
  local active_at = assert(text:find("[Issues]", 1, true)) - 1
  common.line(document, text, {
    highlights = {
      { start_col = 0, end_col = -1, hl_group = "RoomPlanWorkspaceMuted" },
      { start_col = active_at, end_col = active_at + 8, hl_group = "RoomPlanWorkspaceTitle" },
    },
  })
  if view.filter and view.filter ~= "" then
    common.line(document, "/ " .. view.filter, {
      highlights = { { start_col = 0, end_col = -1, hl_group = "RoomPlanWorkspaceStatus" } },
    })
  end
end

function M.render(view, width, height)
  local document = common.document(width)
  add_header(document, view)

  if #(view.rows or {}) == 0 then
    common.line(document, "✓ No validation problems", {
      highlights = { { start_col = 0, end_col = -1, hl_group = "RoomPlanWorkspaceStatus" } },
    })
  else
    for _, row in ipairs(view.rows) do
      local style = severity[row.severity] or severity.info
      local target = row.id and string.format(" · %s:%s", row.kind or "object", row.id) or ""
      local message = row.message ~= "" and (" · " .. row.message) or ""
      local line = string.format("%s %s%s%s", style.marker, row.code or "UNKNOWN", message, target)
      local heading_end = #style.marker + 1 + #(row.code or "UNKNOWN")
      common.line(document, line, {
        row_map = row,
        highlights = {
          { start_col = 0, end_col = heading_end, hl_group = style.highlight },
        },
      })
    end
  end
  return common.finish(document, height)
end

return M
