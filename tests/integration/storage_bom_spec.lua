local h = require("tests.harness")

local codec = require("roomplan.codec.json")
local controller = require("roomplan.controller")
local model = require("roomplan.model")
local source = require("roomplan.storage.source")
local state = require("roomplan.state")

local BOM = "\239\187\191"
local temporary = {}

local function temp(suffix)
  local path = vim.fn.tempname() .. suffix
  temporary[#temporary + 1] = path
  return path
end

local function write_bytes(path, bytes)
  local fd = assert(vim.uv.fs_open(path, "w", 420))
  assert(vim.uv.fs_write(fd, bytes, 0))
  assert(vim.uv.fs_close(fd))
end

local function cleanup()
  for _, session in ipairs(state.list()) do
    session:destroy({ force = true })
  end
  for _, path in ipairs(temporary) do
    local bufnr = vim.fn.bufnr(path)
    if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then pcall(vim.api.nvim_buf_delete, bufnr, { force = true }) end
    pcall(vim.uv.fs_unlink, path)
  end
  temporary = {}
end

local function crlf(text) return text:gsub("\n", "\r\n") end

local function assert_bom_crlf(bytes)
  h.eq(BOM, bytes:sub(1, #BOM))
  local body = bytes:sub(#BOM + 1)
  h.truthy(body:find("\r\n", 1, true), "fixture must retain CRLF line endings")
  h.falsy(body:gsub("\r\n", ""):find("[\r\n]"), "saved file contains mixed line endings")
end

describe("storage BOM compatibility", function()
  it("saves and reopens a pre-existing BOM standalone plan without semantic divergence", function()
    cleanup()
    local path = temp(".roomplan.json")
    local initial = h.truthy(model.new({ name = "BOM standalone" }))
    write_bytes(path, BOM .. crlf(h.truthy(model.encode(initial))))

    local session, open_err = controller.open(nil, { path = path, noninteractive = true })
    h.truthy(session, vim.inspect(open_err))
    h.truthy(vim.bo[session.source.bufnr].bomb)
    h.eq("dos", vim.bo[session.source.bufnr].fileformat)
    h.truthy(session.durable_source_matches_savepoint)
    h.falsy(session:requires_protection())

    h.truthy(controller.dispatch(session, {
      type = "edit_metadata",
      patch = { name = "BOM standalone saved" },
    }))
    local saved, save_err = controller.save(session, { quiet = true, noninteractive = true })
    h.truthy(saved, vim.inspect(save_err))
    h.falsy(session:requires_protection())
    local bytes = h.truthy(source.read_file(path))
    assert_bom_crlf(bytes)
    h.eq("BOM standalone saved", h.truthy(model.decode(source.logical_text(bytes))).metadata.name)

    local old_bufnr = session.source.bufnr
    h.truthy(controller.close(session, { bang = true, noninteractive = true }))
    pcall(vim.api.nvim_buf_delete, old_bufnr, { force = true })
    local reopened, reopen_err = controller.open(nil, { path = path, noninteractive = true })
    h.truthy(reopened, vim.inspect(reopen_err))
    h.eq("BOM standalone saved", reopened:model().metadata.name)
    h.truthy(reopened.durable_source_matches_savepoint)
    h.falsy(reopened:requires_protection())
    cleanup()
  end)

  it("saves and reopens a BOM Norg plan whose block starts on the first line", function()
    cleanup()
    local path = temp(".norg")
    local initial = h.truthy(model.new({ name = "BOM Norg" }))
    local payload = h.truthy(require("roomplan.storage.norg").serialize(initial))
    local note = table.concat({
      "@code json roomplan.nvim",
      payload,
      "@end",
      "Outside text remains.",
      "",
    }, "\n")
    write_bytes(path, BOM .. crlf(note))

    local session, open_err = controller.open(nil, { path = path, noninteractive = true })
    h.truthy(session, vim.inspect(open_err))
    h.truthy(session.durable_source_matches_savepoint)
    h.falsy(session:requires_protection())
    h.truthy(controller.dispatch(session, {
      type = "edit_metadata",
      patch = { name = "BOM Norg saved" },
    }))
    local saved, save_err = controller.save(session, { quiet = true, noninteractive = true })
    h.truthy(saved, vim.inspect(save_err))
    local bytes = h.truthy(source.read_file(path))
    assert_bom_crlf(bytes)
    h.truthy(source.logical_text(bytes):find("Outside text remains.", 1, true))

    local old_bufnr = session.source.bufnr
    h.truthy(controller.close(session, { bang = true, noninteractive = true }))
    pcall(vim.api.nvim_buf_delete, old_bufnr, { force = true })
    local reopened, reopen_err = controller.open(nil, { path = path, noninteractive = true })
    h.truthy(reopened, vim.inspect(reopen_err))
    h.eq("BOM Norg saved", reopened:model().metadata.name)
    h.truthy(reopened.durable_source_matches_savepoint)
    h.falsy(reopened:requires_protection())
    cleanup()
  end)

  it("keeps BOM rejection strict inside JSON payloads", function()
    local decoded, err = codec.decode(BOM .. [[{"format":"roomplan.nvim"}]])
    h.falsy(decoded)
    h.eq("JSON_BOM", h.truthy(err).code)

    local path = temp(".roomplan.json")
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, path)
    vim.bo[bufnr].bomb = false
    source.set_buffer_text(bufnr, BOM .. h.truthy(model.encode(h.truthy(model.new()))))
    local loaded, load_err = require("roomplan.storage.json").load(source.context({ bufnr = bufnr }))
    h.falsy(loaded)
    h.eq("JSON_BOM", h.truthy(load_err).code)
    cleanup()
  end)
end)
