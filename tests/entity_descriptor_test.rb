# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/record_fixtures"

# One descriptive contract for every record kind, catalog or entity-owned: its values, identity,
# occurrence reference and outgoing core references. The generic incoming-reference scan reads core
# references from it, so an entity record naming a catalog record blocks that record's deletion
# exactly as a catalog record does. Nothing here uses a building feature.
class EntityDescriptorTest < PhComposerTestCase
  include RecordFixtures

  MARKER = "test.descriptor.marker"
  MARKER_VALUES = {
    "type" => "object", "additionalProperties" => false,
    "properties" => { "definition_id" => { "type" => "string" } }
  }.freeze
  OCCURRENCE = {
    "type" => "object", "additionalProperties" => false, "required" => ["path"],
    "properties" => { "path" => { "type" => "array", "items" => { "type" => "integer" } } }
  }.freeze

  def setup
    super
    @model = Sketchup::Model.new
    @markers = []
  end

  def test_an_entity_target_publishes_its_values_occurrence_and_core_references
    assert_equal({
      "id" => MARKER, "label" => "Marker", "schema_version" => 1, "identity_field" => "id",
      "values" => MARKER_VALUES, "occurrence_reference" => OCCURRENCE,
      "references" => [{ "key" => "definition_id", "target_kind" => DEFINITION.id, "cardinality" => "one" }],
      "parts" => []
    }, marker_target.descriptor.to_h)
  end

  def test_a_catalog_kind_publishes_the_same_descriptor_shape
    descriptor = PART.descriptor.to_h

    assert_equal [PART.id, 1, PART.values_schema, nil],
                 descriptor.values_at("id", "schema_version", "values", "occurrence_reference")
    assert_equal [["definition_id", DEFINITION.id, "one"], ["neighbour_ids", PART.id, "many"]],
                 descriptor.fetch("references").map { |row| row.values_at("key", "target_kind", "cardinality") }
  end

  def test_the_descriptor_names_the_core_targets_one_record_holds
    record = { "id" => "mkr_1", "definition_id" => "tdf_000000000001" }

    assert_equal [[DEFINITION.id, "tdf_000000000001"]], marker_target.descriptor.referenced_targets(record)
    assert_empty marker_target.descriptor.referenced_targets({ "id" => "mkr_2" })
  end

  def test_an_entity_core_reference_blocks_deleting_the_catalog_record
    definition = seed_definition
    @markers << marker([7], "definition_id" => definition)

    error = assert_raises(PhComposer::CodedError) do
      engine.propose_delete(DEFINITION.id, definition, PhComposer::Records::ChangeSet.new)
    end

    assert_equal "reference.in_use", error.code
    assert_match(/#{MARKER} mkr_7 still refers/, error.message)
  end

  def test_an_entity_record_without_the_reference_leaves_deletion_alone
    definition = seed_definition
    @markers << marker([7], {})
    changes = PhComposer::Records::ChangeSet.new

    engine.propose_delete(DEFINITION.id, definition, changes)

    assert_equal [DEFINITION.id], changes.writes.map(&:kind)
  end

  private

  def marker_target
    markers = @markers
    PhComposer::Records::ReferenceTarget.new(
      :id => MARKER, :label => "Marker", :schema_version => 1, :values => MARKER_VALUES,
      :occurrence => OCCURRENCE,
      :references => [PhComposer::Records::Reference.new(:key => "definition_id", :target_kind => DEFINITION.id,
                                                         :cardinality => "one", :required => false)],
      :records => ->(_model) { markers }, :validate => ->(_record) { [] }
    )
  end

  def marker(key, values)
    PhComposer::Records::ReferenceEntry.new(:kind => MARKER, :key => key,
                                            :record => { "id" => "mkr_#{key.last}" }.merge(values))
  end

  def engine
    PhComposer::Records::Engine.new(@model, PhComposer::Records::Catalog.new(:kinds => [DEFINITION, PART],
                                                                             :reference_targets => [marker_target]))
  end

  def seed_definition
    changes = PhComposer::Records::ChangeSet.new
    id = engine.propose_create(DEFINITION.id, changes, :values => { "label" => "Frame" })
    engine.apply(changes)
    id
  end
end
