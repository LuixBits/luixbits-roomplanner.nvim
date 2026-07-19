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
    vim.list_extend(paths, vim.fn.glob(root .. "/*.md", false, true))
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

  h.it("documents every registered command in Markdown and Vim help", function()
    require("roomplan.commands").register()
    local markdown = read(root .. "/docs/reference/commands.md")
    local help = read(root .. "/doc/roomplan.txt")
    local missing = {}
    for name in pairs(vim.api.nvim_get_commands({})) do
      if name:match("^RoomPlan") then
        if not markdown:find(":" .. name, 1, true) then
          missing[#missing + 1] = name .. " (Markdown)"
        end
        if not help:find("*:" .. name .. "*", 1, true) then
          missing[#missing + 1] = name .. " (help)"
        end
      end
    end
    table.sort(missing)
    h.eq({}, missing)
  end)

  h.it("documents every high-level Lua function in Markdown and Vim help", function()
    local public = require("roomplan")
    local markdown = read(root .. "/docs/reference/lua-api.md")
    local help = read(root .. "/doc/roomplan.txt")
    local missing = {}
    for name, value in pairs(public) do
      if type(value) == "function" then
        local markdown_name = name == "aspect" and "roomplan.aspect" or ("`" .. name .. "(")
        local help_name = "roomplan." .. name
        if not markdown:find(markdown_name, 1, true) then
          missing[#missing + 1] = name .. " (Markdown)"
        end
        if not help:find(help_name, 1, true) then
          missing[#missing + 1] = name .. " (help)"
        end
      end
    end
    table.sort(missing)
    h.eq({}, missing)
  end)

  h.it("keeps special semantic and literal Canvas mappings discoverable", function()
    local keymaps = read(root .. "/docs/configuration/keymaps.md")
    for _, name in ipairs({
      "pan_mode",
      "coarse_right",
      "toggle_minimap",
      "aspect",
      "reload",
      "close",
      "literal `U`",
      "literal `zf`",
    }) do
      h.truthy(keymaps:find(name, 1, true), "missing keymap documentation for " .. name)
    end
  end)
end)
