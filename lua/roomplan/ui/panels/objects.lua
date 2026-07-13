local common = require("roomplan.ui.panels.common")

local M = {}

local kind_icons = {
  plan = "P",
  room = "R",
  door = "D",
  furniture = "F",
  template = "T",
}

local kind_highlights = {
  plan = "RoomPlanWorkspacePlan",
  room = "RoomPlanWorkspaceRoom",
  door = "RoomPlanWorkspaceDoor",
  furniture = "RoomPlanWorkspaceFurniture",
  template = "RoomPlanWorkspaceValue",
}

local function count_badge(counts)
  counts = counts or {}
  local values = {}
  if (counts.errors or 0) > 0 then values[#values + 1] = "E" .. counts.errors end
  if (counts.warnings or 0) > 0 then values[#values + 1] = "W" .. counts.warnings end
  return #values > 0 and (" " .. table.concat(values, " ")) or ""
end

local function summary(view)
  local counts = view.counts or {}
  local parts = {
    string.format("%dR", counts.rooms or view.room_count or 0),
    string.format("%dD", counts.doors or 0),
    string.format("%dF", counts.furniture or 0),
  }
  if (counts.templates or 0) > 0 then parts[#parts + 1] = string.format("%dT", counts.templates) end
  return table.concat(parts, " ")
end

local function add_header(document, view, opts)
  local objects = opts.active == "issues" and "Objects" or "[Objects]"
  local issues = opts.active == "issues" and "[Issues]" or "Issues"
  local line = string.format("%s  %s · %s", objects, issues, summary(view))
  local active = opts.active == "issues" and issues or objects
  local active_at = assert(line:find(active, 1, true)) - 1
  common.line(document, line, {
    highlights = {
      { start_col = 0, end_col = -1, hl_group = "RoomPlanWorkspaceMuted" },
      { start_col = active_at, end_col = active_at + #active, hl_group = "RoomPlanWorkspaceTitle" },
    },
  })
  if view.filter and view.filter ~= "" then
    common.line(document, "/ " .. view.filter, {
      highlights = { { start_col = 0, end_col = -1, hl_group = "RoomPlanWorkspaceStatus" } },
    })
  end
end

local function row_text(row, width, ascii, show_details)
  local branch = " "
  if row.expandable then
    branch = row.expanded and (ascii and "v" or "▾") or (ascii and ">" or "▸")
  elseif (row.depth or 0) > 0 then
    branch = ascii and "-" or "└"
  end
  local marker = row.selected and (ascii and ">" or "›") or " "
  local indent = string.rep("  ", row.depth or 0)
  local icon = kind_icons[row.kind] or "•"
  local orphan = row.orphan and "! " or ""
  local label = orphan .. (row.label or row.name or row.id or "?")
  if row.detail and (row.selected or show_details) then label = label .. " · " .. row.detail end

  local prefix = string.format("%s %s%s %s ", marker, indent, branch, icon)
  local badge = count_badge(row.counts)
  local available = math.max(0, width - common.width(badge))
  local base = common.truncate(prefix .. label, available)
  if badge ~= "" then base = common.pad(base, available) end
  return base .. badge, prefix, icon, badge
end

function M.render(view, width, height, opts)
  opts = opts or {}
  local document = common.document(width)
  add_header(document, view, opts)

  for _, row in ipairs(view.rows or {}) do
    local line, prefix, icon, badge = row_text(row, width, opts.ascii == true, opts.show_details == true)
    local spans = {}
    local counts = row.counts or {}
    if row.selected then
      spans[#spans + 1] = { start_col = 0, end_col = -1, hl_group = "RoomPlanWorkspaceSelected" }
    else
      local icon_at = #prefix - #icon - 1
      spans[#spans + 1] = {
        start_col = icon_at,
        end_col = icon_at + #icon,
        hl_group = kind_highlights[row.kind] or "RoomPlanWorkspaceStatus",
      }
    end
    if badge ~= "" then
      spans[#spans + 1] = {
        start_col = #line - #badge,
        end_col = -1,
        hl_group = (counts.errors or 0) > 0 and "RoomPlanWorkspaceError" or "RoomPlanWorkspaceWarning",
      }
    end
    common.line(document, line, { row_map = row, highlights = spans })
  end

  if (view.room_count or 0) == 0 then
    common.line(document, "No rooms yet · [a] Add room", {
      highlights = {
        { start_col = 0, end_col = 12, hl_group = "RoomPlanWorkspaceMuted" },
        { start_col = 15, end_col = -1, hl_group = "RoomPlanWorkspaceStatus" },
      },
    })
  end
  return common.finish(document, height)
end

return M
