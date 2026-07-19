-- Stable public facade for the RoomPlan workspace. Implementation details are
-- split by responsibility under roomplan.ui.workspace.*.

local interaction = require("roomplan.ui.workspace.interaction")
local lifecycle = require("roomplan.ui.workspace.lifecycle")
local layout = require("roomplan.ui.workspace.layout")
local render = require("roomplan.ui.workspace.render")

local M = {}

function M.action_context(session) return render.action_context(session) end

function M.refresh(session, roles) return render.refresh(session, roles) end

function M.reflow(session, force) return layout.reflow(M, session, force) end

function M.focus(session, pane) return layout.focus(M, session, pane) end

function M.toggle(session, pane) return layout.toggle(M, session, pane) end

function M.cycle_focus(session, direction) return layout.cycle_focus(M, session, direction) end

function M.select_focused(session) return interaction.select_focused(M, session) end

function M.toggle_mark_focused(session) return interaction.toggle_mark_focused(M, session) end

function M.set_filter(session, pane, value) return interaction.set_filter(M, session, pane, value) end

function M.set_interaction(session, mode, form) return interaction.set_interaction(M, session, mode, form) end

function M.update_cursor(session, world, zoom) return interaction.update_cursor(M, session, world, zoom) end

function M.filter_prompt(session, pane) return interaction.filter_prompt(M, session, pane) end

function M.expand_focused(session, value) return interaction.expand_focused(M, session, value) end

function M.collapse_focused(session) return interaction.collapse_focused(M, session) end

function M.filter_focused(session) return interaction.filter_focused(M, session) end

function M.set_details_section(session, expanded) return interaction.set_details_section(M, session, expanded) end

function M.toggle_details_section(session) return interaction.toggle_details_section(M, session) end

function M.invoke(session, id) return interaction.invoke(M, session, id) end

function M.invoke_key(session, key) return interaction.invoke_key(M, session, key) end

function M.escape(session) return interaction.escape(M, session) end

function M.apply_canvas_keymaps(session, opts) return interaction.apply_canvas_keymaps(M, session, opts) end

function M.mount(session, opts) return lifecycle.mount(M, session, opts) end

M.attach = M.mount

function M.hide(session) return lifecycle.hide(M, session) end

function M.close(session, opts) return lifecycle.close(M, session, opts) end

function M.is_visible(session) return lifecycle.is_visible(M, session) end

function M.owns_window(session, winid) return lifecycle.owns_window(M, session, winid) end

function M.layout(session) return lifecycle.current_layout(M, session) end

return M
