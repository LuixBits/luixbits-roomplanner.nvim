-- Pure transient state and responsive layout calculations for the RoomPlan
-- workspace.  This module intentionally has no dependency on Neovim.

local M = {}

local defaults = require("roomplan.ui.workspace_defaults").get()

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

local function pane_name(pane)
  if pane == "navigator" or pane == "left" or pane == "objects" or pane == "issues" then
    return "navigator"
  end
  if pane == "details" or pane == "right" or pane == "properties" then return "details" end
  return nil
end

-- The optional visibility argument may be either the visibility table itself
-- or the complete workspace state.
local function resolve_visibility(options, visibility)
  local source = visibility
  local focused_pane
  local active_side
  if type(source) == "table" and type(source.visibility) == "table" then
    focused_pane = source.focused_pane
    active_side = source.active_side
    source = source.visibility
  end
  if type(source) ~= "table" then source = options end
  local navigator = source.navigator
  local details = source.details
  if navigator == nil then navigator = options.navigator_visible end
  if details == nil then details = options.details_visible end
  return {
    navigator = navigator ~= false,
    details = details == true,
    focused_pane = focused_pane,
    active_side = active_side,
  }
end

local function pane(width, height, visible, extra)
  local result = {
    width = visible and math.max(0, width or 0) or 0,
    height = height,
    persistent = visible,
    visible = visible,
  }
  for key, value in pairs(extra or {}) do result[key] = value end
  return result
end

---Calculate pane dimensions without touching editor state.
---@return table
function M.calculate_layout(columns, lines, options, visibility)
  local opts = merged(options)
  columns = math.max(1, math.floor(tonumber(columns) or 1))
  lines = math.max(1, math.floor(tonumber(lines) or 1))
  local kind = choose_kind(columns, lines, opts)
  local requested = resolve_visibility(opts, visibility)
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
    -- Keep pane entries present for callers that render or inspect all roles;
    -- compact mode exposes them through the shared drawer instead of splits.
    result.panes.left = pane(0, content_height, false)
    result.panes.properties = pane(0, content_height, false)
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
    -- Medium layouts have room for one persistent side pane. Prefer the pane
    -- that currently owns focus; otherwise the navigator remains the anchor.
    local show_details = requested.details and not requested.navigator
      or requested.details and (requested.focused_pane == "properties" or requested.active_side == "details")
    local show_navigator = requested.navigator and not show_details
    local has_side = show_navigator or show_details
    local separator = has_side and 1 or 0
    local desired = show_details and opts.right_width or opts.left_width
    local maximum_side = math.max(0, columns - opts.min_canvas_width - separator)
    local side = has_side and clamp(desired, math.min(24, maximum_side), maximum_side) or 0
    if side == 0 then
      show_navigator, show_details, separator = false, false, 0
    end
    local canvas = math.max(1, columns - side - separator)
    result.panes.left = pane(side, content_height, show_navigator)
    result.panes.canvas = { width = canvas, height = content_height, persistent = true }
    result.panes.properties = pane(side, content_height, show_details, { dock = "left" })
    result.panes.footer = { width = columns, height = footer_height, persistent = footer_height > 0 }
    return result
  end

  -- Side panes yield space before the canvas does. Hidden panes consume neither
  -- width nor a separator, so the canvas expands without changing layout kind.
  local side_count = (requested.navigator and 1 or 0) + (requested.details and 1 or 0)
  local separators = side_count
  local maximum_budget = math.max(0, columns - separators - 1)
  local side_budget = math.min(maximum_budget,
    math.max(0, columns - opts.min_canvas_width - separators))
  local desired_total = (requested.navigator and opts.left_width or 0)
    + (requested.details and opts.right_width or 0)
  local left, right = 0, 0
  if desired_total > 0 and desired_total <= side_budget then
    left = requested.navigator and opts.left_width or 0
    right = requested.details and opts.right_width or 0
  elseif desired_total > 0 and side_budget > 0 then
    left = requested.navigator and math.floor(side_budget * opts.left_width / desired_total) or 0
    right = requested.details and (side_budget - left) or 0
    if requested.navigator and requested.details and side_budget >= 2 then
      left = math.max(1, math.min(side_budget - 1, left))
      right = side_budget - left
    end
  end
  local show_navigator = requested.navigator and left > 0
  local show_details = requested.details and right > 0
  separators = (show_navigator and 1 or 0) + (show_details and 1 or 0)
  local canvas = math.max(1, columns - left - right - separators)
  result.panes.left = pane(left, content_height, show_navigator)
  result.panes.canvas = { width = canvas, height = content_height, persistent = true }
  result.panes.properties = pane(right, content_height, show_details)
  result.panes.footer = { width = columns, height = footer_height, persistent = footer_height > 0 }
  return result
end

function M.initial(options)
  local opts = merged(options)
  return {
    layout = "compact",
    focused_pane = "canvas",
    active_side = opts.navigator_visible == false and opts.details_visible == true and "details" or "navigator",
    left_view = "objects",
    drawer = nil,
    visibility = {
      navigator = opts.navigator_visible ~= false,
      details = opts.details_visible == true,
    },
    expanded = {},
    collapsed_sections = { advanced = true, source = true },
    filters = { objects = "", issues = "" },
    interaction = "NAV",
    cursor_world = nil,
    zoom = nil,
  }
end

function M.focus_order(state)
  if not state or state.layout == "compact" then
    return { "objects", "issues", "canvas", "properties" }
  end
  local visibility = state.visibility or { navigator = true, details = false }
  local order = {}
  if visibility.navigator ~= false then
    order[#order + 1] = "objects"
    order[#order + 1] = "issues"
  end
  order[#order + 1] = "canvas"
  if visibility.details ~= false then order[#order + 1] = "properties" end
  return order
end

function M.next_focus(state, direction)
  local order = M.focus_order(state)
  local current
  for index, pane in ipairs(order) do
    if pane == state.focused_pane then current = index; break end
  end
  if current == nil then return "canvas" end
  direction = direction == -1 and -1 or 1
  return order[((current - 1 + direction) % #order) + 1]
end

local function ensure_transient_state(state)
  if type(state.visibility) ~= "table" then
    state.visibility = { navigator = true, details = false }
  end
  if state.visibility.navigator == nil then state.visibility.navigator = true end
  if state.visibility.details == nil then state.visibility.details = false end
  if state.active_side ~= "navigator" and state.active_side ~= "details" then
    state.active_side = state.focused_pane == "properties" and "details" or "navigator"
  end
  if type(state.collapsed_sections) ~= "table" then
    state.collapsed_sections = { advanced = true, source = true }
  end
  return state
end

local function set_pane_visible(state, name, visible)
  state.visibility[name] = visible ~= false
  if visible ~= false then
    state.active_side = name
  elseif state.active_side == name then
    local other = name == "navigator" and "details" or "navigator"
    if state.visibility[other] then state.active_side = other end
  end
  if visible == false then
    local focused = pane_name(state.focused_pane)
    if focused == name then state.focused_pane = "canvas" end
  end
end

---Reduce one UI event. The input table is never mutated.
function M.reduce(state, event)
  state = ensure_transient_state(copy(state or M.initial()))
  event = event or {}
  local name = event.type
  if name == "layout" then
    state.layout = assert(event.kind, "layout event requires kind")
    if state.layout ~= "compact" then
      state.drawer = nil
      local focused = pane_name(state.focused_pane)
      if focused then set_pane_visible(state, focused, true) end
    end
  elseif name == "focus" then
    local pane = event.pane or "canvas"
    state.focused_pane = pane
    if pane == "objects" or pane == "issues" then
      state.active_side = "navigator"
      state.left_view = pane
      if state.layout == "compact" then state.drawer = pane end
      if state.layout ~= "compact" then set_pane_visible(state, "navigator", true) end
    elseif pane == "properties" then
      state.active_side = "details"
      if state.layout == "compact" then state.drawer = pane end
      if state.layout ~= "compact" then set_pane_visible(state, "details", true) end
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
      if event.pane == "objects" or event.pane == "issues" then
        state.left_view = event.pane
        state.active_side = "navigator"
      elseif event.pane == "properties" then
        state.active_side = "details"
      end
    end
  elseif name == "toggle_pane" then
    local target = assert(pane_name(event.pane), "toggle_pane requires navigator or details")
    if state.layout == "compact" then
      local role = target == "details" and "properties" or state.left_view
      return M.reduce(state, { type = "drawer", pane = role })
    end
    set_pane_visible(state, target, not state.visibility[target])
  elseif name == "set_pane_visible" then
    local target = assert(pane_name(event.pane), "set_pane_visible requires navigator or details")
    assert(type(event.visible) == "boolean", "set_pane_visible requires visible boolean")
    set_pane_visible(state, target, event.visible)
  elseif name == "left_view" then
    state.left_view = event.view == "issues" and "issues" or "objects"
  elseif name == "toggle_expanded" then
    local id = assert(event.id, "toggle_expanded requires id")
    state.expanded[id] = state.expanded[id] == false and true or false
  elseif name == "set_expanded" then
    state.expanded[assert(event.id, "set_expanded requires id")] = event.value ~= false
  elseif name == "toggle_section" then
    local key = assert(event.key, "toggle_section requires key")
    state.collapsed_sections[key] = state.collapsed_sections[key] ~= true
  elseif name == "set_section" then
    local key = assert(event.key, "set_section requires key")
    assert(type(event.expanded) == "boolean", "set_section requires expanded boolean")
    state.collapsed_sections[key] = not event.expanded
  elseif name == "filter" then
    state.filters[event.pane or "objects"] = tostring(event.value or "")
  elseif name == "interaction" then
    state.interaction = event.mode or "NAV"
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
