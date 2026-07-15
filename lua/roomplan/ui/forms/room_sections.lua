-- Width/depth editing for non-preset compound rooms. Part positions and IDs
-- stay internal; the form exposes only user-facing rectangular sections.

local geometry = require("roomplan.geometry.footprint")
local util = require("roomplan.util")

local M = {}

local function parts(draft)
  return draft.footprint and draft.footprint.parts or {}
end

local function find(draft, id)
  for _, part in ipairs(parts(draft)) do
    if part.id == id then return part end
  end
end

local function selected_patch(footprint, id)
  local draft = { footprint = footprint }
  local part = find(draft, id) or footprint.parts[1]
  return {
    footprint = footprint,
    section_id = part.id,
    section_width_mm = part.size_mm[1],
    section_depth_mm = part.size_mm[2],
  }
end

function M.initial(room)
  return selected_patch(util.deepcopy(room.footprint), room.footprint.parts[1].id)
end

function M.fields(runtime, room)
  local multiple = #(room.footprint.parts or {}) > 1
  return {
    {
      key = "section_id",
      label = "Room section",
      type = "enum",
      required = true,
      visible = multiple,
      choices = function(_, draft)
        local choices = {}
        for index, part in ipairs(parts(draft)) do
          choices[index] = {
            value = part.id,
            label = string.format("Section %d · %d x %d mm", index, part.size_mm[1], part.size_mm[2]),
          }
        end
        return choices
      end,
    },
    {
      key = "section_width_mm",
      label = multiple and "Section width" or "Overall width",
      type = "measurement",
      required = true,
      max = runtime.limits.max_dimension_mm,
    },
    {
      key = "section_depth_mm",
      label = multiple and "Section depth" or "Overall depth",
      type = "measurement",
      required = true,
      max = runtime.limits.max_dimension_mm,
    },
  }
end

function M.on_change(key, value, _, draft)
  if key == "section_id" then
    return selected_patch(util.deepcopy(draft.footprint), value)
  end
  local dimension = key == "section_width_mm" and 1 or key == "section_depth_mm" and 2 or nil
  if not dimension then return nil end
  local footprint = util.deepcopy(draft.footprint)
  local part = find({ footprint = footprint }, draft.section_id)
  if not part then return nil end
  part.size_mm[dimension] = value
  return { footprint = footprint }
end

function M.validate(draft)
  if not find(draft, draft.section_id) then return "the selected room section no longer exists" end
  local _, err = geometry.from_persisted(draft.footprint)
  return err and (err.message or err.code) or nil
end

function M.footprint(draft)
  return util.deepcopy(draft.footprint)
end

return M
