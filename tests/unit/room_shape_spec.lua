local h = require("tests.harness")

local model = require("roomplan.model")
local room_shape = require("roomplan.room_shape")

local function fixture()
  local plan = h.truthy(model.new({ name = "Shape edit" }))
  plan.rooms[1] = model.new_room({
    id = "room-main", name = "Main", origin_mm = { 100, 200 }, size_mm = { 3000, 2000 },
  })
  return plan
end

describe("direct room resize drafts", function()
  it("selects, resizes, adds, and removes sections without mutating the model", function()
    local plan = fixture()
    plan.rooms[1].footprint.note = "keep me"
    local edit = h.truthy(room_shape.start(plan, "room-main", 7))
    h.eq("part-main", edit.selected_part_id)

    edit = h.truthy(room_shape.direction(edit, 1, 0, 100, { max_dimension_mm = 100000 }))
    h.eq(3100, edit.footprint.parts[1].size_mm[1])
    h.eq(3000, plan.rooms[1].footprint.parts[1].size_mm[1])

    edit = h.truthy(room_shape.add(edit, 1, 0))
    h.eq(2, #edit.footprint.parts)
    h.eq("part-1", edit.selected_part_id)
    local selected = h.truthy(room_shape.select_world(edit, plan.rooms[1].origin_mm, { 3300, 500 }))
    h.eq("part-1", selected.selected_part_id)

    edit = h.truthy(room_shape.remove(edit, plan))
    h.eq(1, #edit.footprint.parts)
    local action = room_shape.action(edit)
    h.eq("edit_room", action.type)
    h.eq("keep me", action.patch.footprint.note)
  end)

  it("edits placed-furniture sections without moving its explicit anchor", function()
    local plan = fixture()
    plan.furniture[1] = model.new_furniture({
      id = "furniture-sofa",
      room_id = "room-main",
      template_id = "builtin:custom-rectangle",
      name = "Sofa",
      category = "seating",
      position_mm = { 1500, 1000 },
      anchor2_mm = { 1000, 500 },
      footprint = model.rectangle_footprint({ 1000, 500 }),
      height_mm = 800,
      rotation_deg = 90,
    })

    local edit = h.truthy(room_shape.start(plan, "furniture-sofa", 3, "furniture"))
    h.eq("furniture", edit.kind)
    h.eq({ 1000, 500 }, edit.anchor2_mm)
    h.eq({ 0, -1 }, { room_shape.local_delta(edit, 1, 0) })

    edit = h.truthy(room_shape.direction(edit, 0, -1, 100, { max_dimension_mm = 100000 }))
    h.eq("east", room_shape.edge_summary(edit))
    h.eq({ 0, -100 }, edit.footprint.parts[1].origin_mm)
    h.eq({ 1000, 600 }, edit.footprint.parts[1].size_mm)
    h.eq({ 0, 0 }, plan.furniture[1].footprint.parts[1].origin_mm)

    local preview = h.truthy(room_shape.preview_model(plan, edit))
    h.eq({ 0, -100 }, preview.furniture[1].footprint.parts[1].origin_mm)
    h.eq({ 1000, 500 }, preview.furniture[1].anchor2_mm)
    local action = room_shape.action(edit)
    h.eq("edit_furniture", action.type)
    h.eq("furniture-sofa", action.id)

    local west = h.truthy(room_shape.start(plan, "furniture-sofa", 3, "furniture"))
    west = h.truthy(room_shape.direction(west, -1, 0, 100, { max_dimension_mm = 100000 }))
    west = h.truthy(room_shape.direction(west, 1, 0, 600, { max_dimension_mm = 100000 }))
    local outside, anchor_err = room_shape.direction(west, 1, 0, 10, { max_dimension_mm = 100000 })
    h.eq(nil, outside)
    h.eq("FURNITURE_SHAPE_ANCHOR", anchor_err.code)
  end)

  it("edits project templates in local coordinates without mutating placed items", function()
    local plan = fixture()
    plan.custom_templates[1] = model.new_custom_template({
      id = "custom:sectional",
      name = "Sectional",
      category = "seating",
      default_anchor2_mm = { 1000, 500 },
      default_footprint = model.rectangle_footprint({ 1000, 500 }),
      default_height_mm = 800,
    })
    plan.furniture[1] = model.new_furniture({
      id = "furniture-section",
      room_id = "room-main",
      template_id = "custom:sectional",
      name = "Placed sectional",
      category = "seating",
      position_mm = { 1500, 1000 },
      anchor2_mm = { 1000, 500 },
      footprint = model.rectangle_footprint({ 1000, 500 }),
      height_mm = 800,
    })

    local edit = h.truthy(room_shape.start(plan, "custom:sectional", 9, "template"))
    h.eq("template", edit.kind)
    h.eq({ 1000, 500 }, edit.anchor2_mm)
    edit = h.truthy(room_shape.direction(edit, 1, 0, 100, { max_dimension_mm = 100000 }))
    h.eq(1100, edit.footprint.parts[1].size_mm[1])
    h.eq(1000, plan.custom_templates[1].default_footprint.parts[1].size_mm[1])
    h.eq(1000, plan.furniture[1].footprint.parts[1].size_mm[1])

    local preview = h.truthy(room_shape.preview_model(plan, edit))
    h.eq(1100, preview.custom_templates[1].default_footprint.parts[1].size_mm[1])
    h.eq(1000, preview.furniture[1].footprint.parts[1].size_mm[1])
    local action = room_shape.action(edit)
    h.eq("edit_custom_template", action.type)
    h.eq("custom:sectional", action.id)

    local furniture_edit = h.truthy(room_shape.start(plan, "furniture-section", 9, "furniture"))
    furniture_edit = h.truthy(room_shape.direction(
      furniture_edit, 1, 0, 100, { max_dimension_mm = 100000 }
    ))
    local combined = room_shape.action(furniture_edit, "template")
    h.eq("edit_furniture_template_shape", combined.type)
    h.eq("custom:sectional", combined.template_id)
    h.eq(nil, combined.anchor2_mm)
  end)

  it("snaps quarter-turned furniture edges in world space", function()
    local plan = fixture()
    plan.rooms[2] = model.new_room({
      id = "room-target", name = "Target", origin_mm = { 1375, 0 }, size_mm = { 1000, 2000 },
    })
    plan.furniture[1] = model.new_furniture({
      id = "furniture-rotated", room_id = "room-main", template_id = "builtin:custom-rectangle",
      name = "Rotated", category = "custom", position_mm = { 1000, 1000 },
      anchor2_mm = { 1000, 500 }, footprint = model.rectangle_footprint({ 1000, 500 }),
      height_mm = 500, rotation_deg = 90,
    })
    local geometry = require("roomplan.geometry.footprint")
    local edit = h.truthy(room_shape.start(plan, "furniture-rotated", 1, "furniture"))
    edit = h.truthy(room_shape.direction(edit, 0, -1, 100, { max_dimension_mm = 100000 }, {
      model = plan,
      options = {
        tolerance_mm = { x = 100, y = 100 },
        mm_per_screen_unit = { x = 100, y = 100 },
        priority = { "room_edge", "furniture_edge", "grid" },
        grid_mm = 100,
      },
      world_shape = function(candidate)
        local preview = h.truthy(room_shape.preview_model(plan, candidate))
        return geometry.from_furniture(preview.rooms[1], preview.furniture[1])
      end,
    }))
    h.eq({ 0, -25 }, edit.footprint.parts[1].origin_mm)
    h.eq({ 1000, 525 }, edit.footprint.parts[1].size_mm)
    h.eq("east", room_shape.edge_summary(edit))
    h.eq("X → Target west wall", room_shape.snap_summary(edit))
  end)

  it("uses the first direction key to choose each resize edge", function()
    local plan = fixture()
    local edit = h.truthy(room_shape.start(plan, "room-main", 1))

    edit = h.truthy(room_shape.direction(edit, -1, 0, 100, { max_dimension_mm = 100000 }))
    h.eq("west", room_shape.edge_summary(edit))
    h.eq({ -100, 0 }, edit.footprint.parts[1].origin_mm)
    h.eq({ 3100, 2000 }, edit.footprint.parts[1].size_mm)

    edit = h.truthy(room_shape.direction(edit, 1, 0, 100, { max_dimension_mm = 100000 }))
    h.eq("west", room_shape.edge_summary(edit))
    h.eq({ 0, 0 }, edit.footprint.parts[1].origin_mm)
    h.eq({ 3000, 2000 }, edit.footprint.parts[1].size_mm)

    edit = h.truthy(room_shape.direction(edit, 0, -1, 100, { max_dimension_mm = 100000 }))
    h.eq("west/south", room_shape.edge_summary(edit))
    h.eq({ 0, -100 }, edit.footprint.parts[1].origin_mm)
    h.eq({ 3000, 2100 }, edit.footprint.parts[1].size_mm)
  end)

  it("protects referenced sections and rejects disconnected resizes", function()
    local plan = fixture()
    local edit = h.truthy(room_shape.start(plan, "room-main", 1))
    edit = h.truthy(room_shape.add(edit, 1, 0))
    edit = h.truthy(room_shape.cycle(edit, -1))
    plan.doors[1] = model.new_door({
      id = "door-main", room_id = "room-main", part_id = "part-main", side = "north",
      offset_mm = 500, width_mm = 900, hinge = "start", opens_into = "owner",
    })
    local removed, remove_err = room_shape.remove(edit, plan)
    h.eq(nil, removed)
    h.eq("ROOM_SHAPE_PART_IN_USE", remove_err.code)

    edit = h.truthy(room_shape.direction(edit, 1, 0, 100, { max_dimension_mm = 100000 }))
    h.eq("east", room_shape.edge_summary(edit))
    local resized, resize_err = room_shape.direction(edit, -1, 0, 100, { max_dimension_mm = 100000 })
    h.eq(nil, resized)
    h.truthy(resize_err.message)
  end)

  it("snaps resize previews to another room and describes the overlap", function()
    local plan = fixture()
    plan.rooms[2] = model.new_room({
      id = "room-east", name = "Kitchen", origin_mm = { 3250, 200 }, size_mm = { 2000, 2000 },
    })
    local context = {
      model = plan,
      origin_mm = plan.rooms[1].origin_mm,
      options = {
        tolerance_mm = { x = 100, y = 100 },
        mm_per_screen_unit = { x = 100, y = 100 },
        priority = { "room_edge", "grid" },
        grid_mm = 100,
      },
    }

    local resized = h.truthy(room_shape.direction(
      h.truthy(room_shape.start(plan, "room-main", 1)), 1, 0, 100,
      { max_dimension_mm = 100000 }, context
    ))
    h.eq(3150, resized.footprint.parts[1].size_mm[1])
    h.eq(1, #resized.snap_guides)
    h.eq("x", resized.snap_guides[1].axis)
    h.eq(3250, resized.snap_guides[1].value_mm)
    h.eq(200, resized.snap_guides[1].overlap_start_mm)
    h.eq(2200, resized.snap_guides[1].overlap_finish_mm)
    h.eq("X → Kitchen west wall", room_shape.snap_summary(resized))

    local released = h.truthy(room_shape.direction(
      resized, -1, 0, 10, { max_dimension_mm = 100000 }, context
    ))
    h.eq(3140, released.footprint.parts[1].size_mm[1])
    h.eq(0, #released.snap_guides)
    released = h.truthy(room_shape.direction(
      released, -1, 0, 10, { max_dimension_mm = 100000 }, context
    ))
    h.eq(3130, released.footprint.parts[1].size_mm[1])
    h.eq(0, #released.snap_guides)

    local preview = h.truthy(room_shape.preview_model(plan, resized))
    local scene = require("roomplan.scene.build").build(preview, nil, {
      shape_edit = resized,
      detail_level = "none",
    })
    local guide, overlap
    for _, primitive in ipairs(scene.primitives) do
      if primitive.kind == "snap_guide" then guide = primitive end
      if primitive.kind == "snap_overlap" then overlap = primitive end
    end
    h.eq("snap", h.truthy(guide).role)
    h.eq("Kitchen west wall", guide.target_label)
    h.eq("snap_overlap", h.truthy(overlap).role)
    h.eq(200, overlap.y1)
    h.eq(2200, overlap.y2)
  end)

  it("draws a visible support tail for north and south snaps", function()
    local plan = fixture()
    plan.rooms[2] = model.new_room({
      id = "room-north", name = "Bedroom", origin_mm = { 100, 2350 }, size_mm = { 3000, 2000 },
    })
    local resized = h.truthy(room_shape.direction(
      h.truthy(room_shape.start(plan, "room-main", 1)), 0, 1, 100,
      { max_dimension_mm = 100000 }, {
        model = plan,
        origin_mm = plan.rooms[1].origin_mm,
        options = {
          tolerance_mm = { x = 100, y = 100 },
          mm_per_screen_unit = { x = 100, y = 100 },
          priority = { "room_edge", "grid" },
          grid_mm = 100,
        },
      }
    ))
    h.eq("Y → Bedroom south wall", room_shape.snap_summary(resized))
    local preview = h.truthy(room_shape.preview_model(plan, resized))
    local scene = require("roomplan.scene.build").build(preview, nil, {
      shape_edit = resized,
      detail_level = "none",
    })
    local guide, overlap
    for _, primitive in ipairs(scene.primitives) do
      if primitive.kind == "snap_guide" then guide = primitive end
      if primitive.kind == "snap_overlap" then overlap = primitive end
    end
    guide, overlap = h.truthy(guide), h.truthy(overlap)
    h.truthy(guide.x1 < scene.bounds.left)
    h.truthy(guide.x2 > scene.bounds.right)
    h.eq(2350, guide.y1)
    h.eq(100, overlap.x1)
    h.eq(3100, overlap.x2)
  end)
end)
