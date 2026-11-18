# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/examples/climate/climate_walkthrough"
require_relative "../tools/examples/climate/station_seed"

class ClimateWalkthroughTest < PhComposerTestCase
  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?("ph_composer.climate")
  end

  def test_the_walkthrough_enters_edits_restores_and_clears_a_climate_and_each_undo_step_reads_its_trace_row
    model = Sketchup.active_model
    operations = model.operations.length

    hand = ClimateWalkthrough.run_hand
    seeded = ClimateStationSeed.seed
    station = ClimateWalkthrough.run_station

    assert hand.fetch("passed"), hand.inspect
    assert seeded.fetch("seeded"), seeded.inspect
    assert station.fetch("passed"), station.inspect
    trace = ClimateWalkthrough::TRACE
    assert_equal trace.map(&:first).reverse, model.operations.drop(operations).map(&:first)
    trace.each do |name, expected|
      model.undo
      assert_equal expected, ClimateWalkthrough.state, "after Undo #{name}"
    end
    trace.length.times { model.redo }
    assert ClimateWalkthrough.verify.fetch("passed")
  end

  def test_the_walkthrough_uses_public_calls_only_and_the_seed_matches_its_values
    text = File.read(File.expand_path("../tools/examples/climate/climate_walkthrough.rb", __dir__))

    refute_match(/PhComposer::Climate/, text)
    assert_equal ClimateStationSeed::STATION_AIR_JAN, ClimateWalkthrough::STATION_AIR_JAN
  end
end
