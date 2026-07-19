local catalog = require("roomplan.catalog")
local color = require("roomplan.color")
local config = require("roomplan.config")
local footprint = require("roomplan.geometry.footprint")
local number = require("roomplan.geometry.number")
local model_helpers = require("roomplan.model")
local common = require("roomplan.ui.forms.common")
local furniture_preview = require("roomplan.ui.forms.furniture_preview")

local M = {}

local function preview_content(entity, summary)
  local graphic, err = furniture_preview.render(entity)
  if not graphic then return nil, err end
  local lines = {}
  for _, line in ipairs(summary or {}) do lines[#lines + 1] = line end
  lines[#lines + 1] = ""
  local first_line = #lines + 1
  for _, line in ipairs(graphic.lines) do lines[#lines + 1] = line end
  return {
    lines = lines,
    graphic = {
      first_line = first_line,
      last_line = #lines,
      highlight_spans = graphic.highlight_spans,
      glyph_mode = graphic.glyph_mode,
    },
    accent = entity.color,
  }
end

local function invalid_preview(state)
  return state and next(state.errors or {}) ~= nil
end

local function schema_version(context)
  local plan = common.model(context)
  return plan and plan.schema_version or 1
end

local function footprint_dimensions(value)
  local shape = value and footprint.from_persisted(value) or nil
  local bounds = shape and footprint.bounds(shape) or nil
  return bounds and { bounds.width, bounds.depth } or nil
end

local function template_dimensions(template)
  if not template then return nil end
  if template.default_size_mm then return template.default_size_mm end
  local size = footprint_dimensions(template.default_footprint)
  return size and { size[1], size[2], template.default_height_mm } or nil
end

local function simple_footprint(value, anchor2)
  local parts = value and value.parts
  local part = parts and #parts == 1 and parts[1] or nil
  if not part or part.id ~= "part-main" or not part.origin_mm or not part.size_mm
    or part.origin_mm[1] ~= 0 or part.origin_mm[2] ~= 0
  then
    return nil
  end
  if anchor2 and (anchor2[1] ~= part.size_mm[1] or anchor2[2] ~= part.size_mm[2]) then return nil end
  return part.size_mm
end

local function template_is_simple(template)
  return template.default_size_mm ~= nil
    or simple_footprint(template.default_footprint, template.default_anchor2_mm) ~= nil
end

local function room_centre(room)
  if room.size_mm then
    return { math.floor(room.size_mm[1] / 2 + 0.5), math.floor(room.size_mm[2] / 2 + 0.5) }
  end
  local shape = footprint.local_from_room(room)
  local anchor = shape and footprint.label_anchor2(shape) or nil
  if not anchor then return nil end
  local x = number.from_doubled(anchor.x2)
  local y = number.from_doubled(anchor.y2)
  return { x, y }
end

local function templates(context)
  local result = {}
  local seen = {}
  local plan = common.model(context)
  for _, template in ipairs(catalog.all(plan)) do
    local size = template_dimensions(template)
    seen[template.id] = true
    result[#result + 1] = {
      value = template.id,
      label = size and string.format("%s (%d x %d x %d mm)", template.name, unpack(size))
        or template.name,
      raw = template,
    }
  end
  -- A hidden built-in remains selectable while editing an existing item that
  -- already references it. Other hidden built-ins stay out of new choices.
  local furniture = context.furniture_id and common.find(context, "furniture", context.furniture_id) or nil
  local current = furniture and not seen[furniture.template_id] and catalog.resolve(plan, furniture.template_id) or nil
  if current then
    local size = template_dimensions(current)
    result[#result + 1] = {
      value = current.id,
      label = size and string.format("%s (%d x %d x %d mm)", current.name, unpack(size))
        or current.name,
      raw = current,
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
  local position = room_centre(room)
  if not position then return nil, { code = "ROOM_GEOMETRY", message = "the room footprint is unavailable" } end
  return position
end

function M.add(session, opts)
  opts = opts or {}
  local runtime = config.get()
  local context = { session = session, cursor_mm = opts.cursor_mm }
  local available = templates(context)
  local template = available[1] and available[1].raw or nil
  if opts.template_id then
    for _, choice in ipairs(available) do
      if choice.value == opts.template_id then template = choice.raw; break end
    end
  end
  assert(template, "RoomPlan furniture catalogue has no visible templates")
  local room_id = opts.room_id or common.selected_room(context)
  local room = room_id and common.find(context, "room", room_id) or nil
  local template_size = assert(template_dimensions(template), "RoomPlan furniture template has no usable dimensions")
  local initial_position = room and room_centre(room) or { 0, 0 }
  local function resolve_draft(draft, ctx)
    ctx = ctx or context
    local position, position_err = centre(draft, ctx)
    if not position then return nil, position_err end
    local selected = resolved_template(ctx, draft.template_id)
    if not selected then
      return nil, { code = "TEMPLATE_REQUIRED", message = "the furniture template no longer exists" }
    end
    local version = schema_version(ctx)
    local selected_simple = template_is_simple(selected)
    return {
      position = position,
      selected = selected,
      version = version,
      footprint = selected_simple and model_helpers.rectangle_footprint({ draft.width_mm, draft.depth_mm })
        or model_helpers.deep_copy(selected.default_footprint),
      anchor2_mm = selected_simple and { draft.width_mm, draft.depth_mm }
        or model_helpers.deep_copy(selected.default_anchor2_mm),
    }
  end
  local function furniture_from_draft(draft, resolved, id, template_id, category)
    local fields = {
      id = id,
      room_id = draft.room_id,
      template_id = template_id or draft.template_id,
      name = draft.name,
      color = color.resolve(draft.color),
      category = category or resolved.selected.category,
      rotation_deg = draft.rotation_deg,
    }
    if resolved.version >= 2 then
      fields.position_mm = resolved.position
      fields.footprint = resolved.footprint
      fields.anchor2_mm = resolved.anchor2_mm
      fields.height_mm = draft.height_mm
    else
      fields.center_mm = resolved.position
      fields.size_mm = { draft.width_mm, draft.depth_mm, draft.height_mm }
    end
    return model_helpers.new_furniture(fields, { schema_version = resolved.version })
  end
  local spec = {
    id = "add-furniture",
    title = "Add furniture",
    mode = "FURNITURE CREATE",
    description = template_is_simple(template) and "Template dimensions are editable before placement."
      or "The compound template footprint is preserved during placement.",
    apply_label = "Place furniture",
    preview_layout = "side",
    preview_title = "Furniture preview",
    preview_width = 34,
    context = context,
    initial = {
      room_id = room_id,
      template_id = template.id,
      name = opts.name or template.name,
      color = opts.color or "auto",
      category = template.category,
      width_mm = opts.width_mm or template_size[1],
      depth_mm = opts.depth_mm or template_size[2],
      height_mm = opts.height_mm or template_size[3],
      placement = opts.placement or "centre",
      local_x_mm = opts.local_x_mm or initial_position[1],
      local_y_mm = opts.local_y_mm or initial_position[2],
      rotation_deg = opts.rotation_deg or 0,
      save_template = opts.save_template == true,
      custom_template_name = opts.custom_template_name or (opts.name or template.name),
      custom_template_category = opts.custom_template_category or template.category,
    },
    fields = {
      { key = "room_id", label = "Room", type = "object_ref", required = true, choices = function(ctx) return common.rooms(ctx) end },
      {
        key = "template_id", label = "Template", type = "object_ref", required = true,
        kind = "roomplan_furniture_template",
        choices = templates,
        on_change = function(value, _, ctx)
          local selected = resolved_template(ctx, value)
          if not selected then return nil end
          local size = template_dimensions(selected)
          return {
            name = selected.name,
            category = selected.category,
            width_mm = size[1],
            depth_mm = size[2],
            height_mm = size[3],
          }
        end,
      },
      { key = "name", label = "Label", type = "text", required = true, trim = true, max_length = 256 },
      {
        key = "color", label = "Color", type = "enum", required = true, kind = "roomplan_color",
        choices = function(_, draft) return color.choices(draft.color) end,
      },
      {
        key = "category", label = "Category", type = "readonly",
        value = function(_, draft) return draft.category end,
      },
      {
        key = "width_mm", label = "Width", type = "measurement", required = true,
        max = runtime.limits.max_dimension_mm,
        visible = function(ctx, draft)
          local selected = resolved_template(ctx, draft.template_id)
          return selected and template_is_simple(selected) or false
        end,
      },
      {
        key = "depth_mm", label = "Depth", type = "measurement", required = true,
        max = runtime.limits.max_dimension_mm,
        visible = function(ctx, draft)
          local selected = resolved_template(ctx, draft.template_id)
          return selected and template_is_simple(selected) or false
        end,
      },
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
    preview = function(draft, ctx, state)
      if invalid_preview(state) then return { lines = { "Correct the highlighted field to update the preview." } } end
      local resolved, err = resolve_draft(draft, ctx)
      if not resolved then return nil, err end
      local selected_room = common.find(ctx, "room", draft.room_id)
      local geometry = template_is_simple(resolved.selected)
          and string.format("Footprint: %d x %d mm", draft.width_mm, draft.depth_mm)
        or string.format("Footprint: %d parts (preserved)",
          #(resolved.selected.default_footprint.parts or {}))
      local entity = furniture_from_draft(draft, resolved, "furniture-preview")
      return preview_content(entity, {
        string.format("%s in %s at %s", draft.name, selected_room.name or selected_room.id,
          common.point_text(resolved.position)),
        string.format("%s; height %d mm; rotation %d degrees", geometry, draft.height_mm, draft.rotation_deg),
      })
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
    local resolved, err = resolve_draft(draft, ctx)
    if not resolved then return nil, err end
    local id, id_err = common.generate_id(ctx, "furniture", draft.name)
    if not id then return nil, id_err end
    local template_id = draft.template_id
    local category = resolved.selected.category
    local custom_template
    if draft.save_template then
      local custom_id, custom_err = common.generate_id(ctx, "custom_template", draft.custom_template_name)
      if not custom_id then return nil, custom_err end
      template_id = custom_id
      category = draft.custom_template_category
      local custom_fields = {
        id = custom_id,
        name = draft.custom_template_name,
        category = draft.custom_template_category,
      }
      if resolved.version >= 2 then
        custom_fields.default_footprint = resolved.footprint
        custom_fields.default_anchor2_mm = resolved.anchor2_mm
        custom_fields.default_height_mm = draft.height_mm
      else
        custom_fields.shape = "rectangle"
        custom_fields.default_size_mm = { draft.width_mm, draft.depth_mm, draft.height_mm }
      end
      custom_template = model_helpers.new_custom_template(custom_fields, { schema_version = resolved.version })
    end
    return {
      type = "add_furniture",
      furniture = furniture_from_draft(draft, resolved, id, template_id, category),
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
  local version = schema_version(context)
  local template = resolved_template(context, furniture.template_id)
  local size
  local can_resize = version < 2
  if version >= 2 then
    local rectangle_size = simple_footprint(furniture.footprint, furniture.anchor2_mm)
    can_resize = rectangle_size ~= nil
    size = rectangle_size and { rectangle_size[1], rectangle_size[2], furniture.height_mm }
      or { nil, nil, furniture.height_mm }
  else
    size = furniture.size_mm
  end
  local position = version >= 2 and furniture.position_mm or furniture.center_mm
  local spec = {
    id = "edit-furniture",
    title = "Edit furniture",
    mode = "FURNITURE EDIT",
    description = can_resize and "Position, footprint, template and rotation apply as one edit."
      or "Compound geometry is preserved; position, height, rotation and metadata remain editable.",
    apply_label = "Apply furniture changes",
    preview_layout = "side",
    preview_title = "Furniture preview",
    preview_width = 34,
    context = context,
    initial = {
      room_id = furniture.room_id,
      template_id = furniture.template_id,
      name = furniture.name,
      color = furniture.color or "auto",
      category = furniture.category or (template and template.category) or "custom",
      width_mm = size[1],
      depth_mm = size[2],
      height_mm = size[3],
      local_x_mm = position[1],
      local_y_mm = position[2],
      rotation_deg = furniture.rotation_deg,
    },
    fields = {
      { key = "room_id", label = "Room", type = "object_ref", required = true, choices = function(ctx) return common.rooms(ctx) end },
      {
        key = "template_id", label = "Template", type = "object_ref", required = true, choices = templates,
        kind = "roomplan_furniture_template",
        on_change = function(value, _, ctx)
          local selected = resolved_template(ctx, value)
          -- Editing a template association deliberately preserves explicit
          -- dimensions and the user's label.
          return selected and { category = selected.category } or nil
        end,
      },
      { key = "name", label = "Label", type = "text", required = true, trim = true, max_length = 256 },
      {
        key = "color", label = "Color", type = "enum", required = true, kind = "roomplan_color",
        choices = function(_, draft) return color.choices(draft.color) end,
      },
      { key = "category", label = "Category", type = "readonly", value = function(_, draft) return draft.category end },
    },
    validate = function(draft, ctx)
      local errors = {}
      if not common.find(ctx, "furniture", ctx.furniture_id) then errors._form = "the furniture no longer exists" end
      if not common.find(ctx, "room", draft.room_id) then errors.room_id = "room no longer exists" end
      if not resolved_template(ctx, draft.template_id) then errors.template_id = "template no longer exists" end
      return errors
    end,
  }
  if can_resize then
    spec.fields[#spec.fields + 1] = {
      key = "width_mm", label = "Width", type = "measurement", max = runtime.limits.max_dimension_mm,
    }
    spec.fields[#spec.fields + 1] = {
      key = "depth_mm", label = "Depth", type = "measurement", max = runtime.limits.max_dimension_mm,
    }
  else
    spec.fields[#spec.fields + 1] = {
      key = "footprint", label = "Footprint", type = "readonly",
      value = function() return string.format("%d parts (preserved)", #(furniture.footprint.parts or {})) end,
    }
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
    key = "height_mm", label = "Height", type = "measurement", max = runtime.limits.max_dimension_mm,
  }
  spec.fields[#spec.fields + 1] = {
    key = "local_x_mm", label = "Room-local X", type = "measurement", allow_negative = true, allow_zero = true,
  }
  spec.fields[#spec.fields + 1] = {
    key = "local_y_mm", label = "Room-local Y", type = "measurement", allow_negative = true, allow_zero = true,
  }
  spec.fields[#spec.fields + 1] = {
    key = "rotation_deg", label = "Rotation", type = "enum", required = true,
    choices = {
      { value = 0, label = "0 degrees" }, { value = 90, label = "90 degrees" },
      { value = 180, label = "180 degrees" }, { value = 270, label = "270 degrees" },
    },
  }
  spec.fields[#spec.fields + 1] = {
    key = "summary", label = "Result", type = "readonly",
    value = function(_, draft)
      local geometry = can_resize and string.format("%d x %d x %d mm", draft.width_mm,
        draft.depth_mm, draft.height_mm)
        or string.format("%d-part footprint, %d mm high", #(furniture.footprint.parts or {}), draft.height_mm)
      return string.format("%s at (%d, %d), %s", draft.name, draft.local_x_mm, draft.local_y_mm, geometry)
    end,
  }
  spec.preview = function(draft, ctx, state)
    if invalid_preview(state) then return { lines = { "Correct the highlighted field to update the preview." } } end
    local room = common.find(ctx, "room", draft.room_id)
    if not room then return nil, { code = "ROOM_REQUIRED", message = "choose a room" } end
    local geometry = can_resize and string.format("%d x %d x %d mm", draft.width_mm,
      draft.depth_mm, draft.height_mm)
      or string.format("%d-part footprint preserved; height %d mm", #(furniture.footprint.parts or {}), draft.height_mm)
    local entity = model_helpers.deep_copy(furniture)
    entity.room_id = draft.room_id
    entity.template_id = draft.template_id
    entity.name = draft.name
    entity.color = color.resolve(draft.color)
    entity.category = draft.category
    entity.rotation_deg = draft.rotation_deg
    if version >= 2 then
      entity.position_mm = { draft.local_x_mm, draft.local_y_mm }
      entity.height_mm = draft.height_mm
      if can_resize then
        entity.footprint = model_helpers.rectangle_footprint({ draft.width_mm, draft.depth_mm })
        entity.anchor2_mm = { draft.width_mm, draft.depth_mm }
      end
    else
      entity.center_mm = { draft.local_x_mm, draft.local_y_mm }
      entity.size_mm = { draft.width_mm, draft.depth_mm, draft.height_mm }
    end
    return preview_content(entity, {
      string.format("%s in %s at %s", draft.name, room.name or room.id,
        common.point_text({ draft.local_x_mm, draft.local_y_mm })),
      string.format("%s; rotation %d degrees", geometry, draft.rotation_deg),
    })
  end
  function spec.build(draft, ctx)
    ctx = ctx or context
    local current = common.find(ctx, "furniture", ctx.furniture_id)
    if not current then
      return nil, { code = "NOT_FOUND", message = "the furniture no longer exists" }
    end
    local selected = resolved_template(ctx, draft.template_id)
    if not selected then return nil, { code = "TEMPLATE_REQUIRED", message = "template no longer exists" } end
    local patch = {
      room_id = draft.room_id,
      template_id = draft.template_id,
      name = draft.name,
      category = selected.category,
      rotation_deg = draft.rotation_deg,
    }
    if version >= 2 then
      patch.position_mm = { draft.local_x_mm, draft.local_y_mm }
      patch.height_mm = draft.height_mm
      if can_resize then
        patch.footprint = model_helpers.rectangle_footprint({ draft.width_mm, draft.depth_mm })
        patch.anchor2_mm = { draft.width_mm, draft.depth_mm }
      end
    else
      patch.center_mm = { draft.local_x_mm, draft.local_y_mm }
      patch.size_mm = { draft.width_mm, draft.depth_mm, draft.height_mm }
    end
    if current.color ~= nil or draft.color ~= "auto" then patch.color = draft.color end
    return {
      type = "edit_furniture",
      id = ctx.furniture_id,
      patch = patch,
    }
  end
  return spec
end

M.new = M.add
M.centre = centre

return M
