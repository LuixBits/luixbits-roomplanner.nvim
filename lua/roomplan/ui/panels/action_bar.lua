local common = require("roomplan.ui.panels.common")
local registry = require("roomplan.ui.action_registry")

local M = {}

local function hint(action)
  if action.key == nil then return action.label end
  return string.format("[%s] %s", action.key_label or registry.display_key(action.key), action.label)
end

local function sorted(actions)
  local result = common.copy_list(actions)
  table.sort(result, function(left, right)
    if (left.priority or 0) ~= (right.priority or 0) then return (left.priority or 0) > (right.priority or 0) end
    return tostring(left.id) < tostring(right.id)
  end)
  return result
end

local function compact_mode(ctx)
  local mode = tostring(ctx.mode or "NAV"):gsub("_", " ")
  if mode == "MOVE" then return "MOVE hjkl · HJKL coarse" end
  if mode == "PAN" then return "PAN hjkl" end
  return mode
end

local function status(ctx)
  local values = { compact_mode(ctx) }
  if ctx.conflicted then
    values[#values + 1] = "CONFLICT"
  else
    values[#values + 1] = ctx.dirty and "DIRTY" or "SAVED"
  end
  if ctx.snap_enabled then values[#values + 1] = "SNAP" end
  if not ctx.form then values[#values + 1] = "DETAIL " .. tostring(ctx.detail_level or "middle"):upper() end
  if ctx.zoom then values[#values + 1] = string.format("×%.2g", ctx.zoom) end
  return table.concat(values, " · ")
end

local function is_primary(action)
  return action.id ~= "help" and action.enabled == true and action.key ~= nil
end

local function find_help(actions)
  for _, action in ipairs(actions) do
    if action.id == "help" then return action end
  end
end

local function overflow(actions, shown, ctx)
  local visible = {}
  for _, action in ipairs(shown) do visible[action] = true end
  local result = {}
  for _, action in ipairs(actions) do
    if action.id ~= "help" and not visible[action] then result[#result + 1] = action end
  end
  local help = find_help(actions)
  return result, (help and help.count or registry.more_count(ctx)) + #result
end

local function compose(shown, actions, status_text, ctx)
  local parts = {}
  for _, action in ipairs(shown) do parts[#parts + 1] = hint(action) end
  local hidden, hidden_count = overflow(actions, shown, ctx)
  local help = find_help(actions)
  local more_key = help and (help.key_label or registry.display_key(help.key)) or nil
  local more = more_key and string.format("[%s] More", more_key) or "More"
  if hidden_count > 0 then more = more .. string.format(" (%d)", hidden_count) end
  parts[#parts + 1] = more
  return table.concat(parts, "  ") .. "  ·  " .. status_text, hidden, hidden_count, more
end

function M.render(ctx, width, opts)
  ctx = ctx or {}
  opts = opts or {}
  local actions = sorted(opts.actions or registry.primary(ctx))
  local candidates = {}
  for _, action in ipairs(actions) do
    if is_primary(action) then candidates[#candidates + 1] = action end
  end

  local shown = {}
  for index = 1, math.min(opts.max_actions or 5, #candidates) do shown[index] = candidates[index] end
  local status_text = status(ctx)
  local line, hidden, hidden_count, more = compose(shown, actions, status_text, ctx)
  while #shown > 0 and common.width(line) > width do
    shown[#shown] = nil
    line, hidden, hidden_count, more = compose(shown, actions, status_text, ctx)
  end

  local document = common.document(width)
  local highlights = {}
  local cursor = 0
  for _, action in ipairs(shown) do
    local text = hint(action)
    highlights[#highlights + 1] = {
      start_col = cursor,
      end_col = cursor + #text,
      hl_group = "RoomPlanWorkspaceStatus",
    }
    if action.key ~= nil then
      local key = "[" .. (action.key_label or registry.display_key(action.key)) .. "]"
      highlights[#highlights + 1] = {
        start_col = cursor,
        end_col = cursor + #key,
        hl_group = "RoomPlanWorkspaceKey",
      }
    end
    cursor = cursor + #text + 2
  end
  highlights[#highlights + 1] = {
    start_col = cursor,
    end_col = cursor + #more,
    hl_group = "RoomPlanWorkspaceTitle",
  }
  local more_key_end = more:find("]", 1, true)
  if more_key_end then
    highlights[#highlights + 1] = {
      start_col = cursor,
      end_col = cursor + more_key_end,
      hl_group = "RoomPlanWorkspaceKey",
    }
  end
  local status_at = assert(line:find(status_text, 1, true)) - 1
  highlights[#highlights + 1] = {
    start_col = status_at,
    end_col = -1,
    hl_group = "RoomPlanWorkspaceMuted",
  }
  local alert = ctx.conflicted and "CONFLICT" or (ctx.dirty and "DIRTY" or nil)
  if alert then
    local alert_at = line:find(alert, status_at + 1, true)
    if alert_at then
      highlights[#highlights + 1] = {
        start_col = alert_at - 1,
        end_col = alert_at - 1 + #alert,
        hl_group = ctx.conflicted and "RoomPlanWorkspaceError" or "RoomPlanWorkspaceWarning",
      }
    end
  end
  common.line(document, line, { highlights = highlights })
  document.actions = actions
  document.shown_actions = shown
  document.overflow_actions = hidden
  document.overflow_count = hidden_count
  document.status = status_text
  return common.finish(document, opts.height or 1)
end

return M
