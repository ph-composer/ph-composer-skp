# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/assembly_assignment_fixtures"

class AssemblyAssignmentTest < PhComposerTestCase
  include AssemblyAssignmentFixtures

  def setup
    super
    assignment_setup
  end

  def test_classify_set_keep_clear_preserves_surface_pairs_and_metadata
    rows = assignment_pair(100)
    id = assignment_assembly("Wall", "type" => "Floor", "exterior_condition" => "Ground")
    entity = @model.entities.to_a.first.entities.to_a.first
    before = STORE.read(entity)
    before["user_data"] = { "firm.note" => ["retain"] }
    before["extension_data"] = { "other.feature" => { "schema_version" => 1, "payload" => { "x" => 7 } } }
    STORE.write(entity, before)
    result = assignment_classify([rows.first], assembly_intent(id))
    assert_equal "committed", result.fetch("effect"), result.inspect
    assert_equal before.merge("assembly_id" => id), STORE.read(entity)
    assert_equal rows.last.fetch("values").merge("assembly_id" => id, "assembly_reversed" => true),
                 assignment_faces.last.fetch("values"), "the counterpart holds the pair's Assembly reversed"
    keep = assignment_classify([assignment_faces.first], assembly_intent(nil, "keep"))
    assert_equal "none", keep.fetch("effect")
    clear = assignment_classify([assignment_faces.first], assembly_intent(nil, "clear"))
    assert_equal "committed", clear.fetch("effect")
    assert_equal before, STORE.read(entity)
    assert_equal rows.last.fetch("values"), assignment_faces.last.fetch("values")
    assert assignment_faces.all? { |row| row.fetch("adjacency_state") == "current" }
  end

  def test_hints_fill_only_absent_fields_and_explicit_values_or_clear_win
    assignment_zone(200, 3)
    id = assignment_assembly("Hint", "type" => "Wall", "exterior_condition" => "AttachedZone")
    rows = assignment_faces
    assert_equal "completed", assignment_classify([rows.first], assembly_intent(id)).fetch("status")
    assert_equal({ "assembly_id" => id, "face_type" => "Wall", "boundary_condition" => "AttachedZone" },
                 assignment_faces.first.fetch("values"))
    intent = assembly_intent(id).merge("face_type" => { "mode" => "set", "value" => "Floor" },
                                       "boundary_condition" => { "mode" => "clear" })
    assert_equal "completed", assignment_classify([rows[1]], intent).fetch("status")
    assert_equal({ "assembly_id" => id, "face_type" => "Floor" }, assignment_faces[1].fetch("values"))
    blank = assignment_assembly("Blank")
    assert_equal "completed", assignment_classify([rows.last], assembly_intent(blank)).fetch("status")
    assert_equal({ "assembly_id" => blank }, assignment_faces.last.fetch("values"))
  end

  def test_reassign_changes_only_assembly_and_undoes_once_noop_has_no_undo
    rows = assignment_pair(300)
    id = assignment_assembly("First", "type" => "Floor", "exterior_condition" => "Ground")
    result = assignment_invoke("#{FACE_PREFIX}.assign_assembly", assignment_params(rows, id))
    assert_equal %w[completed committed], result.values_at("status", "effect"), result.inspect
    assigned = rows.map { |row| row.fetch("values").merge("assembly_id" => id) }
    assigned.last["assembly_reversed"] = true
    assert_equal assigned, assignment_faces.map { |row| row.fetch("values") }
    before_operations = @model.operations.length
    noop = assignment_invoke("#{FACE_PREFIX}.assign_assembly", assignment_params(assignment_faces, id))
    assert_equal "none", noop.fetch("effect")
    assert_equal before_operations, @model.operations.length
    @model.undo
    assert_equal rows.map { |row| row.fetch("values") }, assignment_faces.map { |row| row.fetch("values") }
    @model.redo
    clear = assignment_invoke("#{FACE_PREFIX}.assign_assembly", assignment_params(assignment_faces, nil))
    assert_equal "committed", clear.fetch("effect")
    assert_equal rows.map { |row| row.fetch("values") }, assignment_faces.map { |row| row.fetch("values") }
  end

  def test_stale_guard_refuses_all_targets_and_limit_is_atomic
    assignment_zone(500, 251)
    id = assignment_assembly("Limit")
    rows = assignment_faces
    params = assignment_params(rows.first(250), id)
    params["targets"].last["expected_values"] = { "face_type" => "Floor" }
    stale = assignment_invoke("#{FACE_PREFIX}.assign_assembly", params)
    assert_equal %w[refused target.changed none], stale.values_at("status", "code", "effect")
    assert assignment_faces.all? { |row| row.fetch("values").empty? }
    large = assignment_invoke("#{FACE_PREFIX}.assign_assembly", assignment_params(rows, id))
    assert_equal %w[refused gesture.too_large none], large.values_at("status", "code", "effect")
    accepted = assignment_invoke("#{FACE_PREFIX}.assign_assembly", assignment_params(rows.first(250), id))
    assert_equal %w[completed committed], accepted.values_at("status", "effect"), accepted.inspect
    assert_equal 250, accepted.fetch("affected").length
  end

  def test_duplicate_targets_deduplicate_but_conflicting_identity_or_guards_refuse
    assignment_zone(700)
    id = assignment_assembly("Duplicate targets")
    params = assignment_params(assignment_faces, id)
    params["targets"] << PhComposer::DeepCopy.call(params.fetch("targets").first)
    duplicate = assignment_invoke("#{FACE_PREFIX}.assign_assembly", params)
    assert_equal "committed", duplicate.fetch("effect")
    assert_equal 1, duplicate.fetch("affected").length
    current = assignment_params(assignment_faces, nil)
    conflicting = PhComposer::DeepCopy.call(current.fetch("targets").first)
    conflicting["reference"]["entity_id"] = "fac_000000000099"
    current["targets"] << conflicting
    refused = assignment_invoke("#{FACE_PREFIX}.assign_assembly", current)
    assert_equal %w[refused params.invalid none], refused.values_at("status", "code", "effect")
    assert_equal id, assignment_faces.first.dig("values", "assembly_id")
  end

  def test_assignment_and_reference_survive_save_reopen_with_metadata
    _group, entities = assignment_zone(750)
    id = assignment_assembly("Saved")
    assignment_classify(assignment_faces, "face_type" => { "mode" => "set", "value" => "Wall" },
                                          "boundary_condition" => { "mode" => "set", "value" => "Outdoors" })
    record = STORE.read(entities.first)
    record["user_data"] = { "firm.note" => ["persist"] }
    STORE.write(entities.first, record)
    assignment_invoke("#{FACE_PREFIX}.assign_assembly", assignment_params(assignment_faces, id))
    @model.save("/tmp/ph-composer-assignment.skp")
    Sketchup.open_file("/tmp/ph-composer-assignment.skp")
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    row = assignment_faces.first
    assert_equal id, row.dig("values", "assembly_id")
    assert_equal record.fetch("id"), row.dig("reference", "entity_id")
    assert_equal record.fetch("user_data"), row.fetch("user_data")
    assert_equal "resolved", row.fetch("assembly_state")
    assert_equal id, assignment_query("#{ASSEMBLY_PREFIX}.all").fetch("records").first.fetch("id")
  end

  def test_assignment_host_failure_rolls_back_and_preview_digest_is_stable
    _group, entities = assignment_zone(800, 2)
    id = assignment_assembly("Atomic")
    params = assignment_params(assignment_faces, id)
    preview = API.preview(:context => @context, :name => "#{FACE_PREFIX}.assign_assembly", :params => params)
    assert_equal "completed", preview.fetch("status"), preview.inspect
    assert entities.all? { |entity| STORE.read(entity).nil? }
    accepted = assignment_invoke("#{FACE_PREFIX}.assign_assembly", params, preview.fetch("proposal_digest"))
    assert_equal "committed", accepted.fetch("effect"), accepted.inspect
    assert_equal preview.fetch("proposal_digest"), accepted.fetch("proposal_digest")
    @model.undo
    current = @model.entities.to_a.first.entities.to_a
    current.last.define_singleton_method(:set_attribute) do |dictionary, key, value|
      raise "Injected Face write failure" if dictionary == PhComposer::Zones::Faces::FACE_DICTIONARY

      super(dictionary, key, value)
    end
    failed = assignment_invoke("#{FACE_PREFIX}.assign_assembly", assignment_params(assignment_faces, id))
    assert_equal %w[failed operation.failed rolled_back], failed.values_at("status", "code", "effect")
    assert assignment_faces.all? { |row| row.fetch("values").empty? }
  end

  def test_nested_shared_group_refuses_before_writing
    group, = assignment_zone(900, 2, :nested => true)
    shared = Sketchup::Group.new(950, group.entities.to_a.first.entities)
    group.entities << shared
    id = assignment_assembly("Shared")
    result = assignment_invoke("#{FACE_PREFIX}.assign_assembly", assignment_params(assignment_faces.first(1), id))
    assert_equal %w[refused target.shared_definition none], result.values_at("status", "code", "effect")
    assert assignment_faces.all? { |row| row.fetch("values").empty? }
  end

  def test_missing_reference_refuses_writes_and_reads_dangling
    _group, entities = assignment_zone(1000)
    id = "asm_000000000001"
    result = assignment_classify(assignment_faces, assembly_intent(id))
    assert_equal %w[refused reference.invalid none], result.values_at("status", "code", "effect")
    STORE.write(entities.first, "id" => "fac_000000000001", "schema_version" => 1,
                                "assembly_id" => id, "face_type" => "Wall", "boundary_condition" => "Outdoors")
    row = assignment_faces.first
    assert_equal "dangling", row.fetch("assembly_state")
    assert_equal "incomplete", row.fetch("state")
    assert_equal id, row.dig("values", "assembly_id")
  end
end
