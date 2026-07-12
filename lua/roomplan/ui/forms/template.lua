local config = require("roomplan.config")
local model_helpers = require("roomplan.model")
local common = require("roomplan.ui.forms.common")

local M = {}

function M.edit(session, template)
  if type(template) == "string" then template = model_helpers.find(session:model(), "template", template) end
  assert(type(template) == "table" and type(template.id) == "string", "template.edit requires a custom template")
  local context = { session = session, template_id = template.id }
  local maximum = config.get().limits.max_dimension_mm
  local size = template.default_size_mm
  local spec = {
    id = "edit-template",
    title = "Edit custom furniture template",
    mode = "TEMPLATE EDIT",
    description = "Furniture already using this template keeps its explicit dimensions.",
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
      { key = "width_mm", label = "Default width", type = "measurement", max = maximum },
      { key = "depth_mm", label = "Default depth", type = "measurement", max = maximum },
      { key = "height_mm", label = "Default height", type = "measurement", max = maximum },
      { key = "shape", label = "Shape", type = "readonly", value = function() return "rectangle" end },
    },
    validate = function(_, ctx)
      return common.find(ctx, "template", ctx.template_id) and {} or { _form = "the custom template no longer exists" }
    end,
    preview = function(draft)
      return {
        lines = {
          string.format("%s · %s · %d x %d x %d mm", draft.name, draft.category,
            draft.width_mm, draft.depth_mm, draft.height_mm),
        },
      }
    end,
  }
  function spec.build(draft, ctx)
    ctx = ctx or context
    if not common.find(ctx, "template", ctx.template_id) then
      return nil, { code = "NOT_FOUND", message = "the custom template no longer exists" }
    end
    return {
      type = "edit_custom_template",
      id = ctx.template_id,
      patch = {
        name = draft.name,
        category = draft.category,
        shape = "rectangle",
        default_size_mm = { draft.width_mm, draft.depth_mm, draft.height_mm },
      },
    }
  end
  return spec
end

return M
