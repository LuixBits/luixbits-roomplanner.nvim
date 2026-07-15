-- Validation and durable writes, including Save As and conflict recovery.
local catalog = require("roomplan.catalog")
local compat = require("roomplan.compat")
local config = require("roomplan.config")
local model = require("roomplan.model")
local state = require("roomplan.state")
local storage = require("roomplan.storage")
local source_io = require("roomplan.storage.source")
local util = require("roomplan.util")
local validator = require("roomplan.validate")

local common = require("roomplan.controller.common")
local source_context = require("roomplan.controller.source_context")

local M = {}

function M.attach(controller)
  local finish = common.finish
  local interactive_call = common.interactive_call
  local notify_error = common.notify_error
  local resolve = common.resolve
  local open_canvas = function(session) return common.open_canvas(controller, session) end

  local explicit_path = source_context.explicit_path
  local explicit_requested_path = source_context.explicit_requested_path
  local find_existing = source_context.find_existing
  local session_source = source_context.session_source

  function controller.validate(session, show_list)
    local resolved, err = resolve(session, type(show_list) == "table" and show_list or nil)
    if not resolved then return notify_error(err) end
    local revision = resolved:revision_id()
    if resolved.validation_revision_id ~= revision then
      local diagnostics, summary = validator.run(resolved:model(), {
        limits = config.get().limits,
        catalog = catalog,
      })
      resolved.validation = diagnostics
      resolved.validation_summary = summary
      resolved.validation_revision_id = revision
    end
    if show_list == true or (type(show_list) == "table" and show_list.show_list) then
      local workspace = require("roomplan.ui.workspace")
      if not workspace.is_visible(resolved) then
        local opened, open_err = open_canvas(resolved)
        if not opened then return notify_error(open_err) end
      end
      workspace.focus(resolved, "issues")
    end
    local workspace_ok, workspace = pcall(require, "roomplan.ui.workspace")
    if workspace_ok and resolved.workspace then workspace.refresh(resolved, { "issues", "properties", "action_bar" }) end
    return resolved.validation, resolved.validation_summary
  end

  local function save_allowed(session, opts, callback, retry_fn)
    local diagnostics, summary = controller.validate(session)
    if summary.structural_errors > 0 then
      return nil, util.err("MODEL_STRUCTURAL_INVALID", "structural model errors must be repaired before saving", {
        diagnostics = diagnostics,
      })
    end
    if summary.errors > 0 and not opts.allow_invalid then
      if opts.noninteractive then
        return nil, util.err("MODEL_LAYOUT_INVALID", "layout errors block noninteractive save; use :RoomPlanSave! deliberately", {
          diagnostics = diagnostics,
        })
      end
      local prompt_err
      local flow
      flow, prompt_err = require("roomplan.ui.prompts").confirm(
        session,
        "save-invalid",
        string.format("Plan has %d error(s). Save an invalid draft?", summary.errors),
        { "Review errors", "Save invalid draft", "Cancel" },
        function(choice)
          if choice == "Review errors" then
            local workspace = require("roomplan.ui.workspace")
            if not workspace.is_visible(session) then
              local opened, open_err = open_canvas(session)
              if not opened then
                finish(callback, nil, open_err)
                return
              end
            end
            workspace.focus(session, "issues")
            finish(callback, nil, util.err("SAVE_CANCELLED", "save cancelled to review validation errors"))
          elseif choice == "Save invalid draft" then
            local retry = vim.tbl_extend("force", opts, { allow_invalid = true })
            local retry_save = retry_fn or controller.save
            retry_save(session, retry, callback)
          else
            finish(callback, nil, util.err("SAVE_CANCELLED", "save cancelled"))
          end
        end
      )
      if not flow then return nil, prompt_err end
      return false
    end
    return true
  end

  local function ensure_source_buffer(session)
    local bufnr = session.source.bufnr
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      if not vim.api.nvim_buf_is_loaded(bufnr) then vim.fn.bufload(bufnr) end
      return true
    end
    if not session.source.path then
      return nil, util.err("SOURCE_UNNAMED", "source buffer was wiped; use RoomPlanSaveAs for this unnamed plan")
    end
    bufnr = storage.ensure_buffer(session.source.path)
    local replacement = vim.tbl_extend("force", session.source, { bufnr = bufnr })
    local updated, err = state.update_source(session, replacement)
    if not updated then return nil, err end
    session:attach_source_autocmds()
    return true
  end

  local function commit_guarded(session, adapter, context, patch, expected_revision, opts)
    session.internal_source_write = true
    local ok, first, second, third = pcall(adapter.commit, context, patch, expected_revision, opts)
    session.internal_source_write = false
    if not ok then
      return nil, util.err("SOURCE_COMMIT_FAILED", "unexpected save transaction failure", { cause = tostring(first) })
    end
    return first, second, third
  end

  function controller.save(session, opts, callback)
    opts = opts or {}
    if opts.noninteractive == nil then opts.noninteractive = not interactive_call(session, opts) end
    if opts.bang then opts.allow_invalid = true end
    local resolved, err = resolve(session, opts)
    if not resolved then return finish(callback, notify_error(err)) end
    if not opts.autosave then resolved.autosave_generation = (resolved.autosave_generation or 0) + 1 end
    if resolved.source_rebind_pending then
      err = util.err("SOURCE_REBIND_PENDING", "source buffer was renamed; use RoomPlanSaveAs to adopt a supported destination or restore its original name", {
        pending_path = resolved.source_rebind_pending,
      })
      if not opts.noninteractive then notify_error(err) end
      return finish(callback, nil, err)
    end
    local attached, attach_err = ensure_source_buffer(resolved)
    if not attached then
      if not opts.noninteractive then notify_error(attach_err) end
      return finish(callback, nil, attach_err)
    end
    if resolved.source_conflicted then
      err = util.err("SOURCE_CONFLICT", "resolve the RoomPlan source conflict before saving")
      if not opts.noninteractive then notify_error(err) end
      return finish(callback, nil, err)
    end
    local allowed, allow_err = save_allowed(resolved, opts, callback, controller.save)
    if allowed == false then return nil end
    if not allowed then
      if not opts.noninteractive then notify_error(allow_err) end
      return finish(callback, nil, allow_err)
    end
    if resolved.source.bufnr and not source_io.buffer_encoding_supported(resolved.source.bufnr) then
      err = util.err("SOURCE_ENCODING_UNSUPPORTED", "in-place save requires UTF-8; use Save As")
      if not opts.noninteractive then notify_error(err) end
      return finish(callback, nil, err)
    end
    local adapter = storage.adapter(resolved.source.adapter)
    local patch, prepare_err = adapter.prepare_save(resolved, resolved:model(), opts)
    if not patch then return finish(callback, notify_error(prepare_err)) end
    local revision, actual_or_err, locator_or_staged = commit_guarded(
      resolved, adapter,
      resolved.source, patch, resolved.source.revision, { write = true }
    )
    if not revision then
      err = actual_or_err
      if err and err.code == "SOURCE_CONFLICT" then
        resolved.source_conflicted = true
        resolved.durable_source_matches_savepoint = false
        resolved.retained_model_at_risk = true
      elseif locator_or_staged and locator_or_staged.staged then
        resolved.buffer_payload_revision_id = resolved:revision_id()
        resolved.pending_disk_write = true
        local staged_model, staged_revision, staged_locator = adapter.load(resolved.source)
        if staged_model and model.deep_equal(staged_model, resolved:model()) then
          resolved.source.revision = staged_revision
          resolved.source.locator = staged_locator
        end
      else
        -- A write hook may fail only after the authoritative buffer or disk was
        -- changed. Re-read conservatively so the retained model stays guarded.
        local current_model, current_revision, current_locator = adapter.load(resolved.source)
        if current_model and model.deep_equal(current_model, resolved:model()) then
          resolved.source.revision = current_revision
          resolved.source.locator = current_locator
          resolved.buffer_payload_revision_id = resolved:revision_id()
          resolved.pending_disk_write = resolved:source_buffer_modified()
            or current_revision.durable_model_matches ~= true
          resolved.retained_model_at_risk = current_revision.durable_model_matches ~= true
        else
          resolved.pending_disk_write = resolved:source_buffer_modified()
          resolved.retained_model_at_risk = true
        end
        resolved.source_conflicted = true
        resolved.durable_source_matches_savepoint = false
      end
      resolved:update_guard()
      if not opts.noninteractive then notify_error(err) end
      return finish(callback, nil, err)
    end
    local actual_model = actual_or_err or resolved:model()
    if not model.deep_equal(actual_model, resolved:model()) then
      resolved.source_conflicted = true
      resolved.retained_model_at_risk = true
      resolved:update_guard()
      err = util.err("SOURCE_HOOK_CHANGED_MODEL", "a write hook changed RoomPlan model semantics")
      return finish(callback, notify_error(err))
    end
    if resolved.source.bufnr and vim.bo[resolved.source.bufnr].modified then
      resolved.buffer_payload_revision_id = resolved:revision_id()
      resolved.pending_disk_write = true
      resolved.source.revision = revision
      if resolved.source.adapter == "norg" then resolved.source.locator = locator_or_staged end
      resolved:update_guard()
      err = util.err("SOURCE_POST_WRITE_MODIFIED", "source remained modified after write hooks; savepoint was not advanced")
      if not opts.noninteractive then notify_error(err) end
      return finish(callback, nil, err)
    end
    local locator = resolved.source.adapter == "norg" and locator_or_staged or nil
    local marked, mark_err = resolved:mark_saved(revision, locator)
    if not marked then return finish(callback, notify_error(mark_err)) end
    controller.refresh(resolved)
    if not opts.quiet then compat.notify("RoomPlan saved " .. (resolved.source.path or resolved.id)) end
    return finish(callback, resolved)
  end

  local function destination_context(path)
    local context = source_io.context({ path = path })
    local existing = vim.fn.bufnr(path)
    if existing ~= -1 and vim.api.nvim_buf_is_valid(existing) then
      vim.fn.bufload(existing)
      context = source_io.context({ bufnr = existing, path = path })
    end
    return context
  end

  local destination_confirmation_tag = {}

  local function same_disk_snapshot(left, right)
    if not left or not right then return left == right end
    if left.exists ~= right.exists or left.type ~= right.type then return false end
    if left.exists and left.type == "file" then return left.text == right.text end
    return true
  end

  local function destination_snapshot(context, key)
    local bufnr = context.bufnr
    if not bufnr or not vim.api.nvim_buf_is_loaded(bufnr) then
      return nil, util.err("SAVE_AS_DESTINATION_UNAVAILABLE", "Save As destination buffer is no longer available")
    end
    local disk, disk_err = source_io.disk_snapshot(context)
    if not disk then return nil, disk_err end
    return {
      tag = destination_confirmation_tag,
      key = key,
      adapter = context.adapter,
      path = context.path,
      bufnr = bufnr,
      changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
      modified = vim.bo[bufnr].modified,
      text = source_io.buffer_text(bufnr),
      disk = disk,
    }
  end

  local function verify_destination_snapshot(snapshot, context, key)
    if type(snapshot) ~= "table" or snapshot.tag ~= destination_confirmation_tag
      or snapshot.key ~= key or snapshot.adapter ~= context.adapter
      or snapshot.path ~= context.path or snapshot.bufnr ~= context.bufnr then
      return false
    end
    local bufnr = context.bufnr
    if not bufnr or not vim.api.nvim_buf_is_loaded(bufnr) then return false end
    local disk, disk_err = source_io.disk_snapshot(context)
    if not disk then return nil, disk_err end
    return snapshot.changedtick == vim.api.nvim_buf_get_changedtick(bufnr)
      and snapshot.modified == vim.bo[bufnr].modified
      and snapshot.text == source_io.buffer_text(bufnr)
      and same_disk_snapshot(snapshot.disk, disk)
  end

  local function confirm_destination(session, opts, context, key, prompt, callback)
    if opts.destination_confirmation ~= nil then
      local unchanged, verify_err = verify_destination_snapshot(opts.destination_confirmation, context, key)
      if unchanged then return true end
      if verify_err then return nil, verify_err end
      return nil, util.err(
        "SAVE_AS_DESTINATION_CHANGED",
        "Save As destination changed after confirmation; review it and run Save As again",
        { path = context.path }
      )
    end
    if opts.noninteractive then
      return nil, util.err("SAVE_AS_CONFIRM_REQUIRED", prompt)
    end
    local snapshot, snapshot_err = destination_snapshot(context, key)
    if not snapshot then return nil, snapshot_err end
    local flow, flow_err = require("roomplan.ui.prompts").confirm(
      session, "save-as-destination", prompt, { "Continue", "Cancel" }, function(choice)
        if choice == "Continue" then
          controller.save_as(session, vim.tbl_extend("force", opts, {
            destination_confirmation = snapshot,
            destination_confirmed = nil,
          }), callback)
        else
          finish(callback, nil, util.err("SAVE_AS_CANCELLED", "Save As cancelled"))
        end
      end
    )
    if not flow then return nil, flow_err end
    return false
  end

  function controller.save_as(session, opts, callback)
    opts = opts or {}
    if opts.noninteractive == nil then opts.noninteractive = not interactive_call(session, opts) end
    local resolved, err = resolve(session, opts)
    if not resolved then return finish(callback, notify_error(err)) end
    local requested_path = explicit_requested_path(opts)
    local path = explicit_path(opts)
    if not path then
      err = util.err("SAVE_AS_PATH_REQUIRED", "RoomPlanSaveAs requires a destination path")
      return finish(callback, notify_error(err))
    end
    local allowed, allow_err = save_allowed(resolved, opts, callback, controller.save_as)
    if allowed == false then return nil end
    if not allowed then
      if not opts.noninteractive then notify_error(allow_err) end
      return finish(callback, nil, allow_err)
    end

    local requested_stat = requested_path and vim.uv.fs_lstat(requested_path) or nil
    if requested_stat and requested_stat.type ~= "file" then
      err = util.err("SAVE_AS_UNSAFE_TARGET", "Save As destination must be an ordinary regular file, not a link or special file", {
        path = requested_path, type = requested_stat.type,
      })
      return finish(callback, notify_error(err))
    end

    local context = destination_context(path)
    local adapter, detect_err = storage.detect(context)
    if not adapter then return finish(callback, notify_error(detect_err)) end
    context.adapter = adapter.name
    local owner = find_existing(context)
    if owner and owner ~= resolved then
      err = util.err("SESSION_SOURCE_OWNED", "another RoomPlan session owns the Save As destination")
      return finish(callback, notify_error(err))
    end
    local target_stat = vim.uv.fs_lstat(path)
    if target_stat and target_stat.type ~= "file" then
      err = util.err("SAVE_AS_UNSAFE_TARGET", "Save As destination must be an ordinary regular file", {
        path = path, type = target_stat.type,
      })
      return finish(callback, notify_error(err))
    end
    local exists = target_stat ~= nil
    local revision, actual, locator

    if adapter.name == "json" then
      if exists or context.bufnr then
        if not context.bufnr then
          context.bufnr = storage.ensure_buffer(path)
          context.filetype = vim.bo[context.bufnr].filetype
        end
        local destination_text = source_io.buffer_text(context.bufnr)
        local destination_model, destination_revision
        if destination_text:match("^%s*$") then
          destination_revision = source_io.with_disk(source_io.revision(destination_text, context), context)
        else
          destination_model, destination_revision = adapter.load(context)
          if not destination_model then
            if not opts.noninteractive then notify_error(destination_revision) end
            return finish(callback, nil, destination_revision)
          end
        end
        if (exists or not destination_text:match("^%s*$")) and not opts.bang then
          local confirmed, confirm_err = confirm_destination(
            resolved, opts, context, "json-replace",
            "Replace the existing valid/empty RoomPlan JSON destination?", callback
          )
          if confirmed == false then return nil end
          if not confirmed then return finish(callback, nil, confirm_err) end
        end
        local patch, prepare_err = adapter.prepare_save(resolved, resolved:model(), opts)
        if not patch then return finish(callback, notify_error(prepare_err)) end
        revision, actual = commit_guarded(resolved, adapter, context, patch, destination_revision, { write = true })
      else
        local patch, prepare_err = adapter.prepare_save(resolved, resolved:model(), opts)
        if not patch then return finish(callback, notify_error(prepare_err)) end
        revision, actual = commit_guarded(resolved, adapter, context, patch, nil, { write = true })
        if revision then
          context.bufnr = storage.ensure_buffer(path)
          context.filetype = vim.bo[context.bufnr].filetype
          local reloaded, reload_revision = adapter.load(context)
          if not reloaded then return finish(callback, notify_error(reload_revision)) end
          actual, revision = reloaded, reload_revision
        end
      end
    else
      if not context.bufnr then
        context.bufnr = storage.ensure_buffer(path)
        context.filetype = "norg"
        vim.bo[context.bufnr].filetype = "norg"
      end
      local destination_model, destination_revision = adapter.load(context)
      if destination_model then
        local confirmed, confirm_err = confirm_destination(
          resolved, opts, context, "norg-replace",
          "Replace the existing RoomPlan payload in this Norg note?", callback
        )
        if confirmed == false then return nil end
        if not confirmed then return finish(callback, nil, confirm_err) end
        local patch, prepare_err = adapter.prepare_save(resolved, resolved:model(), opts)
        if not patch then return finish(callback, notify_error(prepare_err)) end
        revision, actual, locator = commit_guarded(
          resolved, adapter, context, patch, destination_revision, { write = true }
        )
      elseif type(destination_revision) ~= "table" or destination_revision.code ~= "NORG_PLAN_MISSING" then
        if not opts.noninteractive then notify_error(destination_revision) end
        return finish(callback, nil, destination_revision)
      else
        local destination_text = source_io.buffer_text(context.bufnr)
        if exists or not destination_text:match("^%s*$") then
          local confirmed, confirm_err = confirm_destination(
            resolved, opts, context, "norg-initialize",
            "Insert a RoomPlan block into this existing Norg note?", callback
          )
          if confirmed == false then return nil end
          if not confirmed then return finish(callback, nil, confirm_err) end
        end
        local initialize_opts = opts
        local headings, heading_err = adapter.headings(context)
        if not headings then return finish(callback, nil, heading_err) end
        if opts.destination_heading_line then
          local present = false
          for _, line in ipairs(headings) do if line == opts.destination_heading_line then present = true; break end end
          if not present then
            return finish(callback, nil, util.err("NORG_HEADING_CHANGED", "selected destination heading changed before Save As"))
          end
          initialize_opts = vim.tbl_extend("force", opts, { heading_line = opts.destination_heading_line })
        elseif #headings == 1 then
          initialize_opts = vim.tbl_extend("force", opts, { heading_line = headings[1] })
        elseif #headings > 1 then
          if opts.noninteractive then
            return finish(callback, nil, util.err("NORG_MULTIPLE_HEADINGS", "multiple destination Floor plan headings require a choice"))
          end
          vim.ui.select(headings, {
            prompt = "Insert at which destination Floor plan heading?",
            format_item = function(line) return "Floor plan heading at line " .. line end,
          }, function(line)
            if line then
              controller.save_as(resolved, vim.tbl_extend("force", opts, { destination_heading_line = line }), callback)
            else
              finish(callback, nil, util.err("SAVE_AS_CANCELLED", "Save As cancelled"))
            end
          end)
          return nil
        end
        local initialized_revision, initialized_locator = adapter.initialize(context, resolved:model(), initialize_opts)
        if not initialized_revision then return finish(callback, notify_error(initialized_locator)) end
        local patch, prepare_err = adapter.prepare_save({ source = { locator = initialized_locator } }, resolved:model(), opts)
        if not patch then return finish(callback, notify_error(prepare_err)) end
        revision, actual, locator = commit_guarded(resolved, adapter, context, patch, initialized_revision, { write = true })
      end
    end
    if not revision then return finish(callback, notify_error(actual)) end
    if actual and not model.deep_equal(actual, resolved:model()) then
      return finish(callback, notify_error(util.err("SAVE_AS_MODEL_MISMATCH", "Save As destination changed model semantics")))
    end
    local new_source = session_source(context, adapter, revision, locator)
    local updated, update_err = state.update_source(resolved, new_source)
    if not updated then return finish(callback, notify_error(update_err)) end
    resolved.source_rebind_pending = nil
    resolved:attach_source_autocmds()
    resolved:mark_saved(revision, locator)
    controller.refresh(resolved)
    if not opts.quiet and not opts.noninteractive then compat.notify("RoomPlan saved as " .. path) end
    return finish(callback, resolved)
  end

  function controller.save_as_prompt(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    local flow, flow_err = require("roomplan.ui.flow").new(resolved, "save-as")
    if not flow then return notify_error(flow_err) end
    flow:input({ prompt = "Save RoomPlan as: ", default = resolved.source.path }, function(path)
      flow:finish()
      controller.save_as(resolved, { args = path })
    end)
  end

  function controller.resolve_conflict(session)
    local resolved, err = resolve(session)
    if not resolved then return notify_error(err) end
    if not resolved.source_conflicted then
      compat.notify("RoomPlan source is not conflicted")
      return true
    end
    local adapter = storage.adapter(resolved.source.adapter)
    local overwrite_allowed = false
    if resolved.source.bufnr and vim.api.nvim_buf_is_loaded(resolved.source.bufnr)
      and not resolved.source_rebind_pending then
      local disk_ok = source_io.verify_expected_disk(resolved.source, resolved.source.revision)
      local external = disk_ok and adapter.load(resolved.source) or nil
      overwrite_allowed = external ~= nil
    end
    local choices = { "Review source", "Reload source", "Save As" }
    if overwrite_allowed then choices[#choices + 1] = "Overwrite current payload" end
    choices[#choices + 1] = "Cancel"
    local flow, flow_err = require("roomplan.ui.flow").new(resolved, "resolve-conflict")
    if not flow then return notify_error(flow_err) end
    flow:select(choices, { prompt = "Resolve RoomPlan source conflict" }, function(choice)
      flow:finish()
      if choice == "Review source" and resolved.source.bufnr and vim.api.nvim_buf_is_valid(resolved.source.bufnr) then
        vim.api.nvim_set_current_buf(resolved.source.bufnr)
      elseif choice == "Reload source" then
        controller.reload(resolved, { bang = true })
      elseif choice == "Save As" then
        controller.save_as_prompt(resolved)
      elseif choice == "Overwrite current payload" then
        local disk_ok, disk_err = source_io.verify_expected_disk(resolved.source, resolved.source.revision)
        local current_model = disk_ok and adapter.load(resolved.source) or nil
        if not disk_ok or not current_model then
          notify_error(disk_err or util.err("SOURCE_CONFLICT", "source is no longer safe to overwrite"))
          return
        end
        local overwrite_snapshot, snapshot_err = destination_snapshot(resolved.source, "conflict-overwrite")
        if not overwrite_snapshot then
          notify_error(snapshot_err)
          return
        end
        require("roomplan.ui.prompts").confirm(
          resolved,
          "overwrite-conflict",
          "Replace the currently parseable source payload with the retained RoomPlan model?",
          { "Overwrite payload", "Cancel" },
          function(confirmation)
            if confirmation ~= "Overwrite payload" then return end
            local unchanged, changed_err = verify_destination_snapshot(
              overwrite_snapshot, resolved.source, "conflict-overwrite"
            )
            if not unchanged then
              notify_error(changed_err or util.err(
                "SOURCE_CHANGED_DURING_CONFIRMATION",
                "source changed while overwrite confirmation was open; review it and try again"
              ))
              return
            end
            local disk_ok, disk_err = source_io.verify_expected_disk(resolved.source, resolved.source.revision)
            local current_model, current_revision, current_locator = adapter.load(resolved.source)
            if not disk_ok or not current_model then
              notify_error(disk_err or current_revision)
              return
            end
            resolved.source.revision = current_revision
            resolved.source.locator = current_locator
            resolved.source_conflicted = false
            resolved.retained_model_at_risk = false
            resolved.source_error = nil
            resolved:update_guard()
            controller.save(resolved, { interactive = true })
          end
        )
      end
    end)
  end

  function controller.maybe_autosave(session)
    local options = config.get().autosave
    if not options.enabled or session.closed or session.source_conflicted
      or session:schema_rewrite_pending()
    then
      return false
    end
    if session.source.adapter == "norg" then
      if not options.norg or session:source_buffer_modified() then return false end
    end
    session.autosave_generation = (session.autosave_generation or 0) + 1
    local generation = session.autosave_generation
    local revision_id = session:revision_id()
    vim.defer_fn(function()
      if session.closed or generation ~= session.autosave_generation
        or revision_id ~= session:revision_id() or session.source_conflicted
        or session:schema_rewrite_pending()
      then
        return
      end
      local _, summary = controller.validate(session)
      if summary and summary.errors == 0 then
        controller.save(session, { noninteractive = true, quiet = true, autosave = true })
      end
    end, options.debounce_ms)
    return true
  end

end

return M
