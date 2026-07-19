-- Pure semantic-scene rasterizer.  Work is clipped and bounded by the logical
-- viewport.  Structural wall masks, visual candidates, hits, and highlights
-- remain separate until final line emission.

local viewport_module = require("roomplan.render.viewport")
local glyph_module = require("roomplan.render.glyphs")
local text = require("roomplan.render.text")

local M = {}

local ROLE_RANK = {
  error = 100,
  warning = 90,
  snap_overlap = 88,
  snap = 85,
  selected = 80,
  outlet = 60,
  sun_window = 56,
  window = 55,
  door = 50,
  furniture = 40,
  room_label = 35,
  furniture_label = 35,
  sun_wall = 31,
  wall = 30,
  sunlight_5 = 25,
  sunlight_4 = 24,
  sunlight_3 = 23,
  sunlight_2 = 22,
  sunlight_1 = 21,
  room = 20,
  dimension = 15,
  grid = 10,
  muted = 1,
}

local HIT_RANK = {
  door = 1,
  window = 2,
  outlet = 3,
  furniture = 4,
  room_wall = 5,
  room = 6,
}

local COLORABLE_ROLES = {
  room = true,
  room_label = true,
  furniture = true,
  furniture_label = true,
}

local function finite(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function round(value)
  if value >= 0 then return math.floor(value + 0.5) end
  return math.ceil(value - 0.5)
end

local function clamp(value, minimum, maximum) return math.max(minimum, math.min(maximum, value)) end

local function new_grid(width, height)
  local grid = {}
  for row = 1, height do
    grid[row] = {}
    for column = 1, width do
      grid[row][column] = {
        wall_mask = 0,
        visuals = {},
        hits_by_key = {},
        roles = {},
        critical = false,
        label_reserved = false,
      }
    end
  end
  return grid
end

local function in_bounds(context, row, column)
  return row >= 1 and row <= context.height and column >= 1 and column <= context.width
end

local function cell_at(context, row, column)
  if not in_bounds(context, row, column) then return nil end
  return context.grid[row][column]
end

local function add_role(cell, role)
  if role then cell.roles[role] = true end
end

local function add_color(cell, role, value)
  if COLORABLE_ROLES[role] and type(value) == "string" then
    cell.colors = cell.colors or {}
    cell.colors[role] = value
  end
end

local function default_role_for_ref(ref, context)
  if not ref then return nil end
  if ref.type == "door" then
    return "door"
  elseif ref.type == "window" then
    return "window"
  elseif ref.type == "outlet" then
    return "outlet"
  elseif ref.type == "furniture" then
    return "furniture"
  elseif ref.type == "room" then
    return context == "wall" and "wall" or "room"
  end
  return nil
end

local function hit_priority(ref, context)
  if ref.type == "door" then
    return HIT_RANK.door
  elseif ref.type == "window" then
    return HIT_RANK.window
  elseif ref.type == "outlet" then
    return HIT_RANK.outlet
  elseif ref.type == "furniture" then
    return HIT_RANK.furniture
  elseif ref.type == "room" and context == "wall" then
    return HIT_RANK.room_wall
  elseif ref.type == "room" then
    return HIT_RANK.room
  end
  return 99
end

local function add_hit(cell, ref, context)
  if type(ref) ~= "table" or type(ref.id) ~= "string" or ref.id == "" then return end
  context = context or ref.context
  local key = (ref.type or "") .. "\0" .. ref.id
  local candidate = {
    type = ref.type,
    id = ref.id,
    order = ref.order or 0,
    context = context,
    priority = hit_priority(ref, context),
  }
  local previous = cell.hits_by_key[key]
  if not previous or candidate.priority < previous.priority then cell.hits_by_key[key] = candidate end
  add_role(cell, default_role_for_ref(ref, context))
end

local function add_visual(context, row, column, visual)
  local cell = cell_at(context, row, column)
  if not cell then return end
  context.serial = context.serial + 1
  visual.serial = context.serial
  visual.layer = visual.layer or 0
  visual.order = visual.order or 0
  cell.visuals[#cell.visuals + 1] = visual
  if visual.critical then cell.critical = true end
  add_role(cell, visual.role)
  add_color(cell, visual.role, visual.color)
  if visual.ref then add_hit(cell, visual.ref, visual.hit_context) end
end

local function add_refs_and_role(cell, primitive, hit_context)
  add_role(cell, primitive.role)
  add_color(
    cell,
    primitive.role or (primitive.ref and default_role_for_ref(primitive.ref, hit_context)),
    primitive.color
  )
  if primitive.ref then add_hit(cell, primitive.ref, hit_context) end
  if primitive.refs then
    for i = 1, #primitive.refs do
      add_hit(cell, primitive.refs[i], hit_context)
    end
  end
end

local function project(viewport, x, y) return viewport_module.world_to_screen(viewport, x, y) end

local LEFT, RIGHT, TOP, BOTTOM = 1, 2, 4, 8

local function out_code(x, y, width, height)
  local code = 0
  if x < 0 then
    code = code + LEFT
  elseif x > width - 1 then
    code = code + RIGHT
  end
  if y < 0 then
    code = code + TOP
  elseif y > height - 1 then
    code = code + BOTTOM
  end
  return code
end

local function has_flag(value, flag) return value % (flag * 2) >= flag end

-- Cohen-Sutherland clipping in zero-based logical screen coordinates.
local function clip_line(x0, y0, x1, y1, width, height)
  local code0 = out_code(x0, y0, width, height)
  local code1 = out_code(x1, y1, width, height)
  for _ = 1, 16 do
    if code0 == 0 and code1 == 0 then return x0, y0, x1, y1 end
    -- No bit library is needed: test every region bit arithmetically.
    local common = false
    for _, flag in ipairs({ LEFT, RIGHT, TOP, BOTTOM }) do
      if has_flag(code0, flag) and has_flag(code1, flag) then
        common = true
        break
      end
    end
    if common then return nil end

    local code = code0 ~= 0 and code0 or code1
    local x, y
    if has_flag(code, TOP) then
      if y1 == y0 then return nil end
      x = x0 + (x1 - x0) * (0 - y0) / (y1 - y0)
      y = 0
    elseif has_flag(code, BOTTOM) then
      if y1 == y0 then return nil end
      x = x0 + (x1 - x0) * ((height - 1) - y0) / (y1 - y0)
      y = height - 1
    elseif has_flag(code, RIGHT) then
      if x1 == x0 then return nil end
      y = y0 + (y1 - y0) * ((width - 1) - x0) / (x1 - x0)
      x = width - 1
    else
      if x1 == x0 then return nil end
      y = y0 + (y1 - y0) * (0 - x0) / (x1 - x0)
      x = 0
    end

    if code == code0 then
      x0, y0 = x, y
      code0 = out_code(x0, y0, width, height)
    else
      x1, y1 = x, y
      code1 = out_code(x1, y1, width, height)
    end
  end
  return nil
end

local function line_cells(context, x0, y0, x1, y1, callback)
  x0, y0, x1, y1 = clip_line(x0, y0, x1, y1, context.width, context.height)
  if not x0 then return end
  local column0 = clamp(round(x0) + 1, 1, context.width)
  local row0 = clamp(round(y0) + 1, 1, context.height)
  local column1 = clamp(round(x1) + 1, 1, context.width)
  local row1 = clamp(round(y1) + 1, 1, context.height)
  local delta_column = math.abs(column1 - column0)
  local column_step = column0 < column1 and 1 or -1
  local delta_row = -math.abs(row1 - row0)
  local row_step = row0 < row1 and 1 or -1
  local err = delta_column + delta_row
  local previous_row, previous_column
  while true do
    callback(row0, column0, previous_row, previous_column, row1, column1)
    if column0 == column1 and row0 == row1 then break end
    previous_row, previous_column = row0, column0
    local twice = 2 * err
    if twice >= delta_row then
      err = err + delta_row
      column0 = column0 + column_step
    end
    if twice <= delta_column then
      err = err + delta_column
      row0 = row0 + row_step
    end
  end
end

local function draw_wall(context, primitive)
  local x0, y0 = project(context.viewport, primitive.x1, primitive.y1)
  local x1, y1 = project(context.viewport, primitive.x2, primitive.y2)
  if math.abs(y1 - y0) < 1e-9 then
    local row = round(y0) + 1
    if row < 1 or row > context.height then return end
    local original_min = math.min(round(x0) + 1, round(x1) + 1)
    local original_max = math.max(round(x0) + 1, round(x1) + 1)
    if original_max < 1 or original_min > context.width then return end
    local first = clamp(original_min, 1, context.width)
    local last = clamp(original_max, 1, context.width)
    if last < first then return end
    for column = first, last do
      local cell = context.grid[row][column]
      if original_min == original_max then
        cell.wall_mask = glyph_module.add(cell.wall_mask, glyph_module.E)
        cell.wall_mask = glyph_module.add(cell.wall_mask, glyph_module.W)
      else
        if column > original_min then cell.wall_mask = glyph_module.add(cell.wall_mask, glyph_module.W) end
        if column < original_max then cell.wall_mask = glyph_module.add(cell.wall_mask, glyph_module.E) end
      end
      cell.critical = true
      add_refs_and_role(cell, primitive, "wall")
    end
  else
    local column = round(x0) + 1
    if column < 1 or column > context.width then return end
    local original_min = math.min(round(y0) + 1, round(y1) + 1)
    local original_max = math.max(round(y0) + 1, round(y1) + 1)
    if original_max < 1 or original_min > context.height then return end
    local first = clamp(original_min, 1, context.height)
    local last = clamp(original_max, 1, context.height)
    if last < first then return end
    for row = first, last do
      local cell = context.grid[row][column]
      if original_min == original_max then
        cell.wall_mask = glyph_module.add(cell.wall_mask, glyph_module.N)
        cell.wall_mask = glyph_module.add(cell.wall_mask, glyph_module.S)
      else
        if row > original_min then cell.wall_mask = glyph_module.add(cell.wall_mask, glyph_module.N) end
        if row < original_max then cell.wall_mask = glyph_module.add(cell.wall_mask, glyph_module.S) end
      end
      cell.critical = true
      add_refs_and_role(cell, primitive, "wall")
    end
  end
end

local function projected_rect(context, primitive)
  local left_screen, top_screen = project(context.viewport, primitive.left, primitive.top)
  local right_screen, bottom_screen = project(context.viewport, primitive.right, primitive.bottom)
  local left = math.min(round(left_screen) + 1, round(right_screen) + 1)
  local right = math.max(round(left_screen) + 1, round(right_screen) + 1)
  local top = math.min(round(top_screen) + 1, round(bottom_screen) + 1)
  local bottom = math.max(round(top_screen) + 1, round(bottom_screen) + 1)
  if right < 1 or left > context.width or bottom < 1 or top > context.height then return nil end
  return clamp(left, 1, context.width),
    clamp(top, 1, context.height),
    clamp(right, 1, context.width),
    clamp(bottom, 1, context.height)
end

local function draw_interior(context, primitive, hit_context)
  local left, top, right, bottom = projected_rect(context, primitive)
  if not left then return end
  for row = top, bottom do
    for column = left, right do
      local cell = context.grid[row][column]
      add_refs_and_role(cell, primitive, hit_context)
    end
  end
end

local function point_in_rectangles(x, y, rectangles)
  for _, rectangle in ipairs(rectangles or {}) do
    if
      x >= rectangle.left - 1e-9
      and x <= rectangle.right + 1e-9
      and y >= rectangle.bottom - 1e-9
      and y <= rectangle.top + 1e-9
    then
      return true
    end
  end
  return false
end

local function point_in_polygon(x, y, vertices)
  local sign
  for index = 1, #vertices do
    local first = vertices[index]
    local second = vertices[index % #vertices + 1]
    local cross = (second[1] - first[1]) * (y - first[2]) - (second[2] - first[2]) * (x - first[1])
    if math.abs(cross) > 1e-7 then
      local current = cross > 0
      if sign ~= nil and current ~= sign then return false end
      sign = current
    end
  end
  return sign ~= nil
end

local function point_in_sun_patch(x, y, patch)
  return point_in_rectangles(x, y, patch.clip_rects) and point_in_polygon(x, y, patch.vertices or {})
end

local function draw_sun_patch(context, primitive)
  local vertices = primitive.vertices or {}
  if #vertices < 3 or #(primitive.clip_rects or {}) == 0 then return end
  local left, right, top, bottom
  for _, vertex in ipairs(vertices) do
    local column, row = project(context.viewport, vertex[1], vertex[2])
    left, right = left and math.min(left, column) or column, right and math.max(right, column) or column
    top, bottom = top and math.min(top, row) or row, bottom and math.max(bottom, row) or row
  end
  left = clamp(math.floor(left) + 1, 1, context.width)
  right = clamp(math.ceil(right) + 1, 1, context.width)
  top = clamp(math.floor(top) + 1, 1, context.height)
  bottom = clamp(math.ceil(bottom) + 1, 1, context.height)
  local span = math.max(1e-9, primitive.far_distance - primitive.near_distance)
  for row = top, bottom do
    for column = left, right do
      local x, y = viewport_module.screen_to_world(context.viewport, column - 1, row - 1)
      if point_in_sun_patch(x, y, primitive) then
        local distance = (x - primitive.midpoint[1]) * primitive.incoming[1]
          + (y - primitive.midpoint[2]) * primitive.incoming[2]
        local progress = clamp((distance - primitive.near_distance) / span, 0, 1)
        local warmth = clamp(math.ceil(math.max(0, 35 - (primitive.elevation_deg or 35)) / 15), 0, 2)
        local level = clamp(math.floor(progress * 5) + 1 + warmth, 1, 5)
        add_visual(context, row, column, {
          char = " ",
          layer = primitive.layer,
          role = "sunlight_" .. level,
          order = primitive.order,
        })
      end
    end
  end
end

local function draw_sun_exposure(context, primitive)
  local exposure = primitive.exposure or {}
  local left, right, top, bottom
  for _, sample in ipairs(exposure.samples or {}) do
    for _, patch in ipairs(sample.patches or {}) do
      for _, vertex in ipairs(patch.vertices or {}) do
        local column, row = project(context.viewport, vertex[1], vertex[2])
        left = left and math.min(left, column) or column
        right = right and math.max(right, column) or column
        top = top and math.min(top, row) or row
        bottom = bottom and math.max(bottom, row) or row
      end
    end
  end
  if not left then return end
  left = clamp(math.floor(left) + 1, 1, context.width)
  right = clamp(math.ceil(right) + 1, 1, context.width)
  top = clamp(math.floor(top) + 1, 1, context.height)
  bottom = clamp(math.ceil(bottom) + 1, 1, context.height)
  local thresholds = exposure.thresholds_minutes or { 60, 120, 240, 360 }
  for row = top, bottom do
    for column = left, right do
      local x, y = viewport_module.screen_to_world(context.viewport, column - 1, row - 1)
      local minutes = 0
      for _, sample in ipairs(exposure.samples or {}) do
        local exposed = false
        for _, patch in ipairs(sample.patches or {}) do
          if point_in_sun_patch(x, y, patch) then
            exposed = true
            break
          end
        end
        if exposed then minutes = minutes + (sample.minutes or 0) end
      end
      if minutes > 0 then
        local level = #thresholds + 1
        for index, threshold in ipairs(thresholds) do
          if minutes <= threshold then
            level = index
            break
          end
        end
        add_visual(context, row, column, {
          char = " ",
          layer = primitive.layer,
          role = "sunlight_" .. clamp(level, 1, 5),
          order = primitive.order,
        })
      end
    end
  end
end

local function draw_visual_axis(context, row1, column1, row2, column2, character, primitive, critical)
  local min_row, max_row = math.min(row1, row2), math.max(row1, row2)
  local min_column, max_column = math.min(column1, column2), math.max(column1, column2)
  min_row, max_row = clamp(min_row, 1, context.height), clamp(max_row, 1, context.height)
  min_column, max_column = clamp(min_column, 1, context.width), clamp(max_column, 1, context.width)
  if row1 == row2 then
    if row1 < 1 or row1 > context.height then return end
    for column = min_column, max_column do
      add_visual(context, row1, column, {
        char = character,
        layer = primitive.layer,
        role = primitive.role or "furniture",
        color = primitive.color,
        ref = primitive.ref,
        hit_context = "edge",
        order = primitive.order,
        critical = critical,
      })
    end
  elseif column1 == column2 then
    if column1 < 1 or column1 > context.width then return end
    for row = min_row, max_row do
      add_visual(context, row, column1, {
        char = character,
        layer = primitive.layer,
        role = primitive.role or "furniture",
        color = primitive.color,
        ref = primitive.ref,
        hit_context = "edge",
        order = primitive.order,
        critical = critical,
      })
    end
  end
end

local function draw_furniture_outline(context, primitive)
  local left_screen, top_screen = project(context.viewport, primitive.left, primitive.top)
  local right_screen, bottom_screen = project(context.viewport, primitive.right, primitive.bottom)
  local left = round(math.min(left_screen, right_screen)) + 1
  local right = round(math.max(left_screen, right_screen)) + 1
  local top = round(math.min(top_screen, bottom_screen)) + 1
  local bottom = round(math.max(top_screen, bottom_screen)) + 1
  if right < 1 or left > context.width or bottom < 1 or top > context.height then return end

  if left == right or top == bottom then
    local row = clamp(round((top + bottom) / 2), 1, context.height)
    local column = clamp(round((left + right) / 2), 1, context.width)
    add_visual(context, row, column, {
      char = context.glyphs.furniture_marker,
      layer = primitive.layer,
      role = primitive.role or "furniture",
      color = primitive.color,
      ref = primitive.ref,
      hit_context = "edge",
      order = primitive.order,
      critical = true,
    })
    return
  end

  draw_visual_axis(context, top, left, top, right, context.glyphs.furniture_horizontal, primitive, true)
  draw_visual_axis(context, bottom, left, bottom, right, context.glyphs.furniture_horizontal, primitive, true)
  draw_visual_axis(context, top, left, bottom, left, context.glyphs.furniture_vertical, primitive, true)
  draw_visual_axis(context, top, right, bottom, right, context.glyphs.furniture_vertical, primitive, true)

  local corners = {
    { top, left, context.glyphs.furniture_corner_nw },
    { top, right, context.glyphs.furniture_corner_ne },
    { bottom, left, context.glyphs.furniture_corner_sw },
    { bottom, right, context.glyphs.furniture_corner_se },
  }
  for i = 1, #corners do
    local corner = corners[i]
    if in_bounds(context, corner[1], corner[2]) then
      add_visual(context, corner[1], corner[2], {
        char = corner[3],
        layer = primitive.layer,
        role = primitive.role or "furniture",
        color = primitive.color,
        ref = primitive.ref,
        hit_context = "edge",
        order = primitive.order,
        critical = true,
      })
    end
  end
end

local function line_character(context, delta_column, delta_row)
  if delta_row == 0 then
    return context.glyphs.door_horizontal
  elseif delta_column == 0 then
    return context.glyphs.door_vertical
  elseif delta_column * delta_row < 0 then
    return context.glyphs.door_slash
  end
  return context.glyphs.door_backslash
end

local function draw_door_leaf(context, primitive)
  local x0, y0 = project(context.viewport, primitive.x1, primitive.y1)
  local x1, y1 = project(context.viewport, primitive.x2, primitive.y2)
  local delta_column = x1 - x0
  local delta_row = y1 - y0
  local character = line_character(context, delta_column, delta_row)
  line_cells(
    context,
    x0,
    y0,
    x1,
    y1,
    function(row, column)
      add_visual(context, row, column, {
        char = character,
        layer = primitive.layer,
        role = primitive.role or "door",
        ref = primitive.ref,
        hit_context = "leaf",
        order = primitive.order,
        critical = true,
      })
    end
  )
end

local function draw_door_aperture(context, primitive)
  local x0, y0 = project(context.viewport, primitive.x1, primitive.y1)
  local x1, y1 = project(context.viewport, primitive.x2, primitive.y2)
  local span = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
  line_cells(context, x0, y0, x1, y1, function(row, column)
    local cell = context.grid[row][column]
    add_refs_and_role(cell, primitive, "aperture")
  end)
  if span < 1.5 then
    local midpoint_x = (x0 + x1) / 2
    local midpoint_y = (y0 + y1) / 2
    if
      midpoint_x < -0.5
      or midpoint_x > context.width - 0.5
      or midpoint_y < -0.5
      or midpoint_y > context.height - 0.5
    then
      return
    end
    local row = clamp(round(midpoint_y) + 1, 1, context.height)
    local column = clamp(round(midpoint_x) + 1, 1, context.width)
    if in_bounds(context, row, column) then
      add_visual(context, row, column, {
        char = context.glyphs.door_marker,
        -- At this level of detail hinge, leaf, and aperture project to the same
        -- cell.  The explicit marker must remain the visible representation.
        layer = primitive.layer + 2,
        role = primitive.role or "door",
        ref = primitive.ref,
        hit_context = "aperture",
        order = primitive.order,
        critical = true,
      })
    end
  end
end

local function draw_window_aperture(context, primitive)
  local x0, y0 = project(context.viewport, primitive.x1, primitive.y1)
  local x1, y1 = project(context.viewport, primitive.x2, primitive.y2)
  local span = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
  local character = math.abs(x1 - x0) >= math.abs(y1 - y0) and context.glyphs.window_horizontal
    or context.glyphs.window_vertical
  if span < 1.5 then character = context.glyphs.window_marker end
  line_cells(
    context,
    x0,
    y0,
    x1,
    y1,
    function(row, column)
      add_visual(context, row, column, {
        char = character,
        layer = primitive.layer,
        role = primitive.role or "window",
        ref = primitive.ref,
        hit_context = "aperture",
        order = primitive.order,
        critical = true,
      })
    end
  )
end

local function draw_outlet_marker(context, primitive)
  local x, y = project(context.viewport, primitive.x, primitive.y)
  local row, column = round(y) + 1, round(x) + 1
  if in_bounds(context, row, column) then
    local character = context.glyphs.outlet_marker
    if primitive.placement ~= "floor" and primitive.side then
      local directions = {
        north = { 0, 1 },
        east = { 1, 0 },
        south = { 0, -1 },
        west = { -1, 0 },
      }
      local direction = directions[primitive.side]
      local dx, dy = viewport_module.world_delta_to_view(context.viewport, direction[1], direction[2])
      local visible_side = math.abs(dx) > math.abs(dy) and (dx > 0 and "east" or "west")
        or (dy > 0 and "north" or "south")
      character = context.glyphs["outlet_wall_" .. visible_side] or character
    end
    add_visual(context, row, column, {
      char = character,
      layer = primitive.layer,
      role = primitive.role or "outlet",
      ref = primitive.ref,
      hit_context = "marker",
      order = primitive.order,
      critical = true,
    })
  end
end

local function draw_door_hinge(context, primitive)
  local x, y = project(context.viewport, primitive.x, primitive.y)
  local row, column = round(y) + 1, round(x) + 1
  if in_bounds(context, row, column) then
    add_visual(context, row, column, {
      char = context.glyphs.door_hinge,
      layer = primitive.layer,
      role = primitive.role or "door",
      ref = primitive.ref,
      hit_context = "hinge",
      order = primitive.order,
      critical = true,
    })
  end
end

local function draw_door_swing(context, primitive)
  if not finite(primitive.radius) or primitive.radius <= 0 then return end
  local projected_radius_x = primitive.radius / context.viewport.mm_per_column
  local projected_radius_y = primitive.radius / context.viewport.mm_per_row
  local projected_radius = math.max(projected_radius_x, projected_radius_y)
  local sample_count = math.ceil(math.abs(primitive.sweep_deg or 0) / 360 * 2 * math.pi * projected_radius * 1.5)
  sample_count = clamp(sample_count, 2, math.max(2, 2 * (context.width + context.height)))
  local previous_x, previous_y
  for index = 0, sample_count do
    local fraction = index / sample_count
    local angle = math.rad((primitive.start_angle_deg or 0) + (primitive.sweep_deg or 0) * fraction)
    local world_x = primitive.cx + primitive.radius * math.cos(angle)
    local world_y = primitive.cy + primitive.radius * math.sin(angle)
    local x, y = project(context.viewport, world_x, world_y)
    if previous_x then
      line_cells(
        context,
        previous_x,
        previous_y,
        x,
        y,
        function(row, column)
          add_visual(context, row, column, {
            char = context.glyphs.door_arc,
            layer = primitive.layer,
            role = primitive.role or "door",
            ref = primitive.ref,
            hit_context = "swing",
            order = primitive.order,
            critical = true,
          })
        end
      )
    end
    previous_x, previous_y = x, y
  end
end

local function draw_annotation(context, primitive)
  local x, y = project(context.viewport, primitive.x, primitive.y)
  local row, column = round(y) + 1, round(x) + 1
  if not in_bounds(context, row, column) then return end
  local character = primitive.char
  if primitive.role == "error" then
    character = context.glyphs.error
  elseif primitive.role == "warning" then
    character = context.glyphs.warning
  end
  if type(character) ~= "string" or context.width_fn(character) ~= 1 then character = context.glyphs.replacement end
  add_visual(context, row, column, {
    char = character or context.glyphs.warning,
    layer = primitive.layer,
    role = primitive.role,
    ref = primitive.ref,
    hit_context = "annotation",
    order = primitive.order,
    critical = true,
  })
end

local function draw_snap_guide(context, primitive)
  local x0, y0 = project(context.viewport, primitive.x1, primitive.y1)
  local x1, y1 = project(context.viewport, primitive.x2, primitive.y2)
  local horizontal = math.abs(x1 - x0) >= math.abs(y1 - y0)
  local character
  if context.glyphs.mode == "unicode" then
    character = horizontal and "┄" or "┊"
  else
    character = horizontal and "." or ":"
  end
  if context.width_fn(character) ~= 1 then character = context.glyphs.grid end
  line_cells(
    context,
    x0,
    y0,
    x1,
    y1,
    function(row, column)
      add_visual(context, row, column, {
        char = character,
        layer = primitive.layer,
        role = "snap",
        order = primitive.order,
      })
    end
  )
end

local function draw_snap_overlap(context, primitive)
  local x0, y0 = project(context.viewport, primitive.x1, primitive.y1)
  local x1, y1 = project(context.viewport, primitive.x2, primitive.y2)
  local horizontal = math.abs(x1 - x0) >= math.abs(y1 - y0)
  local character
  if context.glyphs.mode == "unicode" then
    character = horizontal and "━" or "┃"
  else
    character = horizontal and "=" or "#"
  end
  if context.width_fn(character) ~= 1 then character = horizontal and "=" or "#" end
  line_cells(
    context,
    x0,
    y0,
    x1,
    y1,
    function(row, column)
      add_visual(context, row, column, {
        char = character,
        layer = primitive.layer,
        role = "snap_overlap",
        order = primitive.order,
        critical = true,
      })
    end
  )
end

local function draw_grid(context, primitive)
  local spacing = primitive.spacing_mm
  if not finite(spacing) or spacing <= 0 then return end
  local origin_x, origin_y = viewport_module.screen_to_world(context.viewport, 0, 0)
  local column_x, column_y = viewport_module.screen_to_world(context.viewport, 1, 0)
  local row_x, row_y = viewport_module.screen_to_world(context.viewport, 0, 1)
  local tolerance_x = math.max(math.abs(column_x - origin_x), math.abs(row_x - origin_x)) / 2
  local tolerance_y = math.max(math.abs(column_y - origin_y), math.abs(row_y - origin_y)) / 2
  for row = 1, context.height do
    for column = 1, context.width do
      local world_x, world_y = viewport_module.screen_to_world(context.viewport, column - 1, row - 1)
      local nearest_x = round(world_x / spacing) * spacing
      local nearest_y = round(world_y / spacing) * spacing
      if math.abs(world_x - nearest_x) <= tolerance_x and math.abs(world_y - nearest_y) <= tolerance_y then
        add_visual(context, row, column, {
          char = context.glyphs.grid,
          layer = primitive.layer,
          role = "grid",
          order = primitive.order,
        })
      end
    end
  end
end

local function label_candidates(primitive)
  local result = {}
  if type(primitive.candidates) == "table" then
    for i = 1, #primitive.candidates do
      local candidate = primitive.candidates[i]
      if type(candidate) == "table" and finite(candidate[1]) and finite(candidate[2]) then
        result[#result + 1] = candidate
      end
    end
  end
  if #result == 0 then result[1] = { primitive.x, primitive.y } end
  return result
end

local function can_place_label(context, row, first_column, count)
  if row < 1 or row > context.height or first_column < 1 or first_column + count - 1 > context.width then
    return false
  end
  for column = first_column, first_column + count - 1 do
    if context.grid[row][column].critical or context.grid[row][column].label_reserved then return false end
  end
  return true
end

local function label_start(column, count, align)
  if align == "left" then
    return column
  elseif align == "right" then
    return column - count + 1
  end
  return column - math.floor((count - 1) / 2)
end

local function offsets(limit, include_zero)
  local result = include_zero and { 0 } or {}
  for distance = 1, limit do
    result[#result + 1] = -distance
    result[#result + 1] = distance
  end
  return result
end

local function abbreviated_cells(cells, length, force_marker, width_fn)
  if length >= #cells and not force_marker then return cells end
  local marker = width_fn("…") == 1 and "…" or "~"
  if length <= 1 then return { marker } end
  local available = length - 1
  local prefix = math.ceil(available / 2)
  local suffix = math.floor(available / 2)
  local result = {}
  for index = 1, prefix do
    result[#result + 1] = cells[index]
  end
  result[#result + 1] = marker
  for index = #cells - suffix + 1, #cells do
    result[#result + 1] = cells[index]
  end
  return result
end

local function placement_positions(context, primitive, anchor_column, anchor_row, length)
  local result = {}
  local function add(row, first_column)
    if row >= 1 and row <= context.height and first_column >= 1 and first_column + length - 1 <= context.width then
      result[#result + 1] = { row = row, first_column = first_column }
    end
  end

  if primitive.placement == "vertical_edge" then
    for _, row_offset in ipairs(offsets(math.min(4, context.height - 1), true)) do
      add(anchor_row + row_offset, anchor_column - length - 1)
      add(anchor_row + row_offset, anchor_column + 1)
    end
    return result
  end

  local row_offsets = primitive.placement == "horizontal_edge" and offsets(math.min(4, context.height - 1), false)
    or offsets(math.min(6, context.height - 1), true)
  local maximum_start = context.width - length + 1
  local desired = clamp(label_start(anchor_column, length, primitive.align), 1, maximum_start)
  local column_offsets = offsets(math.min(6, math.max(0, maximum_start - 1)), true)
  for _, row_offset in ipairs(row_offsets) do
    for _, column_offset in ipairs(column_offsets) do
      add(anchor_row + row_offset, desired + column_offset)
    end
  end
  return result
end

local LABEL_SCALE = {
  room_name = { min_width = 6, min_height = 3, width_fraction = 0.65 },
  object_name = { min_width = 7, min_height = 3, width_fraction = 0.6 },
}

local function projected_box_cells(context, bounds)
  if type(bounds) ~= "table" then return nil end
  local points = {
    { bounds.left, bounds.bottom },
    { bounds.left, bounds.top },
    { bounds.right, bounds.bottom },
    { bounds.right, bounds.top },
  }
  local left, right, top, bottom
  for _, point in ipairs(points) do
    if not finite(point[1]) or not finite(point[2]) then return nil end
    local x, y = project(context.viewport, point[1], point[2])
    left = left and math.min(left, x) or x
    right = right and math.max(right, x) or x
    top = top and math.min(top, y) or y
    bottom = bottom and math.max(bottom, y) or y
  end
  return right - left + 1, bottom - top + 1
end

local function projected_span_cells(context, span)
  if type(span) ~= "table" then return nil end
  if not finite(span.x1) or not finite(span.y1) or not finite(span.x2) or not finite(span.y2) then return nil end
  local x1, y1 = project(context.viewport, span.x1, span.y1)
  local x2, y2 = project(context.viewport, span.x2, span.y2)
  return math.max(math.abs(x2 - x1), math.abs(y2 - y1)) + 1
end

-- Terminal cells cannot change font size. Instead, labels use the projected
-- object as a screen-space budget: full text when it has room, an abbreviated
-- name at medium scale, and no text once the shape becomes a tiny overview
-- glyph. Dimensions also need air around their measured edge.
local function label_cell_budget(context, primitive)
  local limit = math.min(context.width, primitive.max_cells or context.max_label_cells)
  if finite(primitive.max_mm_per_column) and context.viewport.mm_per_column > primitive.max_mm_per_column then
    return 0
  end
  local policy = LABEL_SCALE[primitive.scale_policy]
  if policy then
    local width, height = projected_box_cells(context, primitive.fit_bounds)
    local text_width = context.width_fn(tostring(primitive.text or ""))
    if not width or width < policy.min_width or height < policy.min_height then
      -- A single-letter room name remains useful in a small but still
      -- recognizable outline. Longer text disappears instead of turning into
      -- a canvas full of ellipses.
      if text_width <= 1 and width and width >= 4 and height and height >= 3 then return math.min(limit, 1) end
      return 0
    end
    limit = math.min(limit, math.floor(math.max(0, width - 2) * policy.width_fraction))
    if limit < 3 and text_width > limit then return 0 end
  elseif primitive.scale_policy == "dimension" then
    local span = projected_span_cells(context, primitive.fit_span)
    local text_width = context.width_fn(tostring(primitive.text or ""))
    if not span or span < math.max(8, text_width + 5) then return 0 end
  end
  return math.max(0, math.floor(limit))
end

local function draw_label(context, primitive)
  local max_cells = label_cell_budget(context, primitive)
  if max_cells < 1 then return end
  local cells, metadata = text.sanitize_cells(
    primitive.text or "",
    context.max_label_source_cells,
    context.width_fn,
    context.glyphs.replacement
  )
  if not cells then
    context.warnings[#context.warnings + 1] = {
      code = "LABEL_NOT_RENDERED",
      object_id = primitive.ref and primitive.ref.id,
      message = "Invalid label text: " .. tostring(metadata),
    }
    return
  end
  if #cells == 0 then return end

  if primitive.allow_truncate == false and (metadata.truncated or #cells > max_cells) then
    context.warnings[#context.warnings + 1] = {
      code = "LABEL_NOT_RENDERED",
      object_id = primitive.ref and primitive.ref.id,
      message = "Dimension text exceeds the configured label width",
    }
    return
  end

  local candidates = label_candidates(primitive)
  local maximum_length = math.min(#cells, max_cells)
  local minimum_length = primitive.allow_truncate == false and #cells or 1
  for length = maximum_length, minimum_length, -1 do
    local displayed = abbreviated_cells(cells, length, metadata.truncated, context.width_fn)
    for candidate_index = 1, #candidates do
      local x, y = project(context.viewport, candidates[candidate_index][1], candidates[candidate_index][2])
      local anchor_column = round(x) + 1
      local anchor_row = round(y) + 1
      for _, position in ipairs(placement_positions(context, primitive, anchor_column, anchor_row, #displayed)) do
        if can_place_label(context, position.row, position.first_column, #displayed) then
          for index = 1, #displayed do
            local column = position.first_column + index - 1
            add_visual(context, position.row, column, {
              char = displayed[index],
              layer = primitive.layer,
              role = primitive.role or (primitive.ref and default_role_for_ref(primitive.ref)) or "muted",
              color = primitive.color,
              ref = primitive.ref,
              hit_context = "label",
              order = primitive.order,
              critical = false,
            })
            context.grid[position.row][column].label_reserved = true
          end
          -- Keep adjacent labels from reading as one accidental word. Names
          -- are placed first, so dimensions naturally move to another row or
          -- disappear when the overview is crowded.
          local before = position.first_column - 1
          local after = position.first_column + #displayed
          if before >= 1 then context.grid[position.row][before].label_reserved = true end
          if after <= context.width then context.grid[position.row][after].label_reserved = true end
          if #displayed < #cells or metadata.truncated or metadata.replaced > 0 then
            context.warnings[#context.warnings + 1] = {
              code = "LABEL_ABBREVIATED",
              object_id = primitive.ref and primitive.ref.id,
              message = "Label was shortened or sanitized for the canvas",
            }
          end
          return
        end
      end
    end
  end

  context.warnings[#context.warnings + 1] = {
    code = "LABEL_NOT_RENDERED",
    object_id = primitive.ref and primitive.ref.id,
    message = "No free addressable cells for label",
  }
end

local function visual_wins(candidate, current)
  if not current then return true end
  if candidate.layer ~= current.layer then return candidate.layer > current.layer end
  if candidate.order ~= current.order then return candidate.order > current.order end
  return candidate.serial > current.serial
end

local function best_role(cell, visual, wall_present)
  local best
  local rank = -1
  for role in pairs(cell.roles) do
    local candidate_rank = ROLE_RANK[role] or 0
    if candidate_rank > rank or (candidate_rank == rank and tostring(role) < tostring(best)) then
      best, rank = role, candidate_rank
    end
  end
  if visual and visual.role and (ROLE_RANK[visual.role] or 0) > rank then
    best = visual.role
  elseif not best and wall_present then
    best = "wall"
  end
  return best
end

local function sorted_hits(cell)
  local result = {}
  for _, hit in pairs(cell.hits_by_key) do
    result[#result + 1] = hit
  end
  table.sort(result, function(a, b)
    if a.priority ~= b.priority then return a.priority < b.priority end
    if a.order ~= b.order then return a.order < b.order end
    if (a.id or "") ~= (b.id or "") then return (a.id or "") < (b.id or "") end
    return (a.type or "") < (b.type or "")
  end)
  return result
end

local function resolve_cells(context)
  local lines = {}
  local offsets = {}
  local hit_map = {}
  local roles = {}
  local colors = {}
  local resolved_cells = {}
  for row = 1, context.height do
    local characters = {}
    hit_map[row] = {}
    roles[row] = {}
    colors[row] = {}
    resolved_cells[row] = {}
    for column = 1, context.width do
      local cell = context.grid[row][column]
      local best_visual
      for i = 1, #cell.visuals do
        if visual_wins(cell.visuals[i], best_visual) then best_visual = cell.visuals[i] end
      end
      local wall_present = cell.wall_mask ~= 0
      local wall_candidate = wall_present
          and {
            char = context.glyphs.wall[cell.wall_mask],
            layer = 50,
            role = "wall",
            order = 0,
            serial = 0,
          }
        or nil
      if wall_candidate and visual_wins(wall_candidate, best_visual) then best_visual = wall_candidate end
      local character = best_visual and best_visual.char or " "
      -- Glyphs were validated up front; sanitized labels are one cell as well.
      characters[column] = character
      local role = best_role(cell, best_visual, wall_present)
      local resolved_color = cell.colors and cell.colors[role] or nil
      roles[row][column] = role
      colors[row][column] = resolved_color
      hit_map[row][column] = sorted_hits(cell)
      resolved_cells[row][column] = {
        char = character,
        role = role,
        color = resolved_color,
        wall_mask = cell.wall_mask,
        critical = cell.critical,
        hits = hit_map[row][column],
      }
    end
    lines[row] = table.concat(characters)
    offsets[row] = text.byte_offsets(characters)
  end
  return lines, offsets, hit_map, roles, colors, resolved_cells
end

local function highlight_spans(roles, colors, offsets, width, height)
  local spans = {}
  for row = 1, height do
    local start_column = 1
    local role = roles[row][1]
    local color_value = colors[row][1]
    for column = 2, width + 1 do
      local next_role = column <= width and roles[row][column] or nil
      local next_color = column <= width and colors[row][column] or nil
      if next_role ~= role or next_color ~= color_value then
        if role then
          spans[#spans + 1] = {
            row = row,
            start_cell = start_column,
            end_cell = column,
            start_col = offsets[row][start_column],
            end_col = offsets[row][column],
            role = role,
            color = color_value,
          }
        end
        start_column = column
        role = next_role
        color_value = next_color
      end
    end
  end
  return spans
end

local function append_scene_warnings(target, scene)
  if type(scene.warnings) == "table" then
    for i = 1, #scene.warnings do
      target[#target + 1] = scene.warnings[i]
    end
  end
end

---Rasterize a semantic scene into complete fixed-display-width lines.
---@param scene table
---@param viewport table
---@param opts table width and height are required logical dimensions.
---@return table
function M.rasterize(scene, viewport, opts)
  scene = scene or { primitives = {}, warnings = {} }
  opts = opts or {}
  assert(viewport_module.valid(viewport), "invalid viewport")
  local width = math.max(1, math.floor(assert(opts.width or opts.columns, "raster width is required")))
  local height = math.max(1, math.floor(assert(opts.height or opts.rows, "raster height is required")))
  local width_fn = opts.width_fn or text.default_width
  local custom = opts.glyphs or opts.glyph_set
  local glyphs, glyph_warning = glyph_module.resolve(opts.glyph_mode or opts.unicode or "auto", custom, width_fn)
  local context = {
    width = width,
    height = height,
    viewport = viewport,
    grid = new_grid(width, height),
    glyphs = glyphs,
    width_fn = width_fn,
    serial = 0,
    warnings = {},
    max_label_cells = math.max(1, math.floor(opts.max_label_cells or 32)),
    max_label_source_cells = math.min(4096, math.max(32, math.floor(opts.max_label_source_cells or 256))),
  }
  if glyph_warning then
    context.warnings[#context.warnings + 1] = {
      code = "GLYPH_FALLBACK_ASCII",
      message = glyph_warning,
    }
  end
  append_scene_warnings(context.warnings, scene)

  local labels_to_draw = {}
  local primitives = type(scene.primitives) == "table" and scene.primitives or {}
  for i = 1, #primitives do
    local primitive = primitives[i]
    if type(primitive) == "table" then
      if primitive.kind == "grid" then
        draw_grid(context, primitive)
      elseif primitive.kind == "room_interior" then
        draw_interior(context, primitive, "interior")
      elseif primitive.kind == "sun_patch" then
        draw_sun_patch(context, primitive)
      elseif primitive.kind == "sun_exposure" then
        draw_sun_exposure(context, primitive)
      elseif primitive.kind == "furniture_interior" then
        draw_interior(context, primitive, "interior")
      elseif primitive.kind == "furniture_outline" then
        draw_furniture_outline(context, primitive)
      elseif primitive.kind == "door_swing" then
        draw_door_swing(context, primitive)
      elseif primitive.kind == "wall" then
        draw_wall(context, primitive)
      elseif primitive.kind == "door_aperture" then
        draw_door_aperture(context, primitive)
      elseif primitive.kind == "window_aperture" then
        draw_window_aperture(context, primitive)
      elseif primitive.kind == "outlet_marker" then
        draw_outlet_marker(context, primitive)
      elseif primitive.kind == "door_leaf" then
        draw_door_leaf(context, primitive)
      elseif primitive.kind == "door_hinge" then
        draw_door_hinge(context, primitive)
      elseif primitive.kind == "annotation" then
        draw_annotation(context, primitive)
      elseif primitive.kind == "snap_guide" then
        draw_snap_guide(context, primitive)
      elseif primitive.kind == "snap_overlap" then
        draw_snap_overlap(context, primitive)
      elseif primitive.kind == "label" or primitive.kind == "dimension" then
        labels_to_draw[#labels_to_draw + 1] = { primitive = primitive, scene_index = i }
      end
    end
  end

  -- Names reserve space before measurements, and higher-priority measurements
  -- (doors/furniture) reserve before wall measurements. This prevents later
  -- labels from overwriting earlier ones while keeping placement deterministic.
  table.sort(labels_to_draw, function(left, right)
    local left_kind = left.primitive.kind == "label" and 0 or 1
    local right_kind = right.primitive.kind == "label" and 0 or 1
    if left_kind ~= right_kind then return left_kind < right_kind end
    local left_priority = left.primitive.priority or 0
    local right_priority = right.primitive.priority or 0
    if left_priority ~= right_priority then return left_priority > right_priority end
    if (left.primitive.order or 0) ~= (right.primitive.order or 0) then
      return (left.primitive.order or 0) < (right.primitive.order or 0)
    end
    return left.scene_index < right.scene_index
  end)
  for i = 1, #labels_to_draw do
    draw_label(context, labels_to_draw[i].primitive)
  end

  local lines, byte_offsets, hit_map, roles, colors, cells = resolve_cells(context)
  return {
    width = width,
    height = height,
    lines = lines,
    byte_offsets = byte_offsets,
    hit_map = hit_map,
    roles = roles,
    colors = colors,
    cells = cells,
    highlight_spans = highlight_spans(roles, colors, byte_offsets, width, height),
    warnings = context.warnings,
    glyph_mode = glyphs.mode,
    glyphs = glyphs,
    viewport = viewport_module.copy(viewport),
  }
end

M.render = M.rasterize
M.round = round
M.clip_line = clip_line

return M
