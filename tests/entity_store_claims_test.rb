# frozen_string_literal: true

require_relative "test_helper"

# The shared "this already belongs to PH-Composer" check (context/EXTENSIBILITY.md, "Native menu items").
class EntityStoreClaimsTest < PhComposerTestCase
  STORE = PhComposer::Records::EntityStore
  DICTIONARY = "ph_composer.test_claims"

  def setup
    super
    @model = Sketchup.active_model
    @first = STORE.new(DICTIONARY, :key => "first", :claims_entity => true)
    @second = STORE.new(DICTIONARY, :key => "second", :claims_entity => true)
    @other = STORE.new("ph_composer.test_unclaimed")
  end

  def group(id, *children)
    Sketchup::Group.new(id, Sketchup::Entities.new(children))
  end

  def test_each_key_in_one_dictionary_claims_its_own_entity
    first = group(1)
    second = group(2)
    @first.write(first, "id" => "a")
    @second.write(second, "id" => "b")

    assert STORE.claimed?([first])
    assert STORE.claimed?([second])
  end

  def test_a_record_in_a_store_that_does_not_claim_leaves_the_entity_open
    entity = group(3)
    @other.write(entity, "id" => "c")

    refute STORE.claimed?([entity])
    refute STORE.claimed?([group(4)])
  end

  def test_the_contents_check_finds_a_claim_at_any_depth_and_leaves_its_input_alone
    claimed = group(9)
    @first.write(claimed, "id" => "e")
    definition = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([group(8, claimed)]))
    wrapper = group(7, Sketchup::ComponentInstance.new(10, definition))
    selected = [wrapper]

    assert STORE.claimed_within?(selected)
    refute STORE.claimed?(selected), "the flat check reads the wrapper alone"
    assert_equal [wrapper], selected

    open = group(11, group(12))
    @other.write(open, "id" => "f")
    refute STORE.claimed_within?([open])
  end

  def test_the_selection_check_counts_the_open_context
    child = group(6)
    claimed = group(5, child)
    @first.write(claimed, "id" => "d")
    @model.entities << claimed
    refute STORE.selection_claimed?(@model), "nothing selected at the root"

    @model.active_path = [claimed]
    @model.selection.add(child)
    assert STORE.selection_claimed?(@model)
  end
end
