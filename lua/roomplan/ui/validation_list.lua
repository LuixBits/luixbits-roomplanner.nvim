local list = require("roomplan.ui.list")

local M = {}

local function format(diagnostic)
  local object = diagnostic.object or {}
  return string.format("[%s] %s %s:%s: %s", (diagnostic.severity or "info"):upper(), diagnostic.code or "UNKNOWN", object.kind or "source", object.id or "-", diagnostic.message or "")
end

function M.open(session, diagnostics)
  diagnostics = diagnostics or session.validation or {}
  local lines = {}
  for index, diagnostic in ipairs(diagnostics) do
    lines[index] = format(diagnostic)
  end
  if #lines == 0 then
    lines[1] = "No RoomPlan validation problems"
  end
  return list.open(session, {
    role = "validation-list",
    filetype = "roomplan-validation",
    lines = lines,
    items = diagnostics,
    on_choose = function(row, diagnostic)
      if not diagnostic or not diagnostic.object or not diagnostic.object.id then
        return
      end
      session.selection = { kind = diagnostic.object.kind, id = diagnostic.object.id }
      session.validation_index = row
      require("roomplan.controller").focus_canvas(session, diagnostic)
    end,
  })
end

return M
