-- Pure label primitive helpers.  Display-width sanitization deliberately lives
-- in render/text.lua because it needs an injected editor width function.

local M = {}

local outlet_types = require("roomplan.outlet_types")

local function label(text, x, y, options)
  options = options or {}
  return {
    kind = options.kind or "label",
    layer = options.layer or 70,
    text = tostring(text or ""),
    x = x,
    y = y,
    align = options.align or "center",
    role = options.role,
    ref = options.ref,
    max_cells = options.max_cells,
    candidates = options.candidates,
    placement = options.placement,
    allow_truncate = options.allow_truncate ~= false,
    priority = options.priority or 0,
    order = options.order or 0,
  }
end

local function add_candidate(candidates, x, y)
  for _, candidate in ipairs(candidates) do
    if candidate[1] == x and candidate[2] == y then return end
  end
  candidates[#candidates + 1] = { x, y }
end

function M.at(text, x, y, options)
  return label(text, x, y, options)
end

function M.room(room, ref, order, geometry)
  if geometry then
    local bounds = geometry.bounds
    local anchor = geometry.anchor
    local cx = anchor and anchor.x or bounds.center_x
    local cy = anchor and anchor.y or bounds.center_y
    local candidates = {}
    add_candidate(candidates, cx, cy)
    add_candidate(candidates, bounds.center_x, bounds.center_y)
    for _, rectangle in ipairs(geometry.rectangles or {}) do
      add_candidate(candidates, (rectangle.left + rectangle.right) / 2,
        (rectangle.bottom + rectangle.top) / 2)
    end
    return label(room.name or room.id, cx, cy, {
      ref = ref,
      role = "room_label",
      candidates = candidates,
      priority = 30,
      order = order,
    })
  end
  local x = room.origin_mm[1]
  local y = room.origin_mm[2]
  local width = room.size_mm[1]
  local depth = room.size_mm[2]
  local cx = x + width / 2
  local cy = y + depth / 2
  local candidates = {
    { cx, cy },
    { cx, y + depth * 0.65 },
    { cx, y + depth * 0.35 },
    { x + width * 0.35, cy },
    { x + width * 0.65, cy },
  }
  return label(room.name or room.id, cx, cy, {
    ref = ref,
    role = "room_label",
    candidates = candidates,
    priority = 30,
    order = order,
  })
end

function M.furniture(item, bounds, ref, order, anchor)
  local x = anchor and anchor.x or (bounds.left + bounds.right) / 2
  local y = anchor and anchor.y or (bounds.bottom + bounds.top) / 2
  local candidates = {}
  add_candidate(candidates, x, y)
  add_candidate(candidates, (bounds.left + bounds.right) / 2, (bounds.bottom + bounds.top) / 2)
  for _, x_ratio in ipairs({ 0.35, 0.65 }) do
    for _, y_ratio in ipairs({ 0.35, 0.65 }) do
      add_candidate(candidates,
        bounds.left + (bounds.right - bounds.left) * x_ratio,
        bounds.bottom + (bounds.top - bounds.bottom) * y_ratio)
    end
  end
  return label(item.name or item.id, x, y, {
    ref = ref,
    role = "furniture_label",
    candidates = candidates,
    priority = 20,
    order = order,
  })
end

local function decimal(value)
  if value == math.floor(value) then
    return string.format("%d", value)
  end
  return string.format("%.1f", value):gsub("%.0$", "")
end

function M.format_length(mm)
  if math.abs(mm) >= 1000 then
    return decimal(mm / 1000) .. "m"
  end
  return decimal(mm) .. "mm"
end

function M.edge_dimension(edge, ref, order, priority)
  local horizontal = edge.orientation == "horizontal"
  local midpoint = edge.start + (edge.finish - edge.start) / 2
  return label(M.format_length(edge.finish - edge.start),
    horizontal and midpoint or edge.fixed,
    horizontal and edge.fixed or midpoint, {
      kind = "dimension",
      ref = ref or edge.ref,
      role = "dimension",
      placement = horizontal and "horizontal_edge" or "vertical_edge",
      allow_truncate = false,
      priority = priority or 0,
      order = order,
    })
end

function M.furniture_dimensions(bounds, ref, order)
  return {
    M.edge_dimension({
      orientation = "horizontal", fixed = bounds.bottom,
      start = bounds.left, finish = bounds.right,
    }, ref, order, 20),
    M.edge_dimension({
      orientation = "vertical", fixed = bounds.left,
      start = bounds.bottom, finish = bounds.top,
    }, ref, order, 20),
  }
end

function M.door_dimension(aperture, ref, order)
  return M.opening_dimension(aperture, ref, order)
end

function M.opening_dimension(aperture, ref, order)
  return M.edge_dimension({
    orientation = aperture.orientation,
    fixed = aperture.fixed,
    start = aperture.start,
    finish = aperture.finish,
  }, ref, order, 30)
end

function M.outlet(outlet, marker, ref, order)
  local slots = outlet.slots or 0
  local type_label = outlet_types.label(outlet.outlet_type) or tostring(outlet.outlet_type or "Outlet")
  local text = string.format("%s · %d slot%s", type_label,
    slots, slots == 1 and "" or "s")
  local x, y = marker.p[1], marker.p[2]
  local candidates
  if marker.placement == "floor" then
    candidates = { { x, y + 250 }, { x + 250, y }, { x, y - 250 }, { x - 250, y }, { x, y } }
  elseif marker.side == "north" then
    candidates = { { x, y - 250 }, { x, y + 250 }, { x, y } }
  elseif marker.side == "south" then
    candidates = { { x, y + 250 }, { x, y - 250 }, { x, y } }
  elseif marker.side == "east" then
    candidates = { { x - 250, y }, { x + 250, y }, { x, y } }
  else
    candidates = { { x + 250, y }, { x - 250, y }, { x, y } }
  end
  return label(text, x, y, {
    ref = ref,
    role = "outlet",
    candidates = candidates,
    priority = 25,
    order = order,
  })
end

return M
