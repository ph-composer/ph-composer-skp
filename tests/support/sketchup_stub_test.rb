# frozen_string_literal: true

require_relative "../test_helper"

class SketchupStubTest < PhComposerTestCase
  def test_definition_instances_includes_unused_storage_and_deduplicates_shared_parents
    model = Sketchup::Model.new
    Sketchup.active_model = model
    definition = model.definitions.add("Synthetic Window")
    direct = model.entities.add_instance(definition, Geom::Transformation.new)
    unused = model.definitions.add("Unused furniture")
    nested = unused.entities.add_instance(definition, Geom::Transformation.new)
    shared = Sketchup::Entities.new
    grouped = shared.add_instance(definition, Geom::Transformation.new)
    model.entities << Sketchup::Group.new(1100, shared)
    model.entities << Sketchup::Group.new(1101, shared)
    assert_equal [direct, nested, grouped].sort_by(&:persistent_id), definition.instances.sort_by(&:persistent_id)
    unused.entities.erase_entities(nested)
    assert_equal [direct, grouped].sort_by(&:persistent_id), definition.instances.sort_by(&:persistent_id)
    replacement = model.definitions.add("Replacement")
    direct.definition = replacement
    assert_equal [grouped], definition.instances
    assert_equal [direct], replacement.instances
  end

  def test_commit_records_operation_and_notifies_observers
    model = Sketchup::Model.new
    observer = transaction_observer
    model.add_observer(observer)

    assert model.start_operation("Edit", true)
    model.set_attribute("test", "value", "changed")
    assert model.commit_operation

    assert_equal [["Edit", true, :committed]], model.operations
    assert_equal [:commit], observer.events
  end

  def test_abort_restores_attributes
    model = Sketchup::Model.new({ "test" => { "value" => "before" } })

    model.start_operation("Edit")
    model.set_attribute("test", "value", "after")
    assert model.abort_operation

    assert_equal "before", model.get_attribute("test", "value")
    assert_equal [["Edit", false, :aborted]], model.operations
  end

  def test_abort_reports_an_undo_as_the_host_does
    model = Sketchup::Model.new
    observer = transaction_observer
    model.add_observer(observer)

    model.start_operation("Edit")
    model.abort_operation

    assert_equal [:undo], observer.events
  end

  def test_abort_restores_entities
    face = Sketchup::Face.new(1)
    model = Sketchup::Model.new(:entities => Sketchup::Entities.new([face]))

    model.start_operation("Edit")
    model.entities << Sketchup::Face.new(2)
    model.abort_operation

    assert_equal [1], model.entities.map(&:persistent_id)
  end

  def test_undo_restores_the_pre_operation_state_and_notifies_observers
    model = Sketchup::Model.new({ "test" => { "value" => "before" } })
    observer = transaction_observer
    model.add_observer(observer)
    model.start_operation("Edit")
    model.set_attribute("test", "value", "after")
    model.commit_operation

    assert model.undo

    assert_equal "before", model.get_attribute("test", "value")
    assert_equal [:commit, :undo], observer.events
  end

  def test_transparent_operations_add_no_undo_step
    model = Sketchup::Model.new({ "test" => { "value" => "before" } })
    model.start_operation("Primary")
    model.set_attribute("test", "value", "primary")
    model.commit_operation
    model.start_operation("Transparent", false, false, true)
    model.set_attribute("test", "value", "transparent")
    model.commit_operation

    assert model.undo
    assert_equal "before", model.get_attribute("test", "value")
    refute model.undo
  end

  def test_redo_restores_an_undone_operation
    model = Sketchup::Model.new({ "test" => { "value" => "before" } })
    model.start_operation("Edit")
    model.set_attribute("test", "value", "after")
    model.commit_operation
    model.undo

    assert model.redo
    assert_equal "after", model.get_attribute("test", "value")
  end

  def test_timers_run_in_order_and_drain_timers_scheduled_during_the_run
    events = []
    UI.start_timer(0.0, false) do
      events << :first
      UI.start_timer(0.0, false) { events << :third }
    end
    UI.start_timer(0.0, false) { events << :second }

    assert_equal 3, UI.run_timers
    assert_equal %i[first second third], events
    assert_equal 0, UI.timer_count
  end

  def test_stop_timer_removes_a_queued_timer
    called = false
    timer = UI.start_timer(0.0, false) { called = true }

    assert UI.stop_timer(timer)
    assert_equal 0, UI.run_timers
    refute called
  end

  def test_add_group_reparents_its_members
    first = Sketchup::Face.new(1)
    second = Sketchup::Face.new(2)
    entities = Sketchup::Entities.new([first, second])

    group = entities.add_group([first, second])

    assert_equal [group], entities.to_a
    assert_equal [first, second], group.entities.to_a
    assert_same group.entities, first.parent_entities
    assert_same group.entities, second.parent_entities
  end

  def test_explode_restores_members_to_the_parent
    face = Sketchup::Face.new(1)
    entities = Sketchup::Entities.new([face])
    group = entities.add_group([face])

    assert_equal [face], group.explode
    assert_equal [face], entities.to_a
    assert_same entities, face.parent_entities
  end

  def test_selection_add_notifies_observers
    selection = Sketchup::Selection.new
    observer = selection_observer
    face = Sketchup::Face.new(1)
    selection.add_observer(observer)

    selection.add(face)

    assert_equal [[:add, face]], observer.events
  end

  def test_selection_remove_notifies_observers
    selection = Sketchup::Selection.new
    observer = selection_observer
    face = Sketchup::Face.new(1)
    selection.add(face)
    selection.add_observer(observer)

    selection.remove(face)

    assert_equal [[:remove, face]], observer.events
  end

  def test_selection_clear_notifies_observers
    selection = Sketchup::Selection.new
    observer = selection_observer
    selection.add(Sketchup::Face.new(1))
    selection.add_observer(observer)

    selection.clear

    assert_equal [:clear], observer.events
  end

  def test_selection_bulk_change_notifies_observers
    selection = Sketchup::Selection.new
    observer = selection_observer
    selection.add_observer(observer)

    selection.add([Sketchup::Face.new(1), Sketchup::Face.new(2)])

    assert_equal :bulk, observer.events.last
  end

  def test_selection_add_ignores_entities_outside_the_active_entities
    model = Sketchup::Model.new
    open_group = model.entities.add_group
    outside = model.entities.add_group
    inside = open_group.entities.add_group
    model.active_path = [open_group]

    model.selection.add([outside, inside])

    assert_equal [inside], model.selection.to_a
  end

  def test_active_entities_follow_the_active_path
    model = Sketchup::Model.new
    group = model.entities.add_group

    model.active_path = [group]

    assert_same group.entities, model.active_entities
  end

  def test_erase_refuses_a_group_on_the_active_path
    model = Sketchup::Model.new
    Sketchup.active_model = model
    outer = model.entities.add_group
    inner = outer.entities.add_group
    model.active_path = [outer, inner]

    assert_raises(ArgumentError) { outer.entities.erase_entities(inner) }
    model.active_path = [outer]
    assert outer.entities.erase_entities(inner)
  end

  def test_root_scan_count_increments_for_each_root_traversal
    entities = Sketchup::Entities.new([Sketchup::Face.new(1), Sketchup::Face.new(2)])
    entities.root = true

    entities[0]
    entities[1]
    entities[0]

    assert_equal 2, entities.scan_count
  end

  class SaveRecorder
    attr_reader :log

    def initialize; @log = []; end
    def onPreSaveModel(model); @log << [:pre, model.active_path]; end
    def onSaveModel(model); @log << [:post, model.modified?]; end
  end

  class PathChangingSaveObserver
    def onPreSaveModel(model); model.active_path = []; end
  end

  def test_save_reports_an_empty_path_to_pre_save_observers_and_restores_it
    observer = SaveRecorder.new
    group = Sketchup::Group.new(5)
    model = Sketchup::Model.new({}, :entities => Sketchup::Entities.new([group]))
    model.add_observer(observer)
    model.active_path = [group]

    Dir.mktmpdir("ph-composer-stub-save") { |directory| model.save(File.join(directory, "m.skp")) }

    assert_equal [[:pre, nil], [:post, true]], observer.log, "a save inside a context leaves the Model modified"
    assert_equal [group], model.active_path
  end

  def test_save_leaves_the_root_when_a_group_on_the_path_is_locked
    observer = SaveRecorder.new
    group = Sketchup::Group.new(5)
    model = Sketchup::Model.new({}, :entities => Sketchup::Entities.new([group]))
    model.add_observer(observer)
    model.active_path = [group]
    group.locked = true

    Dir.mktmpdir("ph-composer-stub-save") { |directory| model.save(File.join(directory, "m.skp")) }

    assert_equal [[:pre, nil], [:post, false]], observer.log
    assert_nil model.active_path
  end

  def test_save_refuses_a_pre_save_observer_that_changes_the_active_path
    observer = PathChangingSaveObserver.new
    model = Sketchup::Model.new({}, :entities => Sketchup::Entities.new([Sketchup::Group.new(5)]))
    model.add_observer(observer)

    Dir.mktmpdir("ph-composer-stub-save") do |directory|
      error = assert_raises(RuntimeError) { model.save(File.join(directory, "m.skp")) }
      assert_match(/onPreSaveModel/, error.message)
    end
  end

  private

  def transaction_observer
    Class.new(Sketchup::ModelObserver) do
      attr_reader :events

      def initialize
        @events = []
      end

      def onTransactionCommit(_model); @events << :commit; end
      def onTransactionUndo(_model); @events << :undo; end
      def onTransactionRedo(_model); @events << :redo; end
    end.new
  end

  def selection_observer
    Class.new(Sketchup::SelectionObserver) do
      attr_reader :events

      def initialize
        @events = []
      end

      def onSelectionAdded(_selection, entity); @events << [:add, entity]; end
      def onSelectionRemoved(_selection, entity); @events << [:remove, entity]; end
      def onSelectionCleared(_selection); @events << :clear; end
      def onSelectionBulkChange(_selection); @events << :bulk; end
    end.new
  end
end
