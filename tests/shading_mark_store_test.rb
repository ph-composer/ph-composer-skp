# frozen_string_literal: true

require_relative "test_helper"

# One store, one dictionary and one record shape carry the Shading mark on all three entity kinds it may sit
# on: a Face, a Group and a ComponentInstance. The mark claims nothing, so Make Zone stays open around it, and
# it excludes from a Zone's envelope through the foundation's neutral check, which names no feature.
class ShadingMarkStoreTest < PhComposerTestCase
  STORE = PhComposer::Records::EntityStore
  MARK = PhComposer::Shading::Mark::STORE
  DICTIONARY = "ph_composer.shading"
  RECORD = { "schema_version" => 1 }.freeze
  CLAIMING = STORE.new("ph_composer.test_shading_claims", :claims_entity => true)

  def marked_entities
    definition = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([Sketchup::Face.new(4)]))
    {
      "Face" => Sketchup::Face.new(1),
      "Group" => Sketchup::Group.new(2, Sketchup::Entities.new([Sketchup::Face.new(3)])),
      "ComponentInstance" => Sketchup::ComponentInstance.new(5, definition)
    }
  end

  def test_one_store_reads_writes_and_removes_the_mark_on_each_entity_kind
    assert_equal DICTIONARY, MARK.dictionary
    marked_entities.each do |kind, entity|
      assert_nil MARK.read(entity), kind
      assert_nil entity.attribute_dictionaries, "#{kind}: a read creates no dictionary"
      refute MARK.marks?(entity), kind

      MARK.write(entity, RECORD)
      assert MARK.marks?(entity), kind
      assert_equal RECORD, MARK.read(entity), kind
      assert_equal [DICTIONARY], entity.attribute_dictionaries.map(&:name), kind

      MARK.delete(entity)
      refute MARK.marks?(entity), kind
      assert_nil MARK.read(entity), kind
    end
  end

  def test_the_mark_does_not_claim_its_entity
    marked_entities.each do |kind, entity|
      MARK.write(entity, RECORD)
      refute STORE.claimed_within?([entity]), kind

      CLAIMING.write(entity, "id" => "a")
      assert STORE.claimed_within?([entity]), "#{kind}: the check reads this entity"
    end
  end

  # Each case is an `inside` list, from the first entity inside a Zone Group down to the Face, as which
  # entities carry the mark, which are claimed, and whether the Face has left the envelope. The live check and
  # its detached twin read the same table, so they cannot drift.
  ENVELOPE_CASES = {
    "an unmarked Face" => [[[], []], false],
    "a marked Face" => [[[:face], []], true],
    "a Face inside a marked Group" => [[[:group], []], true],
    "a marked Face with a damaged mark" => [[[:damaged], []], true],
    "a marked Face inside a claimed Group" => [[[:face], [:group]], false],
    "a marked Group around a claimed Face" => [[[:group], [:face]], false]
  }.freeze

  def test_envelope_exclusion_reads_the_flag_and_lets_a_claim_win_live_and_detached
    ENVELOPE_CASES.each do |label, ((marks, claims), excluded)|
      group = Sketchup::Group.new(10, Sketchup::Entities.new([face = Sketchup::Face.new(11)]))
      inside = { :group => group, :face => face }
      marks.each do |mark|
        next face.set_attribute(DICTIONARY, "record", "{not json") if mark == :damaged

        MARK.write(inside.fetch(mark), RECORD)
      end
      claims.each { |claim| CLAIMING.write(inside.fetch(claim), "id" => "a") }
      entities = [group, face]
      entries = entities.map do |entity|
        PhComposer::Export::GeometrySnapshot::Entry.new(
          :dictionaries => PhComposer::Export::GeometrySnapshot.read_dictionaries(entity)
        )
      end
      assert_equal excluded, STORE.envelope_excluded?(entities), label
      assert_equal excluded, STORE.envelope_excluded_entries?(entries), "#{label} (detached)"
    end
  end

  def test_only_a_flagged_store_excludes
    face = Sketchup::Face.new(1)
    STORE.new("ph_composer.test_shading_plain").write(face, RECORD)
    refute STORE.envelope_excluded?([face])
  end
end
