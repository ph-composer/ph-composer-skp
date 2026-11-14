# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/record_fixtures"

class RecordsEngineTest < PhComposerTestCase
  include RecordFixtures

  def setup
    super
    @model = Sketchup::Model.new
    @engine = PhComposer::Records::Engine.new(@model, record_catalog)
  end

  def test_a_created_record_reads_back_with_empty_metadata_and_a_durable_id
    changes = PhComposer::Records::ChangeSet.new
    definition = @engine.propose_create("test.fixture.definition", changes, :values => { "label" => "Frame" })
    values = { "label" => "Sill", "length_mm" => 1200.0, "definition_id" => definition }
    part = @engine.propose_create("test.fixture.part", changes, :values => values)
    @engine.apply(changes)

    view = @engine.view("test.fixture.part", @engine.find("test.fixture.part", part))
    assert_match(/\Atpt_[A-Za-z0-9]{12}\z/, part)
    assert_equal({ "label" => "Sill", "length_mm" => 1200.0, "definition_id" => definition }, view.fetch("values"))
    assert_equal({}, view.fetch("user_data"))
    assert_equal [{ "kind" => "test.fixture.definition", "id" => definition, "change" => "created" },
                  { "kind" => "test.fixture.part", "id" => part, "change" => "created" }], changes.affected
  end

  def test_reads_do_not_create_dictionaries_repair_records_or_mark_the_model_modified
    definition = store_record(@model, DEFINITION, "id" => "tdf_AAAAAAAAAAAA", "schema_version" => 1, "label" => "A")
    text = stored_text(@model, DEFINITION, definition["id"])
    @model.instance_variable_set(:@modified, false)

    @engine.view("test.fixture.definition", @engine.find("test.fixture.definition", definition["id"]))
    @engine.ids("test.fixture.part")

    assert_equal text, stored_text(@model, DEFINITION, definition["id"])
    assert_nil @model.attribute_dictionary(PART.store.dictionary)
    refute @model.modified?
  end

  def test_an_ordinary_edit_carries_an_unavailable_extensions_payload_through_unchanged
    foreign = { "schema_version" => 7, "payload" => { "score" => 0.5, "notes" => ["a"] },
                "references" => [], "export_relevance" => "required" }
    part = seed_part("extension_data" => { "other.vendor" => foreign })

    changes = PhComposer::Records::ChangeSet.new
    @engine.propose_update("test.fixture.part", part, changes, :values => { "length_mm" => 900.0 })
    @engine.apply(changes)

    stored = @engine.find("test.fixture.part", part)
    assert_equal 900.0, stored.fetch("length_mm")
    assert_equal foreign, stored.dig("extension_data", "other.vendor")
    assert_equal "unavailable", @engine.view("test.fixture.part", stored).dig("extension_status", "other.vendor")
  end

  def test_an_edit_that_changes_nothing_proposes_nothing
    part = seed_part
    changes = PhComposer::Records::ChangeSet.new

    @engine.propose_update("test.fixture.part", part, changes, :values => { "length_mm" => 1200.0 })

    assert changes.empty?
  end

  def test_a_delete_reports_its_effect_and_removes_the_record
    part = seed_part
    changes = PhComposer::Records::ChangeSet.new

    @engine.propose_delete("test.fixture.part", part, changes)
    @engine.apply(changes)

    assert_equal [{ "kind" => "test.fixture.part", "id" => part, "change" => "deleted" }], changes.affected
    assert_raises(PhComposer::CodedError) { @engine.find("test.fixture.part", part) }
  end

  def test_a_delete_is_refused_while_a_projected_record_still_refers_to_it
    part = seed_part
    definition = @engine.find("test.fixture.part", part).fetch("definition_id")
    changes = PhComposer::Records::ChangeSet.new

    error = assert_raises(PhComposer::CodedError) do
      @engine.propose_delete("test.fixture.definition", definition, changes)
    end

    assert_equal "reference.in_use", error.code
    assert_equal "reference.in_use", changes.refusal.code
  end

  def test_a_replacement_and_delete_can_be_staged_atomically
    part = seed_part
    old_definition = @engine.find("test.fixture.part", part).fetch("definition_id")
    changes = PhComposer::Records::ChangeSet.new
    new_definition = @engine.propose_create(
      "test.fixture.definition", changes, :values => { "label" => "Replacement" }
    )
    @engine.propose_update("test.fixture.part", part, changes,
                           :values => { "definition_id" => new_definition })
    @engine.propose_delete("test.fixture.definition", old_definition, changes)

    @engine.apply(changes)

    assert_equal new_definition, @engine.find("test.fixture.part", part).fetch("definition_id")
    assert_raises(PhComposer::CodedError) { @engine.find("test.fixture.definition", old_definition) }
  end

  def test_an_invalid_value_is_refused_with_its_findings
    part = seed_part
    error = assert_raises(PhComposer::CodedError) do
      @engine.propose_update("test.fixture.part", part, PhComposer::Records::ChangeSet.new,
                             :values => { "length_mm" => -1 })
    end

    assert_equal "validation.failed", error.code
    assert_equal ["$.length_mm must be greater than 0"], error.detail.fetch("findings")
  end

  def test_a_reference_to_a_missing_record_is_refused
    part = seed_part
    error = assert_raises(PhComposer::CodedError) do
      @engine.propose_update("test.fixture.part", part, PhComposer::Records::ChangeSet.new,
                             :values => { "definition_id" => "tdf_MISSINGMISSI" })
    end

    assert_equal "reference.invalid", error.code
  end

  def test_an_edit_whose_expected_values_no_longer_match_is_refused
    part = seed_part
    error = assert_raises(PhComposer::CodedError) do
      @engine.propose_update("test.fixture.part", part, PhComposer::Records::ChangeSet.new,
                             :values => { "length_mm" => 900.0 }, :expected_values => { "length_mm" => 1000.0 })
    end

    assert_equal "target.changed", error.code
    assert_equal ["length_mm"], error.detail.fetch("fields")
  end

  def test_values_cannot_set_identity_or_metadata
    %w[id extension_data user_data schema_version].each do |key|
      error = assert_raises(PhComposer::CodedError) do
        @engine.propose_update("test.fixture.part", seed_part, PhComposer::Records::ChangeSet.new,
                               :values => { key => nil })
      end
      assert_equal "params.invalid", error.code, key
    end
  end

  def test_a_refused_proposal_marks_its_change_set_even_when_the_caller_rescues
    good = seed_part("extension_data" => { "test.fixture.review" => version_one("draft") })
    bad = seed_part("extension_data" => { "test.fixture.review" => version_one("lost") })
    changes = PhComposer::Records::ChangeSet.new

    begin
      @engine.propose_migration("test.fixture.part", [good, bad], "test.fixture.review", changes)
    rescue PhComposer::CodedError
      nil
    end

    assert_equal "extension.migration_failed", changes.refusal.code
  end

  def test_writing_outdated_extension_data_asks_for_migration_first
    part = seed_part("extension_data" => { "test.fixture.review" => version_one("draft") })
    error = assert_raises(PhComposer::CodedError) do
      @engine.propose_update("test.fixture.part", part, PhComposer::Records::ChangeSet.new,
                             :extension_payloads => { "test.fixture.review" => { "review_status" => "checked" } })
    end

    assert_equal "extension.migration_required", error.code
  end

  def test_user_data_that_is_not_plain_json_is_refused
    error = assert_raises(PhComposer::CodedError) do
      @engine.propose_create("test.fixture.part", PhComposer::Records::ChangeSet.new,
                             :values => { "label" => "Sill", "length_mm" => 900.0, "definition_id" => seed_part },
                             :user_data => { "org" => { "score" => Float::NAN } })
    end

    assert_equal "params.invalid", error.code
  end

  def test_a_duplicated_collection_remaps_internal_references_and_keeps_external_ones
    first = seed_part("user_data" => { "org" => { "note" => "keep" } })
    second = seed_part("neighbour_ids" => [first])
    changes = PhComposer::Records::ChangeSet.new
    @engine.propose_update("test.fixture.part", second, changes, :extension_payloads => {
      "test.fixture.review" => { "review_status" => "checked", "checked_against" => first }
    })
    @engine.apply(changes)

    changes = PhComposer::Records::ChangeSet.new
    mapping = @engine.propose_duplicate("test.fixture.part", [first, second], changes)
    @engine.apply(changes)

    copy = @engine.find("test.fixture.part", mapping.fetch(second))
    assert_equal [mapping.fetch(first)], copy.fetch("neighbour_ids")
    assert_equal @definition, copy.fetch("definition_id")
    assert_equal mapping.fetch(first), copy.dig("extension_data", "test.fixture.review", "payload", "checked_against")
    first_copy = @engine.find("test.fixture.part", mapping.fetch(first))
    assert_equal({ "org" => { "note" => "keep" } }, first_copy.fetch("user_data"))
    refute_same @engine.find("test.fixture.part", first).fetch("user_data"), first_copy.fetch("user_data")
  end

  def test_duplicate_can_transform_authored_values_without_changing_metadata
    original = seed_part("user_data" => { "note" => "keep" })
    changes = PhComposer::Records::ChangeSet.new
    mapping = @engine.propose_duplicate("test.fixture.part", [original], changes) do |values|
      values.merge("label" => "Copy")
    end
    @engine.apply(changes)

    copy = @engine.find("test.fixture.part", mapping.fetch(original))
    assert_equal "Copy", copy.fetch("label")
    assert_equal({ "note" => "keep" }, copy.fetch("user_data"))
    refute_equal "Copy", @engine.find("test.fixture.part", original).fetch("label")
  end

  def test_duplicate_transform_cannot_write_identity_or_metadata
    original = seed_part
    changes = PhComposer::Records::ChangeSet.new
    error = assert_raises(PhComposer::CodedError) do
      @engine.propose_duplicate("test.fixture.part", [original], changes) do |values|
        values.merge("id" => original)
      end
    end
    assert_equal "params.invalid", error.code
    assert changes.empty?
  end

  def test_duplicate_transformed_values_are_validated_before_writing
    original = seed_part
    changes = PhComposer::Records::ChangeSet.new
    error = assert_raises(PhComposer::CodedError) do
      @engine.propose_duplicate("test.fixture.part", [original], changes) do |values|
        values.merge("label" => 42)
      end
    end
    assert_equal "validation.failed", error.code
    assert changes.empty?
  end

  def test_duplicate_transformed_references_are_checked_and_refuse_the_whole_collection
    first = seed_part
    second = seed_part
    changes = PhComposer::Records::ChangeSet.new
    error = assert_raises(PhComposer::CodedError) do
      @engine.propose_duplicate("test.fixture.part", [first, second], changes) do |values|
        values.merge("definition_id" => "tdf_MISSING00001")
      end
    end
    assert_equal "reference.invalid", error.code
    assert_equal error, changes.refusal
    assert_equal [first, second].sort, @engine.ids("test.fixture.part").sort
  end

  # The first copy names a counterpart that is staged after it.
  def test_a_duplicated_collection_accepts_a_reference_to_a_later_copy
    later = seed_part
    earlier = seed_part("neighbour_ids" => [later])
    changes = PhComposer::Records::ChangeSet.new

    mapping = @engine.propose_duplicate("test.fixture.part", [earlier, later], changes)

    copy = changes.find("test.fixture.part", mapping.fetch(earlier)).after
    assert_equal [mapping.fetch(later)], copy.fetch("neighbour_ids")
  end

  def test_a_copy_needing_an_unavailable_extensions_rules_is_refused_whole
    plain = seed_part
    foreign = seed_part("extension_data" => { "other.vendor" => { "schema_version" => 1, "payload" => {} } })
    changes = PhComposer::Records::ChangeSet.new

    error = assert_raises(PhComposer::CodedError) {
      @engine.propose_duplicate("test.fixture.part", [plain, foreign], changes)
    }

    assert_equal "copy.rule_missing", error.code
    assert_equal "unavailable", error.detail.fetch("status")
    assert changes.empty?
  end

  def test_shared_copy_rules_remap_each_copy_from_the_same_source_independently
    old_id = "tpt_OLDRECORD001"
    first_id = "tpt_NEWRECORD001"
    second_id = "tpt_NEWRECORD002"
    data = { REVIEW.namespace => REVIEW.envelope("review_status" => "checked", "checked_against" => old_id) }

    first = PhComposer::Records::Extension.copy_data(data, record_catalog, "Test part", old_id,
                                                     { old_id => first_id })
    second = PhComposer::Records::Extension.copy_data(data, record_catalog, "Test part", old_id,
                                                      { old_id => second_id })

    assert_equal first_id, first.dig(REVIEW.namespace, "payload", "checked_against")
    assert_equal second_id, second.dig(REVIEW.namespace, "payload", "checked_against")
    assert_equal old_id, data.dig(REVIEW.namespace, "payload", "checked_against")
  end

  def test_shared_copy_rules_revalidate_the_remapped_payload
    extension = PhComposer::Records::Extension.new(
      :namespace => "test.fixture.checked_copy", :schema_version => 1,
      :references => [{ "path" => "$.target", "target_kind" => "test.fixture.part", "cardinality" => "one" }],
      :validate => ->(payload) { payload["target"] == "tpt_FORBIDDEN001" ? ["target is forbidden"] : [] }
    )
    source_id = "tpt_SOURCE00001"
    data = { extension.namespace => extension.envelope("target" => source_id) }
    catalog = record_catalog(:extensions => [extension])

    error = assert_raises(PhComposer::CodedError) do
      PhComposer::Records::Extension.copy_data(data, catalog, "Test part", source_id,
                                               { source_id => "tpt_FORBIDDEN001" })
    end

    assert_equal "extension.invalid", error.code
    assert_equal source_id, data.dig(extension.namespace, "payload", "target")
  end

  def test_copy_refuses_outdated_and_explicit_refuse_policies_before_staging
    old = seed_part("extension_data" => { REVIEW.namespace => version_one("draft") })
    changes = PhComposer::Records::ChangeSet.new

    outdated = assert_raises(PhComposer::CodedError) do
      @engine.propose_duplicate("test.fixture.part", [old], changes)
    end
    assert_equal "copy.rule_missing", outdated.code
    assert_equal "outdated", outdated.detail.fetch("status")
    assert changes.empty?

    refusing = PhComposer::Records::Extension.new(
      :namespace => "test.fixture.no_copy", :schema_version => 1, :copy => :refuse
    )
    another = seed_part("extension_data" => { refusing.namespace => refusing.envelope("note" => "keep") })
    restricted_engine = PhComposer::Records::Engine.new(@model, record_catalog(:extensions => [REVIEW, refusing]))

    refused = assert_raises(PhComposer::CodedError) do
      restricted_engine.propose_duplicate("test.fixture.part", [another], PhComposer::Records::ChangeSet.new)
    end
    assert_equal "copy.rule_missing", refused.code
    assert_equal "understood", refused.detail.fetch("status")
  end

  def test_migration_raises_outdated_payloads_and_reports_current_and_absent_records
    outdated = seed_part("extension_data" => { "test.fixture.review" => version_one("draft") })
    current = seed_part("extension_data" => { "test.fixture.review" => REVIEW.envelope("review_status" => "checked") })
    absent = seed_part
    changes = PhComposer::Records::ChangeSet.new

    results = @engine.propose_migration("test.fixture.part", [outdated, current, absent], "test.fixture.review",
                                        changes)
    @engine.apply(changes)

    assert_equal({ outdated => "migrated", current => "current", absent => "absent" }, results)
    envelope = @engine.find("test.fixture.part", outdated).dig("extension_data", "test.fixture.review")
    assert_equal REVIEW.envelope("review_status" => "draft"), envelope
  end

  # The refusal abandons the whole change set; nothing applies a set whose proposal raised.
  def test_a_failed_migration_is_refused_and_leaves_every_stored_byte
    good = seed_part("extension_data" => { "test.fixture.review" => version_one("draft") })
    bad = seed_part("extension_data" => { "test.fixture.review" => version_one("lost") })
    before = [stored_text(@model, PART, good), stored_text(@model, PART, bad)]

    error = assert_raises(PhComposer::CodedError) do
      @engine.propose_migration("test.fixture.part", [good, bad], "test.fixture.review",
                                PhComposer::Records::ChangeSet.new)
    end

    assert_equal "extension.migration_failed", error.code
    assert_equal before, [stored_text(@model, PART, good), stored_text(@model, PART, bad)]
  end

  def test_newer_and_unavailable_payloads_are_refused_distinctly
    newer = seed_part("extension_data" => { "test.fixture.review" => { "schema_version" => 3, "payload" => {} } })
    engine_without = PhComposer::Records::Engine.new(@model, record_catalog(:extensions => []))

    newer_error = assert_raises(PhComposer::CodedError) do
      @engine.propose_migration("test.fixture.part", [newer], "test.fixture.review", PhComposer::Records::ChangeSet.new)
    end
    missing_error = assert_raises(PhComposer::CodedError) do
      engine_without.propose_migration("test.fixture.part", [newer], "test.fixture.review",
                                       PhComposer::Records::ChangeSet.new)
    end

    assert_equal "extension.schema_unsupported", newer_error.code
    assert_equal "extension.unavailable", missing_error.code
  end

  def test_extension_status_distinguishes_every_case
    statuses = {
      "understood" => REVIEW.envelope("review_status" => "draft"),
      "outdated" => { "schema_version" => 1, "payload" => {} },
      "unsupported" => { "schema_version" => 3, "payload" => {} },
      "unreadable" => { "payload" => {} }
    }
    part = seed_part("extension_data" => statuses.transform_keys { |key| "test.fixture.review.#{key}" }
                                                 .merge("test.fixture.review" => statuses["outdated"]))

    view = @engine.view("test.fixture.part", @engine.find("test.fixture.part", part)).fetch("extension_status")

    assert_equal "outdated", view.fetch("test.fixture.review")
    assert_equal "unavailable", view.fetch("test.fixture.review.understood")
    assert_equal "unsupported", view.fetch("test.fixture.review.unreadable")
  end

  # A readable envelope at the installed version is understood only when its payload passes the
  # installed validator and it declares the installed references.
  def test_current_extension_data_failing_its_payload_or_reference_contract_is_invalid
    target = seed_part
    bad_payload = seed_part("extension_data" => { "test.fixture.review" => REVIEW.envelope("review_status" => "lost") })
    bad_references = seed_part("extension_data" => { "test.fixture.review" => review_without_references(target) })

    statuses = [bad_payload, bad_references].map do |id|
      @engine.view("test.fixture.part", @engine.find("test.fixture.part", id)).dig("extension_status",
                                                                                   "test.fixture.review")
    end

    assert_equal %w[invalid invalid], statuses
  end

  def test_invalid_extension_data_survives_unrelated_edits_and_refuses_dependent_operations
    target = seed_part
    invalid = review_without_references(target)
    part = seed_part("extension_data" => { "test.fixture.review" => invalid })

    edit = PhComposer::Records::ChangeSet.new
    @engine.propose_update("test.fixture.part", part, edit, :values => { "length_mm" => 900.0 })
    @engine.apply(edit)
    copy_error = assert_raises(PhComposer::CodedError) do
      @engine.propose_duplicate("test.fixture.part", [part, target], PhComposer::Records::ChangeSet.new)
    end
    migration_error = assert_raises(PhComposer::CodedError) do
      @engine.propose_migration("test.fixture.part", [part], "test.fixture.review", PhComposer::Records::ChangeSet.new)
    end

    assert_equal invalid, @engine.find("test.fixture.part", part).dig("extension_data", "test.fixture.review")
    assert_equal %w[extension.invalid extension.invalid], [copy_error.code, migration_error.code]
  end

  # Replacing the whole payload with a valid one does not depend on the invalid data, so it repairs it.
  def test_a_valid_payload_replaces_invalid_extension_data
    part = seed_part("extension_data" => { "test.fixture.review" => REVIEW.envelope("review_status" => "lost") })
    changes = PhComposer::Records::ChangeSet.new

    @engine.propose_update("test.fixture.part", part, changes,
                           :extension_payloads => { "test.fixture.review" => { "review_status" => "checked" } })
    @engine.apply(changes)

    stored = @engine.find("test.fixture.part", part)
    assert_equal "understood", @engine.view("test.fixture.part", stored).dig("extension_status", "test.fixture.review")
  end

  def test_a_stored_record_that_fails_its_schema_is_unreadable_not_repaired
    store_record(@model, DEFINITION, "id" => "tdf_AAAAAAAAAAAA", "schema_version" => 1)

    error = assert_raises(PhComposer::CodedError) { @engine.find("test.fixture.definition", "tdf_AAAAAAAAAAAA") }

    assert_equal "record.unreadable", error.code
  end

  def test_unchanged_compares_every_named_record_with_its_before_state
    part = seed_part
    changes = PhComposer::Records::ChangeSet.new
    @engine.propose_update("test.fixture.part", part, changes, :values => { "label" => "Head" })
    assert @engine.unchanged?(changes)

    @engine.apply(changes)

    refute @engine.unchanged?(changes)
  end

  private

  # A current-version review whose stored references omit the installed `checked_against` declaration.
  def review_without_references(target)
    REVIEW.envelope("review_status" => "draft", "checked_against" => target).merge("references" => [])
  end

  def version_one(status)
    { "schema_version" => 1, "payload" => { "status" => status } }
  end

  def seed_part(extra = {})
    @definition ||= store_record(@model, DEFINITION, "id" => "tdf_DEFINITION01", "schema_version" => 1,
                                                     "label" => "Frame")["id"]
    id = PhComposer::Records::Identity.mint("tpt")
    record = { "id" => id, "schema_version" => 1, "label" => "Sill", "length_mm" => 1200.0,
               "definition_id" => @definition }.merge(extra)
    store_record(@model, PART, record)["id"]
  end
end
