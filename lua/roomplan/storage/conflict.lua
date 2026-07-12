local M = {}

function M.is(error)
  return type(error) == "table" and error.code == "SOURCE_CONFLICT"
end

function M.actions(error)
  local actions = { "Review source", "Reload", "Save As", "Cancel" }
  if error and error.overwrite_allowed then
    table.insert(actions, 4, "Overwrite current payload")
  end
  return actions
end

return M
