local state = require("roomplan.state")

local M = {}

function M.open(session, opts)
  opts = opts or {}
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modeline = false
  vim.bo[buf].filetype = opts.filetype or "roomplan-list"
  local lines = opts.lines or { "No items" }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.cmd(opts.open_command or "botright new")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  state.attach_buffer(session, buf, opts.role or "list")
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function() state.detach_buffer(buf) end,
    desc = "Detach RoomPlan list buffer",
  })
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true, desc = "Close RoomPlan list" })
  vim.keymap.set("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    if opts.on_choose then
      opts.on_choose(row, opts.items and opts.items[row] or nil)
    end
  end, { buffer = buf, silent = true, desc = "Choose RoomPlan list item" })
  return { bufnr = buf, winid = win }
end

return M
