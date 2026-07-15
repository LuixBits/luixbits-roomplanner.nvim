local util = require("roomplan.util")
local schema = require("roomplan.schema")
local workspace_defaults = require("roomplan.ui.workspace_defaults")
local canvas_detail = require("roomplan.canvas_detail")

local M = {}

local defaults = {
  plan_defaults = {
    -- A nil name lets model.new() apply the canonical schema name. It is
    -- declared separately in nullable_options because Lua cannot retain nil.
    metadata = { name = nil, notes = schema.defaults.metadata.notes },
    settings = util.deepcopy(schema.defaults.settings),
  },
  furniture = {
    include_builtins = true,
    definitions = {},
    files = {},
  },
  limits = {
    max_dimension_mm = 100000,
    max_abs_coordinate_mm = 1000000,
    max_plan_span_mm = 1000000,
    max_auto_place_distance_mm = 100000,
    max_history = 100,
    max_history_bytes_per_session = 64 * 1024 * 1024,
    max_history_bytes_global = 256 * 1024 * 1024,
  },
  canvas = {
    open = "tab",
    unicode = "auto",
    mm_per_column = 100,
    cell_aspect = 2.0,
    zoom_factor = 1.25,
    min_mm_per_column = 1,
    max_mm_per_column = 100000,
    fit_margin_cells = 2,
    header_lines = 1,
    pan_step_cells = 5,
    pan_coarse_step_cells = 20,
    show_grid = false,
    detail_level = canvas_detail.default,
    show_compass = true,
  },
  snapping = {
    enabled = true,
    tolerance_cells = 1.5,
    max_distance_mm = 250,
    priority = { "door", "room_edge", "room_center", "furniture", "grid" },
  },
  ui = {
    confirm_delete = true,
    notify_level = "info",
    workspace = workspace_defaults.get(),
  },
  autosave = { enabled = false, debounce_ms = 1000, norg = false },
  keymaps = { enabled = true, mappings = {} },
  glyphs = nil,
}

local effective = util.deepcopy(defaults)

-- Lua tables cannot retain a key whose default value is nil, so these two
-- documented nullable options need an explicit shape outside `defaults`.
local nullable_options = {
  ["plan_defaults.metadata.name"] = "string",
  glyphs = "table",
}

local function merge_checked(target, source, template, path, errors)
  for key, value in pairs(source or {}) do
    local here = path == "" and tostring(key) or (path .. "." .. tostring(key))
    if nullable_options[here] then
      if type(value) ~= nullable_options[here] then
        errors[#errors + 1] = here .. ": expected " .. nullable_options[here] .. ", got " .. type(value)
      else
        target[key] = util.deepcopy(value)
      end
    elseif template[key] == nil then
      errors[#errors + 1] = here .. ": unknown option"
    elseif (here == "furniture.definitions" or here == "furniture.files") and type(value) == "table" then
      target[key] = util.deepcopy(value)
    elseif here == "keymaps.mappings" and type(value) == "table" then
      target[key] = {}
      for mapping, lhs in pairs(value) do
        if type(mapping) ~= "string" or (type(lhs) ~= "string" and lhs ~= false) then
          errors[#errors + 1] = here .. ": keys must be strings and values must be strings or false"
        else
          target[key][mapping] = lhs
        end
      end
    elseif type(template[key]) == "table" and type(value) == "table" then
      merge_checked(target[key], value, template[key], here, errors)
    elseif type(value) ~= type(template[key]) and not (template[key] == nil) then
      errors[#errors + 1] = here .. ": expected " .. type(template[key]) .. ", got " .. type(value)
    else
      target[key] = util.deepcopy(value)
    end
  end
end

local function numeric_positive(config, path, value, errors)
  if type(value) ~= "number" or value <= 0 or value ~= value or value == math.huge then
    errors[#errors + 1] = path .. ": expected positive finite number"
  end
end

local function integer_positive(path, value, errors, allow_zero)
  if type(value) ~= "number" or value ~= math.floor(value) or value < (allow_zero and 0 or 1) then
    errors[#errors + 1] = path .. ": expected " .. (allow_zero and "non-negative" or "positive") .. " integer"
  end
end

function M.setup(opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    error("roomplan.setup: expected table", 2)
  end
  local candidate = util.deepcopy(defaults)
  local errors = {}
  merge_checked(candidate, opts, defaults, "", errors)
  numeric_positive(candidate, "canvas.mm_per_column", candidate.canvas.mm_per_column, errors)
  numeric_positive(candidate, "canvas.cell_aspect", candidate.canvas.cell_aspect, errors)
  numeric_positive(candidate, "canvas.zoom_factor", candidate.canvas.zoom_factor, errors)
  numeric_positive(candidate, "canvas.min_mm_per_column", candidate.canvas.min_mm_per_column, errors)
  numeric_positive(candidate, "canvas.max_mm_per_column", candidate.canvas.max_mm_per_column, errors)
  numeric_positive(candidate, "snapping.tolerance_cells", candidate.snapping.tolerance_cells, errors)
  numeric_positive(candidate, "snapping.max_distance_mm", candidate.snapping.max_distance_mm, errors)
  for key, value in pairs(candidate.plan_defaults.settings) do
    integer_positive("plan_defaults.settings." .. key, value, errors)
  end
  for _, key in ipairs({
    "max_dimension_mm", "max_abs_coordinate_mm", "max_plan_span_mm", "max_auto_place_distance_mm",
    "max_history", "max_history_bytes_per_session", "max_history_bytes_global",
  }) do
    integer_positive("limits." .. key, candidate.limits[key], errors)
  end
  integer_positive("canvas.fit_margin_cells", candidate.canvas.fit_margin_cells, errors, true)
  integer_positive("canvas.header_lines", candidate.canvas.header_lines, errors, true)
  integer_positive("canvas.pan_step_cells", candidate.canvas.pan_step_cells, errors)
  integer_positive("canvas.pan_coarse_step_cells", candidate.canvas.pan_coarse_step_cells, errors)
  integer_positive("autosave.debounce_ms", candidate.autosave.debounce_ms, errors)
  for _, key in ipairs({
    "left_width", "right_width", "wide_min_columns", "compact_max_columns",
    "compact_min_rows", "min_canvas_width", "min_canvas_height", "footer_height",
  }) do
    integer_positive("ui.workspace." .. key, candidate.ui.workspace[key], errors, key == "footer_height")
  end
  if candidate.canvas.min_mm_per_column > candidate.canvas.max_mm_per_column then
    errors[#errors + 1] = "canvas.min_mm_per_column: must not exceed max_mm_per_column"
  end
  if candidate.canvas.zoom_factor <= 1 then errors[#errors + 1] = "canvas.zoom_factor: expected number greater than 1" end
  if candidate.canvas.open ~= "tab" and candidate.canvas.open ~= "split" and candidate.canvas.open ~= "vsplit" then
    errors[#errors + 1] = "canvas.open: expected tab, split, or vsplit"
  end
  if candidate.canvas.unicode ~= "auto" and candidate.canvas.unicode ~= "unicode" and candidate.canvas.unicode ~= "ascii" then
    errors[#errors + 1] = "canvas.unicode: expected auto, unicode, or ascii"
  end
  if not canvas_detail.valid(candidate.canvas.detail_level) then
    errors[#errors + 1] = "canvas.detail_level: expected high, middle, or none"
  end
  if candidate.ui.workspace.layout ~= "auto" and candidate.ui.workspace.layout ~= "wide"
    and candidate.ui.workspace.layout ~= "medium" and candidate.ui.workspace.layout ~= "compact" then
    errors[#errors + 1] = "ui.workspace.layout: expected auto, wide, medium, or compact"
  end
  if candidate.ui.notify_level ~= "debug" and candidate.ui.notify_level ~= "info"
    and candidate.ui.notify_level ~= "warn" and candidate.ui.notify_level ~= "error" then
    errors[#errors + 1] = "ui.notify_level: expected debug, info, warn, or error"
  end
  if #errors > 0 then
    error("roomplan.setup failed:\n- " .. table.concat(errors, "\n- "), 2)
  end
  local catalog_ok, catalog_errors = require("roomplan.catalog").configure(candidate.furniture, candidate.limits)
  if not catalog_ok then
    error("roomplan.setup failed:\n- " .. table.concat(catalog_errors, "\n- "), 2)
  end
  effective = candidate
  return util.deepcopy(effective)
end

function M.get()
  return effective
end

---Override the terminal cell height/width calibration for this Neovim
---process without rebuilding the rest of the effective configuration.
function M.set_cell_aspect(value)
  if type(value) ~= "number" or value ~= value or value <= 0 or value == math.huge then
    return nil, util.err("CONFIG_CELL_ASPECT", "canvas.cell_aspect must be a positive finite number", {
      value = value,
    })
  end
  effective.canvas.cell_aspect = value
  return value
end

function M.defaults()
  return util.deepcopy(defaults)
end

function M.reset()
  effective = util.deepcopy(defaults)
  require("roomplan.catalog").reset()
end

return M
