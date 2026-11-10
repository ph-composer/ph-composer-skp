# frozen_string_literal: true

require_relative "test_helper"

class SessionsTest < PhComposerTestCase
  Sessions = PhComposer::Sessions

  def test_every_open_model_keeps_its_own_session_across_activation
    first = Sketchup.active_model
    second = Sketchup::Model.new
    first_session = Sessions.for(first)
    second_session = Sessions.for(second)

    notify_app(:onActivateModel, second)
    notify_app(:onActivateModel, first)

    refute_equal first_session.id, second_session.id
    assert_same first_session, Sessions.find(first_session.id)
    assert_same second_session, Sessions.find(second_session.id)
  end

  def test_a_closed_models_session_is_dropped_and_its_observers_removed
    model = Sketchup::Model.new
    session = Sessions.for(model)

    model.close

    assert_nil Sessions.find(session.id)
    refute_includes model.observers, session.observers.model
    refute session.valid?
  end

  def test_a_session_whose_observers_were_never_attached_still_detaches
    model = Sketchup::Model.new
    session = PhComposer::ModelSession.new(model)
    Sessions.send(:sessions)[model.object_id] = session

    assert Sessions.detach(model)
    refute session.valid?
  end

  # A closed Model's view raises when asked, as SketchUp's did on 26.1.188 (context/SKETCHUP_HOST_BEHAVIOR.md):
  # pruning it never raises, and its session still drops its deferred work.
  def test_pruning_a_closed_model_whose_view_raises_still_detaches_its_session
    model = Sketchup::Model.new
    session = Sessions.for(model)
    deferred = session.feature_state(:test) { PhComposer::DeferredWork.new { |_jobs| nil } }
    deferred.queue(:job, 1)
    model.define_singleton_method(:valid?) { false }
    model.define_singleton_method(:active_view) { raise TypeError, "reference to deleted Model" }

    assert_nil Sessions.find(session.id)
    refute session.valid?
    refute deferred.pending?
  end

  def test_installing_registers_the_observer_and_opening_the_active_model_creates_its_session
    created = []
    unsubscribe = Sessions.on_host_event(:session_created) { |session| created << session }
    Sessions.reset
    assert_equal [Sessions.for(Sketchup.active_model)], created
  ensure
    unsubscribe&.call
  end

  # The host can create a Model's session before its file has loaded, so opening it reports again.
  def test_opening_a_model_reports_model_opened_to_its_existing_session
    model = Sketchup.active_model
    session = Sessions.for(model)
    opened = []
    unsubscribe = Sessions.on_host_event(:model_opened) { |reported| opened << reported }
    notify_app(:onOpenModel, model)
    assert_equal [session], opened
  ensure
    unsubscribe&.call
  end

  def test_reopening_a_file_creates_a_new_session_identity
    model = Sketchup.active_model
    model.save("/tmp/ph-composer-sessions.skp")
    before = Sessions.for(model).id

    Sketchup.open_file("/tmp/ph-composer-sessions.skp")

    refute_equal before, Sessions.for(Sketchup.active_model).id
  end

  def test_the_revision_starts_at_one_and_advances_on_external_commits_undo_redo_and_path_changes
    model = Sketchup.active_model
    session = Sessions.for(model)
    assert_equal 1, session.revision

    model.start_operation("External edit")
    model.set_attribute("test", "value", 1)
    model.commit_operation
    assert_equal 2, session.revision

    model.undo
    model.redo
    model.active_path = []
    assert_equal 5, session.revision
  end

  def test_selection_and_save_do_not_advance_the_revision
    model = Sketchup.active_model
    session = Sessions.for(model)

    model.selection.add(Sketchup::Face.new(1)) if model.selection.respond_to?(:add)
    model.save("/tmp/ph-composer-sessions-save.skp")

    assert_equal 1, session.revision
  end

  def test_an_own_mutation_advances_the_revision_once_whenever_its_commit_callback_arrives
    model = Sketchup.active_model
    session = Sessions.for(model)

    session.mutate do
      PhComposer::ModelOperation.perform(model, "Own edit") { model.set_attribute("test", "value", 1) }
      true
    end

    assert_equal 2, session.revision
  end

  # The same own commit with its callback delivered after the mutation returns, as SketchUp does
  # for user actions (context/SKETCHUP_HOST_BEHAVIOR.md): recognized, then a later commit counts.
  def test_an_own_commit_whose_callback_arrives_later_is_recognized_once
    model = Sketchup.active_model
    session = Sessions.for(model)
    observers = model.observers.dup
    observers.each { |observer| model.remove_observer(observer) }

    session.mutate do
      PhComposer::ModelOperation.perform(model, "Own edit") { model.set_attribute("test", "value", 1) }
      true
    end
    observers.each { |observer| model.add_observer(observer) }
    session.host_event(:transaction_committed)
    assert_equal 2, session.revision

    session.host_event(:transaction_committed)
    assert_equal 3, session.revision
  end

  # SketchUp reports the transactions of an operation on a Model it is not showing to the shown Model's
  # observers, naming the shown Model (context/SKETCHUP_HOST_BEHAVIOR.md). The session inside its own
  # operation claims them: the shown Model's revision stays, and the hidden Model's next edit still counts.
  def test_an_operation_on_a_model_not_shown_reported_to_the_shown_model_is_its_own
    shown = Sketchup.active_model
    hidden = Sketchup::Model.new
    shown_session = Sessions.for(shown)
    hidden_session = Sessions.for(hidden)
    revisions = [shown_session.revision, hidden_session.revision]

    hidden_session.mutate do
      shown_session.observers.model.onTransactionCommit(shown)
      true
    end
    hidden_session.observers.model.onTransactionCommit(hidden)

    assert_equal [revisions[0], revisions[1] + 2], [shown_session.revision, hidden_session.revision]
  end

  # SketchUp 26.1.188 reports an aborted operation as an Undo (context/SKETCHUP_HOST_BEHAVIOR.md);
  # inside the session's own operation that is its abort and changes nothing.
  def test_the_undo_callback_for_an_own_abort_does_not_advance_the_revision
    model = Sketchup.active_model
    session = Sessions.for(model)

    assert_raises(IOError) do
      session.mutate do
        PhComposer::ModelOperation.perform(model, "Own edit") { raise IOError, "failed" }
      end
    end

    assert_equal 1, session.revision
  end

  def test_a_commit_followed_by_an_exception_still_advances_the_revision
    model = Sketchup.active_model
    session = Sessions.for(model)

    assert_raises(RuntimeError) do
      session.mutate do
        PhComposer::ModelOperation.perform(model, "Own edit") { model.set_attribute("test", "value", 1) }
        raise "after the commit"
      end
    end

    assert_equal 2, session.revision
  end

  def test_a_mutation_that_commits_nothing_leaves_the_revision
    session = Sessions.for(Sketchup.active_model)

    session.mutate { false }

    assert_equal 1, session.revision
  end

  def test_a_session_is_busy_for_a_whole_change_or_while_a_feature_state_has_pending_work
    session = Sessions.for(Sketchup.active_model)
    assert_nil session.busy_reason

    during = nil
    session.exclusive { during = session.busy_reason }
    assert_nil session.busy_reason
    assert_match(/still running/, during)

    work = Struct.new(:pending?).new(true)
    session.feature_state(:sessions_test) { work }
    assert_match(/deferred work/, session.busy_reason)
  end

  private

  def notify_app(callback, model)
    Sketchup.instance_variable_get(:@observers).each do |observer|
      observer.public_send(callback, model) if observer.respond_to?(callback)
    end
  end
end
