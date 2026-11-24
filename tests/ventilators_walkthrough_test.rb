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
    erv2 = VentilatorsWalkthrough::ERV_1.merge("name" => "ERV-2", "quantity" => 1, "sensible_heat_recovery" => 0.75,
                                               "latent_heat_recovery" => 0.0, "electric_efficiency_wh_m3" => 0.55,
                                               "subsoil_heat_exchange_efficiency" => 0.2)
    assert_equal VentilatorsWalkthrough::EXPECTED + [[erv2, {}]], restored
    4.times { model.undo }
    assert_empty VentilatorsWalkthrough.state
    5.times { model.redo }
    assert VentilatorsWalkthrough.verify.fetch("passed")
    kind = "ph_composer.mechanical.ventilator"
    engine = PhComposer::Records::Engine.new(model, PhComposer::Registry.current.catalog)
    store = engine.kind(kind).store
    copy = engine.find(kind, engine.ids(kind).min)
    store.write(model, copy.merge("temperature_below_defrost_used_c" => -18.0))
    refute VentilatorsWalkthrough.verify.fetch("passed"), "a changed stored value fails the read-back"
    store.write(model, copy)
    store.write(model, copy.merge("id" => "vnt_ZZZZZZZZZZZZ"))
    refute VentilatorsWalkthrough.verify.fetch("passed"), "an extra record fails the read-back, even an equal one"
    store.write(model, copy.merge("rated_flow_m3h" => 120))
    assert_raises(RuntimeError) { VentilatorsWalkthrough.verify }
    text = File.read(File.expand_path("../tools/examples/authoring/ventilators_walkthrough.rb", __dir__))
    refute_match(/PhComposer::Mechanical|PhComposer::Zones/, text)
  end
end
