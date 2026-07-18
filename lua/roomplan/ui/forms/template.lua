local config = require("roomplan.config")
local model_helpers = require("roomplan.model")
local common = require("roomplan.ui.forms.common")

local M = {}

local function schema_version(context)
  local plan = common.model(context)
  return plan and plan.schema_version or 1
end

local function editable_rectangle(template, version)
  if version < 2 then return true, template.default_size_mm, "rectangle" end
  local parts = template.default_footprint and template.default_footprint.parts
  local part = parts and #parts == 1 and parts[1] or nil
  local anchor = template.default_anchor2_mm
  if not part then
    return false, { nil, nil, template.default_height_mm }, "compound"
  end
  if part.id ~= "part-main" or not part.origin_mm or not part.size_mm
    or part.origin_mm[1] ~= 0 or part.origin_mm[2] ~= 0
    or not anchor or anchor[1] ~= part.size_mm[1] or anchor[2] ~= part.size_mm[2] then
    return false, { nil, nil, template.default_height_mm }, "custom anchor"
  end
  return true, { part.size_mm[1], part.size_mm[2], template.default_height_mm }, "rectangle"
end

function M.edit(session, template)
  if type(template) == "string" then template = model_helpers.find(session:model(), "template", template) end
  assert(type(template) == "table" and type(template.id) == "string", "template.edit requires a custom template")
  local context = { session = session, template_id = template.id }
  local maximum = config.get().limits.max_dimension_mm
  local version = schema_version(context)
  local can_resize, size, shape_label = editable_rectangle(template, version)
  local spec = {
    id = "edit-template",
    title = "Edit custom furniture template",
    mode = "TEMPLATE EDIT",
    description = can_resize and "Furniture already using this template keeps its explicit dimensions."
      or "Shape geometry is preserved here; use More → Edit template shape for direct canvas editing.",
    apply_label = "Apply template changes",
    context = context,
    initial = {
      name = template.name,
      category = template.category,
      width_mm = size[1],
      depth_mm = size[2],
      height_mm = size[3],
    },
    fields = {
      { key = "name", label = "Name", type = "text", required = true, trim = true, max_length = 256 },
      { key = "category", label = "Category", type = "text", required = true, trim = true, max_length = 128 },
    },
    validate = function(_, ctx)
      return common.find(ctx, "template", ctx.template_id) and {} or { _form = "the custom template no longer exists" }
    end,
  }
  if can_resize then
    spec.fields[#spec.fields + 1] = {
      key = "width_mm", label = "Default width", type = "measurement", max = maximum,
    }
    spec.fields[#spec.fields + 1] = {
      key = "depth_mm", label = "Default depth", type = "measurement", max = maximum,
    }
  else
    spec.fields[#spec.fields + 1] = {
      key = "footprint", label = "Footprint", type = "readonly",
      value = function()
        return string.format("%d part%s · %s", #(template.default_footprint.parts or {}),
          #(template.default_footprint.parts or {}) == 1 and "" or "s", shape_label)
      end,
    }
  end
  spec.fields[#spec.fields + 1] = {
    key = "height_mm", label = "Default height", type = "measurement", max = maximum,
  }
  spec.fields[#spec.fields + 1] = {
    key = "shape", label = "Shape", type = "readonly",
    value = function() return shape_label end,
  }
  spec.preview = function(draft)
    local geometry = can_resize and string.format("%d x %d x %d mm", draft.width_mm,
      draft.depth_mm, draft.height_mm)
      or string.format("%d-part footprint · %d mm high", #(template.default_footprint.parts or {}), draft.height_mm)
    return { lines = { string.format("%s · %s · %s", draft.name, draft.category, geometry) } }
  end
  function spec.build(draft, ctx)
    ctx = ctx or context
    if not common.find(ctx, "template", ctx.template_id) then
      return nil, { code = "NOT_FOUND", message = "the custom template no longer exists" }
    end
    local patch = {
      name = draft.name,
      category = draft.category,
    }
    if version >= 2 then
      patch.default_height_mm = draft.height_mm
      if can_resize then
        patch.default_footprint = model_helpers.rectangle_footprint({ draft.width_mm, draft.depth_mm })
        patch.default_anchor2_mm = { draft.width_mm, draft.depth_mm }
      end
    else
      patch.shape = "rectangle"
      patch.default_size_mm = { draft.width_mm, draft.depth_mm, draft.height_mm }
    end
    return {
      type = "edit_custom_template",
      id = ctx.template_id,
      patch = patch,
    }
  end
  return spec
end

return M
