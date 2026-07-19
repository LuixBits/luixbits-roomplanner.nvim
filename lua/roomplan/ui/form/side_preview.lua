-- Optional presentation-only companion for structured forms. The main form
-- remains complete on its own; this float exists only when the editor is wide.

local M = {}

local function valid_buffer(bufnr) return type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr) end

local function valid_window(winid) return type(winid) == "number" and vim.api.nvim_win_is_valid(winid) end

local function configure_buffer(bufnr)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modeline = false
  vim.bo[bufnr].undolevels = -1
  vim.bo[bufnr].filetype = "roomplan-form-preview"
end

local function position(winid, width, height, col, row)
  if not valid_window(winid) then return end
  col, row = math.max(0, col), math.max(0, row)
  local current = vim.api.nvim_win_get_config(winid)
  if
    current.relative == "editor"
    and current.width == width
    and current.height == height
    and current.col == col
    and current.row == row
  then
    return
  end
  pcall(vim.api.nvim_win_set_config, winid, {
    relative = "editor",
    width = width,
    height = height,
    col = col,
    row = row,
  })
end

local function content(handle)
  local preview = handle.state.preview or {}
  local lines = { handle.spec.preview_title or "Preview", string.rep("-", 30) }
  local meta = { graphic_rows = {}, graphic_spans = {}, error_rows = {} }
  if preview.error then
    lines[#lines + 1] = "! " .. tostring(preview.error)
    meta.error_rows[#lines] = true
  else
    local graphic = preview.graphic or {}
    for index, line in ipairs(preview.lines or {}) do
      lines[#lines + 1] = tostring(line)
      if index >= (graphic.first_line or math.huge) and index <= (graphic.last_line or -math.huge) then
        meta.graphic_rows[#lines] = true
        local graphic_row = index - graphic.first_line + 1
        for _, span in ipairs(graphic.highlight_spans or {}) do
          if span.row == graphic_row then
            meta.graphic_spans[#meta.graphic_spans + 1] = {
              row = #lines,
              start_col = span.start_col,
              end_col = span.end_col,
            }
          end
        end
      end
    end
  end
  return lines, meta
end

local function layout(handle)
  local desired_main_width = math.min(handle.width, math.max(20, vim.o.columns - 4))
  local main_height = math.min(handle.height or 8, math.max(6, vim.o.lines - 4))
  local preview_width = math.max(30, math.min(handle.spec.preview_width or 34, 44))
  local available_main_width = vim.o.columns - preview_width - 9
  local visible = handle.spec.preview_layout == "side"
    and type(handle.spec.preview) == "function"
    and handle.callbacks.preview ~= false
    and type(handle.callbacks.open_window) ~= "function"
    and available_main_width >= math.min(48, desired_main_width)
  local main_width = visible and math.min(desired_main_width, available_main_width) or desired_main_width
  local total_width = main_width + preview_width + 5
  return {
    main_width = main_width,
    main_height = main_height,
    preview_width = preview_width,
    total_width = total_width,
    visible = visible,
  }
end

function M.visible(handle) return layout(handle).visible end

function M.width(handle) return layout(handle).main_width end

local function highlight_rows(handle, lines, meta)
  handle.preview_namespace = handle.preview_namespace
    or vim.api.nvim_create_namespace("roomplan.form.preview." .. handle.id)
  vim.api.nvim_buf_clear_namespace(handle.preview_bufnr, handle.preview_namespace, 0, -1)
  local function mark(row, group)
    local line = lines[row] or ""
    vim.api.nvim_buf_set_extmark(handle.preview_bufnr, handle.preview_namespace, row - 1, 0, {
      end_col = #line,
      hl_group = group,
      hl_mode = "combine",
      strict = false,
    })
  end
  local function mark_range(span, group)
    if span.end_col <= span.start_col then return end
    vim.api.nvim_buf_set_extmark(handle.preview_bufnr, handle.preview_namespace, span.row - 1, span.start_col, {
      end_col = span.end_col,
      hl_group = group,
      hl_mode = "combine",
      strict = false,
    })
  end
  mark(1, "RoomPlanFormTitle")
  if next(meta.graphic_rows) ~= nil then
    local accent = handle.state.preview and handle.state.preview.accent
    local graphic_group = "RoomPlanFormPreviewShape" .. handle.id
    if type(accent) == "string" and accent:match("^#%x%x%x%x%x%x$") then
      vim.api.nvim_set_hl(0, graphic_group, { fg = accent, bold = true })
    else
      vim.api.nvim_set_hl(0, graphic_group, { link = "RoomPlanPreview" })
    end
    if #meta.graphic_spans > 0 then
      for _, span in ipairs(meta.graphic_spans) do
        mark_range(span, graphic_group)
      end
    else
      for row in pairs(meta.graphic_rows) do
        mark(row, graphic_group)
      end
    end
  end
  for row in pairs(meta.error_rows) do
    mark(row, "RoomPlanFormError")
  end
end

function M.close(handle)
  if valid_window(handle.preview_winid) then pcall(vim.api.nvim_win_close, handle.preview_winid, true) end
  if valid_buffer(handle.preview_bufnr) then pcall(vim.api.nvim_buf_delete, handle.preview_bufnr, { force = true }) end
  handle.preview_winid, handle.preview_bufnr = nil, nil
end

function M.sync(handle)
  if not valid_window(handle.winid) then return end
  local dimensions = layout(handle)
  local main_width = dimensions.main_width
  local main_height = dimensions.main_height
  local preview_width = dimensions.preview_width
  local total_width = dimensions.total_width
  local visible = dimensions.visible

  local main_col = math.floor((vim.o.columns - (visible and total_width or main_width)) / 2)
  local lines, meta = content(handle)
  local preview_height = math.min(#lines, math.max(6, vim.o.lines - 6))
  local group_height = visible and math.max(main_height, preview_height) or main_height
  local row = math.max(0, math.floor((vim.o.lines - group_height) / 2))
  position(handle.winid, main_width, main_height, main_col, row)

  if not visible then
    M.close(handle)
    return
  end
  if not valid_buffer(handle.preview_bufnr) then
    handle.preview_bufnr = vim.api.nvim_create_buf(false, true)
    configure_buffer(handle.preview_bufnr)
    pcall(vim.api.nvim_buf_set_name, handle.preview_bufnr, "roomplan://form-preview/" .. handle.id)
  end
  if not valid_window(handle.preview_winid) then
    handle.preview_winid = vim.api.nvim_open_win(handle.preview_bufnr, false, {
      relative = "editor",
      style = "minimal",
      border = handle.callbacks.border or "rounded",
      width = preview_width,
      height = preview_height,
      col = main_col + main_width + 3,
      row = row,
      focusable = false,
    })
    vim.wo[handle.preview_winid].wrap = false
    vim.wo[handle.preview_winid].number = false
    vim.wo[handle.preview_winid].relativenumber = false
    vim.wo[handle.preview_winid].signcolumn = "no"
  end
  vim.bo[handle.preview_bufnr].modifiable = true
  vim.bo[handle.preview_bufnr].readonly = false
  vim.api.nvim_buf_set_lines(handle.preview_bufnr, 0, -1, false, lines)
  vim.bo[handle.preview_bufnr].modifiable = false
  vim.bo[handle.preview_bufnr].readonly = true
  highlight_rows(handle, lines, meta)
  position(handle.preview_winid, preview_width, preview_height, main_col + main_width + 3, row)
end

return M
