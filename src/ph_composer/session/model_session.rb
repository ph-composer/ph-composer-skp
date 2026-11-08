# frozen_string_literal: true

require "securerandom"

module PhComposer
  # One open Model: its session identity, revision, callers, retained outcomes, refresh timer and
  # observers. What a feature keeps per Model lives in that feature's state object, reached through
  # `feature_state`, so a new feature adds no line here.
  #
  # The revision is one whole-Model counter (context/CONTRACTS.md, "Revisions, transactions and host
  # execution"). It advances on a committed mutation, Undo, Redo and an edit-path change, and never on
  # a read, a selection change or a save. The view generation is the second counter: it advances when
  # what the host shows changes without the Model changing, such as the selection, so a read of the
  # selection can tell a page of an older selection from the current one.
  class ModelSession
    attr_reader :model, :id, :revision, :view_generation, :export_generation, :refresh, :observers, :callers,
                :outcomes

    # Host events that change what the host shows and not the Model.
    VIEW_EVENTS = %i[selection_changed camera_changed].freeze

    def initialize(model)
      @model = model
      @id = SecureRandom.uuid.freeze
      @revision = 1
      @view_generation = 1
      @export_generation = 1
      @export_path = Array(model.active_path)
      @own_commits_pending = 0
      @exclusive = false
      @committing = false
      @refresh = CoalescedTimer.new
      @observers = Observers.new
      @feature_state = {}
      @callers = CallerRegistry.new
      @outcomes = OutcomeStore.new
    end

    # Built by the block on first use and kept for the life of the session.
    def feature_state(name)
      @feature_state[name] ||= yield
    end

    def valid?
      !@detached && (!@model.respond_to?(:valid?) || @model.valid?)
    end

    # The observers attached to this session's Model, its selection and its tags, kept so detaching removes
    # exactly those.
    Observers = Struct.new(:model, :selection, :layers, :view, :rendering, keyword_init: true)

    def add_observers(observers)
      @observers = observers
    end

    # Why an authoritative read or write cannot run now, or nil when it can. A feature state object
    # with deferred Model work answers `pending?`; the session refuses until that work settles.
    def busy_reason
      return "Another change to this Model is still running." if @exclusive

      deferred = @feature_state.each_value.any? { |state| state.respond_to?(:pending?) && state.pending? }
      deferred ? "This Model has deferred work that has not finished." : nil
    end

    # Runs one change request from its first read to its recorded outcome. While it runs the session
    # is busy, so no other change can start, even one a handler starts itself. The dispatcher checks
    # `busy_reason` before calling this.
    def exclusive
      @exclusive = true
      yield
    ensure
      @exclusive = false
    end

    # Runs the block as the session's one native operation; the block answers whether it committed.
    # The revision advances once for it here. SketchUp may deliver the commit callback inside the block
    # (measured on 26.1.188) or after it returns, so the callback is recognized as ours either way.
    # SketchUp 26.1.188 reports an aborted operation as `onTransactionUndo`; inside the block that is
    # our own abort and changes nothing. A commit seen before an exception still advances the revision.
    def mutate
      @committing = true
      @commits_seen = 0
      committed = false
      committed = yield
    ensure
      @committing = false
      if committed || @commits_seen.positive?
        @revision += 1
        @export_generation += 1
        @own_commits_pending += 1 if @commits_seen.zero?
      end
    end

    # True inside #mutate: an extension operation is open on the Model, and work done now joins it.
    def mutating?
      @committing
    end

    # Completes deferred Model work before something reads the Model as a whole.
    def settle
      @feature_state.each_value { |state| state.settle if state.respond_to?(:settle) }
    end

    def host_event(kind, *arguments)
      previous = @revision
      path = Array(model.active_path)
      # SketchUp 26.1 emits a commit for the new edit path immediately before its path callback.
      # It commits preceding content changes separately while the old path is still active.
      navigation_commit = kind == :transaction_committed && path != @export_path
      advance_revision_for(kind)
      @view_generation += 1 if VIEW_EVENTS.include?(kind)
      if %i[transaction_committed transaction_undone transaction_redone].include?(kind) &&
         @revision != previous && !navigation_commit
        @export_generation += 1
      end
      @export_path = path if kind == :transaction_committed || kind == :active_path_changed
      ContainerWatch.for(self).host_event(kind) unless @detached
      Sessions.notify_host_event(self, kind, *arguments)
    end

    def changed(source, detail = nil)
      Sessions.notify_change(self, source, detail)
      request_refresh
    end

    def notice(message, tone: :info)
      Sessions.notify_notice(self, message, tone)
    end

    def request_refresh
      return if @detached

      @refresh.schedule { Sessions.notify_refresh(self) }
    end

    def detach
      @detached = true
      @feature_state.each_value { |state| state.detach if state.respond_to?(:detach) }
      @refresh.cancel
    end

    private

    def advance_revision_for(kind)
      case kind
      when :transaction_committed
        if @committing
          @commits_seen += 1
        elsif @own_commits_pending.positive?
          @own_commits_pending -= 1
        else
          @revision += 1
        end
      when :transaction_undone
        @revision += 1 unless @committing
      when :transaction_redone, :active_path_changed
        @revision += 1
      end
    end
  end
end
