# frozen_string_literal: true

require_relative "test_helper"

# The development example and its walkthrough, run offline against the stub. The same script runs in
# a real host through the bridge for the phase's host evidence.
class ExampleFoundationTest < PhComposerTestCase
  def setup
    super
    load File.expand_path("../tools/examples/foundation/load.rb", __dir__)
  end

  def test_the_walkthrough_passes_every_step_with_the_panel_closed
    result = ExampleWalkthrough.run

    failed = result.fetch("steps").reject { |step| step.fetch("passed") }
    assert_empty failed
    assert_equal ["create", "read", "update", "read back", "stale second client", "retry", "duplicate", "summary"],
                 result.fetch("steps").map { |step| step.fetch("step") }
  end

  def test_an_outside_contribution_keeps_its_admitted_values_and_a_refused_one_publishes_nothing
    result = ExampleWalkthrough.registration

    assert_empty(result.fetch("steps").reject { |step| step.fetch("passed") })
    assert_equal 3, result.fetch("steps").length
  end

  def test_a_dependent_feature_composes_the_example_participant_into_one_undo_step
    result = ExampleWalkthrough.composition

    assert_empty(result.fetch("steps").reject { |step| step.fetch("passed") })
    engine = PhComposer::Records::Engine.new(Sketchup.active_model, PhComposer::Registry.current.catalog)
    assert_equal 4, engine.ids(ExampleFoundation::PART).length
    Sketchup.active_model.undo
    assert_equal 2, engine.ids(ExampleFoundation::PART).length, "one Undo removes both composed parts"
    described = PhComposer::API.describe(:name => "example.kit.add_pair")
    assert_equal ["example.foundation.add_part"], described.fetch("participants")
  end

  def test_the_example_needs_no_change_outside_its_own_files
    registry = PhComposer::Registry.current

    assert_equal ExampleFoundation::ID, registry.owner_of("example.foundation.update_parts")
    assert_equal [PhComposer::Assemblies, PhComposer::Zones, PhComposer::Windows, PhComposer::Spaces,
                  PhComposer::ThermalBridges],
                 PhComposer::FEATURES,
                 "the example does not alter the shipping feature list"
  end

  # The synthetic editor reaches the panel only through the development entry: the page runs it after the
  # kit starts and before the first snapshot, and the shipped page names no example file.
  def test_the_development_entry_hands_the_synthetic_editor_to_the_panel
    dialog = PhComposer::Panel.show
    dialog.fire("ph_composer_message", JSON.generate("type" => "panel.ready", "payload" => {}))

    editor = File.read(File.expand_path("../tools/examples/foundation/editor.js", __dir__))
    assert_equal editor, dialog.scripts.first
    assert_match(/panel\.snapshot/, dialog.scripts[1])
    assert_includes dialog.scripts[1], "example.foundation.parts"
    refute_match(/example/, File.read(PhComposer::Panel::PAGE))
  end

  def test_the_kit_hears_one_selection_change_once_however_often_the_example_loads
    before = ExampleKit.selection_events
    load File.expand_path("../tools/examples/foundation/load.rb", __dir__)
    PhComposer::Sessions.current.host_event(:selection_changed)
    assert_equal before + 1, ExampleKit.selection_events
  end

  def test_loading_the_example_twice_installs_it_once
    load File.expand_path("../tools/examples/foundation/load.rb", __dir__)

    assert_equal 1, PhComposer::Registry.current.features.keys.count(ExampleFoundation::ID)
  end
end
