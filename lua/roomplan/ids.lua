-- Stable globally unique RoomPlan entity IDs.

local M = {}

local PREFIX = {
  room = "room-",
  door = "door-",
  window = "window-",
  outlet = "outlet-",
  furniture = "furniture-",
  custom_template = "custom:",
  template = "custom:",
}

local COLLECTIONS = {
  { "rooms", "room", 1 },
  { "doors", "door", 1 },
  { "windows", "window", 3 },
  { "outlets", "outlet", 3 },
  { "furniture", "furniture", 1 },
  { "custom_templates", "custom_template", 1 },
}

M.prefixes = PREFIX

local function problem(code, message, id, kind)
  return { code = code, message = message, id = id, kind = kind }
end

function M.valid_syntax(id)
  if type(id) ~= "string" then
    return false, problem("ID_TYPE", "ID must be a string", id)
  end
  if #id < 1 or #id > 128 then
    return false, problem("ID_LENGTH", "ID must contain between 1 and 128 UTF-8 bytes", id)
  end
  if not id:sub(1, 1):match("^[A-Za-z]$") then
    return false, problem("ID_FIRST_CHARACTER", "ID must start with an ASCII letter", id)
  end
  if #id > 1 and not id:sub(2):match("^[A-Za-z0-9._:-]+$") then
    return false, problem("ID_CHARACTER", "ID contains a character outside A-Z, a-z, 0-9, '.', '_', ':', and '-'", id)
  end
  return true
end

function M.validate(id, kind)
  local valid, err = M.valid_syntax(id)
  if not valid then
    err.kind = kind
    return false, err
  end
  local prefix = PREFIX[kind]
  if prefix == nil then
    return false, problem("ID_KIND", "unknown RoomPlan entity kind", id, kind)
  end
  if id:sub(1, #prefix) ~= prefix then
    return false, problem("ID_PREFIX", kind .. " IDs must start with '" .. prefix .. "'", id, kind)
  end
  if #id == #prefix then
    return false, problem("ID_EMPTY_SUFFIX", "ID must contain a non-empty suffix after '" .. prefix .. "'", id, kind)
  end
  return true
end

function M.valid_room_reference(id)
  return M.validate(id, "room")
end

function M.valid_template_reference(id)
  local valid, err = M.valid_syntax(id)
  if not valid then
    return false, err
  end
  if id:sub(1, 8) == "builtin:" and #id > 8 then
    return true
  end
  if id:sub(1, 7) == "custom:" and #id > 7 then
    return true
  end
  return false, problem("TEMPLATE_ID_PREFIX", "template reference must start with 'builtin:' or 'custom:'", id, "template_reference")
end

local function add_to_index(index, id, kind, entity, collection, position)
  local existing = index[id]
  if existing then
    return nil, problem(
      "ID_DUPLICATE",
      "ID '" .. id .. "' is already used by " .. existing.kind,
      id,
      kind
    )
  end
  index[id] = {
    id = id,
    kind = kind,
    entity = entity,
    collection = collection,
    position = position,
  }
  return true
end

-- Build the one global entity index shared by every schema version.
function M.index(model)
  local index = {}
  local errors = {}
  if type(model) ~= "table" then
    return nil, { problem("ID_MODEL", "model must be a table") }
  end
  local collection_index = 1
  while collection_index <= #COLLECTIONS do
    local collection = COLLECTIONS[collection_index][1]
    local kind = COLLECTIONS[collection_index][2]
    local minimum_version = COLLECTIONS[collection_index][3]
    local entities = model[collection]
    if (type(model.schema_version) ~= "number" or model.schema_version >= minimum_version)
      and type(entities) == "table"
    then
      local position = 1
      while position <= #entities do
        local entity = entities[position]
        if type(entity) == "table" then
          local valid, err = M.validate(entity.id, kind)
          if not valid then
            errors[#errors + 1] = err
          else
            local ok
            ok, err = add_to_index(index, entity.id, kind, entity, collection, position)
            if not ok then
              errors[#errors + 1] = err
            end
          end
        end
        position = position + 1
      end
    end
    collection_index = collection_index + 1
  end
  if #errors > 0 then
    return nil, errors
  end
  return index
end

function M.used_set(model, reserved)
  local result = {}
  if type(reserved) == "table" then
    for id, value in pairs(reserved) do
      if value then
        result[id] = true
      end
    end
  end
  local index = type(model) == "table" and M.index(model) or nil
  if index then
    for id in pairs(index) do
      result[id] = true
    end
  end
  return result
end

function M.slug(value)
  if type(value) ~= "string" then
    value = ""
  end
  value = value:lower()
  value = value:gsub("[^a-z0-9]+", "-")
  value = value:gsub("^-+", ""):gsub("-+$", ""):gsub("%-+", "-")
  if value == "" then
    return "item"
  end
  return value
end

local function occupied(used, id)
  if type(used) ~= "table" then
    return false
  end
  return used[id] ~= nil and used[id] ~= false
end

-- Generate a readable ID. `options.slugger` and `options.is_used` are
-- injectable so property tests and session-level never-reuse sets do not need
-- global state.
function M.generate(kind, name, used, options)
  options = options or {}
  local prefix = PREFIX[kind]
  if not prefix then
    return nil, problem("ID_KIND", "unknown RoomPlan entity kind", nil, kind)
  end
  local slugger = options.slugger or M.slug
  local slug = slugger(name)
  if type(slug) ~= "string" then
    return nil, problem("ID_SLUGGER", "ID slugger must return a string", nil, kind)
  end
  slug = M.slug(slug)
  local maximum_suffix_length = 128 - #prefix
  if #slug > maximum_suffix_length then
    slug = slug:sub(1, maximum_suffix_length):gsub("-+$", "")
  end
  if slug == "" then
    slug = "item"
  end
  local is_used = options.is_used or function(id)
    return occupied(used, id)
  end
  local base = prefix .. slug
  if not is_used(base) then
    return base
  end
  local suffix_number = 2
  while suffix_number < 1000000000 do
    local suffix = "-" .. tostring(suffix_number)
    local allowed_slug_length = 128 - #prefix - #suffix
    local shortened = slug:sub(1, allowed_slug_length):gsub("-+$", "")
    if shortened == "" then
      shortened = ("item"):sub(1, allowed_slug_length)
    end
    local candidate = prefix .. shortened .. suffix
    if not is_used(candidate) then
      return candidate
    end
    suffix_number = suffix_number + 1
  end
  return nil, problem("ID_EXHAUSTED", "could not find a unique readable ID", nil, kind)
end

return M
