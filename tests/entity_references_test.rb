# frozen_string_literal: true

require_relative "test_helper"

class EntityReferencesTest < PhComposerTestCase
  R = PhComposer::Records
  FACE = PhComposer::Zones::Faces
  ZONES = PhComposer::Zones
  ATTACHED = FACE::AttachedZone::RECORD_KIND
  EXTENSION = R::Extension.new(
    :namespace => "test.references.links", :schema_version => 1,
    :references => [
      { "path" => "$.self", "target_kind" => FACE::REFERENCE_KIND, "cardinality" => "one" },
      { "path" => "$.peers", "target_kind" => FACE::REFERENCE_KIND, "cardinality" => "many" },
      { "path" => "$.owner", "target_kind" => ZONES::REFERENCE_KIND, "cardinality" => "one" },
      { "path" => "$.external_face", "target_kind" => FACE::REFERENCE_KIND, "cardinality" => "one" },
      { "path" => "$.external_zone", "target_kind" => ZONES::REFERENCE_KIND, "cardinality" => "one" },
      { "path" => "$.catalog", "target_kind" => ATTACHED.id, "cardinality" => "one" }
    ]
  )

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = PhComposer::API.connect(:session_id => @session.id)
    extension = EXTENSION
    fixture = Module.new do
      define_singleton_method(:install) do |registry|
        registry.feature("test.references", :contract_version => 1).extension(extension)
      end
    end
    PhComposer::Registry.install([fixture])
    @engine = R::Engine.new(@model, PhComposer::Registry.current.catalog)
  end

  def test_registered_entity_targets_are_read_only_detached_and_strict
    zone, faces = zone(100, [101])
    before = FACE::FACE_STORE.read(faces.first)
    found = @engine.resolve_reference(FACE::REFERENCE_KIND, before.fetch("id"))

    assert_equal [100, 101], found.key
    found.record["face_type"] = "Floor"
    assert_equal before, FACE::FACE_STORE.read(faces.first)
    assert_equal ZONES::ZONE_STORE.read(zone), @engine.resolve_reference(ZONES::REFERENCE_KIND,
                                                                         zone_id(zone)).record
    assert_equal "reference.invalid", refusal { @engine.resolve_reference(ZONES::REFERENCE_KIND, face_id(faces.first)) }
    assert_equal "reference.invalid", refusal { @engine.resolve_reference(FACE::REFERENCE_KIND, "fac_000000999999") }
  end

  def test_orphan_and_shared_occurrences_are_included_in_uuid_ambiguity_checks
    _zone, faces = zone(100, [101])
    orphan = make_face(201)
    FACE::FACE_STORE.write(orphan, FACE::FACE_STORE.read(faces.first))
    @model.entities << orphan

    assert_equal "target.ambiguous", refusal { @engine.resolve_reference(FACE::REFERENCE_KIND, face_id(orphan)) }
  end

  def test_planned_reference_results_do_not_alias_nested_records_or_occurrence_keys
    _zone, faces = zone(100, [101])
    record = FACE::FACE_STORE.read(faces.first).merge("user_data" => { "tags" => ["original"] })
    plan = R::ReferencePlan.new(:entries => [
      R::ReferenceEntry.new(:kind => FACE::REFERENCE_KIND, :key => [100, 101], :record => record)
    ])

    found = @engine.resolve_reference(FACE::REFERENCE_KIND, record.fetch("id"), :reference_plan => plan)
    found.key << 999
    found.record.fetch("user_data").fetch("tags") << "mutated"
    found.record["face_type"] = "invalid"

    assert_equal [100, 101], plan.entries.first.key
    assert_equal record, plan.entries.first.record
    assert_equal record, @engine.resolve_reference(FACE::REFERENCE_KIND, record.fetch("id"),
                                                   :reference_plan => plan).record
  end

  def test_staged_catalog_reference_results_cannot_change_what_apply_persists
    before = attached("atz_000000000001")
    changes = R::ChangeSet.new
    @engine.propose_update(ATTACHED.id, before.fetch("id"), changes,
                           :values => { "name" => "Updated" }, :user_data => { "tags" => ["original"] })
    expected = PhComposer::DeepCopy.call(changes.writes.first.after)

    found = @engine.resolve_reference(ATTACHED.id, before.fetch("id"), :change_set => changes)
    found.record.fetch("user_data").fetch("tags") << "mutated"
    found.record["temperature_reduction_factor"] = -1
    found.key.replace("mutated")
    @engine.apply(changes)

    assert_equal expected, changes.writes.first.after
    assert_equal expected, ATTACHED.store.read(@model, before.fetch("id"))
    assert_empty ATTACHED.problems(changes.writes.first.after)
  end

  def test_removal_is_detached_and_retains_another_occurrence_with_the_same_uuid
    _group, faces = zone(100, [101, 102])
    before = FACE::FACE_STORE.read(faces.first)
    FACE::FACE_STORE.write(faces.last, before)
    key = [100, 101]
    removal = R::ReferenceRemoval.new(:kind => FACE::REFERENCE_KIND, :key => key, :before => before)
    plan = R::ReferencePlan.new(:entries => [], :removals => [removal])
    key << 999
    before["face_type"] = "Floor"

    found = @engine.resolve_reference(FACE::REFERENCE_KIND, face_id(faces.last), :reference_plan => plan)

    assert_equal [100, 102], found.key
    assert_equal [100, 101], plan.removals.first.key
    assert_equal "Wall", plan.removals.first.before.fetch("face_type")
    assert_equal 2, PhComposer::Registry.current.catalog.reference_target(FACE::REFERENCE_KIND).entries(@model).length
  end

  def test_removals_are_distinct_from_valid_replacements_and_additions
    _group, faces = zone(100, [101, 102])
    removal = removal_for(faces.first, [100, 101])
    replacement = R::ReferenceEntry.new(:kind => FACE::REFERENCE_KIND, :key => [100, 102],
                                        :record => FACE::FACE_STORE.read(faces.last).merge("face_type" => "Floor"))
    addition = R::ReferenceEntry.new(:kind => FACE::REFERENCE_KIND, :key => [100, 103],
                                     :record => replacement.record.merge("id" => "fac_000000000103"))
    plan = R::ReferencePlan.new(:entries => [replacement, addition], :removals => [removal])

    code = refusal do
      @engine.resolve_reference(FACE::REFERENCE_KIND, face_id(faces.first), :reference_plan => plan)
    end
    assert_equal "reference.invalid", code
    assert_equal "Floor", @engine.resolve_reference(FACE::REFERENCE_KIND, face_id(faces.last),
                                                    :reference_plan => plan).record.fetch("face_type")
    assert_equal [100, 103], @engine.resolve_reference(FACE::REFERENCE_KIND, "fac_000000000103",
                                                       :reference_plan => plan).key
    assert_empty R::ReferencePlan.new(:entries => []).removals
  end

  def test_removal_shape_and_conflicting_occurrence_keys_are_rejected
    _group, faces = zone(100, [101])
    removal = removal_for(faces.first, [100, 101])
    entry = R::ReferenceEntry.new(:kind => removal.kind, :key => removal.key, :record => removal.before)

    [nil, entry, R::ReferenceRemoval.new(:kind => removal.kind, :key => removal.key, :before => nil)].each do |bad|
      assert_raises(PhComposer::InternalError) { R::ReferencePlan.new(:entries => [], :removals => [bad]) }
    end
    assert_raises(PhComposer::InternalError) { R::ReferencePlan.new(:entries => [], :removals => [removal, removal]) }
    assert_raises(PhComposer::InternalError) { R::ReferencePlan.new(:entries => [entry], :removals => [removal]) }
  end

  def test_removal_checks_full_before_record_exact_path_and_registered_entity_schema
    _group, faces = zone(100, [101])
    set_data(FACE::FACE_STORE, faces.first, "literal" => "authored")
    before = FACE::FACE_STORE.read(faces.first)
    cases = [
      ["outside.missing", [100, 101], before, "reference.invalid"],
      [ATTACHED.id, "atz_000000000001", before, "reference.invalid"],
      [FACE::REFERENCE_KIND, [100, 101], before.merge("face_type" => "invalid"), "validation.failed"],
      [FACE::REFERENCE_KIND, [101], before, "target.not_found"],
      [FACE::REFERENCE_KIND, [100, 101], before.merge("user_data" => { "literal" => "changed" }), "target.changed"],
      [FACE::REFERENCE_KIND, [100, 101], before.merge("extension_data" => {}), "target.changed"]
    ]
    cases.each do |kind, key, expected, code|
      plan = R::ReferencePlan.new(:entries => [], :removals => [
        R::ReferenceRemoval.new(:kind => kind, :key => key, :before => expected)
      ])
      assert_equal code, refusal {
                           @engine.resolve_reference(FACE::REFERENCE_KIND, before.fetch("id"),
                                                     :reference_plan => plan)
                         }
    end
    assert_equal before, FACE::FACE_STORE.read(faces.first)
  end

  def test_removal_of_another_kind_is_guarded_when_resolving_a_target
    group, faces = zone(100, [101])
    removal = R::ReferenceRemoval.new(:kind => ZONES::REFERENCE_KIND, :key => [100],
                                      :before => ZONES::ZONE_STORE.read(group))
    plan = R::ReferencePlan.new(:entries => [], :removals => [removal])
    assert_equal [100, 101], @engine.resolve_reference(FACE::REFERENCE_KIND, face_id(faces.first),
                                                       :reference_plan => plan).key
    ZONES::ZONE_STORE.write(group, removal.before.merge("name" => "Changed"))
    code = refusal do
      @engine.resolve_reference(FACE::REFERENCE_KIND, face_id(faces.first), :reference_plan => plan)
    end
    assert_equal "target.changed", code
  end

  def test_duplicate_storage_keys_cannot_satisfy_a_removal_guard
    id = "outside.removal.object"
    entry = R::ReferenceEntry.new(:kind => id, :key => [7], :record => { "id" => "obj_7" })
    target = R::ReferenceTarget.new(:id => id, :label => "Outside object",
                                    :records => ->(_model) { [entry, entry] }, :validate => ->(_record) { [] })
    fixture = Module.new do
      define_singleton_method(:install) do |registry|
        registry.feature("outside.removal", :contract_version => 1).reference_target(target)
      end
    end
    PhComposer::Registry.install([fixture])
    engine = R::Engine.new(@model, PhComposer::Registry.current.catalog)
    plan = R::ReferencePlan.new(:entries => [], :removals => [
      R::ReferenceRemoval.new(:kind => id, :key => entry.key, :before => entry.record)
    ])

    assert_equal "target.ambiguous", refusal { engine.resolve_reference(id, "obj_7", :reference_plan => plan) }
  end

  def test_catalog_delete_requires_removal_of_all_exact_incoming_occurrences
    record = attached("atz_000000000001")
    _group, faces = zone(100, [101, 102])
    faces.each do |face|
      FACE::FACE_STORE.write(face, FACE::FACE_STORE.read(face).merge("boundary_condition" => "AttachedZone",
                                                                     "attached_zone_id" => record.fetch("id")))
    end
    orphan = make_face(201)
    @model.entities << orphan
    FACE::FACE_STORE.write(orphan, FACE::FACE_STORE.read(faces.first))
    removals = faces.map { |face| removal_for(face, [100, face.persistent_id]) }
    [removals.first(1), removals].each do |partial|
      changes = R::ChangeSet.new
      plan = R::ReferencePlan.new(:entries => [], :removals => partial)
      assert_equal "reference.in_use", refusal {
                                         @engine.propose_delete(ATTACHED.id, record.fetch("id"), changes,
                                                                :reference_plan => plan)
                                       }
      assert_equal "reference.in_use", changes.refusal.code
      assert_equal record, ATTACHED.store.read(@model, record.fetch("id"))
    end
    removals << removal_for(orphan, [201])
    changes = R::ChangeSet.new
    plan = R::ReferencePlan.new(:entries => [], :removals => removals)
    @engine.propose_delete(ATTACHED.id, record.fetch("id"), changes, :reference_plan => plan)

    assert_nil changes.writes.first.after
    assert_empty @engine.incoming_references(ATTACHED.id, record.fetch("id"), :reference_plan => plan)
    assert_equal 3, PhComposer::Registry.current.catalog.reference_target(FACE::REFERENCE_KIND).entries(@model).length
    assert_equal record, ATTACHED.store.read(@model, record.fetch("id"))
  end

  def test_surviving_unavailable_extension_reference_blocks_identity_removal
    record = attached("atz_000000000001")
    _group, faces = zone(100, [101, 102])
    set_data(FACE::FACE_STORE, faces.last, "catalog" => record.fetch("id"))
    before = FACE::FACE_STORE.read(faces.last)
    data = { "outside.unavailable" => before.fetch("extension_data").fetch(EXTENSION.namespace) }
    FACE::FACE_STORE.write(faces.last, before.merge("extension_data" => data))
    engine = R::Engine.new(@model, PhComposer::Registry.current.catalog)
    plan = R::ReferencePlan.new(:entries => [], :removals => [removal_for(faces.first, [100, 101])])

    assert_equal "reference.in_use", refusal {
                                       engine.check_identity_removal!(ATTACHED.id, record.fetch("id"),
                                                                      :reference_plan => plan)
                                     }
    all = R::ReferencePlan.new(:entries => [], :removals => [removal_for(faces.first, [100, 101]),
                                                             removal_for(faces.last, [100, 102])])
    assert_nil engine.check_identity_removal!(ATTACHED.id, record.fetch("id"), :reference_plan => all)
  end

  def test_malformed_neighbor_identity_reports_its_occurrence_without_writing
    _zone, faces = zone(100, [101])
    orphan = make_face(201)
    @model.entities << orphan
    FACE::FACE_STORE.write(orphan, "schema_version" => 1, "face_type" => "Wall")
    before = FACE::FACE_STORE.read(orphan)
    id = face_id(faces.first)
    fixture = Module.new do
      define_singleton_method(:install) do |registry|
        registry.feature("test.reference_read", :contract_version => 1).query(
          "test.reference_read.resolve", :description => "Resolve the fixture Face.",
                                         :params => { "type" => "object" }, :result => { "type" => "object" },
                                         :refuses => %w[record.unreadable]
        ) { |request| request.engine.resolve_reference(FACE::REFERENCE_KIND, id).record }
      end
    end
    PhComposer::Registry.install([fixture])

    result = PhComposer::API.query(:context => @context, :name => "test.reference_read.resolve")

    assert_equal %w[refused record.unreadable none], result.values_at("status", "code", "effect")
    assert_equal FACE::REFERENCE_KIND, result.dig("detail", "target_kind")
    assert_equal [201], result.dig("detail", "key")
    assert_includes result.fetch("message"), "[201]"
    assert_equal before, FACE::FACE_STORE.read(orphan)
    assert_empty @model.operations
    [nil, "", 201].each do |bad_id|
      FACE::FACE_STORE.write(orphan, before.merge("id" => bad_id))
      assert_equal "record.unreadable", refusal { @engine.resolve_reference(FACE::REFERENCE_KIND, id) }
    end
  end

  def test_catalog_edits_validate_entity_targets_without_catalog_crud
    _zone, faces = zone(100, [101])
    record = attached("atz_000000000001")
    changes = R::ChangeSet.new
    @engine.propose_update(ATTACHED.id, record.fetch("id"), changes,
                           :extension_payloads => { EXTENSION.namespace => { "self" => face_id(faces.first) } })
    @engine.apply(changes)

    assert_equal face_id(faces.first), ATTACHED.store.read(@model, record.fetch("id")).dig(
      "extension_data", EXTENSION.namespace, "payload", "self"
    )
    bad = R::ChangeSet.new
    code = refusal do
      @engine.propose_update(ATTACHED.id, record.fetch("id"), bad,
                             :extension_payloads => { EXTENSION.namespace => { "self" => "zon_000000000100" } })
    end
    assert_equal "reference.invalid", code
    assert_empty bad.writes
  end

  # An understood extension's reference is checked on every edit and copy, so an entity id that now
  # occurs twice refuses both, as their published refusal codes say.
  def test_an_extension_reference_to_a_duplicated_entity_id_refuses_edit_and_copy
    _zone, faces = zone(100, [101])
    record = attached("atz_000000000001")
    data = { EXTENSION.namespace => EXTENSION.envelope("self" => face_id(faces.first)) }
    ATTACHED.store.write(@model, record.merge("extension_data" => data))
    orphan = make_face(201)
    FACE::FACE_STORE.write(orphan, FACE::FACE_STORE.read(faces.first))
    @model.entities << orphan

    saved = invoke("ph_composer.zones.faces.attached_zone.save",
                   "id" => record.fetch("id"), "values" => { "name" => "Carport" })
    copied = invoke("ph_composer.zones.faces.attached_zone.duplicate", "ids" => [record.fetch("id")])

    [saved, copied].each { |outcome| assert_equal %w[refused target.ambiguous], outcome.values_at("status", "code") }
    assert_equal "Garage", ATTACHED.store.read(@model, record.fetch("id")).fetch("name")
  end

  def test_catalog_copy_keeps_an_outside_target_with_the_same_uuid_string
    original = attached("atz_000000000001")
    target = R::ReferenceTarget.new(
      :id => "test.copy_kind.object", :label => "Outside object",
      :records => lambda do |_model|
        [R::ReferenceEntry.new(:kind => "test.copy_kind.object", :key => [900], :record => original)]
      end,
      :validate => ->(_record) { [] }
    )
    extension = R::Extension.new(
      :namespace => "test.copy_kind.links", :schema_version => 1,
      :references => [
        { "path" => "$.self", "target_kind" => ATTACHED.id, "cardinality" => "one" },
        { "path" => "$.outside", "target_kind" => target.id, "cardinality" => "one" }
      ]
    )
    fixture = Module.new do
      define_singleton_method(:install) do |registry|
        feature = registry.feature("test.copy_kind", :contract_version => 1)
        feature.reference_target(target)
        feature.extension(extension)
      end
    end
    PhComposer::Registry.install([fixture])
    engine = R::Engine.new(@model, PhComposer::Registry.current.catalog)
    original["extension_data"] = {
      extension.namespace => extension.envelope("self" => original.fetch("id"), "outside" => original.fetch("id"))
    }
    ATTACHED.store.write(@model, original)
    changes = R::ChangeSet.new

    mapping = engine.propose_duplicate(ATTACHED.id, [original.fetch("id")], changes)
    copied = changes.find(ATTACHED.id, mapping.fetch(original.fetch("id"))).after

    assert_equal mapping.fetch(original.fetch("id")),
                 copied.dig("extension_data", extension.namespace, "payload", "self")
    assert_equal original.fetch("id"), copied.dig("extension_data", extension.namespace, "payload", "outside")
    assert_equal original, engine.resolve_reference(target.id, original.fetch("id")).record
  end

  def test_catalog_deletion_checks_incoming_entity_references_even_when_extension_unavailable
    _zone, faces = zone(100, [101])
    record = attached("atz_000000000001")
    data = { "foreign.references" => EXTENSION.envelope("catalog" => record.fetch("id")) }
    FACE::FACE_STORE.write(faces.first, FACE::FACE_STORE.read(faces.first).merge("extension_data" => data))
    changes = R::ChangeSet.new

    assert_equal "reference.in_use", refusal { @engine.propose_delete(ATTACHED.id, record.fetch("id"), changes) }
    assert_equal "reference.in_use", changes.refusal.code
    assert_equal record, ATTACHED.store.read(@model, record.fetch("id"))
  end

  def test_collection_copy_remaps_actual_self_cross_many_and_zone_references
    original, first = zone(100, [101, 102])
    copy, copied = zone(200, [201, 202], :record_ids => [zone_id(original), *first.map { |face| face_id(face) }])
    external, outside = zone(300, [301])
    catalog = attached("atz_000000000001")
    payload = { "owner" => zone_id(original), "peers" => first.map { |face| face_id(face) },
                "external_face" => face_id(outside.first), "external_zone" => zone_id(external),
                "catalog" => catalog.fetch("id"), "literal" => face_id(first.first) }
    [original, copy].each { |group| set_data(ZONES::ZONE_STORE, group, payload) }
    (first + copied).each_with_index do |face, index|
      set_data(FACE::FACE_STORE, face, payload.merge("self" => face_id(first[index % 2])))
    end
    set_data(FACE::FACE_STORE, outside.first, "peers" => first.map { |face| face_id(face) })
    incoming_before = FACE::FACE_STORE.read(outside.first)
    original_before = first.map { |face| FACE::FACE_STORE.read(face) }

    result = invoke("ph_composer.zones.repair_identity", "zone_path" => [200])

    assert_equal %w[completed committed], result.values_at("status", "effect")
    result.fetch("affected").select { |entry| entry.fetch("kind") == "face" }.each do |entry|
      resolved = ZONES::Occurrences.resolve_face(@model, entry.fetch("reference"))
      assert_equal entry.fetch("id"), face_id(resolved.entity)
    end
    new_ids = copied.map { |face| face_id(face) }
    copied.each do |face|
      value = FACE::FACE_STORE.read(face).dig("extension_data", EXTENSION.namespace, "payload")
      assert_equal face_id(face), value.fetch("self")
      assert_equal new_ids, value.fetch("peers")
      assert_equal zone_id(copy), value.fetch("owner")
      assert_equal face_id(outside.first), value.fetch("external_face")
      assert_equal zone_id(external), value.fetch("external_zone")
      assert_equal catalog.fetch("id"), value.fetch("catalog")
      assert_equal face_id(first.first), value.fetch("literal")
      assert_equal face_id(first.first), FACE::FACE_STORE.read(face).dig("user_data", "literal")
      assert_equal FACE::FACE_STORE.read(face), @engine.resolve_reference(FACE::REFERENCE_KIND, face_id(face)).record
    end
    assert_equal new_ids, ZONES::ZONE_STORE.read(copy).dig("extension_data", EXTENSION.namespace, "payload", "peers")
    assert_equal incoming_before, FACE::FACE_STORE.read(outside.first)
    assert_equal original_before, first.map { |face| FACE::FACE_STORE.read(face) }
    assert_equal FACE::FACE_STORE.read(first.first), @engine.resolve_reference(FACE::REFERENCE_KIND,
                                                                               face_id(first.first)).record
  end

  def test_split_keeper_receives_incoming_while_new_pieces_remap_self_references
    group, pieces = zone(100, [101, 102], :record_ids => ["zon_000000000100", "fac_000000000101",
                                                          "fac_000000000101"])
    external, outside = zone(200, [201])
    old_id = face_id(pieces.first)
    pieces.each { |face| set_data(FACE::FACE_STORE, face, "self" => old_id, "owner" => zone_id(group)) }
    set_data(ZONES::ZONE_STORE, external, "peers" => [old_id])
    catalog = attached("atz_000000000001")
    ATTACHED.store.write(@model, catalog.merge("extension_data" => { EXTENSION.namespace =>
                                                                   EXTENSION.envelope("self" => old_id) }))
    set_data(FACE::FACE_STORE, outside.first, "self" => old_id)
    incoming = [ZONES::ZONE_STORE.read(external), FACE::FACE_STORE.read(outside.first),
                ATTACHED.store.read(@model, catalog.fetch("id"))]
    ref = ZONES::Occurrences.zones(@model).find { |zone| zone.path == [100] }.reference

    result = invoke("ph_composer.zones.repair_split_face", "zone" => ref, "face_id" => old_id,
                                                           "zones" => [ref], "retaining_entity_path" => [101])

    assert_equal %w[completed committed], result.values_at("status", "effect")
    assert_equal old_id, face_id(pieces.first)
    refute_equal old_id, face_id(pieces.last)
    pieces.each do |face|
      assert_equal face_id(face), FACE::FACE_STORE.read(face).dig("extension_data", EXTENSION.namespace,
                                                                  "payload", "self")
    end
    assert_equal incoming, [ZONES::ZONE_STORE.read(external), FACE::FACE_STORE.read(outside.first),
                            ATTACHED.store.read(@model, catalog.fetch("id"))]
    assert_equal [100, 101], @engine.resolve_reference(FACE::REFERENCE_KIND, old_id).key
  end

  def test_invalid_wrong_kind_or_dangling_copy_reference_refuses_atomically
    original, faces = zone(100, [101])
    copy, copied = zone(200, [201], :record_ids => [zone_id(original), face_id(faces.first)])
    ["fac_000000999999", face_id(faces.first)].each do |bad|
      set_data(FACE::FACE_STORE, copied.first, "owner" => bad)
      before = [ZONES::ZONE_STORE.read(copy), FACE::FACE_STORE.read(copied.first)]
      result = invoke("ph_composer.zones.repair_identity", "zone_path" => [200])

      assert_equal %w[refused reference.invalid none], result.values_at("status", "code", "effect")
      assert_equal before, [ZONES::ZONE_STORE.read(copy), FACE::FACE_STORE.read(copied.first)]
    end
  end

  def test_public_contributor_can_register_targets_without_changing_core
    records = [R::ReferenceEntry.new(:kind => "outside.feature.object", :key => [777],
                                     :record => { "id" => "custom_source" })]
    target = R::ReferenceTarget.new(:id => "outside.feature.object", :label => "Outside object",
                                    :records => ->(_model) { records }, :validate => ->(_record) { [] })
    feature = Module.new do
      define_singleton_method(:install) do |registry|
        registry.feature("outside.feature", :contract_version => 1).reference_target(target)
      end
    end
    PhComposer::Registry.install([feature])
    engine = R::Engine.new(@model, PhComposer::Registry.current.catalog)

    assert_equal "custom_source", engine.resolve_reference(target.id, "custom_source").record.fetch("id")
    plan = R::ReferencePlan.new(:entries => [R::ReferenceEntry.new(:kind => FACE::REFERENCE_KIND, :key => [101],
                                                                   :record => { "id" => "custom_copy" })])
    code = refusal { engine.resolve_reference(target.id, "custom_copy", :reference_plan => plan) }
    assert_equal "validation.failed", code
  end

  def test_identity_removal_refuses_opaque_incoming_data_without_rewriting_it
    _zone, faces = zone(100, [101])
    data = { "unknown.fixture" => { "payload" => { "hidden" => "custom_old_id" } } }
    FACE::FACE_STORE.write(faces.first, FACE::FACE_STORE.read(faces.first).merge("extension_data" => data))

    assert_equal "copy.rule_missing", refusal { @engine.check_identity_removal!(FACE::REFERENCE_KIND, "custom_old_id") }
    assert_equal data, FACE::FACE_STORE.read(faces.first).fetch("extension_data")
  end

  def test_same_string_id_in_outside_target_kind_is_not_remapped_by_face_collection
    _group, faces = zone(100, [101])
    source_id = face_id(faces.first)
    record = FACE::FACE_STORE.read(faces.first)
    target = R::ReferenceTarget.new(
      :id => "outside.feature.object", :label => "Outside object",
      :records => ->(_model) {
                    [R::ReferenceEntry.new(:kind => "outside.feature.object", :key => [9],
                                           :record => { "id" => source_id })]
                  },
      :validate => ->(_record) { [] }
    )
    extension = R::Extension.new(
      :namespace => "outside.feature.links", :schema_version => 1,
      :references => [{ "path" => "$.external", "target_kind" => target.id, "cardinality" => "one" }]
    )
    feature = Module.new do
      define_singleton_method(:install) do |registry|
        scope = registry.feature("outside.feature", :contract_version => 1)
        scope.reference_target(target)
        scope.extension(extension)
      end
    end
    PhComposer::Registry.install([feature])
    catalog = PhComposer::Registry.current.catalog
    engine = R::Engine.new(@model, catalog)
    new_id = "fac_000000000999"
    plan = R::ReferencePlan.new(:entries => [R::ReferenceEntry.new(:kind => FACE::REFERENCE_KIND, :key => [100, 999],
                                                                   :record => record.merge("id" => new_id))])
    data = { extension.namespace => extension.envelope("external" => source_id) }

    copied = R::Extension.copy_data(data, catalog, "Face", source_id, { source_id => new_id },
                                    :engine => engine, :reference_plan => plan)

    assert_equal source_id, copied.dig(extension.namespace, "payload", "external")
    assert_equal source_id, engine.resolve_reference(target.id, source_id).record.fetch("id")
  end

  def test_discovery_and_description_publish_detached_reference_target_inventory
    inventory = PhComposer::API.discover.fetch("reference_targets")
    assert_equal [FACE::REFERENCE_KIND, ZONES::REFERENCE_KIND, ZONES::Options::STAMP_KIND,
                  PhComposer::Windows::Settings::KIND, PhComposer::Windows::Units::REFERENCE_KIND,
                  *PhComposer::Spaces::KINDS.keys, PhComposer::ThermalBridges::EDGE_KIND].sort,
                 inventory.map { |target| target.fetch("id") }.sort
    found = PhComposer::API.describe(:name => FACE::REFERENCE_KIND)
    assert_equal "reference_target", found.fetch("kind")
    assert_equal ZONES::FEATURE_ID, found.fetch("owner")
    found["label"] = "Edited"
    assert_equal "Face", PhComposer::API.describe(:name => FACE::REFERENCE_KIND).fetch("label")
  end

  private

  def removal_for(face, key)
    R::ReferenceRemoval.new(:kind => FACE::REFERENCE_KIND, :key => key, :before => FACE::FACE_STORE.read(face))
  end

  def refusal
    assert_raises(PhComposer::CodedError) { yield }.code
  end

  def make_face(pid)
    Sketchup::Face.new(pid, {}, :points => [Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(2, 0, 0),
                                            Geom::Point3d.new(2, 2, 0)])
  end

  def zone(pid, face_pids, record_ids: nil)
    members = face_pids.map { |id| make_face(id) }
    group = Sketchup::Group.new(pid, Sketchup::Entities.new(members))
    @model.entities << group
    ids = record_ids || ["zon_#{format('%012d', pid)}", *face_pids.map { |id| "fac_#{format('%012d', id)}" }]
    ZONES::ZONE_STORE.write(group, "id" => ids.first, "schema_version" => 1, "name" => "Zone #{pid}",
                                   "building_segment" => "Test", "level" => nil, "ground_depth_mm" => 0.0)
    members.each_with_index do |face, index|
      FACE::FACE_STORE.write(face, "id" => ids[index + 1], "schema_version" => 1,
                                   "face_type" => "Wall", "boundary_condition" => "Ground")
    end
    [group, members]
  end

  def face_id(face)
    FACE::FACE_STORE.read(face).fetch("id")
  end

  def zone_id(group)
    ZONES::ZONE_STORE.read(group)&.fetch("id", nil)
  end

  def set_data(store, entity, payload)
    data = { EXTENSION.namespace => EXTENSION.envelope(payload) }
    store.write(entity, store.read(entity).merge("extension_data" => data,
                                                 "user_data" => { "literal" => payload["literal"] }))
  end

  def attached(id)
    record = { "id" => id, "schema_version" => 1, "name" => "Garage", "kind" => "garage",
               "temperature_reduction_factor" => 0.95 }
    ATTACHED.store.write(@model, record)
    record
  end

  def invoke(name, params)
    @sequence = (@sequence || 0) + 1
    PhComposer::API.invoke(:context => @context, :name => name, :params => params,
                           :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end
end
