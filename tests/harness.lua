local M = { tests = {}, prefix = "" }

local function inspect(value)
  return vim.inspect(value)
end

function M.describe(name, fn)
  local previous = M.prefix
  M.prefix = previous == "" and name or (previous .. " / " .. name)
  local ok, err = pcall(fn)
  M.prefix = previous
  if not ok then
    error(err, 0)
  end
end

function M.it(name, fn)
  M.tests[#M.tests + 1] = { name = M.prefix == "" and name or (M.prefix .. " / " .. name), fn = fn }
end

M.test = M.it

function M.eq(expected, actual, message)
  if not vim.deep_equal(expected, actual) then
    error((message or "values differ") .. "\nexpected: " .. inspect(expected) .. "\nactual:   " .. inspect(actual), 2)
  end
end

function M.truthy(value, message)
  if not value then
    error(message or ("expected truthy, got " .. inspect(value)), 2)
  end
  return value
end

function M.falsy(value, message)
  if value then
    error(message or ("expected falsy, got " .. inspect(value)), 2)
  end
end

function M.matches(pattern, value, message)
  if not tostring(value):match(pattern) then
    error(message or ("expected " .. inspect(value) .. " to match " .. pattern), 2)
  end
end

function M.raises(fn, pattern)
  local ok, err = pcall(fn)
  if ok then
    error("expected function to raise", 2)
  end
  if pattern and not tostring(err):match(pattern) then
    error("error did not match " .. pattern .. ": " .. tostring(err), 2)
  end
  return err
end

function M.run()
  local failures = {}
  for _, case in ipairs(M.tests) do
    local ok, err = xpcall(case.fn, debug.traceback)
    if ok then
      io.stdout:write("ok - " .. case.name .. "\n")
    else
      failures[#failures + 1] = case.name .. "\n" .. tostring(err)
      io.stderr:write("not ok - " .. case.name .. "\n")
    end
  end
  if #failures > 0 then
    io.stderr:write(table.concat(failures, "\n\n") .. "\n")
    vim.cmd("cquit 1")
    return
  end
  io.stdout:write(string.format("%d tests passed\n", #M.tests))
end

_G.describe = M.describe
_G.it = M.it
_G.test = M.test
_G.assert_equal = function(actual, expected, message)
  return M.eq(expected, actual, message)
end
_G.assert_true = M.truthy

return M
