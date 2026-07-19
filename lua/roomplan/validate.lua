-- Pure, deterministic model validation. Schema decoding/normalization is the
-- first authority; structural checks here are deliberately defensive so model
-- actions cannot accidentally commit impossible primitives.

local adjacency = require("roomplan.geometry.adjacency")
local json = require("roomplan.codec.json")
local door_geometry = require("roomplan.geometry.door")
local footprint_geometry = require("roomplan.geometry.footprint")
local interval = require("roomplan.geometry.interval")
local number = require("roomplan.geometry.number")
local schema = require("roomplan.schema")
local sector = require("roomplan.geometry.sector")
local wall_attachment = require("roomplan.geometry.wall_attachment")

local M = {}

local function connected_id(attachment)
  local value = attachment and attachment.connects_to_room_id
  if value == nil or json.is_null(value) then return nil end
  return value
end

local builtin_templates = {
  ["builtin:bed"] = true,
  ["builtin:sofa"] = true,
  ["builtin:armchair"] = true,
  ["builtin:table"] = true,
  ["builtin:chair"] = true,
  ["builtin:desk"] = true,
  ["builtin:wardrobe"] = true,
  ["builtin:bookcase"] = true,
  ["builtin:cabinet"] = true,
  ["builtin:kitchen-unit"] = true,
  ["builtin:appliance"] = true,
  ["builtin:bathroom-fixture"] = true,
  ["builtin:custom-rectangle"] = true,
}

local kind_rank = {
  room = 1,
  door = 2,
  window = 3,
  outlet = 4,
  furniture = 5,
  template = 6,
  plan = 7,
  settings = 8,
}
local severity_rank = { error = 1, warning = 2, info = 3 }

local function object_ref(kind, id) return { kind = kind, id = id or "<unknown>" } end

local function diagnostic(code, severity, kind, id, message, related, details, structural)
  local result = {
    code = code,
    severity = severity,
    object = object_ref(kind, id),
    related = related or {},
    message = message,
    details = details or {},
    fix = nil,
  }
  if structural then result.structural = true end
  return result
end

local function append(target, value) target[#target + 1] = value end

local function append_geometry_problem(target, kind, entity, err)
  local id = entity and entity.id or "<unknown>"
  append(
    target,
    diagnostic("GEOMETRY_RANGE", "error", kind, id, id .. " exceeds the exact footprint geometry range", nil, {
      cause_code = err and err.code,
      cause_message = err and err.message,
      cause_details = err and err.details,
    })
  )
end

local function safe_footprint(target, kind, entity, build)
  local shape, shape_error = build()
  if not shape then
    append_geometry_problem(target, kind, entity, shape_error)
    return nil
  end
  local bounds, bounds_error = footprint_geometry.bounds2(shape)
  if not bounds then
    append_geometry_problem(target, kind, entity, bounds_error)
    return nil
  end
  return shape, bounds
end

local function valid_id(value)
  return type(value) == "string"
    and #value >= 1
    and #value <= 128
    and value:sub(1, 1):match("^[A-Za-z]$") ~= nil
    and (#value == 1 or value:sub(2):match("^[A-Za-z0-9._:-]+$") ~= nil)
end

local function prefixed_id(value, prefix) return valid_id(value) and value:sub(1, #prefix) == prefix end

local function valid_string(value) return type(value) == "string" and value ~= "" and not value:find("%z") end

local function valid_integer(value, minimum, maximum, coordinate)
  if not number.is_integer(value) then return false end
  if coordinate and math.abs(value) >= number.MAX_SAFE_COORDINATE then return false end
  if minimum ~= nil and value < minimum then return false end
  if maximum ~= nil and value > maximum then return false end
  return true
end

local function valid_vector(value, count, predicate)
  if type(value) ~= "table" then return false end
  local i
  for i = 1, count do
    if not predicate(value[i], i) then return false end
  end
  return true
end

local function structural_field(target, code, kind, id, message, details)
  append(target, diagnostic(code, "error", kind, id, message, nil, details, true))
end

local function schema_object(model, path)
  local collection, index
  if type(path) == "string" then
    collection, index = path:match("^%$%.([%a_]+)%[(%d+)%]")
  end
  local kinds = {
    rooms = "room",
    doors = "door",
    windows = "window",
    outlets = "outlet",
    furniture = "furniture",
    custom_templates = "template",
  }
  local values = collection and model[collection]
  local entity = type(values) == "table" and values[tonumber(index)] or nil
  local kind = kinds[collection] or (collection == "settings" and "settings") or "plan"
  local id = type(entity) == "table" and entity.id or (kind == "settings" and "settings") or "roomplan.nvim"
  return kind, id
end

local function versioned_structural(model)
  local valid, info = schema.validate_versioned(model)
  if valid then return {} end
  local result = {}
  local diagnostics = info and info.diagnostics or { info }
  for _, value in ipairs(diagnostics) do
    if value then
      local kind, id = schema_object(model, value.path)
      structural_field(
        result,
        value.code or "SCHEMA_INVALID",
        kind,
        id,
        (value.path and (value.path .. ": ") or "") .. (value.message or "invalid versioned model"),
        {
          path = value.path,
          value = value.value,
        }
      )
    end
  end
  return result
end

function M.structural(model)
  local result = {}
  if type(model) ~= "table" then
    structural_field(result, "INVALID_MODEL", "plan", "roomplan.nvim", "RoomPlan model root must be an object")
    return result
  end
  if type(model.schema_version) == "number" and model.schema_version >= 2 then return versioned_structural(model) end
  if model.format ~= "roomplan.nvim" then
    structural_field(result, "INVALID_FORMAT", "plan", "roomplan.nvim", "format must be exactly roomplan.nvim")
  end
  if model.schema_version ~= 1 then
    structural_field(
      result,
      "UNSUPPORTED_SCHEMA_VERSION",
      "plan",
      "roomplan.nvim",
      "schema_version is unsupported",
      { actual = model.schema_version }
    )
  end
  if model.units ~= "mm" then
    structural_field(result, "INVALID_UNITS", "plan", "roomplan.nvim", "units must be exactly mm")
  end

  local collections = {
    { key = "rooms", kind = "room", prefix = "room-" },
    { key = "doors", kind = "door", prefix = "door-" },
    { key = "furniture", kind = "furniture", prefix = "furniture-" },
    { key = "custom_templates", kind = "template", prefix = "custom:" },
  }
  local seen = {}
  local c, i
  for c = 1, #collections do
    local specification = collections[c]
    local values = model[specification.key]
    if type(values) ~= "table" then
      structural_field(
        result,
        "MISSING_COLLECTION",
        "plan",
        "roomplan.nvim",
        specification.key .. " must be an array",
        { collection = specification.key }
      )
    else
      for i = 1, #values do
        local entity = values[i]
        local fallback_id = specification.kind .. "[" .. i .. "]"
        if type(entity) ~= "table" then
          structural_field(
            result,
            "INVALID_ENTITY",
            specification.kind,
            fallback_id,
            fallback_id .. " must be an object"
          )
        else
          local id = type(entity.id) == "string" and entity.id or fallback_id
          if not prefixed_id(entity.id, specification.prefix) then
            structural_field(
              result,
              "INVALID_ID",
              specification.kind,
              id,
              id .. " does not satisfy the " .. specification.prefix .. " ID contract"
            )
          elseif seen[entity.id] then
            append(
              result,
              diagnostic(
                "DUPLICATE_ID",
                "error",
                specification.kind,
                entity.id,
                entity.id .. " duplicates a globally unique entity ID",
                { object_ref(seen[entity.id].kind, entity.id) },
                { first_kind = seen[entity.id].kind },
                true
              )
            )
          else
            seen[entity.id] = { kind = specification.kind, index = i }
          end
        end
      end
    end
  end

  for i = 1, #(type(model.rooms) == "table" and model.rooms or {}) do
    local room = model.rooms[i]
    if type(room) == "table" then
      local id = type(room.id) == "string" and room.id or "room[" .. i .. "]"
      if not valid_string(room.name) then
        structural_field(result, "INVALID_NAME", "room", id, id .. " must have a non-empty name")
      end
      if not valid_vector(room.origin_mm, 2, function(v) return valid_integer(v, nil, nil, true) end) then
        structural_field(result, "INVALID_COORDINATE", "room", id, id .. " origin_mm must contain two safe integers")
      end
      if not valid_vector(room.size_mm, 2, function(v) return valid_integer(v, 1, number.MAX_LOCAL_DIMENSION) end) then
        structural_field(
          result,
          "NON_POSITIVE_DIMENSION",
          "room",
          id,
          id .. " size_mm must contain two positive integer dimensions"
        )
      end
    end
  end

  local rotations = { [0] = true, [90] = true, [180] = true, [270] = true }
  for i = 1, #(type(model.furniture) == "table" and model.furniture or {}) do
    local furniture = model.furniture[i]
    if type(furniture) == "table" then
      local id = type(furniture.id) == "string" and furniture.id or "furniture[" .. i .. "]"
      if not prefixed_id(furniture.room_id, "room-") then
        structural_field(result, "INVALID_REFERENCE_SHAPE", "furniture", id, id .. " room_id must be a room-* ID")
      end
      if
        type(furniture.template_id) ~= "string"
        or (furniture.template_id:sub(1, 8) ~= "builtin:" and furniture.template_id:sub(1, 7) ~= "custom:")
      then
        structural_field(
          result,
          "INVALID_REFERENCE_SHAPE",
          "furniture",
          id,
          id .. " template_id must be a builtin:* or custom:* reference"
        )
      end
      if not valid_string(furniture.name) or not valid_string(furniture.category) then
        structural_field(result, "INVALID_NAME", "furniture", id, id .. " must have non-empty name and category fields")
      end
      if not valid_vector(furniture.center_mm, 2, function(v) return valid_integer(v, nil, nil, true) end) then
        structural_field(
          result,
          "INVALID_COORDINATE",
          "furniture",
          id,
          id .. " center_mm must contain two safe integers"
        )
      end
      if
        not valid_vector(furniture.size_mm, 3, function(v) return valid_integer(v, 1, number.MAX_LOCAL_DIMENSION) end)
      then
        structural_field(
          result,
          "NON_POSITIVE_DIMENSION",
          "furniture",
          id,
          id .. " size_mm must contain three positive integer dimensions"
        )
      end
      if not rotations[furniture.rotation_deg] then
        structural_field(
          result,
          "UNSUPPORTED_ROTATION",
          "furniture",
          id,
          id .. " rotation_deg must be 0, 90, 180, or 270"
        )
      end
    end
  end

  local sides = { north = true, east = true, south = true, west = true }
  local hinges = { start = true, ["end"] = true }
  local targets = { owner = true, connected = true, outside = true }
  for i = 1, #(type(model.doors) == "table" and model.doors or {}) do
    local door = model.doors[i]
    if type(door) == "table" then
      local id = type(door.id) == "string" and door.id or "door[" .. i .. "]"
      if door.kind ~= "hinged" then
        structural_field(result, "UNSUPPORTED_OBJECT_KIND", "door", id, id .. " kind must be hinged")
      end
      if not prefixed_id(door.room_id, "room-") then
        structural_field(result, "INVALID_REFERENCE_SHAPE", "door", id, id .. " room_id must be a room-* ID")
      end
      if
        door.connects_to_room_id ~= nil
        and not json.is_null(door.connects_to_room_id)
        and not prefixed_id(door.connects_to_room_id, "room-")
      then
        structural_field(
          result,
          "INVALID_REFERENCE_SHAPE",
          "door",
          id,
          id .. " connects_to_room_id must be null or a room-* ID"
        )
      end
      if not sides[door.side] or not hinges[door.hinge] or not targets[door.opens_into] then
        structural_field(result, "INVALID_ENUM", "door", id, id .. " has an unsupported side, hinge, or swing target")
      end
      if
        not valid_integer(door.offset_mm, 0, number.MAX_LOCAL_DIMENSION)
        or not valid_integer(door.width_mm, 1, number.MAX_LOCAL_DIMENSION)
      then
        structural_field(
          result,
          "INVALID_DOOR_APERTURE",
          "door",
          id,
          id .. " offset_mm and width_mm must be non-negative/positive integers"
        )
      end
      if not valid_integer(door.open_angle_deg, 1, 180) then
        structural_field(
          result,
          "INVALID_DOOR_ANGLE",
          "door",
          id,
          id .. " open_angle_deg must be an integer from 1 through 180"
        )
      end
    end
  end

  for i = 1, #(type(model.custom_templates) == "table" and model.custom_templates or {}) do
    local template = model.custom_templates[i]
    if type(template) == "table" then
      local id = type(template.id) == "string" and template.id or "template[" .. i .. "]"
      if not valid_string(template.name) or not valid_string(template.category) then
        structural_field(result, "INVALID_NAME", "template", id, id .. " must have non-empty name and category fields")
      end
      if template.shape ~= "rectangle" then
        structural_field(result, "UNSUPPORTED_OBJECT_KIND", "template", id, id .. " shape must be rectangle")
      end
      if
        not valid_vector(
          template.default_size_mm,
          3,
          function(v) return valid_integer(v, 1, number.MAX_LOCAL_DIMENSION) end
        )
      then
        structural_field(
          result,
          "NON_POSITIVE_DIMENSION",
          "template",
          id,
          id .. " default_size_mm must contain three positive integer dimensions"
        )
      end
    end
  end

  if model.settings ~= nil and type(model.settings) ~= "table" then
    structural_field(result, "INVALID_SETTINGS", "settings", "settings", "settings must be an object")
  elseif type(model.settings) == "table" then
    local keys = { "grid_mm", "fine_step_mm", "normal_step_mm", "coarse_step_mm", "default_door_width_mm" }
    for i = 1, #keys do
      local key = keys[i]
      if not valid_integer(model.settings[key], 1, number.MAX_LOCAL_DIMENSION) then
        structural_field(
          result,
          "INVALID_SETTING",
          "settings",
          "settings",
          "settings." .. key .. " must be a positive integer",
          { field = key }
        )
      end
    end
  end
  return result
end

local function build_indexes(model)
  local result = {
    rooms = {},
    room_order = {},
    doors = {},
    door_order = {},
    windows = {},
    window_order = {},
    outlets = {},
    outlet_order = {},
    furniture = {},
    furniture_order = {},
    templates = {},
  }
  local i
  for i = 1, #(model.rooms or {}) do
    result.rooms[model.rooms[i].id] = model.rooms[i]
    result.room_order[model.rooms[i].id] = i
  end
  for i = 1, #(model.doors or {}) do
    result.doors[model.doors[i].id] = model.doors[i]
    result.door_order[model.doors[i].id] = i
  end
  for i = 1, #(model.windows or {}) do
    result.windows[model.windows[i].id] = model.windows[i]
    result.window_order[model.windows[i].id] = i
  end
  for i = 1, #(model.outlets or {}) do
    result.outlets[model.outlets[i].id] = model.outlets[i]
    result.outlet_order[model.outlets[i].id] = i
  end
  for i = 1, #(model.furniture or {}) do
    result.furniture[model.furniture[i].id] = model.furniture[i]
    result.furniture_order[model.furniture[i].id] = i
  end
  for i = 1, #(model.custom_templates or {}) do
    result.templates[model.custom_templates[i].id] = model.custom_templates[i]
  end
  return result
end

local function template_resolves(id, indexes, options)
  if builtin_templates[id] or indexes.templates[id] then return true end
  local catalogue = options.catalog or options.catalogue
  if type(catalogue) == "function" then return catalogue(id) ~= nil end
  if type(catalogue) == "table" then
    if catalogue[id] then return true end
    if type(catalogue.resolve) == "function" then
      local ok, value = pcall(catalogue.resolve, id)
      return ok and value ~= nil
    end
  end
  return false
end

local function attachment_candidates(model, owner, attachment, aperture)
  local positive, full = {}, {}
  if not aperture or not aperture.within_edge or not aperture.on_exterior then return positive, full end
  for _, other in ipairs(model.rooms or {}) do
    if other.id ~= owner.id then
      local overlaps, covers = false, false
      for _, other_edge in ipairs(adjacency.edges(other)) do
        if
          other_edge.side == adjacency.opposite(attachment.side)
          and other_edge.axis == aperture.axis
          and other_edge.fixed_mm == aperture.fixed_mm
          and interval.overlaps_positive(
            other_edge.start_mm,
            other_edge.finish_mm,
            aperture.start_mm,
            aperture.finish_mm
          )
        then
          overlaps = true
          if
            interval.contains_interval(other_edge.start_mm, other_edge.finish_mm, aperture.start_mm, aperture.finish_mm)
          then
            covers = true
          end
        end
      end
      if overlaps then positive[#positive + 1] = other end
      if covers then full[#full + 1] = other end
    end
  end
  return positive, full
end

local function layout_diagnostics(model, options)
  options = options or {}
  local result = {}
  local indexes = build_indexes(model)
  local limits = options.limits or options
  local i, j

  -- References are layout errors because safely loaded repair drafts retain
  -- well-shaped orphan IDs.
  for i = 1, #model.furniture do
    local furniture = model.furniture[i]
    if not indexes.rooms[furniture.room_id] then
      append(
        result,
        diagnostic(
          "INVALID_REFERENCE",
          "error",
          "furniture",
          furniture.id,
          furniture.id .. " references missing room " .. furniture.room_id,
          { object_ref("room", furniture.room_id) },
          { field = "room_id" }
        )
      )
    end
    if not template_resolves(furniture.template_id, indexes, options) then
      append(
        result,
        diagnostic(
          "TEMPLATE_UNRESOLVED",
          "warning",
          "furniture",
          furniture.id,
          furniture.id .. " references unavailable template " .. furniture.template_id,
          { object_ref("template", furniture.template_id) },
          { template_id = furniture.template_id }
        )
      )
    end
  end
  for i = 1, #model.doors do
    local door = model.doors[i]
    if not indexes.rooms[door.room_id] then
      append(
        result,
        diagnostic(
          "INVALID_REFERENCE",
          "error",
          "door",
          door.id,
          door.id .. " references missing owner room " .. door.room_id,
          { object_ref("room", door.room_id) },
          { field = "room_id" }
        )
      )
    end
    local connection_id = connected_id(door)
    if connection_id and not indexes.rooms[connection_id] then
      append(
        result,
        diagnostic(
          "INVALID_REFERENCE",
          "error",
          "door",
          door.id,
          door.id .. " references missing connected room " .. connection_id,
          { object_ref("room", connection_id) },
          { field = "connects_to_room_id" }
        )
      )
    end
  end
  for i = 1, #(model.windows or {}) do
    local window = model.windows[i]
    if not indexes.rooms[window.room_id] then
      append(
        result,
        diagnostic(
          "INVALID_REFERENCE",
          "error",
          "window",
          window.id,
          window.id .. " references missing owner room " .. window.room_id,
          { object_ref("room", window.room_id) },
          { field = "room_id" }
        )
      )
    end
    local connection_id = connected_id(window)
    if connection_id and not indexes.rooms[connection_id] then
      append(
        result,
        diagnostic(
          "INVALID_REFERENCE",
          "error",
          "window",
          window.id,
          window.id .. " references missing connected room " .. connection_id,
          { object_ref("room", connection_id) },
          { field = "connects_to_room_id" }
        )
      )
    end
  end
  for i = 1, #(model.outlets or {}) do
    local outlet = model.outlets[i]
    if not indexes.rooms[outlet.room_id] then
      append(
        result,
        diagnostic(
          "INVALID_REFERENCE",
          "error",
          "outlet",
          outlet.id,
          outlet.id .. " references missing owner room " .. outlet.room_id,
          { object_ref("room", outlet.room_id) },
          { field = "room_id" }
        )
      )
    end
  end

  -- Rooms and plan limits.
  local room_footprints, room_bounds, room_footprints_by_id = {}, {}, {}
  for i = 1, #model.rooms do
    local room = model.rooms[i]
    local shape, bounds = safe_footprint(result, "room", room, function() return footprint_geometry.from_room(room) end)
    if shape then
      room_footprints[i] = shape
      room_bounds[i] = bounds
      room_footprints_by_id[room.id] = shape
    end
  end
  for i = 1, #model.rooms do
    local room_a = model.rooms[i]
    local bounds_a = room_bounds[i]
    if bounds_a then
      if
        limits.max_dimension_mm
        and (bounds_a.width2 / 2 > limits.max_dimension_mm or bounds_a.depth2 / 2 > limits.max_dimension_mm)
      then
        append(
          result,
          diagnostic(
            "PLAN_LIMIT_EXCEEDED",
            "error",
            "room",
            room_a.id,
            room_a.id .. " exceeds the configured maximum room dimension",
            nil,
            { max_dimension_mm = limits.max_dimension_mm }
          )
        )
      end
      if limits.max_abs_coordinate_mm then
        local maximum = math.max(
          math.abs(bounds_a.left2 / 2),
          math.abs(bounds_a.right2 / 2),
          math.abs(bounds_a.bottom2 / 2),
          math.abs(bounds_a.top2 / 2)
        )
        if maximum > limits.max_abs_coordinate_mm then
          append(
            result,
            diagnostic(
              "PLAN_LIMIT_EXCEEDED",
              "error",
              "room",
              room_a.id,
              room_a.id .. " exceeds the configured coordinate limit",
              nil,
              { max_abs_coordinate_mm = limits.max_abs_coordinate_mm, actual_mm = maximum }
            )
          )
        end
      end
      for j = i + 1, #model.rooms do
        if room_footprints[j] then
          local room_b = model.rooms[j]
          local intersection = footprint_geometry.first_intersection2(room_footprints[i], room_footprints[j])
          if intersection then
            local width = (intersection.right2 - intersection.left2) / 2
            local depth = (intersection.top2 - intersection.bottom2) / 2
            append(
              result,
              diagnostic(
                "ROOM_OVERLAP",
                "error",
                "room",
                room_a.id,
                room_a.id .. " overlaps " .. room_b.id .. " with positive area",
                { object_ref("room", room_b.id) },
                { width_mm = width, depth_mm = depth, area_mm2 = width * depth }
              )
            )
          end
        end
      end
    end
  end
  if limits.max_plan_span_mm then
    local left2, bottom2, right2, top2
    for i = 1, #model.rooms do
      local bounds = room_bounds[i]
      if bounds then
        if left2 == nil then
          left2, bottom2, right2, top2 = bounds.left2, bounds.bottom2, bounds.right2, bounds.top2
        else
          left2, bottom2 = math.min(left2, bounds.left2), math.min(bottom2, bounds.bottom2)
          right2, top2 = math.max(right2, bounds.right2), math.max(top2, bounds.top2)
        end
      end
    end
    if left2 ~= nil then
      local width, depth = (right2 - left2) / 2, (top2 - bottom2) / 2
      if width > limits.max_plan_span_mm or depth > limits.max_plan_span_mm then
        append(
          result,
          diagnostic(
            "PLAN_LIMIT_EXCEEDED",
            "error",
            "plan",
            "roomplan.nvim",
            "plan span exceeds the configured maximum",
            nil,
            { width_mm = width, depth_mm = depth, max_plan_span_mm = limits.max_plan_span_mm }
          )
        )
      end
    end
  end

  -- Furniture containment and pairwise global overlap.
  local furniture_footprints = {}
  for i = 1, #model.furniture do
    local furniture = model.furniture[i]
    local room = indexes.rooms[furniture.room_id]
    if room then
      local shape, bounds = safe_footprint(
        result,
        "furniture",
        furniture,
        function() return footprint_geometry.from_furniture(room, furniture) end
      )
      if shape then
        furniture_footprints[i] = shape
        local height = furniture.height_mm or (furniture.size_mm and furniture.size_mm[3])
        if
          limits.max_dimension_mm
          and (
            bounds.width2 / 2 > limits.max_dimension_mm
            or bounds.depth2 / 2 > limits.max_dimension_mm
            or height > limits.max_dimension_mm
          )
        then
          append(
            result,
            diagnostic(
              "PLAN_LIMIT_EXCEEDED",
              "error",
              "furniture",
              furniture.id,
              furniture.id .. " exceeds the configured maximum object dimension",
              nil,
              { max_dimension_mm = limits.max_dimension_mm }
            )
          )
        end
        if limits.max_abs_coordinate_mm then
          local maximum = math.max(
            math.abs(bounds.left2 / 2),
            math.abs(bounds.right2 / 2),
            math.abs(bounds.bottom2 / 2),
            math.abs(bounds.top2 / 2)
          )
          if maximum > limits.max_abs_coordinate_mm then
            append(
              result,
              diagnostic(
                "PLAN_LIMIT_EXCEEDED",
                "error",
                "furniture",
                furniture.id,
                furniture.id .. " exceeds the configured coordinate limit",
                nil,
                { max_abs_coordinate_mm = limits.max_abs_coordinate_mm, actual_mm = maximum }
              )
            )
          end
        end
        local room_shape = room_footprints_by_id[room.id]
        if room_shape then
          local contained, containment_error = footprint_geometry.contains(room_shape, shape)
          if contained == nil then
            append_geometry_problem(result, "furniture", furniture, containment_error)
          elseif contained == false then
            local overflow2, overflow_error = footprint_geometry.overflow2(room_shape, shape)
            if not overflow2 then
              append_geometry_problem(result, "furniture", furniture, overflow_error)
            else
              local details = {
                overflow_mm = {
                  west = overflow2.west / 2,
                  east = overflow2.east / 2,
                  south = overflow2.south / 2,
                  north = overflow2.north / 2,
                },
              }
              append(
                result,
                diagnostic(
                  "FURNITURE_OUTSIDE_ROOM",
                  "error",
                  "furniture",
                  furniture.id,
                  furniture.id .. " extends outside owning room " .. room.id,
                  { object_ref("room", room.id) },
                  details
                )
              )
            end
          end
        end
      end
    end
  end
  for i = 1, #model.furniture do
    if furniture_footprints[i] then
      for j = i + 1, #model.furniture do
        if furniture_footprints[j] then
          local overlaps = footprint_geometry.overlaps_positive(furniture_footprints[i], furniture_footprints[j])
          if overlaps then
            local overlap = footprint_geometry.first_intersection2(furniture_footprints[i], furniture_footprints[j])
            if overlap then
              append(
                result,
                diagnostic(
                  "FURNITURE_OVERLAP",
                  "error",
                  "furniture",
                  model.furniture[i].id,
                  model.furniture[i].id .. " overlaps " .. model.furniture[j].id .. " with positive area",
                  { object_ref("furniture", model.furniture[j].id) },
                  { width_mm = (overlap.right2 - overlap.left2) / 2, depth_mm = (overlap.top2 - overlap.bottom2) / 2 }
                )
              )
            end
          end
        end
      end
    end
  end

  -- Apertures, adjacency, swing target, and global opening overlap.
  local apertures, swings = {}, {}
  for i = 1, #model.doors do
    local door = model.doors[i]
    local owner = indexes.rooms[door.room_id]
    if owner then
      local aperture, aperture_error = door_geometry.aperture(owner, door)
      if limits.max_dimension_mm and door.width_mm > limits.max_dimension_mm then
        append(
          result,
          diagnostic(
            "PLAN_LIMIT_EXCEEDED",
            "error",
            "door",
            door.id,
            door.id .. " exceeds the configured maximum object dimension",
            nil,
            { max_dimension_mm = limits.max_dimension_mm, width_mm = door.width_mm }
          )
        )
      end
      if not aperture then
        append(
          result,
          diagnostic(
            "DOOR_EDGE_INVALID",
            "error",
            "door",
            door.id,
            door.id .. " references an unavailable owner-room edge",
            { object_ref("room", owner.id) },
            { cause = aperture_error }
          )
        )
      elseif not aperture.within_edge then
        append(
          result,
          diagnostic(
            "DOOR_OUTSIDE_EDGE",
            "error",
            "door",
            door.id,
            door.id .. " aperture extends outside its owning wall edge",
            { object_ref("room", owner.id) },
            {
              edge_start_mm = aperture.edge_start_mm,
              edge_finish_mm = aperture.edge_finish_mm,
              aperture_start_mm = aperture.start_mm,
              aperture_finish_mm = aperture.finish_mm,
            }
          )
        )
      elseif not aperture.on_exterior then
        append(
          result,
          diagnostic(
            "DOOR_NOT_EXTERIOR",
            "error",
            "door",
            door.id,
            door.id .. " aperture lies on an internal footprint seam",
            { object_ref("room", owner.id) },
            { part_id = door.part_id, side = door.side }
          )
        )
      end

      local positive_candidates, full_candidates = {}, {}
      if aperture and aperture.within_edge and aperture.on_exterior then
        for j = 1, #model.rooms do
          local other = model.rooms[j]
          if other.id ~= owner.id then
            local overlaps, covers = false, false
            for _, other_edge in ipairs(adjacency.edges(other)) do
              if
                other_edge.side == adjacency.opposite(door.side)
                and other_edge.axis == aperture.axis
                and other_edge.fixed_mm == aperture.fixed_mm
                and interval.overlaps_positive(
                  other_edge.start_mm,
                  other_edge.finish_mm,
                  aperture.start_mm,
                  aperture.finish_mm
                )
              then
                overlaps = true
                if
                  interval.contains_interval(
                    other_edge.start_mm,
                    other_edge.finish_mm,
                    aperture.start_mm,
                    aperture.finish_mm
                  )
                then
                  covers = true
                end
              end
            end
            if overlaps then positive_candidates[#positive_candidates + 1] = other end
            if covers then full_candidates[#full_candidates + 1] = other end
          end
        end
      end

      local connection_id = connected_id(door)
      if connection_id then
        local connected = indexes.rooms[connection_id]
        local connection = connected and door_geometry.connection(owner, connected, door) or nil
        if connection_id == door.room_id or not connection then
          append(
            result,
            diagnostic(
              "DOOR_CONNECTION_INVALID",
              "error",
              "door",
              door.id,
              door.id .. " claimed connection does not cover the complete aperture",
              { object_ref("room", connection_id) },
              { side = door.side }
            )
          )
        end
        if door.opens_into == "outside" then
          append(
            result,
            diagnostic(
              "DOOR_SWING_TARGET_INVALID",
              "error",
              "door",
              door.id,
              door.id .. " is connected and cannot swing into outside",
              { object_ref("room", connection_id) },
              { opens_into = door.opens_into }
            )
          )
        end
      else
        if #positive_candidates == 1 and #full_candidates == 1 then
          append(
            result,
            diagnostic(
              "DOOR_CONNECTION_MISSING",
              "error",
              "door",
              door.id,
              door.id .. " aperture is fully covered by adjacent room " .. full_candidates[1].id,
              { object_ref("room", full_candidates[1].id) },
              {}
            )
          )
        elseif #positive_candidates > 0 then
          local related = {}
          for j = 1, #positive_candidates do
            related[j] = object_ref("room", positive_candidates[j].id)
          end
          append(
            result,
            diagnostic(
              "DOOR_EXTERIOR_OBSTRUCTED",
              "error",
              "door",
              door.id,
              door.id .. " exterior aperture is partially or ambiguously obstructed",
              related,
              { candidate_count = #positive_candidates, full_cover_count = #full_candidates }
            )
          )
        end
        if door.opens_into == "connected" then
          append(
            result,
            diagnostic(
              "DOOR_SWING_TARGET_INVALID",
              "error",
              "door",
              door.id,
              door.id .. " has no connected room but opens_into is connected",
              nil,
              { opens_into = door.opens_into }
            )
          )
        end
      end
      apertures[i] = aperture
      if aperture and aperture.within_edge and aperture.on_exterior then
        swings[i] = door_geometry.swing(owner, door)
      end
      if swings[i] and limits.max_abs_coordinate_mm then
        local swing_bounds = sector.aabb(swings[i])
        local maximum = math.max(
          math.abs(swing_bounds.left),
          math.abs(swing_bounds.right),
          math.abs(swing_bounds.bottom),
          math.abs(swing_bounds.top)
        )
        if maximum > limits.max_abs_coordinate_mm then
          append(
            result,
            diagnostic(
              "PLAN_LIMIT_EXCEEDED",
              "error",
              "door",
              door.id,
              door.id .. " swing exceeds the configured coordinate limit",
              nil,
              { max_abs_coordinate_mm = limits.max_abs_coordinate_mm, actual_mm = maximum }
            )
          )
        end
      end
    end
  end

  local window_apertures = {}
  for i = 1, #(model.windows or {}) do
    local window = model.windows[i]
    local owner = indexes.rooms[window.room_id]
    if owner then
      local aperture, aperture_error = wall_attachment.aperture(owner, window)
      if limits.max_dimension_mm and window.width_mm > limits.max_dimension_mm then
        append(
          result,
          diagnostic(
            "PLAN_LIMIT_EXCEEDED",
            "error",
            "window",
            window.id,
            window.id .. " exceeds the configured maximum object dimension",
            nil,
            { max_dimension_mm = limits.max_dimension_mm, width_mm = window.width_mm }
          )
        )
      end
      if not aperture then
        append(
          result,
          diagnostic(
            "WINDOW_EDGE_INVALID",
            "error",
            "window",
            window.id,
            window.id .. " references an unavailable owner-room edge",
            { object_ref("room", owner.id) },
            { cause = aperture_error }
          )
        )
      elseif not aperture.within_edge then
        append(
          result,
          diagnostic(
            "WINDOW_OUTSIDE_EDGE",
            "error",
            "window",
            window.id,
            window.id .. " aperture extends outside its owning wall edge",
            { object_ref("room", owner.id) },
            {
              edge_start_mm = aperture.edge_start_mm,
              edge_finish_mm = aperture.edge_finish_mm,
              aperture_start_mm = aperture.start_mm,
              aperture_finish_mm = aperture.finish_mm,
            }
          )
        )
      elseif not aperture.on_exterior then
        append(
          result,
          diagnostic(
            "WINDOW_NOT_EXTERIOR",
            "error",
            "window",
            window.id,
            window.id .. " aperture lies on an internal footprint seam",
            { object_ref("room", owner.id) },
            { part_id = window.part_id, side = window.side }
          )
        )
      end

      local connection_id = connected_id(window)
      if connection_id then
        local connected = indexes.rooms[connection_id]
        local connection = connected and wall_attachment.connection(owner, connected, window) or nil
        if connection_id == window.room_id or not connection then
          append(
            result,
            diagnostic(
              "WINDOW_CONNECTION_INVALID",
              "error",
              "window",
              window.id,
              window.id .. " claimed connection does not cover the complete aperture",
              { object_ref("room", connection_id) },
              { side = window.side }
            )
          )
        end
      else
        local positive_candidates, full_candidates = attachment_candidates(model, owner, window, aperture)
        if #positive_candidates == 1 and #full_candidates == 1 then
          append(
            result,
            diagnostic(
              "WINDOW_CONNECTION_MISSING",
              "error",
              "window",
              window.id,
              window.id .. " aperture is fully covered by adjacent room " .. full_candidates[1].id,
              { object_ref("room", full_candidates[1].id) },
              {}
            )
          )
        elseif #positive_candidates > 0 then
          local related = {}
          for candidate_index = 1, #positive_candidates do
            related[candidate_index] = object_ref("room", positive_candidates[candidate_index].id)
          end
          append(
            result,
            diagnostic(
              "WINDOW_EXTERIOR_OBSTRUCTED",
              "error",
              "window",
              window.id,
              window.id .. " exterior aperture is partially or ambiguously obstructed",
              related,
              { candidate_count = #positive_candidates, full_cover_count = #full_candidates }
            )
          )
        end
      end
      window_apertures[i] = aperture
    end
  end

  for i = 1, #(model.outlets or {}) do
    local outlet = model.outlets[i]
    local owner = indexes.rooms[outlet.room_id]
    if owner then
      if outlet.placement == "floor" then
        local marker, marker_error = wall_attachment.floor_marker(owner, outlet)
        if not marker then
          append(
            result,
            diagnostic(
              "OUTLET_FLOOR_INVALID",
              "error",
              "outlet",
              outlet.id,
              outlet.id .. " has an unavailable floor position",
              { object_ref("room", owner.id) },
              { cause = marker_error }
            )
          )
        elseif not marker.within_room then
          append(
            result,
            diagnostic(
              "OUTLET_OUTSIDE_ROOM",
              "error",
              "outlet",
              outlet.id,
              outlet.id .. " must lie strictly inside its owner room",
              { object_ref("room", owner.id) },
              { position_mm = outlet.position_mm }
            )
          )
        end
      else
        local marker, marker_error = wall_attachment.marker(owner, outlet)
        if not marker then
          append(
            result,
            diagnostic(
              "OUTLET_EDGE_INVALID",
              "error",
              "outlet",
              outlet.id,
              outlet.id .. " references an unavailable owner-room edge",
              { object_ref("room", owner.id) },
              { cause = marker_error }
            )
          )
        elseif not marker.within_edge then
          append(
            result,
            diagnostic(
              "OUTLET_OUTSIDE_EDGE",
              "error",
              "outlet",
              outlet.id,
              outlet.id .. " must lie strictly inside its owning wall edge, away from corners",
              { object_ref("room", owner.id) },
              {
                edge_start_mm = marker.edge_start_mm,
                edge_finish_mm = marker.edge_finish_mm,
                marker_mm = marker.scalar_mm,
              }
            )
          )
        elseif not marker.on_exterior then
          append(
            result,
            diagnostic(
              "OUTLET_NOT_EXTERIOR",
              "error",
              "outlet",
              outlet.id,
              outlet.id .. " lies on an internal footprint seam",
              { object_ref("room", owner.id) },
              { part_id = outlet.part_id, side = outlet.side }
            )
          )
        end
      end
    end
  end

  for i = 1, #model.doors do
    if apertures[i] and apertures[i].within_edge and apertures[i].on_exterior then
      for j = i + 1, #model.doors do
        if
          apertures[j]
          and apertures[j].within_edge
          and apertures[j].on_exterior
          and door_geometry.apertures_overlap(apertures[i], apertures[j])
        then
          local overlap_start = math.max(apertures[i].start_mm, apertures[j].start_mm)
          local overlap_finish = math.min(apertures[i].finish_mm, apertures[j].finish_mm)
          append(
            result,
            diagnostic(
              "DOOR_OPENING_OVERLAP",
              "error",
              "door",
              model.doors[i].id,
              model.doors[i].id .. " opening overlaps " .. model.doors[j].id,
              { object_ref("door", model.doors[j].id) },
              { overlap_mm = overlap_finish - overlap_start, start_mm = overlap_start, finish_mm = overlap_finish }
            )
          )
        end
      end
    end
  end
  for i = 1, #model.doors do
    local door_aperture = apertures[i]
    if door_aperture and door_aperture.within_edge and door_aperture.on_exterior then
      for j = 1, #(model.windows or {}) do
        local window_aperture = window_apertures[j]
        if
          window_aperture
          and window_aperture.within_edge
          and window_aperture.on_exterior
          and wall_attachment.apertures_overlap(door_aperture, window_aperture)
        then
          local overlap_start = math.max(door_aperture.start_mm, window_aperture.start_mm)
          local overlap_finish = math.min(door_aperture.finish_mm, window_aperture.finish_mm)
          append(
            result,
            diagnostic(
              "WALL_OPENING_OVERLAP",
              "error",
              "door",
              model.doors[i].id,
              model.doors[i].id .. " opening overlaps " .. model.windows[j].id,
              { object_ref("window", model.windows[j].id) },
              { overlap_mm = overlap_finish - overlap_start, start_mm = overlap_start, finish_mm = overlap_finish }
            )
          )
        end
      end
    end
  end
  for i = 1, #(model.windows or {}) do
    local first = window_apertures[i]
    if first and first.within_edge and first.on_exterior then
      for j = i + 1, #(model.windows or {}) do
        local second = window_apertures[j]
        if
          second
          and second.within_edge
          and second.on_exterior
          and wall_attachment.apertures_overlap(first, second)
        then
          local overlap_start = math.max(first.start_mm, second.start_mm)
          local overlap_finish = math.min(first.finish_mm, second.finish_mm)
          append(
            result,
            diagnostic(
              "WALL_OPENING_OVERLAP",
              "error",
              "window",
              model.windows[i].id,
              model.windows[i].id .. " opening overlaps " .. model.windows[j].id,
              { object_ref("window", model.windows[j].id) },
              { overlap_mm = overlap_finish - overlap_start, start_mm = overlap_start, finish_mm = overlap_finish }
            )
          )
        end
      end
    end
  end

  -- Door swept sectors against furniture.
  for i = 1, #model.doors do
    if swings[i] then
      for j = 1, #model.furniture do
        if furniture_footprints[j] then
          local rectangles = assert(footprint_geometry.rectangles(furniture_footprints[j]))
          local hit = false
          for rectangle_index = 1, #rectangles do
            if sector.intersects_rect(swings[i], rectangles[rectangle_index]) then
              hit = true
              break
            end
          end
          if hit then
            append(
              result,
              diagnostic(
                "DOOR_SWING_FURNITURE",
                "warning",
                "door",
                model.doors[i].id,
                model.doors[i].id .. " swing intersects " .. model.furniture[j].id,
                { object_ref("furniture", model.furniture[j].id) },
                {}
              )
            )
          end
        end
      end
    end
  end

  -- Door sweep versus every non-aperture wall piece. Designed hinge/jamb
  -- endpoint contacts on the owner and valid connected contributor are ignored.
  for i = 1, #model.doors do
    local swing = swings[i]
    local aperture = apertures[i]
    local current_door = model.doors[i]
    if swing and aperture then
      local warned = false
      for j = 1, #model.rooms do
        local wall_room = model.rooms[j]
        local edges = adjacency.edges(wall_room)
        local e
        for e = 1, #edges do
          local edge = edges[e]
          local cuts = {}
          local is_owner_edge = wall_room.id == current_door.room_id and edge.side == current_door.side
          local connection_id = connected_id(current_door)
          local connected = connection_id and indexes.rooms[connection_id]
          local is_connected_edge = connected
            and wall_room.id == connected.id
            and edge.side == adjacency.opposite(current_door.side)
            and door_geometry.connection(indexes.rooms[current_door.room_id], connected, current_door) ~= nil
          if
            (is_owner_edge or is_connected_edge)
            and edge.axis == aperture.axis
            and edge.fixed_mm == aperture.fixed_mm
          then
            cuts[1] = { aperture.start_mm, aperture.finish_mm }
          end
          local pieces = interval.subtract(edge.start_mm, edge.finish_mm, cuts)
          local p
          for p = 1, #pieces do
            local a, b = door_geometry.wall_piece_segment(edge, pieces[p].start, pieces[p].finish)
            local hit = sector.intersects_segment(swing, a, b, { exclude_points = { swing.hinge, swing.jamb } })
            if hit then
              append(
                result,
                diagnostic(
                  "DOOR_SWING_WALL",
                  "warning",
                  "door",
                  current_door.id,
                  current_door.id .. " swing intersects a non-aperture wall of " .. wall_room.id,
                  { object_ref("room", wall_room.id) },
                  { side = edge.side }
                )
              )
              warned = true
              break
            end
          end
          if warned then break end
        end
        if warned then break end
      end
    end
  end

  -- Pairwise leaf/sector interference. Tangency is intentionally a warning.
  for i = 1, #model.doors do
    local owner_a = indexes.rooms[model.doors[i].room_id]
    if owner_a and swings[i] then
      for j = i + 1, #model.doors do
        local owner_b = indexes.rooms[model.doors[j].room_id]
        if owner_b and swings[j] then
          local hit = door_geometry.interferes(owner_a, model.doors[i], owner_b, model.doors[j])
          if hit then
            append(
              result,
              diagnostic(
                "DOOR_SWING_DOOR",
                "warning",
                "door",
                model.doors[i].id,
                model.doors[i].id .. " swing interferes with " .. model.doors[j].id,
                { object_ref("door", model.doors[j].id) },
                {}
              )
            )
          end
        end
      end
    end
  end
  return result, indexes
end

local function order_map(model)
  local result = { room = {}, door = {}, window = {}, outlet = {}, furniture = {}, template = {} }
  local collections = {
    { key = "rooms", kind = "room" },
    { key = "doors", kind = "door" },
    { key = "windows", kind = "window" },
    { key = "outlets", kind = "outlet" },
    { key = "furniture", kind = "furniture" },
    { key = "custom_templates", kind = "template" },
  }
  local c, i
  for c = 1, #collections do
    for i = 1, #(model[collections[c].key] or {}) do
      result[collections[c].kind][model[collections[c].key][i].id] = i
    end
  end
  return result
end

local function sort_diagnostics(diagnostics, model)
  local orders = order_map(type(model) == "table" and model or {})
  table.sort(diagnostics, function(a, b)
    local as, bs = severity_rank[a.severity] or 99, severity_rank[b.severity] or 99
    if as ~= bs then return as < bs end
    if a.code ~= b.code then return a.code < b.code end
    local ak, bk = kind_rank[a.object.kind] or 99, kind_rank[b.object.kind] or 99
    if ak ~= bk then return ak < bk end
    local ao = orders[a.object.kind] and orders[a.object.kind][a.object.id] or math.huge
    local bo = orders[b.object.kind] and orders[b.object.kind][b.object.id] or math.huge
    if ao ~= bo then return ao < bo end
    return tostring(a.object.id) < tostring(b.object.id)
  end)
  return diagnostics
end

function M.run(model, options)
  options = options or {}
  local diagnostics = M.structural(model)
  if #diagnostics == 0 then
    local layout = layout_diagnostics(model, options)
    local i
    for i = 1, #layout do
      diagnostics[#diagnostics + 1] = layout[i]
    end
  end
  sort_diagnostics(diagnostics, model)
  local summary = { errors = 0, warnings = 0, structural_errors = 0, valid = true }
  local i
  for i = 1, #diagnostics do
    if diagnostics[i].severity == "error" then
      summary.errors = summary.errors + 1
      summary.valid = false
    end
    if diagnostics[i].severity == "warning" then summary.warnings = summary.warnings + 1 end
    if diagnostics[i].structural then summary.structural_errors = summary.structural_errors + 1 end
  end
  return diagnostics, summary
end

function M.is_structurally_valid(model)
  local diagnostics = M.structural(model)
  return #diagnostics == 0, diagnostics
end

return M
