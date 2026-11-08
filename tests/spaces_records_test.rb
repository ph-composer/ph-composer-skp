# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

class SpacesRecordsTest < PhComposerTestCase
  include SpaceFixtures

  SPACES = PhComposer::Spaces
  METRICS = PhComposer::Spaces::Metrics

  def test_each_record_validates_and_an_unknown_key_does_not
    [[SPACES::SPACE, space_record("A", :number => "1")], [SPACES::VOLUME, volume_record("A")],
     [SPACES::FLOOR_SEGMENT, segment_record("A")]].each do |kind, record|
      assert_empty kind.problems(record), kind.label
      refute_empty kind.problems(record.merge("colour" => "#fff")), kind.label
    end
    refute_empty SPACES::FLOOR_SEGMENT.problems(segment_record("A", :weighting_factor => 1.5))
    refute_empty SPACES::SPACE.problems(space_record("A", :number => "1", :airflows => { "v_sup_m3h" => nil }))
  end

  def test_airflow_absent_zero_and_a_value_are_three_stored_states
    absent = space_record("A", :number => "1")
    zero = space_record("A", :number => "1", :airflows => { "v_sup_m3h" => 0.0 })
    set = space_record("A", :number => "1", :airflows => { "v_sup_m3h" => 30.0 })
    group = Sketchup::Group.new(10)
    [absent, zero, set].each do |record|
      SPACES::SPACE_STORE.write(group, record)
      assert_equal record, SPACES::SPACE_STORE.read(group)
    end
    modes = [absent, zero, set].map { |record| METRICS.airflow_mode(record) }
    assert_equal %w[inheriting user_specified user_specified], modes
    assert_equal [nil, 0.0, 0.0], [absent, zero, set].map { |record| METRICS.airflows(record)["v_eta_m3h"] }
  end

  def test_clearing_the_last_airflow_returns_a_space_to_inheriting
    record = space_record("A", :number => "1", :airflows => { "v_tran_m3h" => 12.0 })
    assert_equal "user_specified", METRICS.airflow_mode(record)
    assert_equal "inheriting", METRICS.airflow_mode(record.reject { |key, _value| key == "v_tran_m3h" })
  end

  def test_projected_area_takes_plan_area_and_subtracts_holes
    sloped = [[0, 0, 0], [3, 0, 0], [3, 4, 2], [0, 4, 2]]
    assert_in_delta 12.0, METRICS.projected_area_m2([sloped]), 1e-9
    hole = [[1, 1, 0], [2, 1, 0], [2, 2, 0], [1, 2, 0]]
    assert_in_delta 11.0, METRICS.projected_area_m2([[[0, 0, 0], [3, 0, 0], [3, 4, 0], [0, 4, 0]], hole]), 1e-9
    refute METRICS.horizontal?([0.0, -0.447, 0.894])
    assert METRICS.horizontal?([0.0, 0.0, -1.0])
  end

  def test_projected_area_does_not_depend_on_where_the_face_is
    square = [[0, 0, 0], [0.1, 0, 0], [0.1, 0.1, 0], [0, 0.1, 0]]
    [[0, 0], [584_000, 4_500_000], [10_000_000, 10_000_000]].each do |x, y|
      moved = square.map { |px, py, pz| [px + x, py + y, pz] }
      assert_in_delta 0.01, METRICS.projected_area_m2([moved]), 1e-9, "at #{x}, #{y}"
    end
  end

  def test_the_height_setting_defaults_records_and_refuses_a_stale_write
    model = Sketchup.active_model
    session = PhComposer::Sessions.for(model)
    context = PhComposer::API.connect(:session_id => session.id)
    assert_equal 2.5, SPACES::Settings.default_height_m(model)
    result = PhComposer::API.invoke(:context => context, :name => "ph_composer.spaces.settings.update",
                                    :params => { "values" => { "last_height_m" => 2.7 },
                                                 "expected_values" => { "last_height_m" => nil } },
                                    :request => { "sequence" => 1, "expected_revision" => session.revision })
    assert_equal "completed", result["status"], result.inspect
    assert_equal 2.7, SPACES::Settings.default_height_m(model)
    stale = PhComposer::API.invoke(:context => context, :name => "ph_composer.spaces.settings.update",
                                   :params => { "values" => { "last_height_m" => 3.0 },
                                                "expected_values" => { "last_height_m" => nil } },
                                   :request => { "sequence" => 2, "expected_revision" => session.revision })
    assert_equal %w[refused target.changed], stale.values_at("status", "code")
  end
end
