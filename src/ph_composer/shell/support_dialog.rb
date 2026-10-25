# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "uri"

module PhComposer
  # Help & Diagnostics: a small window of its own, opened from the Extensions menu or the panel, that
  # works with no Model, no panel and no Python. It shows what is installed and what the log recorded,
  # previews the support report, and offers the two recoveries this build has: reopening the panel and
  # resetting display preferences. Nothing here writes the Model; copying or saving sends nothing.
  #
  # If the page cannot be built, or does not report ready within FALLBACK_SECONDS, a native message box
  # gives the version, build, log folder and help address instead.
  module SupportDialog
    PAGE = File.join(__dir__, "..", "html", "support", "index.html")
    CALLBACK = "ph_composer_support"
    TITLE = "#{EXTENSION_NAME} Help & Diagnostics".freeze
    FALLBACK_SECONDS = 5
    HELP_PAGE = File.join(ROOT, "help", "index.html")
    # The online copy of the shipped help page, both from docs/HELP.md, at the commit this build came from.
    HELP_URL = "https://github.com/ph-composer/ph-composer-skp/blob/%<ref>s/docs/HELP.md"
    ISSUE_URL = "https://github.com/ph-composer/ph-composer-skp/issues/new?template=bug_report.yml"
    INBOUND = {
      "support.ready" => [], "support.capture" => %w[purpose], "support.save" => %w[capture_id],
      "support.open_log_folder" => [], "support.open_help" => [], "support.open_online_help" => [],
      "support.report_problem" => [],
      "support.clear_history" => [], "support.reopen_panel" => [], "support.reset_preferences" => []
    }.freeze
    OUTBOUND = {
      "support.state" => %w[about problems incident retention_days resettable],
      "support.capture" => %w[capture_id captured_at text purpose],
      "support.result" => %w[action status message]
    }.freeze

    class << self
      # Opens the window, or brings it forward, at `incident` when a failure notice named one.
      def show(incident: nil)
        @incident = Diagnostics::INCIDENT.match?(incident.to_s) ? incident : nil
        return bring_forward if @dialog

        @ready = false
        @dialog = build_dialog
        @dialog.show
        @fallback = UI.start_timer(FALLBACK_SECONDS, false) { fallback unless @ready }
        @dialog
      rescue StandardError => error
        Diagnostics.exception("support_dialog", error)
        fallback
      end

      def open?
        !@dialog.nil?
      end

      def reset_for_test
        @dialog&.close
        @dialog = nil
        @incident = nil
        @ready = false
      end

      def parse(raw)
        message = JSON.parse(raw.to_s)
        type = message.is_a?(Hash) ? message["type"] : nil
        payload = message.is_a?(Hash) ? message.fetch("payload", {}) : nil
        accepted = INBOUND.key?(type) && payload.is_a?(Hash) && (payload.keys - INBOUND[type]).empty?
        raise UserError, "That Help & Diagnostics message is not accepted." unless accepted

        [type, payload]
      rescue JSON::ParserError
        raise UserError, "That Help & Diagnostics message is not accepted."
      end

      def script(type, payload)
        declared = OUTBOUND.fetch(type) { raise ArgumentError, "#{type} is not an outbound support message." }
        stray = payload.keys - declared
        raise ArgumentError, "#{type} does not declare #{stray.join(', ')}." unless stray.empty?

        "PhComposerUI.get(\"support/page\").receive(#{JSON.generate('type' => type, 'payload' => payload)})"
      end

      # The plain words the message box shows when the window cannot.
      def fallback_text
        "#{EXTENSION_NAME} #{VERSION}\nBuild: #{BuildIdentity.build}\n" \
          "Log folder: #{File.dirname(Diagnostics.path)}\nHelp: #{help_url}"
      end

      # The help for the installed build: its commit, or main for a development build.
      def help_url
        format(HELP_URL, :ref => BuildIdentity.commit.to_s.delete_suffix("-dirty")[/\A\h+\z/] || "main")
      end

      private

      def bring_forward
        @dialog.bring_to_front
        publish_state
        @dialog
      end

      def build_dialog
        dialog = UI::HtmlDialog.new(
          :dialog_title => TITLE, :preferences_key => "#{EXTENSION_ID}.support", :scrollable => true,
          :resizable => true, :width => 560, :height => 640, :min_width => 360, :min_height => 420,
          :style => UI::HtmlDialog::STYLE_DIALOG
        )
        dialog.set_file(PAGE)
        dialog.add_action_callback(CALLBACK) { |_context, raw| receive(dialog, raw) }
        dialog.set_on_closed { closed(dialog) }
        dialog
      end

      def closed(dialog)
        return unless @dialog.equal?(dialog)

        @dialog = nil
        CoalescedTimer.stop(@fallback)
        @fallback = nil
      end

      def fallback
        dialog = @dialog
        @dialog = nil
        dialog&.close
        UI.messagebox(fallback_text)
        nil
      end

      def receive(dialog, raw)
        return unless @dialog.equal?(dialog)

        type, payload = parse(raw)
        handle(type, payload)
      rescue UserError => error
        result("message", "refused", error.message)
      rescue StandardError => error
        reference = Diagnostics.incident("support_message", error)
        result(type || "message", "failed", "Help & Diagnostics could not do that (#{reference}).")
      end

      def handle(type, payload)
        case type
        when "support.ready" then ready
        when "support.capture" then capture(payload["purpose"])
        when "support.save" then save(payload["capture_id"])
        when "support.open_log_folder" then open_log_folder
        when "support.open_help" then open_url(type, File.exist?(HELP_PAGE) ? file_url(HELP_PAGE) : help_url)
        when "support.open_online_help" then open_url(type, help_url)
        when "support.report_problem" then open_url(type, ISSUE_URL)
        when "support.clear_history" then clear_history
        when "support.reopen_panel" then reopen_panel
        when "support.reset_preferences" then reset_preferences
        end
      end

      def ready
        @ready = true
        CoalescedTimer.stop(@fallback)
        @fallback = nil
        publish_state
      end

      def publish_state
        publish("support.state", "about" => SupportReport.about, "problems" => SupportReport.problems,
                                 "incident" => @incident, "retention_days" => Diagnostics::RETENTION_SECONDS / 86_400,
                                 "resettable" => Preferences::RESETTABLE)
      end

      def capture(purpose)
        captured = SupportReport.capture(:incident => @incident)
        publish("support.capture", captured.merge("purpose" => purpose == "save" ? "save" : "copy"))
      end

      # Writes the previewed bytes through a temporary file renamed into place, so a failed write never
      # leaves what looks like a complete report.
      def save(capture_id)
        text = SupportReport.text(capture_id)
        unless text
          return result("support.save", "refused", "That preview is out of date. Refresh it and save again.")
        end

        path = UI.savepanel("Save support report", nil, "ph-composer-support-#{Time.now.strftime('%Y%m%d-%H%M')}.txt")
        return result("support.save", "cancelled", "Nothing was saved.") unless path

        write_report(path, text)
        result("support.save", "completed", "Support report saved.")
      rescue SystemCallError, IOError => error
        Diagnostics.exception("support_report_save", error)
        result("support.save", "failed", "The support report could not be saved there. Choose another location.")
      end

      def write_report(path, text)
        partial = "#{path}.partial-#{SecureRandom.hex(4)}"
        File.binwrite(partial, text)
        File.rename(partial, path)
      ensure
        FileUtils.rm_f(partial) if partial && File.exist?(partial)
      end

      def open_log_folder
        folder = File.dirname(Diagnostics.path)
        return result("support.open_log_folder", "refused", "No log has been written yet.") unless Dir.exist?(folder)

        open_url("support.open_log_folder", file_url(folder))
      end

      def open_url(action, url)
        UI.openURL(url)
        result(action, "completed", "Opened.")
      end

      def file_url(path)
        "file://#{URI::DEFAULT_PARSER.escape(path)}"
      end

      def clear_history
        cleared = Diagnostics.clear
        publish_state
        return result("support.clear_history", "completed", "Diagnostic history cleared.") if cleared

        result("support.clear_history", "failed", "Some of the diagnostic history could not be deleted.")
      end

      def reopen_panel
        Panel.reopen
        result("support.reopen_panel", "completed", "The panel was reopened.")
      end

      def reset_preferences
        Preferences.reset_display
        # The panel takes the defaults with its next snapshot; nothing it holds is discarded.
        session = Sessions.current
        Panel.refresh(session) if session
        result("support.reset_preferences", "completed", "Display preferences were reset.")
      rescue UserError => error
        result("support.reset_preferences", "failed", error.message)
      end

      def result(action, status, message)
        publish("support.result", "action" => action, "status" => status, "message" => message)
      end

      def publish(type, payload)
        @dialog&.execute_script(script(type, payload))
      end
    end
  end

  on_reset("support_dialog") { SupportDialog.reset_for_test }
end
