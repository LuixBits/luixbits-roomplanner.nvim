local document = require("roomplan.schema.v4.document")

return {
  VERSION = 4,
  KEY_ORDER = require("roomplan.schema.v4.key_order"),
  normalize = document.normalize,
}
