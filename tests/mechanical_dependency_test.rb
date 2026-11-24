# frozen_string_literal: true

require_relative "test_helper"

# Mechanical's equipment families are definitions that read and validate on their own: nothing in a family folder
# names Zones, Spaces, Programs, the Zone record, the serves/ folder or SketchUp. Nothing in another feature's
# folder names Mechanical (context/EXTENSIBILITY.md, "Organization and dependencies").
class MechanicalDependencyTest < PhComposerTestCase
  FEATURES = File.join(SOURCE_ROOT, "ph_composer", "features")
  MECHANICAL = File.join(FEATURES, "mechanical")
  # The feature's own layer-3 and registration folders; every other folder is an equipment family.
  NOT_FAMILIES = %w[serves declarations].freeze
  UPWARD = %r{\b(Zones|Spaces|Programs|Serves)\b|ph_composer\.(zones|spaces|programs)\b|(zones|spaces|programs)/|
              REFERENCE_KIND|ZONE_KIND|zone_id|serves/|Sketchup::}x
  # Mechanical's module, ids or folder, from anywhere else.
  DOWNWARD = %r{\bMechanical\b|ph_composer\.mechanical|mechanical/}

  def offenders(paths, pattern)
    paths.select { |path| File.read(path, :encoding => "UTF-8").match?(pattern) }
         .map { |path| path.delete_prefix("#{FEATURES}/") }
  end

  def test_no_family_folder_names_zones_spaces_programs_serves_or_sketchup
    families = Dir[File.join(MECHANICAL, "*")].select { |path| File.directory?(path) }
                                              .reject { |path| NOT_FAMILIES.include?(File.basename(path)) }
    files = families.flat_map { |folder| Dir[File.join(folder, "**", "*.rb")] }
    assert_includes families.map { |path| File.basename(path) }, "ventilators"
    refute_empty files
    controls = ["Zones::REFERENCE_KIND", "Zones.install(registry)", "ph_composer.spaces.all", "\"zone_id\"",
                "require_relative \"../serves/payload\"", "require_relative \"../../zones/install\"",
                "Sketchup::Group"]
    controls.each { |text| assert_match UPWARD, text }
    assert_empty offenders(files, UPWARD)
  end

  def test_no_other_feature_names_mechanical
    others = Dir[File.join(FEATURES, "*")].reject { |path| path == MECHANICAL }
                                          .flat_map { |folder| Dir[File.join(folder, "**", "*.rb")] }
    refute_empty others
    ["Mechanical::VENTILATOR_KIND", "require_relative \"../mechanical/install\"", "ph_composer.mechanical.ventilators"]
      .each { |text| assert_match DOWNWARD, text }
    assert_empty offenders(others, DOWNWARD)
  end

  # Programs since the airflow balance counts a By Program Zone's flow, Climate since the heat pump blend reads it.
  def test_mechanical_requires_zones_spaces_programs_and_climate
    assert_equal %w[ph_composer.zones ph_composer.spaces ph_composer.programs ph_composer.climate],
                 PhComposer::Registry.current.features.fetch("ph_composer.mechanical").requires
  end
end
