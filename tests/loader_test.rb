# frozen_string_literal: true

require_relative "test_helper"

class LoaderTest < PhComposerTestCase
  EXTENSION_ROOT = File.join(SOURCE_ROOT, "ph_composer")

  def test_extension_identity_is_registered_once
    before = Sketchup.registered_extensions.length
    load File.join(SOURCE_ROOT, "ph_composer.rb")

    assert_equal before, Sketchup.registered_extensions.length
    extension = PhComposer::EXTENSION
    assert_equal "PH-Composer", extension.name
    assert_equal PhComposer::VERSION, extension.version
    assert_equal File.join(EXTENSION_ROOT, "extension"), extension.path
  end

  # The walk is the foundation's only require list, so a Ruby file outside its directories would
  # never load. Feature files are the exception: the composition root requires each by name.
  def test_every_foundation_source_file_sits_in_a_walked_directory_and_is_loaded
    walked = PhComposer::FOUNDATION_DIRECTORIES
    sources = Dir[File.join(EXTENSION_ROOT, "**", "*.rb")].reject { |path| path.include?("/vendor/") }
    sources.delete(File.join(EXTENSION_ROOT, "extension.rb"))
    sources.reject! { |path| path.start_with?(File.join(EXTENSION_ROOT, "features") + "/") }

    sources.each do |path|
      assert_includes walked, path.delete_prefix(EXTENSION_ROOT + "/").split("/").first, path
      assert_includes $LOADED_FEATURES, File.realpath(path), path
    end
  end

  def test_the_shipping_composition_root_lists_the_authoring_features
    assert_equal [PhComposer::Assemblies, PhComposer::Zones, PhComposer::Windows, PhComposer::Spaces,
                  PhComposer::ThermalBridges],
                 PhComposer::FEATURES
    assert PhComposer::Registry.installed?("ph_composer.assemblies")
    assert PhComposer::Registry.installed?("ph_composer.zones")
    refute PhComposer::Registry.installed?("ph_composer.face_assignment")
  end

  # The Model already open at load gets its session only after every feature has subscribed, so a
  # `session_created` subscriber hears it: Spaces protects the Volumes a file holds unlocked.
  def test_the_active_models_session_is_created_after_the_features_compose
    root = File.read(File.join(EXTENSION_ROOT, "extension.rb"))
    composed = root.index(/^ +compose$/)
    opened = root.index("Sessions.open_active")
    assert composed && opened && opened > composed, "extension.rb must call Sessions.open_active after compose"
  end

  # One feature owns Zones, Faces and adjacency, so the published dependency graph is the whole truth
  # and no registered name survives from the retired face_assignment feature.
  def test_zones_owns_every_zone_face_and_adjacency_registration
    registry = PhComposer::Registry.current
    names = [registry.queries, registry.actions, registry.view_commands, registry.record_kinds,
             registry.reference_targets, registry.snapshot_sections, registry.export_contributors,
             registry.proposal_participants, registry.colour_modes, registry.menu_items].flat_map(&:keys)

    assert_equal ["ph_composer.assemblies"], registry.features.fetch("ph_composer.zones").requires
    assert_empty names.grep(/face_assignment/)
    assert_includes names, "ph_composer.zones.faces.classify"
    names.grep(/\Aph_composer\.zones\./).each do |name|
      assert_equal "ph_composer.zones", registry.owner_of(name), name
    end
  end

  def test_reset_for_test_clears_every_registered_state_once_per_name
    cleared = []
    PhComposer.on_reset(:loader_test) { cleared << :first }
    PhComposer.on_reset(:loader_test) { cleared << :reregistered }

    PhComposer.reset_for_test

    assert_equal [:reregistered], cleared
  end

  def test_reloading_the_composition_root_keeps_its_constants
    features = PhComposer::FEATURES
    load File.join(EXTENSION_ROOT, "extension.rb")

    assert_same features, PhComposer::FEATURES
  end

  # The record a failed load leaves when the logger itself could not load: the error's class and nothing else.
  def test_a_load_failure_before_the_logger_is_recorded_by_its_class_alone
    Dir.mktmpdir("phc-bootstrap-") do |directory|
      log = File.join(directory, "logs", "ph-composer.log")

      PhComposer.bootstrap_record(LoadError.new("cannot load /Users/example/Client Model"), log)

      record = JSON.parse(File.read(log))
      assert_equal %w[extension_load_failed LoadError failed], record.values_at("event", "error_class", "status")
      refute_includes File.read(log), "/Users/"
    end
  end
end
