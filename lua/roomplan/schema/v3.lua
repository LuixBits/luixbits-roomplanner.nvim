-- Public schema-v3 facade.

local document = require("roomplan.schema.v3.document")

return {
  VERSION = 3,
  KEY_ORDER = require("roomplan.schema.v3.key_order"),
  normalize = document.normalize,
}
