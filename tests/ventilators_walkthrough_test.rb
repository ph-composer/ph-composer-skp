# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/examples/authoring/ventilators_walkthrough"

class VentilatorsWalkthroughTest < PhComposerTestCase
  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?("ph_composer.mechanical")
  end

  def test_the_walkthrough_authors_ventilators_through_public_calls_and_undo_steps_back_through_it
    result = VentilatorsWalkthrough.run
    assert result.fetch("passed"), result.inspect
    assert_equal 5, result.fetch("steps").count { |step| %w[create update duplicate delete].include?(step["step"]) }
    model = Sketchup.active_model
    model.undo
    restored = VentilatorsWalkthrough.state
    assert_equal VentilatorsWalkthrough::EXPECTED.merge("ERV-2" => [0.75, 0.0, 0.55, 1, 0.2, "manual", {}]), restored
    4.times { model.undo }
    assert_empty VentilatorsWalkthrough.state
    5.times { model.redo }
    assert VentilatorsWalkthrough.verify.fetch("passed")
    text = File.read(File.expand_path("../tools/examples/authoring/ventilators_walkthrough.rb", __dir__))
    refute_match(/PhComposer::Mechanical|PhComposer::Zones/, text)
  end
end
