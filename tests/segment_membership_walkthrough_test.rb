# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/examples/authoring/segment_membership_walkthrough"

# The Building Segment walkthrough (tools/examples/authoring/segment_membership_walkthrough.rb) passes only
# through public calls, and each of its steps is one Undo step. Its box geometry needs the host; three named
# one-Face Groups stand in here.
class SegmentMembershipWalkthroughTest < PhComposerTestCase
  W = SegmentMembershipWalkthrough

  def setup
    super
    model = Sketchup.active_model
    PhComposer::Zones::Faces::Settings::STORE.write(model, PhComposer::Zones::Faces::Settings::DEFAULTS
                                                             .merge("suggest_on_make" => false))
    W::ZONES.each_with_index do |name, index|
      base = 100 * (index + 1)
      points = [[0, 0, 0], [2, 0, 0], [2, 2, 0]].map { |x, y, z| Geom::Point3d.new(x + (index * 5), y, z) }
      group = Sketchup::Group.new(base, Sketchup::Entities.new([Sketchup::Face.new(base + 1, {}, :points => points)]))
      group.name = "#{W::GROUP_PREFIX}#{name}"
      model.entities << group
    end
  end

  def test_the_walkthrough_moves_zones_out_and_back_and_each_step_undoes
    model = Sketchup.active_model
    made = W.make_zones
    assert_equal({ "Annex" => "Building", "House" => "Building", "Loft" => "Building" }, made.fetch("zones"))
    operations = model.operations.length

    result = W.run

    assert result.fetch("passed"), result.inspect
    assert_equal W::UNDO_NAMES, model.operations.drop(operations).map(&:first)
    model.undo
    assert_equal({ "Annex" => nil, "House" => nil, "Loft" => nil }, W.state.fetch("zones"), "Loft moved back undone")
    model.undo
    assert_equal %w[Annex Building], W.state.fetch("segments")
    assert_equal({ "Annex" => "Annex", "House" => nil, "Loft" => "Annex" }, W.state.fetch("zones"))
    3.times { model.undo }
    assert_equal made, W.state
    5.times { model.redo }
    assert W.verify.fetch("passed")
    text = File.read(File.expand_path("../tools/examples/authoring/segment_membership_walkthrough.rb", __dir__))
    refute_match(/PhComposer::Zones/, text, "the walkthrough uses only the public API")
  end
end
