# frozen_string_literal: true

require_relative "tokens"
require_relative "dialog"

module PhComposer
  # Local agent access (context/AGENT_INTERFACE.md, "User-controlled local access"), registered as a
  # foundation capability. It declares one native menu item, which opens the Agent Access dialog, and
  # no public operation: tokens are managed only by the user in that dialog.
  module AgentAccess
    FEATURE_ID = "ph_composer.agent_access"
    MENU = "Agent Access"
    # What the dialog can be refused. No public operation raises these; they are declared so every code
    # the extension raises is described in one catalog.
    CODES = {
      "agent_access.limit" => "This machine already has the most live agent tokens it keeps; revoke one first.",
      "agent_access.token_unknown" => "No agent token has that id on this machine.",
      "agent_access.store_unreadable" => "The stored agent tokens cannot be read; reset them before issuing another.",
      "agent_access.store_unavailable" => "The agent tokens could not be read or saved on this machine.",
      "agent_access.model_unsaved" => "A token can be bound only to a Model that has been saved to a file.",
      "agent_access.model_changed" => "The open Model changed since the form showed it; nothing was issued.",
      "agent_access.connection_unavailable" => "The token could not be saved for the client in its owner-only file.",
      "agent_access.not_listening" => "PH-Composer is not listening, so no client was set up."
    }.freeze

    module_function

    def install(registry)
      feature = registry.feature(FEATURE_ID, :contract_version => Declarations::CONTRACT_VERSION)
      CODES.each { |code, description| feature.code(code, :description => description) }
      # Kept out of the viewport's right-click menu: managing tokens has nothing to do with what is under
      # the pointer.
      # The path each session's Model was last known by, so a save can tell a Save As from a save in place.
      %i[session_created model_opened].each do |event|
        feature.on_host_event(event) { |session| saved_path(session).path = session.model.path.to_s }
      end
      feature.on_host_event(:post_save) { |session| saved(session) }
      # The form shows which Model "This Model only" binds, so it follows activation and Save As.
      %i[model_activated post_save].each { |event| feature.on_host_event(event) { |_session| Dialog.refresh } }
      feature.menu_item("#{FEATURE_ID}.open", :label => "Agent Access…", :menu => MENU,
                                              :available => ->(_read) { false }) { |_session| Dialog.show }
    end

    # The path the session's Model has now, and the earlier paths whose tokens a failed save left behind.
    SavedPath = Struct.new(:path, :unmoved)

    def saved_path(session)
      session.feature_state("#{FEATURE_ID}.saved_path") { SavedPath.new(session.model.path.to_s, []) }
    end

    # After a save: a Model saved under a new name (Save As, how a stage copy is made) keeps the tokens
    # bound to it. An autosave or a save in place keeps the path and writes nothing. It runs inside
    # SketchUp's save, so a failure is logged, never raised, and the paths it left behind are moved by
    # the next save, with any token issued since at the path the Model then had.
    def saved(session)
      held = saved_path(session)
      to = session.model.path.to_s
      held.unmoved |= [held.path] unless held.path.empty? || held.path == to
      held.unmoved -= [to]
      held.path = to
      return if held.unmoved.empty?

      Tokens.follow(held.unmoved, to)
      held.unmoved = []
    rescue StandardError => error
      fields = { "severity" => "warning", "error_class" => error.class.name }
      fields["code"] = error.code if error.is_a?(CodedError)
      Diagnostics.log("agent_access_follow_failed", fields)
    end

    # Called after every token store write, a revoke or a reset alike: the caller handles of every token
    # that is no longer live end at once, its waiting calls are answered as revoked, a client's saved copy
    # of it is deleted, the listener takes the new snapshot (stopping after the last token), and the dialog
    # shows the new list.
    def tokens_changed
      snapshot = Tokens.snapshot
      Connections.prune(snapshot.keys)
      live = snapshot.values.map { |row| row.fetch("id") }
      ended = (handles.keys - live).to_h { |token_id| [token_id, revoke_callers(token_id)] }
      refused = Listener.refresh || {}
      (ended.keys | refused.keys).each do |token_id|
        summary = ended.fetch(token_id) { acknowledgment(token_id).merge("calls_refused" => 0) }
        acknowledgments[token_id] = summary.merge("calls_refused" => refused.fetch(token_id, 0))
      end
      Dialog.refresh
    end

    # What ending a token stopped and what it had already done, for the dialog's acknowledgment.
    def acknowledgment(token_id)
      acknowledgments.fetch(token_id) do
        { "exports_completed" => 0, "exports_stopped" => 0, "changes_committed" => 0, "calls_refused" => 0 }
      end
    end

    def acknowledgments
      @acknowledgments ||= {}
    end

    # A change a token's invoke committed, counted once per session and sequence however often it replays.
    def committed(token_id, session_id, sequence)
      (changes[token_id] ||= {})[[session_id, sequence]] = true
    end

    def changes
      @changes ||= {}
    end

    # Each token's caller handle and sequences per Model session, kept here rather than in the Executor so
    # they outlive a listener restart (Executor#binding_for).
    def bindings
      @bindings ||= {}
    end

    # Forgets the bindings of every token not in `live_ids`.
    def drop_bindings(live_ids)
      bindings.delete_if { |(token_id, _session), _binding| !live_ids.include?(token_id) }
    end

    def reset_bindings
      @bindings = {}
    end

    # The listener's state for the dialog.
    def server_status
      Listener.status
    end

    # Records the caller handle a token acts through on a session, so a revoke can end it there too.
    # Records of closed sessions are dropped on the way, so a long-lived token holds no closed Model.
    def bound(token_id, session, handle)
      held = (handles[token_id] ||= [])
      held.select! { |(open, _handle)| open.valid? }
      held << [session, handle]
    end

    # Ends every caller handle the token held and says what its exports had done: completed ones keep
    # their files; one still running is stopped at its commit check and writes nothing. A call already
    # running finishes whole; the next one is refused as revoked.
    def revoke_callers(token_id)
      summary = { "exports_completed" => 0, "exports_stopped" => 0,
                  "changes_committed" => (changes.delete(token_id) || {}).length }
      Array(handles.delete(token_id)).each do |session, handle|
        next unless session.valid?

        tasks = Export::Tasks.for(session).owned_by(handle)
        summary["exports_completed"] += tasks.count { |task| task.snapshot.dig("outcome", "code") == "export.complete" }
        summary["exports_stopped"] += tasks.count { |task| !task.terminal? }
        session.callers.revoke(handle)
      end
      summary
    end

    def handles
      @handles ||= {}
    end

    # Forgets every record of a closed session, whichever token held it.
    def prune_handles
      handles.each_value { |held| held.select! { |(session, _handle)| session.valid? } }
    end

    def reset_handles
      @handles = {}
      @acknowledgments = {}
      @changes = {}
    end
  end

  on_reset("agent_access.dialog") { AgentAccess::Dialog.reset_for_test }
  on_reset("agent_access.listener") { AgentAccess::Listener.reset }
  on_reset("agent_access.bindings") { AgentAccess.reset_bindings }
  on_reset("agent_access.handles") { AgentAccess.reset_handles }
end
