local config = require("roomplan.config")
local common = require("roomplan.ui.forms.common")

local M = {}

function M.edit(session)
  local plan = assert(session:model(), "plan.edit requires an active model")
  local limits = config.get().limits
  local context = { session = session }
  local spec = {
    id = "edit-plan",
    title = "Edit plan",
    mode = "PLAN EDIT",
    description = "Metadata and movement defaults apply as one undoable edit.",
    apply_label = "Apply plan changes",
    context = context,
    initial = {
      name = plan.metadata.name,
      notes = plan.metadata.notes or "",
      grid_mm = plan.settings.grid_mm,
      fine_step_mm = plan.settings.fine_step_mm,
      normal_step_mm = plan.settings.normal_step_mm,
      coarse_step_mm = plan.settings.coarse_step_mm,
      default_door_width_mm = plan.settings.default_door_width_mm,
      default_wall_thickness_mm = plan.settings.default_wall_thickness_mm,
    },
    fields = {
      { key = "name", label = "Plan name", type = "text", required = true, trim = true, max_length = 256 },
      { key = "notes", label = "Notes", type = "text", max_length = 4096 },
      { key = "grid_mm", label = "Grid step", type = "measurement", max = limits.max_dimension_mm },
      { key = "fine_step_mm", label = "Fine move", type = "measurement", max = limits.max_dimension_mm },
      { key = "normal_step_mm", label = "Normal move", type = "measurement", max = limits.max_dimension_mm },
      { key = "coarse_step_mm", label = "Coarse move", type = "measurement", max = limits.max_dimension_mm },
      { key = "default_door_width_mm", label = "Default door width", type = "measurement", max = limits.max_dimension_mm },
      { key = "default_wall_thickness_mm", label = "Wall metadata", type = "measurement", max = limits.max_dimension_mm },
      {
        key = "summary", label = "Contents", type = "readonly",
        value = function(ctx)
          local current = common.model(ctx)
          return string.format("%d rooms, %d doors, %d furniture items",
            #(current.rooms or {}), #(current.doors or {}), #(current.furniture or {}))
        end,
      },
    },
    preview = function(draft)
      return {
        lines = {
          string.format("Grid %d mm; movement %d / %d / %d mm",
            draft.grid_mm, draft.fine_step_mm, draft.normal_step_mm, draft.coarse_step_mm),
          string.format("Door default %d mm; wall thickness remains metadata-only",
            draft.default_door_width_mm),
        },
      }
    end,
  }
  function spec.build(draft)
    return {
      type = "edit_plan",
      metadata = { name = draft.name, notes = draft.notes },
      settings = {
        grid_mm = draft.grid_mm,
        fine_step_mm = draft.fine_step_mm,
        normal_step_mm = draft.normal_step_mm,
        coarse_step_mm = draft.coarse_step_mm,
        default_door_width_mm = draft.default_door_width_mm,
        default_wall_thickness_mm = draft.default_wall_thickness_mm,
      },
    }
  end
  return spec
end

return M
