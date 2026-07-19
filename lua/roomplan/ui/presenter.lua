-- Pure presentation layer: canonical model/session state in, display-only view
-- models out.  No returned table is part of the saved model.

local color = require("roomplan.color")
local footprint = require("roomplan.geometry.footprint")
local canvas_detail = require("roomplan.canvas_detail")
local outlet_types = require("roomplan.outlet_types")
local directions = require("roomplan.directions")

local M = {}

local function footprint_info(value)
  local shape = value and footprint.from_persisted(value) or nil
  if not shape then return nil end
  local bounds = footprint.bounds(shape)
  local area = footprint.area(shape)
  local perimeter = footprint.perimeter(shape)
  if not bounds or not area or not perimeter then return nil end
  return {
    width = bounds.width,
    depth = bounds.depth,
    area = area,
    perimeter = perimeter,
    parts = #(value.parts or {}),
  }
end

local function model_of(value)
  if type(value) ~= "table" then return {} end
  if type(value.current_model) == "function" then return value:current_model() end
  if type(value.model) == "function" then return value:model() end
  if type(value.model) == "table" then return value.model end
  return value
end

local function selection_of(value, opts)
  if opts and opts.selection ~= nil then return opts.selection end
  return type(value) == "table" and value.selection or nil
end

local function shape_context(value)
  local edit = type(value) == "table" and value.shape_edit or nil
  if not edit then return {} end
  local _, index = require("roomplan.room_shape").selected(edit)
  return {
    shape_section_index = index or 0,
    shape_section_count = #(edit.footprint.parts or {}),
    shape_edge = directions.replace_cardinals(require("roomplan.room_shape").edge_summary(edit), value),
    shape_feedback = directions.replace_cardinals(edit.move_feedback, value),
    shape_snap = directions.replace_cardinals(require("roomplan.room_shape").snap_summary(edit), value),
  }
end

local function diagnostics_of(value, opts)
  if opts and opts.diagnostics ~= nil then return opts.diagnostics end
  return type(value) == "table" and value.validation or {}
end

local function lower(value) return tostring(value or ""):lower() end

local function selected(selection, kind, id) return selection ~= nil and selection.kind == kind and selection.id == id end

function M.format_mm(value)
  if type(value) ~= "number" then return tostring(value or "-") end
  local exact = string.format("%d mm", value)
  if value == 0 then return exact end
  if value % 1000 == 0 then return string.format("%s (%g m)", exact, value / 1000) end
  if value % 10 == 0 then return string.format("%s (%g cm)", exact, value / 10) end
  return exact
end

---Format dimensions for the workspace's compact details view. The persisted
---model remains millimetre-based; this is display-only and deliberately avoids
---showing the same value twice in different units.
function M.compact_mm(value)
  if type(value) ~= "number" then return tostring(value or "-") end
  if math.abs(value) >= 1000 then
    local metres = string.format("%.3f", value / 1000):gsub("0+$", ""):gsub("%.$", "")
    return metres .. " m"
  end
  return string.format("%d mm", value)
end

local function short_mm(value)
  if type(value) ~= "number" then return "?" end
  if value % 1000 == 0 then return string.format("%gm", value / 1000) end
  if value >= 1000 then return string.format("%.2gm", value / 1000) end
  return string.format("%dmm", value)
end

local function issue_index(diagnostics)
  local result = {}
  for _, diagnostic in ipairs(diagnostics or {}) do
    local object = diagnostic.object or {}
    if object.id then
      local key = tostring(object.kind or "object") .. ":" .. tostring(object.id)
      local counts = result[key] or { errors = 0, warnings = 0, info = 0, items = {} }
      local severity = diagnostic.severity == "error" and "errors"
        or diagnostic.severity == "warning" and "warnings"
        or "info"
      counts[severity] = counts[severity] + 1
      counts.items[#counts.items + 1] = diagnostic
      result[key] = counts
    end
  end
  return result
end

local function counts_for(index, kind, id)
  return index[tostring(kind) .. ":" .. tostring(id)] or { errors = 0, warnings = 0, info = 0, items = {} }
end

local function matches_filter(row, query)
  if query == "" then return true end
  local haystack = table
    .concat({
      row.kind or "",
      row.id or "",
      row.name or "",
      row.label or "",
      row.room_name or "",
    }, " ")
    :lower()
  return haystack:find(query, 1, true) ~= nil
end

local function room_lookup(model)
  local result = {}
  for _, room in ipairs(model.rooms or {}) do
    result[room.id] = room
  end
  return result
end

---Build hierarchical object rows. Rooms retain model order; wall attachments
---are listed before furniture, also in canonical model order.
function M.objects(value, opts)
  opts = opts or {}
  local model = model_of(value)
  local compound_geometry = model.schema_version >= 2
  local selection = selection_of(value, opts)
  local marked = opts.marked or (type(value) == "table" and value.marked_objects) or {}
  local selection_set = require("roomplan.selection_set")
  local function is_marked(kind, id) return id ~= nil and marked[selection_set.key(kind, id)] ~= nil end
  local diagnostics = diagnostics_of(value, opts)
  local indexed = issue_index(diagnostics)
  local expanded = opts.expanded or {}
  local query = lower(opts.filter)
  local rooms = room_lookup(model)
  local children = {}
  local orphans = {}

  local function child(room_id, row)
    if rooms[room_id] then
      children[room_id] = children[room_id] or {}
      children[room_id][#children[room_id] + 1] = row
    else
      orphans[#orphans + 1] = row
    end
  end

  for _, door in ipairs(model.doors or {}) do
    local destination = rooms[door.connects_to_room_id]
    local destination_name = destination and destination.name or "outside"
    child(door.room_id, {
      kind = "door",
      id = door.id,
      name = door.name or door.id,
      room_name = rooms[door.room_id] and rooms[door.room_id].name or door.room_id,
      label = string.format("%s → %s", directions.label(door.side, value), destination_name),
      detail = short_mm(door.width_mm),
      object = door,
    })
  end
  for _, window in ipairs(model.windows or {}) do
    local destination = rooms[window.connects_to_room_id]
    local destination_name = destination and destination.name or "outside"
    child(window.room_id, {
      kind = "window",
      id = window.id,
      name = window.id,
      room_name = rooms[window.room_id] and rooms[window.room_id].name or window.room_id,
      label = string.format("%s window → %s", directions.label(window.side, value), destination_name),
      detail = short_mm(window.width_mm),
      object = window,
    })
  end
  for _, outlet in ipairs(model.outlets or {}) do
    local outlet_name = outlet_types.label(outlet.outlet_type) or outlet.outlet_type or "Outlet"
    child(outlet.room_id, {
      kind = "outlet",
      id = outlet.id,
      name = outlet_name .. " outlet",
      room_name = rooms[outlet.room_id] and rooms[outlet.room_id].name or outlet.room_id,
      label = outlet_name .. " outlet",
      detail = string.format(
        "%d slot%s · %s",
        outlet.slots or 0,
        outlet.slots == 1 and "" or "s",
        outlet.placement == "floor" and "floor" or directions.label(outlet.side, value):lower()
      ),
      object = outlet,
    })
  end
  for _, furniture in ipairs(model.furniture or {}) do
    local geometry = compound_geometry and footprint_info(furniture.footprint) or nil
    local size = furniture.size_mm or { geometry and geometry.width, geometry and geometry.depth, furniture.height_mm }
    child(furniture.room_id, {
      kind = "furniture",
      id = furniture.id,
      name = furniture.name or furniture.id,
      room_name = rooms[furniture.room_id] and rooms[furniture.room_id].name or furniture.room_id,
      label = furniture.name or furniture.id or "Furniture",
      detail = string.format(
        "%s × %s%s",
        short_mm(size[1]),
        short_mm(size[2]),
        geometry and geometry.parts > 1 and string.format(" · %d parts", geometry.parts) or ""
      ),
      object = furniture,
    })
  end

  local rows = {
    {
      kind = "plan",
      name = model.metadata and model.metadata.name or "Untitled plan",
      label = model.metadata and model.metadata.name or "Untitled plan",
      depth = 0,
      selected = selection and selection.kind == "plan" or false,
      marked = false,
      counts = { errors = 0, warnings = 0, info = 0, items = {} },
    },
  }

  for _, room in ipairs(model.rooms or {}) do
    local geometry = compound_geometry and footprint_info(room.footprint) or nil
    local size = room.size_mm or { geometry and geometry.width, geometry and geometry.depth }
    local room_row = {
      kind = "room",
      id = room.id,
      name = room.name or room.id,
      label = room.name or room.id or "Room",
      detail = string.format(
        "%s × %s%s",
        short_mm(size[1]),
        short_mm(size[2]),
        geometry and geometry.parts > 1 and string.format(" · %d parts", geometry.parts) or ""
      ),
      object = room,
      depth = 0,
      expandable = #(children[room.id] or {}) > 0,
      expanded = expanded[room.id] ~= false,
      selected = selected(selection, "room", room.id),
      marked = is_marked("room", room.id),
      counts = counts_for(indexed, "room", room.id),
    }
    local presented_children = {}
    for _, row in ipairs(children[room.id] or {}) do
      row.depth = 1
      row.selected = selected(selection, row.kind, row.id)
      row.marked = is_marked(row.kind, row.id)
      row.counts = counts_for(indexed, row.kind, row.id)
      if matches_filter(row, query) then presented_children[#presented_children + 1] = row end
    end
    if matches_filter(room_row, query) or #presented_children > 0 then
      rows[#rows + 1] = room_row
      if room_row.expanded then
        for _, row in ipairs(presented_children) do
          rows[#rows + 1] = row
        end
      end
    end
  end

  for _, template in ipairs(model.custom_templates or {}) do
    local geometry = compound_geometry and footprint_info(template.default_footprint) or nil
    local size = template.default_size_mm
      or { geometry and geometry.width, geometry and geometry.depth, template.default_height_mm }
    local row = {
      kind = "template",
      id = template.id,
      name = template.name or template.id,
      label = template.name or template.id or "Custom",
      detail = string.format(
        "%s × %s × %s%s",
        short_mm(size[1]),
        short_mm(size[2]),
        short_mm(size[3]),
        geometry and geometry.parts > 1 and string.format(" · %d parts", geometry.parts) or ""
      ),
      object = template,
      depth = 0,
      selected = selected(selection, "template", template.id),
      marked = is_marked("template", template.id),
      counts = counts_for(indexed, "template", template.id),
    }
    if matches_filter(row, query) then rows[#rows + 1] = row end
  end

  for _, row in ipairs(orphans) do
    row.depth = 0
    row.orphan = true
    row.selected = selected(selection, row.kind, row.id)
    row.marked = is_marked(row.kind, row.id)
    row.counts = counts_for(indexed, row.kind, row.id)
    if matches_filter(row, query) then rows[#rows + 1] = row end
  end

  local summary = string.format(
    "%d rooms · %d doors · %d windows · %d outlets · %d items",
    #(model.rooms or {}),
    #(model.doors or {}),
    #(model.windows or {}),
    #(model.outlets or {}),
    #(model.furniture or {})
  )
  if #(model.custom_templates or {}) > 0 then
    summary = summary .. string.format(" · %d templates", #model.custom_templates)
  end
  return {
    title = model.metadata and model.metadata.name or "Untitled plan",
    summary = summary,
    counts = {
      rooms = #(model.rooms or {}),
      doors = #(model.doors or {}),
      windows = #(model.windows or {}),
      outlets = #(model.outlets or {}),
      furniture = #(model.furniture or {}),
      templates = #(model.custom_templates or {}),
    },
    room_count = #(model.rooms or {}),
    rows = rows,
    marked_count = #selection_set.list(model, marked),
    filter = opts.filter or "",
  }
end

function M.issues(value, opts)
  opts = opts or {}
  local diagnostics = diagnostics_of(value, opts)
  local query = lower(opts.filter)
  local rows = {}
  local counts = { errors = 0, warnings = 0, info = 0 }
  for index, diagnostic in ipairs(diagnostics or {}) do
    local severity = diagnostic.severity == "error" and "error"
      or diagnostic.severity == "warning" and "warning"
      or "info"
    counts[severity .. "s"] = counts[severity .. "s"] + 1
    local object = diagnostic.object or {}
    local row = {
      index = index,
      kind = object.kind,
      id = object.id,
      severity = severity,
      code = diagnostic.code or "UNKNOWN",
      message = diagnostic.message or "",
      diagnostic = diagnostic,
    }
    local haystack = lower(table.concat({ row.severity, row.code, row.message, row.kind or "", row.id or "" }, " "))
    if query == "" or haystack:find(query, 1, true) then rows[#rows + 1] = row end
  end
  return { rows = rows, counts = counts, filter = opts.filter or "" }
end

local function find(model, selection)
  if not selection then return nil end
  local collection = selection.kind == "room" and model.rooms
    or selection.kind == "door" and model.doors
    or selection.kind == "window" and model.windows
    or selection.kind == "outlet" and model.outlets
    or selection.kind == "furniture" and model.furniture
    or selection.kind == "template" and model.custom_templates
  for _, object in ipairs(collection or {}) do
    if object.id == selection.id then return object end
  end
end

local breadcrumb_highlights = {
  room = "RoomPlanWorkspaceRoom",
  door = "RoomPlanWorkspaceDoor",
  window = "RoomPlanWorkspaceWindow",
  outlet = "RoomPlanWorkspaceOutlet",
  furniture = "RoomPlanWorkspaceFurniture",
  template = "RoomPlanWorkspaceValue",
}

local function capitalized(value, fallback)
  value = tostring(value or fallback or "")
  if value == "" then return value end
  return value:sub(1, 1):upper() .. value:sub(2)
end

local function room_name(rooms, id, fallback)
  local owner = type(id) == "string" and rooms[id] or nil
  if owner then return tostring(owner.name or owner.id) end
  if type(id) == "string" then return id end
  return fallback
end

local function selection_breadcrumb(model, selection, object, direction_context)
  if not selection or selection.kind == "plan" or not object then return nil end
  local rooms = room_lookup(model)
  local kind = selection.kind
  local values = {}

  if kind == "room" then
    values[1] = tostring(object.name or object.id)
  elseif kind == "furniture" then
    values[1] = room_name(rooms, object.room_id, "Unknown room")
    values[2] = tostring(object.name or object.id or "Furniture")
    if object.category then values[2] = values[2] .. " · " .. tostring(object.category) end
  elseif kind == "door" or kind == "window" then
    values[1] = room_name(rooms, object.room_id, "Unknown room")
    local destination = room_name(rooms, object.connects_to_room_id, "outside")
    values[2] = string.format(
      "%s · %s → %s",
      kind == "door" and "Door" or "Window",
      directions.label(object.side, direction_context),
      destination
    )
  elseif kind == "outlet" then
    values[1] = room_name(rooms, object.room_id, "Unknown room")
    local placement = object.placement == "floor" and "Floor outlet" or "Wall outlet"
    local outlet = outlet_types.label(object.outlet_type) or capitalized(object.outlet_type, "Outlet")
    local slots = tonumber(object.slots) or 0
    values[2] = string.format("%s · %s · %d slot%s", placement, outlet, slots, slots == 1 and "" or "s")
  elseif kind == "template" then
    values[1] = "Project template"
    values[2] = tostring(object.name or object.id)
    if object.category then values[2] = values[2] .. " · " .. tostring(object.category) end
  else
    return nil
  end

  return {
    text = table.concat(values, " › "),
    selection_text = table.concat(values, " › "),
    kind = kind,
    hl_group = breadcrumb_highlights[kind] or "RoomPlanWorkspaceStatus",
  }
end

---Build one compact, display-only selection path. MOVE and RESIZE append only
---the feedback needed to understand the active interaction; Details remains the
---authority for complete object properties.
function M.breadcrumb(value, ctx)
  ctx = ctx or {}
  local model = model_of(value)
  local selection = ctx.selection ~= nil and ctx.selection or selection_of(value)
  local object = ctx.selected_object or find(model, selection)
  local result = selection_breadcrumb(model, selection, object, value)
  if not result then return nil end

  local values = { result.selection_text }
  if ctx.mode == "MOVE" then
    values[#values + 1] = "MOVE"
    if ctx.move_feedback then values[#values + 1] = ctx.move_feedback end
    if ctx.snap_summary then values[#values + 1] = "snap: " .. ctx.snap_summary end
  elseif ctx.mode == "RESIZE" then
    values[#values + 1] =
      string.format("RESIZE section %d/%d", ctx.shape_section_index or 0, ctx.shape_section_count or 0)
    values[#values + 1] = ctx.shape_edge and (ctx.shape_edge .. " edge") or "choose edge"
    if ctx.shape_feedback then values[#values + 1] = ctx.shape_feedback end
    if ctx.shape_snap then values[#values + 1] = "snap: " .. ctx.shape_snap end
  end
  result.text = table.concat(values, " · ")
  result.interactive = ctx.mode == "MOVE" or ctx.mode == "RESIZE"
  return result
end

local function field(label, value, raw) return { label = label, value = tostring(value or "-"), raw = raw } end

local function metric(label, value) return field(label, M.compact_mm(value), value) end

local function duration_text(minutes)
  if type(minutes) ~= "number" then return "-" end
  minutes = math.max(0, math.floor(minutes + 0.5))
  local hours = math.floor(minutes / 60)
  local remainder = minutes % 60
  if hours == 0 then return string.format("%d min", remainder) end
  if remainder == 0 then return string.format("%d h", hours) end
  return string.format("%d h %02d min", hours, remainder)
end

local function sunlight_group(value, model, selection, object)
  local study = type(value) == "table" and value.sun_study or nil
  if not study or not study.viewing or not study.calculation then return nil end
  local solar = require("roomplan.solar")
  local calculation = study.calculation
  local fields = { field("Date", study.date), field("Local time", study.time) }
  if calculation.daylight_state == "normal" then
    local sunrise = solar.format_time(calculation.sunrise_minutes)
    local sunset = solar.format_time(calculation.sunset_minutes)
    local span = math.max(1, calculation.sunset_minutes - calculation.sunrise_minutes)
    local progress = math.max(0, math.min(1, (calculation.minutes - calculation.sunrise_minutes) / span))
    fields[#fields + 1] = field("Timeline", string.format("%s → %s → %s", sunrise, study.time, sunset))
    fields[#fields + 1] = field("Progress", string.format("%d%%", math.floor(progress * 100 + 0.5)))
  elseif calculation.daylight_state == "polar_day" then
    fields[#fields + 1] = field("Daylight", "Sun remains above horizon")
  else
    fields[#fields + 1] = field("Daylight", "No sunrise on this date")
  end
  fields[#fields + 1] =
    field("Sun", string.format("az %.1f° · el %.1f°", calculation.azimuth_deg, calculation.elevation_deg))
  fields[#fields + 1] =
    field("Display", study.overlay == "daily" and "Daily direct-sun exposure" or "Current-time patches")

  local exposure = study.daily_exposure
  if study.overlay == "daily" and exposure then
    fields[#fields + 1] = field("Legend", "≤1h · ≤2h · ≤4h · ≤6h · >6h")
    local minutes
    local label
    if selection and selection.kind == "window" then
      minutes = exposure.window_minutes and exposure.window_minutes[selection.id]
      label = "This window"
    else
      local room_id = selection and selection.kind == "room" and selection.id or object and object.room_id
      minutes = room_id and exposure.room_minutes and exposure.room_minutes[room_id]
      label = room_id and "Potential sun" or nil
    end
    if label then fields[#fields + 1] = field(label, duration_text(minutes or 0)) end
    fields[#fields + 1] = field("Sampling", string.format("Every %d min · approximate", study.step_minutes or 60))
  end
  local offset = model.site and solar.number(model.site.utc_offset_minutes)
  if offset ~= nil then
    fields[#fields + 1] = field("UTC offset", solar.format_utc_offset(offset) .. " · fixed for date")
  end
  return { id = "sun_study", title = "Sun study", default_expanded = true, fields = fields }
end

local function object_diagnostics(diagnostics, selection)
  local result = {}
  if not selection then return result end
  for _, diagnostic in ipairs(diagnostics or {}) do
    local object = diagnostic.object or {}
    if object.id == selection.id and object.kind == selection.kind then result[#result + 1] = diagnostic end
  end
  return result
end

function M.properties(value, opts)
  opts = opts or {}
  local model = model_of(value)
  local compound_geometry = model.schema_version >= 2
  local selection = selection_of(value, opts)
  local diagnostics = diagnostics_of(value, opts)
  local object = find(model, selection)
  local source = type(value) == "table" and value.source or {}
  local status = type(value) == "table" and type(value.status_text) == "function" and value:status_text() or ""
  local groups = {}

  if not object then
    groups = {
      {
        id = "summary",
        title = "Summary",
        default_expanded = true,
        fields = {
          field("Rooms", #(model.rooms or {})),
          field("Doors", #(model.doors or {})),
          field("Windows", #(model.windows or {})),
          field("Outlets", #(model.outlets or {})),
          field("Furniture", #(model.furniture or {})),
          field("Units", model.units or "mm"),
        },
      },
      {
        id = "grid",
        title = "Grid",
        fields = {
          metric("Grid step", model.settings and model.settings.grid_mm),
          metric("Fine step", model.settings and model.settings.fine_step_mm),
        },
      },
      {
        id = "source",
        title = "Source",
        fields = {
          field("Adapter", source and source.adapter or "detached"),
          field("Path", source and (source.path or (source.bufnr and ("buffer #" .. source.bufnr))) or "detached"),
          field("State", status ~= "" and status or "unknown"),
        },
      },
    }
    local sun = sunlight_group(value, model, selection, object)
    if sun then table.insert(groups, 1, sun) end
    return {
      title = model.metadata and model.metadata.name or "Untitled plan",
      subtitle = "plan",
      kind = "plan",
      groups = groups,
      diagnostics = diagnostics,
    }
  end

  if selection.kind == "room" then
    local origin = object.origin_mm or {}
    local compound = compound_geometry and footprint_info(object.footprint) or nil
    local size = object.size_mm or { compound and compound.width, compound and compound.depth }
    groups[#groups + 1] = {
      id = "geometry",
      title = "Geometry",
      fields = {
        metric("X", origin[1]),
        metric("Y", origin[2]),
        metric("Width", size[1]),
        metric("Depth", size[2]),
        field(
          "Area",
          compound and string.format("%.2f m²", compound.area / 1000000)
            or (size[1] and size[2] and string.format("%.2f m²", size[1] * size[2] / 1000000) or "-")
        ),
        metric(
          "Perimeter",
          compound and compound.perimeter or (size[1] and size[2] and 2 * (size[1] + size[2]) or nil)
        ),
      },
    }
    if compound then groups[#groups].fields[#groups[#groups].fields + 1] = field("Parts", compound.parts) end
  elseif selection.kind == "furniture" then
    local center = object.center_mm or object.position_mm or {}
    local position_label = object.position_mm and "Position" or "Centre"
    local compound = compound_geometry and footprint_info(object.footprint) or nil
    local size = object.size_mm or { compound and compound.width, compound and compound.depth, object.height_mm }
    groups[#groups + 1] = {
      id = "geometry",
      title = "Geometry",
      fields = {
        field("Room", object.room_id),
        metric(position_label .. " X", center[1]),
        metric(position_label .. " Y", center[2]),
        field("Rotation", tostring(object.rotation_deg or 0) .. "°"),
        metric("Width", size[1]),
        metric("Depth", size[2]),
        metric("Height", size[3]),
      },
    }
    if compound then groups[#groups].fields[#groups[#groups].fields + 1] = field("Parts", compound.parts) end
  elseif selection.kind == "door" then
    local destination = type(object.connects_to_room_id) == "string" and object.connects_to_room_id or "outside"
    groups[#groups + 1] = {
      id = "placement",
      title = "Placement",
      fields = {
        field("Room", object.room_id),
        field("Wall", directions.label(object.side, value)),
        metric("Offset", object.offset_mm),
        metric("Width", object.width_mm),
      },
    }
    if compound_geometry and object.part_id then
      table.insert(groups[#groups].fields, 2, field("Part", object.part_id))
    end
    groups[#groups + 1] = {
      id = "connection",
      title = "Connection",
      fields = {
        field("Destination", destination),
        field("Hinge", object.hinge),
        field("Opens into", object.opens_into),
        field("Angle", tostring(object.open_angle_deg or 90) .. "°"),
      },
    }
  elseif selection.kind == "window" then
    local destination = type(object.connects_to_room_id) == "string" and object.connects_to_room_id or "outside"
    groups[#groups + 1] = {
      id = "placement",
      title = "Placement",
      fields = {
        field("Room", object.room_id),
        field("Wall", directions.label(object.side, value)),
        metric("Offset", object.offset_mm),
        metric("Width", object.width_mm),
      },
    }
    if object.part_id then table.insert(groups[#groups].fields, 2, field("Part", object.part_id)) end
    local defaults = require("roomplan.config").get().sun_study.window_defaults
    groups[#groups + 1] = {
      id = "sunlight",
      title = "Sunlight",
      fields = {
        metric("Sill height", object.sill_height_mm or defaults.sill_height_mm),
        metric("Head height", object.head_height_mm or defaults.head_height_mm),
        field(
          "Source",
          object.sill_height_mm ~= nil and object.head_height_mm ~= nil and "This window" or "Configured defaults"
        ),
      },
    }
    groups[#groups + 1] =
      { id = "connection", title = "Connection", fields = {
        field("Destination", destination),
      } }
  elseif selection.kind == "outlet" then
    if object.placement == "floor" then
      groups[#groups + 1] = {
        id = "placement",
        title = "Placement",
        fields = {
          field("Room", object.room_id),
          field("Location", "Floor"),
          metric("Local X", object.position_mm and object.position_mm[1]),
          metric("Local Y", object.position_mm and object.position_mm[2]),
        },
      }
    else
      groups[#groups + 1] = {
        id = "placement",
        title = "Placement",
        fields = {
          field("Room", object.room_id),
          field("Location", "Wall"),
          field("Wall", directions.label(object.side, value)),
          metric("Offset", object.offset_mm),
        },
      }
      if object.part_id then table.insert(groups[#groups].fields, 2, field("Part", object.part_id)) end
    end
    groups[#groups + 1] = {
      id = "specification",
      title = "Specification",
      fields = {
        field("Type", outlet_types.label(object.outlet_type) or object.outlet_type),
        field("Slots", object.slots),
      },
    }
  elseif selection.kind == "template" then
    local compound = compound_geometry and footprint_info(object.default_footprint) or nil
    local size = object.default_size_mm
      or { compound and compound.width, compound and compound.depth, object.default_height_mm }
    groups[#groups + 1] = {
      id = "defaults",
      title = "Defaults",
      fields = {
        field("Category", object.category),
        metric("Width", size[1]),
        metric("Depth", size[2]),
        metric("Height", size[3]),
      },
    }
    if compound then groups[#groups].fields[#groups[#groups].fields + 1] = field("Parts", compound.parts) end
  end
  if selection.kind == "room" or selection.kind == "furniture" then
    groups[#groups + 1] = {
      id = "appearance",
      title = "Appearance",
      fields = {
        field("Color", color.label(object.color), object.color),
      },
    }
  end
  groups[#groups + 1] = { id = "advanced", title = "Advanced", fields = { field("Stable ID", object.id) } }

  local sun = sunlight_group(value, model, selection, object)
  if sun then table.insert(groups, 1, sun) end

  return {
    title = object.name
      or (selection.kind == "window" and "Window")
      or (selection.kind == "outlet" and ((outlet_types.label(object.outlet_type) or "Outlet") .. " outlet"))
      or object.id,
    subtitle = selection.kind,
    kind = selection.kind,
    id = object.id,
    groups = groups,
    diagnostics = object_diagnostics(diagnostics, selection),
  }
end

function M.mode(value, ui_state)
  local interaction = ui_state and ui_state.interaction
  if interaction and interaction ~= "NAV" then return interaction end
  if type(value) == "table" and value.sun_study and value.sun_study.viewing then return "SUN STUDY" end
  local workflow = type(value) == "table" and value.workflow and value.workflow.kind
  if workflow then return workflow:gsub("%-", "_"):upper() end
  return type(value) == "table" and value.mode or "NAV"
end

function M.context(value, ui_state)
  local model = model_of(value)
  local selection = selection_of(value)
  local focus = ui_state and ui_state.focused_pane or "canvas"
  if selection == nil and focus == "properties" then selection = { kind = "plan" } end
  local zoom = ui_state and ui_state.zoom or nil
  local viewport = type(value) == "table" and value.viewport or nil
  local canvas_options = type(value) == "table" and value.canvas and value.canvas.handle and value.canvas.handle.opts
    or nil
  if viewport and viewport.mm_per_column and canvas_options and canvas_options.mm_per_column then
    zoom = canvas_options.mm_per_column / viewport.mm_per_column
  end
  local context = {
    model = model,
    selection = selection,
    selected_object = find(model, selection),
    diagnostics = diagnostics_of(value),
    mode = M.mode(value, ui_state),
    focus = focus,
    dirty = type(value) == "table" and type(value.model_dirty) == "function" and value:model_dirty() or false,
    conflicted = type(value) == "table" and value.source_conflicted == true or false,
    snap_enabled = type(value) ~= "table" or value.snap_enabled ~= false,
    snap_summary = type(value) == "table" and require("roomplan.geometry.snapping").summary(value.snap_guides) or nil,
    move_feedback = type(value) == "table" and value.move_feedback or nil,
    detail_level = type(value) == "table" and value.canvas_detail_level or canvas_detail.default,
    cursor_world = ui_state and ui_state.cursor_world or nil,
    zoom = zoom,
    view_rotation = viewport and (tonumber(viewport.rotation_quarters) or 0) % 4 or 0,
    minimap_enabled = type(value) == "table" and value.minimap and value.minimap.enabled == true or false,
  }
  local study = type(value) == "table" and value.sun_study or nil
  if study then
    local calculation = study.calculation or {}
    local exposure = study.daily_exposure or {}
    context.sun_study = {
      date = study.date,
      time = study.time,
      step_minutes = study.step_minutes,
      frame_duration_ms = study.frame_duration_ms,
      playing = study.playing == true,
      viewing = study.viewing == true,
      playback_state = study.playback_state,
      overlay = study.overlay or "instant",
      sunrise_minutes = calculation.sunrise_minutes,
      sunset_minutes = calculation.sunset_minutes,
      solar_noon_minutes = calculation.solar_noon_minutes,
      minutes = calculation.minutes,
      daylight_state = calculation.daylight_state,
      azimuth_deg = calculation.azimuth_deg,
      elevation_deg = calculation.elevation_deg,
      room_minutes = exposure.room_minutes,
      window_minutes = exposure.window_minutes,
      exposure_total_minutes = exposure.total_minutes,
    }
  end
  for key, item in pairs(shape_context(value)) do
    context[key] = item
  end
  context.breadcrumb = M.breadcrumb(model, context)
  return context
end

return M
