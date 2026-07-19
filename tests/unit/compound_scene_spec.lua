local json = require("roomplan.codec.json")
local door_geometry = require("roomplan.geometry.door")
local scene_builder = require("roomplan.scene.build")
local walls = require("roomplan.scene.walls")
local raster = require("roomplan.render.raster")
local viewport = require("roomplan.render.viewport")

local function part(id, x, y, width, depth)
  return {
    id = id,
    origin_mm = { x, y },
    size_mm = { width, depth },
  }
end

local function compound_room()
  return {
    id = "room-l",
    name = "L room",
    origin_mm = { 0, 0 },
    footprint = {
      kind = "rect_union",
      parts = {
        part("part-main", 0, 0, 1000, 1000),
        part("part-east", 1000, 0, 500, 500),
      },
    },
  }
end

local function fixed_view(left, top, scale)
  return viewport.new({
    world_left_mm = left,
    world_top_mm = top,
    mm_per_column = scale,
    mm_per_row = scale,
  })
end

local function count_kind(scene, kind)
  local result = 0
  for _, primitive in ipairs(scene.primitives) do
    if primitive.kind == kind then result = result + 1 end
  end
  return result
end

describe("compound scene extraction", function()
  it("renders a room union without internal wall seams or duplicate selection refs", function()
    local scene = scene_builder.build({
      rooms = { compound_room() },
      doors = {},
      furniture = {},
    })

    assert_equal(6, #scene.wall_data.segments)
    assert_equal(nil, (function()
      for _, segment in ipairs(scene.wall_data.segments) do
        if segment.orientation == "vertical" and segment.fixed == 1000
          and segment.start < 250 and segment.finish > 250
        then
          return segment
        end
      end
    end)())
    assert_equal(2, count_kind(scene, "room_interior"))
    assert_equal(1, #scene.objects)

    local output = raster.rasterize(scene, fixed_view(0, 1000, 250), {
      width = 7,
      height = 5,
      glyph_mode = "ascii",
    })
    assert_equal(0, #output.hit_map[2][6]) -- the L-shaped notch
    assert_equal("room-l", output.hit_map[4][6][1].id)
  end)

  it("keeps compound furniture parts under one logical object", function()
    local scene = scene_builder.build({
      rooms = { compound_room() },
      doors = {},
      furniture = {
        {
          id = "furniture-l",
          room_id = "room-l",
          name = "Sectional",
          position_mm = { 250, 250 },
          anchor2_mm = { 0, 0 },
          footprint = {
            kind = "rect_union",
            parts = {
              part("part-main", 0, 0, 400, 200),
              part("part-return", 0, 200, 200, 200),
            },
          },
          rotation_deg = 0,
        },
      },
    }, nil, {
      shape_edit = {
        kind = "furniture", entity_id = "furniture-l", selected_part_id = "part-return",
      },
    })

    assert_equal(2, count_kind(scene, "furniture_interior"))
    assert_equal(2, count_kind(scene, "furniture_outline"))
    assert_equal(2, #scene.objects)
    assert_equal("furniture-l", scene.objects[2].id)

    local first_ref
    local selected_parts = 0
    for _, primitive in ipairs(scene.primitives) do
      if primitive.kind == "furniture_interior" then
        first_ref = first_ref or primitive.ref
        assert_true(first_ref == primitive.ref)
      end
      if (primitive.kind == "furniture_interior" or primitive.kind == "furniture_outline")
        and primitive.part_id == "part-return" and primitive.role == "selected"
      then
        selected_parts = selected_parts + 1
      end
    end
    assert_equal(2, selected_parts)
    assert_true(scene.focus_points["furniture-l"] ~= nil)
  end)

  it("renders a form furniture preview without making it selectable", function()
    local preview = {
      id = "furniture-preview",
      room_id = "room-l",
      name = "Draft sofa",
      position_mm = { 1000, 500 },
      anchor2_mm = { 1000, 500 },
      footprint = {
        kind = "rect_union",
        parts = { part("part-main", 0, 0, 1000, 500) },
      },
      height_mm = 800,
      rotation_deg = 0,
    }
    local scene = scene_builder.build({
      rooms = { compound_room() },
      doors = {}, windows = {}, outlets = {}, furniture = {},
    }, nil, {
      detail_level = "high",
      form_preview = { kind = "furniture", entity = preview },
    })

    assert_equal("furniture", scene.preview.kind)
    assert_equal(1, #scene.objects, "the draft must not join selectable scene objects")
    assert_equal(nil, scene.focus_points["furniture-preview"])
    local preview_primitives = 0
    for _, primitive in ipairs(scene.primitives) do
      if primitive.role == "preview" then
        preview_primitives = preview_primitives + 1
        assert_equal(nil, primitive.ref)
      end
    end
    assert_true(preview_primitives >= 5, "interior, outline, label, and dimensions should share the preview role")
  end)

  it("renders project-template edits as an isolated local preview", function()
    local model = {
      settings = { grid_mm = 100 },
      rooms = { compound_room() },
      doors = {}, windows = {}, outlets = {}, furniture = {},
      custom_templates = {
        {
          id = "custom:sectional", name = "Sectional",
          default_footprint = {
            kind = "rect_union",
            parts = {
              part("part-main", 0, 0, 1000, 500),
              part("part-return", 0, 500, 500, 300),
            },
          },
        },
      },
    }
    local edit = {
      kind = "template", entity_id = "custom:sectional", selected_part_id = "part-return",
      footprint = model.custom_templates[1].default_footprint,
      snap_guides = {},
    }
    local scene = scene_builder.build(model, nil, {
      shape_edit = edit, show_grid = true, detail_level = "high",
    })
    assert_equal(0, #scene.wall_data.segments)
    assert_equal(1, #scene.objects)
    assert_equal("template", scene.objects[1].type)
    assert_equal("custom:sectional", scene.objects[1].id)
    assert_equal(2, count_kind(scene, "furniture_interior"))
    assert_equal(2, count_kind(scene, "furniture_outline"))
    assert_equal(0, scene.bounds.left)
    assert_equal(1000, scene.bounds.right)
    local selected = 0
    for _, primitive in ipairs(scene.primitives) do
      if primitive.part_id == "part-return" and primitive.role == "selected" then selected = selected + 1 end
    end
    assert_equal(2, selected)
  end)

  it("accepts only part-local door apertures that lie on the union exterior", function()
    local room = compound_room()
    local internal = {
      id = "door-internal",
      room_id = room.id,
      connects_to_room_id = json.null,
      part_id = "part-main",
      side = "east",
      offset_mm = 100,
      width_mm = 200,
    }
    local exterior = vim.tbl_extend("force", internal, {
      id = "door-exterior",
      offset_mm = 600,
    })

    local internal_aperture = assert(door_geometry.aperture(room, internal))
    assert_equal(true, internal_aperture.within_edge)
    assert_equal(false, internal_aperture.on_exterior)
    local exterior_aperture = assert(door_geometry.aperture(room, exterior))
    assert_equal(true, exterior_aperture.within_edge)
    assert_equal(true, exterior_aperture.on_exterior)

    local classified = walls.build({ room }, { internal, exterior }).apertures
    assert_equal(false, classified[1].owner_edge_valid)
    assert_equal("aperture is not on owner footprint exterior", classified[1].reason)
    assert_equal(true, classified[2].owner_edge_valid)
    assert_equal("part-main", classified[2].owner_part_id)
  end)

  it("cuts both contributors of a valid compound shared-boundary door", function()
    local owner = compound_room()
    local connected = {
      id = "room-connected",
      name = "Connected",
      origin_mm = { 1000, 500 },
      size_mm = { 500, 500 },
    }
    local door = {
      id = "door-connected",
      room_id = owner.id,
      connects_to_room_id = connected.id,
      part_id = "part-main",
      side = "east",
      offset_mm = 600,
      width_mm = 200,
    }

    local result = walls.build({ owner, connected }, { door })
    assert_equal(true, result.apertures[1].connection_valid)
    for _, segment in ipairs(result.segments) do
      local covers_aperture = segment.orientation == "vertical"
        and segment.fixed == 1000
        and segment.start < 700
        and segment.finish > 700
      assert_equal(false, covers_aperture)
    end
  end)
end)
