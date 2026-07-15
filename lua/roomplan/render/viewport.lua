-- Pure viewport transforms.  Screen coordinates are zero-based logical cells;
-- canvas.lua performs the final conversion to Neovim's one-based rows.

local M = {}

local DEFAULT_MM_PER_COLUMN = 100
local DEFAULT_CELL_ASPECT = 2

local function finite_positive(value)
  return type(value) == "number" and value == value and value > 0 and value < math.huge
end

local function finite(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function clamp(value, minimum, maximum)
  if finite_positive(minimum) and value < minimum then
    value = minimum
  end
  if finite_positive(maximum) and value > maximum then
    value = maximum
  end
  return value
end

local function normalized_rotation(value)
  value = tonumber(value) or 0
  if not finite(value) then return 0 end
  return math.floor(value) % 4
end

function M.rotation(viewport)
  return normalized_rotation(type(viewport) == "table" and viewport.rotation_quarters or 0)
end

---Convert a direction expressed in screen axes (right/up) to world axes
---(east/north) for the active quarter-turn projection.
function M.view_delta_to_world(viewport, dx, dy)
  local rotation = M.rotation(viewport)
  if rotation == 1 then
    return -dy, dx
  elseif rotation == 2 then
    return -dx, -dy
  elseif rotation == 3 then
    return dy, -dx
  end
  return dx, dy
end

---Convert a world-axis direction to visible screen axes (right/up).
function M.world_delta_to_view(viewport, dx, dy)
  local rotation = M.rotation(viewport)
  if rotation == 1 then
    return dy, -dx
  elseif rotation == 2 then
    return -dx, -dy
  elseif rotation == 3 then
    return -dy, dx
  end
  return dx, dy
end

---Return the visible cell scale for each world axis.
function M.world_axis_scales(viewport)
  if M.rotation(viewport) % 2 == 1 then
    return viewport.mm_per_row, viewport.mm_per_column
  end
  return viewport.mm_per_column, viewport.mm_per_row
end

---Return a configured-step multiple large enough to move at least one visible
---cell on the active world axis. Fine movement deliberately bypasses this.
function M.visible_move_step(viewport, dx, dy, minimum_mm)
  local scale_x, scale_y = M.world_axis_scales(viewport)
  local cell_mm
  if dx ~= 0 and dy ~= 0 then cell_mm = math.max(scale_x, scale_y)
  elseif dx ~= 0 then cell_mm = scale_x
  else cell_mm = scale_y end
  if not finite_positive(cell_mm) then return math.max(1, math.floor(minimum_mm or 1)) end
  local minimum = finite_positive(minimum_mm) and math.floor(minimum_mm) or 1
  local multiples = math.max(1, math.ceil(cell_mm / minimum - 1e-9))
  return multiples * minimum
end

function M.copy(viewport)
  return {
    world_left_mm = viewport.world_left_mm,
    world_top_mm = viewport.world_top_mm,
    mm_per_column = viewport.mm_per_column,
    mm_per_row = viewport.mm_per_row,
    cell_aspect = viewport.cell_aspect,
    rotation_quarters = M.rotation(viewport),
  }
end

---Create a validated viewport.
---@param opts table|nil
---@return table
function M.new(opts)
  opts = opts or {}
  local mm_per_column = finite_positive(opts.mm_per_column) and opts.mm_per_column or DEFAULT_MM_PER_COLUMN
  local aspect = finite_positive(opts.cell_aspect) and opts.cell_aspect or nil
  local mm_per_row = finite_positive(opts.mm_per_row) and opts.mm_per_row or nil

  if not aspect and mm_per_row then
    aspect = mm_per_row / mm_per_column
  end
  aspect = finite_positive(aspect) and aspect or DEFAULT_CELL_ASPECT
  if not mm_per_row then
    mm_per_row = mm_per_column * aspect
  else
    aspect = mm_per_row / mm_per_column
  end

  return {
    world_left_mm = finite(opts.world_left_mm) and opts.world_left_mm or 0,
    world_top_mm = finite(opts.world_top_mm) and opts.world_top_mm or 0,
    mm_per_column = mm_per_column,
    mm_per_row = mm_per_row,
    cell_aspect = aspect,
    rotation_quarters = normalized_rotation(opts.rotation_quarters),
  }
end

function M.valid(viewport)
  return type(viewport) == "table"
    and finite(viewport.world_left_mm)
    and finite(viewport.world_top_mm)
    and finite_positive(viewport.mm_per_column)
    and finite_positive(viewport.mm_per_row)
end

function M.world_to_screen(viewport, x, y)
  local dx = x - viewport.world_left_mm
  local dy = y - viewport.world_top_mm
  local rotation = M.rotation(viewport)
  if rotation == 1 then
    return dy / viewport.mm_per_column, dx / viewport.mm_per_row
  elseif rotation == 2 then
    return -dx / viewport.mm_per_column, dy / viewport.mm_per_row
  elseif rotation == 3 then
    return -dy / viewport.mm_per_column, -dx / viewport.mm_per_row
  end
  return dx / viewport.mm_per_column, -dy / viewport.mm_per_row
end

M.project = M.world_to_screen

function M.screen_to_world(viewport, column, row)
  local column_mm = column * viewport.mm_per_column
  local row_mm = row * viewport.mm_per_row
  local rotation = M.rotation(viewport)
  if rotation == 1 then
    return viewport.world_left_mm + row_mm, viewport.world_top_mm + column_mm
  elseif rotation == 2 then
    return viewport.world_left_mm - column_mm, viewport.world_top_mm + row_mm
  elseif rotation == 3 then
    return viewport.world_left_mm - row_mm, viewport.world_top_mm - column_mm
  end
  return viewport.world_left_mm + column_mm, viewport.world_top_mm - row_mm
end

M.unproject = M.screen_to_world

function M.visible_bounds(viewport, columns, rows)
  local last_column = math.max(0, columns - 1)
  local last_row = math.max(0, rows - 1)
  local corners = {
    { M.screen_to_world(viewport, 0, 0) },
    { M.screen_to_world(viewport, last_column, 0) },
    { M.screen_to_world(viewport, 0, last_row) },
    { M.screen_to_world(viewport, last_column, last_row) },
  }
  local left, right = corners[1][1], corners[1][1]
  local bottom, top = corners[1][2], corners[1][2]
  for index = 2, #corners do
    left, right = math.min(left, corners[index][1]), math.max(right, corners[index][1])
    bottom, top = math.min(bottom, corners[index][2]), math.max(top, corners[index][2])
  end
  return {
    left = left,
    right = right,
    top = top,
    bottom = bottom,
  }
end

local function origin_for_anchor(rotation, world_x, world_y, screen_x, screen_y, column_scale, row_scale)
  local column_mm = screen_x * column_scale
  local row_mm = screen_y * row_scale
  if rotation == 1 then
    return world_x - row_mm, world_y - column_mm
  elseif rotation == 2 then
    return world_x + column_mm, world_y - row_mm
  elseif rotation == 3 then
    return world_x + row_mm, world_y + column_mm
  end
  return world_x - column_mm, world_y + row_mm
end

local function normalized_bounds(bounds)
  if type(bounds) ~= "table" or bounds.empty then
    return nil
  end
  local left = bounds.left or bounds.min_x
  local right = bounds.right or bounds.max_x
  local bottom = bounds.bottom or bounds.min_y
  local top = bounds.top or bounds.max_y
  if not finite(left) or not finite(right) or not finite(bottom) or not finite(top) then
    return nil
  end
  if right < left then
    left, right = right, left
  end
  if top < bottom then
    bottom, top = top, bottom
  end
  return left, bottom, right, top
end

---Fit bounds to a logical drawable area while preserving cell aspect.
---@param bounds table
---@param columns integer
---@param rows integer
---@param opts table|nil Existing viewport or render configuration.
---@return table
function M.fit(bounds, columns, rows, opts)
  opts = opts or {}
  columns = math.max(1, math.floor(columns or 1))
  rows = math.max(1, math.floor(rows or 1))
  local base = M.valid(opts) and M.copy(opts) or M.new(opts)
  local aspect = base.mm_per_row / base.mm_per_column
  local rotation = M.rotation(base)
  local margin = tonumber(opts.fit_margin_cells or opts.margin_cells) or 2
  margin = math.max(0, margin)
  local usable_columns = math.max(1, columns - 2 * margin)
  local usable_rows = math.max(1, rows - 2 * margin)
  local left, bottom, right, top = normalized_bounds(bounds)

  if not left then
    local scale = clamp(base.mm_per_column, opts.min_mm_per_column, opts.max_mm_per_column)
    local row_scale = scale * aspect
    local origin_x, origin_y = origin_for_anchor(
      rotation, 0, 0, (columns - 1) / 2, (rows - 1) / 2, scale, row_scale
    )
    return M.new({
      world_left_mm = origin_x,
      world_top_mm = origin_y,
      mm_per_column = scale,
      mm_per_row = row_scale,
      rotation_quarters = rotation,
    })
  end

  local span_x = math.max(0, right - left)
  local span_y = math.max(0, top - bottom)
  local scale_x, scale_y
  if rotation % 2 == 1 then
    scale_x = span_y > 0 and span_y / usable_columns or 0
    scale_y = span_x > 0 and span_x / (usable_rows * aspect) or 0
  else
    scale_x = span_x > 0 and span_x / usable_columns or 0
    scale_y = span_y > 0 and span_y / (usable_rows * aspect) or 0
  end
  local scale = math.max(scale_x, scale_y)
  if not finite_positive(scale) then
    scale = base.mm_per_column
  end
  scale = clamp(scale, opts.min_mm_per_column, opts.max_mm_per_column)
  local row_scale = scale * aspect
  local center_x = (left + right) / 2
  local center_y = (bottom + top) / 2
  local origin_x, origin_y = origin_for_anchor(
    rotation, center_x, center_y, (columns - 1) / 2, (rows - 1) / 2, scale, row_scale
  )

  return M.new({
    world_left_mm = origin_x,
    world_top_mm = origin_y,
    mm_per_column = scale,
    mm_per_row = row_scale,
    rotation_quarters = rotation,
  })
end

function M.fit_scene(scene, columns, rows, opts)
  return M.fit(scene and scene.bounds or nil, columns, rows, opts)
end

local function anchor_values(viewport, anchor, columns, rows)
  anchor = anchor or {}
  local screen_x = anchor.screen_x or anchor.column or anchor.col
  local screen_y = anchor.screen_y or anchor.row
  if not finite(screen_x) then
    screen_x = math.max(0, ((columns or 1) - 1) / 2)
  end
  if not finite(screen_y) then
    screen_y = math.max(0, ((rows or 1) - 1) / 2)
  end
  local world_x = anchor.world_x or anchor.x
  local world_y = anchor.world_y or anchor.y
  if not finite(world_x) or not finite(world_y) then
    world_x, world_y = M.screen_to_world(viewport, screen_x, screen_y)
  elseif anchor.screen_x == nil and anchor.column == nil and anchor.col == nil then
    screen_x, screen_y = M.world_to_screen(viewport, world_x, world_y)
  end
  return world_x, world_y, screen_x, screen_y
end

---Scale a viewport. factor > 1 zooms out; factor < 1 zooms in.
function M.zoom(viewport, factor, anchor, limits)
  assert(M.valid(viewport), "invalid viewport")
  assert(finite_positive(factor), "zoom factor must be positive")
  limits = limits or {}
  local world_x, world_y, screen_x, screen_y = anchor_values(
    viewport,
    anchor,
    limits.columns,
    limits.rows
  )
  local new_column_scale = clamp(
    viewport.mm_per_column * factor,
    limits.min_mm_per_column,
    limits.max_mm_per_column
  )
  local ratio = viewport.mm_per_row / viewport.mm_per_column
  local new_row_scale = new_column_scale * ratio
  local rotation = M.rotation(viewport)
  local origin_x, origin_y = origin_for_anchor(
    rotation, world_x, world_y, screen_x, screen_y, new_column_scale, new_row_scale
  )
  return M.new({
    world_left_mm = origin_x,
    world_top_mm = origin_y,
    mm_per_column = new_column_scale,
    mm_per_row = new_row_scale,
    rotation_quarters = rotation,
  })
end

function M.zoom_in(viewport, factor, anchor, limits)
  factor = factor or 1.25
  return M.zoom(viewport, 1 / factor, anchor, limits)
end

function M.zoom_out(viewport, factor, anchor, limits)
  return M.zoom(viewport, factor or 1.25, anchor, limits)
end

---Rotate the view in 90-degree clockwise steps while preserving an anchor.
---The model remains in world coordinates; only projection changes.
function M.rotate(viewport, delta_quarters, anchor, limits)
  assert(M.valid(viewport), "invalid viewport")
  limits = limits or {}
  local world_x, world_y, screen_x, screen_y = anchor_values(
    viewport,
    anchor,
    limits.columns,
    limits.rows
  )
  local rotation = normalized_rotation(M.rotation(viewport) + (tonumber(delta_quarters) or 1))
  local origin_x, origin_y = origin_for_anchor(
    rotation,
    world_x,
    world_y,
    screen_x,
    screen_y,
    viewport.mm_per_column,
    viewport.mm_per_row
  )
  return M.new({
    world_left_mm = origin_x,
    world_top_mm = origin_y,
    mm_per_column = viewport.mm_per_column,
    mm_per_row = viewport.mm_per_row,
    rotation_quarters = rotation,
  })
end

---Pan by world millimetres. Positive Y pans north/up.
function M.pan(viewport, delta_x_mm, delta_y_mm)
  local result = M.copy(viewport)
  result.world_left_mm = result.world_left_mm + (delta_x_mm or 0)
  result.world_top_mm = result.world_top_mm + (delta_y_mm or 0)
  return result
end

---Pan by logical cells. Positive row cells pan north/up, matching pan intent
---rather than buffer row direction.
function M.pan_cells(viewport, columns, rows)
  local origin_x, origin_y = M.screen_to_world(viewport, 0, 0)
  local target_x, target_y = M.screen_to_world(viewport, columns or 0, -(rows or 0))
  return M.pan(viewport, target_x - origin_x, target_y - origin_y)
end

---Shift the viewport just enough to include a world point plus a cell margin.
function M.ensure_visible(viewport, x, y, columns, rows, margin_cells)
  local result = M.copy(viewport)
  margin_cells = math.max(0, margin_cells or 1)
  local column, row = M.world_to_screen(result, x, y)
  local min_column = math.min(margin_cells, math.max(0, columns - 1))
  local max_column = math.max(min_column, columns - 1 - margin_cells)
  local min_row = math.min(margin_cells, math.max(0, rows - 1))
  local max_row = math.max(min_row, rows - 1 - margin_cells)
  local target_column = math.max(min_column, math.min(max_column, column))
  local target_row = math.max(min_row, math.min(max_row, row))
  result.world_left_mm, result.world_top_mm = origin_for_anchor(
    M.rotation(result),
    x,
    y,
    target_column,
    target_row,
    result.mm_per_column,
    result.mm_per_row
  )
  return result
end

return M
