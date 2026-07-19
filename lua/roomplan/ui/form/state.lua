-- Immutable structured-form state and reducer.  Window management belongs in
-- ui/form/init.lua; this module is intentionally usable in plain Lua tests.

local field_helpers = require("roomplan.ui.form.fields")
local util = require("roomplan.util")

local M = {}

local function equal(left, right, seen)
  if left == right then return true end
  if type(left) ~= type(right) or type(left) ~= "table" then return false end
  seen = seen or {}
  if seen[left] == right then return true end
  seen[left] = right
  for key, value in pairs(left) do
    if not equal(value, right[key], seen) then return false end
  end
  for key in pairs(right) do
    if left[key] == nil then return false end
  end
  return true
end

local function copy(state)
  local result = {}
  for key, value in pairs(state) do
    result[key] = value
  end
  result.draft = util.deepcopy(state.draft or {})
  result.initial_draft = util.deepcopy(state.initial_draft or {})
  result.errors = util.deepcopy(state.errors or {})
  result.raw = util.deepcopy(state.raw or {})
  result.preview = util.deepcopy(state.preview or { lines = {} })
  return result
end

local function field_index(spec)
  local result = {}
  for index, field in ipairs(spec.fields or {}) do
    assert(type(field.key) == "string" and field.key ~= "", "form field requires a key")
    assert(field_helpers.supported(field.type or "text"), "unsupported form field type " .. tostring(field.type))
    assert(result[field.key] == nil, "duplicate form field key " .. field.key)
    result[field.key] = { field = field, index = index }
  end
  return result
end

local function preview_for(state)
  if type(state.spec.preview) ~= "function" then return { lines = {} } end
  local first, second = state.spec.preview(state.draft, state.context, state)
  if first == nil then
    local message = type(second) == "table" and (second.message or second.code) or second
    return { lines = {}, error = message and tostring(message) or nil }
  elseif type(first) == "string" then
    return { lines = { first } }
  elseif type(first) == "table" and type(first.lines) == "table" then
    return util.deepcopy(first)
  elseif type(first) == "table" then
    local lines = {}
    for index = 1, #first do
      lines[index] = tostring(first[index])
    end
    return { lines = lines }
  end
  return { lines = { tostring(first) } }
end

function M.visible_fields(state)
  local result = {}
  for _, field in ipairs(state.spec.fields or {}) do
    if field_helpers.visible(field, state.context, state.draft, state) then result[#result + 1] = field end
  end
  return result
end

function M.editable_fields(state)
  local result = {}
  for _, field in ipairs(M.visible_fields(state)) do
    if field_helpers.enabled(field, state.context, state.draft, state) then result[#result + 1] = field end
  end
  return result
end

function M.field(state, key)
  local record = state.field_index[key]
  return record and record.field or nil
end

local function normalize_active(state, preferred_index)
  local fields = M.editable_fields(state)
  if #fields == 0 then
    state.active_key = nil
    return
  end
  for _, field in ipairs(fields) do
    if field.key == state.active_key then return end
  end
  preferred_index = math.max(1, math.min(preferred_index or 1, #fields))
  state.active_key = fields[preferred_index].key
end

local function clear_hidden_errors(state)
  for key in pairs(state.errors) do
    local field = M.field(state, key)
    if field and not field_helpers.visible(field, state.context, state.draft, state) then state.errors[key] = nil end
  end
end

local function refresh(state)
  clear_hidden_errors(state)
  normalize_active(state)
  state.preview = preview_for(state)
  state.dirty = not equal(state.draft, state.initial_draft) or next(state.raw or {}) ~= nil
  state.version = (state.version or 0) + 1
  return state
end

local function apply_patch(draft, patch)
  if type(patch) ~= "table" then return end
  for key, value in pairs(patch) do
    draft[key] = util.deepcopy(value)
  end
end

local function normalize_error(value)
  if value == nil or value == false then return nil end
  if type(value) == "table" then return value.message or value.code or tostring(value) end
  return tostring(value)
end

local function set_value(state, key, raw, parsed)
  local field = M.field(state, key)
  if not field then
    state.form_error = "unknown form field " .. tostring(key)
    return refresh(state)
  end
  if not field_helpers.visible(field, state.context, state.draft, state) then
    state.form_error = (field.label or key) .. " is not currently available"
    return refresh(state)
  end
  if not field_helpers.enabled(field, state.context, state.draft, state) then
    state.form_error = (field.label or key) .. " is read-only"
    return refresh(state)
  end
  local value, err
  if parsed then
    value = raw
  else
    value, err = field_helpers.parse(field, raw, state.context, state.draft, state)
  end
  if err then
    state.raw[key] = raw
    state.errors[key] = normalize_error(err)
    state.form_error = nil
    state.active_key = key
    return refresh(state)
  end
  local old = state.draft[key]
  state.draft[key] = util.deepcopy(value)
  state.raw[key] = nil
  state.errors[key] = field_helpers.validate(field, value, state.context, state.draft, state)
  state.form_error = nil
  if type(field.on_change) == "function" then
    apply_patch(state.draft, field.on_change(value, old, state.context, state.draft, field, state))
  end
  if type(state.spec.on_change) == "function" then
    apply_patch(state.draft, state.spec.on_change(key, value, old, state.draft, state.context, state))
  end
  state.active_key = key
  return refresh(state)
end

local function merge_spec_errors(state, result, second)
  if result == false then
    state.form_error = normalize_error(second or "form is invalid")
    return
  end
  if type(result) == "string" then
    state.form_error = result
    return
  end
  if type(result) ~= "table" then
    if result == nil and second ~= nil then state.form_error = normalize_error(second) end
    return
  end
  if result.message and not result.field and not result.key then
    state.form_error = normalize_error(result)
    return
  end
  for key, value in pairs(result) do
    if type(key) == "number" and type(value) == "table" then
      local field_key = value.field or value.key
      if field_key then state.errors[field_key] = normalize_error(value.message or value.error) end
    elseif state.field_index[key] then
      state.errors[key] = normalize_error(value)
    elseif key == "_form" then
      state.form_error = normalize_error(value)
    end
  end
end

function M.validate_all(state)
  local next_state = copy(state)
  next_state.errors = {}
  next_state.form_error = nil
  for _, field in ipairs(M.visible_fields(next_state)) do
    local value = field_helpers.value(field, next_state.context, next_state.draft, next_state)
    local err
    if next_state.raw[field.key] ~= nil then
      local parsed, parse_err =
        field_helpers.parse(field, next_state.raw[field.key], next_state.context, next_state.draft, next_state)
      if parse_err then
        err = normalize_error(parse_err)
      else
        value = parsed
        next_state.draft[field.key] = util.deepcopy(parsed)
        next_state.raw[field.key] = nil
      end
    end
    err = err or field_helpers.validate(field, value, next_state.context, next_state.draft, next_state)
    if err then next_state.errors[field.key] = err end
  end
  if type(next_state.spec.validate) == "function" then
    local result, second = next_state.spec.validate(next_state.draft, next_state.context, next_state)
    merge_spec_errors(next_state, result, second)
  end
  refresh(next_state)
  local valid = next(next_state.errors) == nil and next_state.form_error == nil and next_state.preview.error == nil
  if not valid then
    for _, field in ipairs(M.editable_fields(next_state)) do
      if next_state.errors[field.key] then
        next_state.active_key = field.key
        break
      end
    end
  end
  return next_state, valid
end

function M.new(spec, context, opts)
  opts = opts or {}
  assert(type(spec) == "table", "form spec must be a table")
  assert(type(spec.fields) == "table", "form spec requires fields")
  local index = field_index(spec)
  context = context or spec.context or {}
  local draft_source = opts.draft
  if draft_source == nil then
    draft_source = spec.initial
    if type(draft_source) == "function" then draft_source = draft_source(context) end
  end
  local draft = util.deepcopy(draft_source or {})
  local provisional = { spec = spec, context = context, draft = draft, field_index = index }
  for _, field in ipairs(spec.fields) do
    if field.type ~= "readonly" and field.type ~= "action" and draft[field.key] == nil then
      local value = field_helpers.default(field, context, draft, provisional)
      if value ~= nil then draft[field.key] = util.deepcopy(value) end
    end
  end
  local state = {
    spec = spec,
    context = context,
    field_index = index,
    draft = draft,
    initial_draft = util.deepcopy(draft),
    errors = {},
    raw = {},
    preview = { lines = {} },
    active_key = opts.active_key,
    form_error = nil,
    base_revision_id = opts.base_revision_id,
    stale = false,
    dirty = false,
    version = 0,
  }
  normalize_active(state)
  return refresh(state)
end

function M.reduce(state, event)
  assert(type(state) == "table" and type(event) == "table", "form reducer requires state and event")
  local next_state = copy(state)
  local kind = event.type
  if kind == "set_raw" then
    return set_value(next_state, event.key, event.value, false)
  elseif kind == "set_value" then
    return set_value(next_state, event.key, event.value, event.trusted == true)
  elseif kind == "activate" then
    local field = M.field(next_state, event.key)
    if
      field
      and field_helpers.visible(field, next_state.context, next_state.draft, next_state)
      and field_helpers.enabled(field, next_state.context, next_state.draft, next_state)
    then
      next_state.active_key = event.key
    end
    return refresh(next_state)
  elseif kind == "move" then
    local editable = M.editable_fields(next_state)
    if #editable > 0 then
      local current = 1
      for index, field in ipairs(editable) do
        if field.key == next_state.active_key then
          current = index
          break
        end
      end
      local delta = event.delta and event.delta < 0 and -1 or 1
      current = ((current - 1 + delta) % #editable) + 1
      next_state.active_key = editable[current].key
    end
    return refresh(next_state)
  elseif kind == "form_error" then
    next_state.form_error = normalize_error(event.error)
    return refresh(next_state)
  elseif kind == "clear_form_error" then
    next_state.form_error = nil
    return refresh(next_state)
  elseif kind == "stale" then
    next_state.stale = true
    next_state.form_error =
      normalize_error(event.error or "the plan changed while this form was open; cancel and reopen it")
    return refresh(next_state)
  elseif kind == "validate_all" then
    return M.validate_all(next_state)
  end
  error("unsupported form event " .. tostring(kind), 2)
end

function M.first_error_key(state)
  for _, field in ipairs(M.editable_fields(state)) do
    if state.errors[field.key] then return field.key end
  end
  return nil
end

M.equal = equal

return M
