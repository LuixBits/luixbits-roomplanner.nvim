local footprint = require("roomplan.geometry.footprint")
local placement = require("roomplan.geometry.furniture_placement")
local common = require("roomplan.ui.forms.common")

local M = {}

local ALIGNMENTS = {
  { value = "center", label = "Centre on wall segment" },
  { value = "start", label = "Align to segment start" },
  { value = "end", label = "Align to segment end" },
  { value = "keep", label = "Keep current position along wall" },
}

local function decimal(value) return value == math.floor(value) and tostring(value) or string.format("%.1f", value) end

local function wall_choices(walls)
  local result = {}
  for _, wall in ipairs(walls or {}) do
    local coordinate = wall.fixed2 / 2
    local start = wall.start2 / 2
    local finish = wall.finish2 / 2
    result[#result + 1] = {
      value = wall.id,
      label = string.format(
        "%s wall · %s %s–%s mm · at %s mm",
        wall.side:gsub("^%l", string.upper),
        wall.axis,
        decimal(start),
        decimal(finish),
        decimal(coordinate)
      ),
      raw = wall,
    }
  end
  return result
end

local function wall_by_id(context, id)
  for _, wall in ipairs(context.walls or {}) do
    if wall.id == id then return wall end
  end
end

local function proposal(draft, context)
  local furniture = common.find(context, "furniture", context.furniture_id)
  local room = furniture and common.find(context, "room", furniture.room_id)
  if not furniture or not room then
    return nil, { code = "PLACEMENT_STALE", message = "the selected furniture or its room no longer exists" }
  end
  return placement.propose(room, furniture, wall_by_id(context, draft.wall_id), {
    clearance_mm = draft.clearance_mm,
    alignment = draft.alignment,
  })
end

local function nearest_wall(room, furniture, walls)
  local shape = footprint.from_furniture(room, furniture)
  local bounds = shape and footprint.bounds2(shape) or nil
  local best, best_distance
  for _, wall in ipairs(walls or {}) do
    local edge = wall.side == "west" and bounds and bounds.left2
      or wall.side == "east" and bounds and bounds.right2
      or wall.side == "south" and bounds and bounds.bottom2
      or wall.side == "north" and bounds and bounds.top2
    local distance = edge and math.abs(wall.fixed2 - edge) or math.huge
    if not best_distance or distance < best_distance then
      best, best_distance = wall, distance
    end
  end
  return best
end

function M.new(session, furniture)
  local room = furniture and common.find({ session = session }, "room", furniture.room_id)
  local walls, wall_error = room and placement.walls(room) or nil
  walls = walls or {}
  local closest = room and nearest_wall(room, furniture, walls) or nil
  local context = {
    session = session,
    furniture_id = furniture and furniture.id,
    walls = walls,
    wall_error = wall_error,
  }
  local spec = {
    id = "place-furniture-wall",
    title = "Place furniture against wall",
    mode = "FURNITURE PLACE",
    description = "Choose an exact exterior wall segment; Apply creates one undo entry.",
    apply_label = "Place furniture",
    context = context,
    initial = {
      wall_id = closest and closest.id or (walls[1] and walls[1].id),
      alignment = "center",
      clearance_mm = 0,
    },
    fields = {
      {
        key = "wall_id",
        label = "Wall segment",
        type = "enum",
        required = true,
        choices = function(ctx) return wall_choices(ctx.walls) end,
      },
      { key = "alignment", label = "Along wall", type = "enum", required = true, choices = ALIGNMENTS },
      { key = "clearance_mm", label = "Clearance", type = "measurement", allow_zero = true },
      {
        key = "position",
        label = "Resulting position",
        type = "readonly",
        value = function(ctx, draft)
          local value = proposal(draft, ctx)
          return value and common.point_text(value.position_mm) or "unavailable"
        end,
      },
      {
        key = "movement",
        label = "Movement",
        type = "readonly",
        value = function(ctx, draft)
          local value = proposal(draft, ctx)
          return value and common.point_text(value.delta_mm) or "unavailable"
        end,
      },
    },
    preview = function(draft, ctx)
      local value, err = proposal(draft, ctx)
      if not value then return nil, err or ctx.wall_error end
      local rounding = (value.residual_mm[1] ~= 0 or value.residual_mm[2] ~= 0)
          and " · rounded to the integer-mm document lattice"
        or ""
      return {
        lines = {
          string.format(
            "%s wall · %s alignment · %d mm clearance%s",
            value.wall.side,
            draft.alignment,
            draft.clearance_mm,
            rounding
          ),
        },
      }
    end,
  }
  function spec.build(draft, ctx)
    local value, err = proposal(draft, ctx or context)
    if not value then return nil, err end
    return {
      type = "move_furniture",
      id = context.furniture_id,
      [value.position_field] = value.position_mm,
      exact = true,
    }
  end
  return spec
end

M.proposal = proposal
M.wall_choices = wall_choices

return M
