# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/examples/climate/site_walkthrough"

class ClimateSiteWalkthroughTest < PhComposerTestCase
  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?("ph_composer.climate")
  end

  def test_the_walkthrough_sets_the_site_and_design_temperatures_through_public_calls_and_undo_steps_back
    model = Sketchup.active_model
    operations = model.operations.length

    result = ClimateSiteWalkthrough.run

    assert result.fetch("passed"), result.inspect
    assert_equal ["Set Site Location"] + (["Change Design Temperature"] * 3),
                 model.operations.drop(operations).map(&:first)
    model.undo
    assert_nil ClimateSiteWalkthrough.state.dig("design_temperatures", "design_temperature_source")
    3.times { model.undo }
    assert_equal "not_set", ClimateSiteWalkthrough.state.dig("site", "state")
    4.times { model.redo }
    assert ClimateSiteWalkthrough.verify.fetch("passed")
    text = File.read(File.expand_path("../tools/examples/climate/site_walkthrough.rb", __dir__))
    refute_match(/PhComposer::Climate/, text)
  end
end
