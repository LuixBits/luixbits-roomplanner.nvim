-- Single source of contextual action labels, keys, handlers and disabled
-- reasons.  The registry is pure; workspace.lua decides how handlers run.

local M = {}
local mappings = require("roomplan.ui.mappings")

local definitions = {
  add = { key = "a", mapping = "add", label = "Add", handler = "add_menu", priority = 80 },
  add_room = { key = "a", mapping = "add", label = "Add room", handler = "add_room", priority = 100 },
  add_door = { key = "D", mapping = "add_door", label = "Add door", handler = "add_door", priority = 50 },
  add_furniture = { key = "F", mapping = "add_furniture", label = "Add furniture", handler = "add_furniture", priority = 50 },
  select = { key = "Enter", mapping = "select", label = "Select", handler = "select_under_cursor", priority = 75 },
  edit = { key = "e", mapping = "edit", label = "Edit", handler = "edit_selected", priority = 100 },
  move = { key = "m", mapping = "move_mode", label = "Move", handler = "set_mode", args = { "MOVE" }, priority = 95 },
  pan = { key = "p", mapping = "pan_mode", label = "Pan", handler = "set_mode", args = { "PAN" }, priority = 30 },
  align = { key = "A", mapping = "align", label = "Align", handler = "align_room", priority = 90 },
  rotate = { key = "r", mapping = "rotate", label = "Rotate", handler = "rotate_selected", priority = 90 },
  duplicate = { key = "y", mapping = "duplicate", label = "Duplicate", handler = "duplicate_selected", priority = 45 },
  delete = { key = "d", mapping = "delete", label = "Delete", handler = "delete_selected", priority = 40 },
  fit = { key = "f", mapping = "fit", label = "Fit", handler = "fit", priority = 65 },
  validate = { key = "v", mapping = "validate", label = "Validate", handler = "validate", args = { true }, priority = 60 },
  save = { key = "s", mapping = "save", label = "Save", handler = "save", priority = 55 },
  undo = { key = "u", mapping = "undo", label = "Undo", handler = "undo", priority = 40 },
  redo = { key = "<C-r>", mapping = "redo", label = "Redo", handler = "redo", priority = 35 },
  help = { key = "?", mapping = "help", label = "Help", handler = "help", priority = 10 },
  hide = { key = "q", mapping = "hide", label = "Hide", handler = "hide", priority = 5 },
  objects = { key = "1", mapping = "focus_objects", label = "Objects", workspace = "objects", priority = 20 },
  canvas = { key = "2", mapping = "focus_canvas", label = "Canvas", workspace = "canvas", priority = 20 },
  properties = { key = "3", mapping = "focus_properties", label = "Properties", workspace = "properties", priority = 20 },
  issues = { key = "!", mapping = "focus_issues", label = "Issues", workspace = "issues", priority = 20 },
  previous_field = { key = "<S-Tab>", mapping = "form_previous_field", label = "Previous field", form = "previous", priority = 30 },
  next_field = { key = "<Tab>", mapping = "form_next_field", label = "Next field", form = "next", priority = 80 },
  edit_field = { key = "<CR>", mapping = "form_edit", label = "Edit field", form = "edit", priority = 90 },
  apply = { key = "<C-s>", mapping = "form_apply", label = "Apply", form = "apply", priority = 100 },
  reset = { key = "R", mapping = "form_reset", label = "Reset", form = "reset", priority = 15 },
  cancel = { key = "<Esc>", mapping = "form_cancel", label = "Cancel", form = "cancel", priority = 95 },
  leave_mode = { key = "<Esc>", mapping = "escape", label = "Finish mode", handler = "escape", priority = 100 },
}

local function clone(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = clone(item) end
  return result
end

local function room_count(ctx)
  return #(ctx.model and ctx.model.rooms or {})
end

local function selected_kind(ctx)
  return ctx.selection and ctx.selection.kind
end

local function availability(id, ctx)
  local kind = selected_kind(ctx)
  if id == "add_door" or id == "add_furniture" then
    if room_count(ctx) == 0 then return false, "Add a room first" end
  elseif id == "edit" or id == "delete" or id == "duplicate" then
    if not ctx.selection then return false, "Select an object first" end
    if (id == "delete" or id == "duplicate") and kind == "plan" then
      return false, "The plan itself cannot be " .. (id == "delete" and "deleted" or "duplicated")
    end
    if id == "duplicate" and kind ~= "room" and kind ~= "door" and kind ~= "furniture" and kind ~= "template" then
      return false, "This object cannot be duplicated"
    end
  elseif id == "move" then
    if kind ~= "room" and kind ~= "door" and kind ~= "furniture" then return false, "Select a movable object first" end
  elseif id == "align" then
    if kind ~= "room" then return false, "Select a room first" end
    if room_count(ctx) < 2 then return false, "Add another room first" end
  elseif id == "rotate" then
    if kind ~= "furniture" then return false, "Select furniture first" end
  elseif id == "save" and ctx.conflicted then
    return false, "Resolve the source conflict first"
  elseif id == "undo" and ctx.can_undo == false then
    return false, "Nothing to undo"
  elseif id == "redo" and ctx.can_redo == false then
    return false, "Nothing to redo"
  end
  return true
end

function M.get(id, ctx)
  local definition = definitions[id]
  if not definition then return nil end
  ctx = ctx or {}
  local result = clone(definition)
  result.id = id
  result.default_key = result.key
  result.key = mappings.resolve(result.default_key, result.mapping or id, ctx.keymaps)
  result.mapped = result.key ~= nil
  result.enabled, result.reason = availability(id, ctx)
  if id == "edit" and ctx.selection then
    if ctx.selection.kind == "plan" then
      result.handler = "edit_plan"
    elseif ctx.selection.kind == "template" then
      result.handler = "edit_template"
      result.args = { ctx.selection.id }
    end
  end
  return result
end

local function is_form(ctx)
  return ctx.form ~= nil or (ctx.mode and (
    ctx.mode:find("ADD_", 1, true) == 1
    or ctx.mode:find("EDIT_", 1, true) == 1
    or ctx.mode:find("CREATE", 1, true) ~= nil
    or ctx.mode == "ALIGN_ROOM"
  ))
end

local function ids_for(ctx)
  if is_form(ctx) then
    if ctx.form then return { "previous_field", "next_field", "edit_field", "apply", "reset", "cancel" } end
    -- Legacy prompt workflows are still represented as a named mode while the
    -- structured form is integrated. Their only universal in-workspace action
    -- is cancellation; the active vim.ui prompt owns its remaining keys.
    return { "cancel", "help" }
  end
  if ctx.mode == "MOVE" then return { "leave_mode", "undo", "redo", "save", "help" } end
  if ctx.mode == "PAN" or ctx.mode == "PICK" then return { "leave_mode", "fit", "help" } end

  local kind = selected_kind(ctx)
  if room_count(ctx) == 0 then
    if kind == "plan" then
      return { "edit", "add_room", "fit", "validate", "save", "undo", "redo", "help", "hide" }
    end
    return { "add_room", "add_door", "add_furniture", "fit", "save", "undo", "redo", "help", "hide" }
  elseif kind == "plan" then
    return { "edit", "add", "fit", "validate", "save", "undo", "redo", "help", "hide" }
  elseif kind == "room" then
    return { "edit", "move", "align", "add", "fit", "duplicate", "delete", "validate", "save", "undo", "redo", "help" }
  elseif kind == "furniture" then
    return { "edit", "move", "rotate", "fit", "duplicate", "delete", "validate", "save", "undo", "redo", "help" }
  elseif kind == "door" then
    return { "edit", "move", "fit", "duplicate", "delete", "validate", "save", "undo", "redo", "help" }
  elseif kind == "template" then
    return { "edit", "duplicate", "delete", "save", "undo", "redo", "help" }
  end
  return { "add", "select", "fit", "validate", "save", "pan", "undo", "redo", "help", "hide" }
end

function M.contextual(ctx, opts)
  opts = opts or {}
  local result = {}
  for _, id in ipairs(ids_for(ctx or {})) do
    local action = M.get(id, ctx)
    if action and (opts.include_disabled ~= false or action.enabled) then result[#result + 1] = action end
  end
  return result
end

function M.for_ids(ids, ctx)
  local result = {}
  for _, id in ipairs(ids or {}) do
    local action = M.get(id, ctx)
    if action then result[#result + 1] = action end
  end
  return result
end

function M.by_key(ctx, key)
  for _, action in ipairs(M.contextual(ctx)) do
    if action.key ~= nil and action.key == key then return action end
  end
end

function M.mode_label(ctx)
  local mode = tostring(ctx and ctx.mode or "NAV"):gsub("_", " ")
  if mode == "NAV" then return "NAV" end
  if mode == "MOVE" then return "MOVE · h/j/k/l move · H/J/K/L coarse · Ctrl-h/j/k/l fine" end
  if mode == "PAN" then return "PAN · h/j/k/l pan" end
  if mode == "PICK" then return "PICK · h/j/k/l position · Enter accept · Esc return" end
  return mode
end

function M.hint(action)
  local suffix = action.enabled and "" or (" (disabled: " .. tostring(action.reason) .. ")")
  if action.key == nil then return string.format("%s (unmapped)%s", action.label, suffix) end
  return string.format("[%s] %s%s", action.key, action.label, suffix)
end

function M.definitions()
  return clone(definitions)
end

return M
