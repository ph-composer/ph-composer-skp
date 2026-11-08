# frozen_string_literal: true

require_relative "test_helper"

class ZoneOptionsTest < PhComposerTestCase
  Z = PhComposer::Zones
  O = Z::Options
  API = PhComposer::API

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
  end

  def query(name = "#{O::PREFIX}.all", params = {})
    result = API.query(:context => @context, :name => name, :params => params)
    assert_equal "completed", result.fetch("status"), result.inspect
    result.fetch("value")
  end

  def invoke(name, params, digest = nil)
    @sequence += 1
    request = { "sequence" => @sequence, "expected_revision" => @session.revision }
    request["proposal_digest"] = digest if digest
    API.invoke(:context => @context, :name => name, :params => params, :request => request)
  end

  def legacy(id = "zon_AAAAAAAAAAAA", segment = "House", level = "Level 1")
    { "id" => id, "schema_version" => 1, "name" => "Zone", "building_segment" => segment,
      "level" => level, "ground_depth_mm" => 125.0, "user_data" => { "firm" => { "note" => "keep" } },
      "extension_data" => {} }
  end

  def add_zone(id = 100, record = legacy)
    face = Sketchup::Face.new(id + 1)
    group = Sketchup::Group.new(id, Sketchup::Entities.new([face]))
    @model.entities << group
    Z::ZONE_STORE.write(group, record)
    Z::STAMP_STORE.write(face, Z::Schema.stamp(record))
    [group, face]
  end

  def mappings
    query.fetch("adoption").fetch("sources").map do |source|
      { "source" => source.fetch("key"), "target_id" => nil, "name" => source.fetch("name"),
        "colour" => source.fetch("colour") }
    end
  end

  def adopt
    result = invoke("#{O::PREFIX}.adopt", "mappings" => mappings)
    assert_equal "completed", result.fetch("status"), result.inspect
    result
  end

  def manage_params(collection)
    snapshot = query
    list = snapshot.fetch(collection == "level" ? "levels" : "building_segments").map { |row|
      row.fetch("values").slice("name", "colour").merge("id" => row.fetch("id"))
    }
    { "collection" => collection, "options" => PhComposer::DeepCopy.call(list), "expected_options" => list,
      "default_segment_id" => snapshot.fetch("default_segment_id"),
      "expected_default_segment_id" => snapshot.fetch("default_segment_id"), "replacements" => {} }
  end

  def test_reading_an_empty_model_creates_no_records_or_settings
    before = @model.attribute_dictionaries&.to_a
    value = query
    assert_empty value.fetch("building_segments")
    assert_empty value.fetch("levels")
    assert_nil value.fetch("default_segment_id")
    refute value.dig("adoption", "required")
    before.nil? ? assert_nil(@model.attribute_dictionaries) : assert_equal(before, @model.attribute_dictionaries.to_a)
  end

  def test_managed_export_preflight_requires_adoption_for_pasted_legacy_zones
    add_zone
    assert_empty query("#{Z::FEATURE_ID}.export_preflight").fetch("findings")
    adopt
    pasted, = add_zone(200, legacy("zon_BBBBBBBBBBBB"))
    other, = add_zone(300, legacy("zon_CCCCCCCCCCCC", "Annex", nil))
    before = [Z::ZONE_STORE.read(pasted), Z::ZONE_STORE.read(other)]
    revision = @session.revision

    assert query.dig("adoption", "required")
    findings = query("#{Z::FEATURE_ID}.export_preflight").fetch("findings")
    assert_equal %w[zon_BBBBBBBBBBBB zon_CCCCCCCCCCCC], findings.map { |row| row.fetch("object_id") }.sort
    assert findings.all? { |row| row.fetch("code") == "zone.options_adoption_required" && row.fetch("blocks_export") }
    assert findings.all? { |row| row.fetch("message").include?("Adopt") }
    outcome = API.export_preflight(:context => @context)
    assert_equal "completed", outcome.fetch("status"), outcome.inspect
    blockers = outcome.dig("value", "findings").select { |row| row.fetch("code") == "zone.options_adoption_required" }
    assert_equal findings.map { |row| row.fetch("object_id") }.sort, blockers.map { |row| row.fetch("object_id") }.sort
    assert_equal revision, @session.revision
    assert_equal before, [Z::ZONE_STORE.read(pasted), Z::ZONE_STORE.read(other)]

    snapshot = query
    choices = mappings.map do |choice|
      source = snapshot.dig("adoption", "sources").find { |row| row.fetch("key") == choice.fetch("source") }
      collection = source.fetch("collection") == "level" ? "levels" : "building_segments"
      existing = snapshot.fetch(collection).find { |row| row.dig("values", "name") == source.fetch("name") }
      choice.merge("target_id" => existing && existing.fetch("id"))
    end
    result = invoke("#{O::PREFIX}.adopt", "mappings" => choices)
    assert_equal "completed", result.fetch("status"), result.inspect
    assert_empty query("#{Z::FEATURE_ID}.export_preflight").fetch("findings")
  end

  def test_fresh_managed_default_also_blocks_pasted_legacy_export
    group = Sketchup::Group.new(100)
    @model.entities << group
    result = invoke("#{Z::FEATURE_ID}.make", "parent_path" => [], "entity_ids" => [100])
    assert_equal "completed", result.fetch("status"), result.inspect
    segment = query.fetch("building_segments").first
    add_zone(200, legacy("zon_BBBBBBBBBBBB", segment.dig("values", "name"), nil))

    findings = query("#{Z::FEATURE_ID}.export_preflight").fetch("findings")
    assert_equal ["zone.options_adoption_required"], findings.map { |row| row.fetch("code") }
    assert_equal ["zon_BBBBBBBBBBBB"], findings.map { |row| row.fetch("object_id") }
  end

  def test_first_make_names_the_default_segment_neutrally_not_after_the_file
    @model.path = "/projects/02_Working.skp"
    @model.entities << Sketchup::Group.new(100)
    result = invoke("#{Z::FEATURE_ID}.make", "parent_path" => [], "entity_ids" => [100])
    assert_equal "completed", result.fetch("status"), result.inspect
    assert_equal ["Building"], query.fetch("building_segments").map { |choice| choice.dig("values", "name") }
  end

  def test_first_make_seeds_default_and_nullable_level_in_one_undo
    group = Sketchup::Group.new(100)
    @model.entities << group
    result = invoke("#{Z::FEATURE_ID}.make", "parent_path" => [], "entity_ids" => [100])
    assert_equal "completed", result.fetch("status"), result.inspect
    zone = Z::ZONE_STORE.read(group)
    assert_equal 2, zone.fetch("schema_version")
    assert_nil zone.fetch("level_id")
    assert_equal zone.fetch("building_segment_id"), query.fetch("default_segment_id")
    @model.undo
    assert_empty query.fetch("building_segments")
    assert_nil query.fetch("default_segment_id")
    @model.redo
    assert_equal zone.fetch("building_segment_id"), query.fetch("default_segment_id")
  end

  def test_adoption_is_previewed_without_writes_and_preserves_records_stamps_metadata_undo
    group, face = add_zone
    before = Z::ZONE_STORE.read(group)
    stamp = Z::STAMP_STORE.read(face)
    choices = mappings
    assert query.dig("adoption", "required")
    assert_equal before, Z::ZONE_STORE.read(group)
    preview = API.preview(:context => @context, :name => "#{O::PREFIX}.adopt", :params => { "mappings" => choices })
    assert_equal "completed", preview.fetch("status"), preview.inspect
    result = invoke("#{O::PREFIX}.adopt", { "mappings" => choices }, preview.fetch("proposal_digest"))
    assert_equal "completed", result.fetch("status"), result.inspect
    after = Z::ZONE_STORE.read(group)
    assert_equal before.slice("id", "name", "ground_depth_mm", "user_data", "extension_data"),
                 after.slice("id", "name", "ground_depth_mm", "user_data", "extension_data")
    assert_equal after.values_at("building_segment_id", "level_id"),
                 Z::STAMP_STORE.read(face).values_at("building_segment_id", "level_id")
    refute query.dig("adoption", "required")
    @model.undo
    current = @model.entities.to_a.first
    assert_equal before, Z::ZONE_STORE.read(current)
    assert_equal stamp, Z::STAMP_STORE.read(current.entities.to_a.first)
    assert_empty query.fetch("building_segments")
    @model.redo
    assert_equal after, Z::ZONE_STORE.read(@model.entities.to_a.first)
  end

  def test_equivalent_legacy_names_require_explicit_survivor_and_keep_its_export_key
    add_zone(100, legacy("zon_AAAAAAAAAAAA", "House", "Level-1"))
    add_zone(200, legacy("zon_BBBBBBBBBBBB", "House", "level 1"))
    choices = mappings
    result = invoke("#{O::PREFIX}.adopt", "mappings" => choices)
    assert_equal ["refused", "zone.option_duplicate", "none"], result.values_at("status", "code", "effect")
    levels = query.dig("adoption", "sources").select { |source| source.fetch("collection") == "level" }
    choices.find { |choice|
      choice.fetch("source") == levels.last.fetch("key")
    }["target_source"] = levels.first.fetch("key")
    result = invoke("#{O::PREFIX}.adopt", "mappings" => choices)
    assert_equal "completed", result.fetch("status"), result.inspect
    assert_equal 1, query.fetch("levels").length
  end

  def test_non_ascii_names_and_null_level_are_preserved
    group, = add_zone(100, legacy("zon_AAAAAAAAAAAA", "Bâtiment é", nil))
    adopt
    assert_nil Z::ZONE_STORE.read(group).fetch("level_id")
    assert_equal "Bâtiment é", query.dig("building_segments", 0, "values", "name")
    assert_equal O.export_identifier("Bâtiment é"), query.dig("building_segments", 0, "values", "export_identifier")
  end

  def test_rename_colour_updates_evidence_and_retains_identity_and_export_key
    group, face = add_zone
    adopt
    before = Z::ZONE_STORE.read(group)
    identifier = query.dig("building_segments", 0, "values", "export_identifier")
    params = manage_params("building_segment")
    params.fetch("options").first.merge!("name" => "Renamed", "colour" => "#123456")
    result = invoke("#{O::PREFIX}.manage", params)
    assert_equal "completed", result.fetch("status"), result.inspect
    assert_equal before.fetch("building_segment_id"), Z::ZONE_STORE.read(group).fetch("building_segment_id")
    assert_equal identifier, query.dig("building_segments", 0, "values", "export_identifier")
    assert_equal "Renamed", Z::STAMP_STORE.read(face).dig("choice_evidence", "building_segment", "name")
    assert_equal [18, 52, 86], Z::ColourModes.option_entries(
      PhComposer::HandlerRequest.for(@session, :owner => Z::FEATURE_ID, :name => "colour"), "building_segment"
    ).first.colour
  end

  def test_invalid_colour_duplicate_and_stale_collection_refuse_atomically
    add_zone
    adopt
    ["invalid", "#12345"].each do |colour|
      params = manage_params("level")
      params.fetch("options").first["colour"] = colour
      result = invoke("#{O::PREFIX}.manage", params)
      assert_equal "refused", result.fetch("status")
    end
    params = manage_params("level")
    params.fetch("options") << { "id" => "new:duplicate", "name" => "level_1", "colour" => "#112233" }
    result = invoke("#{O::PREFIX}.manage", params)
    assert_equal "zone.option_duplicate", result.fetch("code"), result.inspect
    assert_equal 1, query.fetch("levels").length
    params = manage_params("level")
    params.fetch("expected_options").first["name"] = "Stale"
    assert_equal "target.changed", invoke("#{O::PREFIX}.manage", params).fetch("code")
  end

  def test_orphan_only_usage_clear_and_undo
    record = legacy
    face = Sketchup::Face.new(100)
    @model.entities << face
    Z::STAMP_STORE.write(face, Z::Schema.stamp(record))
    adopt
    assert_equal 1, query.dig("levels", 0, "usage", "recoverable")
    before = Z::STAMP_STORE.read(face)
    params = manage_params("level")
    id = params.fetch("options").first.fetch("id")
    params["options"] = []
    assert_equal "reference.in_use", invoke("#{O::PREFIX}.manage", params).fetch("code")
    params["replacements"] = { id => nil }
    result = invoke("#{O::PREFIX}.manage", params)
    assert_equal "completed", result.fetch("status"), result.inspect
    assert_nil Z::STAMP_STORE.read(face).fetch("level_id")
    @model.undo
    assert_equal before, Z::STAMP_STORE.read(@model.entities.to_a.first)
  end

  def test_used_segment_requires_replacement_and_default_cannot_dangle
    group, = add_zone
    adopt
    params = manage_params("building_segment")
    old_id = params.fetch("options").first.fetch("id")
    params["options"] = [{ "id" => "new:replacement", "name" => "Other", "colour" => "#ABCDEF" }]
    assert_equal "reference.in_use", invoke("#{O::PREFIX}.manage", params).fetch("code")
    params["replacements"] = { old_id => "new:replacement" }
    params["default_segment_id"] = "new:replacement"
    result = invoke("#{O::PREFIX}.manage", params)
    assert_equal "completed", result.fetch("status"), result.inspect
    assert_equal query.fetch("default_segment_id"), Z::ZONE_STORE.read(group).fetch("building_segment_id")
  end

  def test_conflicting_stamps_locked_targets_and_incomplete_mapping_refuse_without_changes
    group, face = add_zone
    Z::STAMP_STORE.write(face, Z::Schema.stamp(legacy("zon_AAAAAAAAAAAA", "Other", "Level 1")))
    before = Z::ZONE_STORE.read(group)
    result = invoke("#{O::PREFIX}.adopt", "mappings" => mappings)
    assert_equal "zone.options_conflict", result.fetch("code"), result.inspect
    assert_equal before, Z::ZONE_STORE.read(group)
    assert_empty query.fetch("building_segments")
    Z::STAMP_STORE.write(face, Z::Schema.stamp(before))
    group.locked = true
    assert_equal "target.locked", invoke("#{O::PREFIX}.adopt", "mappings" => mappings).fetch("code")
    assert_equal "target.changed", invoke("#{O::PREFIX}.adopt", "mappings" => []).fetch("code")
  end

  def test_older_strings_can_resolve_existing_choices_but_cannot_create_categories
    group, = add_zone
    adopt
    zone = query("#{Z::FEATURE_ID}.all").fetch("zones").first
    values = { "name" => "Changed", "building_segment" => "House", "level" => "level_1", "ground_depth_mm" => 5.0 }
    expected = { "name" => "Zone", "building_segment" => "House", "level" => "Level 1", "ground_depth_mm" => 125.0 }
    result = invoke("#{Z::FEATURE_ID}.update", "reference" => zone.fetch("reference"), "values" => values,
                                               "expected_values" => expected)
    assert_equal "completed", result.fetch("status"), result.inspect
    before = Z::ZONE_STORE.read(group)
    values["level"] = "Unknown"
    result = invoke("#{Z::FEATURE_ID}.update", "reference" => zone.fetch("reference"), "values" => values,
                                               "expected_values" => values.merge("level" => "Level 1"))
    assert_equal "reference.invalid", result.fetch("code")
    assert_equal before, Z::ZONE_STORE.read(group)
  end

  def test_unadopted_category_edits_refuse_and_unknown_versions_stay_unreadable
    group, = add_zone
    zone = query("#{Z::FEATURE_ID}.all").fetch("zones").first
    params = { "reference" => zone.fetch("reference"), "values" => zone.fetch("values").merge("level" => "New"),
               "expected_values" => zone.fetch("values") }
    assert_equal "zone.options_adoption_required", invoke("#{Z::FEATURE_ID}.update", params).fetch("code")
    Z::ZONE_STORE.write(group, legacy.merge("schema_version" => 99))
    result = API.query(:context => @context, :name => "#{O::PREFIX}.all")
    assert_equal "record.unreadable", result.fetch("code")
  end

  def test_public_single_option_operations_and_paging_use_the_same_managed_authority
    first = invoke("#{O::PREFIX}.create", "collection" => "level",
                                          "values" => { "name" => "Level 1", "colour" => "#123456" },
                                          "user_data" => { "firm" => { "note" => "keep" } })
    assert_equal "completed", first.fetch("status"), first.inspect
    id = first.dig("value", "id")
    detail = query("#{O::PREFIX}.detail", "collection" => "level", "id" => id)
    assert_equal({ "firm" => { "note" => "keep" } }, detail.fetch("user_data"))
    second = invoke("#{O::PREFIX}.create", "collection" => "level",
                                           "values" => { "name" => "Level 2", "colour" => "#ABCDEF" })
    target = second.dig("value", "id")
    page = query("#{O::PREFIX}.list", "collection" => "level", "limit" => 1)
    assert_equal 1, page.fetch("options").length
    assert page.fetch("next_cursor")
    updated = invoke("#{O::PREFIX}.update", "collection" => "level", "id" => id,
                                            "values" => { "name" => "Ground", "colour" => "#112233" },
                                            "expected_values" => { "name" => "Level 1", "colour" => "#123456" })
    assert_equal "completed", updated.fetch("status"), updated.inspect
    merged = invoke("#{O::PREFIX}.merge", "collection" => "level", "id" => id, "target_id" => target)
    assert_equal "completed", merged.fetch("status"), merged.inspect
    removed = invoke("#{O::PREFIX}.remove", "collection" => "level", "id" => target)
    assert_equal "completed", removed.fetch("status"), removed.inspect
    assert_empty query.fetch("levels")
  end

  def test_copied_choices_remain_visible_without_implicit_import_then_adopt_explicitly
    group, face = add_zone
    adopt
    copy_record = Z::ZONE_STORE.read(group)
    copy_stamp = Z::STAMP_STORE.read(face)
    @model = Sketchup::Model.new
    Sketchup.active_model = @model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    group, face = add_zone(200, copy_record)
    Z::STAMP_STORE.write(face, copy_stamp)
    before = Z::ZONE_STORE.read(group)
    snapshot = query
    assert snapshot.dig("adoption", "required")
    assert_empty snapshot.fetch("building_segments")
    assert_equal before, Z::ZONE_STORE.read(group)
    zone = query("#{Z::FEATURE_ID}.all").fetch("zones").first
    assert_equal "House", zone.dig("display", "building_segment")
    refused = invoke("#{Z::FEATURE_ID}.update", "reference" => zone.fetch("reference"),
                                                "values" => zone.fetch("values"),
                                                "expected_values" => zone.fetch("values"))
    assert_equal "zone.options_adoption_required", refused.fetch("code")
    adopt
    after = Z::ZONE_STORE.read(group)
    refute_equal before.fetch("building_segment_id"), after.fetch("building_segment_id")
    assert_equal before.dig("choice_evidence", "building_segment", "export_identifier"),
                 after.dig("choice_evidence", "building_segment", "export_identifier")
    assert_equal after.fetch("building_segment_id"), Z::STAMP_STORE.read(face).fetch("building_segment_id")
    @model.save("/tmp/ph-composer-options-copy.skp")
    Sketchup.open_file("/tmp/ph-composer-options-copy.skp")
    reopened = Sketchup.active_model.entities.to_a.first
    assert_equal after, Z::ZONE_STORE.read(reopened)
  end

  def test_restore_after_managed_adoption_uses_ids_and_conflicting_stamps_refuse
    group, face = add_zone
    adopt
    record = Z::ZONE_STORE.read(group)
    @model.entities.delete(group)
    @model.entities << face
    result = invoke("#{Z::FEATURE_ID}.restore", "parent_path" => [], "zone_id" => record.fetch("id"))
    assert_equal "completed", result.fetch("status"), result.inspect
    restored = Z::ZONE_STORE.read(@model.entities.grep(Sketchup::Group).first)
    assert_equal record.values_at("building_segment_id", "level_id"),
                 restored.values_at("building_segment_id", "level_id")
  end

  def test_adoption_merge_cycles_and_unknown_targets_refuse_atomically
    add_zone(100, legacy("zon_AAAAAAAAAAAA", "House", "Lower"))
    add_zone(200, legacy("zon_BBBBBBBBBBBB", "House", "Upper"))
    choices = mappings
    level_choices = choices.reject { |choice| choice.fetch("name") == "House" }
    level_choices.first["target_source"] = level_choices.last.fetch("source")
    level_choices.last["target_source"] = level_choices.first.fetch("source")
    result = invoke("#{O::PREFIX}.adopt", "mappings" => choices)
    assert_equal "params.invalid", result.fetch("code")
    assert_empty query.fetch("levels")
    choices = mappings
    choices.first["target_id"] = "bsg_ZZZZZZZZZZZZ"
    assert_equal "target.not_found", invoke("#{O::PREFIX}.adopt", "mappings" => choices).fetch("code")
  end

  def test_no_change_management_adds_no_undo_and_mid_apply_failure_rolls_back
    group, face = add_zone
    adopt
    before = Z::ZONE_STORE.read(group)
    params = manage_params("level")
    unchanged = invoke("#{O::PREFIX}.manage", params)
    assert_equal "none", unchanged.fetch("effect"), unchanged.inspect
    params.fetch("options").first["name"] = "Updated"
    failure = lambda { |_entity, _record| raise IOError, "injected stamp write failure" }
    result = Z::STAMP_STORE.stub(:write, failure) { invoke("#{O::PREFIX}.manage", params) }
    assert_equal ["failed", "operation.failed", "rolled_back"], result.values_at("status", "code", "effect")
    assert_equal before, Z::ZONE_STORE.read(@model.entities.grep(Sketchup::Group).first)
    assert_equal "Level 1", query.dig("levels", 0, "values", "name")
    assert Z::STAMP_STORE.read(@model.entities.grep(Sketchup::Group).first.entities.to_a.first)
  end

  def register_portable_extension(references)
    extension = PhComposer::Records::Extension.new(:namespace => "test.portable.options", :schema_version => 1,
                                                   :references => references, :export_relevance => "local_only")
    fixture = Module.new do
      define_singleton_method(:install) do |registry|
        registry.feature("test.portable", :contract_version => 1).extension(extension)
      end
    end
    PhComposer::Registry.install([fixture])
    extension
  end

  def foreign_record(extension, payload, include_level = false)
    segment = { "id" => "bsg_AAAAAAAAAAAA", "schema_version" => 1, "name" => "Copied", "colour" => "#123456",
                "export_identifier" => O.export_identifier("Copied"),
                "extension_data" => { extension.namespace => extension.envelope(payload) } }
    level = include_level ? { "id" => "lvl_AAAAAAAAAAAA", "schema_version" => 1,
                              "name" => "Copied Level", "colour" => "#ABCDEF" } : nil
    { "id" => "zon_AAAAAAAAAAAA", "schema_version" => 2, "name" => "Copied Zone", "ground_depth_mm" => 0.0,
      "building_segment_id" => segment.fetch("id"), "level_id" => level && level.fetch("id"),
      "choice_evidence" => { "source_model_id" => "foreign", "building_segment" => segment, "level" => level } }
  end

  def test_foreign_option_extension_with_missing_destination_reference_refuses_before_writes
    extension = register_portable_extension([
      { "path" => "$.external_id", "target_kind" => Z::Faces::AttachedZone::KIND_ID, "cardinality" => "one" }
    ])
    record = foreign_record(extension, "external_id" => "atz_MISSING00000")
    group, = add_zone(100, record)
    result = invoke("#{O::PREFIX}.adopt", "mappings" => mappings)
    assert_equal ["refused", "reference.invalid", "none"], result.values_at("status", "code", "effect")
    assert_equal record, Z::ZONE_STORE.read(group)
    assert_empty query.fetch("building_segments")
  end

  def test_foreign_option_extension_remaps_self_and_cross_collection_after_allocation
    extension = register_portable_extension([
      { "path" => "$.segment_id", "target_kind" => O::SEGMENT_KIND, "cardinality" => "one" },
      { "path" => "$.level_id", "target_kind" => O::LEVEL_KIND, "cardinality" => "one" }
    ])
    record = foreign_record(extension, { "segment_id" => "bsg_AAAAAAAAAAAA", "level_id" => "lvl_AAAAAAAAAAAA" }, true)
    group, = add_zone(100, record)
    adopt
    after = Z::ZONE_STORE.read(group)
    segment = O::SEGMENTS.store.read(@model, after.fetch("building_segment_id"))
    payload = segment.dig("extension_data", extension.namespace, "payload")
    assert_equal after.fetch("building_segment_id"), payload.fetch("segment_id")
    assert_equal after.fetch("level_id"), payload.fetch("level_id")
  end

  def test_source_merge_can_terminate_at_an_existing_local_option
    created = invoke("#{O::PREFIX}.create", "collection" => "level",
                                            "values" => { "name" => "Existing", "colour" => "#123456" })
    target = created.dig("value", "id")
    add_zone(100, legacy("zon_AAAAAAAAAAAA", "House", "Lower"))
    add_zone(200, legacy("zon_BBBBBBBBBBBB", "House", "Upper"))
    choices = mappings
    levels = choices.reject { |choice| choice.fetch("name") == "House" }
    levels.first["target_source"] = levels.last.fetch("source")
    levels.last["target_id"] = target
    result = invoke("#{O::PREFIX}.adopt", "mappings" => choices)
    assert_equal "completed", result.fetch("status"), result.inspect
    assert @model.entities.grep(Sketchup::Group).all? { |group| Z::ZONE_STORE.read(group).fetch("level_id") == target }
    assert_equal 1, query.fetch("levels").length
  end
end
