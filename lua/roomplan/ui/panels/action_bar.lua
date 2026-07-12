local common = require("roomplan.ui.panels.common")
local registry = require("roomplan.ui.action_registry")

local M = {}

local function compact_hint(action)
  if action.key == nil then
    return string.format("%s%s", action.label, action.enabled and " (unmapped)" or "×")
  end
  return string.format("[%s] %s%s", action.key, action.label, action.enabled and "" or "×")
end

function M.render(ctx, width, opts)
  opts = opts or {}
  local actions = opts.actions or registry.contextual(ctx, { include_disabled = true })
  actions = vim.deepcopy(actions)
  table.sort(actions, function(left, right)
    if (left.priority or 0) ~= (right.priority or 0) then return (left.priority or 0) > (right.priority or 0) end
    return left.id < right.id
  end)
  local hints = {}
  local used = 0
  local disabled_reason
  for _, action in ipairs(actions) do
    local hint = compact_hint(action)
    local cost = common.width(hint) + (#hints > 0 and 2 or 0)
    if used + cost <= width then
      hints[#hints + 1] = hint
      used = used + cost
      if not action.enabled and not disabled_reason then disabled_reason = action.reason end
    end
  end
  if #hints == 0 and actions[1] then hints[1] = common.truncate(compact_hint(actions[1]), width) end

  local status_parts = {
    registry.mode_label(ctx),
    (ctx.dirty and "DIRTY" or "SAVED"),
    (ctx.snap_enabled and "snap on" or "snap off"),
  }
  if ctx.focus then status_parts[#status_parts + 1] = "focus " .. ctx.focus end
  if ctx.cursor_world then
    status_parts[#status_parts + 1] = string.format(
      "cursor (%d, %d) mm",
      math.floor((ctx.cursor_world.x or 0) + 0.5),
      math.floor((ctx.cursor_world.y or 0) + 0.5)
    )
  end
  if ctx.zoom then status_parts[#status_parts + 1] = string.format("zoom %.2f", ctx.zoom) end
  if disabled_reason then status_parts[#status_parts + 1] = disabled_reason end
  if opts.compact_reason then status_parts[#status_parts + 1] = opts.compact_reason end
  local status = table.concat(status_parts, " · ")
  return {
    lines = common.fit({ table.concat(hints, "  "), status }, width, opts.height or 2),
    actions = actions,
  }
end

return M
