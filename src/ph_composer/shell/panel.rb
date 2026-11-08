# frozen_string_literal: true

module PhComposer
  # The HtmlDialog panel: one client of the public interface (context/CONTRACTS.md, "Public
  # interface"), showing the active Model. It connects to each session it shows with its own caller
  # handle and gives its mutations their sequence numbers; the page's request ids only correlate a
  # result with the view that asked.
  #
  # The panel never owns Model behavior. Features render into it through snapshot sections, and a
  # programmatic caller never opens or raises it.
  module Panel
    WIDTH = 1280
    HEIGHT = 800
    MIN_WIDTH = 360
    MIN_HEIGHT = 520
    PAGE = File.join(ROOT, "html", "index.html")
    # Host events after which the shown Model's snapshot is stale. A new session matters where activation
    # is not reported (SketchUp documents onActivateModel for macOS only).
    REFRESH_EVENTS = %i[
      session_created transaction_committed transaction_undone transaction_redone active_path_changed
    ].freeze
    MAX_PENDING_NOTICES = 20
    # Once a request id has been forgotten, an id the host does not hold may have been received and run.
    FORGOTTEN = Outcome.build(
      "refused", "request.outcome_unavailable",
      "PH-Composer can no longer tell whether that change was applied. Check the Model before making it again.",
      "unknown", nil
    ).freeze
    SESSION_CHANGED = "The panel now shows a different Model."
    EXPORT_TYPES = %w[export.start export.preflight export.status export.cancel export.latest].freeze
    # Export startup failure is reported before a task or a Model operation begins.
    EXPORT_FAILED = Outcome.build(
      "failed", "operation.failed", "Export could not start. Nothing was written.", "none", nil
    ).freeze
    # A view command reaches no record and opens no operation, so a failure there leaves the Model as it was.
    VIEW_FAILED = Outcome.build(
      "failed", "operation.failed", "The panel could not change what the viewport shows.", "none", nil
    ).freeze
    SETUP_FAILED = Outcome.build(
      "failed", "operation.failed", "The panel could not change that setup.", "none", nil
    ).freeze
    QUERY_FAILED = Outcome.build(
      "failed", "operation.failed", "The panel could not read that information.", "none", nil
    ).freeze
    # The panel could not tell whether an action ran, so it does not claim the Model is unchanged.
    # The page asked about a request id the host never received, so nothing ran.
    NOT_RECEIVED = Outcome.refused("request.not_received", "PH-Composer did not receive that change.",
                                   :revision => nil, :mutation => true).freeze
    UNEXPECTED = Outcome.build(
      "failed", "operation.failed",
      "The panel could not complete that request. Check the Model before continuing.", "unknown", nil
    ).freeze

    class << self
      def install
        return if @installed

        Sessions.on_refresh { |session| refresh(session) }
        Sessions.on_notice { |session, message, tone| notice(session, message, tone) }
        REFRESH_EVENTS.each do |kind|
          Sessions.on_host_event(kind) { |session| session.request_refresh if showing?(session) }
        end
        @installed = true
      end

      # Opens the panel, or brings an open one forward. Only a user command calls this.
      def show
        if @dialog
          @dialog.bring_to_front
        else
          @dialog = build_dialog
          @dialog.show
        end
        @dialog
      end

      def open?
        !@dialog.nil?
      end

      # Closes the panel's window and opens a new one, for a page that stopped rendering. An unsaved edit in
      # the old page goes with it; what was applied to the Model stays.
      def reopen
        @dialog&.close
        @dialog = nil
        show
      end

      # Development only: a development composition entry (tools/examples/) adds a script that runs in the
      # page each time it opens, after the kit has started. Shipping features declare their modules in
      # html/ instead; nothing in the shipping build calls this.
      def add_development_script(path)
        development_scripts << File.expand_path(path) unless development_scripts.include?(File.expand_path(path))
      end

      # Republishes the shown Model's snapshot when `session` is that Model.
      def refresh(session)
        publish_snapshot(session) if showing?(session)
      end

      # Whether an open, started panel shows this session's Model.
      def showing?(session)
        @ready && !session.nil? && session.equal?(Sessions.current)
      end

      # A session's notice reaches the open panel if it shows that session; otherwise it waits, bounded,
      # until the panel next shows it. It never opens the panel.
      def notice(session, message, tone)
        item = { "session" => session.id, "message" => message.to_s, "tone" => tone.to_s }
        if showing?(session)
          publish("panel.notice", item)
        else
          pending_notices << item
          pending_notices.shift while pending_notices.length > MAX_PENDING_NOTICES
        end
      end

      def reset_for_test
        @dialog&.close
        @dialog = nil
        @ready = false
        @contexts = {}
        @sequences = {}
        @pending_notices = []
        @development_scripts = []
      end

      private

      def build_dialog
        dialog = UI::HtmlDialog.new(
          :dialog_title => EXTENSION_NAME, :preferences_key => "#{EXTENSION_ID}.panel", :scrollable => true,
          :resizable => true, :width => WIDTH, :height => HEIGHT, :min_width => MIN_WIDTH,
          :min_height => MIN_HEIGHT, :style => UI::HtmlDialog::STYLE_WINDOW
        )
        dialog.set_file(PAGE)
        # Bound to this dialog: a message from a page that has since closed is ignored.
        dialog.add_action_callback("ph_composer_message") { |_context, raw| receive(dialog, raw) }
        dialog.set_on_closed { closed(dialog) }
        @ready = false
        dialog
      end

      def closed(dialog)
        return unless @dialog.equal?(dialog)

        @dialog = nil
        @ready = false
      end

      def receive(dialog, raw)
        return unless @dialog.equal?(dialog)

        type, payload = PanelMessages.parse(raw)
      rescue PanelMessages::Malformed => error
        publish("panel.failure", "message" => error.message)
      else
        handle(type, payload)
      end

      # Every event logged while serving a message names the session and request it served.
      def handle(type, payload)
        references = Diagnostics.accepted("session" => payload["session"], "request" => payload["request_id"])
        Diagnostics.with_context(references) { route(type, payload) }
      end

      # A request the page is waiting on is always answered in its own shape, so the view that asked can
      # settle; an unexpected error is logged under an incident reference the failed outcome carries.
      def route(type, payload)
        PanelPresence.catch_up(type, method(:publish), method(:publish_snapshot))
        case type
        when "panel.ready" then ready
        when "panel.diagnostic" then PanelDiagnostics.record(payload)
        when "panel.support" then SupportDialog.show(:incident => payload["incident"])
        when *SetupEntries::MESSAGES then publish("panel.setup", "entries" => SetupEntries.answer(type, payload))
        when "panel.undo", "panel.redo" then PanelHistory.step(type, payload["session"])
        when "action.invoke" then invoke(payload)
        when "action.status" then status(payload)
        when "view.invoke" then view(payload)
        when "setup.invoke" then setup(payload)
        when "query.invoke" then query(payload)
        when "file_export.invoke" then file_export(payload)
        when "preferences.set" then set_preference(payload)
        when *EXPORT_TYPES then export(type, payload)
        end
      rescue StandardError => error
        detail = { "detail" => { "incident" => Diagnostics.incident("panel_message", error) } }
        case type
        when "action.invoke", "action.status" then publish_result(payload, UNEXPECTED.merge(detail))
        when "view.invoke" then publish_view(payload, VIEW_FAILED.merge(detail))
        when "setup.invoke" then publish_setup(payload, SETUP_FAILED.merge(detail))
        when "query.invoke" then publish_query(payload, QUERY_FAILED.merge(detail))
        when "file_export.invoke" then publish_file_export(payload, EXPORT_FAILED.merge(detail))
        when *EXPORT_TYPES then publish_export(payload, EXPORT_FAILED.merge(detail))
        when "preferences.set" then publish_preferences(payload, "failed", "The display preference could not be saved.")
        else publish("panel.failure", "message" => "The panel could not complete that request.")
        end
      end

      # A page that has just loaded numbers its requests from the start again, so the ids an earlier page
      # used are forgotten here rather than matched to the new page's.
      def ready
        PanelRequests.reset
        @ready = true
        development_scripts.each { |path| run_development_script(path) }
        session = Sessions.current
        return publish("panel.snapshot", PanelPresence.empty_snapshot) unless session

        publish_snapshot(session)
        delivered, waiting = pending_notices.partition { |item| item["session"] == session.id }
        @pending_notices = waiting
        delivered.each { |item| publish("panel.notice", item) }
      end

      # The active Model's session when the payload names it: the panel acts only on the Model it shows.
      def shown_session(payload)
        Sessions.current.then { |session| session if session && payload["session"] == session.id }
      end

      # The answer to a request for a Model the panel no longer shows: it closed, or another is shown now.
      def inactive_outcome(mutation: false)
        Outcome.refused("session.inactive", PanelPresence.inactive_message, :revision => nil, :mutation => mutation)
      end

      # The panel acts only on the Model it shows. The result follows the authoritative snapshot, so
      # the page confirms an edit against values the Model already holds.
      def invoke(payload)
        session = Sessions.current
        unless session && payload["session"] == session.id
          outcome = inactive_outcome(:mutation => true)
          publish_result(payload, outcome)
          # The page was showing another Model than the active one: bring it up to date and say why the
          # change it sent was not applied.
          return unless session

          publish_snapshot(session)
          return publish("panel.notice", "session" => session.id, "message" => outcome.fetch("message"),
                                         "tone" => "warning")
        end

        sequence = next_sequence(session)
        PanelRequests.track(session, payload["request_id"], sequence)
        outcome = API.invoke(
          :context => context_for(session), :name => payload["name"].to_s, :params => payload.fetch("params", {}),
          :request => { "sequence" => sequence, "expected_revision" => payload["expected_revision"] }
        )
        session.refresh.cancel
        publish_snapshot(session)
        publish_result(payload, outcome)
      end

      # The retained outcome of an action whose result the page lost, under its original sequence; it never
      # runs again (TECH_STACK, "Panel protocol"). The snapshot comes first, so the answer reads against it.
      def status(payload)
        session = shown_session(payload)
        return publish_result(payload, inactive_outcome) unless session

        sequence = PanelRequests.sequence(session, payload["request_id"])
        unknown = PanelRequests.forgotten?(session) ? FORGOTTEN : NOT_RECEIVED
        outcome = sequence ? retained_outcome(session, sequence) : unknown.merge("revision" => session.revision)
        publish_snapshot(session)
        publish_result(payload, outcome)
      end

      # An expired outcome cannot say whether the change was kept, so it never reads as nothing written.
      def retained_outcome(session, sequence)
        outcome = API.outcome(:context => context_for(session), :request => { "sequence" => sequence })
        outcome["code"] == "request.outcome_unavailable" ? outcome.merge("effect" => "unknown") : outcome
      end

      # Selection, camera and the active Colour-by mode, for the Model the panel shows. A section may read
      # what the command changed, so a snapshot follows; the revision does not move, so nothing the page has
      # in flight goes stale.
      #
      # Changing the selection raises a host event, which schedules a refresh that would publish the same
      # snapshot again a tick later: cancelling it first keeps one viewport click to one Model read. A
      # refusal publishes nothing, because a section that refused with it would replace good data with the
      # same refusal.
      def view(payload)
        session = shown_session(payload)
        return publish_view(payload, inactive_outcome) unless session

        outcome = API.view(:context => context_for(session), :name => payload["name"].to_s,
                           :params => payload.fetch("params", {}))
        if outcome.fetch("status") == "completed"
          session.refresh.cancel
          publish_snapshot(session)
        end
        publish_view(payload, outcome)
      end

      def publish_view(payload, outcome)
        publish("view.result", "request_id" => payload["request_id"], "session" => payload["session"],
                               "outcome" => outcome)
      end

      # Session and machine state for the Model the panel shows. A completed command is followed by a
      # snapshot, because a section may show what it changed; the revision does not move.
      def setup(payload)
        session = shown_session(payload)
        return publish_setup(payload, inactive_outcome) unless session

        outcome = NativeApproval.setup(context_for(session), payload["name"].to_s, payload.fetch("params", {}))
        if outcome.fetch("status") == "completed"
          session.refresh.cancel
          publish_snapshot(session)
        end
        publish_setup(payload, outcome)
      end

      def publish_setup(payload, outcome)
        publish("setup.result", "request_id" => payload["request_id"], "session" => payload["session"],
                                "outcome" => outcome)
      end

      # Read-only queries answer directly; they neither refresh the page nor consume a mutation sequence.
      def query(payload)
        session = shown_session(payload)
        outcome = if session
                    API.query(:context => context_for(session), :name => payload["name"].to_s,
                              :params => payload.fetch("params", {}))
                  else
                    inactive_outcome
                  end
        publish_query(payload, outcome)
      end

      def publish_query(payload, outcome)
        publish("query.result", "request_id" => payload["request_id"], "session" => payload["session"],
                                "outcome" => outcome)
      end

      # Registered local file commands use their export grant without a mutation sequence or snapshot refresh.
      # The panel is a native client: it asks the user for a declared destination first (NativeApproval).
      def file_export(payload)
        session = shown_session(payload)
        outcome = if session
                    NativeApproval.file_export(context_for(session), payload["name"].to_s,
                                               payload.fetch("params", {}))
                  else
                    inactive_outcome
                  end
        publish_file_export(payload, outcome)
      end

      def publish_file_export(payload, outcome)
        publish("file_export.result", "request_id" => payload["request_id"], "session" => payload["session"],
                                      "outcome" => outcome)
      end

      # Export acts on the Model the panel shows, like an action, but it is the shell's command: it opens a
      # native destination dialog, so it never runs inside a Model operation.
      def export(type, payload)
        session = shown_session(payload)
        outcome = session ? export_request(type, payload, session) : inactive_outcome
        publish_export(payload, outcome)
      end

      def export_request(type, payload, session)
        context = context_for(session)
        case type
        when "export.start"
          Export::Workflow.start(session, :context => context, :repairs => payload.fetch("repairs", []),
                                          :request => -> {
                                                        { "sequence" => next_sequence(session),
                                                          "expected_revision" => session.revision }
                                                      })
        when "export.preflight" then API.export_preflight(:context => context)
        when "export.status" then API.export_status(:context => context, :task_id => payload["task_id"])
        when "export.cancel" then API.cancel_export(:context => context, :task_id => payload["task_id"])
        when "export.latest" then API.latest_export(:context => context)
        end
      end

      def publish_export(payload, outcome)
        publish("export.result", "request_id" => payload["request_id"], "session" => payload["session"],
                                 "outcome" => outcome)
      end

      # A snapshot that cannot be built is logged and skipped; the result that follows still settles the
      # request, and the next refresh tries again.
      def publish_snapshot(session)
        publish("panel.snapshot", snapshot(session).tap { PanelPresence.shown(session.id) })
      rescue StandardError => error
        Diagnostics.exception("panel_snapshot", error)
      end

      def run_development_script(path)
        @dialog.execute_script(File.read(path))
      rescue StandardError => error
        Diagnostics.exception("panel_development_script", error)
      end

      def publish_result(payload, outcome)
        publish("action.result", "request_id" => payload["request_id"], "session" => payload["session"],
                                 "outcome" => outcome)
      end

      def set_preference(payload)
        Preferences.set(payload["key"], payload["value"], :scope => payload["scope"], :system => payload["system"])
        publish_preferences(payload, "completed", "Display preference saved.")
      rescue UserError => error
        publish_preferences(payload, "refused", error.message)
      end

      def publish_preferences(payload, status, message)
        publish("preferences.result", "request_id" => payload["request_id"], "status" => status,
                                      "message" => message, "preferences" => Preferences.snapshot)
      end

      def snapshot(session)
        Snapshot.build(context_for(session)).merge(
          "product" => EXTENSION_NAME, "version" => VERSION, "file_name" => File.basename(session.model.path.to_s),
          "edit_path" => edit_path(session.model), "preferences" => Preferences.snapshot
        )
      end

      # The names of the groups and components the user has opened for editing, outermost first.
      def edit_path(model)
        Array(model.active_path).map do |instance|
          name = instance.respond_to?(:name) ? instance.name.to_s : ""
          name = instance.definition.name.to_s if name.empty? && instance.respond_to?(:definition)
          name
        end
      end

      # The panel's caller handle for a session, issued on first use and kept while the session lives.
      def context_for(session)
        @contexts ||= {}
        @contexts.delete_if { |id, _context| Sessions.find(id).nil? }
        @contexts[session.id] ||= API.connect(:session_id => session.id,
                                              :capabilities => %w[read view model_write setup export])
      end

      def next_sequence(session)
        @sequences ||= {}
        @sequences[session.id] = @sequences.fetch(session.id, 0) + 1
      end

      def publish(type, payload)
        @dialog&.execute_script(PanelMessages.script(type, payload))
      end

      def pending_notices
        @pending_notices ||= []
      end

      def development_scripts
        @development_scripts ||= []
      end
    end
  end

  on_reset("panel") { Panel.reset_for_test }
end
