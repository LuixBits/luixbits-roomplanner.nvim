local json = require("roomplan.codec.json")
local solar = require("roomplan.solar")

local M = {}

local function decimal(value, minimum, maximum, label)
  local persisted, reason = solar.persisted_number(value)
  if not persisted then return nil, reason end
  local number = solar.number(persisted)
  if number < minimum or number > maximum then
    return nil, string.format("%s must be between %g and %g", label, minimum, maximum)
  end
  return persisted, number
end

local function values(draft)
  local north, north_number = decimal(draft.north_deg, 0, 360, "north angle")
  if not north then return nil, north_number, "north_deg" end
  if north_number >= 360 then return nil, "north angle must be less than 360", "north_deg" end
  local latitude, latitude_error = decimal(draft.latitude_deg, -90, 90, "latitude")
  if not latitude then return nil, latitude_error, "latitude_deg" end
  local longitude, longitude_error = decimal(draft.longitude_deg, -180, 180, "longitude")
  if not longitude then return nil, longitude_error, "longitude_deg" end
  local utc_offset, offset_error = solar.parse_utc_offset(draft.utc_offset)
  if utc_offset == nil then return nil, offset_error, "utc_offset" end
  return json.object({
    north_deg = north,
    latitude_deg = latitude,
    longitude_deg = longitude,
    utc_offset_minutes = utc_offset,
  })
end

function M.new(session)
  local site = session:model().site or {}
  local spec = {
    id = "sun-site",
    title = site.north_deg == nil and "Set up sunlight" or "Edit sunlight location",
    mode = "SUN SITE",
    description = "Angles are exact decimal degrees. North is measured clockwise from plan top.",
    apply_label = "Save sunlight location",
    context = { session = session },
    initial = {
      north_deg = solar.number_text(site.north_deg or 0),
      latitude_deg = solar.number_text(site.latitude_deg or 0),
      longitude_deg = solar.number_text(site.longitude_deg or 0),
      utc_offset = solar.format_utc_offset(solar.number(site.utc_offset_minutes) or 0),
    },
    fields = {
      { key = "north_deg", label = "North angle from plan top", type = "text", required = true, trim = true },
      { key = "latitude_deg", label = "Latitude", type = "text", required = true, trim = true },
      { key = "longitude_deg", label = "Longitude", type = "text", required = true, trim = true },
      { key = "utc_offset", label = "UTC offset", type = "text", required = true, trim = true },
      {
        key = "note",
        label = "Calculation",
        type = "readonly",
        value = "Offline clear-sky geometry; no network, weather, or daylight-saving lookup.",
      },
    },
  }
  function spec.validate(draft)
    local _, reason, field = values(draft)
    return field and { [field] = reason } or {}
  end
  function spec.build(draft)
    local site_value, reason, field = values(draft)
    if not site_value then return nil, { code = "SITE_INVALID", field = field, message = reason } end
    return { type = "edit_site", site = site_value }
  end
  return spec
end

return M
