local order = require("roomplan.codec.json").deep_copy(require("roomplan.schema.v3.key_order"))

order["$"] = {
  "format", "schema_version", "units", "metadata", "settings", "site",
  "rooms", "doors", "windows", "outlets", "furniture", "custom_templates", "extensions",
}
order["$.site"] = { "north_deg", "latitude_deg", "longitude_deg", "utc_offset_minutes" }
order["$.windows[]"] = {
  "id", "room_id", "connects_to_room_id", "part_id", "side", "offset_mm", "width_mm",
  "sill_height_mm", "head_height_mm",
}

order["$.outlets[]"] = {
  "id",
  "room_id",
  "placement",
  "part_id",
  "side",
  "offset_mm",
  "position_mm",
  "outlet_type",
  "slots",
}

return order
