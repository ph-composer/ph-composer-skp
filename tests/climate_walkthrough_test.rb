# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/examples/climate/climate_walkthrough"
require_relative "../tools/examples/climate/station_seed"
require_relative "support/climate_station_files"
require "minitest/mock"

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

  # The agent guide's recipe on a copy of the invented fixture folder, which the user chose in SketchUp.
  def test_the_attach_walkthrough_attaches_the_nearest_passing_station_in_one_undo_step
    model = Sketchup.active_model
    root = Dir.mktmpdir("climate_walkthrough")
    folder = File.join(root, "Phius invented")
    FileUtils.cp_r(File.expand_path("fixtures/climate/folder", __dir__), folder)
    context = PhComposer::API.connect(:session_id => PhComposer::Sessions.for(model).id,
                                      :capabilities => %w[read setup])
    id = UI.stub(:select_directory, folder) do
      PhComposer::NativeApproval.setup(context, "ph_composer.climate.folders.add", {})
    end.dig("value", "id")
    client = AuthoringExample::Client.new
    site = ClimateStationFiles::SITE.merge("climate_zone" => nil, "hours_from_utc" => nil)
    expected = client.query("ph_composer.climate.site.get").fetch("value").slice(*site.keys)
    client.invoke("ph_composer.climate.site.update", "values" => site, "expected_values" => expected)
    operations = model.operations.length

    attached = ClimateWalkthrough.run_attach(id)

    assert attached.fetch("passed"), attached.inspect
    assert_equal ["Attach Climate Station"], model.operations.drop(operations).map(&:first)
    assert_equal "Caf\u00E9 Station XB", ClimateWalkthrough.climate(client).dig("climate", "values", "name")
  ensure
    FileUtils.rm_rf(root) if root
  end

  def test_the_walkthrough_uses_public_calls_only_and_the_seed_matches_its_values
    text = File.read(File.expand_path("../tools/examples/climate/climate_walkthrough.rb", __dir__))

    refute_match(/PhComposer::Climate/, text)
    assert_equal ClimateStationSeed::STATION_AIR_JAN, ClimateWalkthrough::STATION_AIR_JAN
  end
end
