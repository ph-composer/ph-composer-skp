# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

# Restore Zone recovers the Zone id its stamped Faces remember, so a Space beside it that names the Zone is
# hosted again: the Space does not move, and `space.zone_missing` clears.
class SpacesRestoreZoneTest < PhComposerTestCase
  include SpaceFixtures

  API = PhComposer::API

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @space = space_group(110, space_record("S", :number => "1"),
                         [volume_group(111, volume_record("A"), [floor_face(112, rectangle(0, 0, 2, 2),
                                                                            segment_record("A"))])])
    @floor = floor_face(120, rectangle(0, 0, 4, 4))
    @zone = zone_group(100, "Z", [@floor])
    @model.entities << @zone << @space
    ZONES::STAMP_STORE.write(@floor, ZONES::Schema.stamp(ZONES::ZONE_STORE.read(@zone)))
    SPACES::SPACE_STORE.write(@space, SPACES::SPACE_STORE.read(@space).merge("zone_id" => "zon_ZZZZZZZZZZZZ"))
  end

  def test_a_space_beside_an_exploded_zone_is_hosted_again_when_the_zone_is_restored
    @zone.explode
    gone = space_row
    assert_includes gone.fetch("findings").map { |finding| finding["code"] }, "space.zone_missing"
    result = API.invoke(:context => @context, :name => "ph_composer.zones.restore",
                        :params => { "parent_path" => [], "zone_id" => "zon_ZZZZZZZZZZZZ" },
                        :request => { "sequence" => 1, "expected_revision" => @session.revision })
    assert_equal "completed", result["status"], result.inspect
    row = space_row
    assert_equal "zon_ZZZZZZZZZZZZ", row.dig("zone", "zone_id")
    assert_equal [110], row.dig("reference", "entity_path")
    assert_empty row.fetch("findings").map { |finding| finding["code"] } & %w[space.outside_zone space.zone_missing]
  end

  private

  def space_row
    API.query(:context => @context, :name => "ph_composer.spaces.all").dig("value", "spaces", 0)
  end
end
