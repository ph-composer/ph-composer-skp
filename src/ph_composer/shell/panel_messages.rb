# frozen_string_literal: true

require "json"

module PhComposer
  # The messages between the panel page and Ruby. The panel is one client of the public interface
  # (context/CONTRACTS.md, "Public interface"): it sends `action.invoke` and reads snapshot sections,
  # and nothing here carries business behavior. Every message is `{"type": ..., "payload": {...}}`.
  module PanelMessages
    INBOUND = {
      "panel.ready" => [],
      # A page failure for the log: its event, section, error class and the panel's own frames.
      "panel.diagnostic" => %w[event section error_class frames],
      # Opens Help & Diagnostics, at the incident a failure notice named when there is one.
      "panel.support" => %w[incident],
      # SketchUp's own Undo or Redo for the Model the panel showed, from the platform shortcut in the panel.
      "panel.undo" => %w[session],
      "panel.redo" => %w[session],
      # The panel's window gained focus, so the host can bring it to the active Model, or to none.
      "panel.focus" => [],
      # The Setup view's entries, and running one by name (SetupEntries). Neither is an API operation.
      "panel.setup_entries" => [],
      "panel.setup_open" => %w[name],
      # `session` names the Model session the panel showed; `expected_revision` the revision it rendered.
      "action.invoke" => %w[request_id session name params expected_revision],
      # What became of an earlier action.invoke whose result the page never received. It never runs the
      # action again; the answer is that request's action.result. A channel's transport may add the
      # revision it rendered, as it does to the action; status ignores it.
      "action.status" => %w[request_id session expected_revision],
      # A viewport-state command for the Model the panel showed. It changes no record, so it carries no
      # expected revision: there is nothing for a stale one to protect.
      "view.invoke" => %w[request_id session name params],
      # A session- or machine-state command, such as adding a library on this machine. It changes no
      # record, so it carries no expected revision either.
      "setup.invoke" => %w[request_id session name params],
      "query.invoke" => %w[request_id session name params],
      "file_export.invoke" => %w[request_id session name params],
      "preferences.set" => %w[request_id key value scope system],
      # The Export command for the Model the panel showed. It is the shell's own command, not a Model action.
      "export.start" => %w[request_id session repairs],
      "export.preflight" => %w[request_id session],
      "export.status" => %w[request_id session task_id],
      "export.cancel" => %w[request_id session task_id],
      "export.latest" => %w[request_id session]
    }.freeze

    OUTBOUND = {
      "panel.snapshot" => %w[product version session revision file_name edit_path preferences sections],
      "action.result" => %w[request_id session outcome],
      "view.result" => %w[request_id session outcome],
      "setup.result" => %w[request_id session outcome],
      "query.result" => %w[request_id session outcome],
      "file_export.result" => %w[request_id session outcome],
      "preferences.result" => %w[request_id status message preferences],
      "export.result" => %w[request_id session outcome],
      "panel.notice" => %w[session message tone],
      "panel.setup" => %w[entries],
      "panel.failure" => %w[message]
    }.freeze

    class Malformed < UserError; end

    module_function

    # The type and payload of one message from the page, or Malformed.
    def parse(raw)
      message = JSON.parse(raw.to_s)
      raise Malformed, "The panel message is not an object." unless message.is_a?(Hash)

      type = message["type"]
      payload = message.fetch("payload", {})
      raise Malformed, "The panel message type #{type.inspect} is not accepted." unless INBOUND.key?(type)
      raise Malformed, "The #{type} payload must be an object." unless payload.is_a?(Hash)

      stray = payload.keys - INBOUND.fetch(type)
      raise Malformed, "The #{type} payload carries #{stray.join(', ')}." unless stray.empty?

      [type, payload]
    rescue JSON::ParserError
      raise Malformed, "The panel message is not JSON."
    end

    # The script that delivers one message to the page.
    def script(type, payload)
      declared = OUTBOUND.fetch(type) { raise ArgumentError, "#{type} is not an outbound panel message." }
      stray = payload.keys - declared
      raise ArgumentError, "#{type} does not declare #{stray.join(', ')}." unless stray.empty?

      "PhComposerUI.get(\"panel\").receive(#{JSON.generate('type' => type, 'payload' => payload)})"
    end
  end
end
