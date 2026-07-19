local M = {}

function M.setup(opts)
  require("roomplan.commands").register()
  return require("roomplan.config").setup(opts or {})
end

local function call(method, ...) return require("roomplan.controller")[method](nil, ...) end

function M.open(opts, callback) return call("open", opts or {}, callback) end
function M.init(opts, callback) return call("init_source", opts or {}, callback) end
function M.save(opts, callback) return call("save", opts or {}, callback) end
function M.save_as(path, opts, callback)
  opts = opts or {}
  opts.args = path
  return call("save_as", opts, callback)
end
function M.reload(opts, callback) return call("reload", opts or {}, callback) end
function M.set_aspect(ratio, opts, callback)
  if type(ratio) == "table" then
    callback = type(opts) == "function" and opts or callback
    opts = ratio
    ratio = opts.ratio
  elseif type(opts) == "function" then
    callback, opts = opts, {}
  end
  opts = vim.tbl_extend("force", opts or {}, { ratio = ratio })
  return call("set_aspect", opts, callback)
end
-- Compatibility alias retained for configurations written before set_aspect
-- became the canonical public name.
M.aspect = M.set_aspect
function M.rotate_view(direction) return call("rotate_view", direction or "clockwise") end
function M.set_canvas_detail(level) return call("set_detail_level", level or "cycle") end
function M.sun_study() return call("sun_study") end
function M.toggle_minimap() return call("toggle_minimap") end
function M.hide(opts) return call("hide", opts or {}) end
function M.close(opts, callback) return call("close", opts or {}, callback) end
function M.validate(opts) return call("validate", opts or {}) end
function M.sessions() return require("roomplan.state").list() end

return M
