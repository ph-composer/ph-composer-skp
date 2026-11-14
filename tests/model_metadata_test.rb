# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/assembly_assignment_fixtures"

# The Model's own metadata (context/CONTRACTS.md, "Model settings"): ph_composer.model.detail reads the
# ph_composer.model dictionary, absent as empty and without a write, and ph_composer.model.update_metadata
# replaces its maps under the metadata last read, in one Undo step; a write of what is stored adds none.
class ModelMetadataTest < PhComposerTestCase
  include AssemblyAssignmentFixtures

  DETAIL = "ph_composer.model.detail"
  ACTION = "ph_composer.model.update_metadata"
  DICTIONARY = "ph_composer.model"
  EMPTY = { "user_data" => {}, "extension_data" => {} }.freeze
  REVIEW = "probe.model.review"

  # An installed extension whose payload is valid when its status is draft or checked.
  module Review
    module_function

    def name
      "Review"
    end

    def install(registry)
      feature = registry.feature("probe.model", :contract_version => 1)
      feature.extension(PhComposer::Records::Extension.new(
        :namespace => REVIEW, :schema_version => 1, :export_relevance => "local_only",
        :validate => ->(payload) { %w[draft checked].include?(payload["status"]) ? [] : ["status is unknown"] }
      ))
    end
  end

  def setup
    super
    assignment_setup
    PhComposer::Registry.install([Review])
  end

  def detail
    assignment_query(DETAIL)
  end

  def write(fields, expected = nil)
    assignment_invoke(ACTION, { "expected_metadata" => expected || detail.slice("user_data", "extension_data") }
                                .merge(fields))
  end

  def test_a_model_without_the_dictionary_reads_empty_and_neither_the_read_nor_clearing_writes
    revision = @session.revision
    assert_equal EMPTY.merge("extension_status" => {}), detail
    assert_nil @model.attribute_dictionary(DICTIONARY)
    cleared = write("user_data" => {})
    assert_equal %w[completed none], cleared.values_at("status", "effect"), cleared.inspect
    assert_nil @model.attribute_dictionary(DICTIONARY)
    assert_equal revision, @session.revision
  end

  def test_a_write_reads_back_detached_repeats_as_a_no_op_and_one_undo_takes_it_back
    note = { "example_org" => { "名前" => "Wärmebrücke ✓", "null" => nil, "false" => false, "zero" => 0,
                                "object" => {}, "array" => [] } }
    operations = @model.operations.length
    written = write("user_data" => note)
    assert_equal "committed", written.fetch("effect"), written.inspect
    assert_equal operations + 1, @model.operations.length
    assert_equal note, written.dig("value", "user_data")
    read = detail
    assert_equal note, read.fetch("user_data")
    read.fetch("user_data").clear
    assert_equal note, detail.fetch("user_data"), "a read hands out a detached map"

    revision = @session.revision
    assert_equal "none", write("user_data" => note).fetch("effect"), "writing what is stored opens no step"
    assert_equal revision, @session.revision

    @model.undo
    assert_equal EMPTY, detail.slice("user_data", "extension_data")
    @model.redo
    assert_equal note, detail.fetch("user_data")
  end

  def test_stale_empty_and_invalid_writes_refuse_and_write_nothing
    write("user_data" => { "kept" => true })
    revision = @session.revision
    refusals = {
      "target.changed" => [{ "user_data" => { "kept" => false } }, EMPTY],
      "params.invalid" => [{}, nil],
      "validation.failed" => [{ "extension_payloads" => { REVIEW => { "status" => "unknown" } } }, nil],
      "extension.unavailable" => [{ "extension_payloads" => { "absent.extension" => {} } }, nil]
    }
    refusals.each do |code, (fields, expected)|
      result = write(fields, expected)
      assert_equal ["refused", code], result.values_at("status", "code"), result.inspect
    end
    assert_equal revision, @session.revision
    assert_equal({ "kept" => true }, detail.fetch("user_data"))
  end

  def test_a_payload_writes_beside_user_data_and_feature_settings_stay_untouched
    written = write("user_data" => { "x" => 1 }, "extension_payloads" => { REVIEW => { "status" => "draft" } })
    assert_equal "committed", written.fetch("effect"), written.inspect
    read = detail
    assert_equal({ "x" => 1 }, read.fetch("user_data"))
    assert_equal({ "status" => "draft" }, read.dig("extension_data", REVIEW, "payload"))
    assert_equal({ REVIEW => "understood" }, read.fetch("extension_status"))
    assert_nil @model.attribute_dictionary("ph_composer.spaces_settings")
    assert_nil @model.attribute_dictionary("ph_composer.windows_settings")
  end

  def test_stored_maps_that_are_not_plain_json_objects_refuse_the_read
    PhComposer::ModelMetadata::SETTINGS.store.write(@model, "user_data" => [1], "extension_data" => {})
    result = API.query(:context => @context, :name => DETAIL, :params => {})
    assert_equal %w[refused record.unreadable], result.values_at("status", "code"), result.inspect
  end
end
