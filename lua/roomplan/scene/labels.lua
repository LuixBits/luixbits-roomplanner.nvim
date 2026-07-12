-- Pure label primitive helpers.  Display-width sanitization deliberately lives
-- in render/text.lua because it needs an injected editor width function.

local M = {}

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
    order = options.order or 0,
  }
end

function M.at(text, x, y, options)
  return label(text, x, y, options)
end

function M.room(room, ref, order)
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
    order = order,
  })
end

function M.furniture(item, bounds, ref, order)
  return label(item.name or item.id, (bounds.left + bounds.right) / 2, (bounds.bottom + bounds.top) / 2, {
    ref = ref,
    role = "furniture_label",
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

function M.room_dimensions(room, ref, order)
  local x = room.origin_mm[1]
  local y = room.origin_mm[2]
  local width = room.size_mm[1]
  local depth = room.size_mm[2]
  return {
    label(M.format_length(width), x + width / 2, y, {
      kind = "dimension",
      ref = ref,
      role = "dimension",
      order = order,
    }),
    label(M.format_length(depth), x, y + depth / 2, {
      kind = "dimension",
      ref = ref,
      role = "dimension",
      order = order,
    }),
  }
end

return M
