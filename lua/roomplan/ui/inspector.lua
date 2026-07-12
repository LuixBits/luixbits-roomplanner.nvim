local state = require("roomplan.state")

local M = {}

local function find(model, selection)
  if not selection then
    return nil
  end
  local collection = selection.kind == "room" and "rooms"
    or selection.kind == "door" and "doors"
    or selection.kind == "furniture" and "furniture"
    or selection.kind == "template" and "custom_templates"
  for _, object in ipairs(collection and model[collection] or {}) do
    if object.id == selection.id then
      return object
    end
  end
end

local function push_value(lines, key, value)
  if type(value) == "table" then
    if require("roomplan.codec.json").is_null(value) then
      lines[#lines + 1] = string.format("%-22s null", key .. ":")
      return
    end
    local array = {}
    for index, item in ipairs(value) do
      array[index] = tostring(item)
    end
    if #array > 0 then
      lines[#lines + 1] = string.format("%-22s %s", key .. ":", table.concat(array, ", "))
    end
  elseif value ~= nil then
    lines[#lines + 1] = string.format("%-22s %s", key .. ":", tostring(value))
  end
end

function M.lines(session)
  local model = session.current_model and session:current_model() or session.model or {}
  local selection = session.selection
  local object = find(model, selection)
  local lines = {
    "RoomPlan inspector",
    string.rep("=", 40),
    "source: " .. (session.source and (session.source.path or ("buffer #" .. tostring(session.source.bufnr))) or "detached"),
    "mode: " .. tostring(session.mode or "NAV"),
  }
  if not object then
    lines[#lines + 1] = "selected: none"
    return lines
  end
  lines[#lines + 1] = "selected: " .. selection.kind .. " " .. tostring(object.name or object.id)
  local ordered = {
    "id", "name", "room_id", "connects_to_room_id", "kind", "side", "offset_mm", "width_mm", "hinge",
    "opens_into", "open_angle_deg", "template_id", "category", "origin_mm", "size_mm", "center_mm", "rotation_deg",
  }
  for _, key in ipairs(ordered) do
    push_value(lines, key, object[key])
  end
  for _, diagnostic in ipairs(session.validation or {}) do
    if diagnostic.object and diagnostic.object.id == object.id then
      lines[#lines + 1] = string.format("[%s] %s: %s", (diagnostic.severity or "info"):upper(), diagnostic.code or "?", diagnostic.message or "")
    end
  end
  return lines
end

function M.refresh(session)
  if not session.inspector or not session.inspector.bufnr or not vim.api.nvim_buf_is_valid(session.inspector.bufnr) then
    return
  end
  local buf = session.inspector.bufnr
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, M.lines(session))
  vim.bo[buf].modifiable = false
end

function M.toggle(session)
  if session.inspector and session.inspector.winid and vim.api.nvim_win_is_valid(session.inspector.winid) then
    vim.api.nvim_win_close(session.inspector.winid, true)
    session.inspector = nil
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "roomplan-inspector"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, M.lines(session))
  vim.bo[buf].modifiable = false
  local mode = require("roomplan.config").get().ui.inspector
  if mode == "off" then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    return
  end
  local win
  if mode == "split" then
    vim.cmd("botright vsplit")
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
  else
    local width = math.min(70, math.max(35, math.floor(vim.o.columns * 0.35)))
    local height = math.min(#M.lines(session) + 2, math.max(8, math.floor(vim.o.lines * 0.6)))
    win = vim.api.nvim_open_win(buf, false, {
      relative = "editor",
      anchor = "NE",
      row = 1,
      col = vim.o.columns - 1,
      width = width,
      height = height,
      border = "rounded",
      style = "minimal",
      focusable = true,
    })
  end
  session.inspector = { bufnr = buf, winid = win }
  state.attach_buffer(session, buf, "inspector")
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      state.detach_buffer(buf)
      if session.inspector and session.inspector.bufnr == buf then session.inspector = nil end
    end,
    desc = "Detach RoomPlan inspector buffer",
  })
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    session.inspector = nil
  end, { buffer = buf, silent = true })
end

return M
