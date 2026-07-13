local compat = require("roomplan.compat")

local M = {}
local registered = false

local function invoke(method, args)
  return function(command)
    local ok, err = xpcall(function()
      local controller = require("roomplan.controller")
      local fn = assert(controller[method], "missing controller method " .. method)
      return fn(nil, vim.tbl_extend("force", args or {}, {
        args = command.args,
        bang = command.bang,
        fargs = command.fargs,
      }))
    end, debug.traceback)
    if not ok then
      compat.notify(tostring(err), vim.log.levels.ERROR)
    end
  end
end

local definitions = {
  RoomPlan = { method = "menu", desc = "Open RoomPlan menu" },
  RoomPlanMenu = { method = "menu", desc = "Open RoomPlan menu" },
  RoomPlanOpen = { method = "open", nargs = "?", complete = "file", desc = "Open a RoomPlan source" },
  RoomPlanInit = { method = "init_source", nargs = "?", complete = "file", desc = "Initialize a RoomPlan source" },
  RoomPlanHide = { method = "hide", desc = "Hide RoomPlan canvas" },
  RoomPlanClose = { method = "close", bang = true, desc = "Close RoomPlan session" },
  RoomPlanAddRoom = { method = "add_room", desc = "Add a RoomPlan room" },
  RoomPlanAlign = { method = "align_room", desc = "Align RoomPlan rooms" },
  RoomPlanAddDoor = { method = "add_door", desc = "Add a RoomPlan door" },
  RoomPlanAddFurniture = { method = "add_furniture", desc = "Add RoomPlan furniture" },
  RoomPlanEdit = { method = "edit_selected", desc = "Edit RoomPlan selection" },
  RoomPlanDuplicate = { method = "duplicate_selected", desc = "Duplicate RoomPlan selection" },
  RoomPlanDelete = { method = "delete_selected", desc = "Delete RoomPlan selection" },
  RoomPlanObjects = { method = "objects", desc = "List RoomPlan objects" },
  RoomPlanInspect = { method = "inspect", desc = "Toggle RoomPlan details (compatibility alias)" },
  RoomPlanToggleNavigator = { method = "toggle_navigator", desc = "Toggle RoomPlan navigator" },
  RoomPlanToggleDetails = { method = "toggle_details", desc = "Toggle RoomPlan details" },
  RoomPlanValidate = { method = "validate", args = { show_list = true }, desc = "Validate RoomPlan" },
  RoomPlanNextIssue = { method = "next_issue", args = { direction = 1 }, desc = "Next RoomPlan issue" },
  RoomPlanPrevIssue = { method = "next_issue", args = { direction = -1 }, desc = "Previous RoomPlan issue" },
  RoomPlanUndo = { method = "undo", desc = "Undo RoomPlan action" },
  RoomPlanRedo = { method = "redo", desc = "Redo RoomPlan action" },
  RoomPlanFit = { method = "fit", desc = "Fit RoomPlan canvas" },
  RoomPlanAspect = { method = "set_aspect", nargs = "?", desc = "Calibrate RoomPlan terminal cell aspect" },
  RoomPlanRotateView = {
    method = "rotate_view", nargs = "?", desc = "Rotate the RoomPlan view without changing geometry",
  },
  RoomPlanSave = { method = "save", bang = true, desc = "Save RoomPlan" },
  RoomPlanSaveAs = { method = "save_as", nargs = 1, bang = true, complete = "file", desc = "Save RoomPlan As" },
  RoomPlanReload = { method = "reload", bang = true, desc = "Reload RoomPlan" },
  RoomPlanResolveConflict = { method = "resolve_conflict", desc = "Resolve RoomPlan source conflict" },
}

function M.register()
  if registered then
    return
  end
  registered = true
  require("roomplan.highlights").setup()
  local group = vim.api.nvim_create_augroup("RoomPlan", { clear = false })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = require("roomplan.highlights").setup,
    desc = "Relink RoomPlan highlights",
  })
  for name, definition in pairs(definitions) do
    if vim.fn.exists(":" .. name) ~= 2 then
      vim.api.nvim_create_user_command(name, invoke(definition.method, definition.args), {
        nargs = definition.nargs or 0,
        bang = definition.bang or false,
        complete = definition.complete,
        desc = definition.desc,
      })
    end
  end
end

return M
