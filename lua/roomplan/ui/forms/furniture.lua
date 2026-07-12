local catalog = require("roomplan.catalog")
local config = require("roomplan.config")
local model_helpers = require("roomplan.model")
local common = require("roomplan.ui.forms.common")

local M = {}

local function templates(context)
  local result = {}
  for _, template in ipairs(catalog.all()) do
    result[#result + 1] = {
      value = template.id,
      label = string.format("%s (%d x %d x %d mm)", template.name, unpack(template.default_size_mm)),
      raw = template,
    }
  end
  local plan = common.model(context)
  for _, template in ipairs(plan and plan.custom_templates or {}) do
    result[#result + 1] = {
      value = template.id,
      label = string.format("%s (%d x %d x %d mm)", template.name, unpack(template.default_size_mm)),
      raw = template,
    }
  end
  return result
end

local function resolved_template(context, id)
  return catalog.resolve(common.model(context), id)
end

local function centre(draft, context)
  local room = common.find(context, "room", draft.room_id)
  if not room then return nil, { code = "ROOM_REQUIRED", message = "add or choose a room first" } end
  if draft.placement == "exact" then
    if type(draft.local_x_mm) ~= "number" or type(draft.local_y_mm) ~= "number" then
      return nil, { code = "FURNITURE_POSITION", message = "enter exact room-local coordinates" }
    end
    return { draft.local_x_mm, draft.local_y_mm }
  elseif draft.placement == "cursor" then
    local cursor = common.cursor(context)
    if not cursor then return nil, { code = "CURSOR_UNAVAILABLE", message = "the canvas cursor position is unavailable" } end
    return { cursor[1] - room.origin_mm[1], cursor[2] - room.origin_mm[2] }
  end
  return { math.floor(room.size_mm[1] / 2 + 0.5), math.floor(room.size_mm[2] / 2 + 0.5) }
end

function M.add(session, opts)
  opts = opts or {}
  local runtime = config.get()
  local context = { session = session, cursor_mm = opts.cursor_mm }
  local template_id = opts.template_id or "builtin:sofa"
  local template = resolved_template(context, template_id) or catalog.get("builtin:custom-rectangle")
  local room_id = opts.room_id or common.selected_room(context)
  local room = room_id and common.find(context, "room", room_id) or nil
  local spec = {
    id = "add-furniture",
    title = "Add furniture",
    mode = "FURNITURE CREATE",
    description = "Template dimensions are editable before placement.",
    apply_label = "Place furniture",
    context = context,
    initial = {
      room_id = room_id,
      template_id = template.id,
      name = opts.name or template.name,
      category = template.category,
      width_mm = opts.width_mm or template.default_size_mm[1],
      depth_mm = opts.depth_mm or template.default_size_mm[2],
      height_mm = opts.height_mm or template.default_size_mm[3],
      placement = opts.placement or "centre",
      local_x_mm = opts.local_x_mm or (room and math.floor(room.size_mm[1] / 2 + 0.5) or 0),
      local_y_mm = opts.local_y_mm or (room and math.floor(room.size_mm[2] / 2 + 0.5) or 0),
      rotation_deg = opts.rotation_deg or 0,
      save_template = opts.save_template == true,
      custom_template_name = opts.custom_template_name or (opts.name or template.name),
      custom_template_category = opts.custom_template_category or template.category,
    },
    fields = {
      { key = "room_id", label = "Room", type = "object_ref", required = true, choices = function(ctx) return common.rooms(ctx) end },
      {
        key = "template_id", label = "Template", type = "object_ref", required = true,
        choices = templates,
        on_change = function(value, _, ctx)
          local selected = resolved_template(ctx, value)
          if not selected then return nil end
          return {
            name = selected.name,
            category = selected.category,
            width_mm = selected.default_size_mm[1],
            depth_mm = selected.default_size_mm[2],
            height_mm = selected.default_size_mm[3],
          }
        end,
      },
      { key = "name", label = "Label", type = "text", required = true, trim = true, max_length = 256 },
      {
        key = "category", label = "Category", type = "readonly",
        value = function(_, draft) return draft.category end,
      },
      { key = "width_mm", label = "Width", type = "measurement", required = true, max = runtime.limits.max_dimension_mm },
      { key = "depth_mm", label = "Depth", type = "measurement", required = true, max = runtime.limits.max_dimension_mm },
      { key = "height_mm", label = "Height", type = "measurement", required = true, max = runtime.limits.max_dimension_mm },
      {
        key = "rotation_deg", label = "Rotation", type = "enum", required = true,
        choices = {
          { value = 0, label = "0 degrees" }, { value = 90, label = "90 degrees" },
          { value = 180, label = "180 degrees" }, { value = 270, label = "270 degrees" },
        },
      },
      {
        key = "placement", label = "Placement", type = "enum", required = true,
        choices = {
          { value = "centre", label = "Room centre" },
          { value = "cursor", label = "Canvas cursor" },
          { value = "exact", label = "Exact room-local coordinates" },
        },
      },
      {
        key = "local_x_mm", label = "Room-local X", type = "measurement", allow_negative = true, allow_zero = true,
        visible = function(_, draft) return draft.placement == "exact" end,
      },
      {
        key = "local_y_mm", label = "Room-local Y", type = "measurement", allow_negative = true, allow_zero = true,
        visible = function(_, draft) return draft.placement == "exact" end,
      },
      {
        key = "resolved_centre", label = "Resolved centre", type = "readonly",
        value = function(ctx, draft) return centre(draft, ctx) end,
        format = function(value) return common.point_text(value) end,
      },
      { key = "save_template", label = "Save as project template", type = "toggle", default = false },
      {
        key = "custom_template_name", label = "Template name", type = "text", required = true, trim = true,
        visible = function(_, draft) return draft.save_template == true end,
      },
      {
        key = "custom_template_category", label = "Template category", type = "text", required = true, trim = true,
        visible = function(_, draft) return draft.save_template == true end,
      },
    },
    preview = function(draft, ctx)
      local position, err = centre(draft, ctx)
      if not position then return nil, err end
      local selected_room = common.find(ctx, "room", draft.room_id)
      return {
        lines = {
          string.format("%s in %s at %s", draft.name, selected_room.name or selected_room.id, common.point_text(position)),
          string.format("Footprint: %d x %d mm; height %d mm; rotation %d degrees",
            draft.width_mm, draft.depth_mm, draft.height_mm, draft.rotation_deg),
        },
      }
    end,
  }
  function spec.validate(draft, ctx)
    local errors = {}
    if not resolved_template(ctx, draft.template_id) then errors.template_id = "template no longer exists" end
    if not common.find(ctx, "room", draft.room_id) then errors.room_id = "room no longer exists" end
    return errors
  end
  function spec.build(draft, ctx)
    ctx = ctx or context
    local position, err = centre(draft, ctx)
    if not position then return nil, err end
    local selected = resolved_template(ctx, draft.template_id)
    if not selected then return nil, { code = "TEMPLATE_REQUIRED", message = "the furniture template no longer exists" } end
    local id, id_err = common.generate_id(ctx, "furniture", draft.name)
    if not id then return nil, id_err end
    local template_id = draft.template_id
    local category = selected.category
    local custom_template
    if draft.save_template then
      local custom_id, custom_err = common.generate_id(ctx, "custom_template", draft.custom_template_name)
      if not custom_id then return nil, custom_err end
      template_id = custom_id
      category = draft.custom_template_category
      custom_template = model_helpers.new_custom_template({
        id = custom_id,
        name = draft.custom_template_name,
        category = draft.custom_template_category,
        shape = "rectangle",
        default_size_mm = { draft.width_mm, draft.depth_mm, draft.height_mm },
      })
    end
    return {
      type = "add_furniture",
      furniture = model_helpers.new_furniture({
        id = id,
        room_id = draft.room_id,
        template_id = template_id,
        name = draft.name,
        category = category,
        center_mm = position,
        size_mm = { draft.width_mm, draft.depth_mm, draft.height_mm },
        rotation_deg = draft.rotation_deg,
      }),
      custom_template = custom_template,
    }
  end
  return spec
end

function M.edit(session, furniture, opts)
  opts = opts or {}
  if type(furniture) == "string" then furniture = model_helpers.find(session:model(), "furniture", furniture) end
  assert(type(furniture) == "table" and type(furniture.id) == "string", "furniture.edit requires furniture")
  local runtime = config.get()
  local context = { session = session, furniture_id = furniture.id }
  local template = resolved_template(context, furniture.template_id)
  local spec = {
    id = "edit-furniture",
    title = "Edit furniture",
    mode = "FURNITURE EDIT",
    description = "Position, footprint, template and rotation apply as one edit.",
    apply_label = "Apply furniture changes",
    context = context,
    initial = {
      room_id = furniture.room_id,
      template_id = furniture.template_id,
      name = furniture.name,
      category = furniture.category or (template and template.category) or "custom",
      width_mm = furniture.size_mm[1],
      depth_mm = furniture.size_mm[2],
      height_mm = furniture.size_mm[3],
      local_x_mm = furniture.center_mm[1],
      local_y_mm = furniture.center_mm[2],
      rotation_deg = furniture.rotation_deg,
    },
    fields = {
      { key = "room_id", label = "Room", type = "object_ref", required = true, choices = function(ctx) return common.rooms(ctx) end },
      {
        key = "template_id", label = "Template", type = "object_ref", required = true, choices = templates,
        on_change = function(value, _, ctx)
          local selected = resolved_template(ctx, value)
          -- Editing a template association deliberately preserves explicit
          -- dimensions and the user's label.
          return selected and { category = selected.category } or nil
        end,
      },
      { key = "name", label = "Label", type = "text", required = true, trim = true, max_length = 256 },
      { key = "category", label = "Category", type = "readonly", value = function(_, draft) return draft.category end },
      { key = "width_mm", label = "Width", type = "measurement", max = runtime.limits.max_dimension_mm },
      { key = "depth_mm", label = "Depth", type = "measurement", max = runtime.limits.max_dimension_mm },
      { key = "height_mm", label = "Height", type = "measurement", max = runtime.limits.max_dimension_mm },
      { key = "local_x_mm", label = "Room-local X", type = "measurement", allow_negative = true, allow_zero = true },
      { key = "local_y_mm", label = "Room-local Y", type = "measurement", allow_negative = true, allow_zero = true },
      {
        key = "rotation_deg", label = "Rotation", type = "enum", required = true,
        choices = {
          { value = 0, label = "0 degrees" }, { value = 90, label = "90 degrees" },
          { value = 180, label = "180 degrees" }, { value = 270, label = "270 degrees" },
        },
      },
      {
        key = "summary", label = "Result", type = "readonly",
        value = function(_, draft)
          return string.format("%s at (%d, %d), %d x %d x %d mm", draft.name, draft.local_x_mm,
            draft.local_y_mm, draft.width_mm, draft.depth_mm, draft.height_mm)
        end,
      },
    },
    validate = function(draft, ctx)
      local errors = {}
      if not common.find(ctx, "furniture", ctx.furniture_id) then errors._form = "the furniture no longer exists" end
      if not common.find(ctx, "room", draft.room_id) then errors.room_id = "room no longer exists" end
      if not resolved_template(ctx, draft.template_id) then errors.template_id = "template no longer exists" end
      return errors
    end,
    preview = function(draft, ctx)
      local room = common.find(ctx, "room", draft.room_id)
      if not room then return nil, { code = "ROOM_REQUIRED", message = "choose a room" } end
      return {
        lines = {
          string.format("%s in %s at %s", draft.name, room.name or room.id,
            common.point_text({ draft.local_x_mm, draft.local_y_mm })),
          string.format("%d x %d x %d mm; rotation %d degrees",
            draft.width_mm, draft.depth_mm, draft.height_mm, draft.rotation_deg),
        },
      }
    end,
  }
  function spec.build(draft, ctx)
    ctx = ctx or context
    if not common.find(ctx, "furniture", ctx.furniture_id) then
      return nil, { code = "NOT_FOUND", message = "the furniture no longer exists" }
    end
    local selected = resolved_template(ctx, draft.template_id)
    if not selected then return nil, { code = "TEMPLATE_REQUIRED", message = "template no longer exists" } end
    return {
      type = "edit_furniture",
      id = ctx.furniture_id,
      patch = {
        room_id = draft.room_id,
        template_id = draft.template_id,
        name = draft.name,
        category = selected.category,
        center_mm = { draft.local_x_mm, draft.local_y_mm },
        size_mm = { draft.width_mm, draft.depth_mm, draft.height_mm },
        rotation_deg = draft.rotation_deg,
      },
    }
  end
  return spec
end

M.new = M.add
M.centre = centre

return M
