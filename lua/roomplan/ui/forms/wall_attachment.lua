-- Shared form-only helpers for objects attached to a room wall. Persisted
-- geometry and layout validation remain owned by the model/geometry layers.

local adjacency = require("roomplan.geometry.adjacency")
local wall_geometry = require("roomplan.geometry.wall_attachment")
local util = require("roomplan.util")
local common = require("roomplan.ui.forms.common")

local M = {}

M.side_choices = {
  { value = "north", label = "North" },
  { value = "east", label = "East" },
  { value = "south", label = "South" },
  { value = "west", label = "West" },
}

function M.owner(draft, context)
  return common.find(context, "room", draft.room_id)
end

function M.selected_part(room, part_id)
  for _, part in ipairs(room and room.footprint and room.footprint.parts or {}) do
    if part.id == part_id then return part end
  end
end

function M.first_part_id(room)
  local parts = room and room.footprint and room.footprint.parts
  return parts and parts[1] and parts[1].id or "part-main"
end

function M.part_choices(context, draft)
  local result = {}
  local room = M.owner(draft, context)
  for _, part in ipairs(room and room.footprint and room.footprint.parts or {}) do
    result[#result + 1] = {
      value = part.id,
      label = string.format("%s (%d x %d mm)", part.id, part.size_mm[1], part.size_mm[2]),
      raw = part,
    }
  end
  return result
end

function M.part_room(room, part_id)
  if not room then return nil end
  if not room.footprint then return room end
  local part = M.selected_part(room, part_id)
  if not part then return nil end
  return {
    origin_mm = {
      room.origin_mm[1] + part.origin_mm[1],
      room.origin_mm[2] + part.origin_mm[2],
    },
    size_mm = { part.size_mm[1], part.size_mm[2] },
  }
end

local function rectangles(room)
  if not room or not room.footprint then return room and { room } or {} end
  local result = {}
  for _, part in ipairs(room.footprint.parts or {}) do
    result[#result + 1] = M.part_room(room, part.id)
  end
  return result
end

function M.edge_length(draft, context)
  return wall_geometry.edge_length(M.owner(draft, context), draft.side, draft.part_id)
end

---Resolve a canonical wall offset. `width_mm` is zero for point fixtures and
---positive for openings, whose cursor/centre represents the opening centre.
function M.resolve_offset(draft, context, width_mm)
  local length = M.edge_length(draft, context)
  if not length or type(width_mm) ~= "number" then
    return nil, { code = "WALL_REQUIRED", message = "choose an owner room, footprint part, and wall" }
  end
  if draft.placement == "exact" then
    if type(draft.offset_mm) ~= "number" then
      return nil, { code = "WALL_OFFSET", message = "enter an exact wall offset" }
    end
    return draft.offset_mm
  end
  if draft.placement == "cursor" then
    local room = M.part_room(M.owner(draft, context), draft.part_id)
    local cursor = common.cursor(context)
    if not cursor then
      return nil, { code = "CURSOR_UNAVAILABLE", message = "the canvas cursor position is unavailable" }
    end
    if not room then return nil, { code = "WALL_REQUIRED", message = "choose an owner wall" } end
    local coordinate = (draft.side == "north" or draft.side == "south")
        and (cursor[1] - room.origin_mm[1])
      or (cursor[2] - room.origin_mm[2])
    return util.round(coordinate - width_mm / 2)
  end
  return util.round((length - width_mm) / 2)
end

function M.bounds_error(draft, context, width_mm, point_attachment)
  local offset = M.resolve_offset(draft, context, width_mm)
  local length = M.edge_length(draft, context)
  if offset == nil or length == nil then return nil end
  local outside = point_attachment and (offset <= 0 or offset >= length)
    or not point_attachment and (offset < 0 or offset + width_mm > length)
  if outside then
    return string.format("placement must fit within the %d mm wall", length)
  end
end

function M.exterior_error(draft, context, width_mm)
  local owner = M.owner(draft, context)
  local offset = M.resolve_offset(draft, context, width_mm)
  if not owner or offset == nil then return nil end
  local attachment = {
    id = "wall-form-preview",
    room_id = owner.id,
    part_id = draft.part_id,
    side = draft.side,
    offset_mm = offset,
  }
  local geometry
  if width_mm > 0 then
    attachment.width_mm = width_mm
    geometry = wall_geometry.aperture(owner, attachment)
  else
    geometry = wall_geometry.marker(owner, attachment)
  end
  if geometry and geometry.within_edge and not geometry.on_exterior then
    return "placement lies on an internal footprint seam"
  end
end

function M.connection_choices(context, draft)
  local result = { { value = "outside", label = "Outside" } }
  local owner = M.owner(draft, context)
  local owner_part = M.part_room(owner, draft.part_id)
  if not owner_part then return result end
  local plan = common.model(context)
  for _, other in ipairs(plan and plan.rooms or {}) do
    if other.id ~= owner.id then
      for _, rectangle in ipairs(rectangles(other)) do
        local shared = adjacency.between(owner_part, rectangle)
        if shared and shared.a_side == draft.side then
          result[#result + 1] = {
            value = other.id,
            label = string.format("%s (%s)", other.name or other.id, other.id),
            raw = other,
          }
          break
        end
      end
    end
  end
  return result
end

function M.connection_available(draft, context, width_mm)
  if draft.connects_to_room_id == "outside" then return true end
  local owner = M.owner(draft, context)
  local connected = common.find(context, "room", draft.connects_to_room_id)
  local offset = M.resolve_offset(draft, context, width_mm)
  if not owner or not connected or offset == nil then return false end
  return wall_geometry.connection(owner, connected, {
    id = "window-form-preview",
    room_id = owner.id,
    part_id = draft.part_id,
    side = draft.side,
    offset_mm = offset,
    width_mm = width_mm,
  }) ~= nil
end

return M
