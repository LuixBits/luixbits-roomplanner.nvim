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

function M.copy(viewport)
  return {
    world_left_mm = viewport.world_left_mm,
    world_top_mm = viewport.world_top_mm,
    mm_per_column = viewport.mm_per_column,
    mm_per_row = viewport.mm_per_row,
    cell_aspect = viewport.cell_aspect,
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
  return (x - viewport.world_left_mm) / viewport.mm_per_column,
    (viewport.world_top_mm - y) / viewport.mm_per_row
end

M.project = M.world_to_screen

function M.screen_to_world(viewport, column, row)
  return viewport.world_left_mm + column * viewport.mm_per_column,
    viewport.world_top_mm - row * viewport.mm_per_row
end

M.unproject = M.screen_to_world

function M.visible_bounds(viewport, columns, rows)
  return {
    left = viewport.world_left_mm,
    right = viewport.world_left_mm + math.max(0, columns - 1) * viewport.mm_per_column,
    top = viewport.world_top_mm,
    bottom = viewport.world_top_mm - math.max(0, rows - 1) * viewport.mm_per_row,
  }
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
  local margin = tonumber(opts.fit_margin_cells or opts.margin_cells) or 2
  margin = math.max(0, margin)
  local usable_columns = math.max(1, columns - 2 * margin)
  local usable_rows = math.max(1, rows - 2 * margin)
  local left, bottom, right, top = normalized_bounds(bounds)

  if not left then
    local scale = clamp(base.mm_per_column, opts.min_mm_per_column, opts.max_mm_per_column)
    local row_scale = scale * aspect
    return M.new({
      world_left_mm = -((columns - 1) / 2) * scale,
      world_top_mm = ((rows - 1) / 2) * row_scale,
      mm_per_column = scale,
      mm_per_row = row_scale,
    })
  end

  local span_x = math.max(0, right - left)
  local span_y = math.max(0, top - bottom)
  local scale_x = span_x > 0 and span_x / usable_columns or 0
  local scale_y = span_y > 0 and span_y / (usable_rows * aspect) or 0
  local scale = math.max(scale_x, scale_y)
  if not finite_positive(scale) then
    scale = base.mm_per_column
  end
  scale = clamp(scale, opts.min_mm_per_column, opts.max_mm_per_column)
  local row_scale = scale * aspect
  local center_x = (left + right) / 2
  local center_y = (bottom + top) / 2

  return M.new({
    world_left_mm = center_x - ((columns - 1) / 2) * scale,
    world_top_mm = center_y + ((rows - 1) / 2) * row_scale,
    mm_per_column = scale,
    mm_per_row = row_scale,
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
  return M.new({
    world_left_mm = world_x - screen_x * new_column_scale,
    world_top_mm = world_y + screen_y * new_row_scale,
    mm_per_column = new_column_scale,
    mm_per_row = new_row_scale,
  })
end

function M.zoom_in(viewport, factor, anchor, limits)
  factor = factor or 1.25
  return M.zoom(viewport, 1 / factor, anchor, limits)
end

function M.zoom_out(viewport, factor, anchor, limits)
  return M.zoom(viewport, factor or 1.25, anchor, limits)
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
  return M.pan(
    viewport,
    (columns or 0) * viewport.mm_per_column,
    (rows or 0) * viewport.mm_per_row
  )
end

---Shift the viewport just enough to include a world point plus a cell margin.
function M.ensure_visible(viewport, x, y, columns, rows, margin_cells)
  local result = M.copy(viewport)
  margin_cells = math.max(0, margin_cells or 1)
  local min_x = result.world_left_mm + margin_cells * result.mm_per_column
  local max_x = result.world_left_mm + math.max(0, columns - 1 - margin_cells) * result.mm_per_column
  local max_y = result.world_top_mm - margin_cells * result.mm_per_row
  local min_y = result.world_top_mm - math.max(0, rows - 1 - margin_cells) * result.mm_per_row
  if x < min_x then
    result.world_left_mm = result.world_left_mm - (min_x - x)
  elseif x > max_x then
    result.world_left_mm = result.world_left_mm + (x - max_x)
  end
  if y > max_y then
    result.world_top_mm = result.world_top_mm + (y - max_y)
  elseif y < min_y then
    result.world_top_mm = result.world_top_mm - (min_y - y)
  end
  return result
end

return M
