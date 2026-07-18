-- Canonical-model to semantic-scene extraction.  This module is intentionally
-- independent from Neovim and from the model/action implementation.

local footprint = require("roomplan.geometry.footprint")
local walls = require("roomplan.scene.walls")
local labels = require("roomplan.scene.labels")
local color = require("roomplan.color")
local canvas_detail = require("roomplan.canvas_detail")

local M = {}

M.layers = {
  grid = 10,
  room_interior = 20,
  furniture = 30,
  door_swing = 40,
  wall = 50,
  door = 60,
  window = 61,
  outlet = 62,
  label = 70,
  diagnostic = 80,
  guide = 85,
  snap_overlap = 88,
  selection = 90,
}

local ROLE_RANK = {
  error = 30,
  warning = 20,
  selected = 10,
}

local function finite(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function spatial_ref(kind, object, order, context)
  return {
    type = kind,
    id = object.id,
    order = order,
    context = context,
  }
end

local function key_for_ref(ref)
  if type(ref) ~= "table" or type(ref.id) ~= "string" then
    return nil
  end
  return (ref.type or ref.kind or "") .. "\0" .. ref.id
end

local function role_max(a, b)
  if not a then
    return b
  end
  if not b then
    return a
  end
  if (ROLE_RANK[b] or 0) > (ROLE_RANK[a] or 0) then
    return b
  end
  return a
end

local function normalize_severity(value)
  value = type(value) == "string" and value:lower() or ""
  if value == "error" or value == "fatal" or value == "structural" then
    return "error"
  end
  if value == "warning" or value == "warn" then
    return "warning"
  end
  return nil
end

local function diagnostics_array(validation)
  if type(validation) ~= "table" then
    return {}
  end
  if type(validation.diagnostics) == "table" then
    return validation.diagnostics
  end
  if type(validation.items) == "table" then
    return validation.items
  end
  return validation
end

local function add_role(roles, ref, role)
  local key = key_for_ref(ref)
  if key and role then
    roles[key] = role_max(roles[key], role)
    -- Some validators identify only an ID.  Keep an ID-only shadow key so
    -- their diagnostics remain useful without weakening typed hit references.
    roles["\0" .. ref.id] = role_max(roles["\0" .. ref.id], role)
  end
end

local function diagnostic_roles(validation, selected)
  local roles = {}
  local diagnostics = diagnostics_array(validation)
  for i = 1, #diagnostics do
    local diagnostic = diagnostics[i]
    if type(diagnostic) == "table" then
      local role = normalize_severity(diagnostic.severity or diagnostic.level)
      if role then
        if type(diagnostic.ref) == "table" then
          add_role(roles, diagnostic.ref, role)
        end
        if type(diagnostic.object_ref) == "table" then
          add_role(roles, diagnostic.object_ref, role)
        end
        if type(diagnostic.object) == "table" then
          add_role(roles, diagnostic.object, role)
        end
        local id = diagnostic.object_id or diagnostic.id
        if type(id) == "string" then
          local ref = { type = diagnostic.object_type or diagnostic.type, id = id }
          add_role(roles, ref, role)
        end
        local refs = diagnostic.refs or diagnostic.related_refs or diagnostic.related
        if type(refs) == "table" then
          for j = 1, #refs do
            if type(refs[j]) == "table" then
              add_role(roles, refs[j], role)
            elseif type(refs[j]) == "string" then
              add_role(roles, { id = refs[j] }, role)
            end
          end
        end
      end
    end
  end

  if type(selected) == "string" then
    roles["\0" .. selected] = role_max(roles["\0" .. selected], "selected")
  elseif type(selected) == "table" then
    add_role(roles, selected, "selected")
  end
  return roles
end

local function role_for(roles, ref, refs)
  local role
  if ref then
    role = role_max(role, roles[key_for_ref(ref)])
    role = role_max(role, roles["\0" .. tostring(ref.id or "")])
  end
  if refs then
    for i = 1, #refs do
      role = role_max(role, roles[key_for_ref(refs[i])])
      role = role_max(role, roles["\0" .. tostring(refs[i].id or "")])
    end
  end
  return role
end

local function bbox_new()
  return {
    left = nil,
    bottom = nil,
    right = nil,
    top = nil,
    empty = true,
  }
end

local function bbox_point(box, x, y)
  if not finite(x) or not finite(y) then
    return
  end
  if box.empty then
    box.left, box.right, box.bottom, box.top = x, x, y, y
    box.empty = false
    return
  end
  box.left = math.min(box.left, x)
  box.right = math.max(box.right, x)
  box.bottom = math.min(box.bottom, y)
  box.top = math.max(box.top, y)
end

local function bbox_rect(box, left, bottom, right, top)
  bbox_point(box, left, bottom)
  bbox_point(box, right, top)
end

local function add_primitive(scene, primitive, roles)
  primitive.layer = primitive.layer or 0
  primitive.role = role_max(primitive.role, role_for(roles, primitive.ref, primitive.refs))
  primitive.order = primitive.order or (primitive.ref and primitive.ref.order) or 0
  scene.primitives[#scene.primitives + 1] = primitive
  return primitive
end

local function add_snap_guides(scene, roles, snap_guides)
  if scene.bounds.empty then return end
  local guide_lines = {}
  for index, guide in ipairs(snap_guides or {}) do
    local primitive = {
      kind = "snap_guide",
      layer = M.layers.guide,
      role = "snap",
      order = index,
      target_label = guide.target_label,
    }
    if guide.axis == "x" then
      local padding = math.max(1, (scene.bounds.top - scene.bounds.bottom) * 0.08)
      primitive.x1, primitive.y1 = guide.value_mm, scene.bounds.bottom - padding
      primitive.x2, primitive.y2 = guide.value_mm, scene.bounds.top + padding
    elseif guide.axis == "y" then
      local padding = math.max(1, (scene.bounds.right - scene.bounds.left) * 0.08)
      primitive.x1, primitive.y1 = scene.bounds.left - padding, guide.value_mm
      primitive.x2, primitive.y2 = scene.bounds.right + padding, guide.value_mm
    end
    local line_key = tostring(guide.axis) .. ":" .. tostring(guide.value2 or guide.value_mm)
    if primitive.x1 and not guide_lines[line_key] then
      guide_lines[line_key] = true
      add_primitive(scene, primitive, roles)
    end
    if guide.overlap_start_mm and guide.overlap_finish_mm then
      local overlap = {
        kind = "snap_overlap",
        layer = M.layers.snap_overlap,
        role = "snap_overlap",
        order = index,
        target_label = guide.target_label,
      }
      if guide.axis == "x" then
        overlap.x1, overlap.y1 = guide.value_mm, guide.overlap_start_mm
        overlap.x2, overlap.y2 = guide.value_mm, guide.overlap_finish_mm
      else
        overlap.x1, overlap.y1 = guide.overlap_start_mm, guide.value_mm
        overlap.x2, overlap.y2 = guide.overlap_finish_mm, guide.value_mm
      end
      add_primitive(scene, overlap, roles)
    end
  end
end

local function add_measurement(scene, roles, measurement)
  local closest = measurement and measurement.closest
  if not closest or not closest.from or not closest.to then
    return
  end
  local from, to = closest.from, closest.to
  add_primitive(scene, {
    kind = "snap_guide",
    layer = M.layers.guide,
    role = "snap",
    order = 1000000,
    x1 = from[1],
    y1 = from[2],
    x2 = to[1],
    y2 = to[2],
    target_label = "Measured clearance",
  }, roles)
  add_primitive(
    scene,
    labels.at(
      require("roomplan.geometry.measurement").format_mm(measurement.nearest_mm),
      (from[1] + to[1]) / 2,
      (from[2] + to[2]) / 2,
      { role = "snap", layer = M.layers.guide, priority = 100, order = 1000000 }
    ),
    roles
  )
end

local function valid_furniture(item, room)
  if not (type(item) == "table"
    and type(item.id) == "string"
    and room ~= nil)
  then
    return false
  end
  if item.footprint ~= nil then
    return footprint.from_furniture(room, item, { rotation_fallback = 0 }) ~= nil
  end
  return type(item.center_mm) == "table"
    and type(item.size_mm) == "table"
    and finite(item.center_mm[1])
    and finite(item.center_mm[2])
    and finite(item.size_mm[1])
    and finite(item.size_mm[2])
    and item.size_mm[1] > 0
    and item.size_mm[2] > 0
end

local function geometry_bounds(shape)
  local bounds = shape and footprint.bounds(shape) or nil
  if not bounds then return nil end
  return {
    left = bounds.left,
    right = bounds.right,
    bottom = bounds.bottom,
    top = bounds.top,
    center_x = bounds.center_x,
    center_y = bounds.center_y,
  }
end

local function shape_rectangles(shape)
  local result = {}
  for index, part in ipairs(shape.parts) do
    result[index] = {
      left = part.left2 / 2,
      bottom = part.bottom2 / 2,
      right = part.right2 / 2,
      top = part.top2 / 2,
      part_id = part.id,
    }
  end
  return result
end

local function furniture_geometry(item, room)
  -- Scene extraction is intentionally tolerant of repair drafts. Preserve the
  -- historical unrotated fallback for a malformed rotation while deriving all
  -- valid geometry through the shared footprint adapter.
  local shape = footprint.from_furniture(room, item, { rotation_fallback = 0 })
  if shape then
    return geometry_bounds(shape), shape
  end

  -- Non-canonical repair drafts historically still rendered when their 2D
  -- values were finite. Keep that fallback outside the exact geometry layer.
  local width, depth = item.size_mm[1], item.size_mm[2]
  if item.rotation_deg == 90 or item.rotation_deg == 270 then width, depth = depth, width end
  local center_x = room.origin_mm[1] + item.center_mm[1]
  local center_y = room.origin_mm[2] + item.center_mm[2]
  return {
    left = center_x - width / 2,
    right = center_x + width / 2,
    bottom = center_y - depth / 2,
    top = center_y + depth / 2,
    center_x = center_x,
    center_y = center_y,
  }, nil
end

local function room_geometry(room)
  if not walls.valid_room_geometry(room) then return nil end
  local shape = footprint.from_room(room)
  if shape then return geometry_bounds(shape), shape end
  local left, bottom = room.origin_mm[1], room.origin_mm[2]
  local right, top = left + room.size_mm[1], bottom + room.size_mm[2]
  local bounds = {
    left = left,
    bottom = bottom,
    right = right,
    top = top,
    width = right - left,
    depth = top - bottom,
    center_x = (left + right) / 2,
    center_y = (bottom + top) / 2,
  }
  return bounds, nil
end

local function furniture_bounds(item, room)
  local bounds = furniture_geometry(item, room)
  return bounds
end

local INWARD = {
  north = { 0, -1 },
  south = { 0, 1 },
  east = { -1, 0 },
  west = { 1, 0 },
}

local function rotate(vector_x, vector_y, radians)
  local cosine = math.cos(radians)
  local sine = math.sin(radians)
  return vector_x * cosine - vector_y * sine, vector_x * sine + vector_y * cosine
end

local function door_swing(aperture)
  local door = aperture.door
  if not aperture.owner_edge_valid or type(door) ~= "table" then
    return nil
  end

  local hinge_at_start = door.hinge ~= "end"
  local hinge = hinge_at_start and aperture.p0 or aperture.p1
  local other = hinge_at_start and aperture.p1 or aperture.p0
  local vector_x = other[1] - hinge[1]
  local vector_y = other[2] - hinge[2]
  local target = INWARD[door.side]
  if not target then
    return nil
  end
  if door.opens_into ~= "owner" then
    target = { -target[1], -target[2] }
  end

  -- The derivative of a positive (CCW) rotation is (-vy, vx).  Choose the
  -- sign whose initial motion has a positive component in the target half-plane.
  local positive_score = -vector_y * target[1] + vector_x * target[2]
  local sign = positive_score >= 0 and 1 or -1
  local angle = finite(door.open_angle_deg) and door.open_angle_deg or 90
  angle = math.max(1, math.min(180, angle))
  local sweep_deg = sign * angle
  local open_x, open_y = rotate(vector_x, vector_y, math.rad(sweep_deg))
  local radius = math.sqrt(vector_x * vector_x + vector_y * vector_y)

  return {
    hinge_x = hinge[1],
    hinge_y = hinge[2],
    closed_x = other[1],
    closed_y = other[2],
    open_x = hinge[1] + open_x,
    open_y = hinge[2] + open_y,
    radius = radius,
    start_angle_deg = math.deg(math.atan2(vector_y, vector_x)),
    sweep_deg = sweep_deg,
  }
end

local function normalize_angle(angle)
  angle = angle % 360
  if angle < 0 then
    angle = angle + 360
  end
  return angle
end

local function angle_in_sweep(candidate, start_angle, sweep)
  candidate = normalize_angle(candidate)
  start_angle = normalize_angle(start_angle)
  if sweep >= 0 then
    return normalize_angle(candidate - start_angle) <= sweep + 1e-9
  end
  return normalize_angle(start_angle - candidate) <= -sweep + 1e-9
end

local function bbox_swing(box, swing)
  bbox_point(box, swing.hinge_x, swing.hinge_y)
  bbox_point(box, swing.closed_x, swing.closed_y)
  bbox_point(box, swing.open_x, swing.open_y)
  for _, angle in ipairs({ 0, 90, 180, 270 }) do
    if angle_in_sweep(angle, swing.start_angle_deg, swing.sweep_deg) then
      local radians = math.rad(angle)
      bbox_point(
        box,
        swing.hinge_x + swing.radius * math.cos(radians),
        swing.hinge_y + swing.radius * math.sin(radians)
      )
    end
  end
end

local function diagnostic_role_for_id(roles, kind, id)
  return role_for(roles, { type = kind, id = id })
end

local function annotation_character(role)
  if role == "error" then
    return "!"
  elseif role == "warning" then
    return "?"
  end
  return nil
end

---Build a semantic scene from the canonical model and validation result.
---@param model table
---@param validation table|nil
---@param opts table|nil
---@return table
function M.build(model, validation, opts)
  model = type(model) == "table" and model or {}
  opts = opts or {}
  local detail_level = canvas_detail.normalize(opts.detail_level) or canvas_detail.default
  local show_labels = detail_level ~= "none"
  local high_detail = detail_level == "high"
  local rooms = type(model.rooms) == "table" and model.rooms or {}
  local doors = type(model.doors) == "table" and model.doors or {}
  local windows = type(model.windows) == "table" and model.windows or {}
  local outlets = type(model.outlets) == "table" and model.outlets or {}
  local furniture = type(model.furniture) == "table" and model.furniture or {}
  local roles = diagnostic_roles(validation, opts.selected or opts.selected_ref or opts.selected_id)
  local template_edit = opts.shape_edit and opts.shape_edit.kind == "template"
  local wall_scene = template_edit and walls.build({}, {}, {}, {})
    or walls.build(rooms, doors, windows, outlets)
  local scene = {
    primitives = {},
    bounds = bbox_new(),
    warnings = {},
    objects = {},
    wall_data = wall_scene,
  }
  local object_points = {}
  local dimension_edges = {}

  -- Project templates have no plan position. During direct shape editing they
  -- therefore receive a deliberately isolated local-coordinate preview rather
  -- than being placed into an arbitrary room or overlaid on the floor plan.
  if template_edit then
    local edit = opts.shape_edit
    if opts.show_grid then
      add_primitive(scene, {
        kind = "grid",
        layer = M.layers.grid,
        spacing_mm = opts.grid_mm or (model.settings and model.settings.grid_mm) or 100,
        role = "grid",
      }, roles)
    end
    local shape, shape_err = footprint.from_persisted(edit.footprint)
    if not shape then
      scene.warnings[#scene.warnings + 1] = {
        code = "SCENE_TEMPLATE_SKIPPED",
        object_id = edit.entity_id,
        message = shape_err and shape_err.message or "Project template geometry cannot be rendered safely",
      }
      return scene
    end
    local template
    for _, candidate in ipairs(model.custom_templates or {}) do
      if candidate.id == edit.entity_id then template = candidate; break end
    end
    template = template or { id = edit.entity_id, name = edit.entity_id }
    local bounds = geometry_bounds(shape)
    local ref = spatial_ref("template", template, 1, "preview")
    scene.objects[1] = ref
    bbox_rect(scene.bounds, bounds.left, bounds.bottom, bounds.right, bounds.top)
    local rectangles = shape_rectangles(shape)
    for part_index, rectangle in ipairs(rectangles) do
      local selected = edit.selected_part_id == rectangle.part_id
      add_primitive(scene, {
        kind = "furniture_interior",
        layer = M.layers.furniture,
        left = rectangle.left,
        bottom = rectangle.bottom,
        right = rectangle.right,
        top = rectangle.top,
        part_id = rectangle.part_id,
        part_index = part_index,
        ref = ref,
        role = selected and "selected" or nil,
      }, roles)
      add_primitive(scene, {
        kind = "furniture_outline",
        layer = M.layers.furniture + 1,
        left = rectangle.left,
        bottom = rectangle.bottom,
        right = rectangle.right,
        top = rectangle.top,
        part_id = rectangle.part_id,
        part_index = part_index,
        ref = ref,
        role = selected and "selected" or nil,
      }, roles)
    end
    if show_labels then
      add_primitive(scene, labels.furniture(template, bounds, ref, 1, footprint.label_anchor(shape)), roles)
    end
    if high_detail then
      for _, dimension in ipairs(labels.furniture_dimensions(bounds, ref, 1)) do
        add_primitive(scene, dimension, roles)
      end
    end
    add_snap_guides(scene, roles, opts.snap_guides or edit.snap_guides)
    return scene
  end

  local function dimension_edge_key(edge)
    return table.concat({
      edge.orientation,
      string.format("%.17g", edge.fixed),
      string.format("%.17g", edge.start),
      string.format("%.17g", edge.finish),
    }, ":")
  end

  if opts.show_grid then
    add_primitive(scene, {
      kind = "grid",
      layer = M.layers.grid,
      spacing_mm = opts.grid_mm or (model.settings and model.settings.grid_mm) or 100,
      role = "grid",
    }, roles)
  end

  for i = 1, #rooms do
    local room = rooms[i]
    local bounds, shape = room_geometry(room)
    if bounds then
      local ref = spatial_ref("room", room, i, "interior")
      scene.objects[#scene.objects + 1] = ref
      local anchor = shape and footprint.label_anchor(shape) or nil
      object_points[room.id] = {
        anchor and anchor.x or bounds.center_x,
        anchor and anchor.y or bounds.center_y,
        ref,
      }
      bbox_rect(scene.bounds, bounds.left, bounds.bottom, bounds.right, bounds.top)
      local rectangles = room.footprint ~= nil and shape_rectangles(shape) or { bounds }
      for part_index, rectangle in ipairs(rectangles) do
        local shape_selected = opts.shape_edit
          and (opts.shape_edit.kind or "room") == "room"
          and opts.shape_edit.room_id == room.id
          and opts.shape_edit.selected_part_id == rectangle.part_id
        add_primitive(scene, {
          kind = "room_interior",
          layer = M.layers.room_interior,
          left = rectangle.left,
          bottom = rectangle.bottom,
          right = rectangle.right,
          top = rectangle.top,
          part_id = rectangle.part_id,
          part_index = room.footprint ~= nil and part_index or nil,
          ref = ref,
          role = shape_selected and "selected" or nil,
        }, roles)
      end
      if show_labels then
        local room_label = labels.room(room, ref, i, room.footprint ~= nil and {
          bounds = bounds,
          anchor = anchor,
          rectangles = rectangles,
        } or nil)
        room_label.color = color.resolve(room.color)
        add_primitive(scene, room_label, roles)
      end
      if show_labels then
        for _, edge in ipairs(walls.room_edges(room, i)) do
          local key = dimension_edge_key(edge)
          if not dimension_edges[key] then
            dimension_edges[key] = true
            add_primitive(scene, labels.edge_dimension(edge, edge.ref, i, 10), roles)
          end
        end
      end
    else
      scene.warnings[#scene.warnings + 1] = {
        code = "SCENE_ROOM_SKIPPED",
        object_id = type(room) == "table" and room.id or nil,
        message = "Room geometry cannot be rendered safely",
      }
    end
  end

  for i = 1, #furniture do
    local item = furniture[i]
    local room = type(item) == "table" and wall_scene.rooms_by_id[item.room_id] or nil
    if valid_furniture(item, room) then
      local ref = spatial_ref("furniture", item, i, "interior")
      local bounds, shape = furniture_geometry(item, room)
      if bounds then
        scene.objects[#scene.objects + 1] = ref
        local anchor = shape and footprint.label_anchor(shape) or nil
        object_points[item.id] = {
          anchor and anchor.x or bounds.center_x,
          anchor and anchor.y or bounds.center_y,
          ref,
        }
        bbox_rect(scene.bounds, bounds.left, bounds.bottom, bounds.right, bounds.top)
        local rectangles = item.footprint ~= nil and shape_rectangles(shape) or { bounds }
        for part_index, rectangle in ipairs(rectangles) do
          local shape_selected = opts.shape_edit
            and opts.shape_edit.kind == "furniture"
            and opts.shape_edit.entity_id == item.id
            and opts.shape_edit.selected_part_id == rectangle.part_id
          add_primitive(scene, {
            kind = "furniture_interior",
            layer = M.layers.furniture,
            left = rectangle.left,
            bottom = rectangle.bottom,
            right = rectangle.right,
            top = rectangle.top,
            part_id = rectangle.part_id,
            part_index = item.footprint ~= nil and part_index or nil,
            ref = ref,
            role = shape_selected and "selected" or nil,
          }, roles)
          add_primitive(scene, {
            kind = "furniture_outline",
            layer = M.layers.furniture + 1,
            left = rectangle.left,
            bottom = rectangle.bottom,
            right = rectangle.right,
            top = rectangle.top,
            part_id = rectangle.part_id,
            part_index = item.footprint ~= nil and part_index or nil,
            ref = ref,
            color = color.resolve(item.color),
            role = shape_selected and "selected" or nil,
          }, roles)
        end
        if show_labels then
          local furniture_label = labels.furniture(item, bounds, ref, i, anchor)
          furniture_label.color = color.resolve(item.color)
          add_primitive(scene, furniture_label, roles)
        end
        if high_detail then
          local dimensions = labels.furniture_dimensions(bounds, ref, i)
          for dimension_index = 1, #dimensions do
            add_primitive(scene, dimensions[dimension_index], roles)
          end
        end
      else
        scene.warnings[#scene.warnings + 1] = {
          code = "SCENE_FURNITURE_SKIPPED",
          object_id = item.id,
          message = "Furniture geometry or owner cannot be rendered safely",
        }
      end
    else
      scene.warnings[#scene.warnings + 1] = {
        code = "SCENE_FURNITURE_SKIPPED",
        object_id = type(item) == "table" and item.id or nil,
        message = "Furniture geometry or owner cannot be rendered safely",
      }
    end
  end

  for i = 1, #wall_scene.segments do
    local segment = wall_scene.segments[i]
    add_primitive(scene, {
      kind = "wall",
      layer = M.layers.wall,
      x1 = segment.x1,
      y1 = segment.y1,
      x2 = segment.x2,
      y2 = segment.y2,
      orientation = segment.orientation,
      refs = segment.refs,
      contributors = segment.contributors,
      order = i,
    }, roles)
    bbox_point(scene.bounds, segment.x1, segment.y1)
    bbox_point(scene.bounds, segment.x2, segment.y2)
  end

  for i = 1, #wall_scene.apertures do
    local aperture = wall_scene.apertures[i]
    if aperture.owner_edge_valid then
      local ref = aperture.ref
      ref.context = "aperture"
      scene.objects[#scene.objects + 1] = ref
      local midpoint_x = (aperture.p0[1] + aperture.p1[1]) / 2
      local midpoint_y = (aperture.p0[2] + aperture.p1[2]) / 2
      object_points[aperture.id] = { midpoint_x, midpoint_y, ref }
      add_primitive(scene, {
        kind = "door_aperture",
        layer = M.layers.door,
        x1 = aperture.p0[1],
        y1 = aperture.p0[2],
        x2 = aperture.p1[1],
        y2 = aperture.p1[2],
        ref = ref,
        connection_valid = aperture.connection_valid,
        connection_requested = aperture.connection_requested,
      }, roles)
      if high_detail then
        add_primitive(scene, labels.door_dimension(aperture, ref, i), roles)
      end

      local swing = door_swing(aperture)
      if swing then
        bbox_swing(scene.bounds, swing)
        add_primitive(scene, {
          kind = "door_swing",
          layer = M.layers.door_swing,
          cx = swing.hinge_x,
          cy = swing.hinge_y,
          radius = swing.radius,
          start_angle_deg = swing.start_angle_deg,
          sweep_deg = swing.sweep_deg,
          ref = ref,
        }, roles)
        add_primitive(scene, {
          kind = "door_leaf",
          layer = M.layers.door,
          x1 = swing.hinge_x,
          y1 = swing.hinge_y,
          x2 = swing.open_x,
          y2 = swing.open_y,
          ref = ref,
        }, roles)
        add_primitive(scene, {
          kind = "door_hinge",
          layer = M.layers.door + 1,
          x = swing.hinge_x,
          y = swing.hinge_y,
          ref = ref,
        }, roles)
      end
      bbox_point(scene.bounds, aperture.p0[1], aperture.p0[2])
      bbox_point(scene.bounds, aperture.p1[1], aperture.p1[2])
    else
      scene.warnings[#scene.warnings + 1] = {
        code = "SCENE_DOOR_SKIPPED",
        object_id = aperture.id,
        message = aperture.reason or "Door aperture cannot be rendered safely",
      }
    end
  end

  for i = 1, #wall_scene.window_apertures do
    local aperture = wall_scene.window_apertures[i]
    if aperture.owner_edge_valid then
      local ref = aperture.ref
      ref.context = "aperture"
      scene.objects[#scene.objects + 1] = ref
      local midpoint_x = (aperture.p0[1] + aperture.p1[1]) / 2
      local midpoint_y = (aperture.p0[2] + aperture.p1[2]) / 2
      object_points[aperture.id] = { midpoint_x, midpoint_y, ref }
      add_primitive(scene, {
        kind = "window_aperture",
        layer = M.layers.window,
        x1 = aperture.p0[1],
        y1 = aperture.p0[2],
        x2 = aperture.p1[1],
        y2 = aperture.p1[2],
        ref = ref,
        connection_valid = aperture.connection_valid,
        connection_requested = aperture.connection_requested,
      }, roles)
      if high_detail then
        add_primitive(scene, labels.opening_dimension(aperture, ref, i), roles)
      end
      bbox_point(scene.bounds, aperture.p0[1], aperture.p0[2])
      bbox_point(scene.bounds, aperture.p1[1], aperture.p1[2])
    else
      scene.warnings[#scene.warnings + 1] = {
        code = "SCENE_WINDOW_SKIPPED",
        object_id = aperture.id,
        message = aperture.reason or "Window aperture cannot be rendered safely",
      }
    end
  end

  for i = 1, #wall_scene.outlet_markers do
    local marker = wall_scene.outlet_markers[i]
    if marker.owner_edge_valid then
      local ref = marker.ref
      ref.context = "marker"
      scene.objects[#scene.objects + 1] = ref
      object_points[marker.id] = { marker.p[1], marker.p[2], ref }
      add_primitive(scene, {
        kind = "outlet_marker",
        layer = M.layers.outlet,
        x = marker.p[1],
        y = marker.p[2],
        orientation = marker.orientation,
        placement = marker.placement,
        side = marker.side,
        ref = ref,
      }, roles)
      if show_labels then
        add_primitive(scene, labels.outlet(marker.outlet, marker, ref, i), roles)
      end
      bbox_point(scene.bounds, marker.p[1], marker.p[2])
    else
      scene.warnings[#scene.warnings + 1] = {
        code = "SCENE_OUTLET_SKIPPED",
        object_id = marker.id,
        message = marker.reason or "Outlet marker cannot be rendered safely",
      }
    end
  end

  add_snap_guides(scene, roles, opts.snap_guides or (opts.shape_edit and opts.shape_edit.snap_guides))
  add_measurement(scene, roles, opts.measurement)

  -- Add textual diagnostic markers at deterministic object points.  The
  -- object's ordinary primitives already carry the same highlight role.
  local object_ids = {}
  for id in pairs(object_points) do
    object_ids[#object_ids + 1] = id
  end
  table.sort(object_ids)
  for object_index = 1, #object_ids do
    local id = object_ids[object_index]
    local point = object_points[id]
    local ref = point[3]
    local role = diagnostic_role_for_id(roles, ref.type, id)
    local marker = annotation_character(role)
    if marker then
      add_primitive(scene, {
        kind = "annotation",
        layer = M.layers.diagnostic,
        x = point[1],
        y = point[2],
        char = marker,
        role = role,
        ref = ref,
      }, roles)
    end
  end

  table.sort(scene.objects, function(a, b)
    local type_rank = { room = 1, door = 2, furniture = 3 }
    local ar = type_rank[a.type] or 99
    local br = type_rank[b.type] or 99
    if a.order ~= b.order then
      -- Model order is collection-local; type rank keeps cycling predictable.
      if ar == br then
        return a.order < b.order
      end
      return ar < br
    end
    if ar ~= br then
      return ar < br
    end
    return a.id < b.id
  end)

  return scene
end

M.extract = M.build
M.door_swing = door_swing
M.furniture_bounds = furniture_bounds

return M
