local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h")
vim.opt.runtimepath:prepend(root)

local harness = dofile(root .. "/tests/harness.lua")
package.loaded["tests.harness"] = harness
local specs = vim.fn.glob(root .. "/tests/unit/*_spec.lua", false, true)
vim.list_extend(specs, vim.fn.glob(root .. "/tests/integration/*_spec.lua", false, true))
table.sort(specs)
for _, path in ipairs(specs) do
  local ok, err = pcall(dofile, path)
  if not ok then
    error("failed loading " .. path .. ": " .. tostring(err), 0)
  end
end
harness.run()
