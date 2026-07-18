-- Neovim-facing scratch canvas.  Session/controller state is supplied through
-- callbacks; this module never imports roomplan.state or dispatches mutations.

local raster = require("roomplan.render.raster")
local snapping = require("roomplan.geometry.snapping")
local viewport_module = require("roomplan.render.viewport")
local text = require("roomplan.render.text")

local M = {}

local handles_by_buffer = {}
local next_handle_id = 0

local function round(value)
  if value >= 0 then
    return math.floor(value + 0.5)
  end
  return math.ceil(value - 0.5)
end

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local HIGHLIGHTS = {
  wall = "RoomPlanWall",
  door = "RoomPlanDoor",
  window = "RoomPlanWindow",
  sun_wall = "RoomPlanSunWall",
  sun_window = "RoomPlanSunWindow",
  sunlight_1 = "RoomPlanSunlight1",
  sunlight_2 = "RoomPlanSunlight2",
  sunlight_3 = "RoomPlanSunlight3",
  sunlight_4 = "RoomPlanSunlight4",
  sunlight_5 = "RoomPlanSunlight5",
  outlet = "RoomPlanOutlet",
  furniture = "RoomPlanFurniture",
  room = "RoomPlanMuted",
  room_label = "RoomPlanRoomLabel",
  furniture_label = "RoomPlanFurnitureLabel",
  dimension = "RoomPlanMuted",
  selected = "RoomPlanSelected",
  snap = "RoomPlanSnap",
  snap_overlap = "RoomPlanSnapOverlap",
  error = "RoomPlanError",
  warning = "RoomPlanWarning",
  grid = "RoomPlanGrid",
  muted = "RoomPlanMuted",
}

local function valid_buffer(buffer)
  return type(buffer) == "number" and vim.api.nvim_buf_is_valid(buffer)
end

local function valid_window(window)
  return type(window) == "number" and vim.api.nvim_win_is_valid(window)
end

local function resolve_handle(value)
  if type(value) ~= "table" then
    return nil
  end
  if value.buf and value.namespace then
    return value
  end
  if type(value.canvas) == "table" then
    if value.canvas.handle then
      return value.canvas.handle
    end
    if value.canvas.bufnr then
      return handles_by_buffer[value.canvas.bufnr]
    end
  end
  if value.bufnr then
    return handles_by_buffer[value.bufnr]
  end
  return nil
end

local function is_session(value)
  return type(value) == "table"
    and type(value.canvas) == "table"
    and type(value.source) == "table"
    and (type(value.model) == "function" or type(value.current_model) == "function")
end

local function current_model(session)
  if type(session.current_model) == "function" then
    return session:current_model()
  end
  return session:model()
end

local function selected_object(model, selection)
  if not selection then
    return nil
  end
  local collection = selection.kind == "room" and model.rooms
    or selection.kind == "door" and model.doors
    or selection.kind == "window" and model.windows
    or selection.kind == "outlet" and model.outlets
    or selection.kind == "furniture" and model.furniture
    or selection.kind == "template" and model.custom_templates
  for _, object in ipairs(collection or {}) do
    if object.id == selection.id then
      return object
    end
  end
  return nil
end

local function session_header(session, canvas_config)
  local source = session.source.path
    or (session.source.bufnr and ("buffer #" .. tostring(session.source.bufnr)))
    or session.id
    or "detached"
  local status = type(session.status_text) == "function" and session:status_text() or ""
  local active_viewport = session.viewport
  local zoom = 1
  if active_viewport and active_viewport.mm_per_column then
    zoom = canvas_config.mm_per_column / active_viewport.mm_per_column
  end
  local diagnostics = session.validation or {}
  local errors, warnings = 0, 0
  for _, diagnostic in ipairs(diagnostics) do
    if diagnostic.severity == "error" then
      errors = errors + 1
    elseif diagnostic.severity == "warning" then
      warnings = warnings + 1
    end
  end
  local selection = session.selection
  local object = selected_object(current_model(session), selection)
  local plan = current_model(session)
  local room_count = #(plan.rooms or {})
  local door_count = #(plan.doors or {})
  local window_count = #(plan.windows or {})
  local outlet_count = #(plan.outlets or {})
  local furniture_count = #(plan.furniture or {})
  local plan_name = plan.metadata and plan.metadata.name or "Untitled plan"
  local selected_text = plan_name
  if selection then
    selected_text = string.format("%s: %s", selection.kind or "object",
      tostring(object and (object.name or object.id) or selection.id))
  end
  local display_mode = session.mode or "NAV"
  if session.workspace and session.workspace.state and session.workspace.state.interaction then
    display_mode = session.workspace.state.interaction
  end
  local shape_notice = ""
  if session.shape_edit then
    local edit = session.shape_edit
    local _, index = require("roomplan.room_shape").selected(edit)
    local directions = require("roomplan.directions")
    local snap = directions.replace_cardinals(require("roomplan.room_shape").snap_summary(edit), session)
    local edge = directions.replace_cardinals(require("roomplan.room_shape").edge_summary(edit), session)
    display_mode = edit.kind == "template" and "TEMPLATE RESIZE" or "RESIZE"
    shape_notice = string.format(" · %s · section %d/%d · edge %s",
      display_mode,
      index or 0, #(edit.footprint.parts or {}), edge or "choose with h/j/k/l")
    if snap then shape_notice = shape_notice .. " · SNAP " .. snap end
  elseif session.mode == "MOVE" then
    local snap = require("roomplan.directions").replace_cardinals(snapping.summary(session.snap_guides), session)
    if session.move_feedback then shape_notice = " · " .. session.move_feedback end
    if snap then shape_notice = shape_notice .. " · SNAP " .. snap end
  end
  local issue_parts = {}
  if errors > 0 then issue_parts[#issue_parts + 1] = errors .. "E" end
  if warnings > 0 then issue_parts[#issue_parts + 1] = warnings .. "W" end
  local issues = #issue_parts > 0 and (" · " .. table.concat(issue_parts, " ")) or ""
  local subject = selection and (plan_name .. " / " .. selected_text) or plan_name
  local workspace_owns_status = session.workspace and session.workspace.owns_footer
  local context_parts = {}
  if not workspace_owns_status then
    context_parts[#context_parts + 1] = display_mode
    if status ~= "" then context_parts[#context_parts + 1] = status end
  end
  local context_status = #context_parts > 0 and (" · " .. table.concat(context_parts, " ")) or ""
  local sun_status = ""
  if session.sun_study and session.sun_study.calculation then
    local sun = session.sun_study.calculation
    sun_status = string.format(" · SUN %s %s · az %.1f° el %.1f°",
      session.sun_study.date or "", session.sun_study.time or "", sun.azimuth_deg, sun.elevation_deg)
  end
  return {
    string.format("RoomPlan · %s%s%s%s%s", subject, shape_notice, sun_status, context_status, issues),
    string.format(
      "%s · %s · %s · %d rooms · %d doors · %d windows · %d outlets · %d items · zoom %.2f · snap %s · detail %s",
      source,
      display_mode,
      status,
      room_count,
      door_count,
      window_count,
      outlet_count,
      furniture_count,
      zoom,
      session.snap_enabled == false and "off" or "on",
      session.canvas_detail_level or canvas_config.detail_level
    ),
  }
end

local function session_footer(session)
  if session.workspace and session.workspace.owns_footer then return nil end
  local plan = current_model(session)
  local rooms = plan.rooms or {}
  local workflow = session.workflow and session.workflow.kind
  if workflow then
    local label = tostring(workflow):gsub("[-_]", " "):upper()
    return string.format(" %s | Complete the active prompt  [Esc] Cancel ", label)
  end
  if session.mode == "RESIZE" and session.shape_edit then
    local edit = session.shape_edit
    local _, index = require("roomplan.room_shape").selected(edit)
    local snap = require("roomplan.room_shape").snap_summary(edit)
      or (session.snap_enabled == false and "off" or "ready")
    local edge = require("roomplan.directions").replace_cardinals(
      require("roomplan.room_shape").edge_summary(edit), session) or "choose h/j/k/l"
    local label = edit.kind == "template" and "TEMPLATE RESIZE"
      or edit.kind == "furniture" and "FURNITURE RESIZE" or "ROOM RESIZE"
    return string.format(
      " %s · section %d/%d · edge %s · snap %s | [Enter/Tab] Select  [a/d] Add/Remove  [gs] Snap  [s] Save  [Esc] Cancel ",
      label, index or 0, #(edit.footprint.parts or {}), edge, snap
    )
  end
  if #rooms == 0 then
    return " [a] Add first room  [?] Help  [q] Hide "
  end
  if session.mode == "PAN" then
    return " PAN | [h/j/k/l] Pan  [H/J/K/L] Pan far  [Esc] Navigation  [f] Fit "
  elseif session.mode == "MOVE" then
    local snap = require("roomplan.directions").replace_cardinals(snapping.summary(session.snap_guides), session)
    return " MOVE" .. (session.move_feedback and (" · " .. session.move_feedback) or "")
      .. (snap and (" · snap " .. snap) or "")
      .. " | [h/j/k/l] Move  [H/J/K/L] Coarse  [Ctrl-h/j/k/l] Fine  [Esc] Done "
  end
  local kind = session.selection and session.selection.kind
  if kind == "room" then
    return " ROOM | [e] Edit  [m] Move  [r] Resize  [A] Align  [f] Fit  [y] Duplicate  [d] Delete  [a] Add "
  elseif kind == "furniture" then
    return " FURNITURE | [e] Edit  [m] Move  [f] Fit  [r] Rotate  [y] Duplicate  [d] Delete "
  elseif kind == "door" then
    return " DOOR | [e] Edit  [m] Move  [f] Fit  [y] Duplicate  [d] Delete  [a] Add "
  elseif kind == "window" then
    return " WINDOW | [e] Edit  [m] Move  [f] Fit  [y] Duplicate  [d] Delete  [a] Add "
  elseif kind == "outlet" then
    return " OUTLET | [e] Edit  [m] Move  [f] Fit  [y] Duplicate  [d] Delete  [a] Add "
  end
  return " NAV | [a] Add  [Enter] Select  [Tab] Next  [f] Fit  [L] Sun  [v] Validate  [?] Help  [q] Hide "
end

local function options_for_session(session, callbacks)
  callbacks = callbacks or {}
  local configured = require("roomplan.config").get()
  local canvas_config = configured.canvas
  local options = {
    open = canvas_config.open,
    unicode = canvas_config.unicode,
    glyphs = configured.glyphs,
    mm_per_column = canvas_config.mm_per_column,
    cell_aspect = canvas_config.cell_aspect,
    min_mm_per_column = canvas_config.min_mm_per_column,
    max_mm_per_column = canvas_config.max_mm_per_column,
    fit_margin_cells = canvas_config.fit_margin_cells,
    header_lines = canvas_config.header_lines,
    show_compass = canvas_config.show_compass,
    viewport = session.viewport,
    fit_on_open = session.viewport == nil,
  }
  options.get_scene = function()
    local scene = require("roomplan.scene.build").build(current_model(session), session.validation, {
      selected = session.shape_edit and nil or session.selection,
      shape_edit = session.shape_edit,
      snap_guides = session.shape_edit and session.shape_edit.snap_guides or session.snap_guides,
      measurement = session.measurement,
      show_grid = canvas_config.show_grid,
      detail_level = session.canvas_detail_level or canvas_config.detail_level,
      sun_study = session.sun_study,
      sun_config = configured.sun_study,
    })
    if session.sun_study and scene.sunlight then
      session.sun_study.assumed_count = scene.sunlight.assumed_count or 0
    end
    return scene
  end
  options.get_viewport = function()
    return session.viewport
  end
  options.get_header = function()
    return session_header(session, canvas_config)
  end
  options.get_footer = function()
    return session_footer(session)
  end
  options.get_compass = function(_, ascii)
    return require("roomplan.directions").compass(current_model(session).site and current_model(session).site.north_deg,
      session, ascii)
  end
  options.get_counts = function()
    local plan = current_model(session)
    return {
      rooms = #(plan.rooms or {}),
      doors = #(plan.doors or {}),
      windows = #(plan.windows or {}),
      outlets = #(plan.outlets or {}),
      furniture = #(plan.furniture or {}),
    }
  end
  options.on_viewport = function(_, value)
    session.viewport = value
    if type(callbacks.on_viewport) == "function" then
      callbacks.on_viewport(value)
    end
  end
  options.on_cursor = callbacks.on_cursor
  options.on_redraw = callbacks.on_redraw
  options.on_close = function(handle)
    if session.canvas and session.canvas.handle == handle then
      session.canvas = { bufnr = nil, winid = nil }
    end
    if type(callbacks.on_wipe) == "function" then
      callbacks.on_wipe(handle)
    end
    if type(callbacks.on_close) == "function" then
      callbacks.on_close(handle)
    end
  end
  return options
end

local function display_width(value)
  return vim.fn.strdisplaywidth(value)
end

local function define_highlights()
  require("roomplan.highlights").setup()
end

local function color_highlight(value)
  if type(value) ~= "string" or not value:match("^#%x%x%x%x%x%x$") then return nil end
  local name = "RoomPlanColor" .. value:sub(2):upper()
  vim.api.nvim_set_hl(0, name, { fg = value })
  return name
end

local function set_buffer_options(buffer)
  local options = {
    buftype = "nofile",
    bufhidden = "wipe",
    swapfile = false,
    modeline = false,
    modifiable = false,
    readonly = true,
    undolevels = -1,
    filetype = "roomplan",
  }
  for name, value in pairs(options) do
    vim.bo[buffer][name] = value
  end
end

local function set_window_options(window, opts)
  local options = {
    wrap = false,
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
    foldenable = false,
    list = false,
    spell = false,
    cursorline = opts.cursorline == true,
    scrolloff = 0,
    sidescrolloff = 0,
  }
  for name, value in pairs(options) do
    vim.wo[window][name] = value
  end
end

local function create_window(buffer, opts)
  if type(opts.open_window) == "function" then
    local window = opts.open_window(buffer, opts)
    assert(valid_window(window), "canvas open_window callback returned an invalid window")
    vim.api.nvim_win_set_buf(window, buffer)
    return window
  end

  local style = opts.open or "tab"
  if style == "current" then
    local window = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(window, buffer)
    return window
  elseif style == "split" or style == "vsplit" then
    vim.cmd((style == "vsplit" or opts.vertical) and "vnew" or "new")
    local window = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(window, buffer)
    return window
  elseif style == "float" then
    local columns = opts.width or math.max(20, math.floor(vim.o.columns * 0.8))
    local rows = opts.height or math.max(6, math.floor(vim.o.lines * 0.8))
    columns = math.min(columns, math.max(1, vim.o.columns - 2))
    rows = math.min(rows, math.max(1, vim.o.lines - 2))
    return vim.api.nvim_open_win(buffer, true, {
      relative = "editor",
      style = "minimal",
      border = opts.border or "rounded",
      width = columns,
      height = rows,
      col = math.max(0, math.floor((vim.o.columns - columns) / 2)),
      row = math.max(0, math.floor((vim.o.lines - rows) / 2)),
    })
  end

  vim.cmd("tabnew")
  local window = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(window, buffer)
  return window
end

local function safe_header_line(value, width, replacement)
  local sanitized = text.sanitize(tostring(value or ""), width, display_width, replacement or "?")
  return sanitized or "[invalid UTF-8 status text]"
end

local function header_lines(handle, width)
  local configured = math.max(0, math.floor(handle.opts.header_lines or 2))
  if configured == 0 then
    return {}
  end
  local value
  if type(handle.opts.get_header) == "function" then
    value = handle.opts.get_header(handle)
  elseif handle.opts.header ~= nil then
    value = handle.opts.header
  else
    value = {
      "RoomPlan | NAV | canvas",
      "Selected: none",
    }
  end
  if type(value) == "string" then
    value = { value }
  elseif type(value) ~= "table" then
    value = {}
  end
  local lines = {}
  for index = 1, configured do
    local line_width = index == 1 and handle.opts.show_compass ~= false and width >= 3
        and width - 3
      or width
    lines[index] = safe_header_line(value[index] or "", line_width, "?")
  end
  return lines
end

local function footer_lines(handle, width)
  local value
  if type(handle.opts.get_footer) == "function" then
    value = handle.opts.get_footer(handle)
  elseif handle.opts.footer ~= nil then
    value = handle.opts.footer
  end
  if value == nil or value == false then
    return {}
  end
  if type(value) ~= "table" then
    value = { value }
  end
  local lines = {}
  for index = 1, #value do
    lines[index] = safe_header_line(value[index] or "", width, "?")
  end
  return lines
end

local function centered_cells(value, width)
  local content = text.sanitize_cells(tostring(value or ""), width, display_width, "?") or {}
  local left = math.max(0, math.floor((width - #content) / 2))
  local cells = {}
  for _ = 1, left do cells[#cells + 1] = " " end
  local start_cell = #cells + 1
  for i = 1, #content do cells[#cells + 1] = content[i] end
  local end_cell = #cells + 1
  while #cells < width do cells[#cells + 1] = " " end
  return cells, start_cell, end_cell
end

local function replace_raster_rows(output, entries)
  local replaced = {}
  output.chrome_spans = output.chrome_spans or {}
  for _, entry in ipairs(entries) do
    local row = entry.row
    if row >= 1 and row <= output.height then
      local cells, start_cell, end_cell = centered_cells(entry.text, output.width)
      local offsets = text.byte_offsets(cells)
      output.lines[row] = table.concat(cells)
      output.byte_offsets[row] = offsets
      output.hit_map[row] = {}
      output.roles[row] = {}
      output.cells[row] = {}
      replaced[row] = true
      if end_cell > start_cell then
        output.chrome_spans[#output.chrome_spans + 1] = {
          row = row,
          start_col = offsets[start_cell],
          end_col = offsets[end_cell],
          hl_group = entry.hl_group or "RoomPlanChrome",
        }
      end
    end
  end
  if next(replaced) then
    local retained = {}
    for _, span in ipairs(output.highlight_spans or {}) do
      if not replaced[span.row] then retained[#retained + 1] = span end
    end
    output.highlight_spans = retained
  end
end

local function empty_state(output)
  local card = {
    { text = "Empty floor plan", hl_group = "RoomPlanEmptyTitle" },
    { text = "" },
    { text = "No rooms yet." },
    { text = "[a] Add first room    [?] Help    [q] Hide" },
    { text = "" },
    { text = "Measurements accept mm, cm, and m." },
  }
  if output.height < #card then
    card = {
      { text = "Empty floor plan", hl_group = "RoomPlanEmptyTitle" },
      { text = "[a] Add first room  [?] Help  [q] Hide" },
    }
  end
  local first = math.max(1, math.floor((output.height - #card) / 2) + 1)
  local entries = {}
  for index, entry in ipairs(card) do
    entries[#entries + 1] = {
      row = first + index - 1,
      text = entry.text,
      hl_group = entry.hl_group,
    }
  end
  replace_raster_rows(output, entries)
  output.chrome_state = "empty"
end

local function has_visible_object(output)
  for row = 1, output.height do
    for column = 1, output.width do
      if output.hit_map[row] and output.hit_map[row][column] and #output.hit_map[row][column] > 0 then
        return true
      end
    end
  end
  return false
end

local function object_counts(handle)
  local counts = type(handle.opts.get_counts) == "function" and handle.opts.get_counts(handle) or nil
  if type(counts) ~= "table" then return nil end
  return {
    rooms = tonumber(counts.rooms) or 0,
    doors = tonumber(counts.doors) or 0,
    windows = tonumber(counts.windows) or 0,
    outlets = tonumber(counts.outlets) or 0,
    furniture = tonumber(counts.furniture) or 0,
  }
end

local function apply_canvas_chrome(handle, scene, output, fitted)
  local counts = object_counts(handle)
  local model_object_count = counts
      and (counts.rooms + counts.doors + counts.windows + counts.outlets + counts.furniture)
    or nil
  if model_object_count == 0 then
    empty_state(output)
    return
  end
  if model_object_count and (#(scene.objects or {}) == 0 or not has_visible_object(output)) then
    local message
    if fitted or #(scene.objects or {}) == 0 then
      message = "RoomPlan could not render plan geometry - press v to inspect"
      output.chrome_state = "render-error"
    else
      message = "Plan is outside the viewport - press f to fit"
      output.chrome_state = "offscreen"
    end
    replace_raster_rows(output, {
      {
        row = math.max(1, math.floor(output.height / 2)),
        text = message,
        hl_group = "RoomPlanWarning",
      },
    })
  end
end

local function controlled_set_lines(handle, lines)
  if not valid_buffer(handle.buf) then
    return
  end
  vim.bo[handle.buf].readonly = false
  vim.bo[handle.buf].modifiable = true
  vim.api.nvim_buf_set_lines(handle.buf, 0, -1, false, lines)
  vim.bo[handle.buf].modifiable = false
  vim.bo[handle.buf].readonly = true
  vim.bo[handle.buf].modified = false
end

local function apply_highlights(handle, output, header_count, footer_count)
  if not valid_buffer(handle.buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(handle.buf, handle.namespace, 0, -1)
  local color_groups = {}
  for i = 1, #output.highlight_spans do
    local span = output.highlight_spans[i]
    local colored_group = span.color and color_groups[span.color] or nil
    if span.color and not colored_group then
      colored_group = color_highlight(span.color)
      color_groups[span.color] = colored_group
    end
    local group = (handle.opts.highlights and handle.opts.highlights[span.role])
      or colored_group
      or HIGHLIGHTS[span.role]
    if group then
      vim.api.nvim_buf_set_extmark(handle.buf, handle.namespace, header_count + span.row - 1, span.start_col, {
        end_col = span.end_col,
        hl_group = group,
        hl_mode = "combine",
        strict = false,
      })
    end
  end
  for _, span in ipairs(output.chrome_spans or {}) do
    vim.api.nvim_buf_set_extmark(handle.buf, handle.namespace, header_count + span.row - 1, span.start_col, {
      end_col = span.end_col,
      hl_group = span.hl_group,
      hl_mode = "combine",
      strict = false,
    })
  end
  if header_count > 0 then
    for row = 0, header_count - 1 do
      local line = vim.api.nvim_buf_get_lines(handle.buf, row, row + 1, false)[1] or ""
      if #line > 0 then
        vim.api.nvim_buf_set_extmark(handle.buf, handle.namespace, row, 0, {
          end_col = #line,
          hl_group = "RoomPlanStatus",
          hl_mode = "combine",
          strict = false,
        })
      end
    end
    if handle.opts.show_compass ~= false then
      local label = type(handle.opts.get_compass) == "function"
          and handle.opts.get_compass(handle, output.glyph_mode == "ascii")
        or require("roomplan.directions").compass(nil, output.viewport, output.glyph_mode == "ascii")
      vim.api.nvim_buf_set_extmark(handle.buf, handle.namespace, 0, 0, {
        virt_text = { { label, "RoomPlanCompass" } },
        virt_text_pos = "right_align",
        hl_mode = "combine",
        priority = 120,
        strict = false,
      })
    end
  end
  if footer_count > 0 then
    for row = header_count + output.height, header_count + output.height + footer_count - 1 do
      local line = vim.api.nvim_buf_get_lines(handle.buf, row, row + 1, false)[1] or ""
      if #line > 0 then
        vim.api.nvim_buf_set_extmark(handle.buf, handle.namespace, row, 0, {
          end_col = #line,
          hl_group = "RoomPlanActions",
          hl_mode = "combine",
          strict = false,
        })
      end
    end
  end
end

local function cleanup(handle)
  if handle.cleaned then
    return
  end
  handle.cleaned = true
  handles_by_buffer[handle.buf] = nil
  if handle.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, handle.augroup)
  end
  if type(handle.opts.on_close) == "function" then
    handle.opts.on_close(handle)
  end
end

local function reset_native_scroll(handle)
  if handle.resetting_scroll or not valid_window(handle.win) then
    return
  end
  handle.resetting_scroll = true
  vim.api.nvim_win_call(handle.win, function()
    local view = vim.fn.winsaveview()
    if view.topline ~= 1 or view.leftcol ~= 0 then
      view.topline = 1
      view.leftcol = 0
      vim.fn.winrestview(view)
    end
  end)
  handle.resetting_scroll = false
end

local function install_autocommands(handle)
  local name = "RoomPlanCanvas" .. handle.id
  handle.augroup = vim.api.nvim_create_augroup(name, { clear = true })
  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    group = handle.augroup,
    callback = function()
      if valid_window(handle.win) then
        M.schedule_redraw(handle, "resize")
      end
    end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = handle.augroup,
    buffer = handle.buf,
    callback = function()
      if type(handle.opts.on_cursor) == "function" then
        handle.opts.on_cursor(handle, M.logical_cursor(handle))
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinScrolled", {
    group = handle.augroup,
    callback = function()
      reset_native_scroll(handle)
    end,
  })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = handle.augroup,
    buffer = handle.buf,
    callback = function()
      -- One backing buffer cannot represent two differently sized windows.
      -- Keep the canonical view and dispose accidental secondary displays.
      vim.schedule(function()
        if handle.cleaned then return end
        local windows = vim.fn.win_findbuf(handle.buf)
        if #windows <= 1 then return end
        local canonical = valid_window(handle.win) and handle.win or windows[1]
        handle.win = canonical
        handle.winid = canonical
        if handle.session and handle.session.canvas then
          handle.session.canvas.winid = canonical
        end
        for _, window in ipairs(windows) do
          if window ~= canonical and valid_window(window) then
            pcall(vim.api.nvim_win_close, window, true)
          end
        end
        if valid_window(canonical) then
          vim.api.nvim_set_current_win(canonical)
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = handle.augroup,
    buffer = handle.buf,
    once = true,
    callback = function()
      cleanup(handle)
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = handle.augroup,
    callback = function()
      define_highlights()
      if not handle.cleaned then M.redraw(handle, { reason = "colorscheme" }) end
    end,
  })
end

local function raster_options(handle, width, height)
  return {
    width = width,
    height = height,
    glyph_mode = handle.opts.glyph_mode or handle.opts.unicode or "auto",
    glyphs = handle.opts.glyphs,
    width_fn = display_width,
    max_label_cells = handle.opts.max_label_cells,
  }
end

local function capture_cursor_world(handle)
  local logical = M.logical_cursor(handle)
  if not logical or not handle.last_raster then
    return nil
  end
  local x, y = viewport_module.screen_to_world(handle.last_raster.viewport, logical.column - 1, logical.row - 1)
  return { x = x, y = y }
end

local function restore_cursor_world(handle, world)
  if not world or not valid_window(handle.win) or not handle.last_raster then
    return
  end
  local column, row = viewport_module.world_to_screen(handle.last_raster.viewport, world.x, world.y)
  M.set_logical_cursor(handle, round(row) + 1, round(column) + 1)
end

local function selected_cursor_cell(handle, output)
  local selection = handle.session and handle.session.selection
  if not selection then return nil end
  local center_row = (output.height + 1) / 2
  local center_column = (output.width + 1) / 2
  local best, best_distance
  for row = 1, output.height do
    for column = 1, output.width do
      for _, hit in ipairs((output.hit_map[row] and output.hit_map[row][column]) or {}) do
        if hit.id == selection.id and (not selection.kind or hit.type == selection.kind) then
          local distance = math.abs(row - center_row) + math.abs(column - center_column)
          if not best_distance or distance < best_distance then
            best = { row = row, column = column }
            best_distance = distance
          end
        end
      end
    end
  end
  return best
end

local function place_initial_cursor(handle, output)
  if not valid_window(handle.win) or not output then return end
  local target = selected_cursor_cell(handle, output) or {
    row = math.max(1, math.floor((output.height + 1) / 2)),
    column = math.max(1, math.floor((output.width + 1) / 2)),
  }
  M.set_logical_cursor(handle, target.row, target.column)
end

---Redraw synchronously. Scene/raster computation completes before modifiable is
---temporarily enabled for one whole-buffer replacement.
function M.redraw(handle, scene, viewport, redraw_opts)
  handle = resolve_handle(handle) or handle
  assert(type(handle) == "table" and not handle.cleaned, "invalid canvas handle")
  if not valid_buffer(handle.buf) or not valid_window(handle.win) then
    return nil, "canvas is no longer visible"
  end
  redraw_opts = redraw_opts or {}
  local cursor_world = capture_cursor_world(handle)
  scene = scene or (type(handle.opts.get_scene) == "function" and handle.opts.get_scene(handle)) or handle.scene
  scene = scene or { primitives = {}, bounds = { empty = true } }
  local width = vim.api.nvim_win_get_width(handle.win)
  local window_height = vim.api.nvim_win_get_height(handle.win)
  local headers = header_lines(handle, width)
  local footers = footer_lines(handle, width)
  local drawable_height = window_height - #headers - #footers

  if width < (handle.opts.min_width or 12) or drawable_height < (handle.opts.min_height or 3) then
    local message = safe_header_line("RoomPlan: window too small; enlarge it to render the plan", width, "?")
    local lines = {}
    for i = 1, #headers do
      lines[#lines + 1] = headers[i]
    end
    lines[#lines + 1] = message
    for i = 1, #footers do
      lines[#lines + 1] = footers[i]
    end
    controlled_set_lines(handle, lines)
    vim.api.nvim_buf_clear_namespace(handle.buf, handle.namespace, 0, -1)
    handle.last_raster = nil
    handle.scene = scene
    return nil, "window too small"
  end

  if not viewport and type(handle.opts.get_viewport) == "function" then
    viewport = handle.opts.get_viewport(handle, width, drawable_height)
  end
  viewport = viewport or handle.viewport
  if redraw_opts.fit or not viewport_module.valid(viewport) then
    local fit_options = {
      mm_per_column = handle.opts.mm_per_column,
      cell_aspect = handle.opts.cell_aspect,
      fit_margin_cells = handle.opts.fit_margin_cells,
      min_mm_per_column = handle.opts.min_mm_per_column,
      max_mm_per_column = handle.opts.max_mm_per_column,
      rotation_quarters = viewport_module.rotation(viewport),
    }
    viewport = viewport_module.fit_scene(scene, width, drawable_height, fit_options)
  end

  local output = raster.rasterize(scene, viewport, raster_options(handle, width, drawable_height))
  apply_canvas_chrome(handle, scene, output, redraw_opts.fit == true)
  local lines = {}
  for i = 1, #headers do
    lines[#lines + 1] = headers[i]
  end
  for i = 1, #output.lines do
    lines[#lines + 1] = output.lines[i]
  end
  for i = 1, #footers do
    lines[#lines + 1] = footers[i]
  end
  controlled_set_lines(handle, lines)
  apply_highlights(handle, output, #headers, #footers)

  handle.scene = scene
  handle.viewport = viewport
  handle.last_raster = output
  handle.header_count = #headers
  handle.footer_count = #footers
  handle.redraw_reason = redraw_opts.reason
  if redraw_opts.focus_selection then
    place_initial_cursor(handle, output)
  elseif cursor_world then
    restore_cursor_world(handle, cursor_world)
  else
    place_initial_cursor(handle, output)
  end
  reset_native_scroll(handle)
  if type(handle.opts.on_viewport) == "function" then
    handle.opts.on_viewport(handle, viewport)
  end
  if type(handle.opts.on_redraw) == "function" then
    handle.opts.on_redraw(handle, output)
  end
  return output
end

function M.schedule_redraw(handle, reason)
  handle = resolve_handle(handle)
  if not handle or handle.redraw_pending or handle.cleaned then
    return
  end
  handle.redraw_pending = true
  vim.schedule(function()
    handle.redraw_pending = false
    if not handle.cleaned and valid_buffer(handle.buf) and valid_window(handle.win) then
      M.redraw(handle, nil, nil, { reason = reason })
    end
  end)
end

---Open a canvas and perform its first fitted redraw.
function M.open(opts, callbacks)
  opts = opts or {}
  local session
  if is_session(opts) then
    session = opts
    local existing = resolve_handle(session)
    if existing and not existing.cleaned and valid_window(existing.win) then
      M.focus(existing)
      return existing
    end
    opts = options_for_session(session, callbacks)
  end
  next_handle_id = next_handle_id + 1
  define_highlights()
  local buffer = vim.api.nvim_create_buf(false, true)
  local handle = {
    id = next_handle_id,
    buf = buffer,
    opts = opts,
    namespace = vim.api.nvim_create_namespace("roomplan.canvas." .. next_handle_id),
    viewport = opts.viewport,
    scene = opts.scene,
    session = session,
  }
  handle.bufnr = buffer
  if opts.name then
    vim.api.nvim_buf_set_name(buffer, opts.name)
  end
  set_buffer_options(buffer)
  handle.win = create_window(buffer, opts)
  handle.winid = handle.win
  set_window_options(handle.win, opts)
  handles_by_buffer[buffer] = handle
  if session then
    session.canvas = { bufnr = buffer, winid = handle.win, handle = handle }
    if require("roomplan.config").get().keymaps.enabled then
      require("roomplan.ui.keymaps").apply(buffer, session)
    end
  end
  install_autocommands(handle)
  local fit_on_open = opts.fit_on_open
  if fit_on_open == nil then
    fit_on_open = not viewport_module.valid(opts.viewport)
  end
  M.redraw(handle, opts.scene, opts.viewport, { fit = fit_on_open, reason = "open" })
  return handle
end

function M.focus(handle)
  handle = resolve_handle(handle) or handle
  if valid_window(handle and handle.win) then
    vim.api.nvim_set_current_win(handle.win)
    return true
  end
  return false
end

---Return one-based drawable raster row/column plus zero-based byte column.
function M.logical_cursor(handle)
  local compatibility_session = is_session(handle)
  handle = resolve_handle(handle) or handle
  if not handle or not valid_window(handle.win) or not handle.last_raster then
    return nil
  end
  local cursor = vim.api.nvim_win_get_cursor(handle.win)
  local row = cursor[1] - (handle.header_count or 0)
  if row < 1 or row > handle.last_raster.height then
    return nil
  end
  local column = text.byte_to_cell(handle.last_raster.byte_offsets[row], cursor[2])
  if not column then
    return nil
  end
  local result = {
    row = row,
    column = column,
    byte_column = cursor[2],
  }
  if compatibility_session then
    -- Controller world transforms use zero-based screen coordinates.  The
    -- standalone handle API remains one-based to match raster table indexing.
    result.row = result.row - 1
    result.column = result.column - 1
  end
  return result
end

function M.set_logical_cursor(handle, row, column)
  local compatibility_session = is_session(handle)
  handle = resolve_handle(handle) or handle
  if not handle or not valid_window(handle.win) or not handle.last_raster then
    return false
  end
  if compatibility_session then
    row = (row or 0) + 1
    column = (column or 0) + 1
  end
  row = clamp(math.floor(row or 1), 1, handle.last_raster.height)
  column = clamp(math.floor(column or 1), 1, handle.last_raster.width)
  local byte_column = handle.last_raster.byte_offsets[row][column]
  vim.api.nvim_win_set_cursor(handle.win, { row + (handle.header_count or 0), byte_column })
  return true
end

function M.hit_candidates(handle, row, column)
  handle = resolve_handle(handle) or handle
  if not handle or not handle.last_raster then
    return {}
  end
  if row == nil or column == nil then
    local cursor = M.logical_cursor(handle)
    if not cursor then
      return {}
    end
    row, column = cursor.row, cursor.column
  end
  local hit_row = handle.last_raster.hit_map[row]
  return (hit_row and hit_row[column]) or {}
end

function M.world_at_cursor(handle)
  handle = resolve_handle(handle) or handle
  local cursor = M.logical_cursor(handle)
  if not cursor or not handle.last_raster then
    return nil
  end
  local x, y = viewport_module.screen_to_world(handle.last_raster.viewport, cursor.column - 1, cursor.row - 1)
  return { x = x, y = y }
end

function M.set_keymap(handle, lhs, callback, opts)
  handle = resolve_handle(handle) or handle
  assert(valid_buffer(handle.buf), "invalid canvas buffer")
  opts = opts or {}
  vim.keymap.set(opts.mode or "n", lhs, function()
    callback(handle)
  end, {
    buffer = handle.buf,
    silent = opts.silent ~= false,
    nowait = opts.nowait,
    desc = opts.desc,
  })
end

---Close/hide the canonical canvas window. bufhidden=wipe disposes its backing
---buffer; session/model lifetime remains the controller's responsibility.
function M.close(handle)
  handle = resolve_handle(handle)
  if not handle or handle.cleaned then
    return false
  end
  if valid_window(handle.win) then
    if #vim.api.nvim_list_wins() == 1 then
      -- Neovim refuses to close the final editor window (E444).  Replace the
      -- disposable canvas with its source when available (never the guard), or
      -- an ordinary empty buffer; bufhidden=wipe performs canvas cleanup.
      local source_buffer = handle.session and handle.session.source and handle.session.source.bufnr
      local replacement = valid_buffer(source_buffer) and source_buffer or vim.api.nvim_create_buf(true, false)
      vim.api.nvim_win_set_buf(handle.win, replacement)
    else
      vim.api.nvim_win_close(handle.win, true)
    end
  elseif valid_buffer(handle.buf) then
    vim.api.nvim_buf_delete(handle.buf, { force = true })
  else
    cleanup(handle)
  end
  return true
end

function M.for_buffer(buffer)
  return handles_by_buffer[buffer]
end

return M
