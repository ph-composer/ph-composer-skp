# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/examples/programs/program_records_walkthrough"

# The Programs walkthrough (tools/examples/programs/program_records_walkthrough.rb) passes only through public calls
# with the panel closed, each of its writes is one Undo step, and its result survives Undo, Redo, save and reopen.
class ProgramRecordsWalkthroughTest < PhComposerTestCase
  W = ProgramRecordsWalkthrough

  def test_the_walkthrough_authors_each_kind_and_each_step_undoes
    model = Sketchup.active_model
    before = W.state
    operations = model.operations.length

    result = W.run

    assert result.fetch("passed"), result.inspect
    assert_equal W::UNDO_NAMES, model.operations.drop(operations).map(&:first)
    after = W.state
    W::UNDO_NAMES.length.times { model.undo }
    assert_equal before, W.state
    W::UNDO_NAMES.length.times { model.redo }
    assert_equal after, W.state
    path = File.join(Dir.tmpdir, "ph-composer-program-walkthrough.skp")
    model.save(path)
    Sketchup.open_file(path)
    assert W.verify.fetch("passed"), W.verify.inspect
    text = File.read(File.expand_path("../tools/examples/programs/program_records_walkthrough.rb", __dir__))
    refute_match(/PhComposer::Programs/, text, "the walkthrough uses only the public API")
  end
end
