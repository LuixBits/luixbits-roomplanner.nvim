local geometry = {
  number = require("roomplan.geometry.number"),
  interval = require("roomplan.geometry.interval"),
  footprint = require("roomplan.geometry.footprint"),
  rect = require("roomplan.geometry.rect"),
  segment = require("roomplan.geometry.segment"),
  adjacency = require("roomplan.geometry.adjacency"),
  alignment = require("roomplan.geometry.alignment"),
  snapping = require("roomplan.geometry.snapping"),
  measurement = require("roomplan.geometry.measurement"),
  furniture_placement = require("roomplan.geometry.furniture_placement"),
  door = require("roomplan.geometry.door"),
  sector = require("roomplan.geometry.sector"),
}
return geometry
