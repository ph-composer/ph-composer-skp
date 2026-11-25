# frozen_string_literal: true

require_relative "test_helper"

# Ducting sits above Mechanical: it requires Mechanical, whose Ventilator its ducts export into, and Zones, and
# installs last. Nothing of Mechanical's or Piping's, in Ruby or in their panels, names Ducting, and Ducting names
# nothing of Piping's: the two edge features share only what sits below them (context/EXTENSIBILITY.md,
# "Organization and dependencies").
class DuctingDependencyTest < PhComposerTestCase
  ROOT = File.join(SOURCE_ROOT, "ph_composer")
  BELOW = %w[mechanical piping].flat_map do |name|
    [File.join(ROOT, "features", name), File.join(ROOT, "html", "features", name)]
  end.freeze
  DUCTING = [File.join(ROOT, "features", "ducting"), File.join(ROOT, "html", "features", "ducting")].freeze
  # A feature's id, Ruby module or folders.
  NAMES_DUCTING = %r{ph_composer\.ducting\b|\bDucting(::|\.)|\bducting/|features/ducting\b|\bducting\.[a-z_]+}
  NAMES_PIPING = %r{ph_composer\.piping\b|\bPiping(::|\.)|\bpiping/}

  def test_nothing_under_mechanical_or_piping_names_ducting
    ["ph_composer.ducting.duct_types", "Ducting::DuctType", "require_relative \"../ducting/install\"",
     "html/features/ducting/section.js", "ducting.insulation_conductivity_missing",
     "features/ducting"].each { |text| assert_match NAMES_DUCTING, text }
    ["(Ventilation's Ventilators, later Ducting).", "ph_composer.ductingx", "supply_ducting.length",
     "ERV ducting. Then"]
      .each { |text| refute_match NAMES_DUCTING, text }
    assert_empty offenders(BELOW, NAMES_DUCTING)
  end

  def test_nothing_under_ducting_names_piping
    assert_empty offenders(DUCTING, NAMES_PIPING)
  end

  def test_ducting_requires_mechanical_and_zones_and_installs_last
    assert_equal %w[ph_composer.mechanical ph_composer.zones],
                 PhComposer::Registry.current.features.fetch("ph_composer.ducting").requires
    assert_equal PhComposer::Ducting, PhComposer::FEATURES.last
  end

  private

  def offenders(folders, pattern)
    files = folders.flat_map { |folder| Dir[File.join(folder, "**", "*.{rb,js,css}")] }
    refute_empty files
    found = files.select { |path| File.read(path, :encoding => "UTF-8").match?(pattern) }
    found.map { |path| path.delete_prefix("#{ROOT}/") }
  end
end
