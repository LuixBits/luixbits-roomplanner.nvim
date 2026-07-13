local h = require("tests.harness")

local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h:h")

local function read(path)
  local handle = assert(io.open(path, "rb"))
  local contents = handle:read("*a")
  handle:close()
  return contents
end

local function local_target(destination)
  destination = destination:match("^%s*(.-)%s*$")
  if destination:sub(1, 1) == "<" and destination:sub(-1) == ">" then
    destination = destination:sub(2, -2)
  end
  destination = destination:match("^[^#?]*") or destination
  if destination == "" or destination:match("^[%a][%w+.-]*:") or destination:sub(1, 2) == "//" then
    return nil
  end
  return destination
end

h.describe("documentation", function()
  h.it("keeps every relative Markdown link resolvable", function()
    local paths = vim.fn.glob(root .. "/docs/**/*.md", false, true)
    vim.list_extend(paths, {
      root .. "/README.md",
      root .. "/CONTRIBUTING.md",
      root .. "/RELEASE.md",
    })
    local failures = {}
    for _, path in ipairs(paths) do
      local directory = vim.fn.fnamemodify(path, ":h")
      for destination in read(path):gmatch("%b[]%((.-)%)") do
        local target = local_target(destination)
        if target then
          local resolved = vim.fn.fnamemodify(directory .. "/" .. target, ":p")
          if not vim.uv.fs_stat(resolved) then
            failures[#failures + 1] = string.format("%s -> %s", vim.fn.fnamemodify(path, ":."), destination)
          end
        end
      end
    end
    h.eq({}, failures)
  end)
end)
