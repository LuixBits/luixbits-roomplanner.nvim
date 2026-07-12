local geometry = {
  number = require("roomplan.geometry.number"),
  interval = require("roomplan.geometry.interval"),
  rect = require("roomplan.geometry.rect"),
  segment = require("roomplan.geometry.segment"),
  adjacency = require("roomplan.geometry.adjacency"),
  alignment = require("roomplan.geometry.alignment"),
  snapping = require("roomplan.geometry.snapping"),
  door = require("roomplan.geometry.door"),
  sector = require("roomplan.geometry.sector"),
}
geometry.rectangle = geometry.rect
geometry.snap = geometry.snapping
return geometry
