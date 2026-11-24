# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/test_feature"

class ExportCollectionSlicesTest < PhComposerTestCase
  def test_a_slice_bounds_entities_and_resumes_without_duplicates
    model = Sketchup.active_model
    (1..205).each { |id| model.entities << Sketchup::Face.new(id) }
    cursor = PhComposer::Export::GeometrySnapshot::Cursor.new(model)

    cursor.advance(:limit => 100, :budget_seconds => 10)
    assert_equal 100, cursor.count
    refute cursor.done?
    cursor.advance(:limit => 100, :budget_seconds => 10)
    assert_equal 200, cursor.count
    cursor.advance(:limit => 100, :budget_seconds => 10)
    assert cursor.done?
    assert_equal (1..205).map { |id| [id] }, cursor.entries.map(&:path)
  end

  def test_incremental_collection_matches_the_existing_shared_contract
    model = Sketchup.active_model
    PhComposer::Registry.install([TestFeature])
    expected = PhComposer::Export::Collection.build(model, :run_id => "same-run")
    builder = PhComposer::Export::Collection::Builder.new(model, :run_id => "same-run")
    40.times { break if builder.advance }

    assert_equal expected.document, builder.extraction.document
    assert_equal expected.findings, builder.extraction.findings
  end

  def test_content_generation_counts_mutations_but_not_navigation_selection_or_save
    model = Sketchup.active_model
    session = PhComposer::Sessions.for(model)
    model.active_path = []
    model.selection.add(Sketchup::Face.new(999))
    session.host_event(:pre_save)
    session.host_event(:post_save)
    assert_equal 1, session.export_generation

    session.mutate do
      PhComposer::ModelOperation.perform(model, "Change") { model.set_attribute("test", "value", 1) }
      true
    end
    assert_equal 2, session.export_generation
    model.undo
    model.redo
    assert_equal 4, session.export_generation
    model.start_operation("External")
    model.set_attribute("test", "value", 2)
    model.commit_operation
    assert_equal 5, session.export_generation
  end
end
