-- Public schema-v2 facade.

local document = require("roomplan.schema.v2.document")

return {
  VERSION = 2,
  KEY_ORDER = require("roomplan.schema.v2.key_order"),
  normalize = document.normalize,
}
