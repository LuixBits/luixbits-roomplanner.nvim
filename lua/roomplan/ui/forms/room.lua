local alignment = require("roomplan.geometry.alignment")
local config = require("roomplan.config")
local model_helpers = require("roomplan.model")
local common = require("roomplan.ui.forms.common")

local M = {}

local RELATIVE = { north = "place_north", east = "place_east", south = "place_south", west = "place_west" }

local function proposal(draft, context)
  local room = {
    origin_mm = { 0, 0 },
    size_mm = { draft.width_mm, draft.depth_mm },
  }
  if type(draft.width_mm) ~= "number" or type(draft.depth_mm) ~= "number" then
    return nil, { code = "ROOM_FORM_DIMENSIONS", message = "enter valid room dimensions" }
  end
  if draft.placement == "origin" then
    return { origin_mm = { 0, 0 }, description = "World origin" }
  elseif draft.placement == "cursor" then
    local cursor = common.cursor(context)
    if not cursor then return nil, { code = "CURSOR_UNAVAILABLE", message = "the canvas cursor position is unavailable" } end
    return { origin_mm = cursor, description = "Canvas cursor" }
  elseif RELATIVE[draft.placement] then
    local reference = common.find(context, "room", draft.reference_room_id)
    if not reference then return nil, { code = "ROOM_REFERENCE", message = "choose a reference room" } end
    local result, err = alignment.propose(room, reference, RELATIVE[draft.placement], { gap_mm = draft.gap_mm or 0 })
    if not result then return nil, err end
    result.description = string.format("%s of %s", draft.placement, reference.name or reference.id)
    return result
  end
  local plan = common.model(context)
  local result, err = alignment.auto_place(room.size_mm, plan and plan.rooms or {}, {
    cursor_mm = common.cursor(context),
    grid_mm = plan and plan.settings and plan.settings.grid_mm or 100,
    max_distance_mm = context.max_auto_place_distance_mm,
  })
  if not result then return nil, err end
  result.description = result.reference_id and ("Automatic beside " .. result.reference_id) or "Automatic placement"
  return result
end

function M.add(session, opts)
  opts = opts or {}
  local runtime = config.get()
  local context = {
    session = session,
    cursor_mm = opts.cursor_mm,
    max_auto_place_distance_mm = runtime.limits.max_auto_place_distance_mm,
  }
  local rooms = common.model(context) and common.model(context).rooms or {}
  local placement_choices = {
    { value = "automatic", label = "Automatic non-overlapping" },
    { value = "origin", label = "World origin" },
    { value = "cursor", label = "Canvas cursor" },
  }
  if #rooms > 0 then
    placement_choices[#placement_choices + 1] = { value = "north", label = "North of a room" }
    placement_choices[#placement_choices + 1] = { value = "east", label = "East of a room" }
    placement_choices[#placement_choices + 1] = { value = "south", label = "South of a room" }
    placement_choices[#placement_choices + 1] = { value = "west", label = "West of a room" }
  end
  local spec = {
    id = "add-room",
    title = "Add room",
    mode = "ROOM CREATE",
    description = "Exact stored geometry uses integer millimetres.",
    apply_label = "Create room",
    context = context,
    initial = {
      name = opts.name or "Room",
      width_mm = opts.width_mm or 4000,
      depth_mm = opts.depth_mm or 3000,
      placement = opts.placement or "automatic",
      reference_room_id = opts.reference_room_id or common.selected_room(context),
      gap_mm = opts.gap_mm or 0,
      force = opts.force == true,
    },
    fields = {
      { key = "name", label = "Name", type = "text", required = true, trim = true, max_length = 256 },
      { key = "width_mm", label = "Width", type = "measurement", required = true, max = runtime.limits.max_dimension_mm },
      { key = "depth_mm", label = "Depth", type = "measurement", required = true, max = runtime.limits.max_dimension_mm },
      { key = "placement", label = "Placement", type = "enum", required = true, choices = placement_choices },
      {
        key = "reference_room_id", label = "Reference room", type = "object_ref", required = true,
        choices = function(ctx) return common.rooms(ctx) end,
        visible = function(_, draft) return RELATIVE[draft.placement] ~= nil end,
      },
      {
        key = "gap_mm", label = "Gap", type = "measurement", allow_zero = true, default = 0,
        visible = function(_, draft) return RELATIVE[draft.placement] ~= nil end,
      },
      { key = "force", label = "Allow invalid draft", type = "toggle", default = false },
      {
        key = "resolved_origin", label = "Resolved origin", type = "readonly",
        value = function(ctx, draft)
          local result = proposal(draft, ctx)
          return result and result.origin_mm or nil
        end,
        format = function(value) return common.point_text(value) end,
      },
    },
    preview = function(draft, ctx)
      local result, err = proposal(draft, ctx)
      if not result then return nil, err end
      return {
        lines = {
          (result.description or "Placement") .. " at " .. common.point_text(result.origin_mm),
          string.format("Footprint: %d x %d mm", draft.width_mm, draft.depth_mm),
        },
      }
    end,
  }
  function spec.build(draft, ctx)
    local result, err = proposal(draft, ctx or context)
    if not result then return nil, err end
    local id, id_err = common.generate_id(ctx or context, "room", draft.name)
    if not id then return nil, id_err end
    return {
      type = "add_room",
      room = model_helpers.new_room({
        id = id,
        name = draft.name,
        origin_mm = result.origin_mm,
        size_mm = { draft.width_mm, draft.depth_mm },
      }),
      force = draft.force == true,
    }
  end
  return spec
end

function M.edit(session, room, opts)
  opts = opts or {}
  if type(room) == "string" then room = model_helpers.find(session:model(), "room", room) end
  assert(type(room) == "table" and type(room.id) == "string", "room.edit requires a room")
  local runtime = config.get()
  local context = { session = session, room_id = room.id }
  local spec = {
    id = "edit-room",
    title = "Edit room",
    mode = "ROOM EDIT",
    description = "All room properties are applied as one undoable edit.",
    apply_label = "Apply room changes",
    context = context,
    initial = {
      name = room.name,
      origin_x_mm = room.origin_mm[1],
      origin_y_mm = room.origin_mm[2],
      width_mm = room.size_mm[1],
      depth_mm = room.size_mm[2],
      force = opts.force == true,
    },
    fields = {
      { key = "name", label = "Name", type = "text", required = true, trim = true, max_length = 256 },
      { key = "origin_x_mm", label = "World X", type = "measurement", allow_negative = true, allow_zero = true },
      { key = "origin_y_mm", label = "World Y", type = "measurement", allow_negative = true, allow_zero = true },
      { key = "width_mm", label = "Width", type = "measurement", max = runtime.limits.max_dimension_mm },
      { key = "depth_mm", label = "Depth", type = "measurement", max = runtime.limits.max_dimension_mm },
      { key = "force", label = "Allow invalid draft", type = "toggle", default = false },
      {
        key = "summary", label = "Result", type = "readonly",
        value = function(_, draft)
          return string.format("%s at (%d, %d), %d x %d mm", draft.name, draft.origin_x_mm,
            draft.origin_y_mm, draft.width_mm, draft.depth_mm)
        end,
      },
    },
    validate = function(_, ctx)
      return common.find(ctx, "room", ctx.room_id) and {} or { _form = "the room no longer exists" }
    end,
    preview = function(draft)
      return {
        lines = {
          string.format("Origin %s; footprint %d x %d mm", common.point_text({ draft.origin_x_mm, draft.origin_y_mm }),
            draft.width_mm, draft.depth_mm),
        },
      }
    end,
  }
  function spec.build(draft, ctx)
    ctx = ctx or context
    if not common.find(ctx, "room", ctx.room_id) then
      return nil, { code = "NOT_FOUND", message = "the room no longer exists" }
    end
    return {
      type = "edit_room",
      id = ctx.room_id,
      patch = {
        name = draft.name,
        origin_mm = { draft.origin_x_mm, draft.origin_y_mm },
        size_mm = { draft.width_mm, draft.depth_mm },
      },
      force = draft.force == true,
    }
  end
  return spec
end

M.new = M.add
M.proposal = proposal

return M
