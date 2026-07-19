local M = {}

function M.dispatch(session_id, action)
  local session = require("roomplan.state").get(session_id)
  if not session then return nil, { code = "SESSION_NOT_FOUND", message = "RoomPlan session does not exist" } end
  return require("roomplan.controller").dispatch(session, action)
end

function M.session(session_id) return require("roomplan.state").get(session_id) end

return M
