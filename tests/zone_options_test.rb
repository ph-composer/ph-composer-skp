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
    assert_equal Z::ZONE_SCHEMA_VERSION, zone.fetch("schema_version")
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

  # A copied Zone whose Level evidence carries an extension payload. A Building Segment's evidence carries its
  # values only, so its settings never travel with a copy.
  def foreign_record(extension, payload)
    segment = { "id" => "bsg_AAAAAAAAAAAA", "schema_version" => 1, "name" => "Copied", "colour" => "#123456",
                "export_identifier" => O.export_identifier("Copied") }
    level = { "id" => "lvl_AAAAAAAAAAAA", "schema_version" => 1, "name" => "Copied Level", "colour" => "#ABCDEF",
              "extension_data" => { extension.namespace => extension.envelope(payload) } }
    { "id" => "zon_AAAAAAAAAAAA", "schema_version" => 2, "name" => "Copied Zone", "ground_depth_mm" => 0.0,
      "building_segment_id" => segment.fetch("id"), "level_id" => level.fetch("id"),
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
    assert_empty query.fetch("levels")
  end

  def test_foreign_option_extension_remaps_self_and_cross_collection_after_allocation
    extension = register_portable_extension([
      { "path" => "$.segment_id", "target_kind" => O::SEGMENT_KIND, "cardinality" => "one" },
      { "path" => "$.level_id", "target_kind" => O::LEVEL_KIND, "cardinality" => "one" }
    ])
    record = foreign_record(extension, { "segment_id" => "bsg_AAAAAAAAAAAA", "level_id" => "lvl_AAAAAAAAAAAA" })
    group, = add_zone(100, record)
    adopt
    after = Z::ZONE_STORE.read(group)
    level = O::LEVELS.store.read(@model, after.fetch("level_id"))
    payload = level.dig("extension_data", extension.namespace, "payload")
    assert_equal after.fetch("building_segment_id"), payload.fetch("segment_id")
    assert_equal after.fetch("level_id"), payload.fetch("level_id")
  end

  # Evidence an earlier version wrote carried the whole Segment record; adoption keeps only its values, so the
  # adopted Segment reads its defaults and no other feature's settings or map arrive with a copy.
  def test_adopting_old_segment_evidence_brings_no_settings_or_map
    extension = register_portable_extension([])
    record = foreign_record(extension, {})
    record.fetch("choice_evidence").fetch("building_segment")
          .merge!("user_data" => { "firm" => 1 },
                  "extension_data" => { extension.namespace => extension.envelope({ "note" => "old" }) })
    group, = add_zone(100, record)
    adopt
    segment = O::SEGMENTS.store.read(@model, Z::ZONE_STORE.read(group).fetch("building_segment_id"))
    assert_equal "Copied", segment.fetch("name")
    assert_nil segment["user_data"]
    assert_empty segment.fetch("extension_data", {})
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

  # ---------------------------------------------------------------- option metadata (EUD-04)

  def metadata_entry(kind, id, user_data)
    stored = query("ph_composer.records.list", "kind" => kind, "ids" => [id]).fetch("records").first
    { "reference" => { "kind" => kind, "id" => id }, "user_data" => user_data,
      "expected_metadata" => stored.slice("user_data", "extension_data") }
  end

  def write_metadata(*entries)
    invoke("ph_composer.records.update_metadata", "updates" => entries)
  end

  def option_map(kind, id)
    query("ph_composer.records.list", "kind" => kind, "ids" => [id]).dig("records", 0, "user_data")
  end

  def zones_and_stamps
    @model.entities.grep(Sketchup::Group).sort_by { |group| Z::ZONE_STORE.read(group).fetch("id") }.flat_map do |group|
      [Z::ZONE_STORE.read(group), Z::STAMP_STORE.read(group.entities.to_a.first)]
    end
  end

  def test_option_maps_rewrite_every_zone_evidence_and_member_stamp_in_one_undo_step
    group, = add_zone
    add_zone(200, legacy("zon_BBBBBBBBBBBB"))
    adopt
    before = zones_and_stamps
    segment_id, level_id = Z::ZONE_STORE.read(group).values_at("building_segment_id", "level_id")
    level_map = { "firm" => { "floor" => "1", "flags" => [nil, false, 0, {}], "name" => "Étage" } }
    segment_map = { "firm" => { "block" => "A" } }
    result = write_metadata(metadata_entry(O::LEVEL_KIND, level_id, level_map),
                            metadata_entry(O::SEGMENT_KIND, segment_id, segment_map))
    assert_equal %w[completed committed], result.values_at("status", "effect"), result.inspect
    after = zones_and_stamps
    assert_equal 4, after.length
    after.each do |record|
      assert_equal level_map, record.dig("choice_evidence", "level", "user_data")
      assert_equal O::SEGMENT_EVIDENCE.sort, record.dig("choice_evidence", "building_segment").keys.sort,
                   "a Segment's evidence keeps its values, never its map"
    end
    assert_equal before.map { |record| record.reject { |key, _| key == "choice_evidence" } },
                 after.map { |record| record.reject { |key, _| key == "choice_evidence" } }
    assert_equal level_map, option_map(O::LEVEL_KIND, level_id)
    unchanged = write_metadata(metadata_entry(O::LEVEL_KIND, level_id, level_map))
    assert_equal %w[completed none], unchanged.values_at("status", "effect"), unchanged.inspect

    @model.undo
    assert_equal before, zones_and_stamps
    assert_equal({}, option_map(O::LEVEL_KIND, level_id))
    assert_equal({}, option_map(O::SEGMENT_KIND, segment_id))
    @model.redo
    assert_equal after, zones_and_stamps
    assert_equal segment_map, option_map(O::SEGMENT_KIND, segment_id)
  end

  def test_option_map_write_leaves_zones_awaiting_adoption_as_they_are
    group, = add_zone
    adopt
    level_id = Z::ZONE_STORE.read(group).fetch("level_id")
    level = O::LEVELS.store.read(@model, level_id)
    # Pasted from another Model: its Segment is not here, and it names this Model's Level by coincidence.
    segment = { "id" => "bsg_ZZZZZZZZZZZZ", "schema_version" => 1, "name" => "Shed", "colour" => "#123456",
                "export_identifier" => O.export_identifier("Shed") }
    copied = { "id" => "zon_BBBBBBBBBBBB", "schema_version" => 2, "name" => "Copied", "ground_depth_mm" => 0.0,
               "building_segment_id" => segment.fetch("id"), "level_id" => level_id,
               "choice_evidence" => { "source_model_id" => "foreign", "building_segment" => segment,
                                      "level" => level } }
    pasted, pasted_face = add_zone(200, copied)
    add_zone(300, legacy("zon_CCCCCCCCCCCC", "Barn", "Level 1"))
    pasted_records = [Z::ZONE_STORE.read(pasted), Z::STAMP_STORE.read(pasted_face)]
    result = write_metadata(metadata_entry(O::LEVEL_KIND, level_id, { "firm" => 1 }))
    assert_equal %w[completed committed], result.values_at("status", "effect"), result.inspect
    assert_equal({ "firm" => 1 }, Z::ZONE_STORE.read(group).dig("choice_evidence", "level", "user_data"))
    assert_equal pasted_records, [Z::ZONE_STORE.read(pasted), Z::STAMP_STORE.read(pasted_face)]
  end

  def test_option_map_write_refuses_a_locked_zone_atomically
    group, = add_zone
    adopt
    level_id = Z::ZONE_STORE.read(group).fetch("level_id")
    before = zones_and_stamps
    revision = @session.revision
    group.locked = true
    result = write_metadata(metadata_entry(O::LEVEL_KIND, level_id, { "firm" => 1 }))
    assert_equal %w[refused target.locked none], result.values_at("status", "code", "effect"), result.inspect
    assert_equal revision, @session.revision
    assert_equal before, zones_and_stamps
    assert_equal({}, option_map(O::LEVEL_KIND, level_id))
  end

  # A Building Segment's evidence holds its values only, so writing its map touches the Segment alone: a locked
  # member Zone does not block it and no Zone is rewritten.
  def test_segment_map_write_leaves_member_zones_alone_even_when_locked
    group, = add_zone
    adopt
    segment_id = Z::ZONE_STORE.read(group).fetch("building_segment_id")
    before = zones_and_stamps
    group.locked = true
    result = write_metadata(metadata_entry(O::SEGMENT_KIND, segment_id, { "firm" => 1 }))
    assert_equal %w[completed committed], result.values_at("status", "effect"), result.inspect
    assert_equal before, zones_and_stamps
    assert_equal({ "firm" => 1 }, option_map(O::SEGMENT_KIND, segment_id))
  end

  def test_merge_and_remove_keep_the_survivor_map_and_report_the_removed_maps
    house, = add_zone(100, legacy("zon_AAAAAAAAAAAA", "House", "Lower"))
    garage, = add_zone(200, legacy("zon_BBBBBBBBBBBB", "Garage", "Upper"))
    adopt
    house_id, lower_id = Z::ZONE_STORE.read(house).values_at("building_segment_id", "level_id")
    garage_id, upper_id = Z::ZONE_STORE.read(garage).values_at("building_segment_id", "level_id")
    write_metadata(metadata_entry(O::SEGMENT_KIND, house_id, { "keep" => { "a" => 1 } }),
                   metadata_entry(O::SEGMENT_KIND, garage_id, { "zeta" => 1, "alpha" => [2] }),
                   metadata_entry(O::LEVEL_KIND, upper_id, { "level_note" => "x" }))

    before_merge = zones_and_stamps
    merged = invoke("#{O::PREFIX}.merge", "collection" => "building_segment", "id" => garage_id,
                                          "target_id" => house_id)
    assert_equal "completed", merged.fetch("status"), merged.inspect
    assert_equal [{ "id" => garage_id, "user_data_keys" => %w[alpha zeta], "user_data_key_total" => 2 }],
                 merged.dig("value", "removed_user_data")
    assert_equal 1, merged.dig("value", "removed_user_data_total")
    assert_equal({ "keep" => { "a" => 1 } }, option_map(O::SEGMENT_KIND, house_id), "maps are never combined")
    garage_zone = Z::ZONE_STORE.read(@model.entities.grep(Sketchup::Group).last)
    assert_equal house_id, garage_zone.fetch("building_segment_id")
    assert_nil garage_zone.dig("choice_evidence", "building_segment", "user_data")
    @model.undo
    assert_equal({ "zeta" => 1, "alpha" => [2] }, option_map(O::SEGMENT_KIND, garage_id))
    assert_equal before_merge, zones_and_stamps, "Undo restores each Zone's choice and evidence"

    removed = invoke("#{O::PREFIX}.remove", "collection" => "level", "id" => upper_id, "replacement_id" => lower_id)
    assert_equal "completed", removed.fetch("status"), removed.inspect
    assert_equal({ "removed_user_data" => [{ "id" => upper_id, "user_data_keys" => ["level_note"],
                                             "user_data_key_total" => 1 }], "removed_user_data_total" => 1 },
                 removed.fetch("value").slice("removed_user_data", "removed_user_data_total"))
    @model.undo
    assert_equal({ "level_note" => "x" }, option_map(O::LEVEL_KIND, upper_id))
    assert_equal before_merge, zones_and_stamps
    @model.redo
    plain = invoke("#{O::PREFIX}.remove", "collection" => "level", "id" => lower_id, "replacement_id" => nil)
    assert_equal "completed", plain.fetch("status"), plain.inspect
    assert_equal [[], 0], plain.fetch("value").values_at("removed_user_data", "removed_user_data_total"),
                 "an option without a map is not reported"
  end

  # Every Building-Segment and Level map stays in the Model with one finding, whether a Zone names the option
  # or not.
  def test_used_and_unused_option_maps_are_each_reported_as_omitted
    group, face = add_zone
    Z::Faces::FACE_STORE.write(face, "id" => "fac_AAAAAAAAAAAA", "schema_version" => 1)
    adopt
    segment_id = Z::ZONE_STORE.read(group).fetch("building_segment_id")
    unused = invoke("#{O::PREFIX}.create", "collection" => "level", "values" => { "name" => "Attic",
                                                                                  "colour" => "#1F7478" },
                                           "user_data" => { "firm" => { "floor" => "attic" } })
    assert_equal "completed", unused.fetch("status"), unused.inspect
    write_metadata(metadata_entry(O::SEGMENT_KIND, segment_id, { "firm" => { "block" => "A" } }))

    extraction = PhComposer::Export::Collection.build(@model, :run_id => "options",
                                                              :contributors => [Z::ExportProjection::SECTION])
    omitted = extraction.findings.select { |row| row.fetch("code") == "export.metadata_omitted" }
    assert_equal [segment_id, unused.dig("value", "id")].sort, omitted.map { |row| row.fetch("object_id") }.sort
    refute_includes JSON.generate(extraction.document), "attic"
  end

  def test_adopting_a_copied_zone_rebuilds_its_level_map_and_not_its_segment_map
    group, face = add_zone
    adopt
    segment_id, level_id = Z::ZONE_STORE.read(group).values_at("building_segment_id", "level_id")
    write_metadata(metadata_entry(O::SEGMENT_KIND, segment_id, { "firm" => { "block" => "A" } }),
                   metadata_entry(O::LEVEL_KIND, level_id, { "firm" => { "floor" => 1 } }))
    copy_record = Z::ZONE_STORE.read(group)
    copy_stamp = Z::STAMP_STORE.read(face)
    @model = Sketchup::Model.new
    Sketchup.active_model = @model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    group, face = add_zone(200, copy_record)
    Z::STAMP_STORE.write(face, copy_stamp)
    adopt
    adopted = Z::ZONE_STORE.read(group)
    refute_equal segment_id, adopted.fetch("building_segment_id")
    assert_equal({}, option_map(O::SEGMENT_KIND, adopted.fetch("building_segment_id")),
                 "a Segment's map stays in the Model it came from")
    assert_equal({ "firm" => { "floor" => 1 } }, option_map(O::LEVEL_KIND, adopted.fetch("level_id")))
    assert_equal({ "firm" => { "floor" => 1 } }, adopted.dig("choice_evidence", "level", "user_data"))
  end
end
