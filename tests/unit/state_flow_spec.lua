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

  it("passes semantic hints to asynchronous vim.ui providers", function()
    local original_input, original_select = vim.ui.input, vim.ui.select
    local input_options, input_done, select_options, select_done
    vim.ui.input = function(opts, done)
      input_options, input_done = opts, done
    end
    vim.ui.select = function(_, opts, done)
      select_options, select_done = opts, done
    end

    local ok, err = xpcall(function()
      local session = { id = "provider-test", workflow = { generation = 0 }, closed = false }
      local caller_options = { prompt = "Value: " }
      local input_value
      local input_flow = assert(flow.new(session, "input"))
      input_flow:input(caller_options, function(value, current)
        input_value = value
        current:finish()
      end)
      assert_equal(input_options.scope, "window")
      assert_equal(caller_options.scope, nil)
      input_done("42")
      assert_equal(input_value, "42")
      assert_true(not input_flow:is_current())

      local selection, selection_index
      local select_flow = assert(flow.new(session, "selection"))
      select_flow:select({ "one", "two" }, { prompt = "Choice" }, function(choice, index, current)
        selection, selection_index = choice, index
        current:finish()
      end)
      assert_equal(select_options.kind, "roomplan_selection")
      select_done("two", 2)
      assert_equal(selection, "two")
      assert_equal(selection_index, 2)

      local confirmed
      assert(require("roomplan.ui.prompts").confirm(
        session,
        "confirm",
        "Continue?",
        { "Continue", "Cancel" },
        function(choice) confirmed = choice end
      ))
      assert_equal(select_options.kind, "roomplan_confirmation")
      select_done("Continue", 1)
      assert_equal(confirmed, "Continue")

      local cancelled
      local cancel_flow = assert(flow.new(session, "cancel", {
        on_cancel = function(reason) cancelled = reason end,
      }))
      cancel_flow:input({}, function() error("cancelled input must not produce a value") end)
      input_done(nil)
      assert_equal(cancelled, "cancelled")
      assert_true(not cancel_flow:is_current())
    end, debug.traceback)

    vim.ui.input, vim.ui.select = original_input, original_select
    if not ok then error(err, 0) end
  end)
end)
