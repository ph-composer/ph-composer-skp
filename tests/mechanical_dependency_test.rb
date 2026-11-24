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
  UPWARD = %r{Zones::|Spaces::|Programs::|ph_composer\.(zones|spaces|programs)\b|REFERENCE_KIND|ZONE_KIND|zone_id|
              serves/|Serves|Sketchup::}x

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
    ["Zones::REFERENCE_KIND", "ph_composer.spaces.all", "require_relative \"../serves/payload\"", "\"zone_id\"",
     "Sketchup::Group"].each { |text| assert_match UPWARD, text }
    assert_empty offenders(files, UPWARD)
  end

  def test_no_other_feature_names_mechanical
    others = Dir[File.join(FEATURES, "*")].reject { |path| path == MECHANICAL }
                                          .flat_map { |folder| Dir[File.join(folder, "**", "*.rb")] }
    refute_empty others
    assert_empty offenders(others, %r{Mechanical::|ph_composer\.mechanical|features/mechanical})
  end

  def test_mechanical_requires_zones_and_spaces
    assert_equal %w[ph_composer.zones ph_composer.spaces],
                 PhComposer::Registry.current.features.fetch("ph_composer.mechanical").requires
  end
end
