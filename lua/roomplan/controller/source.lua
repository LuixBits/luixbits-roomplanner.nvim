-- Session lifecycle: open, initialize, track, reload, and close sources.
local config = require("roomplan.config")
local model = require("roomplan.model")
local source_io = require("roomplan.storage.source")
local storage = require("roomplan.storage")
local util = require("roomplan.util")

local common = require("roomplan.controller.common")
local source_context = require("roomplan.controller.source_context")

local M = {}

function M.attach(controller)
  local finish = common.finish
  local interactive_call = common.interactive_call
  local is_session = common.is_session
  local notify_error = common.notify_error
  local resolve = common.resolve
  local open_canvas = function(session) return common.open_canvas(controller, session) end

  local context_for = source_context.context_for
  local find_existing = source_context.find_existing
  local reusable_existing = source_context.reusable_existing
  local session_source = source_context.session_source
  local reattach_existing = function(context, existing)
    return source_context.reattach_existing(controller, context, existing)
  end

  local function load_is_durable(revision, info)
    return revision.durable_model_matches == true
      and not (info and (info.normalized or info.migrated))
  end

  local function attach_loaded(context, adapter, loaded_model, revision, locator, info)
    local durable = load_is_durable(revision, info)
    local session, err = require("roomplan.session").new(
      session_source(context, adapter, revision, locator),
      loaded_model,
      { durable = durable }
    )
    if not session then return nil, err end
    session.normalization_info = info
    controller.validate(session)
    return session
  end

  function controller.open(_, opts, callback)
    opts = opts or {}
    local interactive = opts.interactive == true or opts.fargs ~= nil
    local context = context_for(opts, "open")
    local adapter, detect_err = storage.detect(context)
    if not adapter then return finish(callback, notify_error(detect_err)) end
    context.adapter = adapter.name
    local existing = find_existing(context)
    if existing then
      local reusable, alias_err = reusable_existing(context, existing)
      if not reusable then return finish(callback, notify_error(alias_err)) end
      local reattached, reattach_err = reattach_existing(context, existing)
      if not reattached then return finish(callback, notify_error(reattach_err)) end
      local opened, err = open_canvas(existing)
      if not opened then notify_error(err) end
      return finish(callback, opened, err)
    end
    local loaded_model, revision, locator, info = adapter.load(context)
    if not loaded_model then
      if revision and revision.code == "NORG_PLAN_MISSING" and interactive and not opts.noninteractive then
        vim.ui.select({ "Initialize RoomPlan block", "Cancel" }, {
          prompt = "No RoomPlan block exists in this Norg note.",
          kind = "roomplan_confirmation",
        }, function(choice)
          if choice == "Initialize RoomPlan block" then
            controller.init_source(nil, {
              bufnr = context.bufnr,
              path = context.path,
              filetype = context.filetype,
              interactive = true,
            }, callback)
          else finish(callback, nil, util.err("OPEN_CANCELLED", "RoomPlan open cancelled")) end
        end)
        return nil
      end
      return finish(callback, notify_error(revision))
    end
    local session, err = attach_loaded(context, adapter, loaded_model, revision, locator, info)
    if not session then return finish(callback, notify_error(err)) end
    local opened, canvas_err = open_canvas(session)
    if not opened then
      session:destroy({ force = true })
      return finish(callback, notify_error(canvas_err))
    end
    return finish(callback, session)
  end

  local function empty_plan(opts)
    local defaults = config.get().plan_defaults
    return model.new({
      name = opts.name or defaults.metadata.name,
      notes = defaults.metadata.notes,
      settings = defaults.settings,
    })
  end

  function controller.init_source(_, opts, callback)
    opts = opts or {}
    local interactive = opts.interactive == true or opts.fargs ~= nil
    local context = context_for(opts, "init")
    local adapter, detect_err = storage.detect(context)
    if not adapter then return finish(callback, notify_error(detect_err)) end
    context.adapter = adapter.name
    local existing = find_existing(context)
    if existing then
      local reusable, alias_err = reusable_existing(context, existing)
      if not reusable then return finish(callback, notify_error(alias_err)) end
      local reattached, reattach_err = reattach_existing(context, existing)
      if not reattached then return finish(callback, notify_error(reattach_err)) end
      local opened, err = open_canvas(existing)
      return finish(callback, opened, err)
    end
    local fresh, fresh_err = empty_plan(opts)
    if not fresh then return finish(callback, notify_error(fresh_err)) end

    if adapter.name == "json" then
      local text
      if context.bufnr and vim.api.nvim_buf_is_loaded(context.bufnr) then
        text = source_io.buffer_text(context.bufnr)
      elseif context.path and vim.uv.fs_lstat(context.path) then
        text, fresh_err = source_io.read_file(context.path)
        if not text then return finish(callback, notify_error(fresh_err)) end
      end
      if text and not text:match("^%s*$") then
        return finish(callback, notify_error(util.err("SOURCE_NOT_EMPTY", "RoomPlanInit refuses to overwrite a non-empty source")))
      end
      local revision, init_err, staged = adapter.initialize(context, fresh)
      if not revision then
        if staged and staged.staged and context.bufnr then
          local staged_model, staged_revision, staged_locator, staged_info = adapter.load(context)
          if staged_model then
            local recovery, recovery_err = attach_loaded(
              context, adapter, staged_model, staged_revision, staged_locator, staged_info
            )
            if recovery then
              recovery.history:clear_savepoint()
              recovery.pending_disk_write = true
              recovery.buffer_payload_revision_id = recovery:revision_id()
              recovery:update_guard()
              open_canvas(recovery)
              if not opts.noninteractive then notify_error(init_err) end
              return finish(callback, recovery, init_err)
            end
            init_err = recovery_err or init_err
          end
        end
        if context.bufnr and source_io.buffer_text(context.bufnr) ~= (text or "") then
          local damaged_text = source_io.buffer_text(context.bufnr)
          local damaged_revision = source_io.with_disk(source_io.revision(damaged_text, context), context)
          if damaged_revision then
            local recovery, recovery_err = require("roomplan.session").new(
              session_source(context, adapter, damaged_revision, { kind = "document" }),
              fresh,
              { durable = false, pending_disk_write = vim.bo[context.bufnr].modified }
            )
            if recovery then
              recovery.source_conflicted = true
              recovery.retained_model_at_risk = true
              recovery:update_guard()
              open_canvas(recovery)
              if not opts.noninteractive then notify_error(init_err) end
              return finish(callback, recovery, init_err)
            end
            init_err = recovery_err or init_err
          end
        end
        return finish(callback, notify_error(init_err))
      end
      if not context.bufnr then
        context.bufnr = storage.ensure_buffer(context.path)
        context.filetype = vim.bo[context.bufnr].filetype
        local reloaded, reload_revision, locator, info = adapter.load(context)
        if not reloaded then return finish(callback, notify_error(reload_revision)) end
        fresh, revision = reloaded, reload_revision
        local session, attach_err = attach_loaded(context, adapter, fresh, revision, locator, info)
        if not session then return finish(callback, notify_error(attach_err)) end
        local opened, canvas_err = open_canvas(session)
        return finish(callback, opened, canvas_err)
      end
      local loaded, loaded_revision, locator, info = adapter.load(context)
      if not loaded then return finish(callback, notify_error(loaded_revision)) end
      local session, attach_err = attach_loaded(context, adapter, loaded, loaded_revision, locator, info)
      if not session then return finish(callback, notify_error(attach_err)) end
      return finish(callback, open_canvas(session))
    end

    if not opts.heading_line then
      local headings, heading_err = adapter.headings(context)
      if not headings then return finish(callback, notify_error(heading_err)) end
      if #headings == 1 then
        opts = vim.tbl_extend("force", opts, { heading_line = headings[1] })
      elseif #headings > 1 then
        if not interactive or opts.noninteractive then
          return finish(callback, nil, util.err("NORG_MULTIPLE_HEADINGS", "multiple '* Floor plan' headings require an explicit heading_line", {
            headings = headings,
          }))
        end
        vim.ui.select(headings, {
          prompt = "Insert RoomPlan under which Floor plan heading?",
          kind = "roomplan_norg_heading",
          format_item = function(line) return "Floor plan heading at line " .. line end,
        }, function(line)
          if line then
            controller.init_source(nil, vim.tbl_extend("force", opts, {
              bufnr = context.bufnr, path = context.path, filetype = context.filetype,
              heading_line = line,
            }), callback)
          else
            finish(callback, nil, util.err("INIT_CANCELLED", "RoomPlan initialization cancelled"))
          end
        end)
        return nil
      end
    else
      local headings, heading_err = adapter.headings(context)
      if not headings then return finish(callback, notify_error(heading_err)) end
      local still_present = false
      for _, line in ipairs(headings) do
        if line == opts.heading_line then still_present = true; break end
      end
      if not still_present then
        return finish(callback, nil, util.err("NORG_HEADING_CHANGED", "selected Floor plan heading changed before initialization"))
      end
    end
    local revision, locator_or_err = adapter.initialize(context, fresh, opts)
    if not revision then
      if locator_or_err and locator_or_err.code == "NORG_MALFORMED_JSON_AMBIGUOUS"
        and interactive and not opts.noninteractive and not opts.allow_other_malformed_json then
        vim.ui.select({ "Initialize beside unrelated malformed JSON", "Cancel" }, {
          prompt = "This Norg note has malformed JSON blocks. Initialize RoomPlan anyway?",
          kind = "roomplan_confirmation",
        }, function(choice)
          if choice and choice:match("^Initialize") then
            controller.init_source(nil, vim.tbl_extend("force", opts, {
              bufnr = context.bufnr,
              path = context.path,
              filetype = context.filetype,
              allow_other_malformed_json = true,
            }), callback)
          else
            finish(callback, nil, util.err("INIT_CANCELLED", "RoomPlan initialization cancelled"))
          end
        end)
        return nil
      end
      return finish(callback, notify_error(locator_or_err))
    end
    local session, attach_err = require("roomplan.session").new(
      session_source(context, adapter, revision, locator_or_err), fresh, { durable = false }
    )
    if not session then return finish(callback, notify_error(attach_err)) end
    controller.validate(session)
    return finish(callback, open_canvas(session))
  end

  function controller.check_source(session)
    if not is_session(session) or session.closed then return end
    session.source_needs_recheck = false
    local adapter = storage.adapter(session.source.adapter)
    local loaded, revision, locator, info = adapter.load(session.source)
    if not loaded then
      session.durable_source_matches_savepoint = false
      session.source_conflicted = true
      session.retained_model_at_risk = true
      session.source_error = revision
      session:update_guard()
      controller.refresh(session)
      return nil, revision
    end
    local expected = session.source.revision
    local disk_unchanged = not expected or not expected.disk or not revision.disk
      or (expected.disk.exists == revision.disk.exists and expected.disk.type == revision.disk.type
        and expected.disk.text == revision.disk.text)
    if expected and revision.hash == expected.hash and disk_unchanged then
      session.source.revision = revision
      session.source.locator = locator
      session.source_conflicted = false
      session.durable_source_matches_savepoint = load_is_durable(revision, info)
      session.normalization_info = info
      session.source_error = nil
      session.retained_model_at_risk = false
      session:update_guard()
      return true
    end
    if disk_unchanged and model.deep_equal(loaded, session:model()) and not session:model_dirty() then
      session.source.revision = revision
      session.source.locator = locator
      session.source_conflicted = false
      session.durable_source_matches_savepoint = load_is_durable(revision, info)
      session.normalization_info = info
      session.retained_model_at_risk = false
      session:update_guard()
      return true
    end
    session.source_conflicted = true
    session.durable_source_matches_savepoint = false
    session.retained_model_at_risk = not model.deep_equal(loaded, session:model())
      or not load_is_durable(revision, info)
    session.source_external_model = loaded
    session.source_external_revision = revision
    session:update_guard()
    controller.refresh(session)
    return nil, util.err("SOURCE_CONFLICT", "RoomPlan source payload changed after the session opened")
  end

  function controller.source_written(session)
    if not is_session(session) or session.closed then return end
    local adapter = storage.adapter(session.source.adapter)
    local loaded, revision, locator, info = adapter.load(session.source)
    if not loaded then
      session.source_conflicted = true
      session.durable_source_matches_savepoint = false
      session.retained_model_at_risk = true
      session.source_error = revision
      session:update_guard()
      return nil, revision
    end
    local staged_id = session.buffer_payload_revision_id
    local staged_model = staged_id and session.history:model_at_revision(staged_id) or nil
    local expected = session.source.revision
    if not staged_id and expected and expected.hash == revision.hash
      and load_is_durable(revision, info) and not session:source_buffer_modified() then
      session.source.revision = revision
      session.source.locator = locator
      session.source_conflicted = false
      session.durable_source_matches_savepoint = true
      session.normalization_info = info
      session.retained_model_at_risk = false
      session.source_error = nil
      session:update_guard()
      controller.refresh(session)
      return true
    end
    if staged_model and model.deep_equal(loaded, staged_model)
      and load_is_durable(revision, info) and not session:source_buffer_modified() then
      local marked = session.history:mark_saved_revision(staged_id)
      session.source.revision = revision
      session.source.locator = locator
      session.pending_disk_write = false
      session.source_conflicted = false
      session.durable_source_matches_savepoint = true
      session.normalization_info = info
      session.retained_model_at_risk = false
      session.source_error = nil
      if staged_id == session:revision_id() then session.buffer_payload_revision_id = nil end
      if not marked then session.history:clear_savepoint() end
      session:update_guard()
      controller.refresh(session)
      return true
    end
    return controller.check_source(session)
  end

  function controller.reload(session, opts, callback)
    opts = opts or {}
    if opts.noninteractive == nil then opts.noninteractive = not interactive_call(session, opts) end
    local resolved, err = resolve(session, opts)
    if not resolved then return finish(callback, notify_error(err)) end
    if resolved.source_rebind_pending then
      err = util.err("SOURCE_REBIND_PENDING", "source buffer was renamed; resolve it with Save As before reloading")
      return finish(callback, nil, err)
    end
    if resolved:requires_protection() and not opts.bang and not opts.confirmed then
      if opts.noninteractive then
        err = util.err("RELOAD_CONFIRM_REQUIRED", "reload would discard protected RoomPlan state; pass bang=true deliberately")
        return finish(callback, nil, err)
      end
      local flow, flow_err = require("roomplan.ui.prompts").confirm(resolved, "reload", "Discard protected RoomPlan session state and reload?", {
        "Reload and discard", "Save first", "Cancel",
      }, function(choice)
        if choice == "Reload and discard" then
          controller.reload(resolved, vim.tbl_extend("force", opts, { confirmed = true }), callback)
        elseif choice == "Save first" then
          controller.save(resolved, {}, function(saved, save_err)
            if saved then controller.reload(resolved, { confirmed = true }, callback) else finish(callback, nil, save_err) end
          end)
        else
          finish(callback, nil, util.err("RELOAD_CANCELLED", "reload cancelled"))
        end
      end)
      if not flow then return finish(callback, nil, flow_err) end
      return nil
    end
    local disk_ok, disk_err = source_io.verify_expected_disk(resolved.source, resolved.source.revision)
    local function retain_model_at_risk(failure)
      -- Reload is allowed to replace the source buffer before the adapter has
      -- proved that the replacement is a valid RoomPlan document.  If that
      -- proof fails, keep the in-memory model and make the hidden acwrite guard
      -- durable immediately; otherwise :qall could discard the only valid copy.
      resolved.durable_source_matches_savepoint = false
      resolved.source_conflicted = true
      resolved.retained_model_at_risk = true
      resolved.source_error = failure
      resolved:update_guard()
      controller.refresh(resolved)
    end
    if not disk_ok and resolved.source.path then
      local bufnr = resolved.source.bufnr
      if bufnr and vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].modified then
        err = util.err("SOURCE_BUFFER_DISK_CONFLICT", "source buffer and disk both changed; review or Save As before reload", {
          cause = disk_err,
        })
        retain_model_at_risk(err)
        return finish(callback, nil, err)
      end
      if bufnr and vim.api.nvim_buf_is_loaded(bufnr) then
        resolved.internal_source_write = true
        local reloaded_ok, reload_buffer_err = pcall(vim.api.nvim_buf_call, bufnr, function()
          vim.cmd("edit!")
        end)
        resolved.internal_source_write = false
        if not reloaded_ok then
          err = util.err("SOURCE_DISK_RELOAD_FAILED", tostring(reload_buffer_err), { cause = disk_err })
          retain_model_at_risk(err)
          return finish(callback, nil, err)
        end
      end
    end
    local adapter = storage.adapter(resolved.source.adapter)
    local loaded, revision, locator, info = adapter.load(resolved.source)
    if not loaded then
      retain_model_at_risk(revision)
      if not opts.noninteractive then notify_error(revision) end
      return finish(callback, nil, revision)
    end
    local durable = load_is_durable(revision, info)
    resolved:reset(loaded, revision, locator, { durable = durable })
    resolved.normalization_info = info
    controller.validate(resolved)
    controller.refresh(resolved)
    return finish(callback, resolved)
  end

  function controller.close(session, opts, callback)
    opts = opts or {}
    if opts.noninteractive == nil then opts.noninteractive = not interactive_call(session, opts) end
    local resolved, err = resolve(session, opts)
    if not resolved then return finish(callback, notify_error(err)) end
    if resolved:requires_protection() and not opts.bang and not opts.confirmed then
      if opts.noninteractive then
        err = util.err("CLOSE_CONFIRM_REQUIRED", "close would discard protected RoomPlan state; save or pass bang=true deliberately")
        return finish(callback, nil, err)
      end
      local choices = { "Save", "Discard session", "Cancel" }
      local flow, flow_err = require("roomplan.ui.prompts").confirm(resolved, "close", "Close " .. resolved:status_text() .. "?", choices, function(choice)
        if choice == "Save" then
          controller.save(resolved, {}, function(saved, save_err)
            if saved then controller.close(resolved, { confirmed = true }, callback) else finish(callback, nil, save_err) end
          end)
        elseif choice == "Discard session" then
          controller.close(resolved, { bang = true }, callback)
        else
          finish(callback, nil, util.err("CLOSE_CANCELLED", "close cancelled"))
        end
      end)
      if not flow then return finish(callback, nil, flow_err) end
      return nil
    end
    local closed, close_err = resolved:destroy({ force = opts.bang or opts.confirmed })
    return finish(callback, closed, close_err)
  end

end

return M
