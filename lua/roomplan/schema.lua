-- Schema facade and version dispatcher for roomplan.nvim.
--
-- Version modules own persisted document shapes. This facade keeps current-
-- version validation/writing separate from the sequential load path so encode
-- can never migrate or silently rewrite an older model.

local json = require("roomplan.codec.json")
local common = require("roomplan.schema.common")
local v1 = require("roomplan.schema.v1")
local v2 = require("roomplan.schema.v2")
local v3 = require("roomplan.schema.v3")
local v4 = require("roomplan.schema.v4")
local v1_to_v2 = require("roomplan.schema.migrations.v1_to_v2")
local v2_to_v3 = require("roomplan.schema.migrations.v2_to_v3")
local v3_to_v4 = require("roomplan.schema.migrations.v3_to_v4")

local M = {}

M.FORMAT = common.FORMAT
M.CURRENT_VERSION = 4
M.LATEST_VERSION = 4
M.defaults = common.defaults
M.limits = common.limits
M.migrations = {
  [1] = v1_to_v2.migrate,
  [2] = v2_to_v3.migrate,
  [3] = v3_to_v4.migrate,
}

local normalizers = {
  [v1.VERSION] = v1,
  [v2.VERSION] = v2,
  [v3.VERSION] = v3,
  [v4.VERSION] = v4,
}

M.validate_text = common.validate_text

-- Normalize only the current writable schema. Migration belongs exclusively
-- to load/decode; actions and encode must reject non-current models.
function M.normalize(document)
  local version = normalizers[M.CURRENT_VERSION]
  if not version then
    return nil,
      common.diagnostic(
        "SCHEMA_NORMALIZER_MISSING",
        "$.schema_version",
        "no normalizer is registered for schema version " .. M.CURRENT_VERSION,
        M.CURRENT_VERSION
      )
  end
  return version.normalize(document)
end

-- Normalize an already-versioned runtime model through its own registered
-- schema. This is used by version-aware consumers during schema transitions;
-- it never migrates and therefore cannot rewrite an older representation.
function M.normalize_versioned(document)
  local version, version_error = common.document_version(document, M.LATEST_VERSION)
  if not version then return nil, version_error end
  local normalizer = normalizers[version]
  if not normalizer then
    return nil,
      common.diagnostic(
        "SCHEMA_NORMALIZER_MISSING",
        "$.schema_version",
        "no normalizer is registered for schema version " .. version,
        version
      )
  end
  return normalizer.normalize(document)
end

local function append_all(target, source)
  for _, value in ipairs(source or {}) do
    target[#target + 1] = value
  end
end

-- Normalize the source version first, then run and validate every sequential
-- migration. Explicit targets support migration tests and recovery tooling;
-- ordinary load/decode always target CURRENT_VERSION.
function M.migrate(document, target_version)
  local explicit_target = target_version ~= nil
  target_version = target_version or M.CURRENT_VERSION
  if
    type(target_version) ~= "number"
    or target_version ~= math.floor(target_version)
    or target_version < 1
    or target_version > M.LATEST_VERSION
  then
    return nil,
      common.diagnostic(
        "SCHEMA_TARGET_VERSION",
        "$.schema_version",
        "migration target must be a registered schema version",
        target_version
      )
  end

  local version_ceiling = explicit_target and M.LATEST_VERSION or target_version
  local version, err = common.document_version(document, version_ceiling)
  if not version then return nil, err end
  if version > target_version then
    local code = explicit_target and "SCHEMA_DOWNGRADE_UNSUPPORTED" or "SCHEMA_FUTURE_VERSION"
    local message = explicit_target
        and ("schema version " .. version .. " cannot be downgraded to version " .. target_version)
      or ("schema version " .. version .. " is newer than supported version " .. target_version)
    return nil, common.diagnostic(code, "$.schema_version", message, version)
  end

  local source_normalizer = normalizers[version]
  if not source_normalizer then
    return nil,
      common.diagnostic(
        "SCHEMA_NORMALIZER_MISSING",
        "$.schema_version",
        "no normalizer is registered for schema version " .. version,
        version
      )
  end
  local copy, source_info = source_normalizer.normalize(document)
  if not copy then return nil, source_info end

  local notes = {}
  local added_fields = {}
  append_all(added_fields, source_info.added_fields)
  local normalized_any = source_info.normalized == true
  local migrated_any = false
  while version < target_version do
    local migration = M.migrations[version]
    if type(migration) ~= "function" then
      return nil,
        common.diagnostic(
          "SCHEMA_MIGRATION_MISSING",
          "$.schema_version",
          "no migration is registered from schema version " .. version,
          version
        )
    end
    local migrated, migration_notes = migration(copy)
    if not migrated then
      return nil,
        migration_notes or common.diagnostic(
          "SCHEMA_MIGRATION_FAILED",
          "$",
          "migration from schema version " .. version .. " failed"
        )
    end
    append_all(notes, migration_notes)

    local next_version = version + 1
    local target_normalizer = normalizers[next_version]
    if not target_normalizer then
      return nil,
        common.diagnostic(
          "SCHEMA_NORMALIZER_MISSING",
          "$.schema_version",
          "no normalizer is registered for schema version " .. next_version,
          next_version
        )
    end
    local normalized, normalization_info = target_normalizer.normalize(migrated)
    if not normalized then return nil, normalization_info end
    copy = normalized
    append_all(added_fields, normalization_info.added_fields)
    normalized_any = true
    migrated_any = true
    version = next_version
  end
  return copy,
    notes,
    migrated_any,
    {
      normalized = normalized_any,
      added_fields = added_fields,
      migration_notes = notes,
    }
end

function M.load(document)
  local migrated, notes_or_error, migrated_any, migration_info = M.migrate(document)
  if not migrated then return nil, notes_or_error end
  migration_info.migration_notes = notes_or_error
  migration_info.migrated = migrated_any == true
  if migration_info.migrated then migration_info.normalized = true end
  return migrated, migration_info
end

function M.decode(text_value, options)
  local document, err = json.decode(text_value, options)
  if document == nil then return nil, err end
  return M.load(document)
end

function M.validate(model)
  local normalized, info_or_error = M.normalize(model)
  if not normalized then return false, info_or_error end
  return true, info_or_error, normalized
end

function M.validate_versioned(model)
  local normalized, info_or_error = M.normalize_versioned(model)
  if not normalized then return false, info_or_error end
  return true, info_or_error, normalized
end

function M.encode(model, options)
  local valid, info_or_error, normalized = M.validate(model)
  if not valid then return nil, info_or_error end
  local encode_options = {}
  for key, value in pairs(options or {}) do
    encode_options[key] = value
  end
  if encode_options.key_order == nil then encode_options.key_order = v4.KEY_ORDER end
  local encoded, encode_error = json.encode(normalized, encode_options)
  if not encoded then return nil, encode_error end
  return encoded, info_or_error
end

return M
