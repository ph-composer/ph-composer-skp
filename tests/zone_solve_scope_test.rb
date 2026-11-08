# frozen_string_literal: true

require_relative "test_helper"

# What Solve does across a whole scope. Reading is unbounded and writing is not, so the interesting
# cases are the ones where a pairing reaches outside the Zones the caller named, and the ones the
# solver reports instead of pairing.
class ZoneSolveScopeTest < PhComposerTestCase
  API = PhComposer::API
  COPY_EXTENSION = PhComposer::Records::Extension.new(
    :namespace => "test.fixture.face_copy", :schema_version => 1,
    :references => [
      { "path" => "$.external_id", "target_kind" => "ph_composer.zones.faces.attached_zone",
        "cardinality" => "one" }
    ]
  )

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @next_id = 1_000
  end

  def test_partial_cut_reports_glued_instances_on_either_side_without_changing_geometry
    [:first, :last].each do |side|
      wall(101, 0, 0, 4, 0, 3, :east)
      wall(102, 0, 2, 6, 0, 3, :west)
      author
      group = @model.entities.to_a.public_send(side)
      face = group.entities.to_a.grep(Sketchup::Face).first
      instance = group.entities.add_instance(Sketchup::ComponentDefinition.new, Geom::Transformation.new)
      instance.glued_to = face
      before = faces
      revision = @session.revision
      result = solve(all_references)
      assert_equal "none", result["effect"], result.inspect
      assert_equal ["adjacency.glued_instances"], finding_codes(result)
      assert_empty result.dig("value", "pair_ids")
      assert_equal before, faces
      assert_equal revision, @session.revision
      assert_same face, instance.glued_to
      @model.entities.erase_entities(@model.entities.to_a)
    end
  end

  def test_full_match_with_glued_instances_pairs_without_cutting
    wall(103, 0, 0, 4, 0, 3, :east)
    wall(104, 0, 0, 4, 0, 3, :west)
    author
    originals = @model.entities.to_a.map { |group| group.entities.to_a.grep(Sketchup::Face).first }
    @model.entities.to_a.each_with_index do |group, index|
      instance = group.entities.add_instance(Sketchup::ComponentDefinition.new, Geom::Transformation.new)
      instance.glued_to = originals[index]
    end
    result = solve(all_references)
    assert_equal "committed", result["effect"], result.inspect
    assert_equal 1, result.dig("value", "pair_ids").length
    assert_empty finding_codes(result)
    assert_equal 2, faces.length
    assert_equal %w[Surface Surface], boundary_conditions
    assert_equal originals, @model.entities.to_a.map { |group| group.entities.to_a.grep(Sketchup::Face).first }
  end

  def test_a_repeat_solve_counts_every_pair_as_already_paired
    wall(103, 0, 0, 4, 0, 3, :east)
    wall(104, 0, 0, 4, 0, 3, :west)
    author
    first = solve(all_references)
    second = solve(all_references)

    assert_equal 1, first.dig("value", "pair_ids").length
    assert_equal 0, first.dig("value", "already_paired")
    assert_equal 1, second.dig("value", "already_paired")
    assert_equal "none", second.fetch("effect")
  end

  def test_wholly_covered_glued_face_is_not_cut_while_its_larger_counterpart_splits
    wall(105, 0, 0, 4, 0, 3, :east)
    wall(106, 0, 1, 3, 0, 3, :west)
    author
    group = @model.entities.to_a.last
    face = group.entities.to_a.grep(Sketchup::Face).first
    instance = group.entities.add_instance(Sketchup::ComponentDefinition.new, Geom::Transformation.new)
    instance.glued_to = face
    result = solve(all_references)
    assert_equal "committed", result["effect"], result.inspect
    assert_equal 1, result.dig("value", "pair_ids").length
    assert_empty finding_codes(result)
    assert_same face, group.entities.to_a.grep(Sketchup::Face).first
    assert_same face, instance.glued_to
    assert_equal "Surface", PhComposer::Zones::Faces::FACE_STORE.read(face)["boundary_condition"]
    assert_operator faces.length, :>, 2
  end

  def test_glue_change_without_revision_or_geometry_change_invalidates_public_preview
    wall(107, 0, 0, 4, 0, 3, :east)
    wall(108, 0, 2, 6, 0, 3, :west)
    author
    params = { "zones" => all_references }
    preview = API.preview(:context => @context, :name => "ph_composer.zones.solve_adjacency", :params => params)
    group = @model.entities.to_a.last
    face = group.entities.to_a.grep(Sketchup::Face).first
    before_geometry = PhComposer::FaceCapture.call(face, Geom::Transformation.new)
    revision = @session.revision
    instance = group.entities.add_instance(Sketchup::ComponentDefinition.new, Geom::Transformation.new)
    instance.glued_to = face
    assert_equal before_geometry.to_h, PhComposer::FaceCapture.call(face, Geom::Transformation.new).to_h
    assert_equal revision, @session.revision
    @sequence += 1
    result = API.invoke(:context => @context, :name => "ph_composer.zones.solve_adjacency", :params => params,
                        :request => { "sequence" => @sequence, "expected_revision" => revision,
                                      "proposal_digest" => preview.fetch("proposal_digest") })
    assert_equal %w[refused proposal.changed none], result.values_at("status", "code", "effect")
    assert_equal 2, faces.length
  end

  def test_live_cut_guard_checks_both_sides_before_first_native_cut
    wall(109, 0, 0, 4, 0, 3, :east)
    wall(110, 0, 2, 6, 0, 3, :west)
    author
    request = PhComposer::HandlerRequest.new(:session => @session, :model => @model,
                                             :params => { "zones" => all_references }, :revision => @session.revision,
                                             :registry => PhComposer::Registry.current,
                                             :engine => PhComposer::Records::Engine.new(
                                               @model, PhComposer::Registry.current.catalog
                                             ))
    proposal = PhComposer::Operations::Proposal.new
    action = PhComposer::Registry.current.actions.fetch("ph_composer.zones.solve_adjacency")
    action.handler.call(request, proposal)
    step = proposal.steps.first
    assert_equal [false, false], %w[left right].map { |side| step.descriptor.fetch(side).fetch("has_glued_instances") }
    group = @model.entities.to_a.last
    face = group.entities.to_a.grep(Sketchup::Face).first
    instance = group.entities.add_instance(Sketchup::ComponentDefinition.new, Geom::Transformation.new)
    instance.glued_to = face
    before = faces
    PhComposer::Zones::FaceSplit.stub(:apply, ->(*) { flunk "No Face may be cut before checking both glue guards." }) do
      error = assert_raises(PhComposer::CodedError) { step.apply(@model, {}) }
      assert_equal "target.changed", error.code
    end
    assert_equal before, faces
  end

  def test_solving_every_zone_pairs_each_full_wall_once
    wall(100, 0, 0, 4, 0, 3, :east)
    wall(110, 0, 0, 4, 0, 3, :west)
    wall(120, 6, 0, 4, 0, 3, :east)
    wall(130, 6, 0, 4, 0, 3, :west)
    author

    result = solve(all_references)

    assert_equal %w[completed committed], result.values_at("status", "effect")
    assert_equal 2, result.dig("value", "pair_ids").length
    assert_equal 4, boundary_conditions.count("Surface")
  end

  def test_solving_one_zone_of_a_pair_refuses_and_names_both_zones
    wall(200, 0, 0, 4, 0, 3, :east)
    wall(210, 0, 0, 4, 0, 3, :west)
    author
    one = all_references.first

    result = solve([one])

    assert_equal %w[refused scope.incomplete none], result.values_at("status", "code", "effect")
    assert_empty boundary_conditions.compact.reject { |value| value == "Outdoors" }
  end

  def test_including_both_zones_after_the_refusal_succeeds
    wall(220, 0, 0, 4, 0, 3, :east)
    wall(230, 0, 0, 4, 0, 3, :west)
    author
    solve([all_references.first])

    result = solve(all_references)

    assert_equal "completed", result.fetch("status")
    assert_equal 2, boundary_conditions.count("Surface")
  end

  # A third Zone the caller did not name is still read, so its full-wall match with a scoped Zone
  # is what triggers the refusal rather than being silently ignored.
  def test_an_unscoped_neighbour_is_read_and_forces_the_refusal
    wall(300, 0, 0, 4, 0, 3, :east)
    wall(310, 0, 0, 4, 0, 3, :west)
    wall(320, 9, 0, 4, 0, 3, :east)
    author
    scoped = all_references.select { |reference| [[300], [320]].include?(reference.fetch("zone_path")) }

    result = solve(scoped)

    assert_equal %w[refused scope.incomplete none], result.values_at("status", "code", "effect")
  end

  def test_coplanar_faces_pointing_the_same_way_are_reported_as_overlapping_zones
    wall(400, 0, 0, 4, 0, 3, :east)
    wall(410, 0, 2, 6, 0, 3, :east)
    author

    result = solve(all_references)

    assert_equal "completed", result.fetch("status")
    assert_equal ["adjacency.overlapping_zones"], finding_codes(result)
    assert_empty boundary_conditions.compact.reject { |value| value == "Outdoors" }
  end

  def test_a_sliver_overlap_is_reported_and_pairs_nothing
    wall(500, 0, 0, 4, 0, 3, :east)
    wall(510, 0, 3.999, 8, 0, 3, :west)
    author

    result = solve(all_references)

    assert_equal ["adjacency.sliver_skipped"], finding_codes(result)
    assert_empty result.dig("value", "pair_ids")
  end

  def test_a_partial_overlap_cuts_both_faces_and_pairs_only_the_shared_part
    wall(600, 0, 0, 4, 0, 3, :east)
    wall(610, 0, 2, 6, 0, 3, :west)
    author

    result = solve(all_references)

    assert_equal %w[completed committed], result.values_at("status", "effect")
    assert_equal 1, result.dig("value", "pair_ids").length
    assert_equal 4, faces.length
    shared, rest = faces.partition { |face| face.dig("values", "boundary_condition") == "Surface" }

    assert_equal 2, shared.length
    assert(shared.all? { |face| (face.fetch("area_m2") - 6.0).abs < 1.0e-6 })
    # The unpaired remainder keeps the classification it already had.
    assert_equal %w[Outdoors Outdoors], rest.map { |face| face.dig("values", "boundary_condition") }
    assert(rest.all? { |face| (face.fetch("area_m2") - 6.0).abs < 1.0e-6 })
  end

  # M4: the shared pieces become Surface, which carries no Attached-zone reference; the remainders
  # keep the AttachedZone boundary and its reference.
  def test_a_partial_overlap_with_one_attached_zone_face_pairs_without_the_reference
    assert_attached_zone_partial_pair(%i[first])
  end

  def test_a_partial_overlap_of_two_attached_zone_faces_pairs_without_the_reference
    assert_attached_zone_partial_pair(%i[first last])
  end

  def test_the_new_pair_is_reciprocal_and_reads_current
    wall(620, 0, 0, 4, 0, 3, :east)
    wall(630, 0, 2, 6, 0, 3, :west)
    author
    solve(all_references)

    shared = faces.select { |face| face.dig("values", "boundary_condition") == "Surface" }
    envelopes = shared.map { |face| face.dig("values", "adjacency") }

    assert_equal %w[current current], shared.map { |face| face.fetch("adjacency_state") }
    assert_equal 1, envelopes.map { |envelope| envelope.fetch("pair_id") }.uniq.length
    assert_equal shared.last.dig("reference", "entity_id"), envelopes.first.dig("counterpart", "entity_id")
    assert_equal shared.first.dig("reference", "entity_id"), envelopes.last.dig("counterpart", "entity_id")
  end

  # The registered rule keeps a reference to a shared catalog record; an untyped Face id is a
  # literal marker and is not inferred as a reference.
  def test_split_carries_registered_external_references_and_literal_metadata
    register_copy_extension
    store_external_reference
    wall(640, 0, 0, 4, 0, 3, :east)
    wall(650, 0, 2, 6, 0, 3, :west)
    author
    original = faces.find { |face| face.dig("reference", "zone_path") == [640] }
    original_id = original.dig("reference", "entity_id")
    entity = @model.entities.to_a.find { |candidate| candidate.persistent_id == 640 }.entities.to_a.first
    store = PhComposer::Zones::Faces::FACE_STORE
    external_id = "atz_000000000001"
    envelope = COPY_EXTENSION.envelope("external_id" => external_id, "marker" => original_id)
    store.write(entity, store.read(entity).merge("user_data" => { "firm.note" => original_id },
                                                 "extension_data" => { COPY_EXTENSION.namespace => envelope }))

    result = solve(all_references)

    pieces = faces.select { |face| face.dig("reference", "zone_path") == [640] }

    assert_equal %w[completed committed], result.values_at("status", "effect")
    assert_equal 2, pieces.length
    assert_includes pieces.map { |face| face.dig("reference", "entity_id") }, original_id
    assert(pieces.all? { |face| face.fetch("user_data") == { "firm.note" => original_id } })
    pieces.each do |face|
      assert_equal external_id, face.dig("extension_data", COPY_EXTENSION.namespace, "payload", "external_id")
      assert_equal original_id, face.dig("extension_data", COPY_EXTENSION.namespace, "payload", "marker")
    end
  end

  def test_partial_split_refuses_unavailable_references_before_any_cut_or_pair
    wall(642, 0, 0, 4, 0, 3, :east)
    wall(652, 0, 2, 6, 0, 3, :west)
    author
    entity = @model.entities.to_a.find { |candidate| candidate.persistent_id == 642 }.entities.to_a.first
    store = PhComposer::Zones::Faces::FACE_STORE
    before = store.read(entity)
    store.write(entity, before.merge("extension_data" => {
      COPY_EXTENSION.namespace => COPY_EXTENSION.envelope("external_id" => "atz_000000000001",
                                                          "marker" => before.fetch("id"))
    }))
    snapshot = faces
    params = { "zones" => all_references }

    preview = API.preview(:context => @context, :name => "ph_composer.zones.solve_adjacency", :params => params)
    result = solve(all_references)

    assert_equal %w[refused copy.rule_missing none], preview.values_at("status", "code", "effect")
    assert_equal %w[refused copy.rule_missing none], result.values_at("status", "code", "effect")
    assert_equal snapshot, faces
    assert_equal 2, faces.length
  end

  def test_an_uncut_face_keeps_unavailable_extension_data
    wall(644, 0, 0, 6, 0, 4, :east)
    wall(654, 0, 1, 5, 1, 3, :west)
    author
    entity = @model.entities.to_a.find { |candidate| candidate.persistent_id == 654 }.entities.to_a.first
    store = PhComposer::Zones::Faces::FACE_STORE
    old_id = store.read(entity).fetch("id")
    envelope = COPY_EXTENSION.envelope("external_id" => "atz_000000000001", "marker" => old_id)
    store.write(entity, store.read(entity).merge("extension_data" => { COPY_EXTENSION.namespace => envelope }))

    result = solve(all_references)

    assert_equal %w[completed committed], result.values_at("status", "effect")
    assert_equal envelope, store.read(entity).dig("extension_data", COPY_EXTENSION.namespace)
  end

  def test_split_refuses_invalid_registered_extension_data
    envelope = COPY_EXTENSION.envelope("external_id" => "atz_000000000001")
    envelope["references"] = []
    assert_split_copy_refusal(COPY_EXTENSION, envelope, "extension.invalid")
  end

  def test_split_refuses_outdated_registered_extension_data
    extension = PhComposer::Records::Extension.new(
      :namespace => "test.fixture.old_copy", :schema_version => 2,
      :migrations => { 1 => ->(payload) { payload } }
    )
    envelope = { "schema_version" => 1, "payload" => {}, "references" => [], "export_relevance" => "unknown" }
    assert_split_copy_refusal(extension, envelope, "copy.rule_missing", "outdated")
  end

  def test_split_refuses_unsupported_registered_extension_data
    envelope = COPY_EXTENSION.envelope("external_id" => "atz_000000000001")
    envelope["schema_version"] = 9
    assert_split_copy_refusal(COPY_EXTENSION, envelope, "copy.rule_missing", "unsupported")
  end

  def test_split_refuses_an_installed_extension_with_a_refuse_copy_rule
    extension = PhComposer::Records::Extension.new(
      :namespace => "test.fixture.refused_copy", :schema_version => 1, :copy => :refuse
    )
    assert_split_copy_refusal(extension, extension.envelope("note" => "keep"), "copy.rule_missing", "understood")
  end

  def test_split_refuses_a_missing_declared_catalog_reference
    envelope = COPY_EXTENSION.envelope("external_id" => "atz_000000000001")
    assert_split_copy_refusal(COPY_EXTENSION, envelope, "reference.invalid")
  end

  def test_a_shared_region_wholly_inside_a_wall_is_cut_out_of_it
    wall(660, 0, 0, 6, 0, 4, :east)
    wall(670, 0, 1, 5, 1, 3, :west)
    author

    result = solve(all_references)

    assert_equal "completed", result.fetch("status")
    shared = faces.select { |face| face.dig("values", "boundary_condition") == "Surface" }

    assert_equal 2, shared.length
    assert(shared.all? { |face| (face.fetch("area_m2") - 8.0).abs < 1.0e-6 })
    larger = faces.find do |face|
      face.dig("reference", "zone_path") == [660] && face.dig("values", "boundary_condition") == "Outdoors"
    end

    assert_in_delta 24.0 - 8.0, larger.fetch("area_m2")
  end

  def test_undo_reverts_the_cut_and_the_records_together
    wall(680, 0, 0, 4, 0, 3, :east)
    wall(690, 0, 2, 6, 0, 3, :west)
    author
    solve(all_references)

    @model.undo

    assert_equal 2, faces.length
    assert_equal %w[Outdoors Outdoors], boundary_conditions
    assert(faces.all? { |face| (face.fetch("area_m2") - 12.0).abs < 1.0e-6 })
  end

  def test_a_failure_cutting_the_second_face_leaves_neither_face_cut
    wall(692, 0, 0, 4, 0, 3, :east)
    wall(694, 0, 2, 6, 0, 3, :west)
    author
    doomed = @model.entities.to_a.find { |entity| entity.persistent_id == 694 }
    doomed.entities.define_singleton_method(:add_face) { |_points| raise IOError, "the host refused the cut" }

    result = solve(all_references)

    assert_equal %w[failed operation.failed rolled_back], result.values_at("status", "code", "effect")
    assert_equal 2, faces.length
    assert(faces.all? { |face| (face.fetch("area_m2") - 12.0).abs < 1.0e-6 })
    assert_equal %w[Outdoors Outdoors], boundary_conditions
  end

  # A copied envelope that does not even name its own Face is not proof of a deleted counterpart.
  def test_cutting_a_face_with_an_unresolvable_pair_refuses_and_writes_nothing
    wall(696, 0, 0, 4, 0, 3, :east)
    wall(698, 0, 2, 6, 0, 3, :west)
    author
    entity = @model.entities.to_a.find { |candidate| candidate.persistent_id == 696 }.entities.to_a.first
    store = PhComposer::Zones::Faces::FACE_STORE
    record = store.read(entity)
    store.write(entity, record.merge(
      "boundary_condition" => "Surface",
      "adjacency" => {
        "schema_version" => 1, "pair_id" => "adj_000000000000",
        "self" => record_reference(record.fetch("id")), "counterpart" => record_reference("fac_000000000000"),
        "self_geometry" => { "digest" => "sha256:x", "area_m2" => 12.0 },
        "counterpart_geometry" => { "digest" => "sha256:y", "area_m2" => 12.0 }
      }
    ))

    result = solve(all_references)

    assert_equal %w[refused adjacency.unresolved none], result.values_at("status", "code", "effect")
    assert_equal 2, faces.length
    assert_equal "Surface", store.read(entity).fetch("boundary_condition")
  end

  def test_a_face_meeting_two_neighbours_is_reported_and_pairs_neither
    wall(700, 0, 0, 4, 0, 3, :east)
    wall(710, 0, 0, 4, 0, 3, :west)
    wall(720, 0, 0, 4, 0, 3, :west)
    author

    result = solve(all_references)

    # The two west-facing walls are also coplanar with each other and point the same way, so the
    # solver has two separate things to say about this model and says both.
    assert_includes finding_codes(result), "adjacency.multiple_neighbours"
    assert_includes finding_codes(result), "adjacency.overlapping_zones"
    assert_empty result.dig("value", "pair_ids")
  end

  def test_two_clean_neighbours_partition_one_face_and_repeat_as_no_op
    wall(702, 0, 0, 12, 0, 3, :east)
    wall(712, 0, 0, 6, 0, 3, :west)
    wall(722, 0, 6, 12, 0, 3, :west)
    author
    original = faces.find { |face| face.dig("reference", "zone_path") == [702] }.dig("reference", "entity_id")
    params = { "zones" => all_references }
    first_preview = API.preview(:context => @context, :name => "ph_composer.zones.solve_adjacency", :params => params)
    second_preview = API.preview(:context => @context, :name => "ph_composer.zones.solve_adjacency", :params => params)

    assert_equal first_preview, second_preview
    result = solve(all_references)

    assert_equal %w[completed committed], result.values_at("status", "effect")
    assert_equal 2, result.dig("value", "pair_ids").length
    assert_equal 4, faces.length
    assert_equal 4, boundary_conditions.count("Surface")
    assert_equal %w[current current current current], faces.map { |face| face.fetch("adjacency_state") }
    assert_includes faces.map { |face| face.dig("reference", "entity_id") }, original
    assert_equal %w[completed none], solve(all_references).values_at("status", "effect")
  end

  def test_separated_neighbours_leave_a_classified_remainder
    wall(704, 0, 0, 12, 0, 3, :east)
    wall(714, 0, 0, 4, 0, 3, :west)
    wall(724, 0, 8, 12, 0, 3, :west)
    author

    result = solve(all_references)

    assert_equal %w[completed committed], result.values_at("status", "effect")
    assert_equal 2, result.dig("value", "pair_ids").length
    assert_equal 5, faces.length
    rest = faces.find { |face| face.dig("values", "boundary_condition") == "Outdoors" }
    assert_equal [704], rest.dig("reference", "zone_path")
    assert_in_delta 12.0, rest.fetch("area_m2")
  end

  def test_three_neighbours_can_cover_one_face
    wall(706, 0, 0, 12, 0, 3, :east)
    wall(716, 0, 0, 4, 0, 3, :west)
    wall(726, 0, 4, 8, 0, 3, :west)
    wall(736, 0, 8, 12, 0, 3, :west)
    author

    result = solve(all_references)

    assert_equal %w[completed committed], result.values_at("status", "effect")
    assert_equal 3, result.dig("value", "pair_ids").length
    assert_equal 6, faces.length
    assert_equal %w[current current current current current current], faces.map { |face| face.fetch("adjacency_state") }
  end

  def test_two_by_two_grid_partitions_contested_faces_on_both_sides
    wall(738, 0, 0, 6, 0, 3, :east)
    wall(748, 0, 6, 12, 0, 3, :east)
    wall(758, 0, 0, 12, 0, 1.5, :west)
    wall(768, 0, 0, 12, 1.5, 3, :west)
    author

    result = solve(all_references)

    assert_equal %w[completed committed], result.values_at("status", "effect")
    assert_equal 4, result.dig("value", "pair_ids").length
    assert_equal 8, faces.length
    assert_equal 8, boundary_conditions.count("Surface")
    assert_equal ["current"], faces.map { |face| face.fetch("adjacency_state") }.uniq
    assert_equal %w[completed none], solve(all_references).values_at("status", "effect")
  end

  def test_overlapping_neighbours_report_without_cutting
    wall(708, 0, 0, 12, 0, 3, :east)
    wall(718, 0, 0, 7, 0, 3, :west)
    wall(728, 0, 5, 12, 0, 3, :west)
    author

    result = solve(all_references)

    assert_includes finding_codes(result), "adjacency.multiple_neighbours"
    assert_empty result.dig("value", "pair_ids")
    assert_equal 3, faces.length
  end

  def test_combined_partition_sliver_is_reported_before_any_cut
    wall(730, 0, 0, 12, 0, 3, :east)
    wall(740, 0, 0, 5, 0, 3, :west)
    wall(750, 0, 5.005, 12, 0, 3, :west)
    author

    result = solve(all_references)

    assert_includes finding_codes(result), "adjacency.multiple_neighbours"
    assert_empty result.dig("value", "pair_ids")
    assert_equal 3, faces.length
  end

  def test_partition_copies_supported_payload_to_all_new_pieces
    register_copy_extension
    store_external_reference
    wall(752, 0, 0, 12, 0, 3, :east)
    wall(762, 0, 0, 4, 0, 3, :west)
    wall(772, 0, 8, 12, 0, 3, :west)
    author
    entity = @model.entities.to_a.find { |zone| zone.persistent_id == 752 }.entities.to_a.first
    store = PhComposer::Zones::Faces::FACE_STORE
    original_id = store.read(entity).fetch("id")
    payload = COPY_EXTENSION.envelope("external_id" => "atz_000000000001", "marker" => original_id)
    store.write(entity, store.read(entity).merge("user_data" => { "firm.note" => original_id },
                                                 "extension_data" => { COPY_EXTENSION.namespace => payload }))

    assert_equal "committed", solve(all_references).fetch("effect")
    pieces = faces.select { |face| face.dig("reference", "zone_path") == [752] }
    assert_equal 3, pieces.length
    assert_includes pieces.map { |face| face.dig("reference", "entity_id") }, original_id
    pieces.each do |face|
      assert_equal original_id, face.dig("user_data", "firm.note")
      assert_equal "atz_000000000001", face.dig("extension_data", COPY_EXTENSION.namespace, "payload", "external_id")
      assert_equal original_id, face.dig("extension_data", COPY_EXTENSION.namespace, "payload", "marker")
    end
  end

  def test_partition_refuses_unsafe_payload_before_any_cut
    wall(754, 0, 0, 12, 0, 3, :east)
    wall(764, 0, 0, 6, 0, 3, :west)
    wall(774, 0, 6, 12, 0, 3, :west)
    author
    entity = @model.entities.to_a.find { |zone| zone.persistent_id == 754 }.entities.to_a.first
    store = PhComposer::Zones::Faces::FACE_STORE
    store.write(entity, store.read(entity).merge("extension_data" => {
      COPY_EXTENSION.namespace => COPY_EXTENSION.envelope("external_id" => "atz_000000000001")
    }))
    snapshot = faces

    preview = API.preview(:context => @context, :name => "ph_composer.zones.solve_adjacency",
                          :params => { "zones" => all_references })
    result = solve(all_references)

    assert_equal %w[refused copy.rule_missing none], preview.values_at("status", "code", "effect")
    assert_equal %w[refused copy.rule_missing none], result.values_at("status", "code", "effect")
    assert_equal snapshot, faces
  end

  def test_partition_failure_on_second_cut_rolls_back_every_face
    wall(756, 0, 0, 12, 0, 3, :east)
    wall(766, 0, 0, 4, 0, 3, :west)
    wall(776, 0, 8, 12, 0, 3, :west)
    author
    snapshot = faces
    zone = @model.entities.to_a.find { |entity| entity.persistent_id == 756 }
    original_add = zone.entities.method(:add_face)
    calls = 0
    zone.entities.define_singleton_method(:add_face) do |points|
      calls += 1
      raise IOError, "the host refused the second cut" if calls == 2

      original_add.call(points)
    end

    result = solve(all_references)

    assert_equal %w[failed operation.failed rolled_back], result.values_at("status", "code", "effect")
    assert_equal snapshot, faces
  end

  def test_a_finding_names_the_zones_it_is_about
    wall(800, 0, 0, 4, 0, 3, :east)
    wall(810, 0, 2, 6, 0, 3, :east)
    author

    finding = solve(all_references).fetch("findings").first

    assert_equal 2, finding.fetch("zones").length
    assert_includes finding.fetch("message"), "Zone 1"
    assert_includes finding.fetch("message"), "Zone 2"
  end

  def test_solving_one_zone_with_no_neighbour_writes_nothing
    wall(900, 0, 0, 4, 0, 3, :east)
    author

    result = solve(all_references)

    assert_equal "none", result.fetch("effect")
    assert_empty result.dig("value", "pair_ids")
  end

  def test_solving_after_a_neighbour_is_deleted_retires_the_survivor_and_preserves_payloads
    left, right = paired_walls
    entity = left.entities.to_a.first
    store = PhComposer::Zones::Faces::FACE_STORE
    before = store.read(entity).merge("user_data" => { "note" => "keep" },
                                      "extension_data" => { "other.ext" => { "payload" => [1, 2] } })
    store.write(entity, before)
    @model.entities.erase_entities(right)

    result = solve(all_references)

    assert_equal %w[completed committed], result.values_at("status", "effect")
    assert_empty result.dig("value", "pair_ids")
    expected = before.reject { |key, _value| %w[adjacency boundary_condition].include?(key) }
    assert_equal expected, store.read(entity)
    @model.undo
    assert_equal before, store.read(@model.entities.to_a.first.entities.to_a.first)
    @model.redo
    assert_equal expected, store.read(@model.entities.to_a.first.entities.to_a.first)
  end

  def test_solving_after_only_the_counterpart_face_is_deleted_retires_the_survivor
    _left, right = paired_walls
    right.entities.erase_entities(right.entities.to_a.first)

    result = solve(all_references)

    assert_equal %w[completed committed], result.values_at("status", "effect")
    assert_equal [nil], boundary_conditions
  end

  def test_separated_pairs_retire_both_ends_and_a_repeat_solve_creates_no_undo_entry
    _left, right = paired_walls
    right.transformation = Geom::Transformation.translation([100, 0, 0])

    result = solve(all_references)

    assert_equal %w[completed committed], result.values_at("status", "effect")
    assert_equal [nil, nil], boundary_conditions
    count = @model.operation_starts.length
    assert_equal "none", solve(all_references).fetch("effect")
    assert_equal count, @model.operation_starts.length
  end

  def test_a_stale_surviving_counterpart_outside_scope_refuses_before_any_write
    _left, right = paired_walls
    right.transformation = Geom::Transformation.translation([100, 0, 0])
    before = faces
    count = @model.operation_starts.length

    result = solve([all_references.first])

    assert_equal %w[refused scope.incomplete none], result.values_at("status", "code", "effect")
    assert_equal before, faces
    assert_equal count, @model.operation_starts.length
  end

  def test_a_duplicated_counterpart_zone_is_ambiguous_even_when_no_geometry_matches
    _left, right = paired_walls
    right.transformation = Geom::Transformation.translation([100, 0, 0])
    wall(930, 9, 0, 4, 0, 3, :west)
    duplicate = @model.entities.to_a.last
    store = PhComposer::Zones::ZONE_STORE
    store.write(duplicate, store.read(duplicate).merge("id" => store.read(right).fetch("id")))
    before = PhComposer::Zones::Faces::FACE_STORE.read(@model.entities.to_a.first.entities.to_a.first)

    result = solve([all_references.first])

    assert_equal %w[refused target.ambiguous none], result.values_at("status", "code", "effect")
    assert_equal before, PhComposer::Zones::Faces::FACE_STORE.read(@model.entities.to_a.first.entities.to_a.first)
  end

  def test_an_exploded_counterpart_is_unresolved_not_deleted
    _left, right = paired_walls
    @model.entities << right.entities.to_a.first
    @model.entities.erase_entities(right)
    before = boundary_conditions

    result = solve(all_references)

    assert_equal %w[refused adjacency.unresolved none], result.values_at("status", "code", "effect")
    assert_equal before, boundary_conditions
  end

  def test_a_deleted_path_with_a_surviving_face_uuid_is_unresolved
    _left, right = paired_walls
    store = PhComposer::Zones::Faces::FACE_STORE
    copied = store.read(right.entities.to_a.first)
    @model.entities.erase_entities(right)
    wall(930, 9, 0, 4, 0, 3, :west)
    store.write(@model.entities.to_a.last.entities.to_a.first, copied)

    result = solve([all_references.first])

    assert_equal %w[refused adjacency.unresolved none], result.values_at("status", "code", "effect")
    assert_equal %w[Surface Surface], boundary_conditions
  end

  def test_a_paired_zone_moved_inside_a_wrapper_is_rebound_only_by_explicit_solve
    left, right = paired_walls
    store = PhComposer::Zones::Faces::FACE_STORE
    left_face = left.entities.to_a.first
    right_face = right.entities.to_a.first
    left_record = store.read(left_face)
    right_record = store.read(right_face)
    wrapper = Sketchup::Group.new(935, Sketchup::Entities.new)
    @model.entities << wrapper
    wrapper.entities << right
    count = @model.operation_starts.length

    rows = faces

    assert_equal [935, 920], rows.find { |row| row.dig("reference", "entity_id") == right_record.fetch("id") }
                                 .dig("reference", "zone_path")
    assert_equal %w[unresolved unresolved], rows.map { |row| row.fetch("adjacency_state") }.sort
    assert_equal [920], store.read(right.entities.to_a.first).dig("adjacency", "self", "zone_path")
    assert_equal count, @model.operation_starts.length

    preview = API.preview(:context => @context, :name => "ph_composer.zones.solve_adjacency",
                          :params => { "zones" => all_references })
    assert_equal "completed", preview.fetch("status")
    assert_equal 2, preview.fetch("affected").count { |entry| entry.fetch("change") == "retired" }
    assert_equal left_record, store.read(left_face)
    assert_equal right_record, store.read(right_face)
    assert_equal count, @model.operation_starts.length

    result = solve(all_references)

    assert_equal %w[completed ok committed], result.values_at("status", "code", "effect")
    assert_equal count + 1, @model.operation_starts.length
    assert_equal %w[current current], faces.map { |row| row.fetch("adjacency_state") }
    assert_equal [935, 920], store.read(right_face).dig("adjacency", "self", "zone_path")
    assert_equal right_record.fetch("id"), store.read(right_face).fetch("id")
    assert_equal left_record.fetch("id"), store.read(left_face).fetch("id")
    assert_equal "none", solve(all_references).fetch("effect")
    assert_equal count + 1, @model.operation_starts.length

    @model.undo
    assert_equal %w[unresolved unresolved], faces.map { |row| row.fetch("adjacency_state") }.sort
    undone_wrapper = @model.entities.to_a.find { |entity| entity.persistent_id == 935 }
    assert_equal right_record, store.read(undone_wrapper.entities.to_a.first.entities.to_a.first)
    @model.redo
    assert_equal %w[current current], faces.map { |row| row.fetch("adjacency_state") }
  end

  def test_an_old_caller_zone_reference_remains_strict_after_reparenting
    _left, right = paired_walls
    old_reference = all_references.find { |reference| reference.fetch("zone_path") == [920] }
    wrapper = Sketchup::Group.new(934, Sketchup::Entities.new)
    @model.entities << wrapper
    wrapper.entities << right
    before = faces
    count = @model.operation_starts.length

    result = solve([old_reference, all_references.first])

    assert_equal %w[refused target.changed none], result.values_at("status", "code", "effect")
    assert_equal before, faces
    assert_equal count, @model.operation_starts.length
  end

  def test_a_split_copy_of_the_local_face_uuid_reads_unresolved
    left, right = paired_walls
    store = PhComposer::Zones::Faces::FACE_STORE
    original = left.entities.to_a.first
    record = store.read(original)
    copied_face = Sketchup::Face.new(936, {},
                                     :points => original.outer_loop.vertices.map(&:position),
                                     :normal => original.normal)
    left.entities << copied_face
    store.write(copied_face, record)
    wrapper = Sketchup::Group.new(937, Sketchup::Entities.new)
    @model.entities << wrapper
    wrapper.entities << left
    count = @model.operation_starts.length

    rows = faces

    assert_equal 3, rows.length
    assert_equal %w[unresolved unresolved unresolved], rows.map { |row| row.fetch("adjacency_state") }
    assert_equal count, @model.operation_starts.length

    result = solve(all_references)

    assert_equal %w[refused target.ambiguous none], result.values_at("status", "code", "effect")
    assert_equal record, store.read(original)
    assert_equal record, store.read(copied_face)
    assert_equal count, @model.operation_starts.length
  end

  def test_an_orphan_copy_of_a_rebound_face_uuid_is_still_ambiguous
    _left, right = paired_walls
    store = PhComposer::Zones::Faces::FACE_STORE
    face = right.entities.to_a.first
    copied = Sketchup::Face.new(944, {}, :points => face.outer_loop.vertices.map(&:position),
                                         :normal => face.normal)
    store.write(copied, store.read(face))
    @model.entities << copied
    wrapper = Sketchup::Group.new(945, Sketchup::Entities.new)
    @model.entities << wrapper
    wrapper.entities << right
    before = store.read(face)
    count = @model.operation_starts.length

    result = solve(all_references)

    assert_equal %w[refused target.ambiguous none], result.values_at("status", "code", "effect")
    assert_equal before, store.read(face)
    assert_equal before, store.read(copied)
    assert_equal count, @model.operation_starts.length
  end

  def test_an_orphan_copy_of_the_unmoved_face_uuid_blocks_path_recovery
    left, right = paired_walls
    store = PhComposer::Zones::Faces::FACE_STORE
    face = left.entities.to_a.first
    copied = Sketchup::Face.new(946, {}, :points => face.outer_loop.vertices.map(&:position),
                                         :normal => face.normal)
    store.write(copied, store.read(face))
    @model.entities << copied
    wrapper = Sketchup::Group.new(947, Sketchup::Entities.new)
    @model.entities << wrapper
    wrapper.entities << right
    before = store.read(face)
    count = @model.operation_starts.length

    result = solve(all_references)

    assert_equal %w[refused target.ambiguous none], result.values_at("status", "code", "effect")
    assert_equal before, store.read(face)
    assert_equal before, store.read(copied)
    assert_equal count, @model.operation_starts.length
  end

  def test_a_recreated_zone_and_face_pid_repair_by_unique_authored_ids
    left, right = paired_walls
    face_store = PhComposer::Zones::Faces::FACE_STORE
    zone_store = PhComposer::Zones::ZONE_STORE
    stamp_store = PhComposer::Zones::STAMP_STORE
    old_face = right.entities.to_a.first
    old_record = face_store.read(old_face)
    payload = { "missing.extension" => { "face_id" => old_record.fetch("id"), "detail" => [1, 2] } }
    preserved = old_record.merge("user_data" => { "note" => "retain" }, "extension_data" => payload)
    face_store.write(old_face, preserved)
    replacement_face = Sketchup::Face.new(939, {},
                                          :points => old_face.outer_loop.vertices.map(&:position),
                                          :normal => old_face.normal)
    face_store.write(replacement_face, preserved)
    stamp_store.write(replacement_face, stamp_store.read(old_face))
    replacement_zone = Sketchup::Group.new(938, Sketchup::Entities.new([replacement_face]))
    zone_store.write(replacement_zone, zone_store.read(right))
    @model.entities.erase_entities(right)
    wrapper = Sketchup::Group.new(940, Sketchup::Entities.new([replacement_zone]))
    @model.entities << wrapper

    assert_equal %w[unresolved unresolved], faces.map { |row| row.fetch("adjacency_state") }.sort
    result = solve(all_references)

    assert_equal %w[completed committed], result.values_at("status", "effect")
    assert_equal %w[current current], faces.map { |row| row.fetch("adjacency_state") }
    after = face_store.read(replacement_face)
    assert_equal [940, 938], after.dig("adjacency", "self", "zone_path")
    assert_equal [939], after.dig("adjacency", "self", "entity_path")
    assert_equal old_record.fetch("id"), after.fetch("id")
    assert_equal preserved.fetch("user_data"), after.fetch("user_data")
    assert_equal payload, after.fetch("extension_data")
    assert_equal "Surface", face_store.read(left.entities.to_a.first).fetch("boundary_condition")
  end

  def test_a_reparented_separated_pair_retires_both_current_occurrences
    _left, right = paired_walls
    right.transformation = Geom::Transformation.translation([100, 0, 0])
    wrapper = Sketchup::Group.new(941, Sketchup::Entities.new)
    @model.entities << wrapper
    wrapper.entities << right
    before = faces

    result = solve(all_references)

    assert_equal %w[completed committed], result.values_at("status", "effect")
    assert_equal [nil, nil], boundary_conditions
    assert_empty result.dig("value", "pair_ids")
    @model.undo
    assert_equal before, faces
    assert_equal %w[Surface Surface], boundary_conditions
  end

  def test_a_reparented_counterpart_outside_scope_still_refuses
    left, right = paired_walls
    right.transformation = Geom::Transformation.translation([100, 0, 0])
    wrapper = Sketchup::Group.new(942, Sketchup::Entities.new)
    @model.entities << wrapper
    wrapper.entities << right
    before = faces
    count = @model.operation_starts.length
    left_reference = all_references.find { |reference| reference.fetch("zone_path") == [left.persistent_id] }

    result = solve([left_reference])

    assert_equal %w[refused scope.incomplete none], result.values_at("status", "code", "effect")
    assert_equal before, faces
    assert_equal count, @model.operation_starts.length
  end

  def test_a_face_moved_to_another_zone_does_not_rebind_its_old_endpoint
    left, right = paired_walls
    right_face = right.entities.to_a.first
    right.entities.delete(right_face)
    left.entities << right_face
    before = PhComposer::Zones::Faces::FACE_STORE.read(right_face)
    count = @model.operation_starts.length

    result = solve(all_references)

    assert_equal %w[refused adjacency.unresolved none], result.values_at("status", "code", "effect")
    assert_equal before, PhComposer::Zones::Faces::FACE_STORE.read(right_face)
    assert_equal count, @model.operation_starts.length
  end

  def test_a_reciprocal_path_corruption_reads_unresolved_even_with_the_same_uuid
    left, right = paired_walls
    store = PhComposer::Zones::Faces::FACE_STORE
    left_record = store.read(left.entities.to_a.first)
    right_face = right.entities.to_a.first
    right_record = store.read(right_face)
    changed = PhComposer::DeepCopy.call(right_record)
    changed.fetch("adjacency").fetch("counterpart")["zone_path"] = [999]
    store.write(right_face, changed)
    count = @model.operation_starts.length

    rows = faces

    assert_equal %w[unresolved unresolved], rows.map { |row| row.fetch("adjacency_state") }
    assert_equal left_record.fetch("id"), changed.dig("adjacency", "counterpart", "entity_id")
    assert_equal count, @model.operation_starts.length

    result = solve(all_references)

    assert_equal %w[refused adjacency.unresolved none], result.values_at("status", "code", "effect")
    assert_equal left_record, store.read(left.entities.to_a.first)
    assert_equal changed, store.read(right_face)
    assert_equal count, @model.operation_starts.length
  end

  def test_failure_after_a_reparented_endpoint_retirement_rolls_back_the_pair
    left, right = paired_walls
    wrapper = Sketchup::Group.new(943, Sketchup::Entities.new)
    @model.entities << wrapper
    wrapper.entities << right
    before = faces
    left.entities.to_a.first.define_singleton_method(:set_attribute) do |dictionary, key, value|
      raise IOError, "the host refused the write" if dictionary == PhComposer::Zones::Faces::FACE_DICTIONARY

      super(dictionary, key, value)
    end

    result = solve(all_references)

    assert_equal %w[failed operation.failed rolled_back], result.values_at("status", "code", "effect")
    assert_equal before, faces
    assert_equal %w[Surface Surface], boundary_conditions
  end

  def test_common_motion_replaces_stale_stamps_and_then_solving_is_a_noop
    left, right = paired_walls
    [left, right].each { |group| group.transformation = Geom::Transformation.translation([100, 0, 0]) }

    result = solve(all_references)

    assert_equal %w[completed committed], result.values_at("status", "effect")
    assert_equal %w[current current], faces.map { |face| face.fetch("adjacency_state") }
    count = @model.operation_starts.length
    assert_equal "none", solve(all_references).fetch("effect")
    assert_equal count, @model.operation_starts.length
  end

  def test_partial_repair_retires_the_old_pair_and_leaves_remainders_unclassified
    _left, right = paired_walls
    right.transformation = Geom::Transformation.translation([0, 2 / 0.0254, 0])

    result = solve(all_references)

    assert_equal %w[completed committed], result.values_at("status", "effect")
    assert_equal 4, faces.length
    assert_equal 2, boundary_conditions.count("Surface")
    assert_equal 2, boundary_conditions.count(nil)
    assert_equal %w[current current], faces.filter_map { |face| face["adjacency_state"] }
  end

  def test_a_failed_cut_after_retirement_rolls_back_both_old_pair_records_and_all_geometry
    _left, right = paired_walls
    right.transformation = Geom::Transformation.translation([0, 2 / 0.0254, 0])
    before = faces
    right.entities.define_singleton_method(:add_face) { |_points| raise IOError, "the host refused the cut" }

    result = solve(all_references)

    assert_equal %w[failed operation.failed rolled_back], result.values_at("status", "code", "effect")
    assert_equal before, faces
    assert_equal %w[Surface Surface], boundary_conditions
  end

  def test_retirement_preview_is_read_only_and_lists_both_endpoints
    _left, right = paired_walls
    right.transformation = Geom::Transformation.translation([100, 0, 0])
    before = faces
    count = @model.operation_starts.length

    preview = API.preview(:context => @context, :name => "ph_composer.zones.solve_adjacency",
                          :params => { "zones" => all_references })

    assert_equal "completed", preview.fetch("status")
    assert_equal 2, preview.fetch("affected").count { |entry| entry.fetch("change") == "retired" }
    assert_equal before, faces
    assert_equal count, @model.operation_starts.length
  end

  def test_a_failure_writing_the_second_retirement_rolls_back_the_first
    left, right = paired_walls
    right.transformation = Geom::Transformation.translation([100, 0, 0])
    before = faces
    # Retirement writes the counterpart first, then the initiating Face.
    left.entities.to_a.first.define_singleton_method(:set_attribute) do |dictionary, key, value|
      raise IOError, "the host refused the write" if dictionary == PhComposer::Zones::Faces::FACE_DICTIONARY

      super(dictionary, key, value)
    end

    result = solve(all_references)

    assert_equal %w[failed operation.failed rolled_back], result.values_at("status", "code", "effect")
    assert_equal before, faces
  end

  def test_solve_new_pieces_have_resolvable_declared_self_references
    extension = entity_link_extension
    register_extension(extension)
    wall(660, 0, 0, 4, 0, 3, :east)
    wall(670, 0, 2, 6, 0, 3, :west)
    author
    store = PhComposer::Zones::Faces::FACE_STORE
    @model.entities.to_a.each do |group|
      face = group.entities.to_a.first
      before = store.read(face)
      store.write(face, before.merge("extension_data" => {
        extension.namespace => extension.envelope("face_id" => before.fetch("id"))
      }))
    end

    result = solve(all_references)

    assert_equal %w[completed committed], result.values_at("status", "effect")
    engine = PhComposer::Records::Engine.new(@model, PhComposer::Registry.current.catalog)
    @model.entities.to_a.each do |group|
      group.entities.to_a.grep(Sketchup::Face).each do |face|
        record = store.read(face)
        id = record.dig("extension_data", extension.namespace, "payload", "face_id")
        assert_equal record.fetch("id"), id
        assert_equal record, engine.resolve_reference(PhComposer::Zones::Faces::REFERENCE_KIND, id).record
      end
    end
  end

  def test_no_survivor_with_catalog_incoming_reference_rolls_back_all_native_cuts
    wall(680, 0, 0, 4, 0, 3, :east)
    wall(690, 0, 2, 6, 0, 3, :west)
    author
    extension = entity_link_extension
    old_id = faces.first.fetch("reference").fetch("entity_id")
    store_external_reference
    kind = PhComposer::Zones::Faces::AttachedZone::RECORD_KIND
    record = kind.store.read(@model, "atz_000000000001")
    kind.store.write(@model, record.merge("extension_data" => {
      "unavailable.incoming" => extension.envelope("face_id" => old_id)
    }))
    before = faces

    result = without_native_survivor { solve(all_references) }

    assert_equal %w[failed operation.failed rolled_back], result.values_at("status", "code", "effect")
    assert_equal "reference.in_use", result.dig("detail", "cause")
    assert_includes result.fetch("message"), old_id
    assert_includes result.fetch("message"), "No changes were retained."
    assert_equal before, faces
    assert_equal old_id, kind.store.read(@model, record.fetch("id")).dig(
      "extension_data", "unavailable.incoming", "payload", "face_id"
    )
  end

  # CAT: the cut checks removed identities against the catalog its request prepared with, not
  # whatever registry is current. Here only the dispatching registry knows the kind that refers to
  # the Face, so a check against Registry.current would let the cut commit.
  def test_no_survivor_cut_checks_the_dispatching_registrys_catalog
    wall(682, 0, 0, 4, 0, 3, :east)
    wall(692, 0, 2, 6, 0, 3, :west)
    author
    old_id = faces.first.fetch("reference").fetch("entity_id")
    reference = PhComposer::Records::Reference.new(:key => "face_id", :cardinality => "one", :required => true,
                                                   :target_kind => PhComposer::Zones::Faces::REFERENCE_KIND)
    link = PhComposer::Records::RecordKind.new(:id => "test.alternate.link", :label => "Link", :schema_version => 1,
                                               :id_prefix => "lnk", :fields => [reference])
    link.store.write(@model, "id" => "lnk_000000000001", "schema_version" => 1, "face_id" => old_id)
    feature = Module.new do
      define_singleton_method(:install) do |registry|
        registry.feature("test.alternate", :contract_version => 1).record_kind(link)
      end
    end
    alternate = PhComposer::Registry.new
    alternate.publish(alternate.stage([PhComposer::Zones, feature]))
    before = faces
    request = { "sequence" => @sequence += 1, "expected_revision" => @session.revision }

    result = without_native_survivor do
      PhComposer::Dispatch.new(alternate).invoke(@context, "ph_composer.zones.solve_adjacency",
                                                 { "zones" => all_references }, request)
    end

    assert_equal %w[failed rolled_back], result.values_at("status", "effect")
    assert_equal "reference.in_use", result.dig("detail", "cause")
    assert_equal before, faces
  ensure
    # The second registry's host-event subscriptions would otherwise outlive the test.
    alternate&.unsubscribe_all
  end

  def test_no_survivor_with_entity_incoming_reference_rolls_back_all_native_cuts
    wall(700, 0, 0, 4, 0, 3, :east)
    wall(710, 0, 2, 6, 0, 3, :west)
    author
    group = @model.entities.to_a.first
    store = PhComposer::Zones::ZONE_STORE
    before_record = store.read(group)
    id = faces.first.fetch("reference").fetch("entity_id")
    store.write(group, before_record.merge("extension_data" => {
      "unavailable.incoming" => entity_link_extension.envelope("face_id" => id)
    }))
    before = faces

    result = without_native_survivor { solve(all_references) }

    assert_equal %w[failed operation.failed rolled_back], result.values_at("status", "code", "effect")
    assert_equal before, faces
  end

  def test_no_survivor_without_incoming_references_keeps_new_piece_policy
    wall(720, 0, 0, 4, 0, 3, :east)
    wall(730, 0, 2, 6, 0, 3, :west)
    author
    old_ids = faces.map { |face| face.fetch("reference").fetch("entity_id") }

    result = without_native_survivor { solve(all_references) }

    assert_equal %w[completed committed], result.values_at("status", "effect")
    assert_empty faces.map { |face| face.fetch("reference").fetch("entity_id") } & old_ids
    assert_equal 4, faces.length
  end

  def test_no_survivor_with_opaque_incoming_payload_rolls_back
    wall(740, 0, 0, 4, 0, 3, :east)
    wall(750, 0, 2, 6, 0, 3, :west)
    author
    group = @model.entities.to_a.first
    store = PhComposer::Zones::ZONE_STORE
    store.write(group, store.read(group).merge("extension_data" => { "opaque.fixture" => { "payload" => {} } }))
    before = faces

    result = without_native_survivor { solve(all_references) }

    assert_equal %w[failed operation.failed rolled_back], result.values_at("status", "code", "effect")
    assert_equal before, faces
  end

  private

  def entity_link_extension
    PhComposer::Records::Extension.new(
      :namespace => "test.fixture.entity_link", :schema_version => 1,
      :references => [{ "path" => "$.face_id", "target_kind" => PhComposer::Zones::Faces::REFERENCE_KIND,
                        "cardinality" => "one" }]
    )
  end

  # Simulate the native answer where every cut piece has a new persistent id. Production code
  # still owns the complete transaction, new records and rollback; no geometry result is mocked.
  def without_native_survivor
    splitter = PhComposer::Zones::FaceSplit
    original = splitter.method(:apply)
    splitter.define_singleton_method(:apply) do |occurrence, polygon|
      original.call(occurrence, polygon).each do |piece|
        id = piece.persistent_id + 1_000_000
        piece.entity.instance_variable_set(:@persistent_id, id)
        piece.persistent_id = id
      end
    end
    yield
  ensure
    splitter.define_singleton_method(:apply, original)
  end

  def register_copy_extension
    register_extension(COPY_EXTENSION)
  end

  def register_extension(extension)
    fixture = Module.new do
      define_singleton_method(:install) do |registry|
        registry.feature("test.fixture", :contract_version => 1).extension(extension)
      end
    end
    PhComposer::Registry.install([fixture])
  end

  def store_external_reference
    kind = PhComposer::Zones::Faces::AttachedZone::RECORD_KIND
    kind.store.write(@model, "id" => "atz_000000000001", "schema_version" => 1,
                             "name" => "Garage", "kind" => "garage", "temperature_reduction_factor" => 0.95)
  end

  def assert_split_copy_refusal(extension, envelope, code, status = nil)
    register_extension(extension)
    wall(648, 0, 0, 4, 0, 3, :east)
    wall(658, 0, 2, 6, 0, 3, :west)
    author
    entity = @model.entities.to_a.find { |candidate| candidate.persistent_id == 648 }.entities.to_a.first
    store = PhComposer::Zones::Faces::FACE_STORE
    store.write(entity, store.read(entity).merge("extension_data" => { extension.namespace => envelope }))
    snapshot = faces
    params = { "zones" => all_references }

    preview = API.preview(:context => @context, :name => "ph_composer.zones.solve_adjacency", :params => params)
    result = solve(all_references)

    assert_equal ["refused", code, "none"], preview.values_at("status", "code", "effect")
    assert_equal ["refused", code, "none"], result.values_at("status", "code", "effect")
    assert_equal status, result.dig("detail", "status") if status
    assert_equal snapshot, faces
    assert_equal 2, faces.length
  end

  # M4: the shared pieces become Surface, which carries no Attached-zone reference; the remainders
  # keep the AttachedZone boundary and its reference. Repeat Solve is a no-op and Undo is exact.
  def assert_attached_zone_partial_pair(attached)
    wall(660, 0, 0, 4, 0, 3, :east)
    wall(670, 0, 2, 6, 0, 3, :west)
    author
    attached_id = invoke("ph_composer.zones.faces.attached_zone.save",
                         { "values" => { "name" => "Garage", "kind" => "garage" } }).dig("value", "id")
    attached.each do |which|
      invoke("ph_composer.zones.faces.classify", {
        "faces" => [faces.public_send(which).fetch("reference")],
        "intent" => { "boundary_condition" => { "mode" => "set", "value" => "AttachedZone" },
                      "attached_zone_id" => { "mode" => "set", "value" => attached_id } }
      })
    end
    before = faces

    result = solve(all_references)

    assert_equal %w[completed committed], result.values_at("status", "effect")
    shared, rest = faces.partition { |face| face.dig("values", "boundary_condition") == "Surface" }
    assert_equal %w[current current], shared.map { |face| face.fetch("adjacency_state") }
    assert(shared.none? { |face| face.fetch("values").key?("attached_zone_id") })
    assert_equal attached.length, rest.count { |face| face.dig("values", "attached_zone_id") == attached_id }
    assert_equal attached.length, rest.count { |face| face.dig("values", "boundary_condition") == "AttachedZone" }

    operation_count = @model.operations.length
    assert_equal %w[completed none], solve(all_references).values_at("status", "effect")
    assert_equal operation_count, @model.operations.length

    @model.undo
    assert_equal before, faces
  end

  def paired_walls
    wall(910, 0, 0, 4, 0, 3, :east)
    wall(920, 0, 0, 4, 0, 3, :west)
    author
    assert_equal "committed", solve(all_references).fetch("effect")
    @model.entities.to_a
  end

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end

  def solve(references)
    invoke("ph_composer.zones.solve_adjacency", { "zones" => references })
  end

  def finding_codes(result)
    result.fetch("findings").map { |finding| finding.fetch("code") }.uniq
  end

  def zones_value
    API.query(:context => @context, :name => "ph_composer.zones.list").dig("value", "zones")
  end

  def all_references
    zones_value.map { |zone| zone.fetch("reference") }
  end

  def faces
    API.query(:context => @context, :name => "ph_composer.zones.faces.list").dig("value", "faces")
  end

  def boundary_conditions
    faces.map { |face| face.dig("values", "boundary_condition") }
  end

  # One Zone holding one vertical wall in the y-z plane at x = offset.
  def wall(persistent_id, offset, low, high, bottom, top, facing)
    points = [[offset, low, bottom], [offset, high, bottom], [offset, high, top], [offset, low, top]]
    points = points.reverse if facing == :west
    face = Sketchup::Face.new(@next_id += 1, {}, :points => points.map { |point| metres(point) },
                                                 :normal => Geom::Vector3d.new(facing == :east ? 1 : -1, 0, 0))
    @model.entities << Sketchup::Group.new(persistent_id, Sketchup::Entities.new([face]))
    invoke("ph_composer.zones.make", { "parent_path" => [], "entity_ids" => [persistent_id] })
  end

  def author
    invoke("ph_composer.zones.faces.classify", {
      "faces" => faces.map { |face| face.fetch("reference") },
      "intent" => { "face_type" => { "mode" => "set", "value" => "Wall" },
                    "boundary_condition" => { "mode" => "set", "value" => "Outdoors" } },
      "expected_values" => {}
    })
  end

  def record_reference(entity_id)
    { "zone_id" => "zon_000000000000", "zone_path" => [1], "entity_path" => [2], "entity_id" => entity_id }
  end

  def metres(point)
    Geom::Point3d.new(*point.map { |value| value / 0.0254 })
  end
end
