# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/zone_options"

class ZoneFaceTest < PhComposerTestCase
  include ZoneOptionsSupport

  API = PhComposer::API

  def setup
    super
    @model = Sketchup.active_model
    # This fixture exercises hand classification; default-on Make/Suggest has its own settings tests.
    settings = PhComposer::Zones::Faces::Settings
    settings::STORE.write(@model, settings::DEFAULTS.merge("suggest_on_make" => false))
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
  end

  def test_panel_closed_make_zone_classify_read_back_undo_redo_and_reopen
    group = box_group(100)
    @model.entities << group
    @model.selection.add(group)

    overview = query("ph_composer.zones.list").fetch("value")
    preview = API.preview(:context => @context, :name => "ph_composer.zones.make",
                          :params => overview.fetch("make_zone"))
    made = invoke("ph_composer.zones.make", overview.fetch("make_zone"), preview.fetch("proposal_digest"))

    assert_equal %w[completed committed], made.values_at("status", "effect")
    assert_includes made.fetch("affected").map { |row| row.fetch("change") }, "grouped"
    zone = query("ph_composer.zones.list").dig("value", "zones", 0)
    assert_equal [100], zone.dig("reference", "zone_path")
    assert_equal "Zone 1", zone.dig("values", "name")

    faces = query("ph_composer.zones.faces.list").dig("value", "faces")
    assert_equal 6, faces.length
    first = faces.first
    classified = invoke("ph_composer.zones.faces.classify", {
      "faces" => [first.fetch("reference")],
      "intent" => {
        "face_type" => { "mode" => "set", "value" => "Wall" },
        "boundary_condition" => { "mode" => "set", "value" => "Outdoors" }
      },
      "expected_values" => {}
    })
    assert_equal %w[completed committed], classified.values_at("status", "effect")
    face_id = classified.dig("value", "face_ids", 0)
    read_back = query("ph_composer.zones.faces.list").dig("value", "faces")
                                                     .find { |face| face.dig("reference", "entity_id") == face_id }
    assert_equal({ "face_type" => "Wall", "boundary_condition" => "Outdoors" }, read_back.fetch("values"))

    @model.undo
    current_group = @model.entities.to_a.find { |entity| entity.persistent_id == group.persistent_id }
    assert_nil PhComposer::Zones::Faces::FACE_STORE.read(current_group.entities.to_a.first)
    @model.redo
    current_group = @model.entities.to_a.find { |entity| entity.persistent_id == group.persistent_id }
    assert_equal face_id, PhComposer::Zones::Faces::FACE_STORE.read(current_group.entities.to_a.first).fetch("id")

    @model.save("/tmp/ph-composer-p1b.skp")
    Sketchup.open_file("/tmp/ph-composer-p1b.skp")
    reopened = PhComposer::Sessions.for(Sketchup.active_model)
    reopened_context = API.connect(:session_id => reopened.id)
    result = API.query(:context => reopened_context, :name => "ph_composer.zones.faces.list")
    assert_equal face_id, result.dig("value", "faces", 0, "reference", "entity_id")
  end

  def test_make_zone_groups_loose_geometry_and_preserves_unrelated_dictionaries
    face = Sketchup::Face.new(201, { "other.extension" => { "payload" => "kept" } })
    edge = Sketchup::Edge.new(202, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(1, 0, 0))
    @model.entities << face << edge
    params = { "parent_path" => [], "entity_ids" => [201, 202], "name" => "Workshop" }

    made = invoke("ph_composer.zones.make", params)

    assert_equal "completed", made.fetch("status")
    group = @model.entities.to_a.find { |entity| entity.is_a?(Sketchup::Group) }
    assert_equal "Workshop", group.name
    assert_equal "kept", face.get_attribute("other.extension", "payload")
    assert_equal [face, edge], group.entities.to_a
  end

  def test_zone_update_preserves_metadata_and_updates_face_stamps
    group = box_group(300)
    @model.entities << group
    zone = make_group_zone(group)
    face = query("ph_composer.zones.faces.list").dig("value", "faces", 0)
    invoke("ph_composer.zones.faces.classify", classify_params(face, "Wall", "Ground"))
    stored = PhComposer::Zones::ZONE_STORE.read(group)
    stored["user_data"] = { "firm.note" => "keep" }
    PhComposer::Zones::ZONE_STORE.write(group, stored)
    level_id = create_zone_option("level", "L1")
    before = zone.fetch("values")
    after = before.merge("name" => "North Zone", "level_id" => level_id,
                         "ground_depth_mm" => 250.0)

    result = invoke("ph_composer.zones.update", {
      "reference" => zone.fetch("reference"), "values" => after, "expected_values" => before
    })

    assert_equal "completed", result.fetch("status")
    assert_equal({ "firm.note" => "keep" }, PhComposer::Zones::ZONE_STORE.read(group).fetch("user_data"))
    stamp = PhComposer::Zones::STAMP_STORE.read(group.entities.to_a.first)
    assert_equal [after.fetch("building_segment_id"), level_id], stamp.values_at("building_segment_id", "level_id")
  end

  def test_existing_zone_selection_is_not_offered_as_a_make_target
    group = box_group(350)
    @model.entities << group
    make_group_zone(group)
    @model.selection.add(group)

    assert_nil query("ph_composer.zones.list").dig("value", "make_zone")
  end

  def test_copied_zone_identity_is_reported_ambiguous_and_refuses_mutation
    first = box_group(400)
    second = box_group(500)
    @model.entities << first << second
    zone = make_group_zone(first)
    PhComposer::Zones::ZONE_STORE.write(second, PhComposer::Zones::ZONE_STORE.read(first))

    rows = query("ph_composer.zones.list").dig("value", "zones")
    assert_equal %w[ambiguous ambiguous], rows.map { |row| row.fetch("state") }
    result = invoke("ph_composer.zones.update", {
      "reference" => zone.fetch("reference"), "values" => zone.fetch("values"),
      "expected_values" => zone.fetch("values")
    })
    assert_equal %w[refused target.ambiguous none], result.values_at("status", "code", "effect")
  end

  def test_nested_zone_is_reported_and_refuses_mutation
    inner = box_group(550)
    outer = Sketchup::Group.new(540, Sketchup::Entities.new([inner]))
    @model.entities << outer
    outer_record = zone_record("zon_AAAAAAAAAAAA", "Outer")
    inner_record = zone_record("zon_BBBBBBBBBBBB", "Inner")
    PhComposer::Zones::ZONE_STORE.write(outer, outer_record)
    PhComposer::Zones::ZONE_STORE.write(inner, inner_record)

    rows = query("ph_composer.zones.list").dig("value", "zones")
    nested = rows.find { |row| row.fetch("id") == inner_record.fetch("id") }
    assert_equal "wrong_hierarchy", nested.fetch("state")
    result = invoke("ph_composer.zones.update", {
      "reference" => nested.fetch("reference"), "values" => nested.fetch("values"),
      "expected_values" => nested.fetch("values")
    })
    assert_equal %w[refused target.wrong_hierarchy none], result.values_at("status", "code", "effect")
  end

  def test_classification_uses_explicit_keep_set_clear_and_preserves_metadata
    group = box_group(600)
    @model.entities << group
    make_group_zone(group)
    face = query("ph_composer.zones.faces.list").dig("value", "faces", 0)
    invoke("ph_composer.zones.faces.classify", classify_params(face, "Wall", "Outdoors"))
    entity = group.entities.to_a.first
    record = PhComposer::Zones::Faces::FACE_STORE.read(entity)
    record["user_data"] = { "firm.note" => "keep" }
    record["extension_data"] = { "outside.extension" => { "schema_version" => 3, "payload" => { "x" => 1 } } }
    PhComposer::Zones::Faces::FACE_STORE.write(entity, record)
    current = query("ph_composer.zones.faces.list").dig("value", "faces", 0)

    result = invoke("ph_composer.zones.faces.classify", {
      "faces" => [current.fetch("reference")],
      "intent" => {
        "face_type" => { "mode" => "keep" },
        "boundary_condition" => { "mode" => "set", "value" => "Adiabatic" }
      },
      "expected_values" => current.fetch("values")
    })

    assert_equal "completed", result.fetch("status")
    stored = PhComposer::Zones::Faces::FACE_STORE.read(entity)
    assert_equal ["Wall", "Adiabatic"], stored.values_at("face_type", "boundary_condition")
    assert_equal({ "firm.note" => "keep" }, stored.fetch("user_data"))
    assert_equal 3, stored.dig("extension_data", "outside.extension", "schema_version")
  end

  def test_keep_intent_on_an_unassigned_face_is_a_no_op
    group = box_group(650)
    @model.entities << group
    make_group_zone(group)
    face = query("ph_composer.zones.faces.list").dig("value", "faces", 0)

    result = invoke("ph_composer.zones.faces.classify", {
      "faces" => [face.fetch("reference")],
      "intent" => {
        "face_type" => { "mode" => "keep" },
        "boundary_condition" => { "mode" => "keep" }
      },
      "expected_values" => {}
    })

    entity = group.entities.to_a.first
    assert_equal %w[completed none], result.values_at("status", "effect")
    assert_nil PhComposer::Zones::Faces::FACE_STORE.read(entity)
    assert_nil PhComposer::Zones::STAMP_STORE.read(entity)
  end

  def test_suggestions_use_world_normal_and_zone_ground_depth_without_writing
    face = Sketchup::Face.new(701, {}, :points => [point(0, 0, 0), point(2, 0, 0), point(2, 2, 0)],
                                       :normal => Geom::Vector3d.new(0, 0, 1))
    group = Sketchup::Group.new(700, Sketchup::Entities.new([face]), {},
                                :transformation => Geom::Transformation.translation([0, 0, 20]))
    @model.entities << group
    make_group_zone(group)
    dictionaries = face.attribute_dictionaries

    row = query("ph_composer.zones.faces.list").dig("value", "faces", 0)

    assert_equal({ "face_type" => "RoofCeiling", "boundary_condition" => "Outdoors" }, row.fetch("suggested"))
    assert_same dictionaries, face.attribute_dictionaries
    assert_nil PhComposer::Zones::Faces::FACE_STORE.read(face)
  end

  def test_full_wall_solve_is_reciprocal_idempotent_and_native_undoable
    left_group, right_group = adjacent_face_groups(800)
    @model.entities << left_group << right_group
    left_zone = make_group_zone(left_group)
    right_zone = make_group_zone(right_group)
    left_face = classify_only_face(left_zone, "Outdoors")
    right_face = classify_only_face(right_zone, "Outdoors")
    params = { "zones" => [left_zone.fetch("reference"), right_zone.fetch("reference")] }

    preview = API.preview(:context => @context, :name => "ph_composer.zones.solve_adjacency", :params => params)
    result = invoke("ph_composer.zones.solve_adjacency", params, preview.fetch("proposal_digest"))

    assert_equal %w[completed committed], result.values_at("status", "effect")
    pair_id = result.dig("value", "pair_ids", 0)
    assert_match(/^adj_/, pair_id)
    rows = query("ph_composer.zones.faces.list").dig("value", "faces")
    paired = rows.select { |row| row.dig("values", "adjacency", "pair_id") == pair_id }
    assert_equal 2, paired.length
    assert_equal %w[current current], paired.map { |row| row.fetch("adjacency_state") }
    assert_equal [left_face.dig("reference", "entity_id"), right_face.dig("reference", "entity_id")].sort,
                 paired.map { |row| row.dig("reference", "entity_id") }.sort

    operation_count = @model.operations.length
    again = invoke("ph_composer.zones.solve_adjacency", params)
    assert_equal %w[completed none], again.values_at("status", "effect")
    assert_equal operation_count, @model.operations.length

    @model.undo
    assert_equal %w[Outdoors Outdoors], query("ph_composer.zones.faces.list").dig("value", "faces")
                                                                             .map { |row|
                                          row.dig("values",
                                                  "boundary_condition")
                                        }.sort
    @model.redo
    assert_equal %w[current current], query("ph_composer.zones.faces.list").dig("value", "faces")
                                                                           .map { |row| row.fetch("adjacency_state") }
  end

  def test_moved_zone_is_stale_until_explicit_retire_and_resolve
    left_group, right_group = adjacent_face_groups(900)
    @model.entities << left_group << right_group
    left_zone = make_group_zone(left_group)
    right_zone = make_group_zone(right_group)
    classify_only_face(left_zone, "Outdoors")
    classify_only_face(right_zone, "Outdoors")
    solve = { "zones" => [left_zone.fetch("reference"), right_zone.fetch("reference")] }
    invoke("ph_composer.zones.solve_adjacency", solve)

    right_group.transformation = Geom::Transformation.translation([1, 0, 0])
    rows = query("ph_composer.zones.faces.list").dig("value", "faces")
    assert_equal %w[stale stale], rows.map { |row| row.fetch("adjacency_state") }

    retired = invoke("ph_composer.zones.retire_adjacency", { "face" => rows.first.fetch("reference") })
    assert_equal %w[completed committed], retired.values_at("status", "effect")
    unpaired = query("ph_composer.zones.faces.list").dig("value", "faces")
    assert unpaired.all? { |row| !row.fetch("values").key?("boundary_condition") }
    assert unpaired.all? { |row| row["adjacency_state"].nil? }

    right_group.transformation = Geom::Transformation.new
    resolved = invoke("ph_composer.zones.solve_adjacency", solve)
    assert_equal %w[completed committed], resolved.values_at("status", "effect")
  end

  def test_classifying_one_surface_face_retires_its_reciprocal_in_the_same_operation
    left_group, right_group = adjacent_face_groups(950)
    @model.entities << left_group << right_group
    left_zone = make_group_zone(left_group)
    right_zone = make_group_zone(right_group)
    classify_only_face(left_zone, "Outdoors")
    classify_only_face(right_zone, "Outdoors")
    invoke("ph_composer.zones.solve_adjacency",
           { "zones" => [left_zone.fetch("reference"), right_zone.fetch("reference")] })
    rows = query("ph_composer.zones.faces.list").dig("value", "faces")
    edited = rows.first

    result = invoke("ph_composer.zones.faces.classify", {
      "faces" => [edited.fetch("reference")],
      "intent" => { "boundary_condition" => { "mode" => "set", "value" => "Outdoors" } },
      "expected_values" => edited.fetch("values")
    })

    assert_equal %w[completed committed], result.values_at("status", "effect")
    after = query("ph_composer.zones.faces.list").dig("value", "faces")
    assert_equal [nil, "Outdoors"], after.map { |row| row.dig("values", "boundary_condition") }.sort_by(&:to_s)
    assert after.all? { |row| row["adjacency_state"].nil? }
  end

  # M1: two child Groups drawn from one definition share every Face in it, so writing through one
  # placement writes the other. Classify and Reverse refuse; reads still list both placements.
  def test_a_face_under_shared_child_groups_refuses_classify_and_reverse
    shared = Sketchup::Entities.new([Sketchup::Face.new(901)])
    zone = Sketchup::Group.new(900, Sketchup::Entities.new([Sketchup::Group.new(910, shared),
                                                            Sketchup::Group.new(920, shared)]))
    @model.entities << zone
    make_group_zone(zone)

    assert_equal [[910, 901], [920, 901]],
                 query("ph_composer.zones.faces.list").dig("value", "faces")
                                                      .map { |row| row.dig("reference", "entity_path") }
    assert_shared_group_refusals
  end

  def test_a_shared_child_group_with_one_placement_outside_the_zone_refuses
    shared = Sketchup::Entities.new([Sketchup::Face.new(901)])
    zone = Sketchup::Group.new(900, Sketchup::Entities.new([Sketchup::Group.new(910, shared)]))
    @model.entities << zone << Sketchup::Group.new(920, shared)
    make_group_zone(zone)

    assert_shared_group_refusals
  end

  def test_a_recorded_face_under_shared_child_groups_still_refuses
    shared = Sketchup::Entities.new([Sketchup::Face.new(901)])
    zone = Sketchup::Group.new(900, Sketchup::Entities.new([Sketchup::Group.new(910, shared)]))
    @model.entities << zone
    make_group_zone(zone)
    classified = invoke("ph_composer.zones.faces.classify",
                        classify_params(query("ph_composer.zones.faces.list").dig("value", "faces", 0),
                                        "Wall", "Outdoors"))
    assert_equal "committed", classified.fetch("effect")
    zone.entities << Sketchup::Group.new(920, shared)

    assert_shared_group_refusals
  end

  def test_suggest_classification_refuses_a_zone_holding_shared_child_groups
    shared = Sketchup::Entities.new([Sketchup::Face.new(901)])
    zone = Sketchup::Group.new(900, Sketchup::Entities.new([Sketchup::Group.new(910, shared),
                                                            Sketchup::Group.new(920, shared)]))
    @model.entities << zone
    made = make_group_zone(zone)
    operation_count = @model.operations.length

    result = invoke("ph_composer.zones.faces.auto_classify", { "zone" => made.fetch("reference") })

    assert_equal %w[refused target.shared_definition none], result.values_at("status", "code", "effect")
    assert_match(/Open that Group with Edit Group/, result.fetch("message"))
    assert_equal operation_count, @model.operations.length
  end

  # M2: an explicit outer-Zone path through an authored inner Zone names a Face the outer Zone does
  # not own. It refuses for reads and writes; an ordinary nested Group still classifies.
  def test_an_explicit_face_path_through_a_nested_zone_refuses
    inner = Sketchup::Group.new(701, Sketchup::Entities.new([Sketchup::Face.new(700)]))
    outer = Sketchup::Group.new(600, Sketchup::Entities.new([Sketchup::Face.new(601), inner]))
    @model.entities << outer
    zone = make_group_zone(outer)
    PhComposer::Zones::ZONE_STORE.write(inner, zone_record("zon_BBBBBBBBBBBB", "Inner"))
    crossing = zone.fetch("reference").merge("entity_path" => [701, 700], "entity_id" => nil)
    operation_count = @model.operations.length

    classify = invoke("ph_composer.zones.faces.classify", {
      "faces" => [crossing], "intent" => { "face_type" => { "mode" => "set", "value" => "Wall" } }
    })
    reverse = invoke("ph_composer.zones.faces.reverse", { "face" => crossing })
    error = assert_raises(PhComposer::CodedError) do
      PhComposer::Zones::Occurrences.resolve_face(@model, crossing, :allow_unassigned => true)
    end

    assert_equal %w[refused target.wrong_hierarchy none], classify.values_at("status", "code", "effect")
    assert_equal %w[refused target.wrong_hierarchy none], reverse.values_at("status", "code", "effect")
    assert_equal "target.wrong_hierarchy", error.code
    assert_equal operation_count, @model.operations.length
    assert_nil PhComposer::Zones::STAMP_STORE.read(inner.entities.to_a.first)
  end

  def test_a_face_in_an_ordinary_nested_group_still_classifies
    outer = Sketchup::Group.new(600, Sketchup::Entities.new([
      Sketchup::Group.new(701, Sketchup::Entities.new([Sketchup::Face.new(700)]))
    ]))
    @model.entities << outer
    make_group_zone(outer)
    face = query("ph_composer.zones.faces.list").dig("value", "faces", 0)

    result = invoke("ph_composer.zones.faces.classify", classify_params(face, "Wall", "Outdoors"))

    assert_equal [701, 700], face.dig("reference", "entity_path")
    assert_equal %w[completed committed], result.values_at("status", "effect")
  end

  # A null entity_id asserts that the Face has no record (context/CONTRACTS.md, "Geometry records and
  # occurrence references"): every Face write refuses it once the Face has one, at the current revision too.
  def test_a_null_face_identity_refuses_every_write_once_the_face_has_a_record
    group = box_group(600)
    @model.entities << group
    make_group_zone(group)
    stale, untouched = query("ph_composer.zones.faces.list").dig("value", "faces").first(2)
    assert_nil stale.dig("reference", "entity_id")
    assert_equal "committed", invoke("ph_composer.zones.faces.classify",
                                     classify_params(stale, "Wall", "Outdoors")).fetch("effect")
    record = PhComposer::Zones::Faces::FACE_STORE.read(group.entities.to_a.first)
    operation_count = @model.operations.length

    writes = {
      "ph_composer.zones.faces.classify" => classify_params(stale, "Floor", "Ground"),
      "ph_composer.zones.faces.reverse" => { "face" => stale.fetch("reference") },
      "ph_composer.zones.faces.assign_assembly" => {
        "assembly_id" => nil, "targets" => [{ "reference" => stale.fetch("reference"), "expected_values" => {} }]
      }
    }
    writes.each do |name, params|
      [API.preview(:context => @context, :name => name, :params => params), invoke(name, params)].each do |result|
        assert_equal %w[refused target.changed none], result.values_at("status", "code", "effect"), name
      end
    end
    handoff = API.view(:context => @context, :name => "ph_composer.zones.faces.open_attached_assignment",
                       :params => { "faces" => [stale.fetch("reference")], "revision" => @session.revision })
    assert_equal %w[refused target.changed], handoff.values_at("status", "code")
    assert_equal operation_count, @model.operations.length
    assert_equal record, PhComposer::Zones::Faces::FACE_STORE.read(group.entities.to_a.first)

    # A Face that truly has no record is still written through a null identity.
    fresh = invoke("ph_composer.zones.faces.classify", classify_params(untouched, "Wall", "Outdoors"))
    assert_equal %w[completed committed], fresh.values_at("status", "effect")
  end

  def test_a_null_identity_naming_a_face_with_a_copied_record_refuses_before_any_transaction
    group = box_group(620)
    @model.entities << group
    make_group_zone(group)
    first, second = group.entities.to_a.first(2)
    record = { "id" => "fac_AAAAAAAAAAAA", "schema_version" => 1, "face_type" => "Floor",
               "boundary_condition" => "Ground" }
    [first, second].each { |face| PhComposer::Zones::Faces::FACE_STORE.write(face, record) }
    row = query("ph_composer.zones.faces.list").dig("value", "faces").first
    masked = classify_params(row, "Wall", "Outdoors")
             .merge("faces" => [row.fetch("reference").merge("entity_id" => nil)], "expected_values" => {})
    operation_count = @model.operations.length

    preview = API.preview(:context => @context, :name => "ph_composer.zones.faces.classify", :params => masked)
    result = invoke("ph_composer.zones.faces.classify", masked)

    [preview, result].each do |outcome|
      assert_equal %w[refused target.changed none], outcome.values_at("status", "code", "effect")
    end
    assert_equal operation_count, @model.operations.length
    assert_equal [record, record], [first, second].map { |face| PhComposer::Zones::Faces::FACE_STORE.read(face) }
  end

  # Apply resolves strictly too: a Face that gains a record between planning and applying stops the step.
  def test_reverse_refuses_at_apply_when_the_face_gained_a_record
    group = box_group(640)
    @model.entities << group
    make_group_zone(group)
    reference = query("ph_composer.zones.faces.list").dig("value", "faces", 0, "reference")
    step = PhComposer::Zones::Faces::ReverseFaceStep.new(:reference => reference)
    face = group.entities.to_a.first
    PhComposer::Zones::Faces::FACE_STORE.write(face, { "id" => "fac_BBBBBBBBBBBB", "schema_version" => 1 })
    normal = [face.normal.x, face.normal.y, face.normal.z]

    error = assert_raises(PhComposer::CodedError) { step.apply(@model, {}) }
    assert_equal "target.changed", error.code
    assert_equal normal, [face.normal.x, face.normal.y, face.normal.z]
  end

  def test_classify_refuses_at_apply_when_a_planned_unassigned_face_gained_a_record
    group = box_group(650)
    @model.entities << group
    make_group_zone(group)
    row = query("ph_composer.zones.faces.list").dig("value", "faces", 0)
    request = PhComposer::HandlerRequest.for(@session, :owner => PhComposer::Zones::FEATURE_ID, :name => "test")
    proposal = PhComposer::Operations::Proposal.new
    intent = classify_params(row, "Wall", "Ground").fetch("intent")
    PhComposer::Zones::Faces.classify(request, proposal, :faces => [row.fetch("reference")], :intent => intent)
    face = group.entities.to_a.first
    gained = { "id" => "fac_GGGGGGGGGGGG", "schema_version" => 1, "face_type" => "Floor" }
    PhComposer::Zones::Faces::FACE_STORE.write(face, gained)

    error = assert_raises(PhComposer::CodedError) { proposal.steps.first.apply(@model, {}) }
    assert_equal "target.changed", error.code
    assert_equal gained, PhComposer::Zones::Faces::FACE_STORE.read(face)
  end

  # One write rule for a Zone's own record: its own lock refuses a single, batch and metadata edit, at preview
  # and invoke, with no Undo entry.
  def test_a_locked_zone_refuses_single_batch_and_metadata_edits
    group = box_group(660)
    @model.entities << group
    zone = make_group_zone(group)
    before = zone.fetch("values")
    record = PhComposer::Zones::ZONE_STORE.read(group)
    group.locked = true
    operation_count = @model.operations.length
    metadata = { "user_data" => record.fetch("user_data", {}), "extension_data" => record.fetch("extension_data", {}) }

    writes = {
      "ph_composer.zones.update" => { "reference" => zone.fetch("reference"),
                                      "values" => before.merge("name" => "Changed"), "expected_values" => before },
      "ph_composer.zones.update_field" => { "field" => "name", "value" => "Changed",
                                            "targets" => [{ "reference" => zone.fetch("reference"),
                                                            "expected_values" => before }] },
      "ph_composer.zones.update_metadata" => { "updates" => [{ "reference" => zone.fetch("reference"),
                                                               "user_data" => { "firm.note" => "x" },
                                                               "expected_metadata" => metadata }] }
    }
    writes.each do |name, params|
      [API.preview(:context => @context, :name => name, :params => params), invoke(name, params)].each do |result|
        assert_equal %w[refused target.locked none], result.values_at("status", "code", "effect"), name
      end
    end
    assert_equal operation_count, @model.operations.length
    assert_equal record, PhComposer::Zones::ZONE_STORE.read(group)

    step = PhComposer::Zones::UpdateZoneStep.new(:reference => zone.fetch("reference"), :before => record,
                                                 :after => record.merge("name" => "Changed"))
    error = assert_raises(PhComposer::CodedError) { step.apply(@model, {}) }
    assert_equal "target.locked", error.code
  end

  private

  def assert_shared_group_refusals
    rows = query("ph_composer.zones.faces.list").dig("value", "faces")
    face = rows.first
    before = PhComposer::Zones::Faces::FACE_STORE.read(@model.entities.to_a.first.entities.to_a.first
                                                           .entities.to_a.first)
    operation_count = @model.operations.length
    classify = classify_params(face, "Floor", "Ground")
    reverse = { "face" => face.fetch("reference") }

    results = [
      API.preview(:context => @context, :name => "ph_composer.zones.faces.classify", :params => classify),
      invoke("ph_composer.zones.faces.classify", classify),
      API.preview(:context => @context, :name => "ph_composer.zones.faces.reverse", :params => reverse),
      invoke("ph_composer.zones.faces.reverse", reverse)
    ]

    results.each do |result|
      assert_equal %w[refused target.shared_definition none], result.values_at("status", "code", "effect")
      assert_match(/Open that Group with Edit Group/, result.fetch("message"))
    end
    assert_equal operation_count, @model.operations.length
    assert_equal [before], [PhComposer::Zones::Faces::FACE_STORE.read(@model.entities.to_a.first.entities.to_a
                                                                         .first.entities.to_a.first)]
    assert_equal rows, query("ph_composer.zones.faces.list").dig("value", "faces")
  end

  def invoke(name, params, proposal_digest = nil)
    @sequence += 1
    request = { "sequence" => @sequence, "expected_revision" => @session.revision }
    request["proposal_digest"] = proposal_digest if proposal_digest
    API.invoke(:context => @context, :name => name, :params => params, :request => request)
  end

  def query(name)
    API.query(:context => @context, :name => name)
  end

  def make_group_zone(group)
    @model.selection.clear
    @model.selection.add(group)
    invoke("ph_composer.zones.make", { "parent_path" => [], "entity_ids" => [group.persistent_id] })
    query("ph_composer.zones.list").dig("value", "zones").find do |zone|
      zone.dig("reference", "zone_path") == [group.persistent_id]
    end
  end

  def classify_params(face, type, boundary)
    {
      "faces" => [face.fetch("reference")],
      "intent" => {
        "face_type" => { "mode" => "set", "value" => type },
        "boundary_condition" => { "mode" => "set", "value" => boundary }
      },
      "expected_values" => face.fetch("values")
    }
  end

  def box_group(base)
    faces = 6.times.map do |index|
      Sketchup::Face.new(base + index + 1, {}, :points => [point(0, 0, index), point(2, 0, index),
                                                           point(2, 2, index)])
    end
    Sketchup::Group.new(base, Sketchup::Entities.new(faces))
  end

  def adjacent_face_groups(base)
    metres = 1.0 / 0.0254
    loop = [point(0, 0, 0), point(0, 4 * metres, 0), point(0, 4 * metres, 3 * metres),
            point(0, 0, 3 * metres)]
    left = Sketchup::Face.new(base + 1, {}, :points => loop, :normal => Geom::Vector3d.new(1, 0, 0))
    right = Sketchup::Face.new(base + 2, {}, :points => loop.reverse, :normal => Geom::Vector3d.new(-1, 0, 0))
    [Sketchup::Group.new(base, Sketchup::Entities.new([left])),
     Sketchup::Group.new(base + 10, Sketchup::Entities.new([right]))]
  end

  def classify_only_face(zone, boundary)
    face = query("ph_composer.zones.faces.list").dig("value", "faces")
                                                .find { |row| row.dig("reference", "zone_id") == zone.fetch("id") }
    invoke("ph_composer.zones.faces.classify", classify_params(face, "Wall", boundary))
    query("ph_composer.zones.faces.list").dig("value", "faces")
                                         .find { |row| row.dig("reference", "zone_id") == zone.fetch("id") }
  end

  def point(x, y, z)
    Geom::Point3d.new(x, y, z)
  end

  def zone_record(id, name)
    {
      "id" => id, "schema_version" => 1, "name" => name, "building_segment" => "Building",
      "level" => nil, "ground_depth_mm" => 0.0, "user_data" => {}, "extension_data" => {}
    }
  end
end
