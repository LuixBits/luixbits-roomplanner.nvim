local h = require("tests.harness")

h.describe("controller facade", function()
  h.it("dispatches fallback menu callbacks through the injected controller", function()
    local session = {
      id = "session-controller-facade-test",
      history = {},
      source = {},
      status_text = function() return "test session" end,
    }
    local menu = h.truthy(require("roomplan.controller").menu(session))
    local hide
    for _, item in ipairs(menu.items) do
      if item.label == "Hide canvas" then hide = item; break end
    end
    h.truthy(hide)
    local ok, err = pcall(hide.callback)
    h.truthy(ok, tostring(err))
    require("roomplan.ui.palette").close(menu, "test complete")
  end)
end)
