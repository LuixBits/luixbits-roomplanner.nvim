local compat = require("roomplan.compat")
local flow_mod = require("roomplan.ui.flow")

local M = {}

function M.measurement(flow, opts, callback)
  opts = opts or {}
  flow:input({ prompt = opts.prompt or "Measurement: ", default = opts.default and tostring(opts.default) or nil }, function(value)
    local ok, units = pcall(require, "roomplan.units")
    local parsed, err
    if ok and units.parse then
      parsed, err = units.parse(value, opts)
    else
      parsed = tonumber(value)
      if not parsed then
        err = "expected a number"
      end
    end
    if not parsed then
      compat.notify(type(err) == "table" and err.message or tostring(err), vim.log.levels.ERROR)
      flow:retry(function(current)
        M.measurement(current, opts, callback)
      end)
      return
    end
    callback(parsed, flow)
  end)
end

function M.integer(flow, opts, callback)
  opts = opts or {}
  flow:input({ prompt = opts.prompt or "Integer: ", default = opts.default and tostring(opts.default) or nil }, function(value)
    local number = tonumber(value)
    if not number or number % 1 ~= 0 or (opts.min and number < opts.min) or (opts.max and number > opts.max) then
      compat.notify(string.format("Expected a whole number%s%s", opts.min and (" >= " .. opts.min) or "", opts.max and (" <= " .. opts.max) or ""), vim.log.levels.ERROR)
      flow:retry(function(current)
        M.integer(current, opts, callback)
      end)
      return
    end
    callback(number, flow)
  end)
end

function M.confirm(session, kind, prompt, choices, callback)
  local flow, err = flow_mod.new(session, kind)
  if not flow then
    return nil, err
  end
  flow:select(choices, { prompt = prompt, kind = "roomplan_confirmation" }, function(choice)
    flow:finish()
    callback(choice)
  end)
  return flow
end

return M
