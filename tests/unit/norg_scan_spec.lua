local scan = require("roomplan.storage.norg_scan")

local function decode(text) return vim.json.decode(text) end

describe("norg scanner", function()
  it("discovers CRLF encoded Norg blocks", function()
    local codec = require("roomplan.codec.json")
    local text = table.concat({
      "* Plan",
      "",
      "@code json roomplan.nvim",
      '{"format":"roomplan.nvim","schema_version":1,"units":"mm"}',
      "@end",
      "",
    }, "\r\n")
    local found, err = scan.discover(text, function(payload)
      local value, decode_err = codec.decode(payload)
      if not value then error(decode_err.message) end
      return value
    end)
    assert_true(found, vim.inspect(err))
    assert_equal(found.kind, "found")
  end)

  it("rejects mixed line endings conservatively", function()
    local text = "* Plan\r\n@code json roomplan.nvim\n{}\r\n@end\r\n"
    local found, err = scan.discover(text, decode)
    assert_equal(found, nil)
    assert_equal(err.code, "NORG_MIXED_LINE_ENDINGS")
  end)

  it("finds a marked plan", function()
    local source = table.concat({
      "* Floor plan",
      "",
      "@code json roomplan.nvim",
      [[{"format":"roomplan.nvim","schema_version":1}]],
      "@end",
      "",
      "outside",
    }, "\n")
    local result = assert(scan.discover(source, decode))
    assert_equal(result.kind, "found")
    assert_true(result.block.marked)
    local replaced = assert(scan.replace(source, result.block, [[{"format":"roomplan.nvim","schema_version":1,"x":1}]]))
    assert_true(replaced:find("outside", 1, true) ~= nil)
    assert_true(replaced:find('"x":1', 1, true) ~= nil)
  end)

  it("rejects mixed marked and legacy plans", function()
    local source = table.concat({
      "@code json roomplan.nvim",
      [[{"format":"roomplan.nvim"}]],
      "@end",
      "@code json",
      [[{"format":"roomplan.nvim"}]],
      "@end",
    }, "\n")
    local result, err = scan.discover(source, decode)
    assert_equal(result, nil)
    assert_equal(err.code, "NORG_MULTIPLE_PLANS")
  end)

  it("initializes a missing plan", function()
    local initialized = scan.initialize("* Notes\ntext\n", [[{"format":"roomplan.nvim"}]], nil)
    assert_true(initialized:find("@code json roomplan.nvim", 1, true) ~= nil)
    assert_true(initialized:find("* Notes\ntext", 1, true) ~= nil)
  end)
end)
