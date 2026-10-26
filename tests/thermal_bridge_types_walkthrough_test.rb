# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/examples/authoring/thermal_bridge_types_walkthrough"

class ThermalBridgeTypesWalkthroughTest < PhComposerTestCase
  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?("ph_composer.thermal_bridges")
  end

  def test_the_walkthrough_authors_the_catalog_through_public_calls_and_undo_steps_back_through_it
    result = ThermalBridgeTypesWalkthrough.run
    assert result.fetch("passed"), result.inspect
    assert_equal 6, result.fetch("steps").count { |step| %w[create update duplicate delete].include?(step["step"]) }
    model = Sketchup.active_model
    model.undo
    assert_includes ThermalBridgeTypesWalkthrough.state.keys, "Walkthrough balcony"
    5.times { model.undo }
    assert_empty ThermalBridgeTypesWalkthrough.state
    text = File.read(File.expand_path("../tools/examples/authoring/thermal_bridge_types_walkthrough.rb", __dir__))
    refute_match(/PhComposer::ThermalBridges|PhComposer::Zones/, text)
  end
end
