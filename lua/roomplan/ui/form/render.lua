-- Pure text presentation for structured forms.  The returned metadata lets
-- the Neovim adapter place the cursor and highlights without parsing text.

local fields = require("roomplan.ui.form.fields")
local form_state = require("roomplan.ui.form.state")

local M = {}

local function display_key(key)
  local friendly = {
    ["<CR>"] = "Enter", ["<C-s>"] = "Ctrl-s", ["<Esc>"] = "Esc",
    ["<Space>"] = "Space", ["<Tab>"] = "Tab", ["<S-Tab>"] = "Shift-Tab",
  }
  return key and (friendly[key] or key) or nil
end

local function hint(key, label)
  key = display_key(key)
  return key and ("[" .. key .. "] " .. label) or (label .. " (unmapped)")
end

local function footer_lines(state, active, opts)
  local footer = state.spec.footer
  if type(footer) == "function" then footer = footer(state, active) end
  if type(footer) == "string" then return { footer } end
  if type(footer) == "table" then return footer end
  local keys = opts.keys or {
    edit = "<CR>", previous_choice = "h", next_choice = "l", toggle = "<Space>",
    apply = "<C-s>", cancel = "<Esc>", cancel_alt = "q",
  }
  local edit_hint = hint(keys.edit, "Edit")
  if active then
    if active.type == "enum" or active.type == "object_ref" then
      local cycle = display_key(keys.previous_choice) and display_key(keys.next_choice)
          and string.format("[%s/%s] Cycle", display_key(keys.previous_choice), display_key(keys.next_choice))
        or "Cycle (unmapped)"
      edit_hint = hint(keys.edit, "Choose") .. "  " .. cycle
    elseif active.type == "toggle" then
      local toggle = display_key(keys.edit) or display_key(keys.toggle)
      edit_hint = hint(toggle, "Toggle")
    elseif active.type == "readonly" then
      edit_hint = ""
    end
  end
  local apply = state.spec.apply_label or "Apply"
  local cancel_keys = {}
  if display_key(keys.cancel) then cancel_keys[#cancel_keys + 1] = display_key(keys.cancel) end
  if display_key(keys.cancel_alt) then cancel_keys[#cancel_keys + 1] = display_key(keys.cancel_alt) end
  local cancel = #cancel_keys > 0 and ("[" .. table.concat(cancel_keys, "/") .. "] Cancel") or "Cancel (unmapped)"
  return {
    string.format("%s%s%s  %s", edit_hint, edit_hint ~= "" and "  " or "", hint(keys.apply, apply), cancel),
  }
end

local function preview_lines(state)
  local preview = state.preview or {}
  local lines = {}
  for index = 1, #(preview.lines or {}) do lines[index] = tostring(preview.lines[index]) end
  return lines, preview.error
end

function M.build(state, opts)
  opts = opts or {}
  local visible = form_state.visible_fields(state)
  local label_width = 0
  for _, field in ipairs(visible) do
    label_width = math.max(label_width, #(field.label or field.key))
  end
  label_width = math.min(opts.max_label_width or 24, math.max(8, label_width))

  local lines = {}
  local meta = {
    field_rows = {},
    error_rows = {},
    readonly_rows = {},
    preview_rows = {},
    footer_rows = {},
  }
  local function push(value)
    lines[#lines + 1] = tostring(value or "")
    return #lines
  end

  local title = state.spec.title or state.spec.id or "RoomPlan form"
  local mode = state.spec.mode and ("  [" .. state.spec.mode .. "]") or ""
  meta.title_row = push(title .. mode)
  if state.spec.description then push(state.spec.description) end
  push(string.rep("-", math.max(16, math.min(opts.width or 72, #title + #mode + 4))))

  for _, field in ipairs(visible) do
    local value = fields.value(field, state.context, state.draft, state)
    local formatted = state.raw and state.raw[field.key]
    if formatted == nil then formatted = fields.format(field, value, state.context, state.draft, state) end
    formatted = tostring(formatted)
    local marker = field.key == state.active_key and ">" or " "
    local suffix = fields.enabled(field, state.context, state.draft, state) and "" or "  (read-only)"
    local row = push(string.format("%s %-" .. label_width .. "s  %s%s", marker, field.label or field.key, formatted, suffix))
    meta.field_rows[field.key] = row
    if not fields.enabled(field, state.context, state.draft, state) then meta.readonly_rows[row] = true end
    if state.errors[field.key] then
      local error_row = push(string.format("  %-" .. label_width .. "s  ! %s", "", state.errors[field.key]))
      meta.error_rows[error_row] = true
    end
  end

  local previews, preview_error = preview_lines(state)
  if opts.include_preview ~= false and (#previews > 0 or preview_error) then
    push("")
    meta.preview_title_row = push(state.spec.preview_title or "Preview")
    for _, line in ipairs(previews) do meta.preview_rows[push("  " .. line)] = true end
    if preview_error then meta.error_rows[push("  ! " .. preview_error)] = true end
  elseif preview_error then
    push("")
    meta.error_rows[push("! " .. preview_error)] = true
  end

  if state.form_error then
    push("")
    meta.error_rows[push("! " .. state.form_error)] = true
  end
  if state.stale then meta.stale = true end

  push("")
  local active = state.active_key and form_state.field(state, state.active_key) or nil
  for _, line in ipairs(footer_lines(state, active, opts)) do meta.footer_rows[push(line)] = true end

  meta.active_row = state.active_key and meta.field_rows[state.active_key] or nil
  meta.width = opts.width
  meta.height = #lines
  return { lines = lines, meta = meta }
end

return M
