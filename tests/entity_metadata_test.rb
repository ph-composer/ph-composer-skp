# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/window_record_fixtures"
require_relative "support/assembly_assignment_fixtures"

# Entity metadata through the owners' public operations (context/CONTRACTS.md, "Records and extension
# data"): Zone, Face and Window Unit reads report each envelope's status as a catalog read does, and
# each owner's update_metadata action replaces user_data and installed payloads under a pre-image, in
# one step and one Undo entry.
class EntityMetadataTest < PhComposerTestCase
  include WindowRecordFixtures
  include AssemblyAssignmentFixtures

  ZONES = "ph_composer.zones"
  WINDOWS = "ph_composer.windows"
  REVIEW = "probe.notes.review"
  LINK = "probe.notes.link"
  EMPTY = { "user_data" => {}, "extension_data" => {} }.freeze

  # A maintained extension at version 2, valid when its status is draft or checked, optionally naming a
  # Zone.
  module Review
    module_function

    def name
      "Review"
    end

    def install(registry)
      feature = registry.feature("probe.notes", :contract_version => 1,
                                                :requires => ["ph_composer.zones", "ph_composer.windows"])
      feature.extension(PhComposer::Records::Extension.new(
        :namespace => REVIEW, :schema_version => 2, :export_relevance => "local_only",
        :references => [{ "path" => "$.zone", "target_kind" => "ph_composer.zones.zone", "cardinality" => "one" }],
        :migrations => { 1 => ->(payload) { payload } },
        :validate => ->(payload) { %w[draft checked].include?(payload["status"]) ? [] : ["status is unknown"] }
      ))
      # A payload naming a Window, so a staged identity repair matters to its reference.
      feature.extension(PhComposer::Records::Extension.new(
        :namespace => LINK, :schema_version => 1, :export_relevance => "local_only",
        :references => [{ "path" => "$.unit", "target_kind" => "ph_composer.windows.unit", "cardinality" => "one" }]
      ))
    end
  end

  def setup
    super
    assignment_setup
    PhComposer::Registry.install([W]) unless PhComposer::Registry.installed?(W::FEATURE_ID)
    PhComposer::Registry.install([Review])
    points = [[0, 0, 0], [3000, 0, 0], [3000, 3000, 0], [0, 3000, 0]].map { |point| Geom::Point3d.new(*point) }
    @group = Sketchup::Group.new(1000, Sketchup::Entities.new([Sketchup::Face.new(1001, {}, :points => points)]))
    @model.entities << @group
    assert_equal "completed", assignment_invoke("#{ZONES}.make", "parent_path" => [],
                                                                 "entity_ids" => [1000]).fetch("status")
    assignment_classify(assignment_faces, "face_type" => { "mode" => "set", "value" => "Wall" },
                                          "boundary_condition" => { "mode" => "set", "value" => "Outdoors" })
    type_id = assignment_invoke("#{WINDOWS}.types.create", "values" => { "name" => "Metadata" }).dig("value", "id")
    placed = assignment_invoke("#{WINDOWS}.units.place", "host" => face.fetch("reference"), "type_id" => type_id,
                                                         "anchor" => "sill_center",
                                                         "offsets" => { "x_m" => 0.8, "y_m" => 1.0 })
    assert_equal "completed", placed.fetch("status"), placed.inspect
  end

  def zone
    assignment_query("#{ZONES}.all").fetch("zones").first
  end

  def face
    assignment_faces.first
  end

  def unit
    assignment_query("#{WINDOWS}.units.list").fetch("units").first
  end

  def envelope(version, payload)
    { "schema_version" => version, "payload" => payload,
      "references" => [{ "path" => "$.zone", "target_kind" => "ph_composer.zones.zone", "cardinality" => "one" }],
      "export_relevance" => "local_only" }
  end

  def update(name, reference, read, **fields)
    assignment_invoke(name, "updates" => [{ "reference" => reference,
                                            "expected_metadata" => read.slice("user_data", "extension_data") }
                                            .merge(fields.transform_keys(&:to_s))])
  end

  def test_entity_reads_report_each_envelope_status_and_absent_metadata_as_empty
    assert_equal({}, zone.fetch("extension_status"))
    assert_equal({}, unit.fetch("extension_status"))
    extension_data = { REVIEW => envelope(2, { "status" => "draft" }), "absent.extension" => envelope(1, {}) }
    record = PhComposer::Zones::ZONE_STORE.read(@group).merge("extension_data" => extension_data)
    PhComposer::Zones::ZONE_STORE.write(@group, record)
    revision = @session.revision
    read = zone
    assert_equal({ REVIEW => "understood", "absent.extension" => "unavailable" }, read.fetch("extension_status"))
    read.fetch("extension_status").clear
    assert_equal "understood", zone.dig("extension_status", REVIEW), "a read hands out a detached map"
    assert_equal revision, @session.revision
  end

  # Each of the five statuses, stored as an older or newer build or another installation would have
  # stored it, read through every owner's public read and compared with what a catalog read reports.
  def test_every_status_word_reaches_each_owners_read_as_a_catalog_read_reports_it
    catalog = PhComposer::Registry.current.catalog
    face_entity = PhComposer::Zones::Occurrences.resolve_face(@model, face.fetch("reference")).entity
    unit_item = PhComposer::Windows::Units::Occurrences.all(@model).first
    { "understood" => [REVIEW, envelope(2, { "status" => "draft" })], "invalid" => [REVIEW, envelope(2, {})],
      "outdated" => [REVIEW, envelope(1, {})], "unsupported" => [REVIEW, envelope(3, {})],
      "unavailable" => ["absent.extension", envelope(1, {})] }.each do |word, (namespace, row)|
      stored = { namespace => row }
      assert_equal({ namespace => word }, PhComposer::Records::Metadata.status_map({ "extension_data" => stored },
                                                                                   catalog), word)
      zone_record = PhComposer::Zones::ZONE_STORE.read(@group).merge("extension_data" => stored)
      PhComposer::Zones::ZONE_STORE.write(@group, zone_record)
      face_record = PhComposer::Zones::Faces::FACE_STORE.read(face_entity).merge("extension_data" => stored)
      PhComposer::Zones::Faces::FACE_STORE.write(face_entity, face_record)
      PhComposer::Windows::Units.write(unit_item.entity, unit_item.record.merge("extension_data" => stored))
      [zone, face, unit].each { |row| assert_equal({ namespace => word }, row.fetch("extension_status"), word) }
    end
  end

  def test_a_zone_update_replaces_user_data_and_a_payload_in_one_undo_and_reads_back
    before = zone
    result = update("#{ZONES}.update_metadata", before.fetch("reference"), before,
                    :user_data => { "firm" => { "note" => "checked" } },
                    :extension_payloads => { REVIEW => { "status" => "checked" } })
    assert_equal "committed", result.fetch("effect"), result.inspect
    assert_equal({ REVIEW => "understood" }, result.dig("value", "updates", 0, "extension_status"))
    after = zone
    assert_equal({ "firm" => { "note" => "checked" } }, after.fetch("user_data"))
    assert_equal({ "status" => "checked" }, after.dig("extension_data", REVIEW, "payload"))
    assert_equal before.fetch("values"), after.fetch("values")
    @model.undo
    assert_equal before.slice("user_data", "extension_data"), zone.slice("user_data", "extension_data")
  end

  def test_a_face_and_a_unit_update_through_their_owners
    face_before = face
    assert_equal "committed", update("#{ZONES}.faces.update_metadata", face_before.fetch("reference"), face_before,
                                     :user_data => { "firm" => { "tag" => "north face" } }).fetch("effect")
    assert_equal({ "firm" => { "tag" => "north face" } }, face.fetch("user_data"))
    assert_equal face_before.fetch("values"), face.fetch("values")
    unit_before = unit
    result = update("#{WINDOWS}.units.update_metadata", unit_before.fetch("reference"), unit_before,
                    :user_data => { "firm" => { "tag" => "north window" } })
    assert_equal "committed", result.fetch("effect"), result.inspect
    assert_equal({ "firm" => { "tag" => "north window" } }, unit.fetch("user_data"))
    assert_equal unit_before.fetch("values"), unit.fetch("values")
  end

  def test_refusals_write_nothing
    read = zone
    reference = read.fetch("reference")
    cases = {
      "validation.failed" => { :extension_payloads => { REVIEW => { "status" => "unknown" } } },
      "extension.unavailable" => { :extension_payloads => { "absent.extension" => {} } },
      "reference.invalid" => { :extension_payloads => { REVIEW => { "status" => "draft", "zone" => "zon_missing" } } }
    }
    cases.each do |code, fields|
      result = update("#{ZONES}.update_metadata", reference, read, **fields)
      assert_equal code, result.fetch("code"), "#{code}: #{result.inspect}"
      assert_equal read.slice("user_data", "extension_data"), zone.slice("user_data", "extension_data")
    end
    stale = update("#{ZONES}.update_metadata", reference, read.merge("user_data" => { "old" => true }),
                   :user_data => { "new" => true })
    assert_equal "target.changed", stale.fetch("code")
    [%w[outdated 1 extension.migration_required], %w[newer 3 extension.schema_unsupported]].each do |_, version, code|
      record = PhComposer::Zones::ZONE_STORE.read(@group)
      record["extension_data"] = { REVIEW => envelope(version.to_i, { "status" => "draft" }) }
      PhComposer::Zones::ZONE_STORE.write(@group, record)
      current = zone
      result = update("#{ZONES}.update_metadata", reference, current,
                      :extension_payloads => { REVIEW => { "status" => "checked" } })
      assert_equal code, result.fetch("code"), result.inspect
    end
  end

  def test_a_batch_collapses_repeats_refuses_conflicts_and_writes_nothing_for_a_no_op
    read = zone
    entry = { "reference" => read.fetch("reference"), "user_data" => { "a" => 1 },
              "expected_metadata" => EMPTY }
    conflicting = entry.merge("user_data" => { "a" => 2 })
    assert_equal "params.invalid", assignment_invoke("#{ZONES}.update_metadata",
                                                     "updates" => [entry, conflicting]).fetch("code")
    assert_equal "params.invalid", assignment_invoke("#{ZONES}.update_metadata",
                                                     "updates" => [entry.reject { |key, _| key == "user_data" }])
      .fetch("code")
    assert_equal "committed", assignment_invoke("#{ZONES}.update_metadata", "updates" => [entry, entry])
      .fetch("effect")
    revision = @session.revision
    again = { "reference" => read.fetch("reference"), "user_data" => { "a" => 1 },
              "expected_metadata" => { "user_data" => { "a" => 1 }, "extension_data" => {} } }
    result = assignment_invoke("#{ZONES}.update_metadata", "updates" => [again])
    assert_equal "none", result.fetch("effect"), "writing what is stored opens no step"
    assert_equal revision, @session.revision
  end

  def test_a_face_in_a_locked_zone_and_an_unrecorded_face_refuse_and_an_ordinary_edit_keeps_metadata
    read = zone
    update("#{ZONES}.update_metadata", read.fetch("reference"), read, :user_data => { "keep" => true })
    edited = zone
    assignment_invoke("#{ZONES}.update", "reference" => edited.fetch("reference"),
                                         "values" => edited.fetch("values").merge("name" => "Renamed"),
                                         "expected_values" => edited.fetch("values"))
    assert_equal({ "keep" => true }, zone.fetch("user_data"))
    # Each owner's resolver decides: a Face inside a locked Zone is not writable.
    @group.locked = true
    locked = update("#{ZONES}.faces.update_metadata", face.fetch("reference"), face, :user_data => {})
    assert_equal "target.locked", locked.fetch("code")
    @group.locked = false
    mismatched = face.fetch("reference").merge("entity_id" => "fac_Zz99Zz99Zz99")
    result = update("#{ZONES}.faces.update_metadata", mismatched, face, :user_data => {})
    assert_includes %w[target.changed target.not_found], result.fetch("code"), result.inspect
  end

  def test_a_face_with_no_record_refuses_and_gains_none
    read = face
    entity = PhComposer::Zones::Occurrences.resolve_face(@model, read.fetch("reference")).entity
    PhComposer::Zones::Faces::FACE_STORE.delete(entity)
    revision = @session.revision
    result = update("#{ZONES}.faces.update_metadata", read.fetch("reference"), EMPTY, :user_data => { "x" => 1 })
    assert_equal "target.not_found", result.fetch("code"), result.inspect
    assert_nil PhComposer::Zones::Faces::FACE_STORE.read(entity)
    assert_equal revision, @session.revision
  end

  # Every owner's update_metadata plans through Records::Metadata.planned, so one owner shows the rule: a
  # record stored without user_data reads it as {}, and clearing it changes nothing.
  def test_clearing_a_map_a_legacy_record_never_stored_writes_nothing
    entity = PhComposer::Zones::Occurrences.resolve_face(@model, face.fetch("reference")).entity
    legacy = PhComposer::Zones::Faces::FACE_STORE.read(entity)
                                                 .reject { |key, _| %w[user_data extension_data].include?(key) }
    store = PhComposer::Zones::Faces::FACE_STORE
    store.write(entity, legacy)
    text = entity.get_attribute(store.dictionary, store.key)
    revision = @session.revision
    result = update("#{ZONES}.faces.update_metadata", face.fetch("reference"), EMPTY, :user_data => {})
    assert_equal %w[completed none], result.values_at("status", "effect"), result.inspect
    assert_equal text, entity.get_attribute(store.dictionary, store.key)
    assert_equal revision, @session.revision
    kept = PhComposer::Records::Metadata.updated({ "user_data" => {} }, nil, :user_data => {})
    assert_equal({ "user_data" => {} }, kept, "a stored empty map stays stored")
  end

  def test_the_unit_action_repairs_a_copied_unit_first
    original = PhComposer::Windows::Units::Occurrences.all(@model).first
    copy = @group.entities.add_instance(original.entity.definition,
                                        Geom::Transformation.translation([200, 0, 0]) * original.entity.transformation)
    copy.glued_to = original.entity.glued_to
    PhComposer::Windows::Units.write(copy, original.record)
    read = unit
    result = update("#{WINDOWS}.units.update_metadata", read.fetch("reference"), read, :user_data => { "x" => 1 })
    assert_equal "committed", result.fetch("effect"), result.inspect
    ids = PhComposer::Windows::Units::Occurrences.all(@model).map { |item| item.record.fetch("id") }
    assert_equal 2, ids.uniq.length, "the copy got its own identity in the same step"
  end

  def copy_first_unit
    original = PhComposer::Windows::Units::Occurrences.all(@model).first
    copy = @group.entities.add_instance(original.entity.definition,
                                        Geom::Transformation.translation([200, 0, 0]) * original.entity.transformation)
    copy.glued_to = original.entity.glued_to
    PhComposer::Windows::Units.write(copy, original.record)
    [original, copy]
  end

  def copy_row(copy)
    assignment_query("#{WINDOWS}.units.list").fetch("units").find do |row|
      row.dig("reference", "entity_path").last == copy.persistent_id
    end
  end

  def test_a_copy_being_repaired_takes_its_metadata_under_its_repaired_identity
    _original, copy = copy_first_unit
    read = copy_row(copy)
    result = update("#{WINDOWS}.units.update_metadata", read.fetch("reference"), read, :user_data => { "x" => 1 })
    assert_equal "committed", result.fetch("effect"), result.inspect
    repaired = result.dig("value", "updates", 0, "reference")
    refute_equal read.dig("reference", "unit_id"), repaired.fetch("unit_id")
    assert_equal repaired, copy_row(copy).fetch("reference")
    assert_equal({ "x" => 1 }, copy_row(copy).fetch("user_data"))
  end

  def test_a_no_op_on_a_copy_being_repaired_reports_its_repaired_reference
    _original, copy = copy_first_unit
    read = copy_row(copy)
    no_op = update("#{WINDOWS}.units.update_metadata", read.fetch("reference"), read,
                   :user_data => read.fetch("user_data"))
    assert_equal "committed", no_op.fetch("effect"), "the repair still commits"
    assert_equal copy_row(copy).fetch("reference"), no_op.dig("value", "updates", 0, "reference")
  end

  def test_a_payload_naming_the_retained_original_resolves_while_its_copy_is_repaired
    original, = copy_first_unit
    read = unit
    id = original.record.fetch("id")
    result = update("#{WINDOWS}.units.update_metadata", read.fetch("reference"), read,
                    :extension_payloads => { LINK => { "unit" => id } })
    assert_equal "committed", result.fetch("effect"), result.inspect
  end

  def test_a_batch_refused_late_or_failing_at_apply_writes_none_of_its_targets
    original, = copy_first_unit
    assignment_invoke("#{WINDOWS}.units.repair_copied_identities", "units" => [unit.fetch("reference")])
    rows = assignment_query("#{WINDOWS}.units.list").fetch("units")
    assert_equal 2, rows.length
    entries = rows.map do |row|
      { "reference" => row.fetch("reference"), "user_data" => { "batch" => true },
        "expected_metadata" => row.slice("user_data", "extension_data") }
    end
    stale = entries.dup
    stale[1] = stale[1].merge("expected_metadata" => { "user_data" => { "old" => true }, "extension_data" => {} })
    assert_equal "target.changed", assignment_invoke("#{WINDOWS}.units.update_metadata", "updates" => stale)
      .fetch("code")
    assert(assignment_query("#{WINDOWS}.units.list").fetch("units").none? { |row| row["user_data"]["batch"] })

    revision = @session.revision
    write = PhComposer::Windows::Units.method(:write)
    calls = 0
    PhComposer::Windows::Units.define_singleton_method(:write) do |entity, record|
      calls += 1
      raise IOError, "injected second write" if calls == 2

      write.call(entity, record)
    end
    begin
      failed = assignment_invoke("#{WINDOWS}.units.update_metadata", "updates" => entries)
    ensure
      PhComposer::Windows::Units.define_singleton_method(:write, write)
    end
    assert_equal %w[failed rolled_back], failed.values_at("status", "effect"), failed.inspect
    assert_equal revision, @session.revision
    assert(assignment_query("#{WINDOWS}.units.list").fetch("units").none? { |row| row["user_data"]["batch"] })
    assert original
  end
end
