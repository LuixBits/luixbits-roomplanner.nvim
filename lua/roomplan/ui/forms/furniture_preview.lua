-- Compact, presentation-only furniture canvas for structured forms. It uses
-- the same footprint adapter, viewport fitter, rasterizer, glyph set, cell
-- aspect, and object color as the main canvas without creating a model draft.

local config = require("roomplan.config")
local footprint = require("roomplan.geometry.footprint")
local raster = require("roomplan.render.raster")
local text = require("roomplan.render.text")
local viewport = require("roomplan.render.viewport")

local M = {}

local function display_width(value)
  if vim and vim.fn and vim.fn.strdisplaywidth then return vim.fn.strdisplaywidth(value) end
  return text.default_width(value)
end

local function scene(shape, bounds, color)
  local rectangles, err = footprint.rectangles(shape)
  if not rectangles then return nil, err end
  local primitives = {}
  for index, rectangle in ipairs(rectangles) do
    primitives[#primitives + 1] = {
      kind = "furniture_outline",
      layer = 2,
      left = rectangle.left,
      bottom = rectangle.bottom,
      right = rectangle.right,
      top = rectangle.top,
      role = "furniture",
      color = color,
      order = index,
    }
  end
  return {
    bounds = {
      left = bounds.left,
      bottom = bounds.bottom,
      right = bounds.right,
      top = bounds.top,
    },
    primitives = primitives,
    warnings = {},
  }
end

local function canvas(shape, bounds, color, opts)
  opts = opts or {}
  local columns = math.max(8, math.floor(opts.columns or 28))
  local rows = math.max(3, math.floor(opts.rows or 9))
  local runtime = config.get()
  local preview_scene, scene_err = scene(shape, bounds, color)
  if not preview_scene then return nil, scene_err end
  local fitted = viewport.fit(preview_scene.bounds, columns, rows, {
    cell_aspect = runtime.canvas.cell_aspect,
    fit_margin_cells = 1,
  })
  return raster.rasterize(preview_scene, fitted, {
    width = columns,
    height = rows,
    glyph_mode = runtime.canvas.unicode,
    glyphs = runtime.glyphs,
    width_fn = display_width,
  })
end

function M.render(furniture, opts)
  local shape, err = footprint.from_furniture({ origin_mm = { 0, 0 } }, furniture, {
    rotation_fallback = 0,
  })
  if not shape then return nil, err end
  local bounds = footprint.bounds(shape)
  if not bounds or bounds.width <= 0 or bounds.depth <= 0 then
    return nil, { code = "FURNITURE_PREVIEW", message = "the furniture footprint is unavailable" }
  end
  local output, render_err = canvas(shape, bounds, furniture.color, opts)
  if not output then return nil, render_err end
  return {
    lines = output.lines,
    highlight_spans = output.highlight_spans,
    glyph_mode = output.glyph_mode,
    width_mm = bounds.width,
    depth_mm = bounds.depth,
  }
end

return M
