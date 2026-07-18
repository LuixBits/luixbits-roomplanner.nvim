-- Single source of contextual action labels, keys, handlers and disabled
-- reasons.  The registry is pure; workspace.lua decides how handlers run.

local M = {}
local mappings = require("roomplan.ui.mappings")

local groups = {
  pane = { label = "Current panel", order = 10 },
  form = { label = "Form", order = 20 },
  mode = { label = "Current mode", order = 20 },
  create = { label = "Create", order = 30 },
  selection = { label = "Selection", order = 40 },
  view = { label = "View and validate", order = 50 },
  history = { label = "Save and history", order = 60 },
  session = { label = "Source and session", order = 65 },
  workspace = { label = "Workspace", order = 70 },
}

local definitions = {
  add = { key = "a", mapping = "add", label = "Add", handler = "add_menu", priority = 80 },
  add_room = { key = "a", mapping = "add", label = "Add room", handler = "add_room", priority = 100 },
  add_door = { key = "D", mapping = "add_door", label = "Add door", handler = "add_door", priority = 50 },
  add_window = { key = "W", mapping = "add_window", label = "Add window", handler = "add_window", priority = 50 },
  add_outlet = { key = "O", mapping = "add_outlet", label = "Add outlet", handler = "add_outlet", priority = 50 },
  add_furniture = { key = "F", mapping = "add_furniture", label = "Add furniture", handler = "add_furniture", priority = 50 },
  select = {
    key = "<CR>", mapping = "select", label = "Select", handler = "select_under_cursor",
    priority = 75, scopes = { "canvas" },
  },
  edit = { key = "e", mapping = "edit", label = "Edit", handler = "edit_selected", priority = 100 },
  resize_dimensions = {
    key = "r", mapping = "resize_dimensions", label = "Resize dimensions",
    handler = "edit_selected_shape", priority = 92,
  },
  move = { key = "m", mapping = "move_mode", label = "Move", handler = "set_mode", args = { "MOVE" }, priority = 95 },
  pan = { key = "p", mapping = "pan_mode", label = "Pan", handler = "set_mode", args = { "PAN" }, priority = 30 },
  align = { key = "A", mapping = "align", label = "Align", handler = "align_room", priority = 90 },
  place_furniture = {
    mapping = "place_furniture",
    label = "Place furniture against wall",
    handler = "place_furniture",
    priority = 70,
  },
  measure = { mapping = "measure", label = "Measure exact clearance", handler = "measure", priority = 55 },
  rotate = { key = "R", mapping = "rotate", label = "Rotate", handler = "rotate_selected", priority = 90 },
  duplicate = { key = "y", mapping = "duplicate", label = "Duplicate", handler = "duplicate_selected", priority = 45 },
  delete = { key = "d", mapping = "delete", label = "Delete", handler = "delete_selected", priority = 40 },
  fit = { key = "f", mapping = "fit", label = "Fit", handler = "fit", priority = 65 },
  cycle_detail_level = {
    key = "t", mapping = "cycle_detail_level", label = "Cycle canvas detail",
    handler = "set_detail_level", args = { "cycle" }, priority = 40,
  },
  zoom_in = { key = ".", mapping = "zoom_in", label = "Zoom in", handler = "zoom", args = { "in" }, priority = 35 },
  zoom_out = { key = ",", mapping = "zoom_out", label = "Zoom out", handler = "zoom", args = { "out" }, priority = 35 },
  rotate_view_clockwise = {
    key = "<A-l>", mapping = "rotate_view_clockwise", label = "Rotate view clockwise",
    handler = "rotate_view", args = { "clockwise" }, priority = 25,
  },
  rotate_view_counterclockwise = {
    key = "<A-h>", mapping = "rotate_view_counterclockwise", label = "Rotate view counter-clockwise",
    handler = "rotate_view", args = { "counterclockwise" }, priority = 25,
  },
  reset_view = {
    key = "g0", mapping = "reset_view", label = "Reset view north-up",
    handler = "rotate_view", args = { "reset" }, priority = 20,
  },
  validate = { key = "v", mapping = "validate", label = "Validate", handler = "validate", args = { true }, priority = 60 },
  next_issue = { key = "<A-j>", mapping = "next_issue", label = "Next issue", handler = "next_issue", args = { 1 }, priority = 30 },
  previous_issue = { key = "<A-k>", mapping = "previous_issue", label = "Previous issue", handler = "next_issue", args = { -1 }, priority = 30 },
  toggle_snap = { key = "gs", mapping = "toggle_snap", label = "Toggle snapping", handler = "toggle_snap", priority = 30 },
  bypass_snap = { key = "g!", mapping = "bypass_snap", label = "Bypass next snap", handler = "bypass_snap", priority = 20 },
  aspect = { mapping = "aspect", label = "Calibrate terminal aspect", handler = "set_aspect", priority = 10 },
  save = { key = "s", mapping = "save", label = "Save", handler = "save", priority = 55 },
  save_as = { key = "S", mapping = "save_as", label = "Save As", handler = "save_as_prompt", priority = 45 },
  undo = { key = "u", mapping = "undo", label = "Undo", handler = "undo", priority = 40 },
  redo = { key = "<C-r>", mapping = "redo", label = "Redo", handler = "redo", priority = 35 },
  history_list = { mapping = "history_list", label = "Browse undo history", handler = "history", priority = 30 },
  reload = { mapping = "reload", label = "Reload source", handler = "reload", priority = 20 },
  close = { mapping = "close", label = "Close session", handler = "close", priority = 10 },
  help = { key = "?", mapping = "help", label = "More", handler = "help", priority = 10 },
  hide = { key = "q", mapping = "hide", label = "Hide", handler = "hide", priority = 5 },
  objects = { key = "1", mapping = "focus_objects", label = "Objects", workspace = "objects", priority = 20 },
  canvas = { key = "2", mapping = "focus_canvas", label = "Canvas", workspace = "canvas", priority = 20 },
  properties = { key = "3", mapping = "focus_properties", label = "Details", workspace = "properties", priority = 20 },
  issues = { key = "!", mapping = "focus_issues", label = "Issues", workspace = "issues", priority = 20 },
  previous_field = { key = "<S-Tab>", mapping = "form_previous_field", label = "Previous field", form = "previous", priority = 30 },
  next_field = { key = "<Tab>", mapping = "form_next_field", label = "Next field", form = "next", priority = 80 },
  edit_field = { key = "<CR>", mapping = "form_edit", label = "Edit field", form = "edit", priority = 90 },
  apply = { key = "<C-s>", mapping = "form_apply", label = "Apply", form = "apply", priority = 100 },
  reset = { key = "R", mapping = "form_reset", label = "Reset", form = "reset", priority = 15 },
  cancel = { key = "<Esc>", mapping = "form_cancel", label = "Cancel", form = "cancel", priority = 95 },
  shape_apply = {
    key = "s", mapping = "save", label = "Save resize",
    handler = "save", priority = 100,
  },
  shape_previous = {
    key = "<S-Tab>", mapping = "shape_previous", label = "Previous section",
    handler = "cycle_room_shape_part", args = { -1 }, priority = 35,
  },
  shape_next = {
    key = "<Tab>", mapping = "shape_next", label = "Next section",
    handler = "cycle_room_shape_part", args = { 1 }, priority = 80,
  },
  leave_mode = { key = "<Esc>", mapping = "escape", label = "Finish mode", handler = "escape", priority = 100 },
  activate_focused = {
    key = "<CR>", mapping = "workspace_activate_focused", label = "Open",
    workspace_action = "select_focused", priority = 100, scopes = { "objects", "issues" },
  },
  collapse_focused = {
    key = "h", mapping = "workspace_collapse_focused", label = "Collapse",
    workspace_action = "collapse_focused", args = { false }, priority = 80, scopes = { "objects" },
  },
  expand_focused = {
    key = "l", mapping = "workspace_expand_focused", label = "Expand",
    workspace_action = "expand_focused", args = { true }, priority = 75, scopes = { "objects" },
  },
  filter_focused = {
    key = "/", mapping = "workspace_filter_focused", label = "Filter",
    workspace_action = "filter_focused", priority = 70, scopes = { "objects", "issues" },
  },
  toggle_mark = {
    key = "<Space>",
    mapping = "workspace_toggle_mark_focused",
    label = "Mark",
    workspace_action = "toggle_mark_focused",
    priority = 90,
    scopes = { "objects" },
  },
  move_marked = { mapping = "move_marked", label = "Move marked objects", handler = "move_marked", priority = 68 },
  duplicate_marked = {
    mapping = "duplicate_marked",
    label = "Duplicate marked objects",
    handler = "duplicate_marked",
    priority = 48,
  },
  delete_marked = {
    mapping = "delete_marked",
    label = "Delete marked objects",
    handler = "delete_marked",
    priority = 43,
  },
  clear_marks = { mapping = "clear_marks", label = "Clear marked objects", handler = "clear_marks", priority = 20 },
  toggle_details_section = {
    key = "<CR>", mapping = "workspace_toggle_details_section", label = "Toggle section",
    workspace_action = "toggle_details_section", priority = 100, scopes = { "properties" },
  },
}

local group_members = {
  create = { "add", "add_room", "add_door", "add_window", "add_outlet", "add_furniture" },
  selection = { "select", "edit", "resize_dimensions", "move", "align",
    "place_furniture", "rotate", "duplicate", "delete",
    "move_marked",
    "duplicate_marked",
    "delete_marked",
    "clear_marks" },
  view = {
    "pan", "fit", "cycle_detail_level", "zoom_in", "zoom_out", "rotate_view_clockwise", "rotate_view_counterclockwise",
    "reset_view", "validate", "next_issue", "previous_issue",
    "toggle_snap", "bypass_snap",
    "measure", "aspect",
  },
  history = { "save", "save_as", "undo", "redo", "history_list" },
  session = { "reload", "close" },
  workspace = { "help", "hide", "objects", "canvas", "properties", "issues" },
  form = { "previous_field", "next_field", "edit_field", "apply", "reset", "cancel" },
  mode = { "shape_apply", "shape_previous", "shape_next", "leave_mode" },
  pane = {
    "activate_focused",
    "toggle_mark", "collapse_focused", "expand_focused", "filter_focused",
    "toggle_details_section",
  },
}

local all_workspace_scopes = { "canvas", "objects", "issues", "properties" }
for group, ids in pairs(group_members) do
  for _, id in ipairs(ids) do
    local definition = assert(definitions[id], "unknown RoomPlan action " .. id)
    definition.group = group
    definition.group_label = groups[group].label
    definition.scopes = definition.scopes or (group == "form" and { "form" } or all_workspace_scopes)
  end
end

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

local function focused_pane(ctx)
  local focus = ctx and ctx.focus or "canvas"
  if focus == "form" then return "properties" end
  if focus ~= "objects" and focus ~= "issues" and focus ~= "properties" then return "canvas" end
  return focus
end

local friendly_keys = {
  ["<CR>"] = "Enter",
  ["<Esc>"] = "Esc",
  ["<C-s>"] = "Ctrl-s",
  ["<C-r>"] = "Ctrl-r",
  ["<Space>"] = "Space",
  ["<Tab>"] = "Tab",
  ["<S-Tab>"] = "S-Tab",
  ["<A-h>"] = "Alt-h",
  ["<A-j>"] = "Alt-j",
  ["<A-k>"] = "Alt-k",
  ["<A-l>"] = "Alt-l",
}

function M.display_key(key)
  return key and (friendly_keys[key] or key) or nil
end

local function availability(id, ctx)
  local kind = selected_kind(ctx)
  if id == "select" and room_count(ctx) == 0 then
    return false, "Add a room first"
  elseif id == "add_door" or id == "add_window" or id == "add_outlet" or id == "add_furniture" then
    if room_count(ctx) == 0 then return false, "Add a room first" end
  elseif id == "edit" or id == "delete" or id == "duplicate" then
    if not ctx.selection then return false, "Select an object first" end
    if (id == "delete" or id == "duplicate") and kind == "plan" then
      return false, "The plan itself cannot be " .. (id == "delete" and "deleted" or "duplicated")
    end
    if id == "duplicate" and kind ~= "room" and kind ~= "door" and kind ~= "window"
      and kind ~= "outlet" and kind ~= "furniture" and kind ~= "template"
    then
      return false, "This object cannot be duplicated"
    end
  elseif id == "resize_dimensions" then
    if kind ~= "room" and kind ~= "furniture" and kind ~= "template" then
      return false, "Select a room, furniture item, or project template first"
    end
  elseif id == "move" then
    if kind ~= "room" and kind ~= "door" and kind ~= "window"
      and kind ~= "outlet" and kind ~= "furniture"
    then
      return false, "Select a movable object first"
    end
  elseif id == "align" then
    if kind ~= "room" then return false, "Select a room first" end
    if room_count(ctx) < 2 then return false, "Add another room first" end
  elseif id == "rotate" then
    if kind ~= "furniture" then return false, "Select furniture first" end
  elseif id == "place_furniture" then
    if kind ~= "furniture" then
      return false, "Select furniture first"
    end
  elseif id == "measure" then
    local plan = ctx.model or {}
    if #(plan.rooms or {}) + #(plan.furniture or {}) < 2 then
      return false, "Add at least two rooms or furniture items"
    end
  elseif id == "toggle_mark" then
    local row = ctx.focused_row
    if not row or row.kind == "plan" or not row.id then
      return false, "Focus an object row"
    end
  elseif id == "move_marked" then
    if (ctx.marked_count or 0) == 0 then
      return false, "Mark objects in Navigator first"
    end
    if (ctx.marked_move_unsupported or 0) > 0 then
      return false, "Group movement supports rooms and furniture"
    end
    if (ctx.marked_move_count or 0) == 0 then
      return false, "No marked object can be moved as a group"
    end
  elseif id == "duplicate_marked" then
    if (ctx.marked_count or 0) == 0 then
      return false, "Mark objects in Navigator first"
    end
    if (ctx.marked_duplicate_unsupported or 0) > 0 then
      return false, "Doors need their placement popup and cannot be batch duplicated"
    end
  elseif id == "delete_marked" or id == "clear_marks" then
    if (ctx.marked_count or 0) == 0 then
      return false, "Mark objects in Navigator first"
    end
  elseif id == "save" and ctx.conflicted then
    return false, "Resolve the source conflict first"
  elseif id == "undo" and ctx.can_undo == false then
    return false, "Nothing to undo"
  elseif id == "redo" and ctx.can_redo == false then
    return false, "Nothing to redo"
  elseif id == "reset_view" and (ctx.view_rotation or 0) == 0 then
    return false, "View is already north-up"
  elseif id == "activate_focused" then
    local row = ctx.focused_row
    local selectable_object = row and (row.kind == "plan" or row.id ~= nil)
    local selectable_issue = row and row.index ~= nil
    if not selectable_object and not selectable_issue then return false, "Focus a selectable row" end
  elseif id == "collapse_focused" or id == "expand_focused" then
    local row = ctx.focused_row
    if not row or not row.expandable then return false, "Focus an expandable room" end
    if id == "collapse_focused" and row.expanded == false then return false, "Room is already collapsed" end
    if id == "expand_focused" and row.expanded ~= false then return false, "Room is already expanded" end
  elseif id == "toggle_details_section" then
    local row = ctx.focused_row
    if not row or row.kind ~= "section" then return false, "Focus a Details section heading" end
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
  result.key_label = M.display_key(result.key)
  result.mapped = result.key ~= nil
  result.enabled, result.reason = availability(id, ctx)
  if id == "edit" and ctx.selection then
    if ctx.selection.kind == "plan" then
      result.handler = "edit_plan"
    elseif ctx.selection.kind == "template" then
      result.handler = "edit_template"
      result.args = { ctx.selection.id }
    end
  elseif id == "toggle_snap" then
    result.label = ctx.snap_enabled == false and "Enable snapping" or "Disable snapping"
  elseif id == "cycle_detail_level" then
    local detail = require("roomplan.canvas_detail")
    local current = detail.normalize(ctx.detail_level) or detail.default
    result.label = string.format("Canvas detail: %s → %s", current, detail.next(current))
  elseif id == "move_marked" or id == "duplicate_marked" or id == "delete_marked" then
    local verb = id == "move_marked" and "Move" or id == "duplicate_marked" and "Duplicate" or "Delete"
    result.label =
      string.format("%s %d marked object%s", verb, ctx.marked_count or 0, ctx.marked_count == 1 and "" or "s")
  elseif id == "toggle_mark" then
    result.label = ctx.focused_row and ctx.focused_row.marked and "Unmark" or "Mark"
  elseif ctx.mode == "RESIZE" then
    if id == "select" then result.label = "Select section"
    elseif id == "add" then result.label = "Add section"
    elseif id == "delete" then result.label = "Remove section" end
  elseif id == "leave_mode" and ctx.mode == "RESIZE" then
    result.label = "Cancel resize"
  end
  return result
end

local function is_form(ctx)
  return ctx.form ~= nil
end

local function ids_for(ctx)
  if ctx.form then
    return { "previous_field", "next_field", "edit_field", "apply", "reset", "cancel" }
  end
  if ctx.mode == "MOVE" then return { "leave_mode", "undo", "redo", "save", "help" } end
  if ctx.mode == "PAN" then return { "leave_mode", "fit", "help" } end
  if ctx.mode == "RESIZE" then
    return {
      "shape_apply", "select", "shape_next", "shape_previous", "add", "delete",
      "toggle_snap", "bypass_snap", "leave_mode", "help",
    }
  end

  local kind = selected_kind(ctx)
  if room_count(ctx) == 0 then
    if kind == "plan" then
      return { "edit", "add_room", "fit", "validate", "save", "undo", "redo", "help", "hide" }
    end
    return {
      "add_room", "add_door", "add_window", "add_outlet", "add_furniture",
      "fit", "save", "undo", "redo", "help", "hide",
    }
  elseif kind == "plan" then
    return { "edit", "add", "fit", "validate", "save", "undo", "redo", "help", "hide" }
  elseif kind == "room" then
    return {
      "edit", "resize_dimensions", "move", "align", "add", "fit", "duplicate",
      "delete", "validate", "save", "undo", "redo", "help",
    }
  elseif kind == "furniture" then
    return {
      "edit", "resize_dimensions", "move", "rotate", "fit", "duplicate", "delete",
      "validate", "save", "undo", "redo", "help",
    }
  elseif kind == "door" then
    return { "edit", "move", "fit", "duplicate", "delete", "validate", "save", "undo", "redo", "help" }
  elseif kind == "window" or kind == "outlet" then
    return { "edit", "move", "fit", "duplicate", "delete", "validate", "save", "undo", "redo", "help" }
  elseif kind == "template" then
    return { "edit", "resize_dimensions", "duplicate", "delete", "save", "undo", "redo", "help" }
  end
  return { "add", "select", "fit", "validate", "save", "pan", "undo", "redo", "help", "hide" }
end

local pane_ids = {
  objects = { "activate_focused", "toggle_mark", "collapse_focused", "expand_focused", "filter_focused" },
  issues = { "activate_focused", "filter_focused", "validate" },
  properties = { "toggle_details_section" },
}

local safe_full_ids = {
  "fit", "cycle_detail_level", "zoom_in", "zoom_out", "rotate_view_clockwise", "rotate_view_counterclockwise", "reset_view",
  "validate", "next_issue", "previous_issue",
  "toggle_snap", "bypass_snap",
  "measure", "aspect", "save", "save_as", "undo", "redo",
  "history_list", "reload", "close",
}

local selection_full_ids = { "edit", "move", "align",
  "place_furniture", "rotate", "duplicate", "delete",
  "move_marked",
  "duplicate_marked",
  "delete_marked",
  "clear_marks" }

local function create_full_ids(ctx)
  if room_count(ctx) == 0 then
    return { "add_room", "add_door", "add_window", "add_outlet", "add_furniture" }
  end
  return { "add", "add_door", "add_window", "add_outlet", "add_furniture" }
end

local function primary_ids_for(ctx)
  if is_form(ctx) then
    return { "edit_field", "apply", "cancel", "help" }
  end
  if ctx.mode == "MOVE" then return { "leave_mode", "undo", "redo", "help" } end
  if ctx.mode == "PAN" then return { "leave_mode", "fit", "help" } end
  if ctx.mode == "RESIZE" then
    return {
      "shape_apply", "select", "shape_next", "add", "delete", "toggle_snap", "leave_mode", "help",
    }
  end

  local focus = focused_pane(ctx)
  if focus == "objects" then
    return { "activate_focused", "toggle_mark", "collapse_focused", "expand_focused", "filter_focused", "help" }
  elseif focus == "issues" then
    return { "activate_focused", "filter_focused", "validate", "help" }
  elseif focus == "properties" then
    return { "toggle_details_section", "edit", "help" }
  end

  local kind = selected_kind(ctx)
  if room_count(ctx) == 0 then
    if kind == "plan" then return { "edit", "add_room", "fit", "help" } end
    return { "add_room", "fit", "help" }
  elseif kind == "plan" then
    return { "edit", "add", "fit", "help" }
  elseif kind == "room" then
    return { "edit", "resize_dimensions", "move", "align", "add", "help" }
  elseif kind == "furniture" then
    return { "edit", "resize_dimensions", "move", "rotate", "delete", "help" }
  elseif kind == "door" then
    return { "edit", "move", "delete", "help" }
  elseif kind == "window" or kind == "outlet" then
    return { "edit", "move", "delete", "help" }
  elseif kind == "template" then
    return { "edit", "resize_dimensions", "duplicate", "delete", "help" }
  end
  return { "add", "select", "fit", "help" }
end

local function id_set(ids)
  local result = {}
  for _, id in ipairs(ids or {}) do result[id] = true end
  return result
end

local function actions_for(ids, ctx, opts)
  opts = opts or {}
  local primary = id_set(primary_ids_for(ctx))
  local excluded = id_set(opts.exclude)
  local result = {}
  for _, id in ipairs(ids or {}) do
    if not excluded[id] then
      local action = M.get(id, ctx)
      if action
        and (opts.include_disabled ~= false or action.enabled)
        and (opts.include_unmapped ~= false or action.mapped)
      then
        action.primary = primary[id] == true
        result[#result + 1] = action
      end
    end
  end
  return result
end

function M.contextual(ctx, opts)
  return actions_for(ids_for(ctx or {}), ctx or {}, opts)
end

---Return the small, focus-aware set intended for persistent UI chrome.
---Disabled entries are hidden by default so the footer remains concise.
function M.primary(ctx, opts)
  opts = clone(opts or {})
  if opts.include_disabled == nil then opts.include_disabled = false end
  if opts.include_unmapped == nil then opts.include_unmapped = false end
  local result = actions_for(primary_ids_for(ctx or {}), ctx or {}, opts)
  for _, action in ipairs(result) do
    if action.id == "help" then action.count = M.more_count(ctx) end
  end
  return result
end

local function full_ids_for(ctx)
  if is_form(ctx) then return ids_for(ctx) end

  local result, seen = {}, {}
  local focus = focused_pane(ctx)
  local function in_scope(id)
    for _, scope in ipairs(definitions[id].scopes or {}) do
      if scope == focus then return true end
    end
    return false
  end
  local function append(ids)
    for _, id in ipairs(ids or {}) do
      if not seen[id] and in_scope(id) then
        seen[id] = true
        result[#result + 1] = id
      end
    end
  end
  append(pane_ids[focused_pane(ctx)])
  append(ids_for(ctx))
  if ctx.mode == "RESIZE" then return result end
  if ctx.mode == nil or ctx.mode == "NAV" then
    append(create_full_ids(ctx))
    append(selection_full_ids)
    append({ "select", "pan" })
  end
  append(safe_full_ids)
  append({ "objects", "canvas", "properties", "issues", "hide" })
  return result
end

---Return every action relevant to the active pane and interaction context.
---Results are grouped for palettes and include disabled actions by default.
function M.full(ctx, opts)
  ctx = ctx or {}
  opts = opts or {}
  local actions = actions_for(full_ids_for(ctx), ctx, opts)
  local grouped = {}
  for _, action in ipairs(actions) do
    grouped[action.group] = grouped[action.group] or {}
    grouped[action.group][#grouped[action.group] + 1] = action
  end
  local result = {}
  for _, group in ipairs(M.groups()) do
    for _, action in ipairs(grouped[group.id] or {}) do result[#result + 1] = action end
  end
  return result
end

function M.grouped(ctx, opts)
  local result, indexed = {}, {}
  for _, action in ipairs(M.full(ctx, opts)) do
    local entry = indexed[action.group]
    if not entry then
      entry = { id = action.group, label = action.group_label, actions = {} }
      indexed[action.group] = entry
      result[#result + 1] = entry
    end
    entry.actions[#entry.actions + 1] = action
  end
  return result
end

function M.more_count(ctx)
  ctx = ctx or {}
  local visible = {}
  for _, action in ipairs(actions_for(primary_ids_for(ctx), ctx, {
    include_disabled = false,
    include_unmapped = false,
    exclude = { "help" },
  })) do
    visible[action.id] = true
  end
  local count = 0
  for _, action in ipairs(M.full(ctx, { include_disabled = true, exclude = { "help" } })) do
    if not visible[action.id] then count = count + 1 end
  end
  return count
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
  for _, action in ipairs(M.primary(ctx, { include_disabled = true })) do
    if action.key ~= nil and action.key == key then return action end
  end
  for _, action in ipairs(M.full(ctx, { include_disabled = true })) do
    if action.key ~= nil and action.key == key then return action end
  end
end

function M.mode_label(ctx)
  local mode = tostring(ctx and ctx.mode or "NAV"):gsub("_", " ")
  if mode == "NAV" then return "NAV" end
  if mode == "MOVE" then
    return "MOVE · h/j/k/l move · H/J/K/L coarse · Ctrl-h/j/k/l fine"
      .. (ctx.move_feedback and (" · " .. ctx.move_feedback) or "")
      .. (ctx.snap_summary and (" · SNAP " .. ctx.snap_summary) or "")
  end
  if mode == "PAN" then return "PAN · h/j/k/l pan" end
  if mode == "RESIZE" then
    local label = ctx.selection and ctx.selection.kind == "template" and "TEMPLATE RESIZE" or "RESIZE"
    return string.format("%s · section %d/%d · edge %s · snap %s",
      label,
      ctx.shape_section_index or 0, ctx.shape_section_count or 0,
      ctx.shape_edge or "choose with h/j/k/l",
      ctx.shape_snap or (ctx.snap_enabled == false and "off" or "ready"))
  end
  return mode
end

function M.hint(action)
  local suffix = action.enabled and "" or (" (disabled: " .. tostring(action.reason) .. ")")
  if action.key == nil then return string.format("%s (unmapped)%s", action.label, suffix) end
  return string.format("[%s] %s%s", action.key_label or M.display_key(action.key), action.label, suffix)
end

function M.definitions()
  return clone(definitions)
end

function M.groups()
  local result = {}
  for id, group in pairs(groups) do
    result[#result + 1] = { id = id, label = group.label, order = group.order }
  end
  table.sort(result, function(left, right)
    if left.order == right.order then return left.id < right.id end
    return left.order < right.order
  end)
  return result
end

return M
