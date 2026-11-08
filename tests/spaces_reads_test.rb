# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

class SpacesReadsTest < PhComposerTestCase
  include SpaceFixtures

  API = PhComposer::API

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
  end

  def all
    result = API.query(:context => @context, :name => "ph_composer.spaces.all")
    assert_equal "completed", result["status"], result.inspect
    result.fetch("value")
  end

  def space(value, number)
    value.fetch("spaces").find { |row| row.dig("values", "number") == number }
  end

  def test_the_reference_model_reads_the_hand_calculated_totals
    reference_model
    value = all
    zone_a, zone_b = value.fetch("zones")
    assert_equal [20.0, 22.0, 59.6], [zone_a["weighted_area_m2"], zone_a["floor_area_m2"], zone_a["net_volume_m3"]]
      .map { |number| number.round(6) }
    assert_equal [12.0, 12.0, 36.0], [zone_b["weighted_area_m2"], zone_b["floor_area_m2"], zone_b["net_volume_m3"]]
      .map { |number| number.round(6) }
    hall = space(value, "103")
    assert_equal [4.0, 6.0, 20.0], hall.fetch("metrics").values_at("weighted_area_m2", "floor_area_m2", "net_volume_m3")
                                       .map { |number| number.round(6) }
    assert_equal [10.0, 10.0], hall.fetch("volumes").map { |volume| volume.dig("metrics", "net_volume_m3").round(6) }
    assert_in_delta 20.0 / 6.0, hall.dig("metrics", "average_height_m"), 1e-9
  end

  def test_building_segment_and_model_totals_cover_every_space
    reference_model
    value = API.query(:context => @context, :name => "ph_composer.spaces.list", :params => { "limit" => 1 })
               .fetch("value")
    segment = value.fetch("building_segments").first
    assert_equal ["Main Building", 2], segment.values_at("name", "zone_count")
    assert_equal [32.0, 34.0, 95.6], segment.values_at("weighted_area_m2", "floor_area_m2", "net_volume_m3")
                                            .map { |number| number.round(6) }
    model = value.fetch("model")
    assert_equal [32.0, 34.0, 95.6], model.values_at("weighted_area_m2", "floor_area_m2", "net_volume_m3")
                                          .map { |number| number.round(6) }
  end

  def test_zone_airflow_sums_follow_the_any_set_rule
    reference_model
    zone_a, zone_b = all.fetch("zones")
    assert_equal({ "v_sup_m3h" => 60.0, "v_eta_m3h" => 40.0, "v_tran_m3h" => 20.0 }, zone_a["airflows"])
    assert_equal 0, zone_a["inheriting_count"]
    assert_equal({ "v_sup_m3h" => nil, "v_eta_m3h" => nil, "v_tran_m3h" => nil }, zone_b["airflows"])
    assert_equal 1, zone_b["inheriting_count"]
    living = space(all, "101")
    assert_equal "user_specified", living["airflow_mode"]
    assert_equal({ "v_sup_m3h" => 60.0, "v_eta_m3h" => 0.0, "v_tran_m3h" => 0.0 }, living["airflows"])
    assert_equal "inheriting", space(all, "201")["airflow_mode"]
  end

  def test_rows_carry_references_zone_membership_and_the_projected_floor_finding
    reference_model
    value = all
    loft = space(value, "201")
    assert_equal({ "space_id" => "spc_FFFFFFFFFFFF", "entity_path" => [2000, 2100] }, loft["reference"])
    assert_equal({ "zone_id" => "zon_BBBBBBBBBBBB", "zone_path" => [2000] }, loft["zone"])
    segment = loft.dig("volumes", 0, "floor_segments", 0)
    assert_equal [2000, 2100, 2110, 2111], segment.dig("reference", "entity_path")
    assert_equal ["space.floor_projected"], segment.fetch("findings").map { |finding| finding["code"] }
    assert_in_delta 12.0, segment.dig("metrics", "floor_area_m2"), 1e-9
    assert_equal({}, loft["extension_status"])
    assert_empty value.fetch("findings")
  end

  def test_a_space_under_a_rotated_wrapper_measures_in_world_and_finds_its_zone
    rotation = Geom::Transformation.new([0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 5, 0, 0, 1])
    room = space_group(110, space_record("R", :number => "1"),
                       [volume_group(111, volume_record("R"), [floor_face(112, rectangle(0, 0, 2, 3),
                                                                          segment_record("R"))])])
    wrapper = Sketchup::Group.new(105, Sketchup::Entities.new([room]))
    @model.entities << zone_group(100, "Z", [wrapper], :transformation => rotation)
    row = all.fetch("spaces").first
    assert_equal({ "zone_id" => "zon_ZZZZZZZZZZZZ", "zone_path" => [100] }, row["zone"])
    assert_equal [100, 105, 110], row.dig("reference", "entity_path")
    assert_in_delta 6.0, row.dig("metrics", "floor_area_m2"), 1e-9
  end

  def test_each_structural_finding_from_a_minimal_fixture
    empty = space_group(110, space_record("E", :number => "1"), [])
    no_floor = space_group(120, space_record("N", :number => "1"),
                           [volume_group(121, volume_record("N", :height => nil), [])])
    deep = space_group(130, space_record("D", :number => "3"),
                       [Sketchup::Group.new(131, Sketchup::Entities.new([volume_group(132, volume_record("D"), [])]))])
    inner = space_group(141, space_record("I", :number => "4"), [])
    outer = space_group(140, space_record("O", :number => "5"), [inner])
    orphan = volume_group(150, volume_record("P"), [])
    loose = floor_face(160, rectangle(0, 0, 1, 1), segment_record("S"))
    @model.entities << zone_group(100, "Z", [empty, no_floor, deep, outer, orphan, loose])
    @model.entities << space_group(200, space_record("X", :number => "9"), [])
    value = all
    codes = value.fetch("spaces").to_h do |row|
      [row.dig("values", "number") + row.fetch("id")[-1],
       (row.fetch("findings") + row.fetch("volumes").flat_map { |volume| volume.fetch("findings") })
         .map { |finding| finding["code"] }.sort]
    end
    assert_equal %w[space.empty space.number_duplicate], codes.fetch("1E")
    assert_equal %w[space.height_missing space.number_duplicate space.volume_empty], codes.fetch("1N")
    assert_equal %w[space.volume_empty space.volume_nested], codes.fetch("3D")
    assert_equal %w[space.empty space.nested], codes.fetch("4I")
    assert_equal %w[space.empty space.outside_zone], codes.fetch("9X")
    assert_equal %w[space.segment_misplaced space.volume_orphan],
                 value.fetch("findings").map { |finding| finding["code"] }.sort
    assert(value.fetch("findings").all? { |finding| finding["blocks_export"] })
  end

  def test_list_pages_spaces_but_sums_every_zone_space
    reference_model
    page = API.query(:context => @context, :name => "ph_composer.spaces.list", :params => { "limit" => 1 })
    assert_equal "completed", page["status"], page.inspect
    value = page.fetch("value")
    assert_equal 4, value["total"]
    assert_equal ["101"], value.fetch("spaces").map { |row| row.dig("values", "number") }
    assert_in_delta 59.6, value.dig("zones", 0, "net_volume_m3"), 1e-9
    refute_nil value["next_cursor"]
    ids = API.query(:context => @context, :name => "ph_composer.spaces.list",
                    :params => { "ids" => ["spc_FFFFFFFFFFFF"] }).dig("value", "spaces")
    assert_equal ["201"], ids.map { |row| row.dig("values", "number") }
  end

  def test_the_space_height_is_weighted_by_floor_area
    low = volume_group(111, volume_record("L", :height => 2.0),
                       [floor_face(112, rectangle(0, 0, 2, 5), segment_record("L"))])
    high = volume_group(113, volume_record("H", :number => 2, :height => 4.0),
                        [floor_face(114, rectangle(2, 0, 2, 5), segment_record("H", :net_area_factor => 0.5))])
    @model.entities << zone_group(100, "Z", [space_group(110, space_record("S", :number => "1"), [low, high])])
    assert_in_delta 3.0, all.dig("spaces", 0, "metrics", "average_height_m"), 1e-9
  end

  def test_a_zone_read_refusal_reaches_the_caller_declared
    group = Sketchup::Group.new(100, Sketchup::Entities.new([]))
    group.set_attribute(PhComposer::Zones::ZONE_STORE.dictionary, PhComposer::Zones::ZONE_STORE.key, "{not json")
    @model.entities << group
    result = API.query(:context => @context, :name => "ph_composer.spaces.all")
    assert_equal %w[refused record.unreadable], result.values_at("status", "code")
  end

  def test_reference_targets_list_every_occurrence
    reference_model
    engine = PhComposer::Records::Engine.new(@model, PhComposer::Registry.current.catalog)
    space = engine.resolve_reference(PhComposer::Spaces::SPACE_KIND, "spc_HHHHHHHHHHHH")
    assert_equal [1000, 1300], space.key
    segment = engine.resolve_reference(PhComposer::Spaces::FLOOR_SEGMENT_KIND, "fsg_IIIIIIIIIIII")
    assert_equal [1000, 1300, 1320, 1321], segment.key
    @model.entities << volume_group(3000, volume_record("O"), [floor_face(3001, rectangle(0, 0, 1, 1),
                                                                          segment_record("I"))])
    error = assert_raises(PhComposer::CodedError) do
      engine.resolve_reference(PhComposer::Spaces::FLOOR_SEGMENT_KIND, "fsg_IIIIIIIIIIII")
    end
    assert_equal "target.ambiguous", error.code
  end
end
