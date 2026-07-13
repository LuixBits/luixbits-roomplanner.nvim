local compat = require("roomplan.compat")
local config = require("roomplan.config")
local glyphs = require("roomplan.render.glyphs")
local health_module = require("roomplan.health")
local state = require("roomplan.state")

local function capture_health(options)
  options = options or {}
  local events = {}
  local reporter = {}
  for _, level in ipairs({ "start", "ok", "info", "warn", "error" }) do
    reporter[level] = function(message)
      events[#events + 1] = { level = level, message = tostring(message) }
    end
  end

  local original_health = compat.health
  local original_list = state.list
  local original_for_buffer = state.for_buffer
  compat.health = function() return reporter end
  state.list = function() return options.sessions or {} end
  state.for_buffer = function() return options.current end
  local ok, err = xpcall(health_module.check, debug.traceback)
  compat.health = original_health
  state.list = original_list
  state.for_buffer = original_for_buffer
  if not ok then error(err, 0) end
  return events
end

local function messages(events, level)
  local result = {}
  for _, event in ipairs(events) do
    if level == nil or event.level == level then result[#result + 1] = event.message end
  end
  return table.concat(result, "\n")
end

describe("health", function()
  it("reports compatibility, display, keymap, and no-session basics", function()
    config.reset()
    config.setup({
      canvas = { unicode = "ascii" },
      keymaps = { mappings = { empty = "", first = "x", second = "x" } },
    })
    local events = capture_health()
    local all = messages(events)
    local warnings = messages(events, "warn")
    assert_true(all:find("minimum 0.10.0", 1, true) ~= nil)
    assert_true(all:find("primary", 1, true) ~= nil)
    assert_true(all:find("requested=ascii, effective=ascii", 1, true) ~= nil)
    assert_true(warnings:find("override \"empty\" is empty", 1, true) ~= nil)
    assert_true(warnings:find("both resolve to \"x\"", 1, true) ~= nil)
    assert_true(all:find("active sessions: 0", 1, true) ~= nil)
    assert_true(all:find("source writability checks were skipped", 1, true) ~= nil)
    config.reset()
  end)

  it("lists every invalid configured glyph before reporting ASCII fallback", function()
    config.reset()
    local custom = glyphs.builtin("ascii")
    custom.wall[2] = "--"
    custom.grid = ""
    config.setup({ glyphs = custom })
    local warnings = messages(capture_health(), "warn")
    assert_true(warnings:find("glyphs.wall[2]", 1, true) ~= nil)
    assert_true(warnings:find("glyphs.grid", 1, true) ~= nil)
    assert_true(warnings:find("falls back atomically to ASCII", 1, true) ~= nil)
    config.reset()
  end)

  it("does not mistake a non-throwing parser miss for Norg availability", function()
    local language = vim.treesitter and vim.treesitter.language
    if not language or type(language.add) ~= "function" then return end
    local original_add = language.add
    language.add = function(name)
      if name == "norg" then return nil, "missing test parser" end
      return original_add(name)
    end
    local ok, events = pcall(capture_health)
    language.add = original_add
    if not ok then error(events, 0) end
    local all = messages(events)
    assert_true(all:find("Norg Tree-sitter parser unavailable", 1, true) ~= nil)
    assert_true(all:find("Norg Tree-sitter parser available", 1, true) == nil)
  end)

  it("reports current source safety hints without probing or writing", function()
    config.reset()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].readonly = true
    vim.bo[bufnr].fileencoding = "latin1"
    vim.bo[bufnr].fileformat = "dos"
    local session = {
      id = "session-health",
      source = { adapter = "json", bufnr = bufnr },
      model_dirty = function() return true end,
      pending_disk_write = true,
    }
    local all = messages(capture_health({ sessions = { session }, current = session }))
    assert_true(all:find("[dirty,pending-write]", 1, true) ~= nil)
    assert_true(all:find("source buffer is 'readonly'", 1, true) ~= nil)
    assert_true(all:find("fileencoding=latin1, fileformat=dos", 1, true) ~= nil)
    assert_true(all:find("in-place RoomPlan save requires UTF-8", 1, true) ~= nil)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    config.reset()
  end)
end)
