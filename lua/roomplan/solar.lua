-- Dependency-free approximate solar position for RoomPlan's 2D sun study.
-- The equations follow NOAA's published fractional-year approximation.

local json = require("roomplan.codec.json")

local M = {}

local function clamp(value, minimum, maximum) return math.max(minimum, math.min(maximum, value)) end

local function leap(year) return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0) end

local MONTH_DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

function M.parse_date(value)
  if type(value) == "table" then
    value = string.format("%04d-%02d-%02d", value.year or 0, value.month or 0, value.day or 0)
  end
  local year, month, day = tostring(value or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  year, month, day = tonumber(year), tonumber(month), tonumber(day)
  if not year or year < 1 or year > 9999 or month < 1 or month > 12 then
    return nil, "use a valid date in YYYY-MM-DD form"
  end
  local maximum = MONTH_DAYS[month] + (month == 2 and leap(year) and 1 or 0)
  if day < 1 or day > maximum then return nil, "day is outside that month" end
  local ordinal = day
  for index = 1, month - 1 do
    ordinal = ordinal + MONTH_DAYS[index]
  end
  if leap(year) and month > 2 then ordinal = ordinal + 1 end
  return { year = year, month = month, day = day, ordinal = ordinal, days_in_year = leap(year) and 366 or 365 }
end

function M.parse_time(value)
  if type(value) == "number" and value >= 0 and value < 24 * 60 then return math.floor(value) end
  local hour, minute = tostring(value or ""):match("^(%d%d?):(%d%d)$")
  hour, minute = tonumber(hour), tonumber(minute)
  if not hour or hour < 0 or hour > 23 or minute < 0 or minute > 59 then
    return nil, "use a valid 24-hour time in HH:MM form"
  end
  return hour * 60 + minute
end

function M.format_time(minutes)
  minutes = math.floor(tonumber(minutes) or 0) % (24 * 60)
  return string.format("%02d:%02d", math.floor(minutes / 60), minutes % 60)
end

---Move a calendar date by an exact number of months while retaining its day
---where possible. End-of-month dates clamp instead of spilling into another
---month, so seasonal comparison remains predictable.
function M.shift_months(value, delta)
  local date, reason = M.parse_date(value)
  if not date then return nil, reason end
  delta = tonumber(delta)
  if not delta or delta ~= math.floor(delta) then return nil, "month step must be a whole number" end
  local absolute = (date.year - 1) * 12 + date.month - 1 + delta
  if absolute < 0 or absolute >= 9999 * 12 then return nil, "date is outside the supported year range" end
  local year = math.floor(absolute / 12) + 1
  local month = absolute % 12 + 1
  local maximum = MONTH_DAYS[month] + (month == 2 and leap(year) and 1 or 0)
  return string.format("%04d-%02d-%02d", year, month, math.min(date.day, maximum))
end

function M.parse_utc_offset(value)
  if type(value) == "number" and value == math.floor(value) and math.abs(value) <= 14 * 60 then return value end
  local sign, hours, minutes = tostring(value or ""):match("^([+-])(%d%d?):(%d%d)$")
  hours, minutes = tonumber(hours), tonumber(minutes)
  if not sign or hours > 14 or minutes > 59 or (hours == 14 and minutes ~= 0) then
    return nil, "use an offset such as +02:00 or -05:30"
  end
  local result = hours * 60 + minutes
  return sign == "-" and -result or result
end

function M.format_utc_offset(minutes)
  minutes = math.floor(tonumber(minutes) or 0)
  local sign = minutes < 0 and "-" or "+"
  minutes = math.abs(minutes)
  return string.format("%s%02d:%02d", sign, math.floor(minutes / 60), minutes % 60)
end

function M.number(value) return json.number_value(value) end

function M.number_text(value, precision)
  local number = M.number(value)
  if number == nil then return "" end
  local formatted = string.format("%." .. tostring(precision or 6) .. "f", number)
  formatted = formatted:gsub("0+$", ""):gsub("%.$", "")
  return formatted
end

function M.persisted_number(value)
  local persisted, reason = json.decimal_from_string(tostring(value or ""))
  if not persisted then return nil, reason end
  return persisted
end

local function terms(date, minutes)
  local fractional_hour = minutes / 60
  local gamma = 2 * math.pi / date.days_in_year * (date.ordinal - 1 + (fractional_hour - 12) / 24)
  local equation = 229.18
    * (
      0.000075
      + 0.001868 * math.cos(gamma)
      - 0.032077 * math.sin(gamma)
      - 0.014615 * math.cos(2 * gamma)
      - 0.040849 * math.sin(2 * gamma)
    )
  local declination = 0.006918
    - 0.399912 * math.cos(gamma)
    + 0.070257 * math.sin(gamma)
    - 0.006758 * math.cos(2 * gamma)
    + 0.000907 * math.sin(2 * gamma)
    - 0.002697 * math.cos(3 * gamma)
    + 0.00148 * math.sin(3 * gamma)
  return equation, declination
end

function M.position(site, date_value, time_value)
  local date, date_error = M.parse_date(date_value)
  if not date then return nil, date_error end
  local minutes, time_error = M.parse_time(time_value)
  if minutes == nil then return nil, time_error end
  local latitude = site and M.number(site.latitude_deg)
  local longitude = site and M.number(site.longitude_deg)
  local north = site and M.number(site.north_deg)
  local offset = site and M.number(site.utc_offset_minutes)
  if not latitude or not longitude or not north or not offset then return nil, "site information is incomplete" end

  local equation, declination = terms(date, minutes)
  local true_solar = (minutes + equation + 4 * longitude - offset) % 1440
  local hour_angle = true_solar / 4 - 180
  if hour_angle < -180 then hour_angle = hour_angle + 360 end
  local latitude_rad = math.rad(latitude)
  local hour_rad = math.rad(hour_angle)
  local cosine_zenith = clamp(
    math.sin(latitude_rad) * math.sin(declination) + math.cos(latitude_rad) * math.cos(declination) * math.cos(hour_rad),
    -1,
    1
  )
  local zenith = math.deg(math.acos(cosine_zenith))
  local elevation = 90 - zenith
  local azimuth = 0
  local sine_zenith = math.sin(math.rad(zenith))
  if math.abs(sine_zenith) > 1e-12 and math.abs(math.cos(latitude_rad)) > 1e-12 then
    local argument = clamp(
      (math.sin(latitude_rad) * cosine_zenith - math.sin(declination)) / (math.cos(latitude_rad) * sine_zenith),
      -1,
      1
    )
    local angle = math.deg(math.acos(argument))
    azimuth = hour_angle > 0 and (angle + 180) % 360 or (540 - angle) % 360
  end

  local noon_equation, noon_declination = terms(date, 12 * 60)
  local solar_noon = 720 - 4 * longitude - noon_equation + offset
  local sunrise, sunset, daylight_state
  local cosine_hour = math.cos(math.rad(90.833)) / (math.cos(latitude_rad) * math.cos(noon_declination))
    - math.tan(latitude_rad) * math.tan(noon_declination)
  if cosine_hour > 1 then
    daylight_state = "polar_night"
  elseif cosine_hour < -1 then
    daylight_state = "polar_day"
    sunrise, sunset = 0, 24 * 60 - 1
  else
    local hour_limit = math.deg(math.acos(clamp(cosine_hour, -1, 1))) * 4
    sunrise, sunset = solar_noon - hour_limit, solar_noon + hour_limit
    daylight_state = "normal"
  end

  local plan_bearing = (north + azimuth) % 360
  local bearing_rad = math.rad(plan_bearing)
  return {
    date = date,
    minutes = minutes,
    azimuth_deg = azimuth,
    elevation_deg = elevation,
    solar_noon_minutes = solar_noon,
    sunrise_minutes = sunrise,
    sunset_minutes = sunset,
    daylight_state = daylight_state,
    sun_dx = math.sin(bearing_rad),
    sun_dy = math.cos(bearing_rad),
    incoming_dx = -math.sin(bearing_rad),
    incoming_dy = -math.cos(bearing_rad),
  }
end

return M
