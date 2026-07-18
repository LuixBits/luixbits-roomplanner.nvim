local common = require("roomplan.ui.panels.common")

local M = {}

local borders = {
  unicode = {
    top_left = "╭",
    top_right = "╮",
    middle_left = "├",
    middle_right = "┤",
    bottom_left = "╰",
    bottom_right = "╯",
    h = "─",
    v = "│",
  },
  ascii = {
    top_left = "+",
    top_right = "+",
    middle_left = "+",
    middle_right = "+",
    bottom_left = "+",
    bottom_right = "+",
    h = "-",
    v = "|",
  },
}

local function section_id(group, index)
  if type(group.id) == "string" and group.id ~= "" then return group.id end
  local id = tostring(group.title or "section"):lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  return id ~= "" and id or ("section_" .. index)
end

local function is_collapsed(section, index, opts)
  local configured = opts.collapsed_sections or opts.collapsed or {}
  if configured[section.id] ~= nil then return configured[section.id] == true end
  if section.default_expanded ~= nil then return section.default_expanded ~= true end
  return index ~= 1
end

local function section_header(section, expanded, width, first, border)
  local marker = expanded and (border == borders.ascii and "v" or "▾") or (border == borders.ascii and ">" or "▸")
  local count = expanded and "" or string.format(" (%d)", section.count or #(section.fields or {}))
  local caption = string.format("%s %s%s", marker, section.title or "Details", count)
  if width < 7 then return common.truncate(caption, width), 0, #caption end

  local left_corner = first and border.top_left or border.middle_left
  local right_corner = first and border.top_right or border.middle_right
  local left = left_corner .. border.h .. " "
  local caption_width = math.max(0, width - common.width(left) - common.width(right_corner) - 1)
  caption = common.truncate(caption, caption_width)
  local fill = math.max(0, caption_width - common.width(caption))
  local line = left .. caption .. " " .. string.rep(border.h, fill) .. right_corner
  return line, #left, #left + #caption
end

local function add_section_header(document, section, expanded, first, border)
  local line, caption_start, caption_end = section_header(section, expanded, document.width, first, border)
  local row_map = {
    kind = "section",
    section = section.id,
    id = section.id,
    expanded = expanded,
    group = section.source,
  }
  common.line(document, line, {
    row_map = row_map,
    highlights = {
      { start_col = 0, end_col = -1, hl_group = "RoomPlanWorkspaceMuted" },
      {
        start_col = caption_start,
        end_col = caption_end,
        hl_group = expanded and "RoomPlanWorkspaceSection" or "RoomPlanWorkspaceStatus",
      },
    },
  })
end

local function add_field(document, field, border)
  if document.width < 4 then
    common.line(document, field.value or "-", {
      highlights = { { start_col = 0, end_col = -1, hl_group = "RoomPlanWorkspaceMuted" } },
    })
    return
  end

  local inner_width = document.width - 2
  local label_width = math.min(12, math.max(5, math.floor(inner_width * 0.38)))
  local label = common.pad(field.label or "", label_width)
  local prefix = " " .. label .. " "
  local value = common.truncate(field.value or "-", math.max(0, inner_width - common.width(prefix)))
  local content = common.pad(prefix .. value, inner_width)
  local line = border.v .. content .. border.v
  common.line(document, line, {
    highlights = {
      { start_col = 0, end_col = #border.v, hl_group = "RoomPlanWorkspaceMuted" },
      { start_col = #line - #border.v, end_col = -1, hl_group = "RoomPlanWorkspaceMuted" },
      {
        start_col = #border.v + 1,
        end_col = #border.v + 1 + #label,
        hl_group = field.key and "RoomPlanWorkspaceKey" or "RoomPlanWorkspaceMuted",
      },
      {
        start_col = #border.v + #prefix,
        end_col = #border.v + #prefix + #value,
        hl_group = "RoomPlanWorkspaceValue",
      },
    },
  })
end

local function add_static_header(document, title, first, border)
  local section = { title = title, fields = {} }
  local line, caption_start, caption_end = section_header(section, true, document.width, first, border)
  common.line(document, line, {
    highlights = {
      { start_col = 0, end_col = -1, hl_group = "RoomPlanWorkspaceMuted" },
      { start_col = caption_start, end_col = caption_end, hl_group = "RoomPlanWorkspaceSection" },
    },
  })
end

local function add_controls(document, view, border)
  local controls = view.controls or {}
  if #controls == 0 then return false end
  add_static_header(document, "Canvas controls", true, border)
  if view.controls_note then
    add_field(document, { label = "Use", value = view.controls_note }, border)
  end
  for _, control in ipairs(controls) do
    add_field(document, {
      label = control.key_label or "-",
      value = control.label or control.id or "Command",
      key = control.key_label ~= nil,
    }, border)
  end
  return true
end

local function add_diagnostic(document, diagnostic, border)
  local severity = diagnostic.severity == "error" and "error"
    or diagnostic.severity == "warning" and "warning"
    or "info"
  local marker = severity == "error" and "E" or severity == "warning" and "W" or "i"
  local message = diagnostic.message or diagnostic.code or "Validation issue"
  local content = common.pad(" " .. marker .. " " .. message, math.max(0, document.width - 2))
  local line = document.width < 4 and (marker .. " " .. message) or (border.v .. content .. border.v)
  common.line(document, line, {
    highlights = {
      {
        start_col = document.width < 4 and 0 or #border.v + 1,
        end_col = document.width < 4 and 1 or #border.v + 2,
        hl_group = severity == "error" and "RoomPlanWorkspaceError"
          or severity == "warning" and "RoomPlanWorkspaceWarning"
          or "RoomPlanWorkspaceInfo",
      },
    },
  })
end

local function sections(view)
  local result = {}
  for index, group in ipairs(view.groups or {}) do
    result[#result + 1] = {
      id = section_id(group, index),
      title = group.title,
      fields = group.fields or {},
      count = #(group.fields or {}),
      default_expanded = group.default_expanded,
      source = group,
    }
  end
  if #(view.diagnostics or {}) > 0 then
    result[#result + 1] = {
      id = "validation",
      title = "Validation",
      diagnostics = view.diagnostics,
      count = #view.diagnostics,
      default_expanded = true,
      source = { id = "validation", title = "Validation", diagnostics = view.diagnostics },
    }
  end
  return result
end

function M.render(view, width, height, opts)
  opts = opts or {}
  local document = common.document(width)
  local border = opts.ascii == true and borders.ascii or borders.unicode
  local title = view.title or "Details"
  local subtitle = view.subtitle and view.subtitle ~= "" and (" · " .. view.subtitle) or ""
  local context_title = tostring(view.context_title or "NAV")
  if context_title == "NAV" then
    local line = title .. subtitle .. " · NAV"
    common.line(document, line, {
      highlights = {
        { start_col = 0, end_col = #title, hl_group = "RoomPlanWorkspaceTitle" },
        { start_col = #title, end_col = -1, hl_group = "RoomPlanWorkspaceMuted" },
      },
    })
  else
    common.line(document, context_title, {
      highlights = { { start_col = 0, end_col = -1, hl_group = "RoomPlanWorkspaceTitle" } },
    })
    common.line(document, title .. subtitle, {
      highlights = { { start_col = 0, end_col = -1, hl_group = "RoomPlanWorkspaceMuted" } },
    })
  end

  local has_controls = add_controls(document, view, border)

  for index, section in ipairs(sections(view)) do
    local collapsed = is_collapsed(section, index, opts)
    add_section_header(document, section, not collapsed, index == 1 and not has_controls, border)
    if not collapsed then
      for _, field in ipairs(section.fields or {}) do add_field(document, field, border) end
      for _, diagnostic in ipairs(section.diagnostics or {}) do add_diagnostic(document, diagnostic, border) end
    end
  end

  if document.width >= 2 then
    local bottom = border.bottom_left .. string.rep(border.h, math.max(0, document.width - 2)) .. border.bottom_right
    common.line(document, bottom, {
      highlights = { { start_col = 0, end_col = -1, hl_group = "RoomPlanWorkspaceMuted" } },
    })
  end
  document.pane_title = "Details · " .. context_title
  return common.finish(document, height)
end

return M
