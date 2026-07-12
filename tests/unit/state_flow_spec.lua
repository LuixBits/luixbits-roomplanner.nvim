local state = require("roomplan.state")
local flow = require("roomplan.ui.flow")

describe("state and flows", function()
  it("refuses duplicate source ownership", function()
    state.reset()
    local one = { id = state.allocate_id(), source = { path = vim.fn.tempname(), adapter = "json" } }
    assert_true(state.add(one))
    local two = { id = state.allocate_id(), source = { path = one.source.path, adapter = "json" } }
    local added, err = state.add(two)
    assert_equal(added, nil)
    assert_equal(err.code, "SESSION_SOURCE_OWNED")
    state.reset()
  end)

  it("invalidates stale workflows", function()
    local session = { id = "session-test", workflow = { generation = 0 } }
    local first = assert(flow.new(session, "first"))
    assert_true(first:is_current())
    first:cancel()
    assert_true(not first:is_current())
    local second = assert(flow.new(session, "second"))
    assert_true(second:is_current())
    second:finish()
  end)
end)
