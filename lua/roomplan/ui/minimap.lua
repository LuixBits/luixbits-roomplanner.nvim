-- Transient, non-focusable overview of the complete plan and the canvas's
-- current world-space field of view. Nothing in this module enters the saved
-- model or semantic history.

local color = require("roomplan.color")
local config = require("roomplan.config")
local raster = require("roomplan.render.raster")
local viewport = require("roomplan.render.viewport")

local M = {}

local next_id = 0

local function valid_buffer(buffer) return type(buffer) == "number" and vim.api.nvim_buf_is_valid(buffer) end

local function valid_window(window) return type(window) == "number" and vim.api.nvim_win_is_valid(window) end

local function current_model(session)
  if type(session.current_model) == "function" then return session:current_model() end
  if type(session.model) == "function" then return session:model() end
  return session.model or {}
end

local function state_for(session)
  session.minimap = session.minimap or { enabled = false }
  return session.minimap
end

local function overview_model(model)
  return {
    schema_version = model.schema_version,
    metadata = model.metadata,
    settings = model.settings,
    site = model.site,
    rooms = model.rooms or {},
    doors = {},
    windows = {},
    outlets = {},
    furniture = {},
    custom_templates = {},
  }
end

local function include_bounds(bounds, rectangle)
  if not rectangle then return end
  if bounds.empty then
    bounds.left, bounds.right = rectangle.left, rectangle.right
    bounds.bottom, bounds.top = rectangle.bottom, rectangle.top
    bounds.empty = false
    return
  end
  bounds.left = math.min(bounds.left, rectangle.left)
  bounds.right = math.max(bounds.right, rectangle.right)
  bounds.bottom = math.min(bounds.bottom, rectangle.bottom)
  bounds.top = math.max(bounds.top, rectangle.top)
end

local function color_room_interiors(scene, model)
  local colors = {}
  for _, room in ipairs(model.rooms or {}) do
    colors[room.id] = color.resolve(room.color)
  end
  for _, primitive in ipairs(scene.primitives or {}) do
    if primitive.kind == "room_interior" and primitive.ref then primitive.color = colors[primitive.ref.id] end
  end
end

---Render a complete-plan overview using the same scene and raster pipeline as
---the main canvas. The selected-role outline is the main canvas's exact field
---of view, including after panning, zooming, or rotating.
function M.render(session, canvas_output, opts)
  opts = opts or {}
  if type(canvas_output) ~= "table" or not viewport.valid(canvas_output.viewport) then
    return nil, "the RoomPlan canvas has not rendered yet"
  end
  local width = math.max(1, math.floor(opts.width or 28))
  local height = math.max(1, math.floor(opts.height or 10))
  local model = current_model(session)
  local scene = require("roomplan.scene.build").build(overview_model(model), {}, {
    detail_level = "none",
    show_grid = false,
  })
  color_room_interiors(scene, model)

  local field_of_view = viewport.visible_bounds(canvas_output.viewport, canvas_output.width, canvas_output.height)
  include_bounds(scene.bounds, field_of_view)
  scene.primitives[#scene.primitives + 1] = {
    kind = "furniture_outline",
    layer = 200,
    left = field_of_view.left,
    right = field_of_view.right,
    bottom = field_of_view.bottom,
    top = field_of_view.top,
    role = "selected",
    order = 1,
  }

  local canvas_config = config.get().canvas
  local map_viewport = viewport.fit_scene(scene, width, height, {
    cell_aspect = canvas_config.cell_aspect,
    fit_margin_cells = 1,
    rotation_quarters = viewport.rotation(canvas_output.viewport),
  })
  local output = raster.rasterize(scene, map_viewport, {
    width = width,
    height = height,
    unicode = canvas_config.unicode,
    glyphs = config.get().glyphs,
    width_fn = vim.fn.strdisplaywidth,
  })
  output.field_of_view = field_of_view
  return output
end

local function color_group(value)
  if type(value) ~= "string" or not value:match("^#%x%x%x%x%x%x$") then return nil end
  local name = "RoomPlanMinimapRoom" .. value:sub(2):upper()
  vim.api.nvim_set_hl(0, name, require("roomplan.highlights").tint(value, 0.18, 0.28))
  return name
end

local ROLE_HIGHLIGHTS = {
  wall = "RoomPlanMinimapWall",
  room = "RoomPlanMinimapRoom",
  selected = "RoomPlanMinimapViewport",
}

local function apply_highlights(state, output)
  vim.api.nvim_buf_clear_namespace(state.bufnr, state.namespace, 0, -1)
  local color_groups = {}
  for _, span in ipairs(output.highlight_spans or {}) do
    local group
    if span.role == "room" and span.color then
      group = color_groups[span.color]
      if not group then
        group = color_group(span.color)
        color_groups[span.color] = group
      end
    end
    group = group or ROLE_HIGHLIGHTS[span.role]
    if group then
      vim.api.nvim_buf_set_extmark(state.bufnr, state.namespace, span.row - 1, span.start_col, {
        end_col = span.end_col,
        hl_group = group,
        hl_mode = "combine",
        strict = false,
        priority = span.role == "selected" and 150 or 100,
      })
    end
  end
end

local function set_lines(state, lines)
  vim.bo[state.bufnr].readonly = false
  vim.bo[state.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
  vim.bo[state.bufnr].modifiable = false
  vim.bo[state.bufnr].readonly = true
  vim.bo[state.bufnr].modified = false
end

local function dispose_window(state)
  if valid_window(state.winid) then pcall(vim.api.nvim_win_close, state.winid, true) end
  if valid_buffer(state.bufnr) then pcall(vim.api.nvim_buf_delete, state.bufnr, { force = true }) end
  state.winid, state.bufnr, state.namespace = nil, nil, nil
end

local function dimensions(session)
  local canvas = session.canvas or {}
  if not valid_window(canvas.winid) then return nil end
  local canvas_width = vim.api.nvim_win_get_width(canvas.winid)
  local canvas_height = vim.api.nvim_win_get_height(canvas.winid)
  local width = math.min(34, math.max(16, math.floor(canvas_width * 0.28)))
  local height = math.min(12, math.max(6, math.floor(canvas_height * 0.30)))
  width = math.min(width, canvas_width - 4)
  height = math.min(height, canvas_height - 4)
  if width < 12 or height < 4 then return nil end
  return {
    relative = "win",
    win = canvas.winid,
    anchor = "NW",
    row = math.min(canvas_height - height - 2, math.max(1, (canvas.handle and canvas.handle.header_count) or 1)),
    col = math.max(0, canvas_width - width - 2),
    width = width,
    height = height,
    focusable = false,
    style = "minimal",
    border = "rounded",
    title = " Overview · M ",
    title_pos = "center",
    zindex = 60,
  }
end

local function same_position(window, desired)
  if not valid_window(window) then return false end
  local current = vim.api.nvim_win_get_config(window)
  return current.relative == desired.relative
    and current.win == desired.win
    and current.row == desired.row
    and current.col == desired.col
    and current.width == desired.width
    and current.height == desired.height
end

local function ensure_window(session, state, position)
  if not valid_buffer(state.bufnr) then
    next_id = next_id + 1
    state.bufnr = vim.api.nvim_create_buf(false, true)
    state.namespace = vim.api.nvim_create_namespace("roomplan.minimap." .. next_id)
    vim.api.nvim_buf_set_name(state.bufnr, "roomplan://minimap/" .. tostring(session.id))
    vim.bo[state.bufnr].buftype = "nofile"
    vim.bo[state.bufnr].bufhidden = "wipe"
    vim.bo[state.bufnr].swapfile = false
    vim.bo[state.bufnr].modeline = false
    vim.bo[state.bufnr].modifiable = false
    vim.bo[state.bufnr].readonly = true
    vim.bo[state.bufnr].undolevels = -1
    vim.bo[state.bufnr].filetype = "roomplan-minimap"
  end
  if not valid_window(state.winid) then
    state.winid = vim.api.nvim_open_win(state.bufnr, false, position)
  elseif not same_position(state.winid, position) then
    vim.api.nvim_win_set_config(state.winid, position)
  end
  vim.wo[state.winid].wrap = false
  vim.wo[state.winid].number = false
  vim.wo[state.winid].relativenumber = false
  vim.wo[state.winid].signcolumn = "no"
  vim.wo[state.winid].foldcolumn = "0"
  vim.wo[state.winid].cursorline = false
  vim.wo[state.winid].winhighlight = table.concat({
    "Normal:NormalFloat",
    "NormalFloat:NormalFloat",
    "FloatBorder:RoomPlanMinimapBorder",
    "FloatTitle:RoomPlanMinimapTitle",
  }, ",")
end

function M.refresh(session, canvas_output)
  local state = state_for(session)
  if not state.enabled then return false end
  if #(current_model(session).rooms or {}) == 0 then
    M.close(session)
    return nil, "add a room before opening the RoomPlan minimap"
  end
  local canvas = session.canvas or {}
  canvas_output = canvas_output or (canvas.handle and canvas.handle.last_raster)
  if not valid_window(canvas.winid) or not canvas_output then return nil, "the RoomPlan canvas has not rendered yet" end
  local position = dimensions(session)
  if not position then
    dispose_window(state)
    return nil, "the RoomPlan canvas is too small for the minimap"
  end
  require("roomplan.highlights").setup()
  ensure_window(session, state, position)
  local output, err = M.render(session, canvas_output, {
    width = position.width,
    height = position.height,
  })
  if not output then return nil, err end
  set_lines(state, output.lines)
  apply_highlights(state, output)
  state.last_raster = output
  return true
end

function M.toggle(session)
  local state = state_for(session)
  if state.enabled then
    M.close(session)
    return false
  end
  state.enabled = true
  local ok, err = M.refresh(session)
  if not ok and err ~= "the RoomPlan canvas is too small for the minimap" then state.enabled = false end
  return state.enabled, err
end

function M.close(session)
  local state = session and session.minimap
  if not state then return false end
  state.enabled = false
  dispose_window(state)
  state.last_raster = nil
  return true
end

function M.is_enabled(session) return session and session.minimap and session.minimap.enabled == true or false end

function M.is_visible(session) return M.is_enabled(session) and valid_window(session.minimap.winid) end

return M
