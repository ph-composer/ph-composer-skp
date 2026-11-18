# frozen_string_literal: true

require_relative "test_helper"
require "json"

# The outline map's ring is drawn from the points in tests/support/map_ring_vectors.json, which
# tests/map_projection_test.js holds the panel's ring function to. Measured here with the Phius limit check's
# own distance function, every point sits on the limit, so the ring shows exactly where a station passes.
class MapRingTest < Minitest::Test
  LimitCheck = PhComposer::Climate::LimitCheck

  def test_ring_points_are_the_distance_limit_from_the_centre_at_three_latitudes
    vectors = JSON.parse(File.read(File.join(__dir__, "support", "map_ring_vectors.json")))
    assert_in_delta LimitCheck::DISTANCE_LIMIT_KM, vectors.fetch("radius_km"), 1e-12
    centres = vectors.fetch("centres")
    assert_equal 3, centres.map { |centre| centre.fetch("latitude_deg") }.uniq.length
    centres.each do |centre|
      centre.fetch("ring").each do |latitude, longitude|
        distance = LimitCheck.distance_km(centre.fetch("latitude_deg"), centre.fetch("longitude_deg"),
                                          latitude, longitude)
        assert_in_delta LimitCheck::DISTANCE_LIMIT_KM, distance, 1e-5
      end
    end
  end
end
