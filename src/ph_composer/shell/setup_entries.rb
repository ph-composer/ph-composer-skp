# frozen_string_literal: true

module PhComposer
  # The panel's Setup view (context/EXTENSIBILITY.md, "Setup entries"): the native menu items a feature
  # declares `in_setup`, each with its line of current state, and the route that runs one from the panel.
  # A menu item is already the user's own route, so the panel reaching it gives nobody more; no client
  # can, because nothing here is an API operation. Names no feature.
  module SetupEntries
    MESSAGES = %w[panel.setup_entries panel.setup_open].freeze

    module_function

    # The entries the panel asked for, after running the one it named for `panel.setup_open`.
    def answer(type, payload)
      type == "panel.setup_open" ? run(payload.fetch("name")) : list(Sessions.current)
    end

    # Every Setup entry in registration order: its name, submenu, label and summary (nil when it has none).
    def list(session)
      Registry.current.menu_items.each_value.select(&:in_setup).map do |item|
        { "name" => item.name, "menu" => item.menu, "label" => item.label, "summary" => summary(item, session) }
      end
    end

    # A summary that raises or answers no text is logged and left out; the entry still shows.
    def summary(item, session)
      return nil unless item.summary

      text = item.summary.call(session)
      text.is_a?(String) && !text.strip.empty? ? text : nil
    rescue StandardError => error
      Diagnostics.log("setup_summary_failed", "severity" => "warning", "operation" => item.name,
                                              "error_class" => error.class.name)
      nil
    end

    # Runs a Setup entry from the panel as the Extensions menu runs it: with the current session, and none
    # when no Model is open. A refusal is that Model's notice, as from the menu. Answers the entries again,
    # so their summaries show what it changed.
    def run(name)
      item = Registry.current.menu_items[name]
      unless item&.in_setup
        raise CodedError.new("request.unknown_operation", "There is no Setup entry #{name.to_s[0, 80].inspect}.")
      end

      session = Sessions.current
      begin
        item.handler.call(session) if session
      rescue UserError => error
        session.notice(error.message, :tone => :warning)
      end
      list(Sessions.current)
    end
  end
end
