# frozen_string_literal: true

require_relative "test_helper"

# A Programs finding's Locate only locates: a row with Zones to check checks them and opens nothing else, and a row
# whose Zones are all a single dwelling's, which cannot be checked, opens that Segment's settings instead.
class ProgramsLocateTest < Minitest::Test
  OS = PhComposer::Programs::OccupancyState
  Preflight = PhComposer::Programs::ProgramPreflight

  def state
    segment = lambda do |id, single|
      OS::Segment.new(:id => id, :name => id, :category => "residential",
                      :settings => { "single_dwelling" => single }, :stored => true)
    end
    zone = lambda do |id, segment_id, path|
      OS::Zone.new(:id => id, :reference => { "zone_id" => id, "zone_path" => [path] }, :name => id,
                   :segment_id => segment_id, :assignment => {})
    end
    OS::State.new(:zones => [zone.call("zon_house", "bsg_house", 1), zone.call("zon_apt", "bsg_flats", 2)],
                  :segments => [segment.call("bsg_house", true), segment.call("bsg_flats", false)], :dwellings => [])
  end

  def test_a_row_over_a_single_dwelling_and_another_segment_checks_zones_and_opens_no_settings
    locate = Preflight.locate_params(state, %w[zon_house zon_apt], nil)
    assert_equal({ "zones" => [{ "zone_id" => "zon_apt", "zone_path" => [2] }] }, locate.fetch("params"))
  end

  def test_a_row_over_a_single_dwelling_alone_opens_its_settings
    assert_equal({ "building_segment_id" => "bsg_house" }, Preflight.locate_params(state, %w[zon_house], nil)
      .fetch("params"))
  end
end
