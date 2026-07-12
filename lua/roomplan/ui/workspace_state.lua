-- Pure transient state and responsive layout calculations for the RoomPlan
-- workspace.  This module intentionally has no dependency on Neovim.

local M = {}

local defaults = {
  layout = "auto",
  left_width = 32,
  right_width = 36,
  wide_min_columns = 120,
  compact_max_columns = 89,
  compact_min_rows = 22,
  min_canvas_width = 55,
  min_canvas_height = 10,
  footer_height = 2,
}

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = copy(item) end
  return result
end

local function merged(opts)
  local result = copy(defaults)
  for key, value in pairs(opts or {}) do
    if result[key] ~= nil then result[key] = value end
  end
  return result
end

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function choose_kind(columns, lines, opts)
  if opts.layout ~= "auto" then return opts.layout end
  local usable_height = lines - math.min(opts.footer_height, math.max(0, lines - 1))
  if columns <= opts.compact_max_columns or lines < opts.compact_min_rows
    or usable_height < opts.min_canvas_height then
    return "compact"
  end
  if columns >= opts.wide_min_columns then return "wide" end
  return "medium"
end

---Calculate pane dimensions without touching editor state.
---@return table
function M.calculate_layout(columns, lines, options)
  local opts = merged(options)
  columns = math.max(1, math.floor(tonumber(columns) or 1))
  lines = math.max(1, math.floor(tonumber(lines) or 1))
  local kind = choose_kind(columns, lines, opts)
  if kind ~= "wide" and kind ~= "medium" and kind ~= "compact" then
    error("unsupported RoomPlan workspace layout: " .. tostring(kind), 2)
  end

  local footer_height = math.min(opts.footer_height, math.max(0, lines - 1))
  local content_height = math.max(1, lines - footer_height)
  local result = {
    kind = kind,
    columns = columns,
    lines = lines,
    footer_height = footer_height,
    content_height = content_height,
    compact_reason = nil,
    panes = {},
  }

  if kind == "compact" then
    result.panes.canvas = { width = columns, height = content_height, persistent = true }
    result.panes.footer = { width = columns, height = footer_height, persistent = footer_height > 0 }
    result.panes.drawer = {
      width = math.max(1, math.min(columns - 4, math.max(34, math.floor(columns * 0.82)))),
      height = math.max(1, math.min(content_height - 2, math.max(8, math.floor(content_height * 0.78)))),
      persistent = false,
    }
    result.compact_reason = columns <= opts.compact_max_columns
        and string.format("compact mode: terminal width %d", columns)
      or string.format("compact mode: terminal height %d", lines)
    return result
  end

  if kind == "medium" then
    local maximum_left = math.max(1, columns - opts.min_canvas_width - 1)
    local left = clamp(opts.left_width, math.min(24, maximum_left), maximum_left)
    local canvas = math.max(1, columns - left - 1)
    result.panes.left = { width = left, height = content_height, persistent = true }
    result.panes.canvas = { width = canvas, height = content_height, persistent = true }
    result.panes.properties = { width = left, height = content_height, persistent = false, dock = "left" }
    result.panes.footer = { width = columns, height = footer_height, persistent = footer_height > 0 }
    return result
  end

  -- Side panes yield space before the canvas does.  At the default 120-column
  -- breakpoint this preserves the promised 55-column drawable canvas.
  local side_budget = math.max(2, columns - opts.min_canvas_width - 2)
  local desired_total = opts.left_width + opts.right_width
  local left
  local right
  if desired_total <= side_budget then
    left, right = opts.left_width, opts.right_width
  else
    left = math.floor(side_budget * opts.left_width / desired_total)
    right = side_budget - left
  end
  left = math.max(1, left)
  right = math.max(1, right)
  local canvas = math.max(1, columns - left - right - 2)
  result.panes.left = { width = left, height = content_height, persistent = true }
  result.panes.canvas = { width = canvas, height = content_height, persistent = true }
  result.panes.properties = { width = right, height = content_height, persistent = true }
  result.panes.footer = { width = columns, height = footer_height, persistent = footer_height > 0 }
  return result
end

function M.initial(options)
  return {
    layout = "compact",
    focused_pane = "canvas",
    left_view = "objects",
    drawer = nil,
    expanded = {},
    filters = { objects = "", issues = "" },
    interaction = "NAV",
    preview = nil,
    cursor_world = nil,
    zoom = nil,
    selection = nil,
    options = merged(options),
  }
end

function M.focus_order()
  return { "objects", "issues", "canvas", "properties" }
end

function M.next_focus(state, direction)
  local order = M.focus_order()
  local current = 1
  for index, pane in ipairs(order) do
    if pane == state.focused_pane then current = index; break end
  end
  direction = direction == -1 and -1 or 1
  return order[((current - 1 + direction) % #order) + 1]
end

---Reduce one UI event. The input table is never mutated.
function M.reduce(state, event)
  state = copy(state or M.initial())
  event = event or {}
  local name = event.type
  if name == "layout" then
    state.layout = assert(event.kind, "layout event requires kind")
    if state.layout ~= "compact" then state.drawer = nil end
  elseif name == "focus" then
    local pane = event.pane or "canvas"
    state.focused_pane = pane
    if pane == "objects" or pane == "issues" or pane == "properties" then
      state.left_view = pane
      if state.layout == "compact" then state.drawer = pane end
    elseif pane == "canvas" then
      state.drawer = nil
    end
  elseif name == "cycle_focus" then
    return M.reduce(state, { type = "focus", pane = M.next_focus(state, event.direction) })
  elseif name == "drawer" then
    if event.pane == nil or state.drawer == event.pane then
      state.drawer = nil
      state.focused_pane = "canvas"
    else
      state.drawer = event.pane
      state.focused_pane = event.pane
      state.left_view = event.pane
    end
  elseif name == "left_view" then
    state.left_view = event.view == "issues" and "issues" or "objects"
  elseif name == "toggle_expanded" then
    local id = assert(event.id, "toggle_expanded requires id")
    state.expanded[id] = state.expanded[id] == false and true or false
  elseif name == "set_expanded" then
    state.expanded[assert(event.id, "set_expanded requires id")] = event.value ~= false
  elseif name == "filter" then
    state.filters[event.pane or "objects"] = tostring(event.value or "")
  elseif name == "selection" then
    state.selection = copy(event.selection)
  elseif name == "interaction" then
    state.interaction = event.mode or "NAV"
  elseif name == "preview" then
    state.preview = copy(event.value)
  elseif name == "cursor" then
    state.cursor_world = copy(event.world)
    if event.zoom ~= nil then state.zoom = event.zoom end
  elseif name == "escape" then
    if state.drawer then
      state.drawer = nil
      state.focused_pane = "canvas"
    elseif state.interaction ~= "NAV" then
      state.interaction = "NAV"
    elseif state.focused_pane ~= "canvas" then
      state.focused_pane = "canvas"
    else
      state.selection = nil
    end
  elseif name ~= nil then
    error("unknown RoomPlan workspace event: " .. tostring(name), 2)
  end
  return state
end

function M.defaults()
  return copy(defaults)
end

return M
