local order = require("roomplan.codec.json").deep_copy(require("roomplan.schema.v3.key_order"))

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
