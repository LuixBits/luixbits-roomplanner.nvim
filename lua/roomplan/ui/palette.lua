-- Small dependency-free action window. Search is opt-in and currently used by
-- the complete `?` action list; compact choice menus stay one-key interfaces.

local mappings = require("roomplan.ui.mappings")
local state = require("roomplan.state")

local M = {}
local next_id = 0
local highlight_namespace = vim.api.nvim_create_namespace("roomplan-palette")

local function valid_buffer(bufnr)
  return type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr)
end

local function valid_window(winid)
  return type(winid) == "number" and vim.api.nvim_win_is_valid(winid)
end

local function text_width(value)
  return vim.fn.strdisplaywidth(tostring(value or ""))
end

local function display_key(key)
  local friendly = { ["<CR>"] = "Enter", ["<Esc>"] = "Esc", ["<C-s>"] = "Ctrl-s" }
  return key and (friendly[key] or key) or "unmapped"
end

local function item_line(item)
  local key = item.palette_shortcut and ("[" .. display_key(item.palette_shortcut) .. "] ") or ""
  local reason = not item.enabled and ("  × " .. tostring(item.reason or "Unavailable")) or ""
  return "  " .. key .. tostring(item.label or item.id or "Action") .. reason
end

local function close(handle, reason)
  if not handle or handle.closed then return false end
  handle.closed = true
  handle.reason = reason
  if handle.session and valid_buffer(handle.bufnr) then state.detach_buffer(handle.bufnr) end
  if handle.augroup then pcall(vim.api.nvim_del_augroup_by_id, handle.augroup) end
  if valid_window(handle.winid) then pcall(vim.api.nvim_win_close, handle.winid, true) end
  if valid_buffer(handle.bufnr) then pcall(vim.api.nvim_buf_delete, handle.bufnr, { force = true }) end
  return true
end

local function selected_item(handle)
  if not valid_window(handle.winid) then return nil end
  return handle.row_map[vim.api.nvim_win_get_cursor(handle.winid)[1]]
end

local function notify_disabled(item)
  require("roomplan.compat").notify(item.reason or "That RoomPlan action is unavailable", vim.log.levels.WARN)
end

local function choose(handle, item)
  item = item or selected_item(handle)
  if not item or not handle.visible[item] then return false end
  if item.enabled == false then notify_disabled(item); return false end
  local callback = item.callback or handle.on_choice
  close(handle, "chosen")
  if callback then
    vim.schedule(function()
      if not handle.session or not handle.session.closed then callback(item, handle) end
    end)
  end
  return item
end

local function move(handle, delta)
  if not valid_window(handle.winid) or #handle.item_rows == 0 then return false end
  local current = vim.api.nvim_win_get_cursor(handle.winid)[1]
  local index = 1
  for candidate, row in ipairs(handle.item_rows) do
    if row == current then index = candidate; break end
  end
  index = ((index - 1 + (delta < 0 and -1 or 1)) % #handle.item_rows) + 1
  vim.api.nvim_win_set_cursor(handle.winid, { handle.item_rows[index], 0 })
  return true
end

local function searchable_text(item)
  return table.concat({
    tostring(item.label or ""), tostring(item.id or ""), tostring(item.description or ""),
    tostring(item.group or ""), tostring(item.group_label or ""), tostring(item.key or ""),
  }, "\n"):lower()
end

local function matches(item, query)
  query = tostring(query or ""):lower()
  return query == "" or searchable_text(item):find(query, 1, true) ~= nil
end

local function document(handle)
  local lines = { handle.title, string.rep("-", math.max(16, text_width(handle.title))), "" }
  local row_map, item_rows, group_rows, disabled_rows, visible = {}, {}, {}, {}, {}
  local maximum = text_width(handle.title)
  if handle.searchable and handle.query ~= "" then
    lines[#lines + 1] = "/ " .. handle.query
    maximum = math.max(maximum, text_width(lines[#lines]))
    lines[#lines + 1] = ""
  end
  local previous_group
  for _, item in ipairs(handle.items) do
    if matches(item, handle.query) then
      visible[item] = true
      if handle.grouped and item.group and item.group ~= previous_group then
        if previous_group ~= nil then lines[#lines + 1] = "" end
        lines[#lines + 1] = tostring(item.group_label or item.group)
        group_rows[#group_rows + 1] = #lines
        maximum = math.max(maximum, text_width(lines[#lines]))
        previous_group = item.group
      end
      local line = item_line(item)
      lines[#lines + 1] = line
      row_map[#lines] = item
      item_rows[#item_rows + 1] = #lines
      if not item.enabled then disabled_rows[#disabled_rows + 1] = #lines end
      maximum = math.max(maximum, text_width(line))
      if item.description and item.description ~= "" then
        local detail = "      " .. tostring(item.description)
        lines[#lines + 1] = detail
        maximum = math.max(maximum, text_width(detail))
      end
    end
  end
  if #item_rows == 0 then
    lines[#lines + 1] = handle.query == "" and "  No actions available."
      or ("  No actions match “" .. handle.query .. "”.")
    maximum = math.max(maximum, text_width(lines[#lines]))
  end
  lines[#lines + 1] = ""
  local footer = string.format("[%s/%s] Move  [%s] Run",
    display_key(handle.keys.next), display_key(handle.keys.previous), display_key(handle.keys.choose))
  if handle.searchable then footer = footer .. "  [/] Search" end
  footer = footer .. string.format("  [%s/%s] Cancel",
    display_key(handle.keys.cancel), display_key(handle.keys.cancel_alt))
  lines[#lines + 1] = footer
  maximum = math.max(maximum, text_width(footer))
  return {
    lines = lines, row_map = row_map, item_rows = item_rows, group_rows = group_rows,
    disabled_rows = disabled_rows, visible = visible, maximum = maximum,
  }
end

local function render(handle)
  if handle.closed or not valid_buffer(handle.bufnr) then return false end
  local view = document(handle)
  handle.row_map, handle.item_rows, handle.visible = view.row_map, view.item_rows, view.visible
  vim.bo[handle.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(handle.bufnr, 0, -1, false, view.lines)
  vim.bo[handle.bufnr].modifiable = false
  vim.api.nvim_buf_clear_namespace(handle.bufnr, highlight_namespace, 0, -1)
  vim.api.nvim_buf_add_highlight(handle.bufnr, highlight_namespace, "Title", 0, 0, -1)
  for _, row in ipairs(view.group_rows) do
    vim.api.nvim_buf_add_highlight(handle.bufnr, highlight_namespace, "Special", row - 1, 0, -1)
  end
  for _, row in ipairs(view.disabled_rows) do
    vim.api.nvim_buf_add_highlight(handle.bufnr, highlight_namespace, "Comment", row - 1, 0, -1)
  end
  for _, row in ipairs(view.item_rows) do
    local first, last = view.lines[row]:find("%b[]")
    if first then
      vim.api.nvim_buf_add_highlight(handle.bufnr, highlight_namespace, "Special", row - 1, first - 1, last)
    end
  end
  if valid_window(handle.winid) then
    local width = math.min(math.max(44, view.maximum + 2), math.max(20, vim.o.columns - 6))
    local height = math.min(#view.lines, math.max(6, vim.o.lines - 6))
    pcall(vim.api.nvim_win_set_config, handle.winid, {
      relative = "editor", width = width, height = height,
      col = math.max(0, math.floor((vim.o.columns - width) / 2)),
      row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    })
    if view.item_rows[1] then vim.api.nvim_win_set_cursor(handle.winid, { view.item_rows[1], 0 }) end
  end
  return view
end

local function filter(handle, query)
  if not handle.searchable then return false end
  handle.query = tostring(query or "")
  return render(handle)
end

local function prompt_search(handle)
  if not handle.searchable then return false end
  vim.ui.input({ prompt = "Search RoomPlan actions: ", default = handle.query }, function(value)
    if value ~= nil and not handle.closed then filter(handle, value) end
  end)
  return true
end

local function resolved_items(items, opts, keys)
  local reserved, claimed, result = {}, {}, {}
  for _, key in pairs(keys) do if key then reserved[key] = true end end
  if opts.searchable then reserved["/"] = true end
  for _, source in ipairs(items) do
    local item = vim.deepcopy(source)
    item.default_key = item.default_key or item.key
    if opts.resolve_keys ~= false then
      item.key = item.default_key and mappings.resolve(item.default_key, item.mapping, opts.keymaps) or nil
    end
    if item.key and not reserved[item.key] and not claimed[item.key] then
      item.palette_shortcut = item.key
      claimed[item.key] = true
    end
    if item.enabled == nil then item.enabled = true end
    result[#result + 1] = item
  end
  return result
end

function M.open(opts)
  opts = opts or {}
  local source_items = opts.items or {}
  if #source_items == 0 then return nil, { code = "PALETTE_EMPTY", message = "no RoomPlan actions are available" } end
  next_id = next_id + 1
  local bufnr = vim.api.nvim_create_buf(false, true)
  local keys = {
    next = mappings.resolve("j", "palette_next"),
    previous = mappings.resolve("k", "palette_previous"),
    choose = mappings.resolve("<CR>", "palette_choose"),
    cancel = mappings.resolve("<Esc>", "palette_cancel"),
    cancel_alt = mappings.resolve("q"),
  }
  local handle = {
    id = next_id, bufnr = bufnr, winid = nil, session = opts.session,
    title = opts.title or "RoomPlan actions", grouped = opts.grouped == true,
    searchable = opts.searchable == true, query = "", keys = keys,
    items = resolved_items(source_items, opts, keys), row_map = {}, item_rows = {}, visible = {},
    on_choice = opts.on_choice, closed = false,
  }
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modeline = false
  vim.bo[bufnr].filetype = "roomplan-palette"
  pcall(vim.api.nvim_buf_set_name, bufnr, "roomplan://palette/" .. next_id)
  local initial = render(handle)
  local width = math.min(math.max(44, initial.maximum + 2), math.max(20, vim.o.columns - 6))
  local height = math.min(#initial.lines, math.max(6, vim.o.lines - 6))
  handle.winid = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor", style = "minimal", border = opts.border or "rounded",
    title = " RoomPlan ", title_pos = "center", width = width, height = height,
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
  })
  vim.wo[handle.winid].cursorline = true
  vim.wo[handle.winid].number = false
  vim.wo[handle.winid].relativenumber = false
  vim.wo[handle.winid].signcolumn = "no"
  vim.wo[handle.winid].wrap = false
  vim.wo[handle.winid].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"
  if opts.session then state.attach_buffer(opts.session, bufnr, "palette") end
  mappings.set(bufnr, "j", function() move(handle, 1) end, "Next RoomPlan action", "palette_next")
  mappings.set(bufnr, "k", function() move(handle, -1) end, "Previous RoomPlan action", "palette_previous")
  mappings.set(bufnr, "<CR>", function() choose(handle) end, "Run RoomPlan action", "palette_choose")
  mappings.set(bufnr, "<Esc>", function() close(handle, "cancelled") end, "Cancel RoomPlan action palette", "palette_cancel")
  mappings.set(bufnr, "q", function() close(handle, "cancelled") end, "Cancel RoomPlan action palette")
  if handle.searchable then
    mappings.set(bufnr, "/", function() prompt_search(handle) end, "Search RoomPlan actions", "palette_search")
  end
  for _, item in ipairs(handle.items) do
    if item.palette_shortcut then
      local selected = item
      mappings.set(bufnr, selected.palette_shortcut, function() choose(handle, selected) end,
        "Run " .. tostring(selected.label), nil, { enabled = true, mappings = {} })
    end
  end
  handle.augroup = vim.api.nvim_create_augroup("RoomPlanPalette" .. next_id, { clear = true })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = handle.augroup, buffer = bufnr, once = true,
    callback = function()
      if not handle.closed then
        handle.closed = true
        if handle.session then state.detach_buffer(bufnr) end
      end
    end,
  })
  if handle.item_rows[1] then vim.api.nvim_win_set_cursor(handle.winid, { handle.item_rows[1], 0 }) end
  return handle
end

M.choose = choose
M.close = close
M.filter = filter
M.move = move
M.prompt_search = prompt_search

return M
