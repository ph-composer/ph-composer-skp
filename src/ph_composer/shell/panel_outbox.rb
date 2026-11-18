# frozen_string_literal: true

module PhComposer
  # What waits for the panel's page to show a session's Model: that session's notices, bounded, and the one
  # native route asking for the page where an owner's operations are worked on (Panel.open_at). The page gets
  # them once it has started and shows that Model, notices first, the route after its snapshot. A later route
  # replaces one waiting, and a window closed before its page started takes its route with it.
  module PanelOutbox
    MAX_NOTICES = 20

    module_function

    def hold(type, item)
      if type == "panel.navigate"
        @route = item
      else
        notices << item
        notices.shift while notices.length > MAX_NOTICES
      end
    end

    # The messages waiting for `session_id`, in the order to publish them, as `[type, payload]` pairs. A route for
    # another session is dropped: the user asked for it in a Model the page does not show.
    def take(session_id)
      delivered, @notices = notices.partition { |item| item["session"] == session_id }
      route, @route = @route, nil
      delivered.map { |item| ["panel.notice", item] } +
        (route && route["session"] == session_id ? [["panel.navigate", route]] : [])
    end

    def forget_route
      @route = nil
    end

    def notices
      @notices ||= []
    end

    def reset
      @notices = []
      @route = nil
    end
  end

  on_reset("panel_outbox") { PanelOutbox.reset }
end
