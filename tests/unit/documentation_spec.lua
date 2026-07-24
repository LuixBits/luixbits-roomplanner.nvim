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
  if destination:sub(1, 1) == "<" and destination:sub(-1) == ">" then destination = destination:sub(2, -2) end
  destination = destination:match("^[^#?]*") or destination
  if destination == "" or destination:match("^[%a][%w+.-]*:") or destination:sub(1, 2) == "//" then return nil end
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
        if not markdown:find(":" .. name, 1, true) then missing[#missing + 1] = name .. " (Markdown)" end
        if not help:find("*:" .. name .. "*", 1, true) then missing[#missing + 1] = name .. " (help)" end
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
        if not markdown:find(markdown_name, 1, true) then missing[#missing + 1] = name .. " (Markdown)" end
        if not help:find(help_name, 1, true) then missing[#missing + 1] = name .. " (help)" end
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
      "shape_next",
      "shape_previous",
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

  h.it("keeps the recently changed Canvas defaults aligned with both manuals", function()
    local definitions = require("roomplan.ui.action_registry").definitions()
    local markdown = read(root .. "/docs/configuration/keymaps.md")
    local help = read(root .. "/doc/roomplan.txt")
    local expected = {
      { id = "add_door", key = "D", markdown = "`D` / `W` / `O` / `F`", help = "D / W / O / F" },
      { id = "add_window", key = "W", markdown = "`D` / `W` / `O` / `F`", help = "D / W / O / F" },
      { id = "add_outlet", key = "O", markdown = "`D` / `W` / `O` / `F`", help = "D / W / O / F" },
      { id = "add_furniture", key = "F", markdown = "`D` / `W` / `O` / `F`", help = "D / W / O / F" },
      { id = "resize_dimensions", key = "r", markdown = "`r` | Resize", help = "r / R" },
      { id = "rotate", key = "R", markdown = "`R` | Rotate", help = "r / R" },
      { id = "sun_study", key = "S", markdown = "`S` | Open or reopen", help = "S               open or reopen" },
      { id = "toggle_minimap", key = "M", markdown = "`M` | Toggle the minimap", help = "M              toggle whole-plan minimap" },
      { id = "save_as", key = "gS", markdown = "`s` / `gS` | Save / Save As", help = "s / gS         save / save as" },
      { id = "next_issue", key = "<A-j>", markdown = "`Alt-j` / `Alt-k`", help = "v / Alt-j / Alt-k" },
      { id = "previous_issue", key = "<A-k>", markdown = "`Alt-j` / `Alt-k`", help = "v / Alt-j / Alt-k" },
      { id = "zoom_in", key = ".", markdown = "`.` / `,` | Zoom in / out", help = ". / , / f / zf" },
      { id = "zoom_out", key = ",", markdown = "`.` / `,` | Zoom in / out", help = ". / , / f / zf" },
    }
    for _, item in ipairs(expected) do
      h.eq(item.key, definitions[item.id].key)
      h.truthy(markdown:find(item.markdown, 1, true), "Markdown is stale for " .. item.id)
      h.truthy(help:find(item.help, 1, true), "Vim help is stale for " .. item.id)
    end
  end)

  h.it("does not join prose with dash punctuation", function()
    local paths = vim.fn.glob(root .. "/docs/**/*.md", false, true)
    paths[#paths + 1] = root .. "/README.md"
    paths[#paths + 1] = root .. "/plan.md"
    paths[#paths + 1] = root .. "/doc/roomplan.txt"
    local failures = {}
    for _, path in ipairs(paths) do
      local contents = read(path)
      if contents:find("—", 1, true) or contents:find(" – ", 1, true) then
        failures[#failures + 1] = vim.fn.fnamemodify(path, ":.")
      end
    end
    table.sort(failures)
    h.eq({}, failures)
  end)
end)
