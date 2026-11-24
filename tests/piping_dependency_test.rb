# frozen_string_literal: true

require_relative "test_helper"

# Piping sits above Mechanical: it requires Mechanical, whose Hot Water System its pipes export into, and Zones, and
# installs after them. Nothing of Mechanical's, in Ruby or in its panel, names Piping, so Mechanical keeps its own
# words for piping (its piping calculation method, the recirculation read from piping) and no more
# (context/EXTENSIBILITY.md, "Organization and dependencies").
class PipingDependencyTest < PhComposerTestCase
  ROOT = File.join(SOURCE_ROOT, "ph_composer")
  MECHANICAL = [File.join(ROOT, "features", "mechanical"), File.join(ROOT, "html", "features", "mechanical")].freeze
  # Piping's id, Ruby module or folders.
  NAMES_PIPING = %r{ph_composer\.piping\b|\bPiping(::|\.)|\bpiping/}

  def test_nothing_under_mechanical_names_piping
    files = MECHANICAL.flat_map { |folder| Dir[File.join(folder, "**", "*.{rb,js,css}")] }
    refute_empty files
    ["ph_composer.piping.pipe_types", "Piping::PipeType", "require_relative \"../piping/install\"",
     "html/features/piping/section.js"].each { |text| assert_match NAMES_PIPING, text }
    ["piping_calc_method", "from_piping", "ph_composer.pipingx"].each { |text| refute_match NAMES_PIPING, text }
    offenders = files.select { |path| File.read(path, :encoding => "UTF-8").match?(NAMES_PIPING) }
    assert_empty offenders.map { |path| path.delete_prefix("#{ROOT}/") }
  end

  def test_piping_requires_mechanical_and_zones_and_installs_last
    assert_equal %w[ph_composer.mechanical ph_composer.zones],
                 PhComposer::Registry.current.features.fetch("ph_composer.piping").requires
    assert_equal PhComposer::Piping, PhComposer::FEATURES.last
  end
end
