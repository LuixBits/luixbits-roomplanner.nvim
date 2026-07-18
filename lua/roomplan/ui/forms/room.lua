local alignment = require("roomplan.geometry.alignment")
local color = require("roomplan.color")
local config = require("roomplan.config")
local model_helpers = require("roomplan.model")
local room_footprints = require("roomplan.model.room_footprints")
local common = require("roomplan.ui.forms.common")
local room_sections = require("roomplan.ui.forms.room_sections")

local M = {}

local RELATIVE = { north = "place_north", east = "place_east", south = "place_south", west = "place_west" }

local function schema_version(context)
  local plan = common.model(context)
  return plan and plan.schema_version or 1
end

local function editable_preset(room, version)
  if version < 2 then
    return { shape = "rectangle", width_mm = room.size_mm[1], depth_mm = room.size_mm[2] }
  end
  return room_footprints.classify(room.footprint)
end

local function dependency_summary(context, room_id)
  local plan = common.model(context) or {}
  local door_count, furniture_count = 0, 0
  for _, door in ipairs(plan.doors or {}) do
    if door.room_id == room_id or door.connects_to_room_id == room_id then door_count = door_count + 1 end
  end
  for _, furniture in ipairs(plan.furniture or {}) do
    if furniture.room_id == room_id then furniture_count = furniture_count + 1 end
  end
  return string.format("%d door%s · %d furniture", door_count, door_count == 1 and "" or "s", furniture_count)
end

local function width_field(runtime)
  return {
    key = "width_mm", label = "Overall width", type = "measurement", required = true,
    max = runtime.limits.max_dimension_mm,
  }
end

local function depth_field(runtime)
  return {
    key = "depth_mm", label = "Overall depth", type = "measurement", required = true,
    max = runtime.limits.max_dimension_mm,
  }
end

local function leg_width_field(runtime)
  return {
    key = "leg_width_mm", label = "Vertical leg width", type = "measurement", required = true,
    max = runtime.limits.max_dimension_mm,
    visible = function(_, draft) return draft.shape == "l_shape" end,
    validate = function(value, _, draft)
      if type(value) == "number" and type(draft.width_mm) == "number" and value >= draft.width_mm then
        return "must be smaller than the overall width"
      end
    end,
  }
end

local function leg_depth_field(runtime)
  return {
    key = "leg_depth_mm", label = "Horizontal leg depth", type = "measurement", required = true,
    max = runtime.limits.max_dimension_mm,
    visible = function(_, draft) return draft.shape == "l_shape" end,
    validate = function(value, _, draft)
      if type(value) == "number" and type(draft.depth_mm) == "number" and value >= draft.depth_mm then
        return "must be smaller than the overall depth"
      end
    end,
  }
end

local function missing_corner_field()
  return {
    key = "missing_corner", label = "Missing corner", type = "enum", required = true,
    visible = function(_, draft) return draft.shape == "l_shape" end,
    choices = {
      { value = "northeast", label = "North-east" },
      { value = "northwest", label = "North-west" },
      { value = "southeast", label = "South-east" },
      { value = "southwest", label = "South-west" },
    },
  }
end

local function draft_room(draft, context)
  if type(draft.width_mm) ~= "number" or type(draft.depth_mm) ~= "number" then
    return nil, { code = "ROOM_FORM_DIMENSIONS", message = "enter valid room dimensions" }
  end
  local room = { origin_mm = { 0, 0 } }
  if schema_version(context) >= 2 then
    local footprint, err = room_footprints.build(draft)
    if not footprint then return nil, err end
    room.footprint = footprint
  else
    if draft.shape ~= nil and draft.shape ~= "rectangle" then
      return nil, { code = "ROOM_FORM_SHAPE", field = "shape", message = "compound rooms require schema v2 or newer" }
    end
    room.size_mm = { draft.width_mm, draft.depth_mm }
  end
  return room
end

local function placement(result, room)
  if result then result.footprint = room.footprint end
  return result
end

local function proposal(draft, context)
  local room, room_error = draft_room(draft, context)
  if not room then return nil, room_error end
  if draft.placement == "origin" then
    return placement({ origin_mm = { 0, 0 }, description = "World origin" }, room)
  elseif draft.placement == "cursor" then
    local cursor = common.cursor(context)
    if not cursor then return nil, { code = "CURSOR_UNAVAILABLE", message = "the canvas cursor position is unavailable" } end
    return placement({ origin_mm = cursor, description = "Canvas cursor" }, room)
  elseif RELATIVE[draft.placement] then
    local reference = common.find(context, "room", draft.reference_room_id)
    if not reference then return nil, { code = "ROOM_REFERENCE", message = "choose a reference room" } end
    local result, err = alignment.propose(room, reference, RELATIVE[draft.placement], { gap_mm = draft.gap_mm or 0 })
    if not result then return nil, err end
    result.description = string.format("%s of %s", draft.placement, reference.name or reference.id)
    return placement(result, room)
  end
  local plan = common.model(context)
  local result, err = alignment.auto_place(room, plan and plan.rooms or {}, {
    cursor_mm = common.cursor(context),
    grid_mm = plan and plan.settings and plan.settings.grid_mm or 100,
    max_distance_mm = context.max_auto_place_distance_mm,
  })
  if not result then return nil, err end
  result.description = result.reference_id and ("Automatic beside " .. result.reference_id) or "Automatic placement"
  return placement(result, room)
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
    description = "Create a rectangular or L-shaped room using exact integer millimetres.",
    apply_label = "Create room",
    context = context,
    initial = {
      name = opts.name or "Room",
      color = opts.color or "auto",
      shape = opts.shape or "rectangle",
      width_mm = opts.width_mm or 4000,
      depth_mm = opts.depth_mm or 3000,
      leg_width_mm = opts.leg_width_mm or 1500,
      leg_depth_mm = opts.leg_depth_mm or 1200,
      missing_corner = opts.missing_corner or "northeast",
      placement = opts.placement or "automatic",
      reference_room_id = opts.reference_room_id or common.selected_room(context),
      gap_mm = opts.gap_mm or 0,
      force = opts.force == true,
    },
    fields = {
      { key = "name", label = "Name", type = "text", required = true, trim = true, max_length = 256 },
      {
        key = "color", label = "Color", type = "enum", required = true, kind = "roomplan_color",
        choices = function(_, draft) return color.choices(draft.color) end,
      },
      {
        key = "shape", label = "Shape", type = "enum", required = true,
        choices = function(ctx)
          local choices = { { value = "rectangle", label = "Rectangle" } }
          if schema_version(ctx) >= 2 then choices[#choices + 1] = { value = "l_shape", label = "L-shaped" } end
          return choices
        end,
      },
      width_field(runtime),
      depth_field(runtime),
      leg_width_field(runtime),
      leg_depth_field(runtime),
      missing_corner_field(),
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
    validate = function(draft, ctx)
      local _, err = draft_room(draft, ctx)
      if not err then return {} end
      return { [err.field or "_form"] = err.message or err.code }
    end,
    preview = function(draft, ctx)
      local result, err = proposal(draft, ctx)
      if not result then return nil, err end
      local geometry = draft.shape == "l_shape"
          and string.format("L-shaped: %d x %d mm overall; legs %d x %d mm",
            draft.width_mm, draft.depth_mm, draft.leg_width_mm, draft.leg_depth_mm)
        or string.format("Footprint: %d x %d mm", draft.width_mm, draft.depth_mm)
      return {
        lines = {
          (result.description or "Placement") .. " at " .. common.point_text(result.origin_mm),
          geometry,
        },
      }
    end,
  }
  function spec.build(draft, ctx)
    local result, err = proposal(draft, ctx or context)
    if not result then return nil, err end
    local id, id_err = common.generate_id(ctx or context, "room", draft.name)
    if not id then return nil, id_err end
    local version = schema_version(ctx or context)
    local fields = {
      id = id,
      name = draft.name,
      origin_mm = result.origin_mm,
      color = color.resolve(draft.color),
    }
    if version >= 2 then fields.footprint = result.footprint
    else fields.size_mm = { draft.width_mm, draft.depth_mm } end
    return {
      type = "add_room",
      room = model_helpers.new_room(fields, { schema_version = version }),
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
  local version = schema_version(context)
  local preset = editable_preset(room, version)
  local can_edit_geometry = preset ~= nil
  local shape_label = preset and (preset.shape == "l_shape" and "L-shaped" or "Rectangle") or "Compound"
  local section_initial = not preset and room_sections.initial(room) or {}
  local function resolve_footprint(draft)
    if can_edit_geometry then return room_footprints.build(draft) end
    return room_sections.footprint(draft)
  end
  local spec = {
    id = "edit-room",
    title = "Edit room",
    mode = "ROOM EDIT",
    description = can_edit_geometry and "Edit the room as one undoable change."
      or "Resize rectangular sections while their positions remain fixed.",
    apply_label = "Apply room changes",
    preview_layout = "side",
    preview_title = "Room preview",
    context = context,
    initial = {
      name = room.name,
      color = room.color or "auto",
      origin_x_mm = room.origin_mm[1],
      origin_y_mm = room.origin_mm[2],
      shape = preset and preset.shape or nil,
      width_mm = preset and preset.width_mm or nil,
      depth_mm = preset and preset.depth_mm or nil,
      leg_width_mm = preset and preset.leg_width_mm or nil,
      leg_depth_mm = preset and preset.leg_depth_mm or nil,
      missing_corner = preset and preset.missing_corner or nil,
      footprint = section_initial.footprint,
      section_id = section_initial.section_id,
      section_width_mm = section_initial.section_width_mm,
      section_depth_mm = section_initial.section_depth_mm,
      force = opts.force == true,
    },
    fields = {
      { key = "name", label = "Name", type = "text", required = true, trim = true, max_length = 256 },
      {
        key = "color", label = "Color", type = "enum", required = true, kind = "roomplan_color",
        choices = function(_, draft) return color.choices(draft.color) end,
      },
      { key = "origin_x_mm", label = "World X", type = "measurement", allow_negative = true, allow_zero = true },
      { key = "origin_y_mm", label = "World Y", type = "measurement", allow_negative = true, allow_zero = true },
    },
    validate = function(draft, ctx)
      if not common.find(ctx, "room", ctx.room_id) then return { _form = "the room no longer exists" } end
      if can_edit_geometry and version >= 2 then
        local _, err = room_footprints.build(draft)
        if err then return { [err.field or "_form"] = err.message or err.code } end
      elseif not can_edit_geometry then
        local err = room_sections.validate(draft)
        if err then return { _form = err } end
      end
      return {}
    end,
  }
  if can_edit_geometry then
    spec.fields[#spec.fields + 1] = {
      key = "shape", label = "Shape", type = "readonly", value = function() return shape_label end,
    }
    spec.fields[#spec.fields + 1] = width_field(runtime)
    spec.fields[#spec.fields + 1] = depth_field(runtime)
    if preset.shape == "l_shape" then
      spec.fields[#spec.fields + 1] = leg_width_field(runtime)
      spec.fields[#spec.fields + 1] = leg_depth_field(runtime)
      spec.fields[#spec.fields + 1] = missing_corner_field()
    end
  else
    for _, field in ipairs(room_sections.fields(runtime, room)) do spec.fields[#spec.fields + 1] = field end
    spec.on_change = room_sections.on_change
  end
  spec.fields[#spec.fields + 1] = {
    key = "edit_footprint",
    label = "Edit footprint",
    type = "action",
    action = "edit_shape",
    action_label = "Edit sections",
    value = "Edit sections on canvas…",
  }
  spec.fields[#spec.fields + 1] = {
    key = "attached", label = "Attached", type = "readonly",
    value = function(ctx) return dependency_summary(ctx, room.id) end,
  }
  spec.fields[#spec.fields + 1] = { key = "force", label = "Allow invalid draft", type = "toggle", default = false }
  spec.preview = require("roomplan.ui.forms.room_preview").edit(resolve_footprint)
  function spec.build(draft, ctx)
    ctx = ctx or context
    local current = common.find(ctx, "room", ctx.room_id)
    if not current then
      return nil, { code = "NOT_FOUND", message = "the room no longer exists" }
    end
    local patch = {
      name = draft.name,
      origin_mm = { draft.origin_x_mm, draft.origin_y_mm },
    }
    if can_edit_geometry then
      if version >= 2 then
        local footprint, footprint_error = room_footprints.build(draft)
        if not footprint then return nil, footprint_error end
        patch.footprint = footprint
      else
        patch.size_mm = { draft.width_mm, draft.depth_mm }
      end
    else
      patch.footprint = room_sections.footprint(draft)
    end
    if current.color ~= nil or draft.color ~= "auto" then patch.color = draft.color end
    return {
      type = "edit_room",
      id = ctx.room_id,
      patch = patch,
      force = draft.force == true,
    }
  end
  return spec
end
M.new = M.add
M.proposal = proposal

return M
