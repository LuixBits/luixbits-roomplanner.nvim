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
