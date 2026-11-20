# frozen_string_literal: true

require_relative "test_helper"

# The pure Shading reads: which marked container a Face is shading through, and the component name it exports
# under, over detached container rows, outermost first.
class ShadingReadsTest < PhComposerTestCase
  READS = PhComposer::Shading::Reads

  def container(name: "", marked: false, zone_name: nil, owned: false, path: [1])
    READS::Container.new(:path => path, :marked => marked, :zone_name => zone_name, :owned => owned, :name => name)
  end

  def test_the_nearest_named_container_names_the_component
    cases = {
      "nested, the inner one unnamed" => [[container(:name => "Neighbour"), container], "Neighbour"],
      "nested, both named" => [[container(:name => "Outer"), container(:name => "Inner")], "Inner"],
      "one named container" => [[container(:name => "Louvre")], "Louvre"],
      "a blank name is no name" => [[container(:name => "Site"), container(:name => "  ")], "Site"],
      "a Zone as the nearest" => [[container(:name => "Site"), container(:zone_name => "Zone A")], "Zone A Shading"],
      "a named Group inside a Zone" => [[container(:zone_name => "Zone A"), container(:name => "Fin")], "Fin"],
      "no named container" => [[container, container], "Shading"],
      "the Model root" => [[], "Shading"]
    }
    cases.each { |label, (containers, name)| assert_equal name, READS.component_name(containers), label }
  end

  def test_a_mark_reaches_down_until_a_zone_or_an_owned_container
    marked = container(:marked => true, :name => "Neighbour", :path => [20])
    assert_equal [20], READS.inherited_from([marked, container]).path
    assert_nil READS.inherited_from([marked, container(:zone_name => "Zone A")])
    assert_nil READS.inherited_from([marked, container(:owned => true)])
    assert_nil READS.inherited_from([container(:owned => true), marked])
    assert_nil READS.inherited_from([container(:marked => true, :zone_name => "Zone A")])
    assert_equal [21], READS.inherited_from([marked, container(:marked => true, :path => [21])]).path
  end

  def test_a_face_is_shading_by_its_own_mark_or_a_container_unless_another_feature_owns_it
    marked = [container(:marked => true)]
    assert READS.shading_face?(:marked => true, :owned => false, :containers => [])
    assert READS.shading_face?(:marked => false, :owned => false, :containers => marked)
    refute READS.shading_face?(:marked => false, :owned => false, :containers => [container])
    refute READS.shading_face?(:marked => true, :owned => true, :containers => marked)
    refute READS.shading_face?(:marked => true, :owned => false, :containers => [container(:owned => true)])
  end
end
