-- Single authority for persisted outlet type values.

local M = {}

M.default = "power"
M.values = { "power", "usb", "ethernet", "coax", "phone", "other" }
M.labels = {
  power = "Power",
  usb = "USB",
  ethernet = "Ethernet",
  coax = "TV / coax",
  phone = "Phone",
  other = "Other",
}

local valid = {}
for _, value in ipairs(M.values) do valid[value] = true end

function M.valid(value)
  return valid[value] == true
end

function M.label(value)
  return M.labels[value]
end

return M
