local compat = require("roomplan.compat")
local config = require("roomplan.config")
local glyph_module = require("roomplan.render.glyphs")
local state = require("roomplan.state")

local M = {}

local MINIMUM = { 0, 10, 0 }
local PRIMARY = { 0, 12, 4 }

local function version_string(version)
  return string.format("%d.%d.%d", version.major or 0, version.minor or 0, version.patch or 0)
end

local function version_at_least(version, target)
  if version.major ~= target[1] then return version.major > target[1] end
  if version.minor ~= target[2] then return version.minor > target[2] end
  return (version.patch or 0) >= target[3]
end

local function report_version(health)
  local version = vim.version()
  local installed = version_string(version)
  local minimum = table.concat(MINIMUM, ".")
  local primary = table.concat(PRIMARY, ".")
  if not version_at_least(version, MINIMUM) then
    health.error(string.format("Neovim %s is unsupported; install %s or newer", installed, minimum))
    return
  end
  health.ok(string.format("Neovim %s meets the minimum %s", installed, minimum))
  if version_at_least(version, PRIMARY) then
    health.ok(string.format("primary target %s is met", primary))
  else
    health.info(string.format("primary tested target is Neovim %s", primary))
  end
end

local function report_runtime(health)
  local runtime = _VERSION
  if type(jit) == "table" and type(jit.version) == "string" then runtime = runtime .. " / " .. jit.version end
  health.info("Lua runtime: " .. runtime .. " (RoomPlan uses Lua 5.1-compatible syntax)")
  if vim.uv and type(vim.uv.hrtime) == "function" then
    health.ok("vim.uv runtime is available")
  else
    health.error("vim.uv is unavailable; RoomPlan requires Neovim's libuv API")
  end
  if vim.o.encoding == "utf-8" then
    health.ok("editor encoding is UTF-8")
  else
    health.error("editor encoding is not UTF-8: " .. tostring(vim.o.encoding))
  end
end

local function width_of(value)
  local ok, width = pcall(vim.fn.strdisplaywidth, value)
  return ok and width or nil
end

local function glyph_failure(failures, path, value)
  if type(value) ~= "string" or value == "" then
    failures[#failures + 1] = path .. " is missing or is not a non-empty string"
    return
  end
  local width = width_of(value)
  if width ~= 1 then
    failures[#failures + 1] = string.format("%s=%q has display width %s (expected 1)", path, value, tostring(width))
  end
end

local function glyph_failures(candidate)
  local failures = {}
  local walls = type(candidate) == "table" and candidate.wall or nil
  for mask = 0, 15 do
    glyph_failure(failures, "glyphs.wall[" .. mask .. "]", type(walls) == "table" and walls[mask] or nil)
  end
  local keys = {}
  for key in pairs(glyph_module.builtin("ascii")) do
    if key ~= "wall" and key ~= "mode" then keys[#keys + 1] = key end
  end
  table.sort(keys)
  for _, key in ipairs(keys) do
    glyph_failure(failures, "glyphs." .. key, type(candidate) == "table" and candidate[key] or nil)
  end
  return failures
end

local function report_glyphs(health, effective)
  local canvas = type(effective.canvas) == "table" and effective.canvas or {}
  local requested = canvas.unicode or "auto"
  local custom = effective.glyphs
  local candidate
  if custom ~= nil then
    candidate = custom
  elseif requested == "ascii" then
    candidate = glyph_module.builtin("ascii")
  else
    candidate = glyph_module.builtin("unicode")
  end

  local resolved, fallback_reason = glyph_module.resolve(requested, custom, width_of)
  health.info(
    string.format(
      "canvas glyph mode: requested=%s, effective=%s%s",
      tostring(requested),
      tostring(resolved.mode),
      custom ~= nil and " (custom set configured)" or ""
    )
  )

  local failures = glyph_failures(candidate)
  if #failures == 0 then
    health.ok("all configured canvas glyphs occupy one display cell")
  else
    for _, failure in ipairs(failures) do
      health.warn(failure)
    end
    health.warn("invalid glyph set falls back atomically to ASCII: " .. tostring(fallback_reason))
  end

  local aspect = tonumber(canvas.cell_aspect)
  if aspect and aspect > 0 and aspect < math.huge then
    health.info(string.format("terminal cell aspect calibration: %.3g", aspect))
  else
    health.error("canvas.cell_aspect is not a positive finite number")
  end
  if requested ~= "ascii" and vim.o.ambiwidth == "double" then
    health.warn("'ambiwidth' is double; use canvas.unicode='ascii' if canvas columns do not align")
  end
end

local function report_keymaps(health, effective)
  local keymaps = type(effective.keymaps) == "table" and effective.keymaps or nil
  if not keymaps then
    health.error("effective keymaps configuration is not a table")
    return
  end
  if keymaps.enabled == false then
    health.info("RoomPlan buffer-local keymaps are disabled")
    return
  end

  local overrides = type(keymaps.mappings) == "table" and keymaps.mappings or {}
  local names = {}
  for name in pairs(overrides) do
    names[#names + 1] = name
  end
  table.sort(names)
  local disabled = 0
  local lhs_owners = {}
  local problems = 0
  for _, name in ipairs(names) do
    local lhs = overrides[name]
    if name == "" then
      health.warn("keymaps.mappings contains an empty mapping name")
      problems = problems + 1
    end
    if lhs == false then
      disabled = disabled + 1
    elseif lhs == "" then
      health.warn("keymap override " .. string.format("%q", name) .. " is empty; use false to disable it explicitly")
      problems = problems + 1
    elseif type(lhs) == "string" then
      local previous = lhs_owners[lhs]
      if previous then
        health.warn(string.format("keymap overrides %q and %q both resolve to %q", previous, name, lhs))
        problems = problems + 1
      else
        lhs_owners[lhs] = name
      end
    end
  end
  if problems == 0 then
    health.ok(string.format("keymaps enabled: %d override(s), %d explicitly disabled", #names, disabled))
  end
end

local function report_configuration(health, effective)
  if type(effective) ~= "table" then
    health.error("effective configuration is unavailable")
    return
  end
  health.ok("effective configuration loaded")
  report_glyphs(health, effective)
  report_keymaps(health, effective)
  local sun = type(effective.sun_study) == "table" and effective.sun_study or {}
  local windows = type(sun.window_defaults) == "table" and sun.window_defaults or {}
  local playback = type(sun.playback) == "table" and sun.playback or {}
  health.info(
    string.format(
      "sun study defaults: sill/head=%s/%s mm, step=%s min, frame=%s ms",
      tostring(windows.sill_height_mm),
      tostring(windows.head_height_mm),
      tostring(playback.step_minutes),
      tostring(playback.frame_duration_ms)
    )
  )
end

local function discover_neorg_version(neorg)
  if type(neorg) ~= "table" then return nil end
  for _, key in ipairs({ "version", "VERSION", "_VERSION" }) do
    if type(neorg[key]) == "string" or type(neorg[key]) == "number" then return tostring(neorg[key]) end
  end
  return nil
end

local function report_norg(health)
  local neorg = package.loaded.neorg
  if neorg then
    local version = discover_neorg_version(neorg)
    health.info("Neorg is loaded (optional)" .. (version and (", version " .. version) or ""))
  elseif vim.g.loaded_neorg then
    health.info("Neorg reports itself loaded (optional)")
  elseif #vim.api.nvim_get_runtime_file("lua/neorg/init.lua", false) > 0 then
    health.info("Neorg is installed but not loaded (optional)")
  else
    health.info("Neorg is not installed (optional)")
  end

  local parser_ok = false
  if vim.treesitter and vim.treesitter.language and type(vim.treesitter.language.add) == "function" then
    local call_ok, added = pcall(vim.treesitter.language.add, "norg")
    parser_ok = call_ok and added == true
  elseif vim.treesitter and type(vim.treesitter.get_parser) == "function" then
    local call_ok, parser = pcall(vim.treesitter.get_parser, 0, "norg")
    parser_ok = call_ok and parser ~= nil
  end
  if not parser_ok then
    health.info("Norg Tree-sitter parser unavailable; the conservative scanner remains authoritative")
    return
  end
  health.ok("Norg Tree-sitter parser available")

  local query_ok, query = pcall(function()
    if not (vim.treesitter.query and type(vim.treesitter.query.get) == "function") then return nil end
    return vim.treesitter.query.get("norg", "highlights")
  end)
  if query_ok and query then
    health.info("a public Norg Tree-sitter query is available (the scanner still verifies replacement bounds)")
  else
    health.info("no public Norg query was found; parser-free scanning is supported")
  end
end

local function session_dirty(session)
  if type(session.model_dirty) ~= "function" then return false end
  local ok, dirty = pcall(session.model_dirty, session)
  return ok and dirty or false
end

local function session_flags(session)
  local flags = {}
  if session_dirty(session) then flags[#flags + 1] = "dirty" end
  if session.source_conflicted then flags[#flags + 1] = "conflict" end
  if session.pending_disk_write then flags[#flags + 1] = "pending-write" end
  if session.source_rebind_pending then flags[#flags + 1] = "renamed" end
  if session.retained_model_at_risk then flags[#flags + 1] = "at-risk" end
  if #flags == 0 then flags[1] = "saved" end
  return flags
end

local function source_label(source)
  if source.path and source.path ~= "" then return source.path end
  if source.bufnr then return "buffer " .. tostring(source.bufnr) end
  return "<no source>"
end

local function path_parent_writable(path)
  local parent = vim.fn.fnamemodify(path, ":p:h")
  return parent, vim.fn.filewritable(parent) == 2
end

local function report_path_hint(health, path, detached)
  if type(path) ~= "string" or path == "" then
    if detached then health.warn("current session has neither a live source buffer nor a destination path") end
    return
  end
  local stat = vim.uv and vim.uv.fs_lstat(path) or nil
  if stat and stat.type ~= "file" then
    health.warn(string.format("source path is a %s, not a regular file: %s", tostring(stat.type), path))
  elseif stat and vim.fn.filewritable(path) ~= 1 then
    health.warn("source file is not reported writable: " .. path)
  elseif stat then
    health.ok("source file is reported writable")
  else
    local parent, writable = path_parent_writable(path)
    if writable then
      health.ok("destination directory is reported writable: " .. parent)
    else
      health.warn("destination directory is not reported writable: " .. parent)
    end
  end

  if detached then
    local parent, writable = path_parent_writable(path)
    if not stat and writable then
      health.ok("detached save may attempt same-directory atomic creation (no probe file was created)")
    elseif stat then
      health.warn("detached atomic creation requires a new destination; this path already exists")
    else
      health.warn(
        "same-directory atomic creation is unlikely to succeed because the parent is not writable: " .. parent
      )
    end
  end
end

local function report_source(health, session)
  local source = type(session.source) == "table" and session.source or {}
  local bufnr = source.bufnr
  local live_buffer = type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr)
  if live_buffer then
    local readonly = vim.bo[bufnr].readonly
    local modifiable = vim.bo[bufnr].modifiable
    if readonly then health.warn("source buffer is 'readonly'") end
    if not modifiable then health.warn("source buffer is not modifiable") end
    if not readonly and modifiable then health.ok("source buffer is modifiable and not 'readonly'") end

    local fileencoding = (vim.bo[bufnr].fileencoding or ""):lower()
    local encoding = fileencoding == "" and "utf-8 (editor default)" or fileencoding
    local fileformat = vim.bo[bufnr].fileformat
    health.info(
      string.format(
        "source buffer format: fileencoding=%s, fileformat=%s, BOM=%s",
        encoding,
        fileformat,
        vim.bo[bufnr].bomb and "yes" or "no"
      )
    )
    if fileencoding ~= "" and fileencoding ~= "utf-8" and fileencoding ~= "utf8" then
      health.warn("in-place RoomPlan save requires UTF-8; use Save As for this source")
    elseif fileformat ~= "unix" then
      health.info("non-Unix line endings are supported and preserved through the source buffer")
    end
  else
    health.info("current session has no live source buffer")
  end
  report_path_hint(health, source.path, not live_buffer)
end

local function current_session(sessions)
  local ok, current = pcall(state.for_buffer, vim.api.nvim_get_current_buf())
  if ok and current then return current end
  if #sessions == 1 then return sessions[1] end
  return nil
end

local function report_sessions(health)
  local sessions = state.list()
  health.info(string.format("active sessions: %d", #sessions))
  for _, session in ipairs(sessions) do
    local source = type(session.source) == "table" and session.source or {}
    health.info(
      string.format(
        "%s: adapter=%s, source=%s [%s]",
        tostring(session.id or "<unknown>"),
        tostring(source.adapter or "unknown"),
        source_label(source),
        table.concat(session_flags(session), ",")
      )
    )
  end

  local current = current_session(sessions)
  if current then
    health.start("Current source")
    report_source(health, current)
  elseif #sessions > 1 then
    health.info("focus a RoomPlan source/canvas to report source writability")
  else
    health.info("no active RoomPlan source; source writability checks were skipped")
  end
end

local function report_window(health, effective)
  local canvas = type(effective.canvas) == "table" and effective.canvas or {}
  local ui = type(effective.ui) == "table" and effective.ui or {}
  local workspace = type(ui.workspace) == "table" and ui.workspace or {}
  local width = vim.api.nvim_win_get_width(0)
  local height = vim.api.nvim_win_get_height(0)
  local minimum_width = tonumber(workspace.min_canvas_width) or 55
  local minimum_height = (tonumber(workspace.min_canvas_height) or 10)
    + (tonumber(canvas.header_lines) or 1)
    + (tonumber(workspace.footer_height) or 1)
  if width < minimum_width or height < minimum_height then
    health.warn(
      string.format(
        "current window is %dx%d; below the useful canvas hint of %dx%d, so RoomPlan will use a compact/degraded layout",
        width,
        height,
        minimum_width,
        minimum_height
      )
    )
  else
    health.ok(string.format("current window %dx%d can host the configured minimum canvas", width, height))
  end
end

local function report_autosave(health, effective)
  local autosave = type(effective.autosave) == "table" and effective.autosave or {}
  if autosave.enabled then
    health.warn("autosave enabled" .. (autosave.norg and " including guarded Norg mode" or " for standalone plans"))
  else
    health.ok("autosave disabled")
  end
end

function M.check()
  local health = compat.health()
  health.start("roomplan.nvim")
  report_version(health)
  report_runtime(health)

  local ok, effective = pcall(config.get)
  if not ok then effective = nil end
  health.start("Configuration and display")
  report_configuration(health, effective)
  report_window(health, effective or {})

  health.start("Optional Norg integration")
  report_norg(health)

  health.start("Sessions")
  report_sessions(health)
  report_autosave(health, effective or {})
end

return M
