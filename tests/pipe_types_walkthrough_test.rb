# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/examples/authoring/pipe_types_walkthrough"

class PipeTypesWalkthroughTest < PhComposerTestCase
  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?("ph_composer.piping")
  end

  def test_the_walkthrough_authors_pipe_types_through_public_calls_and_undo_steps_back_through_it
    result = PipeTypesWalkthrough.run
    assert result.fetch("passed"), result.inspect
    ids = PipeTypesWalkthrough.ids
    assert_equal ["PT-1", "PT-1 (copy)"], ids.keys.sort
    assert_equal 5, result.fetch("steps").count { |step| %w[create update duplicate delete].include?(step["step"]) }
    model = Sketchup.active_model
    model.undo
    pt2 = PipeTypesWalkthrough::PT_1.merge("name" => "PT-2", "material" => 2, "diameter_mm" => 12.7,
                                           "insulation_thickness_mm" => 0.0, "insulation_conductivity_w_mk" => 0.04,
                                           "assigned_color" => "#FF7F0E")
    assert_equal PipeTypesWalkthrough::EXPECTED + [[pt2, {}]], PipeTypesWalkthrough.state
    4.times { model.undo }
    assert_empty PipeTypesWalkthrough.state
    5.times { model.redo }
    assert PipeTypesWalkthrough.verify(ids).fetch("passed"), "Redo restores each type under its id"
    refute PipeTypesWalkthrough.verify(ids.merge("PT-1" => "ppt_ZZZZZZZZZZZZ")).fetch("passed"),
           "a type back under another id fails the read-back"
    kind = "ph_composer.piping.pipe_type"
    engine = PhComposer::Records::Engine.new(model, PhComposer::Registry.current.catalog)
    store = engine.kind(kind).store
    copy = engine.find(kind, engine.ids(kind).min)
    store.write(model, copy.merge("insulation_quality" => 3))
    refute PipeTypesWalkthrough.verify.fetch("passed"), "a changed stored value fails the read-back"
    store.write(model, copy)
    store.write(model, copy.merge("id" => "ppt_ZZZZZZZZZZZZ"))
    refute PipeTypesWalkthrough.verify.fetch("passed"), "an extra record fails the read-back, even an equal one"
    store.write(model, copy.merge("water_temp_c" => 60))
    assert_raises(RuntimeError) { PipeTypesWalkthrough.verify }
    text = File.read(File.expand_path("../tools/examples/authoring/pipe_types_walkthrough.rb", __dir__))
    refute_match(/PhComposer::Piping|PhComposer::Mechanical/, text)
  end
end
