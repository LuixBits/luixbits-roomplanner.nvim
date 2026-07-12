local list = require("roomplan.ui.list")

local M = {}

local function model_of(session)
  if session.current_model then
    return session:current_model()
  end
  return session.model
end

function M.items(session)
  local model = model_of(session) or {}
  local items = {}
  items[#items + 1] = {
    kind = "plan",
    name = model.metadata and model.metadata.name or "Untitled plan",
    line = string.format("[PLAN] %s  metadata/settings", model.metadata and model.metadata.name or "Untitled plan"),
  }
  for _, room in ipairs(model.rooms or {}) do
    local origin = room.origin_mm or { 0, 0 }
    local size = room.size_mm or { 0, 0 }
    items[#items + 1] = {
      kind = "room",
      id = room.id,
      object = room,
      line = string.format("[ROOM] %s  %s  origin=(%s,%s) size=%sx%s", room.name or "", room.id or "?", origin[1], origin[2], size[1], size[2]),
    }
  end
  for _, door in ipairs(model.doors or {}) do
    items[#items + 1] = {
      kind = "door",
      id = door.id,
      object = door,
      line = string.format("[DOOR] %s  owner=%s %s offset=%s width=%s", door.id or "?", door.room_id or "?", door.side or "?", door.offset_mm or "?", door.width_mm or "?"),
    }
  end
  for _, furniture in ipairs(model.furniture or {}) do
    local center = furniture.center_mm or { 0, 0 }
    items[#items + 1] = {
      kind = "furniture",
      id = furniture.id,
      object = furniture,
      line = string.format("[FURNITURE] %s  %s  room=%s centre=(%s,%s)", furniture.name or "", furniture.id or "?", furniture.room_id or "?", center[1], center[2]),
    }
  end
  for _, template in ipairs(model.custom_templates or {}) do
    local size = template.default_size_mm or { 0, 0, 0 }
    items[#items + 1] = {
      kind = "template",
      id = template.id,
      object = template,
      line = string.format("[TEMPLATE] %s  %s  %s %sx%sx%s", template.name or "", template.id or "?", template.category or "?", size[1], size[2], size[3]),
    }
  end
  return items
end

function M.open(session)
  local items = M.items(session)
  local lines = {}
  for index, item in ipairs(items) do
    lines[index] = item.line
  end
  return list.open(session, {
    role = "object-list",
    filetype = "roomplan-objects",
    lines = lines,
    items = items,
    on_choose = function(_, item)
      if not item then
        return
      end
      local controller = require("roomplan.controller")
      if item.kind == "plan" then
        controller.edit_plan(session)
      elseif item.kind == "template" then
        controller.edit_template(session, item.id)
      else
        session.selection = { kind = item.kind, id = item.id }
        controller.focus_canvas(session, item)
      end
    end,
  })
end

return M
