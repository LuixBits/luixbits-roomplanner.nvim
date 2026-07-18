-- Helpers for transient Navigator multi-selection.

local model_helpers = require("roomplan.model")

local M = {}

local collections = {
  { kind = "room", key = "rooms" },
  { kind = "door", key = "doors" },
  { kind = "window", key = "windows" },
  { kind = "outlet", key = "outlets" },
  { kind = "furniture", key = "furniture" },
  { kind = "template", key = "custom_templates" },
}

function M.key(reference_or_kind, id)
  local kind = type(reference_or_kind) == "table" and reference_or_kind.kind or reference_or_kind
  id = type(reference_or_kind) == "table" and reference_or_kind.id or id
  return tostring(kind) .. "\31" .. tostring(id)
end

function M.list(model, marked)
  local result = {}
  marked = marked or {}
  for _, collection in ipairs(collections) do
    for _, object in ipairs(model and model[collection.key] or {}) do
      local reference = { kind = collection.kind, id = object.id }
      if marked[M.key(reference)] then
        result[#result + 1] = reference
      end
    end
  end
  return result
end

function M.move_refs(model, marked)
  local refs = M.list(model, marked)
  local selected_rooms = {}
  for _, reference in ipairs(refs) do
    if reference.kind == "room" then
      selected_rooms[reference.id] = true
    end
  end
  local result, unsupported = {}, {}
  for _, reference in ipairs(refs) do
    if reference.kind == "room" then
      result[#result + 1] = reference
    elseif reference.kind == "furniture" then
      local furniture = model_helpers.find(model, "furniture", reference.id)
      if furniture and not selected_rooms[furniture.room_id] then
        result[#result + 1] = reference
      end
    else
      unsupported[#unsupported + 1] = reference
    end
  end
  return result, unsupported
end

function M.delete_refs(model, marked)
  local refs = M.list(model, marked)
  local selected_rooms = {}
  for _, reference in ipairs(refs) do
    if reference.kind == "room" then
      selected_rooms[reference.id] = true
    end
  end
  local ordinary, templates = {}, {}
  for _, reference in ipairs(refs) do
    local object = model_helpers.find(model, reference.kind, reference.id)
    local owner_selected = object and object.room_id and selected_rooms[object.room_id]
    local connected_selected = object and object.connects_to_room_id and selected_rooms[object.connects_to_room_id]
    if reference.kind == "template" then
      templates[#templates + 1] = reference
    elseif reference.kind == "room" or not owner_selected and not connected_selected then
      ordinary[#ordinary + 1] = reference
    end
  end
  for _, reference in ipairs(templates) do
    ordinary[#ordinary + 1] = reference
  end
  return ordinary
end

return M
