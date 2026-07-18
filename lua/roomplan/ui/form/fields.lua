-- Pure field semantics for RoomPlan's structured forms.  This module has no
-- Neovim dependency; field specs and drafts are ordinary Lua tables.

local units = require("roomplan.units")

local M = {}

local SUPPORTED = {
  text = true,
  measurement = true,
  integer = true,
  enum = true,
  object_ref = true,
  toggle = true,
  readonly = true,
  action = true,
}

local function resolve(value, context, draft, field, state)
  if type(value) == "function" then
    return value(context, draft, field, state)
  end
  return value
end

local function error_message(err)
  if type(err) == "table" then
    return err.message or err.code or tostring(err)
  end
  return tostring(err)
end

local function trimmed(value)
  return (value:gsub("^[ \t\r\n]+", ""):gsub("[ \t\r\n]+$", ""))
end

function M.supported(kind)
  return SUPPORTED[kind] == true
end

function M.visible(field, context, draft, state)
  if field.hidden == true then return false end
  if type(field.visible) == "function" then
    return field.visible(context, draft, field, state) ~= false
  end
  return field.visible ~= false
end

function M.enabled(field, context, draft, state)
  if field.type == "readonly" or field.readonly == true then return false end
  if type(field.enabled) == "function" then
    return field.enabled(context, draft, field, state) ~= false
  end
  return field.enabled ~= false
end

function M.value(field, context, draft, state)
  if (field.type == "readonly" or field.type == "action") and field.value ~= nil then
    return resolve(field.value, context, draft, field, state)
  end
  return draft[field.key]
end

function M.default(field, context, draft, state)
  return resolve(field.default, context, draft, field, state)
end

local function normalize_choice(item)
  if type(item) ~= "table" then
    return { value = item, label = tostring(item) }
  end
  if item.value ~= nil or item.label ~= nil then
    return {
      value = item.value,
      label = tostring(item.label ~= nil and item.label or item.value),
      description = item.description,
      disabled = item.disabled == true,
      raw = item,
    }
  end
  if item.id ~= nil then
    return {
      value = item.id,
      label = tostring(item.name or item.label or item.id),
      description = item.description,
      disabled = item.disabled == true,
      raw = item,
    }
  end
  return { value = item, label = tostring(item.name or item[1] or "item"), raw = item }
end

function M.choices(field, context, draft, state)
  local source = resolve(field.choices, context, draft, field, state) or {}
  local result = {}
  for index = 1, #source do
    result[index] = normalize_choice(source[index])
  end
  return result
end

function M.choice(field, value, context, draft, state)
  local choices = M.choices(field, context, draft, state)
  for index = 1, #choices do
    if choices[index].value == value then return choices[index], index, choices end
  end
  return nil, nil, choices
end

local function number_option(field, name, context, draft, state)
  return resolve(field[name], context, draft, field, state)
end

function M.parse(field, raw, context, draft, state)
  local kind = field.type or "text"
  if kind == "readonly" then
    return nil, { code = "FORM_FIELD_READONLY", message = (field.label or field.key) .. " is read-only" }
  elseif kind == "action" then
    return nil, { code = "FORM_FIELD_ACTION", message = (field.label or field.key) .. " is an action" }
  elseif kind == "text" then
    if type(raw) ~= "string" then raw = tostring(raw or "") end
    if field.trim == true then raw = trimmed(raw) end
    local maximum = number_option(field, "max_length", context, draft, state)
    if maximum and #raw > maximum then
      return nil, { code = "FORM_TEXT_MAX", message = string.format("must contain at most %d bytes", maximum) }
    end
    return raw
  elseif kind == "measurement" then
    return units.parse(tostring(raw or ""), {
      allow_negative = number_option(field, "allow_negative", context, draft, state) == true,
      allow_zero = number_option(field, "allow_zero", context, draft, state) == true,
      min = number_option(field, "min", context, draft, state),
      max = number_option(field, "max", context, draft, state),
      max_abs = number_option(field, "max_abs", context, draft, state),
    })
  elseif kind == "integer" then
    local value
    if type(raw) == "number" and raw == math.floor(raw) then
      value = raw
    elseif type(raw) == "string" and raw:match("^[+-]?%d+$") then
      value = tonumber(raw)
    end
    if not value or value ~= math.floor(value) then
      return nil, { code = "FORM_INTEGER", message = "expected a whole number" }
    end
    local minimum = number_option(field, "min", context, draft, state)
    local maximum = number_option(field, "max", context, draft, state)
    if minimum ~= nil and value < minimum then
      return nil, { code = "FORM_INTEGER_MIN", message = "must be at least " .. tostring(minimum) }
    end
    if maximum ~= nil and value > maximum then
      return nil, { code = "FORM_INTEGER_MAX", message = "must be at most " .. tostring(maximum) }
    end
    return value
  elseif kind == "enum" or kind == "object_ref" then
    local choice = M.choice(field, raw, context, draft, state)
    if not choice and field.allow_unknown ~= true then
      return nil, { code = "FORM_CHOICE", message = "choose one of the available values" }
    end
    if choice and choice.disabled then
      return nil, { code = "FORM_CHOICE_DISABLED", message = choice.description or "that choice is unavailable" }
    end
    return choice and choice.value or raw
  elseif kind == "toggle" then
    if type(raw) == "boolean" then return raw end
    if raw == 1 or raw == "1" or raw == "true" or raw == "yes" or raw == "on" then return true end
    if raw == 0 or raw == "0" or raw == "false" or raw == "no" or raw == "off" then return false end
    return nil, { code = "FORM_TOGGLE", message = "expected yes or no" }
  end
  return nil, { code = "FORM_FIELD_TYPE", message = "unsupported field type " .. tostring(kind) }
end

function M.validate(field, value, context, draft, state)
  if not M.visible(field, context, draft, state) then return nil end
  local kind = field.type or "text"
  if kind == "action" then return nil end
  if kind ~= "readonly" and field.required == true then
    if value == nil or (type(value) == "string" and trimmed(value) == "") then
      return "is required"
    end
  end
  if (kind == "enum" or kind == "object_ref") and value ~= nil and field.allow_unknown ~= true then
    local choice = M.choice(field, value, context, draft, state)
    if not choice then return "is no longer available" end
    if choice.disabled then return choice.description or "is unavailable" end
  end
  if kind == "text" and value ~= nil then
    if type(value) ~= "string" then return "must be text" end
    local maximum = number_option(field, "max_length", context, draft, state)
    if maximum and #value > maximum then return string.format("must contain at most %d bytes", maximum) end
  elseif kind == "measurement" and value ~= nil then
    if type(value) ~= "number" or value ~= math.floor(value) then return "must be a whole number of millimetres" end
    local minimum = number_option(field, "min", context, draft, state)
    local maximum = number_option(field, "max", context, draft, state)
    local allow_negative = number_option(field, "allow_negative", context, draft, state) == true
    local allow_zero = number_option(field, "allow_zero", context, draft, state) == true
    if value < 0 and not allow_negative and not (minimum and minimum < 0) then return "must not be negative" end
    if value == 0 and not allow_zero and not (minimum and minimum <= 0) then return "must be greater than zero" end
    if minimum ~= nil and value < minimum then return "must be at least " .. tostring(minimum) .. " mm" end
    if maximum ~= nil and value > maximum then return "must be at most " .. tostring(maximum) .. " mm" end
  elseif kind == "integer" and value ~= nil then
    if type(value) ~= "number" or value ~= math.floor(value) then return "must be a whole number" end
    local minimum = number_option(field, "min", context, draft, state)
    local maximum = number_option(field, "max", context, draft, state)
    if minimum ~= nil and value < minimum then return "must be at least " .. tostring(minimum) end
    if maximum ~= nil and value > maximum then return "must be at most " .. tostring(maximum) end
  elseif kind == "toggle" and value ~= nil and type(value) ~= "boolean" then
    return "must be yes or no"
  end
  if type(field.validate) == "function" then
    local first, second = field.validate(value, context, draft, field, state)
    if first == false then return error_message(second or "is invalid") end
    if type(first) == "string" or type(first) == "table" then return error_message(first) end
    if first == nil and second ~= nil then return error_message(second) end
  end
  return nil
end

function M.format(field, value, context, draft, state)
  if type(field.format) == "function" then
    return tostring(field.format(value, context, draft, field, state) or "")
  end
  local kind = field.type or "text"
  if kind == "action" then return tostring(value or field.action_label or "Open…") end
  if value == nil then return field.empty_text or "—" end
  if kind == "measurement" then
    local formatted = units.format_mm(value)
    return formatted or tostring(value)
  elseif kind == "enum" or kind == "object_ref" then
    local choice = M.choice(field, value, context, draft, state)
    return choice and choice.label or tostring(value)
  elseif kind == "toggle" then
    return value and (field.true_label or "yes") or (field.false_label or "no")
  elseif type(value) == "table" then
    local parts = {}
    for index = 1, #value do parts[index] = tostring(value[index]) end
    if #parts > 0 then return table.concat(parts, ", ") end
  end
  return tostring(value)
end

function M.input_default(field, value, context, draft, state)
  if type(field.input_format) == "function" then
    return tostring(field.input_format(value, context, draft, field, state) or "")
  end
  return value == nil and "" or tostring(value)
end

return M
