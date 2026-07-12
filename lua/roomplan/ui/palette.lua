-- Small RoomPlan-native action palette. This keeps workspace navigation out of
-- numbered vim.ui.select menus while remaining dependency-free.

local mappings = require("roomplan.ui.mappings")
local state = require("roomplan.state")

local M = {}
local next_id = 0

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
  local key = item.key and ("[" .. item.key .. "] ") or ""
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
  if not item then return false end
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

function M.open(opts)
  opts = opts or {}
  local items = opts.items or {}
  if #items == 0 then return nil, { code = "PALETTE_EMPTY", message = "no RoomPlan actions are available" } end
  next_id = next_id + 1
  local bufnr = vim.api.nvim_create_buf(false, true)
  local title = opts.title or "RoomPlan actions"
  local lines = { title, string.rep("-", math.max(16, text_width(title))), "" }
  local row_map, item_rows = {}, {}
  local maximum = text_width(title)
  for _, source in ipairs(items) do
    local item = vim.deepcopy(source)
    item.default_key = item.key
    item.key = item.default_key and mappings.resolve(item.default_key, item.mapping) or nil
    if item.enabled == nil then item.enabled = true end
    local line = item_line(item)
    lines[#lines + 1] = line
    row_map[#lines] = item
    item_rows[#item_rows + 1] = #lines
    maximum = math.max(maximum, text_width(line))
    if item.description and item.description ~= "" then
      local detail = "      " .. tostring(item.description)
      lines[#lines + 1] = detail
      maximum = math.max(maximum, text_width(detail))
    end
  end
  local palette_keys = {
    next = mappings.resolve("j", "palette_next"),
    previous = mappings.resolve("k", "palette_previous"),
    choose = mappings.resolve("<CR>", "palette_choose"),
    cancel = mappings.resolve("<Esc>", "palette_cancel"),
    cancel_alt = mappings.resolve("q"),
  }
  lines[#lines + 1] = ""
  lines[#lines + 1] = string.format("[%s/%s] Move  [%s] Run  [%s/%s] Cancel",
    display_key(palette_keys.next), display_key(palette_keys.previous), display_key(palette_keys.choose),
    display_key(palette_keys.cancel), display_key(palette_keys.cancel_alt))
  maximum = math.max(maximum, text_width(lines[#lines]))

  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modeline = false
  vim.bo[bufnr].filetype = "roomplan-palette"
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  pcall(vim.api.nvim_buf_set_name, bufnr, "roomplan://palette/" .. next_id)

  local width = math.min(math.max(44, maximum + 2), math.max(20, vim.o.columns - 6))
  local height = math.min(#lines, math.max(6, vim.o.lines - 6))
  local winid = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor", style = "minimal", border = opts.border or "rounded",
    title = " RoomPlan ", title_pos = "center",
    width = width, height = height,
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
  })
  vim.wo[winid].cursorline = true
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = "no"
  vim.wo[winid].wrap = false

  local handle = {
    id = next_id, bufnr = bufnr, winid = winid, session = opts.session,
    items = items, row_map = row_map, item_rows = item_rows,
    on_choice = opts.on_choice, closed = false,
  }
  if opts.session then state.attach_buffer(opts.session, bufnr, "palette") end
  mappings.set(bufnr, "j", function() move(handle, 1) end, "Next RoomPlan action", "palette_next")
  mappings.set(bufnr, "k", function() move(handle, -1) end, "Previous RoomPlan action", "palette_previous")
  mappings.set(bufnr, "<CR>", function() choose(handle) end, "Run RoomPlan action", "palette_choose")
  mappings.set(bufnr, "<Esc>", function() close(handle, "cancelled") end, "Cancel RoomPlan action palette", "palette_cancel")
  mappings.set(bufnr, "q", function() close(handle, "cancelled") end, "Cancel RoomPlan action palette")
  for _, item in pairs(row_map) do
    if item.key then
      local selected = item
      mappings.set(bufnr, selected.default_key, function() choose(handle, selected) end,
        "Run " .. tostring(selected.label), selected.mapping)
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
  vim.api.nvim_win_set_cursor(winid, { item_rows[1], 0 })
  return handle
end

M.choose = choose
M.close = close
M.move = move

return M
