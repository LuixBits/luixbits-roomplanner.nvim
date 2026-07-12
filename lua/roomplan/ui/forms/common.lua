local ids = require("roomplan.ids")
local model_helpers = require("roomplan.model")

local M = {}

function M.model(context)
  local session = context and context.session
  if session then
    if type(session.current_model) == "function" then return session:current_model() end
    if type(session.model) == "function" then return session:model() end
  end
  return context and context.model or nil
end

function M.find(context, kind, id)
  return model_helpers.find(M.model(context), kind, id)
end

function M.rooms(context, exclude_id)
  local result = {}
  for _, room in ipairs((M.model(context) and M.model(context).rooms) or {}) do
    if room.id ~= exclude_id then
      result[#result + 1] = {
        value = room.id,
        label = string.format("%s (%s)", room.name or room.id, room.id),
        raw = room,
      }
    end
  end
  return result
end

function M.selected_room(context)
  local session = context and context.session
  local selection = session and session.selection
  if selection and selection.kind == "room" and M.find(context, "room", selection.id) then return selection.id end
  local rooms = M.model(context) and M.model(context).rooms or {}
  return rooms[1] and rooms[1].id or nil
end

function M.generate_id(context, kind, name)
  local session = context and context.session
  local used = ids.used_set(M.model(context), session and session.reserved_ids or nil)
  return ids.generate(kind, name, used)
end

function M.error_message(err)
  if type(err) == "table" then return err.message or err.code or tostring(err) end
  return tostring(err)
end

function M.point_text(point)
  if type(point) ~= "table" then return "unavailable" end
  return string.format("(%s, %s) mm", tostring(point[1]), tostring(point[2]))
end

function M.cursor(context)
  local value = context and context.cursor_mm
  if type(value) == "function" then value = value(context) end
  if type(value) == "table" and type(value[1]) == "number" and type(value[2]) == "number" then
    return { value[1], value[2] }
  end
  return nil
end

return M
