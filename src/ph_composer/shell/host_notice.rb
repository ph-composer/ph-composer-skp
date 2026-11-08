# frozen_string_literal: true

module PhComposer
  # The answer to an action taken in SketchUp, shown in SketchUp: the panel's notice (which may be closed),
  # the status bar and SketchUp's own notification box. For one action's outcome or refusal; a viewport
  # tool's per-click guidance stays in the status bar and the panel. Notifications stack and the API has
  # no call to close one (context/SKETCHUP_HOST_BEHAVIOR.md), so the same message again soon shows no second
  # box, and a box that fails to show is logged without troubling the action that answered.
  module HostNotice
    REPEAT_SECONDS = 10.0
    MONOTONIC = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

    class << self
      attr_writer :clock

      def show(session, message, tone: :warning)
        session.notice(message, :tone => tone)
        Sketchup.status_text = message
        notify(session, message)
      end

      private

      def notify(session, message)
        last = session.feature_state(:host_notice) { {} }
        now = (@clock || MONOTONIC).call
        return if last[:message] == message && now - last[:at] < REPEAT_SECONDS

        UI::Notification.new(EXTENSION, message).show
        last.update(:message => message, :at => now)
      rescue StandardError => error
        Diagnostics.exception("host_notice", error)
      end
    end
  end
end
