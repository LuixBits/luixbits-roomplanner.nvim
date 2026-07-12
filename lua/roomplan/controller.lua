local catalog = require("roomplan.catalog")
local compat = require("roomplan.compat")
local config = require("roomplan.config")
local model = require("roomplan.model")
local state = require("roomplan.state")
local storage = require("roomplan.storage")
local source_io = require("roomplan.storage.source")
local util = require("roomplan.util")
local validator = require("roomplan.validate")

local M = {}
local workspace_form_action

local function message(err)
  if type(err) == "table" then
    return err.message or err.code or vim.inspect(err)
  end
  return tostring(err)
end

local function notify_error(err)
  compat.notify(message(err), vim.log.levels.ERROR)
  return nil, err
end

local function finish(callback, value, err)
  if callback then callback(value, err) end
  return value, err
end

local function is_session(value)
  return type(value) == "table" and value.history and value.source and value.id
end

local function interactive_call(session, opts)
  return is_session(session) or (opts and (opts.interactive == true or opts.fargs ~= nil))
end

local function resolve(session, opts)
  if is_session(session) then return session end
  return state.resolve(opts or {})
end

local function explicit_path(opts)
  local path = opts and (opts.path or opts.args)
  if type(path) ~= "string" or path:match("^%s*$") then return nil end
  return compat.normalize_path(vim.fn.expand(path))
end

local function explicit_requested_path(opts)
  local path = opts and (opts.path or opts.args)
  if type(path) ~= "string" or path:match("^%s*$") then return nil end
  -- Keep the final path component unresolved for safety checks.  Resolving it
  -- first would turn a user-supplied symlink into an apparently regular target
  -- and let Save As overwrite through the link.
  return vim.fn.fnamemodify(vim.fn.expand(path), ":p")
end

local function context_for(opts, purpose)
  opts = opts or {}
  local path = explicit_path(opts)
  local bufnr = opts.bufnr
  if bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  if path then
    local existing = vim.fn.bufnr(path)
    if existing ~= -1 and vim.api.nvim_buf_is_valid(existing) then
      bufnr = existing
      vim.fn.bufload(bufnr)
    elseif purpose == "open" or path:lower():sub(-5) == ".norg"
      or (purpose == "init" and vim.uv.fs_lstat(path) ~= nil) then
      bufnr = storage.ensure_buffer(path)
    else
      bufnr = nil
    end
  elseif not bufnr then
    bufnr = vim.api.nvim_get_current_buf()
  end
  return source_io.context({ bufnr = bufnr, path = path, filetype = opts.filetype })
end

local function find_existing(context)
  local key = state.source_key(context)
  local id = key and state.source_keys[key]
  return id and state.get(id) or nil
end

local function reusable_existing(context, existing)
  if not existing or not context.bufnr or not existing.source.bufnr
    or context.bufnr == existing.source.bufnr then return existing end
  if not vim.api.nvim_buf_is_loaded(context.bufnr) or not vim.api.nvim_buf_is_loaded(existing.source.bufnr) then
    return existing
  end
  local alias_text = source_io.buffer_text(context.bufnr)
  local authoritative_text = source_io.buffer_text(existing.source.bufnr)
  if vim.bo[context.bufnr].modified or alias_text ~= authoritative_text then
    return nil, util.err("DUPLICATE_BUFFER_CONFLICT", "another loaded buffer for this RoomPlan path is modified or divergent", {
      authoritative_bufnr = existing.source.bufnr,
      alias_bufnr = context.bufnr,
    })
  end
  return existing
end

local function reattach_existing(context, existing)
  if not context.bufnr or (existing.source.bufnr and vim.api.nvim_buf_is_valid(existing.source.bufnr)) then
    return true
  end
  local replacement = vim.tbl_extend("force", existing.source, {
    bufnr = context.bufnr,
    path = context.path or existing.source.path,
    filetype = context.filetype,
  })
  local updated, err = state.update_source(existing, replacement)
  if not updated then return nil, err end
  existing:attach_source_autocmds()
  M.check_source(existing)
  return true
end

local function session_source(context, adapter, revision, locator)
  return {
    adapter = adapter.name,
    path = context.path,
    bufnr = context.bufnr,
    filetype = context.filetype,
    revision = revision,
    locator = locator,
  }
end

local function open_canvas(session)
  local ok, canvas = pcall(require, "roomplan.render.canvas")
  if not ok then
    return nil, util.err("CANVAS_UNAVAILABLE", "RoomPlan renderer is not available yet", { cause = canvas })
  end
  local opened, err = canvas.open(session, {
    on_select = function(hits) M.select_hits(session, hits) end,
    on_cursor = function()
      local workspace_ok, workspace = pcall(require, "roomplan.ui.workspace")
      if workspace_ok and session.workspace then
        local world = canvas.world_at_cursor(session)
        local canvas_config = config.get().canvas
        local zoom = session.viewport and session.viewport.mm_per_column
            and canvas_config.mm_per_column / session.viewport.mm_per_column
          or 1
        workspace.update_cursor(session, world, zoom)
      end
    end,
    on_wipe = function(handle)
      if handle and handle.buf then state.detach_buffer(handle.buf) end
      session.canvas = { bufnr = nil, winid = nil }
    end,
  })
  if not opened then return nil, err end
  if opened.buf then state.attach_buffer(session, opened.buf, "canvas") end
  if config.get().ui.experience == "workspace" then
    local workspace_ok, workspace = pcall(require, "roomplan.ui.workspace")
    if not workspace_ok then
      return nil, util.err("WORKSPACE_UNAVAILABLE", "RoomPlan workspace is unavailable", { cause = workspace })
    end
    local mounted_ok, mounted = pcall(workspace.mount, session, {
      on_form_action = function(active_session, action)
        if workspace_form_action then return workspace_form_action(active_session, action) end
        return nil, util.err("FORM_UNAVAILABLE", "structured form actions are not available")
      end,
    })
    if not mounted_ok then
      return nil, util.err("WORKSPACE_OPEN_FAILED", tostring(mounted), { cause = mounted })
    end
    workspace.set_interaction(session, session.mode or "NAV", session.form)
    canvas.redraw(opened, nil, nil, { reason = "workspace-mounted" })
  end
  return session
end

local function attach_loaded(context, adapter, loaded_model, revision, locator, info)
  local durable = revision.durable_model_matches ~= false
    and not (info and (info.normalized or info.migrated))
  local session, err = require("roomplan.session").new(
    session_source(context, adapter, revision, locator),
    loaded_model,
    { durable = durable }
  )
  if not session then return nil, err end
  session.normalization_info = info
  M.validate(session)
  return session
end

function M.open(_, opts, callback)
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
      }, function(choice)
        if choice == "Initialize RoomPlan block" then
          M.init_source(nil, {
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

function M.init_source(_, opts, callback)
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
        format_item = function(line) return "Floor plan heading at line " .. line end,
      }, function(line)
        if line then
          M.init_source(nil, vim.tbl_extend("force", opts, {
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
      }, function(choice)
        if choice and choice:match("^Initialize") then
          M.init_source(nil, vim.tbl_extend("force", opts, {
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
  M.validate(session)
  return finish(callback, open_canvas(session))
end

function M.check_source(session)
  if not is_session(session) or session.closed then return end
  session.source_needs_recheck = false
  local adapter = storage.adapter(session.source.adapter)
  local loaded, revision, locator = adapter.load(session.source)
  if not loaded then
    session.durable_source_matches_savepoint = false
    session.source_conflicted = true
    session.retained_model_at_risk = true
    session.source_error = revision
    session:update_guard()
    M.refresh(session)
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
    session.durable_source_matches_savepoint = revision.durable_model_matches == true
    session.source_error = nil
    session.retained_model_at_risk = false
    session:update_guard()
    return true
  end
  if disk_unchanged and model.deep_equal(loaded, session:model()) and not session:model_dirty() then
    session.source.revision = revision
    session.source.locator = locator
    session.source_conflicted = false
    session.durable_source_matches_savepoint = revision.durable_model_matches == true
    session.retained_model_at_risk = false
    session:update_guard()
    return true
  end
  session.source_conflicted = true
  session.durable_source_matches_savepoint = false
  session.retained_model_at_risk = not model.deep_equal(loaded, session:model())
    or revision.durable_model_matches == false
  session.source_external_model = loaded
  session.source_external_revision = revision
  session:update_guard()
  M.refresh(session)
  return nil, util.err("SOURCE_CONFLICT", "RoomPlan source payload changed after the session opened")
end

function M.source_written(session)
  if not is_session(session) or session.closed then return end
  local adapter = storage.adapter(session.source.adapter)
  local loaded, revision, locator = adapter.load(session.source)
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
    and revision.durable_model_matches and not session:source_buffer_modified() then
    session.source.revision = revision
    session.source.locator = locator
    session.source_conflicted = false
    session.durable_source_matches_savepoint = true
    session.retained_model_at_risk = false
    session.source_error = nil
    session:update_guard()
    M.refresh(session)
    return true
  end
  if staged_model and model.deep_equal(loaded, staged_model)
    and revision.durable_model_matches and not session:source_buffer_modified() then
    local marked = session.history:mark_saved_revision(staged_id)
    session.source.revision = revision
    session.source.locator = locator
    session.pending_disk_write = false
    session.source_conflicted = false
    session.durable_source_matches_savepoint = true
    session.retained_model_at_risk = false
    session.source_error = nil
    if staged_id == session:revision_id() then session.buffer_payload_revision_id = nil end
    if not marked then session.history:clear_savepoint() end
    session:update_guard()
    M.refresh(session)
    return true
  end
  return M.check_source(session)
end

function M.validate(session, show_list)
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
    local workspace_ok, workspace = pcall(require, "roomplan.ui.workspace")
    if config.get().ui.experience == "workspace" and workspace_ok and resolved.workspace then
      workspace.focus(resolved, "issues")
    else
      resolved.validation_list = require("roomplan.ui.validation_list").open(resolved, resolved.validation)
    end
  end
  require("roomplan.ui.inspector").refresh(resolved)
  local workspace_ok, workspace = pcall(require, "roomplan.ui.workspace")
  if workspace_ok and resolved.workspace then workspace.refresh(resolved, { "issues", "properties", "action_bar" }) end
  return resolved.validation, resolved.validation_summary
end

local function save_allowed(session, opts, callback, retry_fn)
  local diagnostics, summary = M.validate(session)
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
          require("roomplan.ui.validation_list").open(session, diagnostics)
          finish(callback, nil, util.err("SAVE_CANCELLED", "save cancelled to review validation errors"))
        elseif choice == "Save invalid draft" then
          local retry = vim.tbl_extend("force", opts, { allow_invalid = true })
          local retry_save = retry_fn or M.save
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

function M.save(session, opts, callback)
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
  local allowed, allow_err = save_allowed(resolved, opts, callback, M.save)
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
  M.refresh(resolved)
  if not opts.quiet then compat.notify("RoomPlan saved " .. (resolved.source.path or resolved.id)) end
  return finish(callback, resolved)
end

function M.reload(session, opts, callback)
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
        M.reload(resolved, vim.tbl_extend("force", opts, { confirmed = true }), callback)
      elseif choice == "Save first" then
        M.save(resolved, {}, function(saved, save_err)
          if saved then M.reload(resolved, { confirmed = true }, callback) else finish(callback, nil, save_err) end
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
    M.refresh(resolved)
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
  local durable = revision.durable_model_matches ~= false
    and not (info and (info.normalized or info.migrated))
  resolved:reset(loaded, revision, locator, { durable = durable })
  M.validate(resolved)
  M.refresh(resolved)
  return finish(callback, resolved)
end

local function snapping_options(session)
  if not session.snap_enabled or session.bypass_snap_once then return false end
  local options = vim.deepcopy(config.get().snapping)
  local viewport = session.viewport or require("roomplan.render.viewport").new(config.get().canvas)
  local cap = options.max_distance_mm
  options.tolerance_mm = {
    x = math.min(cap, options.tolerance_cells * viewport.mm_per_column),
    y = math.min(cap, options.tolerance_cells * viewport.mm_per_row),
  }
  options.mm_per_screen_unit = { x = viewport.mm_per_column, y = viewport.mm_per_row }
  return options
end

local function spatial_object_count(plan)
  if type(plan) ~= "table" then return 0 end
  return #(plan.rooms or {}) + #(plan.doors or {}) + #(plan.furniture or {})
end

function M.dispatch(session, action)
  local resolved, err = resolve(session)
  if not resolved then return nil, err end
  local was_spatially_empty = spatial_object_count(resolved:model()) == 0
  local current_diagnostics = M.validate(resolved)
  local new_model, result = require("roomplan.actions").apply(resolved:model(), action, {
    limits = config.get().limits,
    catalog = catalog,
    snapping = snapping_options(resolved),
    current_diagnostics = current_diagnostics,
  })
  resolved.bypass_snap_once = false
  if not new_model then return nil, result end
  local node, history_info = resolved:commit(new_model, result)
  if not node then return nil, history_info end
  if result.validation then
    resolved.validation = result.validation
    resolved.validation_summary = result.validation_summary
    resolved.validation_revision_id = node.revision_id
    require("roomplan.ui.inspector").refresh(resolved)
  else
    M.validate(resolved)
  end
  if was_spatially_empty and spatial_object_count(new_model) > 0 then
    -- The first object changes the canvas from an abstract empty viewport into
    -- a spatial scene. Fit exactly once and move the cursor to the selected
    -- object so the successful action cannot look like a no-op.
    M.fit(resolved, { focus_selection = true, immediate = true })
    M.focus_canvas(resolved)
  end
  return {
    session_id = resolved.id,
    revision_id = node.revision_id,
    model = new_model,
    result = result,
    history = history_info,
  }
end

function M.undo(session)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  local snapshot, node = resolved:undo()
  if not snapshot then return notify_error(node) end
  M.validate(resolved)
  return snapshot, node
end

function M.redo(session)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  local snapshot, node = resolved:redo()
  if not snapshot then return notify_error(node) end
  M.validate(resolved)
  return snapshot, node
end

function M.hide(session, opts)
  local resolved, err = resolve(session, opts)
  if not resolved then return notify_error(err) end
  local workspace_ok, workspace = pcall(require, "roomplan.ui.workspace")
  if workspace_ok and workspace.is_visible(resolved) then return workspace.hide(resolved) end
  local ok, canvas = pcall(require, "roomplan.render.canvas")
  if ok then return canvas.close(resolved) end
  return true
end

function M.close(session, opts, callback)
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
        M.save(resolved, {}, function(saved, save_err)
          if saved then M.close(resolved, { confirmed = true }, callback) else finish(callback, nil, save_err) end
        end)
      elseif choice == "Discard session" then
        M.close(resolved, { bang = true }, callback)
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
        M.save_as(session, vim.tbl_extend("force", opts, {
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

function M.save_as(session, opts, callback)
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
  local allowed, allow_err = save_allowed(resolved, opts, callback, M.save_as)
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
            M.save_as(resolved, vim.tbl_extend("force", opts, { destination_heading_line = line }), callback)
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
  M.refresh(resolved)
  if not opts.quiet and not opts.noninteractive then compat.notify("RoomPlan saved as " .. path) end
  return finish(callback, resolved)
end

function M.save_as_prompt(session)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  local flow, flow_err = require("roomplan.ui.flow").new(resolved, "save-as")
  if not flow then return notify_error(flow_err) end
  flow:input({ prompt = "Save RoomPlan as: ", default = resolved.source.path }, function(path)
    flow:finish()
    M.save_as(resolved, { args = path })
  end)
end

function M.resolve_conflict(session)
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
      M.reload(resolved, { bang = true })
    elseif choice == "Save As" then
      M.save_as_prompt(resolved)
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
          M.save(resolved, { interactive = true })
        end
      )
    end
  end)
end

function M.refresh(session)
  if not is_session(session) or session.closed then return end
  require("roomplan.ui.inspector").refresh(session)
  local workspace_ok, workspace = pcall(require, "roomplan.ui.workspace")
  if workspace_ok and session.workspace then workspace.refresh(session) end
  local ok, canvas = pcall(require, "roomplan.render.canvas")
  if ok and canvas.schedule_redraw then canvas.schedule_redraw(session) end
end

function M.maybe_autosave(session)
  local options = config.get().autosave
  if not options.enabled or session.closed or session.source_conflicted then return false end
  if session.source.adapter == "norg" then
    if not options.norg or session:source_buffer_modified() then return false end
  end
  session.autosave_generation = (session.autosave_generation or 0) + 1
  local generation = session.autosave_generation
  local revision_id = session:revision_id()
  vim.defer_fn(function()
    if session.closed or generation ~= session.autosave_generation
      or revision_id ~= session:revision_id() or session.source_conflicted then return end
    local _, summary = M.validate(session)
    if summary and summary.errors == 0 then
      M.save(session, { noninteractive = true, quiet = true, autosave = true })
    end
  end, options.debounce_ms)
  return true
end

function M.focus_canvas(session)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  local ok, canvas = pcall(require, "roomplan.render.canvas")
  if ok and canvas.focus and canvas.focus(resolved) then
    local workspace_ok, workspace = pcall(require, "roomplan.ui.workspace")
    if workspace_ok and workspace.is_visible(resolved) then workspace.focus(resolved, "canvas") end
    require("roomplan.ui.inspector").refresh(resolved)
    local handle = resolved.canvas and resolved.canvas.handle
    if handle and canvas.redraw then
      canvas.redraw(handle, nil, nil, { reason = "focus" })
    else
      M.refresh(resolved)
    end
    return true
  end
  return open_canvas(resolved)
end

function M.inspect(session)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  if config.get().ui.experience == "workspace" then
    if not resolved.canvas or not resolved.canvas.winid or not vim.api.nvim_win_is_valid(resolved.canvas.winid) then
      local opened, open_err = open_canvas(resolved)
      if not opened then return notify_error(open_err) end
    end
    return require("roomplan.ui.workspace").focus(resolved, "properties")
  end
  return require("roomplan.ui.inspector").toggle(resolved)
end

function M.objects(session)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  if config.get().ui.experience == "workspace" then
    if not resolved.canvas or not resolved.canvas.winid or not vim.api.nvim_win_is_valid(resolved.canvas.winid) then
      local opened, open_err = open_canvas(resolved)
      if not opened then return notify_error(open_err) end
    end
    return require("roomplan.ui.workspace").focus(resolved, "objects")
  end
  resolved.object_list = require("roomplan.ui.object_list").open(resolved)
  return resolved.object_list
end

function M.next_issue(session, direction)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  if type(direction) == "table" then direction = direction.direction end
  direction = direction == -1 and -1 or 1
  local diagnostics = M.validate(resolved)
  if #diagnostics == 0 then compat.notify("RoomPlan has no validation issues"); return end
  resolved.validation_index = ((resolved.validation_index or (direction < 0 and 1 or 0)) - 1 + direction) % #diagnostics + 1
  local diagnostic = diagnostics[resolved.validation_index]
  if diagnostic.object then resolved.selection = { kind = diagnostic.object.kind, id = diagnostic.object.id } end
  M.focus_canvas(resolved)
  compat.notify(string.format("%s: %s", diagnostic.code, diagnostic.message),
    diagnostic.severity == "error" and vim.log.levels.ERROR or vim.log.levels.WARN)
  return diagnostic
end

local function canvas_size(session)
  local winid = session.canvas and session.canvas.winid
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return math.max(1, vim.o.columns), math.max(1, vim.o.lines - config.get().canvas.header_lines - 3)
  end
  local local_footer = session.workspace and session.workspace.owns_footer and 0 or 1
  return vim.api.nvim_win_get_width(winid),
    math.max(1, vim.api.nvim_win_get_height(winid) - config.get().canvas.header_lines - local_footer)
end

local function ensure_viewport(session)
  if not session.viewport then
    local options = config.get().canvas
    session.viewport = require("roomplan.render.viewport").new({
      mm_per_column = options.mm_per_column,
      cell_aspect = options.cell_aspect,
    })
  end
  return session.viewport
end

function M.fit(session, opts)
  opts = type(opts) == "table" and opts or {}
  local resolved, err = resolve(session, opts)
  if not resolved then return notify_error(err) end
  local width, height = canvas_size(resolved)
  local options = config.get().canvas
  local scene = require("roomplan.scene.build").build(resolved:model(), resolved.validation, {
    selected = resolved.selection,
    show_grid = options.show_grid,
    show_dimensions = options.show_dimensions,
  })
  resolved.viewport = require("roomplan.render.viewport").fit_scene(scene, width, height, {
    mm_per_column = ensure_viewport(resolved).mm_per_column,
    cell_aspect = options.cell_aspect,
    fit_margin_cells = options.fit_margin_cells,
    min_mm_per_column = options.min_mm_per_column,
    max_mm_per_column = options.max_mm_per_column,
  })
  if opts.immediate then
    require("roomplan.ui.inspector").refresh(resolved)
    local ok, canvas = pcall(require, "roomplan.render.canvas")
    local handle = ok and resolved.canvas and resolved.canvas.handle
    if handle and canvas.redraw then
      canvas.redraw(handle, scene, resolved.viewport, {
        fit = true,
        focus_selection = opts.focus_selection == true,
        reason = "fit",
      })
    else
      M.refresh(resolved)
    end
  else
    M.refresh(resolved)
  end
  return resolved.viewport
end

local function aspect_target(session, opts)
  if is_session(session) then return session end
  opts = opts or {}
  if opts.session_id then return state.get(opts.session_id) end
  local bufnr = opts.bufnr
  if bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  local current = state.for_buffer(bufnr)
  if current then return current end
  local sessions = state.list()
  return #sessions == 1 and sessions[1] or nil
end

---Calibrate terminal cell height/width for this Neovim process. setup() stays
---the persistent configuration source; this runtime override refits the active
---session immediately when one can be identified.
function M.set_aspect(session, opts, callback)
  if type(opts) ~= "table" then opts = { ratio = opts } end
  opts = opts or {}
  local raw = opts.ratio ~= nil and opts.ratio or opts.args
  if type(raw) == "string" and raw:match("^%s*$") then raw = nil end
  if raw == nil then
    vim.ui.input({
      prompt = "RoomPlan terminal cell height/width ratio: ",
      default = string.format("%.3g", config.get().canvas.cell_aspect),
    }, function(value)
      if value == nil then
        finish(callback, nil, util.err("ASPECT_CANCELLED", "RoomPlan aspect calibration cancelled"))
        return
      end
      M.set_aspect(session, vim.tbl_extend("force", opts, { ratio = value }), callback)
    end)
    return nil
  end

  local ratio = type(raw) == "number" and raw or tonumber(raw)
  local updated, config_err = config.set_cell_aspect(ratio)
  if not updated then return finish(callback, notify_error(config_err)) end

  local target = aspect_target(session, opts)
  if target and not target.closed then
    local handle = target.canvas and target.canvas.handle
    if handle and handle.opts then handle.opts.cell_aspect = updated end
    M.fit(target, { immediate = true })
  end
  if not opts.quiet then
    compat.notify(string.format("RoomPlan cell aspect set to %.3g (height / width)", updated))
  end
  return finish(callback, updated)
end

M.aspect = M.set_aspect

function M.zoom(session, direction)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  local viewport = ensure_viewport(resolved)
  local width, height = canvas_size(resolved)
  local options = config.get().canvas
  local limits = {
    columns = width,
    rows = height,
    min_mm_per_column = options.min_mm_per_column,
    max_mm_per_column = options.max_mm_per_column,
  }
  local anchor
  local canvas_ok, canvas = pcall(require, "roomplan.render.canvas")
  if canvas_ok then
    local logical = canvas.logical_cursor(resolved)
    local world = canvas.world_at_cursor(resolved)
    if logical and world then
      anchor = {
        world_x = world.x, world_y = world.y,
        screen_x = logical.column, screen_y = logical.row,
      }
    end
  end
  if direction == "in" then
    resolved.viewport = require("roomplan.render.viewport").zoom_in(viewport, options.zoom_factor, anchor, limits)
  else
    resolved.viewport = require("roomplan.render.viewport").zoom_out(viewport, options.zoom_factor, anchor, limits)
  end
  M.refresh(resolved)
  return resolved.viewport
end

function M.set_mode(session, mode)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  if mode == "MOVE" and not resolved.selection then
    return notify_error(util.err("SELECTION_REQUIRED", "select a room, door, or furniture before entering MOVE mode"))
  end
  if mode ~= "NAV" and mode ~= "MOVE" and mode ~= "PAN" then
    return notify_error(util.err("MODE_INVALID", "unsupported RoomPlan mode " .. tostring(mode)))
  end
  resolved.mode = mode
  local workspace_ok, workspace = pcall(require, "roomplan.ui.workspace")
  if workspace_ok and resolved.workspace then
    workspace.set_interaction(resolved, mode, resolved.form)
    if (mode == "MOVE" or mode == "PAN") and workspace.is_visible(resolved) then
      workspace.focus(resolved, "canvas")
    end
  end
  M.refresh(resolved)
  return mode
end

local function move_canvas_cursor(session, dx, dy, coarse)
  local ok, canvas = pcall(require, "roomplan.render.canvas")
  if not ok then return end
  local cursor = canvas.logical_cursor(session)
  if not cursor then return end
  local step = coarse and 5 or 1
  local width, height = canvas_size(session)
  local row = util.clamp(cursor.row - dy * step, 0, height - 1)
  local column = util.clamp(cursor.column + dx * step, 0, width - 1)
  canvas.set_logical_cursor(session, row, column)
end

function M.direction(session, dx, dy, scale)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  if resolved.mode == "PAN" then
    local cells = scale == "coarse" and config.get().canvas.pan_coarse_step_cells or config.get().canvas.pan_step_cells
    resolved.viewport = require("roomplan.render.viewport").pan_cells(ensure_viewport(resolved), dx * cells, dy * cells)
    M.refresh(resolved)
    return resolved.viewport
  elseif resolved.mode ~= "MOVE" then
    move_canvas_cursor(resolved, dx, dy, scale == "coarse")
    return true
  end
  local selection = resolved.selection
  if not selection then return notify_error(util.err("SELECTION_REQUIRED", "MOVE mode requires a selection")) end
  local settings = resolved:model().settings
  local step = scale == "fine" and settings.fine_step_mm
    or scale == "coarse" and settings.coarse_step_mm
    or settings.normal_step_mm
  local action
  if selection.kind == "room" then
    action = { type = "move_room", id = selection.id, delta_mm = { dx * step, dy * step } }
  elseif selection.kind == "furniture" then
    action = { type = "move_furniture", id = selection.id, delta_mm = { dx * step, dy * step } }
  elseif selection.kind == "door" then
    local door = model.find(resolved:model(), "door", selection.id)
    if not door then return notify_error(util.err("SELECTION_STALE", "selected door no longer exists")) end
    local delta = (door.side == "north" or door.side == "south") and dx * step or dy * step
    action = { type = "edit_door", id = door.id, patch = { offset_mm = door.offset_mm + delta } }
  else
    return notify_error(util.err("SELECTION_NOT_MOVABLE", "selected object cannot be moved"))
  end
  local result, action_err = M.dispatch(resolved, action)
  if not result then return notify_error(action_err) end
  return result
end

function M.pan(session, dx, dy, coarse)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  local cells = coarse and config.get().canvas.pan_coarse_step_cells or config.get().canvas.pan_step_cells
  resolved.viewport = require("roomplan.render.viewport").pan_cells(ensure_viewport(resolved), dx * cells, dy * cells)
  M.refresh(resolved)
  return resolved.viewport
end

function M.select_hits(session, hits, cycle_key)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  hits = hits or {}
  if #hits == 0 then resolved.selection = nil; M.refresh(resolved); return end
  resolved.selection_cycle = resolved.selection_cycle or {}
  local current = resolved.selection_cycle.key == cycle_key and resolved.selection or nil
  local index = 1
  if current then
    for candidate_index, candidate in ipairs(hits) do
      if candidate.id == current.id and (candidate.type or candidate.kind) == current.kind then
        index = candidate_index % #hits + 1
        break
      end
    end
  end
  local candidate = hits[index]
  resolved.selection = { kind = candidate.type or candidate.kind, id = candidate.id }
  resolved.selection_cycle.key = cycle_key
  resolved.selection_cycle.index = index
  M.refresh(resolved)
  return resolved.selection
end

function M.select_under_cursor(session)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  local ok, canvas = pcall(require, "roomplan.render.canvas")
  if not ok or not canvas.hit_candidates then return nil end
  local cursor = canvas.logical_cursor(resolved)
  local key = cursor and string.format("%d:%d", cursor.row, cursor.column) or nil
  return M.select_hits(resolved, canvas.hit_candidates(resolved) or {}, key)
end

function M.select_next(session, direction)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  local scene = require("roomplan.scene.build").build(resolved:model(), resolved.validation, { selected = resolved.selection })
  local objects = scene.objects or {}
  if #objects == 0 then resolved.selection = nil; return nil end
  local current_index = direction < 0 and 1 or 0
  for index, object in ipairs(objects) do
    if resolved.selection and object.id == resolved.selection.id and object.type == resolved.selection.kind then
      current_index = index
      break
    end
  end
  local next_index = ((current_index - 1 + direction) % #objects) + 1
  resolved.selection = { kind = objects[next_index].type, id = objects[next_index].id }
  M.refresh(resolved)
  return resolved.selection
end

function M.toggle_snap(session)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  resolved.snap_enabled = not resolved.snap_enabled
  compat.notify("RoomPlan snapping " .. (resolved.snap_enabled and "enabled" or "disabled"))
  M.refresh(resolved)
  return resolved.snap_enabled
end

function M.bypass_snap(session)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  resolved.bypass_snap_once = true
  compat.notify("RoomPlan will bypass snapping for the next move")
  return true
end

function M.escape(session)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  if resolved.form then
    require("roomplan.ui.form").cancel(resolved.form, "cancelled")
  elseif resolved.workflow and resolved.workflow.kind then
    require("roomplan.ui.flow").cancel(resolved, "cancelled")
  elseif resolved.mode ~= "NAV" then
    resolved.mode = "NAV"
  else
    resolved.selection = nil
  end
  local workspace_ok, workspace = pcall(require, "roomplan.ui.workspace")
  if workspace_ok and resolved.workspace then
    workspace.set_interaction(resolved, resolved.mode or "NAV", resolved.form)
  end
  M.refresh(resolved)
end

local function find_entity(session, selection)
  if not selection then return nil end
  return model.find(session:model(), selection.kind, selection.id)
end

local function generate_id(session, kind, name)
  local ids = require("roomplan.ids")
  local id, err = ids.generate(kind, name, ids.used_set(session:model(), session.reserved_ids))
  if id then
    session.reserved_ids = session.reserved_ids or {}
    session.reserved_ids[id] = true
  end
  return id, err
end

local function structured_ui_enabled()
  return config.get().ui.experience == "workspace"
end

local function focus_after_form(session)
  vim.schedule(function()
    if session and not session.closed then
      -- The submit action redraws while the form mode is still active, and
      -- the form closes immediately afterwards. Redraw once more so the
      -- canvas header cannot keep a stale "ROOM CREATE/EDIT" label.
      M.refresh(session)
      local workspace_ok, workspace = pcall(require, "roomplan.ui.workspace")
      if workspace_ok and workspace.is_visible(session) then workspace.focus(session, "canvas")
      else M.focus_canvas(session) end
    end
  end)
end

local function open_structured_form(session, spec)
  local form = require("roomplan.ui.form")
  local handle, err = form.open(session, spec, {
    on_submit = function(draft, form_state)
      local action, build_err = spec.build(draft, form_state.context)
      if not action then return nil, build_err end
      local result, dispatch_err = M.dispatch(session, action)
      if not result then return nil, dispatch_err end
      focus_after_form(session)
      return result
    end,
    on_cancel = function() focus_after_form(session) end,
  })
  if not handle then return notify_error(err) end
  return handle
end

workspace_form_action = function(session, action)
  local handle = session and session.form
  if not handle then return nil, util.err("FORM_UNAVAILABLE", "no structured RoomPlan form is active") end
  return require("roomplan.ui.form").perform(handle, action)
end

local function commit_ui(session, action, flow)
  local result, err = M.dispatch(session, action)
  if not result then
    local forceable_room = {
      add_room = true, move_room = true, resize_room = true,
      align_room = true, duplicate_room = true,
    }
    if flow and flow:is_current() and err and err.code == "LAYOUT_BLOCKED"
      and forceable_room[action.type] then
      flow:select({ "Force this room operation", "Cancel" }, {
        prompt = "Operation introduces layout errors. Force it as an invalid draft?",
      }, function(choice)
        if choice == "Force this room operation" then
          local forced = vim.tbl_extend("force", action, { force = true })
          local forced_result, forced_err = M.dispatch(session, forced)
          if forced_result then
            flow:finish()
            session.mode = "NAV"
            M.focus_canvas(session)
          else
            flow:cancel("force failed")
            notify_error(forced_err)
          end
        else
          flow:cancel("cancelled")
        end
      end)
      return flow
    end
    if flow then flow:cancel("action failed") end
    return notify_error(err)
  end
  if flow then flow:finish() end
  session.mode = "NAV"
  M.focus_canvas(session)
  return result
end

local function room_choices(session)
  local result = {}
  for _, room in ipairs(session:model().rooms) do result[#result + 1] = room end
  return result
end

local function choose_room(flow, session, prompt, callback, exclude_id)
  local rooms = {}
  for _, room in ipairs(room_choices(session)) do
    if room.id ~= exclude_id then rooms[#rooms + 1] = room end
  end
  if #rooms == 0 then
    flow:cancel("no rooms")
    notify_error(util.err("ROOM_REQUIRED", "add a room first"))
    return
  end
  flow:select(rooms, {
    prompt = prompt or "Room:",
    format_item = function(room) return string.format("%s (%s)", room.name, room.id) end,
  }, callback)
end

local function cursor_world(session)
  local ok, canvas = pcall(require, "roomplan.render.canvas")
  if not ok or not canvas.logical_cursor then return nil end
  local first, second = canvas.logical_cursor(session)
  local column, row
  if type(first) == "table" then
    column, row = first.column or first.col or first[1], first.row or first[2]
  else
    column, row = first, second
  end
  if type(column) ~= "number" or type(row) ~= "number" then return nil end
  local x, y = require("roomplan.render.viewport").screen_to_world(ensure_viewport(session), column, row)
  return { util.round(x), util.round(y) }
end

function M.add_room(session)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  if structured_ui_enabled() then
    local spec = require("roomplan.ui.forms").room.add(resolved, { cursor_mm = cursor_world(resolved) })
    return open_structured_form(resolved, spec)
  end
  local flow, flow_err = require("roomplan.ui.flow").new(resolved, "add-room")
  if not flow then return notify_error(flow_err) end
  flow:input({ prompt = "Room name: ", default = "Room" }, function(name)
    require("roomplan.ui.prompts").measurement(flow, {
      prompt = "Room width: ", default = 4000, max = config.get().limits.max_dimension_mm,
    }, function(width)
      require("roomplan.ui.prompts").measurement(flow, {
        prompt = "Room depth: ", default = 3000, max = config.get().limits.max_dimension_mm,
      }, function(depth)
        local placements = { "Automatic non-overlapping", "World origin", "Canvas cursor" }
        local reference = resolved.selection and resolved.selection.kind == "room" and find_entity(resolved, resolved.selection) or nil
        if reference then
          vim.list_extend(placements, {
            "North of " .. reference.name, "East of " .. reference.name,
            "South of " .. reference.name, "West of " .. reference.name,
          })
        end
        flow:select(placements, { prompt = "Initial placement:" }, function(choice)
          local origin = { 0, 0 }
          if choice == "Automatic non-overlapping" then
            local placement, place_err = require("roomplan.geometry.alignment").auto_place({ width, depth }, resolved:model().rooms, {
              cursor_mm = cursor_world(resolved),
              max_distance_mm = config.get().limits.max_auto_place_distance_mm,
            })
            if not placement then flow:cancel("placement failed"); notify_error(place_err); return end
            origin = placement.origin_mm
          elseif choice == "Canvas cursor" then
            origin = cursor_world(resolved) or origin
          elseif reference and choice ~= "World origin" then
            local operation = choice:match("^North") and "place_north"
              or choice:match("^East") and "place_east"
              or choice:match("^South") and "place_south"
              or "place_west"
            local proposal = require("roomplan.geometry.alignment").propose(
              { origin_mm = origin, size_mm = { width, depth } }, reference, operation
            )
            origin = proposal.origin_mm
          end
          local id, id_err = generate_id(resolved, "room", name)
          if not id then flow:cancel("id failed"); notify_error(id_err); return end
          commit_ui(resolved, {
            type = "add_room",
            room = model.new_room({ id = id, name = name, origin_mm = origin, size_mm = { width, depth } }),
          }, flow)
        end)
      end)
    end)
  end)
  return flow
end

function M.add_furniture(session)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  if structured_ui_enabled() then
    if #resolved:model().rooms == 0 then
      return notify_error(util.err("ROOM_REQUIRED", "add a room before placing furniture"))
    end
    local spec = require("roomplan.ui.forms").furniture.add(resolved, { cursor_mm = cursor_world(resolved) })
    return open_structured_form(resolved, spec)
  end
  local flow, flow_err = require("roomplan.ui.flow").new(resolved, "add-furniture")
  if not flow then return notify_error(flow_err) end
  choose_room(flow, resolved, "Place furniture in room:", function(room)
    local templates = catalog.all()
    for _, template in ipairs(resolved:model().custom_templates) do templates[#templates + 1] = template end
    flow:select(templates, {
      prompt = "Furniture template:",
      format_item = function(item)
        return string.format("%s — %d × %d × %d mm", item.name, unpack(item.default_size_mm))
      end,
    }, function(template)
      local values = {}
      local labels = { "Width", "Depth", "Height" }
      local function dimension(index)
        if index > 3 then
          flow:input({ prompt = "Furniture label: ", default = template.name }, function(name)
            local positions = { "Room centre", "Canvas cursor", "Exact room-local coordinates" }
            flow:select(positions, { prompt = "Placement:" }, function(position)
              local function add_at(center)
                local id, id_err = generate_id(resolved, "furniture", name)
                if not id then flow:cancel("id failed"); notify_error(id_err); return end
                commit_ui(resolved, {
                  type = "add_furniture",
                  furniture = model.new_furniture({
                    id = id, room_id = room.id, template_id = template.id,
                    name = name, category = template.category, center_mm = center,
                    size_mm = values, rotation_deg = 0,
                  }),
                }, flow)
              end
              if position == "Room centre" then
                add_at({ util.round(room.size_mm[1] / 2), util.round(room.size_mm[2] / 2) })
              elseif position == "Canvas cursor" then
                local world = cursor_world(resolved)
                add_at(world and { world[1] - room.origin_mm[1], world[2] - room.origin_mm[2] }
                  or { util.round(room.size_mm[1] / 2), util.round(room.size_mm[2] / 2) })
              else
                require("roomplan.ui.prompts").measurement(flow, {
                  prompt = "Room-local X: ", default = util.round(room.size_mm[1] / 2), allow_negative = true, allow_zero = true,
                }, function(x)
                  require("roomplan.ui.prompts").measurement(flow, {
                    prompt = "Room-local Y: ", default = util.round(room.size_mm[2] / 2), allow_negative = true, allow_zero = true,
                  }, function(y) add_at({ x, y }) end)
                end)
              end
            end)
          end)
          return
        end
        require("roomplan.ui.prompts").measurement(flow, {
          prompt = labels[index] .. ": ", default = template.default_size_mm[index], max = config.get().limits.max_dimension_mm,
        }, function(value) values[index] = value; dimension(index + 1) end)
      end
      dimension(1)
    end)
  end)
  return flow
end

function M.add_door(session)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  if structured_ui_enabled() then
    if #resolved:model().rooms == 0 then
      return notify_error(util.err("ROOM_REQUIRED", "add a room before placing a door"))
    end
    local spec = require("roomplan.ui.forms").door.add(resolved, { cursor_mm = cursor_world(resolved) })
    return open_structured_form(resolved, spec)
  end
  local flow, flow_err = require("roomplan.ui.flow").new(resolved, "add-door")
  if not flow then return notify_error(flow_err) end
  choose_room(flow, resolved, "Door owner room:", function(room)
    flow:select({ "north", "east", "south", "west" }, { prompt = "Wall side:" }, function(side)
      require("roomplan.ui.prompts").measurement(flow, {
        prompt = "Door width: ", default = resolved:model().settings.default_door_width_mm,
        max = math.max(room.size_mm[1], room.size_mm[2]),
      }, function(width)
        local edge_length = (side == "north" or side == "south") and room.size_mm[1] or room.size_mm[2]
        local function continue_with_offset(offset)
          flow:select({ "start", "end" }, { prompt = "Hinge:" }, function(hinge)
            local destinations = { { label = "Outside", id = nil } }
            for _, other in ipairs(resolved:model().rooms) do
              if other.id ~= room.id then
                local shared = require("roomplan.geometry.adjacency").between(room, other)
                if shared and shared.a_side == side then
                  destinations[#destinations + 1] = { label = other.name, id = other.id }
                end
              end
            end
            flow:select(destinations, {
              prompt = "Door connects to:", format_item = function(item) return item.label end,
            }, function(destination)
              local openings = destination.id and { "owner", "connected" } or { "owner", "outside" }
              flow:select(openings, { prompt = "Door opens into:" }, function(opens_into)
                local id, id_err = generate_id(resolved, "door", room.name .. "-" .. side)
                if not id then flow:cancel("id failed"); notify_error(id_err); return end
                commit_ui(resolved, {
                  type = "add_door",
                  door = model.new_door({
                    id = id, room_id = room.id, connects_to_room_id = destination.id,
                    side = side, offset_mm = offset, width_mm = width,
                    hinge = hinge, opens_into = opens_into, open_angle_deg = 90,
                  }),
                }, flow)
              end)
            end)
          end)
        end
        flow:select({ "Numeric offset", "Centre opening at canvas cursor" }, {
          prompt = "Door placement:",
        }, function(placement)
          if placement == "Centre opening at canvas cursor" then
            local world = cursor_world(resolved)
            if not world then
              flow:cancel("cursor unavailable")
              notify_error(util.err("CURSOR_UNAVAILABLE", "place the canvas cursor in the plan and retry"))
              return
            end
            local coordinate = (side == "north" or side == "south")
                and (world[1] - room.origin_mm[1])
              or (world[2] - room.origin_mm[2])
            continue_with_offset(util.clamp(util.round(coordinate - width / 2), 0, math.max(0, edge_length - width)))
          else
            require("roomplan.ui.prompts").measurement(flow, {
              prompt = "Offset from canonical edge start: ", default = math.max(0, util.round((edge_length - width) / 2)),
              allow_zero = true, max = edge_length,
            }, continue_with_offset)
          end
        end)
      end)
    end)
  end)
  return flow
end

function M.align_room(session)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  if structured_ui_enabled() then
    if #resolved:model().rooms < 2 then
      return notify_error(util.err("ROOM_REFERENCE_REQUIRED", "add at least two rooms before aligning them"))
    end
    return open_structured_form(resolved, require("roomplan.ui.forms").alignment.new(resolved))
  end
  local flow, flow_err = require("roomplan.ui.flow").new(resolved, "align-room")
  if not flow then return notify_error(flow_err) end
  local selected = resolved.selection and resolved.selection.kind == "room" and find_entity(resolved, resolved.selection) or nil
  local function moving_selected(moving)
    choose_room(flow, resolved, "Reference room:", function(reference)
      local operations = {
        { label = "Align left edges", value = "align_left" },
        { label = "Align right edges", value = "align_right" },
        { label = "Align north/top edges", value = "align_top" },
        { label = "Align south/bottom edges", value = "align_bottom" },
        { label = "Align horizontal centres", value = "align_center_x" },
        { label = "Align vertical centres", value = "align_center_y" },
        { label = "Place north", value = "place_north" },
        { label = "Place east", value = "place_east" },
        { label = "Place south", value = "place_south" },
        { label = "Place west", value = "place_west" },
        { label = "Place north with gap", value = "place_north", gap = true },
        { label = "Place east with gap", value = "place_east", gap = true },
        { label = "Place south with gap", value = "place_south", gap = true },
        { label = "Place west with gap", value = "place_west", gap = true },
        { label = "Snap a moving corner to a reference corner", value = "snap_corner", corners = true },
      }
      flow:select(operations, {
        prompt = "Alignment operation:", format_item = function(item) return item.label end,
      }, function(operation)
        local function commit_alignment(gap, moving_corner, reference_corner)
          commit_ui(resolved, {
            type = "align_room", id = moving.id, reference_room_id = reference.id,
            operation = operation.value, gap_mm = gap or 0,
            moving_corner = moving_corner, reference_corner = reference_corner,
          }, flow)
        end
        if operation.corners then
          local corners = { "southwest", "southeast", "northwest", "northeast" }
          flow:select(corners, { prompt = "Moving room corner:" }, function(moving_corner)
            flow:select(corners, { prompt = "Reference room corner:" }, function(reference_corner)
              commit_alignment(0, moving_corner, reference_corner)
            end)
          end)
        elseif operation.gap then
          require("roomplan.ui.prompts").measurement(flow, {
            prompt = "Gap: ", default = resolved:model().settings.grid_mm, allow_zero = true,
          }, commit_alignment)
        else commit_alignment(0) end
      end)
    end, moving.id)
  end
  if selected then moving_selected(selected)
  else choose_room(flow, resolved, "Moving room:", moving_selected) end
  return flow
end

function M.rotate_selected(session)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  if not resolved.selection or resolved.selection.kind ~= "furniture" then
    return notify_error(util.err("FURNITURE_REQUIRED", "select furniture to rotate"))
  end
  local result, action_err = M.dispatch(resolved, { type = "rotate_furniture", id = resolved.selection.id, delta_deg = 90 })
  if not result then return notify_error(action_err) end
  return result
end

local function edit_room_flow(session, room, flow)
  flow:select({ "Rename", "Exact origin", "Dimensions" }, { prompt = "Edit room:" }, function(choice)
    if choice == "Rename" then
      flow:input({ prompt = "Room name: ", default = room.name }, function(name)
        commit_ui(session, { type = "rename_room", id = room.id, name = name }, flow)
      end)
    elseif choice == "Exact origin" then
      require("roomplan.ui.prompts").measurement(flow, {
        prompt = "World X: ", default = room.origin_mm[1], allow_negative = true, allow_zero = true,
      }, function(x)
        require("roomplan.ui.prompts").measurement(flow, {
          prompt = "World Y: ", default = room.origin_mm[2], allow_negative = true, allow_zero = true,
        }, function(y) commit_ui(session, { type = "move_room", id = room.id, origin_mm = { x, y }, exact = true }, flow) end)
      end)
    else
      require("roomplan.ui.prompts").measurement(flow, { prompt = "Width: ", default = room.size_mm[1] }, function(width)
        require("roomplan.ui.prompts").measurement(flow, { prompt = "Depth: ", default = room.size_mm[2] }, function(depth)
          commit_ui(session, { type = "resize_room", id = room.id, size_mm = { width, depth } }, flow)
        end)
      end)
    end
  end)
end

local function edit_furniture_flow(session, furniture, flow)
  flow:select({ "Rename", "Exact position", "Dimensions", "Rotation", "Template", "Save dimensions as custom template" }, { prompt = "Edit furniture:" }, function(choice)
    if choice == "Rename" then
      flow:input({ prompt = "Furniture name: ", default = furniture.name }, function(name)
        commit_ui(session, { type = "rename_furniture", id = furniture.id, name = name }, flow)
      end)
    elseif choice == "Exact position" then
      require("roomplan.ui.prompts").measurement(flow, {
        prompt = "Room-local X: ", default = furniture.center_mm[1], allow_negative = true, allow_zero = true,
      }, function(x)
        require("roomplan.ui.prompts").measurement(flow, {
          prompt = "Room-local Y: ", default = furniture.center_mm[2], allow_negative = true, allow_zero = true,
        }, function(y) commit_ui(session, { type = "move_furniture", id = furniture.id, center_mm = { x, y }, exact = true }, flow) end)
      end)
    elseif choice == "Dimensions" then
      local values = {}
      local function next_dimension(index)
        if index > 3 then
          commit_ui(session, { type = "resize_furniture", id = furniture.id, size_mm = values }, flow)
          return
        end
        local labels = { "Width", "Depth", "Height" }
        require("roomplan.ui.prompts").measurement(flow, {
          prompt = labels[index] .. ": ", default = furniture.size_mm[index],
        }, function(value) values[index] = value; next_dimension(index + 1) end)
      end
      next_dimension(1)
    elseif choice == "Rotation" then
      flow:select({ 0, 90, 180, 270 }, { prompt = "Rotation:" }, function(rotation)
        commit_ui(session, { type = "rotate_furniture", id = furniture.id, rotation_deg = rotation }, flow)
      end)
    elseif choice == "Template" then
      local templates = catalog.all()
      for _, template in ipairs(session:model().custom_templates) do templates[#templates + 1] = template end
      flow:select(templates, {
        prompt = "Template:", format_item = function(item) return item.name .. " (keeps explicit dimensions)" end,
      }, function(template)
        commit_ui(session, {
          type = "change_furniture_template", id = furniture.id,
          template_id = template.id, category = template.category,
        }, flow)
      end)
    else
      flow:input({ prompt = "Custom template name: ", default = furniture.name }, function(name)
        flow:input({ prompt = "Category: ", default = furniture.category }, function(category)
          local id, id_err = generate_id(session, "custom_template", name)
          if not id then flow:cancel("id failed"); notify_error(id_err); return end
          commit_ui(session, {
            type = "add_custom_template",
            template = model.new_custom_template({
              id = id, name = name, category = category, shape = "rectangle",
              default_size_mm = furniture.size_mm,
            }),
          }, flow)
        end)
      end)
    end
  end)
end

local function edit_door_flow(session, door, flow)
  flow:select({ "Width", "Offset", "Toggle hinge", "Toggle opening side", "Open angle" }, { prompt = "Edit door:" }, function(choice)
    if choice == "Toggle hinge" then
      commit_ui(session, { type = "toggle_door_hinge", id = door.id }, flow)
    elseif choice == "Toggle opening side" then
      commit_ui(session, { type = "toggle_door_swing", id = door.id }, flow)
    elseif choice == "Width" then
      require("roomplan.ui.prompts").measurement(flow, { prompt = "Door width: ", default = door.width_mm }, function(width)
        commit_ui(session, { type = "edit_door", id = door.id, patch = { width_mm = width }, exact = true }, flow)
      end)
    elseif choice == "Offset" then
      require("roomplan.ui.prompts").measurement(flow, {
        prompt = "Door offset: ", default = door.offset_mm, allow_zero = true,
      }, function(offset)
        commit_ui(session, { type = "edit_door", id = door.id, patch = { offset_mm = offset }, exact = true }, flow)
      end)
    else
      require("roomplan.ui.prompts").integer(flow, {
        prompt = "Open angle (1–180): ", default = door.open_angle_deg, min = 1, max = 180,
      }, function(angle)
        commit_ui(session, { type = "edit_door", id = door.id, patch = { open_angle_deg = angle }, exact = true }, flow)
      end)
    end
  end)
end

function M.edit_selected(session)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  if not resolved.selection then return notify_error(util.err("SELECTION_REQUIRED", "select an object to edit")) end
  if resolved.selection.kind == "plan" then return M.edit_plan(resolved) end
  local entity = find_entity(resolved, resolved.selection)
  if not entity then return notify_error(util.err("SELECTION_STALE", "selected object no longer exists")) end
  if structured_ui_enabled() then
    local forms = require("roomplan.ui.forms")
    local spec
    if resolved.selection.kind == "room" then spec = forms.room.edit(resolved, entity)
    elseif resolved.selection.kind == "furniture" then spec = forms.furniture.edit(resolved, entity)
    elseif resolved.selection.kind == "door" then spec = forms.door.edit(resolved, entity)
    elseif resolved.selection.kind == "template" then spec = forms.template.edit(resolved, entity) end
    if not spec then return notify_error(util.err("EDIT_UNSUPPORTED", "selected object cannot be edited here")) end
    return open_structured_form(resolved, spec)
  end
  if resolved.selection.kind == "template" then return M.edit_template(resolved, resolved.selection.id) end
  local flow, flow_err = require("roomplan.ui.flow").new(resolved, "edit-" .. resolved.selection.kind)
  if not flow then return notify_error(flow_err) end
  if resolved.selection.kind == "room" then edit_room_flow(resolved, entity, flow)
  elseif resolved.selection.kind == "furniture" then edit_furniture_flow(resolved, entity, flow)
  elseif resolved.selection.kind == "door" then edit_door_flow(resolved, entity, flow)
  else flow:cancel("unsupported"); return notify_error(util.err("EDIT_UNSUPPORTED", "selected object cannot be edited here")) end
  return flow
end

function M.edit_plan(session)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  if structured_ui_enabled() then
    return open_structured_form(resolved, require("roomplan.ui.forms").plan.edit(resolved))
  end
  local flow, flow_err = require("roomplan.ui.flow").new(resolved, "edit-plan")
  if not flow then return notify_error(flow_err) end
  flow:select({ "Name", "Notes", "Grid and movement setting", "Door/wall default" }, {
    prompt = "Edit plan:",
  }, function(choice)
    if choice == "Name" or choice == "Notes" then
      local field = choice:lower()
      flow:input({ prompt = choice .. ": ", default = resolved:model().metadata[field] }, function(value)
        commit_ui(resolved, { type = "edit_metadata", patch = { [field] = value } }, flow)
      end)
      return
    end
    local fields = choice == "Grid and movement setting" and {
      "grid_mm", "fine_step_mm", "normal_step_mm", "coarse_step_mm",
    } or { "default_door_width_mm", "default_wall_thickness_mm" }
    flow:select(fields, { prompt = "Setting:" }, function(field)
      require("roomplan.ui.prompts").measurement(flow, {
        prompt = field .. ": ", default = resolved:model().settings[field],
      }, function(value)
        commit_ui(resolved, { type = "edit_plan_settings", patch = { [field] = value } }, flow)
      end)
    end)
  end)
end

function M.edit_template(session, id)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  local template = model.find(resolved:model(), "template", id)
  if not template then return notify_error(util.err("NOT_FOUND", "custom template was not found")) end
  if structured_ui_enabled() then
    return open_structured_form(resolved, require("roomplan.ui.forms").template.edit(resolved, template))
  end
  local flow, flow_err = require("roomplan.ui.flow").new(resolved, "edit-template")
  if not flow then return notify_error(flow_err) end
  flow:select({ "Name", "Category", "Default dimensions" }, { prompt = "Edit custom template:" }, function(choice)
    if choice == "Name" or choice == "Category" then
      local field = choice:lower()
      flow:input({ prompt = choice .. ": ", default = template[field] }, function(value)
        commit_ui(resolved, { type = "edit_custom_template", id = id, patch = { [field] = value } }, flow)
      end)
      return
    end
    local values = {}
    local labels = { "Width", "Depth", "Height" }
    local function dimension(index)
      if index > 3 then
        commit_ui(resolved, { type = "edit_custom_template", id = id, patch = { default_size_mm = values } }, flow)
        return
      end
      require("roomplan.ui.prompts").measurement(flow, {
        prompt = labels[index] .. ": ", default = template.default_size_mm[index],
      }, function(value) values[index] = value; dimension(index + 1) end)
    end
    dimension(1)
  end)
end

function M.duplicate_selected(session)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  local selection = resolved.selection
  local entity = find_entity(resolved, selection)
  if not entity then return notify_error(util.err("SELECTION_REQUIRED", "select an object to duplicate")) end
  local id, id_err
  local action
  if selection.kind == "room" then
    id, id_err = generate_id(resolved, "room", entity.name .. " copy")
    action = { type = "duplicate_room", id = entity.id, new_id = id }
  elseif selection.kind == "furniture" then
    id, id_err = generate_id(resolved, "furniture", entity.name .. " copy")
    action = { type = "duplicate_furniture", id = entity.id, new_id = id }
  elseif selection.kind == "door" then
    id, id_err = generate_id(resolved, "door", entity.id .. " copy")
    if not id then return notify_error(id_err) end
    local flow, flow_err = require("roomplan.ui.flow").new(resolved, "duplicate-door")
    if not flow then return notify_error(flow_err) end
    require("roomplan.ui.prompts").measurement(flow, {
      prompt = "Copied door offset: ", default = entity.offset_mm + entity.width_mm, allow_zero = true,
    }, function(offset)
      require("roomplan.ui.prompts").measurement(flow, {
        prompt = "Copied door width: ", default = entity.width_mm,
      }, function(width)
        flow:select({ "start", "end" }, { prompt = "Copied door hinge:" }, function(hinge)
          commit_ui(resolved, {
            type = "duplicate_door_from_draft", id = entity.id, new_id = id,
            patch = { offset_mm = offset, width_mm = width, hinge = hinge },
          }, flow)
        end)
      end)
    end)
    return flow
  elseif selection.kind == "template" then
    id, id_err = generate_id(resolved, "custom_template", entity.name .. " copy")
    action = { type = "duplicate_custom_template", id = entity.id, new_id = id }
  else
    return notify_error(util.err("DUPLICATE_UNSUPPORTED", "selected object cannot be duplicated"))
  end
  if not id then return notify_error(id_err) end
  local result, action_err = M.dispatch(resolved, action)
  if not result then return notify_error(action_err) end
  return result
end

local function deletion_action(selection)
  if selection.kind == "room" then return { type = "delete_room_cascade", id = selection.id } end
  if selection.kind == "furniture" then return { type = "delete_furniture", id = selection.id } end
  if selection.kind == "door" then return { type = "delete_door", id = selection.id } end
  if selection.kind == "template" then return { type = "delete_custom_template", id = selection.id } end
end

function M.delete_selected(session)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  local selection = resolved.selection
  local entity = find_entity(resolved, selection)
  local action = selection and deletion_action(selection)
  if not entity or not action then return notify_error(util.err("SELECTION_REQUIRED", "select a deletable object")) end
  local function remove()
    local result, action_err = M.dispatch(resolved, action)
    if not result then return notify_error(action_err) end
    resolved.selection = nil
    M.refresh(resolved)
    return result
  end
  if not config.get().ui.confirm_delete then return remove() end
  local summary = entity.name or entity.id
  if selection.kind == "room" then
    local dependencies = require("roomplan.actions").room_dependencies(resolved:model(), entity.id)
    summary = string.format("%s and %d dependent object(s)", summary, #dependencies.all)
  end
  local flow, flow_err = require("roomplan.ui.prompts").confirm(
    resolved, "delete", "Delete " .. summary .. "?", { "Delete", "Cancel" },
    function(choice) if choice == "Delete" then remove() end end
  )
  if not flow then return notify_error(flow_err) end
  return flow
end

function M.add_menu(session)
  local resolved, err = resolve(session)
  if not resolved then return notify_error(err) end
  if #(resolved:model().rooms or {}) == 0 then
    return M.add_room(resolved)
  end
  return require("roomplan.ui.palette").open({
    session = resolved,
    title = "Add to plan",
    items = {
      { key = "r", label = "Room", description = "Create and place a rectangular room", callback = function() M.add_room(resolved) end },
      { key = "d", label = "Door", description = "Place a hinged door on a room wall", callback = function() M.add_door(resolved) end },
      { key = "f", label = "Furniture", description = "Place a catalogue or custom furniture footprint", callback = function() M.add_furniture(resolved) end },
    },
  })
end

local function active_menu(session)
  local actions = {
    { label = "Open/focus canvas", method = "focus_canvas" },
    { label = "Add room", method = "add_room" },
    { label = "Align rooms", method = "align_room" },
    { label = "Add door", method = "add_door" },
    { label = "Add furniture", method = "add_furniture" },
    { label = "Edit selected object", method = "edit_selected" },
    { label = "Duplicate selected object", method = "duplicate_selected" },
    { label = "Delete selected object", method = "delete_selected" },
    { label = "List objects", method = "objects" },
    { label = "Validate plan", method = "validate", argument = true },
    { label = "Fit plan to viewport", method = "fit" },
    { label = "Calibrate terminal aspect", method = "set_aspect" },
    { label = "Save", method = "save" },
    { label = "Reload", method = "reload" },
    { label = "Hide canvas", method = "hide" },
    { label = "Close session", method = "close" },
  }
  local items = {}
  for _, action in ipairs(actions) do
    local selected = action
    items[#items + 1] = {
      label = selected.label,
      callback = function() M[selected.method](session, selected.argument) end,
    }
  end
  return require("roomplan.ui.palette").open({
    session = session,
    title = "Plan actions · " .. session:status_text(),
    items = items,
  })
end

function M.menu(session)
  local resolved = is_session(session) and session or state.for_buffer()
  if resolved then return active_menu(resolved) end
  local sessions = state.list()
  if #sessions == 1 then return active_menu(sessions[1]) end
  if #sessions > 1 then
    local items = {}
    for _, candidate in ipairs(sessions) do
      local selected = candidate
      items[#items + 1] = {
        label = selected.source.path or selected.id,
        description = selected:status_text(),
        callback = function() active_menu(selected) end,
      }
    end
    return require("roomplan.ui.palette").open({ title = "Choose RoomPlan session", items = items })
  end
  return require("roomplan.ui.palette").open({
    title = "Start RoomPlan",
    items = {
      {
        key = "o", label = "Open current source", description = "Load an existing .roomplan.json or Norg plan block",
        callback = function() M.open(nil, { bufnr = 0, interactive = true }) end,
      },
      {
        key = "i", label = "Initialize current source", description = "Create an empty plan without overwriting other content",
        callback = function() M.init_source(nil, { bufnr = 0, interactive = true }) end,
      },
    },
  })
end

return M
