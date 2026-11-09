# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

# Move Space to Zone is a record edit: the Space's `zone_id` names the Zone, the Group stays where it
# stands, one Undo step (context/CONTRACTS.md, "Space membership").
class SpacesMoveTest < PhComposerTestCase
  include SpaceFixtures

  API = PhComposer::API
  ROOT_ZONE_B = "zon_BBBBBBBBBBBB"

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @volume = volume_group(111, volume_record("A"), [floor_face(112, rectangle(1, 1, 2, 3), segment_record("A"))])
    @space = space_group(110, space_record("S", :number => "7", :name => "Hall"), [@volume],
                         :transformation => Geom::Transformation.translation([10, 20, 0]))
    @space.name = "7 Hall"
    @zone_a = zone_group(100, "A", [])
    @zone_b = zone_group(200, "B", [space_group(210, space_record("T", :number => "7"), [])])
    @model.entities << @zone_a << @zone_b << @space
    SPACES::SPACE_STORE.write(@space, space_record("S", :number => "7", :name => "Hall")
                                                  .merge("zone_id" => "zon_AAAAAAAAAAAA"))
  end

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => "ph_composer.spaces.#{name}", :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end

  def move(zone_path = [200])
    invoke("move_to_zone", "space" => { "space_id" => "spc_SSSSSSSSSSSS", "entity_path" => [110] },
                           "zone" => { "zone_id" => ZONES::ZONE_STORE.read(zone_at(zone_path))["id"],
                                       "zone_path" => zone_path })
  end

  def zone_at(path)
    SPACES::Occurrences.entity_at(@model, path)
  end

  def row
    API.query(:context => @context, :name => "ph_composer.spaces.all").fetch("value").fetch("spaces")
       .find { |space| space["id"] == "spc_SSSSSSSSSSSS" }
  end

  def test_move_writes_the_zone_on_the_record_and_leaves_the_group_where_it_stands
    records = SPACES::SPACE_STORE.read(@space)
    before = @model.operations.length
    result = move
    assert_equal "completed", result["status"], result.inspect
    assert_equal before + 1, @model.operations.length
    assert_equal({ "zone_id" => ROOT_ZONE_B, "zone_path" => [200] }, row["zone"])
    assert_equal [110], row.dig("reference", "entity_path")
    assert_equal @volume.entities.to_a, zone_at([110, 111]).entities.to_a
    assert_equal records.merge("zone_id" => ROOT_ZONE_B), SPACES::SPACE_STORE.read(@space)
    assert_equal "7 Hall", @space.name
  end

  def test_a_moved_space_keeps_its_number_and_flags_the_collision
    move
    assert_equal "7", row.dig("values", "number")
    assert_includes row.fetch("findings").map { |finding| finding["code"] }, "space.number_duplicate"
  end

  def test_one_undo_restores_the_zone_and_redo_moves_it_again
    move
    @model.undo
    assert_equal({ "zone_id" => "zon_AAAAAAAAAAAA", "zone_path" => [100] }, row["zone"])
    @model.redo
    assert_equal [200], row.dig("zone", "zone_path")
  end

  def test_move_refuses_the_current_zone
    assert_equal %w[refused space.same_zone], move([100]).values_at("status", "code")
  end

  def test_move_works_with_an_edit_context_open_because_no_geometry_moves
    @model.active_path = [@zone_a]
    assert_equal "completed", move["status"]
    assert_equal [200], row.dig("zone", "zone_path")
  end

  def test_a_locked_target_zone_is_only_named_and_does_not_refuse
    @zone_b.locked = true
    assert_equal "completed", move["status"]
  end

  def test_a_space_whose_zone_is_gone_reads_zone_missing_and_unhost_clears_it
    @model.entities.delete(@zone_a)
    UI.run_timers
    finding = row.fetch("findings").find { |item| item["code"] == "space.zone_missing" }
    assert_equal "unhost", finding["repair"]
    assert finding["blocks_export"]
    assert_nil row["zone"]

    result = invoke("unhost", "space" => { "space_id" => "spc_SSSSSSSSSSSS", "entity_path" => [110] })
    assert_equal "completed", result["status"], result.inspect
    refute SPACES::SPACE_STORE.read(@space).key?("zone_id")
    codes = row.fetch("findings").map { |item| item["code"] }
    assert_includes codes, "space.outside_zone"
    refute_includes codes, "space.zone_missing"
    @model.undo
    assert_equal "zon_AAAAAAAAAAAA", row.dig("values", "zone_id")
  end
end
