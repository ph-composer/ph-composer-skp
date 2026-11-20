# frozen_string_literal: true

require_relative "test_helper"

# One store, one dictionary and one record shape carry the Shading mark on all three entity kinds it may sit
# on: a Face, a Group and a ComponentInstance. The mark claims nothing, so Make Zone stays open around it.
class ShadingMarkStoreTest < PhComposerTestCase
  STORE = PhComposer::Records::EntityStore
  DICTIONARY = "ph_composer.shading"
  RECORD = { "schema_version" => 1 }.freeze

  def setup
    super
    @store = STORE.new(DICTIONARY)
  end

  def marked_entities
    definition = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([Sketchup::Face.new(4)]))
    {
      "Face" => Sketchup::Face.new(1),
      "Group" => Sketchup::Group.new(2, Sketchup::Entities.new([Sketchup::Face.new(3)])),
      "ComponentInstance" => Sketchup::ComponentInstance.new(5, definition)
    }
  end

  def test_one_store_reads_writes_and_removes_the_mark_on_each_entity_kind
    marked_entities.each do |kind, entity|
      assert_nil @store.read(entity), kind
      assert_nil entity.attribute_dictionaries, "#{kind}: a read creates no dictionary"
      refute @store.marks?(entity), kind

      @store.write(entity, RECORD)
      assert @store.marks?(entity), kind
      assert_equal RECORD, @store.read(entity), kind
      assert_equal [DICTIONARY], entity.attribute_dictionaries.map(&:name), kind

      @store.delete(entity)
      refute @store.marks?(entity), kind
      assert_nil @store.read(entity), kind
    end
  end

  def test_the_mark_does_not_claim_its_entity
    claiming = STORE.new("ph_composer.test_shading_claims", :claims_entity => true)
    marked_entities.each do |kind, entity|
      @store.write(entity, RECORD)
      refute STORE.claimed_within?([entity]), kind

      claiming.write(entity, "id" => "a")
      assert STORE.claimed_within?([entity]), "#{kind}: the check reads this entity"
    end
  end
end
