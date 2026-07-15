local catalog = require("roomplan.catalog")
local forms = require("roomplan.ui.forms")
local form_state = require("roomplan.ui.form.state")
local model = require("roomplan.model")
local presenter = require("roomplan.ui.presenter")

local function rectangle(id, x, y, width, depth)
  return { id = id, origin_mm = { x, y }, size_mm = { width, depth } }
end

local function compound(parts)
  return { kind = "rect_union", parts = parts }
end

local function fixture()
  local plan = {
    format = "roomplan.nvim",
    schema_version = 2,
    units = "mm",
    metadata = { name = "Compound form test", notes = "" },
    settings = { grid_mm = 100, fine_step_mm = 10, default_door_width_mm = 900 },
    rooms = {
      {
        id = "room-living", name = "Living", origin_mm = { 0, 0 },
        footprint = compound({
          rectangle("part-main", 0, 0, 4000, 2000),
          rectangle("part-wing", 0, 2000, 1500, 1500),
        }),
      },
      {
        id = "room-office", name = "Office", origin_mm = { 4000, 0 },
        footprint = compound({ rectangle("part-main", 0, 0, 3000, 2000) }),
      },
    },
    doors = {
      {
        id = "door-living-east", kind = "hinged", room_id = "room-living",
        connects_to_room_id = "room-office", part_id = "part-main", side = "east",
        offset_mm = 500, width_mm = 900, hinge = "start", opens_into = "connected",
        open_angle_deg = 90,
      },
    },
    furniture = {
      {
        id = "furniture-sectional", room_id = "room-living", template_id = "custom:sectional",
        name = "Sectional", category = "seating", position_mm = { 1000, 1000 },
        anchor2_mm = { 1000, 500 },
        footprint = compound({
          rectangle("part-main", 0, 0, 1000, 500),
          rectangle("part-wing", 0, 500, 400, 500),
        }),
        height_mm = 850, rotation_deg = 0,
      },
    },
    custom_templates = {
      {
        id = "custom:sectional", name = "Sectional", category = "seating",
        default_anchor2_mm = { 1000, 500 },
        default_footprint = compound({
          rectangle("part-main", 0, 0, 1000, 500),
          rectangle("part-wing", 0, 500, 400, 500),
        }),
        default_height_mm = 850,
      },
    },
    extensions = {},
  }
  local session = {
    selection = { kind = "room", id = "room-living" },
    reserved_ids = {},
  }
  function session:model() return plan end
  function session:current_model() return plan end
  return session, plan
end

local function field(spec, key)
  for _, candidate in ipairs(spec.fields or {}) do
    if candidate.key == key then return candidate end
  end
end

local function presented_field(group, label)
  for _, candidate in ipairs(group.fields or {}) do
    if candidate.label == label then return candidate end
  end
end

describe("compound-compatible forms", function()
  it("keeps compound room editing compact and lossless", function()
    local session, plan = fixture()
    plan.rooms[1].footprint.note = "preserve me"
    plan.rooms[1].footprint.parts[1].material = "existing extension"
    local spec = forms.room.edit(session, plan.rooms[1])
    assert_equal("ROOM EDIT", spec.mode)
    local state = form_state.new(spec, spec.context)
    assert_equal("side", spec.preview_layout)
    assert_true(#state.preview.lines > 2)
    assert_equal(nil, field(spec, "part_origin_x_mm"))
    assert_equal(nil, field(spec, "part_origin_y_mm"))
    assert_equal(nil, field(spec, "add_part"))
    assert_true(field(spec, "section_width_mm") ~= nil)
    assert_true(field(spec, "section_depth_mm") ~= nil)
    state = form_state.reduce(state, { type = "set_value", key = "name", value = "Living updated" })
    state = form_state.reduce(state, { type = "set_value", key = "section_width_mm", value = 4500 })
    local action = assert(spec.build(state.draft, spec.context))
    assert_equal("edit_room", action.type)
    assert_equal("Living updated", action.patch.name)
    assert_equal(4500, action.patch.footprint.parts[1].size_mm[1])
    assert_equal("preserve me", action.patch.footprint.note)
    assert_equal("existing extension", action.patch.footprint.parts[1].material)
  end)

  it("authors an L-shaped room and chooses an interior furniture position", function()
    local session, plan = fixture()
    local room_spec = forms.room.add(session, {
      name = "Corner lounge",
      shape = "l_shape",
      width_mm = 4000,
      depth_mm = 3000,
      leg_width_mm = 1500,
      leg_depth_mm = 1200,
      missing_corner = "northeast",
      placement = "origin",
    })
    assert_true(field(room_spec, "shape") ~= nil)
    assert_true(field(room_spec, "leg_width_mm") ~= nil)
    local state, valid = form_state.validate_all(form_state.new(room_spec, room_spec.context))
    assert_true(valid, vim.inspect(state.errors))
    local action = assert(room_spec.build(state.draft, room_spec.context))
    assert_equal(nil, action.room.shape)
    assert_equal(nil, action.room.size_mm)
    assert_equal(2, #action.room.footprint.parts)
    assert_equal("part-horizontal", action.room.footprint.parts[1].id)
    assert_equal("part-vertical", action.room.footprint.parts[2].id)

    action.room.id = "room-corner-lounge"
    plan.rooms[#plan.rooms + 1] = action.room
    local furniture_spec = forms.furniture.add(session, {
      room_id = action.room.id,
      template_id = "builtin:sofa",
      placement = "centre",
    })
    local furniture_action = assert(furniture_spec.build(furniture_spec.initial, furniture_spec.context))
    assert_equal({ 2000, 600 }, furniture_action.furniture.position_mm)

    local edit_spec = forms.room.edit(session, action.room)
    assert_true(field(edit_spec, "width_mm") ~= nil)
    assert_true(field(edit_spec, "leg_width_mm") ~= nil)
    assert_equal("readonly", field(edit_spec, "shape").type)
    local edit_draft = model.deep_copy(edit_spec.initial)
    edit_draft.width_mm = 4500
    edit_draft.leg_width_mm = 1600
    edit_draft.missing_corner = "southwest"
    local edit_action = assert(edit_spec.build(edit_draft, edit_spec.context))
    assert_equal({ 0, 1800 }, edit_action.patch.footprint.parts[1].origin_mm)
    assert_equal({ 4500, 1200 }, edit_action.patch.footprint.parts[1].size_mm)
    assert_equal({ 2900, 0 }, edit_action.patch.footprint.parts[2].origin_mm)
    assert_equal({ 1600, 1800 }, edit_action.patch.footprint.parts[2].size_mm)

    local invalid_spec = forms.room.add(session, {
      shape = "l_shape", width_mm = 4000, depth_mm = 3000,
      leg_width_mm = 4000, leg_depth_mm = 1200, placement = "origin",
    })
    local invalid_state, invalid = form_state.validate_all(form_state.new(invalid_spec, invalid_spec.context))
    assert_equal(false, invalid)
    assert_true(invalid_state.errors.leg_width_mm ~= nil)
  end)

  it("keeps catalogue v1 public while exposing one canonical v2 view", function()
    local legacy = assert(catalog.get("builtin:sofa"))
    assert_true(legacy.default_size_mm ~= nil)
    assert_equal(nil, legacy.default_footprint)

    local _, plan = fixture()
    local converted = assert(catalog.resolve(plan, "builtin:sofa"))
    assert_equal(nil, converted.default_size_mm)
    assert_equal(nil, converted.shape)
    assert_equal(1, #converted.default_footprint.parts)
    assert_equal({ 2100, 900 }, converted.default_anchor2_mm)
    assert_equal(850, converted.default_height_mm)

    local local_template = assert(catalog.resolve(plan, "custom:sectional"))
    assert_equal(2, #local_template.default_footprint.parts)
    local_template.default_footprint.parts[1].size_mm[1] = 1
    assert_equal(1000, plan.custom_templates[1].default_footprint.parts[1].size_mm[1])
  end)

  it("creates canonical one-part v2 rooms, furniture, and doors", function()
    local session = fixture()
    local room_spec = forms.room.add(session, {
      name = "Bedroom", width_mm = 3200, depth_mm = 2800, placement = "origin",
    })
    local room_action = assert(room_spec.build(room_spec.initial, room_spec.context))
    assert_equal(nil, room_action.room.size_mm)
    assert_equal({ 3200, 2800 }, room_action.room.footprint.parts[1].size_mm)

    local furniture_spec = forms.furniture.add(session, {
      room_id = "room-living", template_id = "builtin:sofa", placement = "centre",
    })
    local furniture_action = assert(furniture_spec.build(furniture_spec.initial, furniture_spec.context))
    assert_equal(nil, furniture_action.furniture.center_mm)
    assert_equal(nil, furniture_action.furniture.size_mm)
    assert_equal({ 2000, 1000 }, furniture_action.furniture.position_mm)
    assert_equal({ 2100, 900 }, furniture_action.furniture.footprint.parts[1].size_mm)

    local door_spec = forms.door.add(session, {
      room_id = "room-living", part_id = "part-wing", side = "north", width_mm = 900,
      placement = "centre", connects_to_room_id = "outside",
    })
    assert_true(field(door_spec, "part_id") ~= nil)
    local door_action = assert(door_spec.build(door_spec.initial, door_spec.context))
    assert_equal("part-wing", door_action.door.part_id)
    assert_equal(300, door_action.door.offset_mm)
  end)

  it("preserves loaded compound geometry while editing scalar fields", function()
    local session, plan = fixture()

    local room_spec = forms.room.edit(session, plan.rooms[1])
    assert_equal(nil, field(room_spec, "width_mm"))
    assert_equal(nil, field(room_spec, "depth_mm"))
    assert_true(field(room_spec, "section_width_mm") ~= nil)
    assert_true(field(room_spec, "section_depth_mm") ~= nil)
    assert_equal("1 door · 1 furniture", field(room_spec, "attached").value(room_spec.context))
    local room_draft = model.deep_copy(room_spec.initial)
    room_draft.name, room_draft.origin_x_mm = "Living updated", 100
    local room_action = assert(room_spec.build(room_draft, room_spec.context))
    assert_equal(plan.rooms[1].footprint, room_action.patch.footprint)
    assert_equal(nil, room_action.patch.size_mm)
    assert_equal({ 100, 0 }, room_action.patch.origin_mm)

    local furniture_spec = forms.furniture.edit(session, plan.furniture[1])
    assert_equal(nil, field(furniture_spec, "width_mm"))
    assert_equal(nil, field(furniture_spec, "depth_mm"))
    local furniture_draft = model.deep_copy(furniture_spec.initial)
    furniture_draft.local_x_mm = 1200
    furniture_draft.rotation_deg = 90
    furniture_draft.height_mm = 900
    local furniture_action = assert(furniture_spec.build(furniture_draft, furniture_spec.context))
    assert_equal(nil, furniture_action.patch.footprint)
    assert_equal(nil, furniture_action.patch.anchor2_mm)
    assert_equal(nil, furniture_action.patch.center_mm)
    assert_equal(nil, furniture_action.patch.size_mm)
    assert_equal({ 1200, 1000 }, furniture_action.patch.position_mm)
    assert_equal(900, furniture_action.patch.height_mm)

    local template_spec = forms.template.edit(session, plan.custom_templates[1])
    assert_equal(nil, field(template_spec, "width_mm"))
    assert_equal(nil, field(template_spec, "depth_mm"))
    local template_draft = model.deep_copy(template_spec.initial)
    template_draft.name, template_draft.height_mm = "Sectional updated", 910
    local template_action = assert(template_spec.build(template_draft, template_spec.context))
    assert_equal(nil, template_action.patch.default_footprint)
    assert_equal(nil, template_action.patch.default_anchor2_mm)
    assert_equal(nil, template_action.patch.default_size_mm)
    assert_equal(910, template_action.patch.default_height_mm)

    assert_equal(2, #plan.rooms[1].footprint.parts)
    assert_equal(2, #plan.furniture[1].footprint.parts)
    assert_equal(2, #plan.custom_templates[1].default_footprint.parts)
  end)

  it("uses a door's selected part length and keeps its part reference", function()
    local session, plan = fixture()
    local door_spec = forms.door.edit(session, plan.doors[1])
    assert_true(field(door_spec, "part_id") ~= nil)
    local draft = model.deep_copy(door_spec.initial)
    draft.part_id, draft.side = "part-wing", "north"
    draft.offset_mm, draft.width_mm = 600, 900
    local errors = door_spec.validate(draft, door_spec.context)
    assert_equal(nil, errors.offset_mm)
    draft.offset_mm = 601
    errors = door_spec.validate(draft, door_spec.context)
    assert_true(errors.offset_mm ~= nil)
    draft.offset_mm = 600
    local action = assert(door_spec.build(draft, door_spec.context))
    assert_equal("part-wing", action.patch.part_id)
  end)

  it("aligns compound rooms and presents their compact geometry", function()
    local session, plan = fixture()
    local spec = forms.alignment.new(session, {
      moving_room_id = "room-office", reference_room_id = "room-living", operation = "place_north",
    })
    local action = assert(spec.build(spec.initial, spec.context))
    assert_equal("align_room", action.type)

    local objects = presenter.objects(plan)
    assert_true(objects.rows[2].detail:find("2 parts", 1, true) ~= nil)
    local properties = presenter.properties({
      model = plan,
      selection = { kind = "furniture", id = "furniture-sectional" },
      validation = {},
    })
    assert_equal("Position X", properties.groups[1].fields[2].label)
    assert_equal("Parts", properties.groups[1].fields[#properties.groups[1].fields].label)

    local room_properties = presenter.properties({
      model = plan,
      selection = { kind = "room", id = "room-living" },
      validation = {},
    })
    assert_equal("4 m", presented_field(room_properties.groups[1], "Width").value)
    assert_equal("3.5 m", presented_field(room_properties.groups[1], "Depth").value)
    assert_equal("10.25 m²", presented_field(room_properties.groups[1], "Area").value)
    assert_equal("15 m", presented_field(room_properties.groups[1], "Perimeter").value)
    assert_equal("2", presented_field(room_properties.groups[1], "Parts").value)
  end)
end)
