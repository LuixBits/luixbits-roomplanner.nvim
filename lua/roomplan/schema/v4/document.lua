local base_document = require("roomplan.schema.v3.document")
local common = require("roomplan.schema.common")
local json = require("roomplan.codec.json")
local entities = require("roomplan.schema.v4.entities")

local M = {}

local function normalize_root(context, document)
  if document.site == nil then return end
  local site = common.object(context, document.site, "$.site")
  if not site then
    document.site = nil
    return
  end
  site.north_deg =
    common.number(context, common.required(context, site, "north_deg", "$.site"), "$.site.north_deg", 0, 360)
  if site.north_deg and json.number_value(site.north_deg) >= 360 then
    common.add_error(context, "SCHEMA_NUMBER_MAX", "$.site.north_deg", "must be less than 360", site.north_deg)
  end
  site.latitude_deg =
    common.number(context, common.required(context, site, "latitude_deg", "$.site"), "$.site.latitude_deg", -90, 90)
  site.longitude_deg =
    common.number(context, common.required(context, site, "longitude_deg", "$.site"), "$.site.longitude_deg", -180, 180)
  site.utc_offset_minutes = common.integer(
    context,
    common.required(context, site, "utc_offset_minutes", "$.site"),
    "$.site.utc_offset_minutes",
    -14 * 60,
    14 * 60,
    14 * 60
  )
  document.site = site
end

function M.normalize(document) return base_document.normalize_with(document, 4, entities, normalize_root) end

return M
