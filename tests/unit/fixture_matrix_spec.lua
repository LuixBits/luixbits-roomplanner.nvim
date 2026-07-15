local json = require("roomplan.codec.json")
local model = require("roomplan.model")
local norg_scan = require("roomplan.storage.norg_scan")
local validate = require("roomplan.validate")

local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h:h")

local function fixture(name)
  return table.concat(vim.fn.readfile(root .. "/tests/fixtures/" .. name, "b"), "\n")
end

local function diagnostic_codes(diagnostics)
  local result = {}
  for _, diagnostic in ipairs(diagnostics) do
    result[diagnostic.code] = true
  end
  return result
end

describe("release fixture matrix", function()
  it("loads the valid standalone fixtures", function()
    local cases = {
      { name = "empty.roomplan.json", migrated = true },
      { name = "acceptance.roomplan.json", migrated = true },
      { name = "compound-v2.roomplan.json", migrated = true },
      { name = "windows-outlets-v3.roomplan.json", migrated = false },
    }
    for _, case in ipairs(cases) do
      local plan, info = model.decode(fixture(case.name))
      assert_true(plan ~= nil, case.name .. ": " .. vim.inspect(info))
      assert_equal(3, plan.schema_version)
      assert_equal(case.migrated, info.migrated)
      local _, summary = validate.run(plan)
      assert_true(summary.valid, case.name)
    end
  end)

  it("keeps repair drafts structurally loadable while reporting layout errors", function()
    local plan, info = model.decode(fixture("invalid-layout.roomplan.json"))
    assert_true(plan ~= nil, vim.inspect(info))
    assert_equal(3, plan.schema_version)
    assert_true(info.migrated)
    local diagnostics, summary = validate.run(plan)
    local codes = diagnostic_codes(diagnostics)
    assert_true(codes.ROOM_OVERLAP)
    assert_true(codes.FURNITURE_OUTSIDE_ROOM)
    assert_equal(0, summary.structural_errors)
    assert_equal(false, summary.valid)
  end)

  it("rejects malformed and future documents with stable error codes", function()
    local plan, err = model.decode(fixture("malformed.roomplan.json"))
    assert_equal(nil, plan)
    assert_equal("JSON_TRAILING_COMMA", err.code)

    plan, err = model.decode(fixture("future-version.roomplan.json"))
    assert_equal(nil, plan)
    assert_equal("SCHEMA_FUTURE_VERSION", err.code)
  end)

  it("round-trips unknown fields and every tagged extension type", function()
    local plan, info = model.decode(fixture("extension-fields.roomplan.json"))
    assert_true(plan ~= nil, vim.inspect(info))
    assert_equal(3, plan.schema_version)
    assert_true(info.migrated)
    local extension = plan.extensions["example.nvim"]
    assert_true(json.is_object(extension.empty_object))
    assert_true(json.is_array(extension.empty_array))
    assert_true(json.is_null(extension.nothing))
    assert_true(json.is_decimal(extension.exact_decimal))
    assert_true(json.is_decimal(plan["vendor-root"].nested[2].value))

    local reloaded = assert(model.decode(assert(model.encode(plan))))
    assert_true(json.deep_equal(plan, reloaded))
  end)

  it("discovers legacy unmarked Norg plans", function()
    local found, err = norg_scan.discover(fixture("legacy-plan.norg"), function(payload)
      local plan, decode_err = model.decode(payload)
      if not plan then error(decode_err.code) end
      return plan
    end)
    assert_true(found ~= nil, vim.inspect(err))
    assert_equal("found", found.kind)
    assert_equal(false, found.block.marked)
    assert_equal(3, found.block.document.schema_version)
  end)
end)
