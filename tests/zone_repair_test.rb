# frozen_string_literal: true

require_relative "test_helper"

# The two explicit Zone repairs. Identity repair gives a copied occurrence an identity of its own
# without touching the Zone it came from. Restore regroups an exploded Zone's stamped members and
# recovers only what a stamp can carry.
class ZoneRepairTest < PhComposerTestCase
  API = PhComposer::API
  ZONE_STORE = PhComposer::Zones::ZONE_STORE
  MAKE_INDEPENDENT = "ph_composer.zones.make_independent"
  STAMP_STORE = PhComposer::Zones::STAMP_STORE
  FACE_STORE = PhComposer::Zones::Faces::FACE_STORE
  COPY_EXTENSION = PhComposer::Records::Extension.new(
    :namespace => "test.fixture.identity", :schema_version => 1,
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
  end

  def test_repair_gives_the_copy_a_new_identity_and_leaves_the_original_untouched
    original, copy = copied_zone
    before = ZONE_STORE.read(original)
    before_faces = original.entities.to_a.map { |face| FACE_STORE.read(face) }

    result = invoke("ph_composer.zones.repair_identity", { "zone_path" => [copy.persistent_id] })

    assert_equal %w[completed committed], result.values_at("status", "effect")
    repaired = ZONE_STORE.read(copy)

    refute_equal before.fetch("id"), repaired.fetch("id")
    assert_equal before.fetch("id"), ZONE_STORE.read(original).fetch("id")
    assert_equal before_faces, original.entities.to_a.map { |face| FACE_STORE.read(face) }
    assert_equal %w[found found], zone_states
  end

  def test_a_zone_made_into_a_component_is_a_finding_and_the_other_zones_stay_readable
    kept = box_group(5000, 3)
    converted = box_group(6000, 3)
    @model.entities << kept << converted
    make_zone(kept)
    make_zone(converted)
    # Native Make Component: the Zone Group becomes a component instance carrying its record.
    component = Sketchup::ComponentInstance.new(6100, Sketchup::ComponentDefinition.new(converted.entities))
    component.set_attribute("ph_composer.zone", "record", converted.get_attribute("ph_composer.zone", "record"))
    @model.entities.erase_entities(converted)
    @model.entities << component

    value = API.query(:context => @context, :name => "ph_composer.zones.all").fetch("value")
    assert_equal [[kept.persistent_id]], value.fetch("zones").map { |zone| zone.dig("reference", "zone_path") }
    finding = value.fetch("findings").first
    assert_equal ["zone.component", [6100]], [finding.fetch("code"), finding.dig("reference", "entity_path")]
    assert_includes finding.fetch("message"), "Undo Make Component"
    preflight = API.query(:context => @context, :name => "ph_composer.zones.export_preflight").dig("value", "findings")
    assert(preflight.any? { |row| row.fetch("code") == "zone.component" && row.fetch("blocks_export") })
  end

  def test_repair_gives_every_copied_face_a_new_id_and_rewrites_its_stamp
    original, copy = copied_zone
    original_ids = original.entities.to_a.map { |face| FACE_STORE.read(face).fetch("id") }

    invoke("ph_composer.zones.repair_identity", { "zone_path" => [copy.persistent_id] })

    repaired_id = ZONE_STORE.read(copy).fetch("id")
    copy.entities.to_a.each do |face|
      refute_includes original_ids, FACE_STORE.read(face).fetch("id")
      assert_equal repaired_id, STAMP_STORE.read(face).fetch("zone_id")
    end
  end

  def test_repair_refuses_unavailable_references_without_changing_either_copy
    original, copy = copied_zone
    old_id = FACE_STORE.read(copy.entities.to_a.first).fetch("id")
    envelope = COPY_EXTENSION.envelope("external_id" => "atz_000000000001", "marker" => old_id)
    [original, copy].each do |group|
      face = group.entities.to_a.first
      record = FACE_STORE.read(face).merge("user_data" => { "firm.note" => "keep" },
                                           "extension_data" => { COPY_EXTENSION.namespace => envelope })
      FACE_STORE.write(face, record)
    end
    before = [ZONE_STORE.read(copy), copy.entities.to_a.map { |face| FACE_STORE.read(face) }]
    params = { "zone_path" => [copy.persistent_id] }

    preview = API.preview(:context => @context, :name => "ph_composer.zones.repair_identity", :params => params)
    result = invoke("ph_composer.zones.repair_identity", params)

    assert_equal %w[refused copy.rule_missing none], result.values_at("status", "code", "effect")
    assert_equal %w[refused copy.rule_missing none], preview.values_at("status", "code", "effect")
    assert_equal "unavailable", result.dig("detail", "status")
    assert_equal before, [ZONE_STORE.read(copy), copy.entities.to_a.map { |face| FACE_STORE.read(face) }]
    assert_equal old_id, FACE_STORE.read(original.entities.to_a.first).fetch("id")
  end

  def test_repair_keeps_registered_external_references_and_literal_metadata
    register_copy_extension
    store_external_reference
    original, copy = copied_zone
    old_zone_id = ZONE_STORE.read(copy).fetch("id")
    old_face_ids = copy.entities.to_a.map { |face| FACE_STORE.read(face).fetch("id") }
    zone_envelope = COPY_EXTENSION.envelope("external_id" => "atz_000000000001", "marker" => old_zone_id)
    ZONE_STORE.write(copy, ZONE_STORE.read(copy).merge("extension_data" => {
      COPY_EXTENSION.namespace => zone_envelope
    }))
    copy.entities.to_a.each do |face|
      before = FACE_STORE.read(face)
      envelope = COPY_EXTENSION.envelope("external_id" => "atz_000000000001", "marker" => old_face_ids.last)
      FACE_STORE.write(face, before.merge("user_data" => { "literal" => old_face_ids.last },
                                          "extension_data" => { COPY_EXTENSION.namespace => envelope }))
    end

    result = invoke("ph_composer.zones.repair_identity", { "zone_path" => [copy.persistent_id] })
    new_zone_id = ZONE_STORE.read(copy).fetch("id")
    new_face_ids = copy.entities.to_a.map { |face| FACE_STORE.read(face).fetch("id") }

    assert_equal %w[completed committed], result.values_at("status", "effect")
    refute_equal old_zone_id, new_zone_id
    refute_equal old_face_ids, new_face_ids
    assert_equal "atz_000000000001", ZONE_STORE.read(copy).dig("extension_data", COPY_EXTENSION.namespace,
                                                               "payload", "external_id")
    assert_equal old_zone_id, ZONE_STORE.read(copy).dig("extension_data", COPY_EXTENSION.namespace,
                                                        "payload", "marker")
    copy.entities.to_a.each do |face|
      repaired = FACE_STORE.read(face)
      assert_equal "atz_000000000001", repaired.dig("extension_data", COPY_EXTENSION.namespace,
                                                    "payload", "external_id")
      assert_equal old_face_ids.last, repaired.dig("extension_data", COPY_EXTENSION.namespace,
                                                   "payload", "marker")
      assert_equal old_face_ids.last, repaired.dig("user_data", "literal")
    end
    assert_equal old_zone_id, ZONE_STORE.read(original).fetch("id")
  end

  def test_repair_retires_the_copied_pair_without_changing_the_original_pair
    left, right = solved_pair
    copy = duplicate_group(right, 900)

    result = invoke("ph_composer.zones.repair_identity", { "zone_path" => [copy.persistent_id] })

    assert_equal 1, result.dig("value", "retired_pairs")
    repaired_face = FACE_STORE.read(copy.entities.to_a.first)

    refute repaired_face.key?("adjacency")
    refute repaired_face.key?("boundary_condition")
    [left, right].each do |group|
      record = FACE_STORE.read(group.entities.to_a.first)

      assert_equal "Surface", record.fetch("boundary_condition")
      assert record.fetch("adjacency").fetch("pair_id")
    end
  end

  def test_repair_refuses_a_zone_whose_identity_is_already_unique
    group = box_group(100, 2)
    @model.entities << group
    make_zone(group)

    result = invoke("ph_composer.zones.repair_identity", { "zone_path" => [group.persistent_id] })

    assert_equal %w[refused zone.identity_unique none], result.values_at("status", "code", "effect")
  end

  # Identity repair writes the Zone record and every member Face, so a lock on the Zone or a Group above it
  # refuses it the way every other Zone write does, and nothing is written.
  def test_repair_refuses_a_locked_copy_or_a_copy_inside_a_locked_group
    original, copy = copied_zone
    before = [original, copy].map { |group| ZONE_STORE.read(group) }
    copy.locked = true
    own = invoke("ph_composer.zones.repair_identity", { "zone_path" => [copy.persistent_id] })
    copy.locked = false
    @model.entities.delete(copy)
    parent = Sketchup::Group.new(500, Sketchup::Entities.new([copy]), :locked => true)
    @model.entities << parent
    treat_duplicates_as_existing(@model)
    UI.run_timers
    above = invoke("ph_composer.zones.repair_identity", { "zone_path" => [500, copy.persistent_id] })

    [own, above].each do |result|
      assert_equal %w[refused target.locked none], result.values_at("status", "code", "effect"), result.inspect
    end
    assert_equal before, [original, copy].map { |group| ZONE_STORE.read(group) }
  end

  # A lock set after the repair was planned still stops it at apply.
  def test_repair_refuses_at_apply_when_the_copy_was_locked_after_planning
    _original, copy = copied_zone
    zone = PhComposer::Zones::Repair.occurrence_at(@model, [copy.persistent_id])
    catalog = PhComposer::Registry.current.catalog
    plan = PhComposer::Zones::Repair.identity_plan(@model, zone, @session.revision, catalog,
                                                   PhComposer::Records::Engine.new(@model, catalog))
    step = PhComposer::Zones::RepairIdentityStep.new(:reference => zone.reference, :plan => plan)
    before = ZONE_STORE.read(copy)
    copy.locked = true

    error = assert_raises(PhComposer::CodedError) { step.apply(@model, {}) }
    assert_equal "target.locked", error.code
    assert_equal before, ZONE_STORE.read(copy)
  end

  def test_repair_refuses_a_copy_held_in_shared_component_storage
    group = box_group(200, 2)
    @model.entities << group
    make_zone(group)
    @model.entities.delete(group)
    definition = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([group]), :name => "copied")
    instance = @model.entities.add_instance(definition, Geom::Transformation.new)
    @model.entities.add_instance(definition, Geom::Transformation.new)
    treat_duplicates_as_existing(@model)

    result = invoke("ph_composer.zones.repair_identity",
                    { "zone_path" => [instance.persistent_id, group.persistent_id] })

    assert_equal %w[refused target.shared_definition none], result.values_at("status", "code", "effect")
  end

  # Copying a Group on the host does not copy what is inside it: both Groups become instances of
  # one definition and share every Face. So a copied Zone is ambiguous and shared at the same time,
  # and repairing one would rewrite the other's Faces. Measured on SketchUp 26.1.188.
  def test_a_zone_copied_the_way_sketchup_copies_one_reads_as_shared_storage
    group = box_group(250, 3)
    @model.entities << group
    make_zone(group)
    classify_all
    twin = Sketchup::Group.new(260, group.entities)
    twin.set_attribute("ph_composer.zone", "record", group.get_attribute("ph_composer.zone", "record"))
    @model.entities << twin
    treat_duplicates_as_existing(@model)

    states = zones_value.fetch("zones").map { |zone| zone.fetch("state") }

    assert_equal %w[shared_definition shared_definition], states
  end

  def test_repairing_a_copy_that_shares_its_faces_refuses_and_leaves_both_alone
    group = box_group(270, 3)
    @model.entities << group
    make_zone(group)
    classify_all
    before = group.entities.to_a.map { |face| FACE_STORE.read(face) }
    twin = Sketchup::Group.new(280, group.entities)
    twin.set_attribute("ph_composer.zone", "record", group.get_attribute("ph_composer.zone", "record"))
    @model.entities << twin
    treat_duplicates_as_existing(@model)

    result = invoke("ph_composer.zones.repair_identity", { "zone_path" => [280] })

    assert_equal %w[refused target.shared_definition none], result.values_at("status", "code", "effect")
    assert_equal before, group.entities.to_a.map { |face| FACE_STORE.read(face) }
  end

  def test_an_exploded_zone_is_offered_for_restore_with_its_recoverable_fields
    group, zone_id = exploded_zone

    offer = restorable.first

    assert_equal zone_id, offer.fetch("zone_id")
    assert_equal 3, offer.fetch("member_count")
    assert_nil offer.fetch("refusal")
    assert_equal %w[extension_data ground_depth_mm name user_data], offer.fetch("unrecoverable").sort
    assert_equal [], offer.fetch("parent_path")
    refute_includes @model.entities.to_a, group
  end

  # A stamp the feature did not write names no Zone to restore, and must not fail the Zones read.
  def test_a_foreign_stamp_is_not_offered_for_restore_and_leaves_the_read_intact
    face = Sketchup::Face.new(990)
    STAMP_STORE.write(face, "schema_version" => 1, "building_segment" => 7)
    @model.entities << face

    result = PhComposer::API.query(:context => @context, :name => "ph_composer.zones.list")

    assert_equal "completed", result.fetch("status")
    assert_empty result.dig("value", "restorable")
  end

  def test_restore_regroups_the_stamped_members_and_recovers_only_the_stamp
    _group, zone_id = exploded_zone

    result = invoke("ph_composer.zones.restore", { "parent_path" => [], "zone_id" => zone_id })

    assert_equal %w[completed committed], result.values_at("status", "effect")
    assert_equal zone_id, result.dig("value", "zone_id")
    restored = @model.entities.to_a.find { |entity| entity.is_a?(Sketchup::Group) }
    record = ZONE_STORE.read(restored)

    assert_equal zone_id, record.fetch("id")
    assert_equal "Attic", record.fetch("building_segment")
    assert_equal "L2", record.fetch("level")
    # The name went with the Group. Restore takes a fresh default rather than claiming recovery.
    assert_equal "Zone 1", record.fetch("name")
    assert_equal 3, restored.entities.to_a.length
    assert_equal ["zone.restore_is_limited"], result.fetch("findings").map { |row| row.fetch("code") }
    assert_empty restorable
  end

  def test_restore_preserves_every_member_payload_and_reverts_in_one_undo
    _group, zone_id = exploded_zone
    face = @model.entities.to_a.find { |entity| entity.is_a?(Sketchup::Face) }
    FACE_STORE.write(face, FACE_STORE.read(face).merge("user_data" => { "firm.note" => "keep" }))

    invoke("ph_composer.zones.restore", { "parent_path" => [], "zone_id" => zone_id })

    restored = @model.entities.to_a.find { |entity| entity.is_a?(Sketchup::Group) }

    assert_equal({ "firm.note" => "keep" }, FACE_STORE.read(restored.entities.to_a.first).fetch("user_data"))

    @model.undo

    assert_empty @model.entities.to_a.select { |entity| entity.is_a?(Sketchup::Group) }
    assert_equal 3, @model.entities.to_a.count { |entity| entity.is_a?(Sketchup::Face) }
  end

  def test_restore_refuses_conflicting_stamps_and_writes_nothing
    _group, zone_id = exploded_zone
    face = @model.entities.to_a.find { |entity| entity.is_a?(Sketchup::Face) }
    STAMP_STORE.write(face, STAMP_STORE.read(face).merge("level" => "L9"))

    assert_equal "stamps_conflict", restorable.first.fetch("refusal")

    result = invoke("ph_composer.zones.restore", { "parent_path" => [], "zone_id" => zone_id })

    assert_equal %w[refused zone.restore_unsafe none], result.values_at("status", "code", "effect")
    assert_empty @model.entities.to_a.select { |entity| entity.is_a?(Sketchup::Group) }
  end

  # Restore regroups through Make Zone's step, so it refuses a member another feature claims as Make Zone does.
  def test_restore_refuses_a_claimed_member_and_writes_nothing
    _group, zone_id = exploded_zone
    face = @model.entities.to_a.find { |entity| entity.is_a?(Sketchup::Face) }
    PhComposer::Spaces::FLOOR_SEGMENT_STORE.write(face, "id" => "fsg_EEEEEEEEEEEE")
    operation_count = @model.operations.length

    result = invoke("ph_composer.zones.restore", { "parent_path" => [], "zone_id" => zone_id })

    assert_equal %w[refused target.wrong_kind none], result.values_at("status", "code", "effect")
    assert_equal operation_count, @model.operations.length
    assert_empty @model.entities.to_a.select { |entity| entity.is_a?(Sketchup::Group) }
  end

  # The step both routes share repeats the claim check at apply, so a claim made after planning still stops it.
  def test_make_zone_step_refuses_at_apply_when_its_group_came_to_hold_a_claimed_object
    inner = Sketchup::Group.new(6210, Sketchup::Entities.new([Sketchup::Face.new(6211)]))
    wrapper = Sketchup::Group.new(6200, Sketchup::Entities.new([inner]))
    @model.entities << wrapper
    record = { "id" => "zon_SSSSSSSSSSSS", "schema_version" => 1, "name" => "Late", "building_segment" => "B",
               "level" => nil, "ground_depth_mm" => 0.0 }
    step = PhComposer::Zones::MakeZoneStep.new(:parent_path => [], :entity_ids => [6200], :record => record)
    PhComposer::Spaces::SPACE_STORE.write(inner, "id" => "spc_SSSSSSSSSSSS")

    error = assert_raises(PhComposer::CodedError) { step.apply(@model, {}) }
    assert_equal "target.wrong_hierarchy", error.code
    assert_nil ZONE_STORE.read(wrapper)
  end

  # Offering them would make Restore build a Zone inside the live one.
  def test_stamped_faces_moved_into_a_live_zone_are_not_offered_for_restore
    _group, zone_id = exploded_zone
    live = box_group(700, 3)
    @model.entities << live
    make_zone(live)
    @model.entities.to_a.grep(Sketchup::Face).each do |face|
      @model.entities.delete(face)
      live.entities << face
    end

    offers = restorable.map { |offer| offer.fetch("zone_id") }

    refute_includes offers, zone_id
  end

  def test_restore_refuses_stamped_members_spread_across_parent_contexts
    _group, zone_id = exploded_zone
    face = @model.entities.to_a.find { |entity| entity.is_a?(Sketchup::Face) }
    @model.entities.delete(face)
    @model.entities << Sketchup::Group.new(700, Sketchup::Entities.new([face]))

    assert_equal "mixed_context", restorable.first.fetch("refusal")

    result = invoke("ph_composer.zones.restore", { "parent_path" => [], "zone_id" => zone_id })

    assert_equal %w[refused zone.restore_unsafe none], result.values_at("status", "code", "effect")
  end

  def test_restore_refuses_when_a_bounding_edge_is_shared_with_unstamped_geometry
    _group, zone_id = exploded_zone
    stamped = @model.entities.to_a.select { |entity| entity.is_a?(Sketchup::Face) }
    shared = Sketchup::Edge.new(800, point(0, 0, 0), point(2, 0, 0))
    @model.entities << shared
    shared.attach_face(stamped.first)
    stamped.first.edges << shared
    # An unstamped Face on the same Edge: regrouping would drag it along.
    outsider = Sketchup::Face.new(801, {}, :points => [point(0, 0, 9), point(2, 0, 9), point(2, 2, 9)],
                                           :edges => [shared])
    @model.entities << outsider

    assert_equal "shared_edge", restorable.first.fetch("refusal")

    result = invoke("ph_composer.zones.restore", { "parent_path" => [], "zone_id" => zone_id })

    assert_equal %w[refused zone.restore_unsafe none], result.values_at("status", "code", "effect")
    assert_empty @model.entities.to_a.select { |entity| entity.is_a?(Sketchup::Group) }
  end

  def test_restore_accepts_an_edge_shared_only_between_stamped_members
    _group, zone_id = exploded_zone
    stamped = @model.entities.to_a.select { |entity| entity.is_a?(Sketchup::Face) }
    shared = Sketchup::Edge.new(810, point(0, 0, 0), point(2, 0, 0))
    @model.entities << shared
    stamped.first(2).each do |face|
      shared.attach_face(face)
      face.edges << shared
    end

    assert_nil restorable.first.fetch("refusal")
    assert_equal "completed", invoke("ph_composer.zones.restore",
                                     { "parent_path" => [], "zone_id" => zone_id }).fetch("status")
  end

  def test_the_restore_offer_reports_every_remembered_member_even_when_it_refuses
    _group, zone_id = exploded_zone
    face = @model.entities.to_a.find { |entity| entity.is_a?(Sketchup::Face) }
    @model.entities.delete(face)
    @model.entities << Sketchup::Group.new(710, Sketchup::Entities.new([face]))

    offer = restorable.first

    assert_equal "mixed_context", offer.fetch("refusal")
    assert_equal offer.fetch("member_count"), offer.fetch("entity_ids").length
    assert_equal zone_id, offer.fetch("zone_id")
  end

  def test_restore_refuses_a_zone_id_that_is_back_in_the_model
    _group, zone_id = exploded_zone
    invoke("ph_composer.zones.restore", { "parent_path" => [], "zone_id" => zone_id })

    result = invoke("ph_composer.zones.restore", { "parent_path" => [], "zone_id" => zone_id })

    assert_equal %w[refused zone.identity_in_use none], result.values_at("status", "code", "effect")
  end

  # Make Zone independent: the copy gets its own Faces, then its own identity, in one operation.
  def test_make_independent_isolates_a_shared_copy_and_leaves_the_original_untouched
    original, copy = shared_copy(700)
    before = original_state(original)
    params = { "zone_path" => [copy.persistent_id] }
    preview = API.preview(:context => @context, :name => MAKE_INDEPENDENT, :params => params)

    result = invoke(MAKE_INDEPENDENT, params, :digest => preview.fetch("proposal_digest"))

    assert_equal %w[completed committed], result.values_at("status", "effect")
    assert result.dig("value", "storage_isolated")
    assert_equal before, original_state(original)
    refute_equal original.definition.persistent_id, copy.definition.persistent_id
    assert_empty copy.entities.to_a & original.entities.to_a
    new_id = ZONE_STORE.read(copy).fetch("id")
    assert_equal result.dig("value", "zone_id"), new_id
    copy.entities.to_a.each { |face| assert_equal new_id, STAMP_STORE.read(face).fetch("zone_id") }
    assert_empty copy.entities.to_a.map { |f| FACE_STORE.read(f).fetch("id") } &
                 original.entities.to_a.map { |f| FACE_STORE.read(f).fetch("id") }
    assert_equal %w[found found], zone_states
  end

  # The copy's Face entities exist only after Make Unique, so the outcome names those, not the shared ones.
  def test_make_independent_reports_the_isolated_faces_it_wrote
    original, copy = shared_copy(720)

    result = invoke(MAKE_INDEPENDENT, { "zone_path" => [copy.persistent_id] })

    faces = result.fetch("affected").select { |entry| entry.fetch("kind") == "face" }
    assert_equal copy.entities.to_a.map(&:persistent_id).sort,
                 faces.map { |entry| entry.dig("reference", "entity_path").last }.sort
    refute_includes faces.map { |entry| entry.dig("reference", "entity_path").last },
                    original.entities.to_a.first.persistent_id
  end

  def test_make_independent_retires_the_copied_pair_and_keeps_the_original_pair
    left, right = solved_pair
    copy = Sketchup::Group.new(915, right.entities)
    copy.set_attribute("ph_composer.zone", "record", right.get_attribute("ph_composer.zone", "record"))
    @model.entities << copy
    treat_duplicates_as_existing(@model)

    result = invoke(MAKE_INDEPENDENT, { "zone_path" => [copy.persistent_id] })

    assert_equal 1, result.dig("value", "retired_pairs")
    refute FACE_STORE.read(copy.entities.to_a.first).key?("adjacency")
    [left, right].each do |group|
      assert_equal "Surface", FACE_STORE.read(group.entities.to_a.first).fetch("boundary_condition")
    end
  end

  def test_make_independent_reidentifies_a_copy_that_already_has_its_own_storage
    _original, copy = copied_zone

    result = invoke(MAKE_INDEPENDENT, { "zone_path" => [copy.persistent_id] })

    assert_equal %w[completed committed], result.values_at("status", "effect")
    refute result.dig("value", "storage_isolated")
    assert_equal %w[found found], zone_states
  end

  def test_make_independent_refuses_what_it_cannot_isolate_and_says_what_to_do
    unique = box_group(740, 2)
    @model.entities << unique
    make_zone(unique)
    _original, locked = shared_copy(760)
    locked.locked = true

    assert_equal %w[refused zone.identity_unique],
                 invoke(MAKE_INDEPENDENT, { "zone_path" => [740] }).values_at("status", "code")
    refusal = invoke(MAKE_INDEPENDENT, { "zone_path" => [locked.persistent_id] })
    assert_equal %w[refused target.locked none], refusal.values_at("status", "code", "effect")
    assert_match(/Unlock it first/, refusal.fetch("message"))
  end

  # A floor copied as one Group shares its Zones through the parent: isolating only the inner Zone
  # would make Groups unique inside the original floor's contents (P2, S5).
  def test_make_independent_refuses_a_zone_whose_parent_group_is_still_shared
    zone = box_group(780, 2)
    floor = Sketchup::Group.new(790, Sketchup::Entities.new([zone]))
    @model.entities << floor
    ZONE_STORE.write(zone, zone_record("zon_#{'f' * 12}"))
    twin = Sketchup::Group.new(795, floor.entities)
    @model.entities << twin
    treat_duplicates_as_existing(@model)

    result = invoke(MAKE_INDEPENDENT, { "zone_path" => [795, 780] })

    assert_equal %w[refused target.shared_definition none], result.values_at("status", "code", "effect")
    assert_match(/Open that Group with Edit Group/, result.fetch("message"),
                 "SketchUp 2026's Group menu has no Make Unique; opening the Group makes it unique")
  end

  def test_make_independent_refuses_inside_a_component
    group = box_group(800, 2)
    ZONE_STORE.write(group, zone_record("zon_#{'c' * 12}"))
    definition = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([group]), :name => "unit")
    instance = @model.entities.add_instance(definition, Geom::Transformation.new)
    @model.entities.add_instance(definition, Geom::Transformation.new)
    treat_duplicates_as_existing(@model)

    result = invoke(MAKE_INDEPENDENT, { "zone_path" => [instance.persistent_id, group.persistent_id] })

    assert_equal %w[refused target.shared_definition none], result.values_at("status", "code", "effect")
    assert_match(/Explode that component first/, result.fetch("message"),
                 "Make Unique leaves a component placement refused; Explode works")
  end

  # Faces inside a child Group: making only the Zone's Group unique leaves that child shared with the
  # original's (P2 S5), so the child is isolated too, and the read offers only what apply can do.
  def test_make_independent_isolates_a_nested_face_group_and_leaves_the_original_untouched
    original, copy = nested_copy(1100)
    original_child = original.entities.to_a.first
    before = original_child.entities.to_a.map { |face| FACE_STORE.read(face) }
    row = zones_value.fetch("zones").find { |zone| zone.dig("reference", "zone_path") == [copy.persistent_id] }
    assert row.dig("independence", "available")
    params = { "zone_path" => [copy.persistent_id] }
    preview = API.preview(:context => @context, :name => MAKE_INDEPENDENT, :params => params)

    result = invoke(MAKE_INDEPENDENT, params, :digest => preview.fetch("proposal_digest"))

    assert_equal %w[completed committed], result.values_at("status", "effect")
    copy_child = copy.entities.to_a.first
    refute_equal original_child.definition.persistent_id, copy_child.definition.persistent_id
    assert_equal before, original_child.entities.to_a.map { |face| FACE_STORE.read(face) }
    new_id = ZONE_STORE.read(copy).fetch("id")
    copy_child.entities.to_a.each { |face| assert_equal new_id, STAMP_STORE.read(face).fetch("zone_id") }
    assert_equal %w[found found], zone_states
  end

  def test_make_independent_is_not_offered_when_member_faces_sit_inside_a_component
    faces = 2.times.map { |index|
      Sketchup::Face.new(1201 + index, {}, :points => [point(0, 0, index),
                                                       point(1, 0, index),
                                                       point(1, 1, index)])
    }
    definition = Sketchup::ComponentDefinition.new(Sketchup::Entities.new(faces), :name => "panel")
    holder = Sketchup::Group.new(1200, Sketchup::Entities.new([]))
    holder.entities.add_instance(definition, Geom::Transformation.new)
    ZONE_STORE.write(holder, zone_record("zon_#{'d' * 12}"))
    stamp = PhComposer::Zones::Schema.stamp(ZONE_STORE.read(holder))
    faces.each { |face| STAMP_STORE.write(face, stamp) }
    copy = Sketchup::Group.new(1250, holder.entities)
    copy.set_attribute("ph_composer.zone", "record", holder.get_attribute("ph_composer.zone", "record"))
    @model.entities << holder
    @model.entities << copy
    treat_duplicates_as_existing(@model)

    row = zones_value.fetch("zones").find { |zone| zone.dig("reference", "zone_path") == [1250] }
    result = invoke(MAKE_INDEPENDENT, { "zone_path" => [1250] })

    refute row.dig("independence", "available")
    assert_equal %w[refused target.shared_definition none], result.values_at("status", "code", "effect")
    assert_match(/inside a component/, result.fetch("message"))
  end

  def test_a_failed_make_independent_rolls_back_storage_and_records
    original, copy = shared_copy(820)
    before = [ZONE_STORE.read(copy), copy.definition.instances.length]
    store = FACE_STORE
    store.singleton_class.send(:alias_method, :__test_write, :write)
    store.define_singleton_method(:write) { |_entity, _record| raise "disk full" }

    result = invoke(MAKE_INDEPENDENT, { "zone_path" => [copy.persistent_id] })

    assert_equal "failed", result.fetch("status")
    assert_equal "rolled_back", result.fetch("effect")
    live = @model.entities.to_a.find { |entity| entity.persistent_id == copy.persistent_id }
    assert_equal before, [ZONE_STORE.read(live), live.definition.instances.length]
    assert_equal %w[shared_definition shared_definition], zone_states
    refute_nil original
  ensure
    store.singleton_class.send(:remove_method, :write)
    store.singleton_class.send(:alias_method, :write, :__test_write)
    store.singleton_class.send(:remove_method, :__test_write)
  end

  def test_a_preview_goes_stale_when_a_copied_face_changes
    _original, copy = shared_copy(840)
    params = { "zone_path" => [copy.persistent_id] }
    preview = API.preview(:context => @context, :name => MAKE_INDEPENDENT, :params => params)
    face = copy.entities.to_a.first
    FACE_STORE.write(face, FACE_STORE.read(face).merge("user_data" => { "note" => "changed" }))

    result = invoke(MAKE_INDEPENDENT, params, :digest => preview.fetch("proposal_digest"),
                                              :revision => preview["revision"])

    assert_equal "refused", result.fetch("status")
    assert_equal "none", result.fetch("effect")
  end

  def test_the_zones_read_does_not_offer_what_the_copy_rules_would_refuse
    _original, copy = shared_copy(960)
    envelope = COPY_EXTENSION.envelope("external_id" => "atz_000000000001")
    ZONE_STORE.write(copy, ZONE_STORE.read(copy).merge("extension_data" => { COPY_EXTENSION.namespace => envelope }))

    row = zones_value.fetch("zones").find { |zone| zone.dig("reference", "zone_path") == [copy.persistent_id] }

    refute row.dig("independence", "available")
    assert_equal "copy.rule_missing", row.dig("independence", "code")
  end

  def test_the_zones_read_says_whether_make_independent_applies
    shared_copy(860)
    unique = box_group(880, 2)
    @model.entities << unique
    make_zone(unique)

    rows = zones_value.fetch("zones").to_h { |zone| [zone.dig("reference", "zone_path"), zone["independence"]] }

    assert_nil rows.fetch([880])
    assert rows.fetch([910]).fetch("available")
    assert rows.fetch([860]).fetch("available"), "both occurrences carry the id; either can take a new one"
  end

  # A child step the transition tests add: it records when it applied and what the Zone read then.
  class ChildStep
    attr_reader :affected

    def initialize(log, group_id)
      @log = log
      @group_id = group_id
      @affected = []
    end

    def descriptor
      { "name" => "child_probe" }
    end

    def apply(model, _slots)
      group = model.entities.to_a.find { |entity| entity.persistent_id == @group_id }
      @log << [:applied, PhComposer::Zones::ZONE_STORE.read(group).fetch("id")]
    end

    def restore
      @log << [:restored]
    end
  end

  class UnrestorableStep < ChildStep
    undef_method :restore
  end

  def child_feature(id, requires: ["ph_composer.zones"], refuses: [], &handler)
    part = PhComposer::Records::RecordKind.new(:id => "#{id}.part", :label => "Child part", :schema_version => 1,
                                               :id_prefix => "cpt", :fields => [])
    Module.new do
      define_singleton_method(:install) do |registry|
        scope = registry.feature(id, :contract_version => 1, :requires => requires)
        scope.record_kind(part)
        refuses.each { |code| scope.code(code, :description => "The child's records cannot follow the copy.") }
        scope.transition_contributor("#{id}.follow_zone_copy", :transition => PhComposer::Zones::TRANSITION,
                                                               :refuses => refuses, &handler)
      end
    end
  end

  def test_a_transition_contributor_must_require_the_feature_that_emits_it
    error = assert_raises(PhComposer::RegistrationError) do
      PhComposer::Registry.install([child_feature("test.child", :requires => []) { |*_args| [] }])
    end
    assert_equal ["registration.missing_dependency"], error.diagnostics.map(&:code)
    assert_includes error.diagnostics.first.message, "ph_composer.zones"
    refute PhComposer::Registry.installed?("test.child")
  end

  def test_a_contributor_runs_under_its_owner_after_the_zone_step_with_a_detached_description
    original, copy = shared_copy(900)
    old_id = ZONE_STORE.read(copy).fetch("id")
    log = []
    seen = []
    PhComposer::Registry.install([child_feature("test.child") do |request, proposal, description|
      seen << [request.owner, PhComposer::DeepCopy.call(description)]
      description["zone_path"] << 0
      proposal.add_step(ChildStep.new(log, description.fetch("zone_path").first), :scopes => [])
      [{ "kind" => "test.child.part", "id" => "cpt_000000000001" }]
    end])

    result = invoke(MAKE_INDEPENDENT, { "zone_path" => [copy.persistent_id] })

    assert_equal %w[completed committed], result.values_at("status", "effect")
    owner, description = seen.last
    assert_equal "test.child", owner
    assert_equal [copy.persistent_id], description.fetch("zone_path")
    assert_equal old_id, description.fetch("old_zone_id")
    assert_equal result.dig("value", "zone_id"), description.fetch("new_zone_id")
    assert_equal description.fetch("new_zone_id"), description.fetch("mapping").fetch(old_id)
    assert_kind_of Integer, description.fetch("revision")
    assert_equal [[:applied, description.fetch("new_zone_id")]], log
    refute_nil original
  end

  def test_a_contributed_step_that_cannot_be_restored_refuses_the_whole_transition
    _original, copy = shared_copy(940)
    PhComposer::Registry.install([child_feature("test.child") do |_request, proposal, description|
      proposal.add_step(UnrestorableStep.new([], description.fetch("zone_path").first), :scopes => [])
      []
    end])

    result = invoke(MAKE_INDEPENDENT, { "zone_path" => [copy.persistent_id] })

    refute_equal "completed", result.fetch("status")
    assert_equal "none", result.fetch("effect")
    assert_equal %w[shared_definition shared_definition], zone_states
  end

  def test_a_contributor_that_changes_an_earlier_step_refuses
    _original, copy = shared_copy(960)
    PhComposer::Registry.install([child_feature("test.child") do |_request, proposal, description|
      proposal.steps.unshift(ChildStep.new([], description.fetch("zone_path").first))
      []
    end])

    result = invoke(MAKE_INDEPENDENT, { "zone_path" => [copy.persistent_id] })

    assert_equal "proposal.contribution_replaced", result.fetch("code")
    assert_equal %w[shared_definition shared_definition], zone_states
  end

  def test_a_contributor_reporting_malformed_or_foreign_references_refuses
    _original, copy = shared_copy(970)
    PhComposer::Registry.install([child_feature("test.child") do |*_args|
      [nil, 123, { "kind" => "ph_composer.zones.zone", "id" => "zon_000000000001" }]
    end])

    result = invoke(MAKE_INDEPENDENT, { "zone_path" => [copy.persistent_id] })

    assert_equal "none", result.fetch("effect")
    refute_equal "completed", result.fetch("status")
    assert_equal %w[shared_definition shared_definition], zone_states
  end

  def test_a_contributor_refusal_is_discovered_on_the_emitting_action_and_answered
    _original, copy = shared_copy(990)
    code = "child.unsupported"
    PhComposer::Registry.install([child_feature("test.child", :refuses => [code]) do |*_args|
      raise PhComposer::CodedError.new(code, "The child's records cannot follow the copy.")
    end])

    result = invoke(MAKE_INDEPENDENT, { "zone_path" => [copy.persistent_id] })

    assert_equal code, result.fetch("code")
    described = API.describe(:name => MAKE_INDEPENDENT)
    assert_includes described.fetch("refuses"), { "code" => code, "owner" => "test.child",
                                                  "description" => "The child's records cannot follow the copy." }
    assert_equal [PhComposer::Zones::TRANSITION], described.fetch("transitions")
  end

  def test_a_contributor_that_raises_after_another_contributed_refuses_everything
    _original, copy = shared_copy(980)
    log = []
    first = child_feature("test.child_a") do |_request, proposal, description|
      proposal.add_step(ChildStep.new(log, description.fetch("zone_path").first), :scopes => [])
      []
    end
    second = child_feature("test.child_b") do |*_args|
      raise PhComposer::CodedError.new("target.changed", "The child's records changed.")
    end
    PhComposer::Registry.install([first, second])

    result = invoke(MAKE_INDEPENDENT, { "zone_path" => [copy.persistent_id] })

    assert_equal "target.changed", result.fetch("code")
    assert_equal "none", result.fetch("effect")
    assert_empty log
    assert_equal %w[shared_definition shared_definition], zone_states
  end

  private

  def register_copy_extension
    extension = COPY_EXTENSION
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

  def invoke(name, params, digest: nil, revision: nil)
    @sequence += 1
    request = { "sequence" => @sequence, "expected_revision" => revision || @session.revision }
    request["proposal_digest"] = digest if digest
    API.invoke(:context => @context, :name => name, :params => params, :request => request)
  end

  # A Zone with classified Faces and a copy made the way SketchUp makes one: a second Group over the
  # same definition, carrying a copy of the Zone record.
  def shared_copy(base)
    original = box_group(base, 3)
    @model.entities << original
    make_zone(original)
    classify_all
    copy = Sketchup::Group.new(base + 50, original.entities)
    copy.set_attribute("ph_composer.zone", "record", original.get_attribute("ph_composer.zone", "record"))
    @model.entities << copy
    treat_duplicates_as_existing(@model)
    [original, copy]
  end

  def original_state(group)
    [ZONE_STORE.read(group), group.entities.to_a, group.entities.to_a.map { |face| FACE_STORE.read(face) }]
  end

  # A Zone whose classified Faces sit in one child Group, and a copy over the same definition.
  def nested_copy(base)
    child = box_group(base + 10, 3)
    original = Sketchup::Group.new(base, Sketchup::Entities.new([child]))
    @model.entities << original
    make_zone(original)
    classify_all
    copy = Sketchup::Group.new(base + 50, original.entities)
    copy.set_attribute("ph_composer.zone", "record", original.get_attribute("ph_composer.zone", "record"))
    @model.entities << copy
    treat_duplicates_as_existing(@model)
    [original, copy]
  end

  def zone_record(id)
    { "id" => id, "schema_version" => 1, "name" => "Zone", "building_segment" => "Main Building", "level" => nil,
      "ground_depth_mm" => 0.0, "user_data" => {}, "extension_data" => {} }
  end

  def zones_value
    API.query(:context => @context, :name => "ph_composer.zones.list").fetch("value")
  end

  def zone_states
    zones_value.fetch("zones").map { |zone| zone.fetch("state") }
  end

  def restorable
    zones_value.fetch("restorable")
  end

  def make_zone(group)
    invoke("ph_composer.zones.make", { "parent_path" => [], "entity_ids" => [group.persistent_id] })
  end

  def classify_all
    faces = API.query(:context => @context, :name => "ph_composer.zones.faces.list").dig("value", "faces")
    invoke("ph_composer.zones.faces.classify", {
      "faces" => faces.map { |face| face.fetch("reference") },
      "intent" => { "face_type" => { "mode" => "set", "value" => "Wall" },
                    "boundary_condition" => { "mode" => "set", "value" => "Outdoors" } },
      "expected_values" => {}
    })
  end

  # A Zone with classified Faces, copied the way SketchUp copies one: every dictionary duplicated.
  def copied_zone
    original = box_group(300, 3)
    @model.entities << original
    make_zone(original)
    classify_all
    [original, duplicate_group(original, 400)]
  end

  def duplicate_group(group, base)
    faces = group.entities.to_a.each_with_index.map do |face, index|
      copy = Sketchup::Face.new(base + index + 1, {}, :points => face.outer_loop.vertices.map(&:position),
                                                      :normal => face.normal)
      %w[ph_composer.face_assignment ph_composer.zone_stamp].each do |dictionary|
        value = face.get_attribute(dictionary, "record")
        copy.set_attribute(dictionary, "record", value) if value
      end
      copy
    end
    copy = Sketchup::Group.new(base, Sketchup::Entities.new(faces))
    copy.set_attribute("ph_composer.zone", "record", group.get_attribute("ph_composer.zone", "record"))
    @model.entities << copy
    treat_duplicates_as_existing(@model)
    copy
  end

  def solved_pair
    metres = 1.0 / 0.0254
    outline = [point(0, 0, 0), point(0, 4 * metres, 0), point(0, 4 * metres, 3 * metres), point(0, 0, 3 * metres)]
    left = Sketchup::Face.new(501, {}, :points => outline, :normal => Geom::Vector3d.new(1, 0, 0))
    right = Sketchup::Face.new(502, {}, :points => outline.reverse, :normal => Geom::Vector3d.new(-1, 0, 0))
    groups = [Sketchup::Group.new(500, Sketchup::Entities.new([left])),
              Sketchup::Group.new(510, Sketchup::Entities.new([right]))]
    groups.each do |group|
      @model.entities << group
      make_zone(group)
    end
    classify_all
    references = zones_value.fetch("zones").map { |zone| zone.fetch("reference") }
    invoke("ph_composer.zones.solve_adjacency", { "zones" => references })
    groups
  end

  # Explode: the Group goes, its stamped Faces stay in the parent context with their payloads.
  def exploded_zone
    group = box_group(600, 3)
    @model.entities << group
    make_zone(group)
    # This fixture specifically proves the supported legacy Restore path. Managed Restore has its own cases.
    record = ZONE_STORE.read(group)
    legacy = record.reject { |key, _| %w[building_segment_id level_id choice_evidence].include?(key) }
                   .merge("schema_version" => 1, "name" => "Loft", "building_segment" => "Attic", "level" => "L2")
    ZONE_STORE.write(group, legacy)
    classify_all
    zone_id = ZONE_STORE.read(group).fetch("id")
    members = group.entities.to_a
    @model.entities.delete(group)
    members.each { |face| @model.entities << face }
    [group, zone_id]
  end

  def box_group(base, face_count)
    faces = face_count.times.map do |index|
      Sketchup::Face.new(base + index + 1, {}, :points => [point(0, 0, index), point(2, 0, index),
                                                           point(2, 2, index)])
    end
    Sketchup::Group.new(base, Sketchup::Entities.new(faces))
  end

  def point(x, y, z)
    Geom::Point3d.new(x, y, z)
  end
end
