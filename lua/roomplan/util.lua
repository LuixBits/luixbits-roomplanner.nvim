local M = {}

function M.deepcopy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local copy = {}
  seen[value] = copy
  for key, item in pairs(value) do
    copy[M.deepcopy(key, seen)] = M.deepcopy(item, seen)
  end
  return setmetatable(copy, getmetatable(value))
end

function M.tbl_isempty(value) return type(value) == "table" and next(value) == nil end

function M.index_by_id(items)
  local out = {}
  for index, item in ipairs(items or {}) do
    if type(item) == "table" and type(item.id) == "string" then out[item.id] = { item = item, index = index } end
  end
  return out
end

function M.clamp(value, low, high) return math.max(low, math.min(high, value)) end

function M.round(value)
  if value >= 0 then return math.floor(value + 0.5) end
  return math.ceil(value - 0.5)
end

function M.basename(path) return (path or ""):gsub("\\", "/"):match("([^/]+)$") or path end

function M.escape_pattern(text) return (text:gsub("([^%w])", "%%%1")) end

function M.list_copy(items)
  local out = {}
  for i, value in ipairs(items or {}) do
    out[i] = value
  end
  return out
end

function M.err(code, message, details) return { code = code, message = message, details = details or {} } end

return M
