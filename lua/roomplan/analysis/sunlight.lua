-- Pure 2D sun-patch geometry. It consumes already-classified exterior windows
-- so rendering and calculations remain independent from Neovim UI state.

local M = {}

local OUTWARD = {
  north = { 0, 1 }, east = { 1, 0 }, south = { 0, -1 }, west = { -1, 0 },
}

local function room_rectangles(room)
  local result = {}
  if room and room.footprint and room.footprint.parts then
    for _, part in ipairs(room.footprint.parts) do
      result[#result + 1] = {
        left = room.origin_mm[1] + part.origin_mm[1],
        bottom = room.origin_mm[2] + part.origin_mm[2],
        right = room.origin_mm[1] + part.origin_mm[1] + part.size_mm[1],
        top = room.origin_mm[2] + part.origin_mm[2] + part.size_mm[2],
      }
    end
  elseif room and room.origin_mm and room.size_mm then
    result[1] = {
      left = room.origin_mm[1], bottom = room.origin_mm[2],
      right = room.origin_mm[1] + room.size_mm[1],
      top = room.origin_mm[2] + room.size_mm[2],
    }
  end
  return result
end

local function faces_sun(side, calculation)
  local outward = OUTWARD[side]
  return outward and outward[1] * calculation.sun_dx + outward[2] * calculation.sun_dy > 1e-9
end

function M.build(model, wall_scene, calculation, defaults)
  local result = { patches = {}, walls = {}, windows = {}, assumed_count = 0 }
  if type(calculation) ~= "table" or (calculation.elevation_deg or -90) <= 0 then return result end
  defaults = defaults or { sill_height_mm = 900, head_height_mm = 2100 }
  local tangent = math.tan(math.rad(calculation.elevation_deg))
  if tangent <= 1e-9 then return result end

  for _, segment in ipairs(wall_scene.segments or {}) do
    if #segment.contributors == 1 and faces_sun(segment.contributors[1].side, calculation) then
      result.walls[segment] = true
    end
  end

  for _, aperture in ipairs(wall_scene.window_apertures or {}) do
    local window = aperture.window
    if aperture.owner_edge_valid and not aperture.connection_requested
      and window and faces_sun(window.side, calculation)
    then
      local explicit = window.sill_height_mm ~= nil and window.head_height_mm ~= nil
      local sill = explicit and window.sill_height_mm or defaults.sill_height_mm
      local head = explicit and window.head_height_mm or defaults.head_height_mm
      if type(sill) == "number" and type(head) == "number" and head > sill then
        local near_distance, far_distance = sill / tangent, head / tangent
        local ix, iy = calculation.incoming_dx, calculation.incoming_dy
        local p0, p1 = aperture.p0, aperture.p1
        result.windows[aperture.id] = true
        if not explicit then result.assumed_count = result.assumed_count + 1 end
        result.patches[#result.patches + 1] = {
          kind = "sun_patch",
          window_id = aperture.id,
          room_id = aperture.owner_room_id,
          vertices = {
            { p0[1] + ix * near_distance, p0[2] + iy * near_distance },
            { p1[1] + ix * near_distance, p1[2] + iy * near_distance },
            { p1[1] + ix * far_distance, p1[2] + iy * far_distance },
            { p0[1] + ix * far_distance, p0[2] + iy * far_distance },
          },
          midpoint = { (p0[1] + p1[1]) / 2, (p0[2] + p1[2]) / 2 },
          incoming = { ix, iy },
          near_distance = near_distance,
          far_distance = far_distance,
          clip_rects = room_rectangles(wall_scene.rooms_by_id[aperture.owner_room_id]),
          estimated = not explicit,
        }
      end
    end
  end
  return result
end

M.faces_sun = faces_sun

return M
