local compat = require("roomplan.compat")
local config = require("roomplan.config")
local state = require("roomplan.state")

local M = {}

local unicode_glyphs = { "─", "│", "┌", "┐", "└", "┘", "├", "┤", "┬", "┴", "┼", "╱", "╲" }

function M.check()
  local health = compat.health()
  health.start("roomplan.nvim")
  local version = vim.version()
  if compat.supported() then
    health.ok(string.format("Neovim %d.%d.%d (minimum 0.10)", version.major, version.minor, version.patch))
  else
    health.error(string.format("Neovim %d.%d.%d is unsupported; install 0.10+", version.major, version.minor, version.patch))
  end

  local effective = config.get()
  health.info("canvas mode: " .. effective.canvas.unicode)
  health.info(string.format("terminal cell aspect calibration: %.3g", effective.canvas.cell_aspect))
  local bad = {}
  for _, glyph in ipairs(unicode_glyphs) do
    if vim.fn.strdisplaywidth(glyph) ~= 1 then
      bad[#bad + 1] = glyph
    end
  end
  if #bad == 0 then
    health.ok("built-in Unicode canvas glyphs have display width 1")
  else
    health.warn("Unicode glyph width is unsuitable; use canvas.unicode='ascii': " .. table.concat(bad, " "))
  end

  local parser_ok = pcall(vim.treesitter.get_parser, 0, "norg")
  if parser_ok then
    health.ok("Norg Tree-sitter parser available")
  else
    health.info("Norg Tree-sitter parser unavailable; conservative scanner will be used")
  end
  if package.loaded.neorg then
    health.info("Neorg is loaded (optional)")
  else
    health.info("Neorg is not loaded (optional)")
  end

  local sessions = state.list()
  health.info(string.format("active sessions: %d", #sessions))
  for _, session in ipairs(sessions) do
    local source = session.source or {}
    local flags = {}
    if session.model_dirty and session:model_dirty() then flags[#flags + 1] = "dirty" end
    if session.source_conflicted then flags[#flags + 1] = "conflict" end
    if session.pending_disk_write then flags[#flags + 1] = "pending-write" end
    health.info(string.format("%s: %s %s [%s]", session.id, source.adapter or "?", source.path or ("buffer " .. tostring(source.bufnr)), table.concat(flags, ",")))
  end
  if effective.autosave.enabled then
    health.warn("autosave enabled" .. (effective.autosave.norg and " including guarded Norg mode" or " for standalone plans"))
  else
    health.ok("autosave disabled by default")
  end
end

return M
