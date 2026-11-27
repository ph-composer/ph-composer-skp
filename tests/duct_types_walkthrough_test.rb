# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/examples/authoring/duct_types_walkthrough"

class DuctTypesWalkthroughTest < PhComposerTestCase
  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?("ph_composer.ducting")
  end

  def test_the_walkthrough_authors_duct_types_through_public_calls_and_undo_steps_back_through_it
    result = DuctTypesWalkthrough.run
    assert result.fetch("passed"), result.inspect
    ids = DuctTypesWalkthrough.ids
    assert_equal ["DT-2", "DT-2 (copy)"], ids.keys.sort
    assert_equal 5, result.fetch("steps").count { |step| %w[create update duplicate delete].include?(step["step"]) }
    model = Sketchup.active_model
    model.undo
    dt1 = { "name" => "DT-1", "notes" => "", "datasheet_links" => [], "source" => { "kind" => "manual" },
            "shape" => "round", "diameter_mm" => 160.0, "insulation_thickness_mm" => 25.4,
            "insulation_conductivity_w_mk" => 0.04, "insulation_reflective" => true, "assigned_color" => "#1F77B4" }
    assert_equal [[dt1, {}]] + DuctTypesWalkthrough::EXPECTED, DuctTypesWalkthrough.state
    model.undo
    model.undo
    round = DuctTypesWalkthrough::DT_2.reject { |key, _value| %w[width_mm height_mm].include?(key) }
                                      .merge("shape" => "round", "diameter_mm" => 160.0)
    assert_equal [[dt1, {}], [round, DuctTypesWalkthrough::USER_DATA]], DuctTypesWalkthrough.state,
                 "Undo of the shape change brings the diameter back"
    2.times { model.undo }
    assert_empty DuctTypesWalkthrough.state
    5.times { model.redo }
    assert DuctTypesWalkthrough.verify(ids).fetch("passed"), "Redo restores each type under its id"
    refute DuctTypesWalkthrough.verify(ids.merge("DT-2" => "dct_ZZZZZZZZZZZZ")).fetch("passed"),
           "a type back under another id fails the read-back"
    kind = "ph_composer.ducting.duct_type"
    engine = PhComposer::Records::Engine.new(model, PhComposer::Registry.current.catalog)
    store = engine.kind(kind).store
    copy = engine.find(kind, engine.ids(kind).min)
    store.write(model, copy.merge("insulation_reflective" => true))
    refute DuctTypesWalkthrough.verify.fetch("passed"), "a changed stored value fails the read-back"
    store.write(model, copy)
    store.write(model, copy.merge("id" => "dct_ZZZZZZZZZZZZ"))
    refute DuctTypesWalkthrough.verify.fetch("passed"), "an extra record fails the read-back, even an equal one"
    store.write(model, copy.merge("diameter_mm" => 160.0))
    assert_raises(RuntimeError) { DuctTypesWalkthrough.verify }
    text = File.read(File.expand_path("../tools/examples/authoring/duct_types_walkthrough.rb", __dir__))
    refute_match(/PhComposer::Ducting|PhComposer::Mechanical/, text)
  end
end
