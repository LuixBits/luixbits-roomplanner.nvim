-- Pure presentation layer: canonical model/session state in, display-only view
-- models out.  No returned table is part of the saved model.

local color = require("roomplan.color")

local M = {}

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

local function diagnostics_of(value, opts)
  if opts and opts.diagnostics ~= nil then return opts.diagnostics end
  return type(value) == "table" and value.validation or {}
end

local function lower(value)
  return tostring(value or ""):lower()
end

local function selected(selection, kind, id)
  return selection ~= nil and selection.kind == kind and selection.id == id
end

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
        or diagnostic.severity == "warning" and "warnings" or "info"
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
  local haystack = table.concat({
    row.kind or "", row.id or "", row.name or "", row.label or "", row.room_name or "",
  }, " "):lower()
  return haystack:find(query, 1, true) ~= nil
end

local function room_lookup(model)
  local result = {}
  for _, room in ipairs(model.rooms or {}) do result[room.id] = room end
  return result
end

---Build hierarchical object rows. Rooms retain model order; their doors are
---listed before furniture, also in canonical model order.
function M.objects(value, opts)
  opts = opts or {}
  local model = model_of(value)
  local selection = selection_of(value, opts)
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
      label = string.format("%s → %s", door.side or "Door", destination_name),
      detail = short_mm(door.width_mm),
      object = door,
    })
  end
  for _, furniture in ipairs(model.furniture or {}) do
    local size = furniture.size_mm or {}
    child(furniture.room_id, {
      kind = "furniture",
      id = furniture.id,
      name = furniture.name or furniture.id,
      room_name = rooms[furniture.room_id] and rooms[furniture.room_id].name or furniture.room_id,
      label = furniture.name or furniture.id or "Furniture",
      detail = string.format("%s × %s", short_mm(size[1]), short_mm(size[2])),
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
      counts = { errors = 0, warnings = 0, info = 0, items = {} },
    },
  }

  for _, room in ipairs(model.rooms or {}) do
    local size = room.size_mm or {}
    local room_row = {
      kind = "room",
      id = room.id,
      name = room.name or room.id,
      label = room.name or room.id or "Room",
      detail = string.format("%s × %s", short_mm(size[1]), short_mm(size[2])),
      object = room,
      depth = 0,
      expandable = #(children[room.id] or {}) > 0,
      expanded = expanded[room.id] ~= false,
      selected = selected(selection, "room", room.id),
      counts = counts_for(indexed, "room", room.id),
    }
    local presented_children = {}
    for _, row in ipairs(children[room.id] or {}) do
      row.depth = 1
      row.selected = selected(selection, row.kind, row.id)
      row.counts = counts_for(indexed, row.kind, row.id)
      if matches_filter(row, query) then presented_children[#presented_children + 1] = row end
    end
    if matches_filter(room_row, query) or #presented_children > 0 then
      rows[#rows + 1] = room_row
      if room_row.expanded then
        for _, row in ipairs(presented_children) do rows[#rows + 1] = row end
      end
    end
  end

  for _, template in ipairs(model.custom_templates or {}) do
    local size = template.default_size_mm or {}
    local row = {
      kind = "template",
      id = template.id,
      name = template.name or template.id,
      label = template.name or template.id or "Custom",
      detail = string.format("%s × %s × %s", short_mm(size[1]), short_mm(size[2]), short_mm(size[3])),
      object = template,
      depth = 0,
      selected = selected(selection, "template", template.id),
      counts = counts_for(indexed, "template", template.id),
    }
    if matches_filter(row, query) then rows[#rows + 1] = row end
  end

  for _, row in ipairs(orphans) do
    row.depth = 0
    row.orphan = true
    row.selected = selected(selection, row.kind, row.id)
    row.counts = counts_for(indexed, row.kind, row.id)
    if matches_filter(row, query) then rows[#rows + 1] = row end
  end

  local summary = string.format("%d rooms · %d doors · %d items",
    #(model.rooms or {}), #(model.doors or {}), #(model.furniture or {}))
  if #(model.custom_templates or {}) > 0 then
    summary = summary .. string.format(" · %d templates", #model.custom_templates)
  end
  return {
    title = model.metadata and model.metadata.name or "Untitled plan",
    summary = summary,
    counts = {
      rooms = #(model.rooms or {}),
      doors = #(model.doors or {}),
      furniture = #(model.furniture or {}),
      templates = #(model.custom_templates or {}),
    },
    room_count = #(model.rooms or {}),
    rows = rows,
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
      or diagnostic.severity == "warning" and "warning" or "info"
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
    or selection.kind == "furniture" and model.furniture
    or selection.kind == "template" and model.custom_templates
  for _, object in ipairs(collection or {}) do
    if object.id == selection.id then return object end
  end
end

local function field(label, value, raw)
  return { label = label, value = tostring(value or "-"), raw = raw }
end

local function metric(label, value)
  return field(label, M.compact_mm(value), value)
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
  local selection = selection_of(value, opts)
  local diagnostics = diagnostics_of(value, opts)
  local object = find(model, selection)
  local source = type(value) == "table" and value.source or {}
  local status = type(value) == "table" and type(value.status_text) == "function" and value:status_text() or ""
  local groups = {}

  if not object then
    groups = {
      { id = "summary", title = "Summary", default_expanded = true, fields = {
        field("Rooms", #(model.rooms or {})), field("Doors", #(model.doors or {})),
        field("Furniture", #(model.furniture or {})), field("Units", model.units or "mm"),
      } },
      { id = "grid", title = "Grid", fields = {
        metric("Grid step", model.settings and model.settings.grid_mm),
        metric("Fine step", model.settings and model.settings.fine_step_mm),
      } },
      { id = "source", title = "Source", fields = {
        field("Adapter", source and source.adapter or "detached"),
        field("Path", source and (source.path or (source.bufnr and ("buffer #" .. source.bufnr))) or "detached"),
        field("State", status ~= "" and status or "unknown"),
      } },
    }
    return {
      title = model.metadata and model.metadata.name or "Untitled plan",
      subtitle = "plan",
      kind = "plan",
      groups = groups,
      diagnostics = diagnostics,
    }
  end

  if selection.kind == "room" then
    local origin, size = object.origin_mm or {}, object.size_mm or {}
    groups[#groups + 1] = { id = "geometry", title = "Geometry", fields = {
      metric("X", origin[1]), metric("Y", origin[2]),
      metric("Width", size[1]), metric("Depth", size[2]),
      field("Area", size[1] and size[2] and string.format("%.2f m²", size[1] * size[2] / 1000000) or "-"),
    } }
  elseif selection.kind == "furniture" then
    local center, size = object.center_mm or {}, object.size_mm or {}
    groups[#groups + 1] = { id = "geometry", title = "Geometry", fields = {
      field("Room", object.room_id), metric("Centre X", center[1]), metric("Centre Y", center[2]),
      field("Rotation", tostring(object.rotation_deg or 0) .. "°"),
      metric("Width", size[1]), metric("Depth", size[2]), metric("Height", size[3]),
    } }
  elseif selection.kind == "door" then
    local destination = type(object.connects_to_room_id) == "string" and object.connects_to_room_id or "outside"
    groups[#groups + 1] = { id = "placement", title = "Placement", fields = {
      field("Room", object.room_id), field("Wall", object.side),
      metric("Offset", object.offset_mm), metric("Width", object.width_mm),
    } }
    groups[#groups + 1] = { id = "connection", title = "Connection", fields = {
      field("Destination", destination), field("Hinge", object.hinge),
      field("Opens into", object.opens_into), field("Angle", tostring(object.open_angle_deg or 90) .. "°"),
    } }
  elseif selection.kind == "template" then
    local size = object.default_size_mm or {}
    groups[#groups + 1] = { id = "defaults", title = "Defaults", fields = {
      field("Category", object.category), metric("Width", size[1]), metric("Depth", size[2]), metric("Height", size[3]),
    } }
  end
  if selection.kind == "room" or selection.kind == "furniture" then
    groups[#groups + 1] = { id = "appearance", title = "Appearance", fields = {
      field("Color", color.label(object.color), object.color),
    } }
  end
  groups[#groups + 1] = { id = "advanced", title = "Advanced", fields = { field("Stable ID", object.id) } }

  return {
    title = object.name or object.id,
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
  local canvas_options = type(value) == "table" and value.canvas and value.canvas.handle
    and value.canvas.handle.opts or nil
  if viewport and viewport.mm_per_column and canvas_options and canvas_options.mm_per_column then
    zoom = canvas_options.mm_per_column / viewport.mm_per_column
  end
  return {
    model = model,
    selection = selection,
    selected_object = find(model, selection),
    diagnostics = diagnostics_of(value),
    mode = M.mode(value, ui_state),
    focus = focus,
    dirty = type(value) == "table" and type(value.model_dirty) == "function" and value:model_dirty() or false,
    conflicted = type(value) == "table" and value.source_conflicted == true or false,
    snap_enabled = type(value) ~= "table" or value.snap_enabled ~= false,
    cursor_world = ui_state and ui_state.cursor_world or nil,
    zoom = zoom,
    view_rotation = viewport and (tonumber(viewport.rotation_quarters) or 0) % 4 or 0,
  }
end

return M
