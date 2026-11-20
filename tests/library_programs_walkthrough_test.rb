# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/examples/library/programs_walkthrough"

# The Program library walkthrough (tools/examples/library/programs_walkthrough.rb) passes through public calls with
# the panel closed: one Undo step copies a library Program with its Schedules as the Model's default, and Undo
# takes all of it back.
class LibraryProgramsWalkthroughTest < PhComposerTestCase
  W = LibraryProgramsWalkthrough
  FIXTURE = File.expand_path("../tools/examples/library/programs.json", __dir__)

  def test_the_walkthrough_copies_a_program_with_its_schedules_in_one_undo_step
    model = Sketchup.active_model
    operations = model.operations.length

    result = W.run(:file_path => FIXTURE)

    assert result.fetch("passed"), result.inspect
    assert_equal W::UNDO_NAMES, model.operations.drop(operations).map(&:first)
    model.undo
    assert_empty PhComposer::Programs::Program::KIND.store.ids(model)
    assert_empty PhComposer::Programs::Schedule::KIND.store.ids(model)
    text = File.read(File.expand_path("../tools/examples/library/programs_walkthrough.rb", __dir__))
    refute_match(/PhComposer::Programs/, text, "the walkthrough uses only the public API")
  end
end
