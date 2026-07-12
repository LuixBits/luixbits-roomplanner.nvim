local common = require("roomplan.ui.panels.common")

local M = {}

function M.render(view, width, height, opts)
  opts = opts or {}
  local lines = {
    common.truncate(view.title or "Properties", width),
    common.truncate(view.subtitle or "", width),
    string.rep("─", math.max(0, math.min(width, 24))),
  }
  for _, group in ipairs(view.groups or {}) do
    lines[#lines + 1] = ""
    lines[#lines + 1] = common.truncate(group.title or "", width)
    for _, field in ipairs(group.fields or {}) do
      local label_width = math.min(14, math.max(7, math.floor(width * 0.38)))
      lines[#lines + 1] = common.truncate(string.format("  %-" .. label_width .. "s %s", (field.label or "") .. ":", field.value or "-"), width)
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Diagnostics"
  if #(view.diagnostics or {}) == 0 then
    lines[#lines + 1] = "  None"
  else
    for _, diagnostic in ipairs(view.diagnostics) do
      lines[#lines + 1] = common.truncate(string.format("  %s %s", (diagnostic.severity or "info"):upper(), diagnostic.message or diagnostic.code or ""), width)
    end
  end
  if opts.actions and #opts.actions > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Actions"
    for _, action in ipairs(opts.actions) do
      local suffix = action.enabled and "" or (" — " .. tostring(action.reason))
      lines[#lines + 1] = common.truncate(string.format("  [%s] %s%s", action.key, action.label, suffix), width)
    end
  end
  return { lines = common.fit(lines, width, height) }
end

return M
