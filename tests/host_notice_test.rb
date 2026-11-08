# frozen_string_literal: true

require_relative "test_helper"

# An action taken in SketchUp answers in SketchUp: the panel's notice, the status bar and SketchUp's own
# notification (shell/host_notice.rb).
class HostNoticeTest < PhComposerTestCase
  HostNotice = PhComposer::HostNotice

  def setup
    super
    @session = PhComposer::Sessions.for(Sketchup.active_model)
    @notices = []
    PhComposer::Sessions.on_notice { |_session, message, tone| @notices << [message, tone] }
    @now = 100.0
    HostNotice.clock = -> { @now }
  end

  def teardown
    HostNotice.clock = nil
    super
  end

  def shown
    UI.notifications.map(&:message)
  end

  def test_a_message_reaches_the_panel_the_status_bar_and_sketchups_notification
    HostNotice.show(@session, "Two Faces paired.", :tone => :success)

    assert_equal [["Two Faces paired.", :success]], @notices
    assert_equal "Two Faces paired.", Sketchup.status_texts.last
    assert_equal ["Two Faces paired."], shown
    assert_equal PhComposer::EXTENSION, UI.notifications.first.extension
  end

  # Notifications stack and SketchUp offers no call to close one, so a refused click repeated on the spot
  # must not pile them up. The panel and the status bar still answer every time.
  def test_the_same_message_again_soon_shows_no_second_notification
    2.times { HostNotice.show(@session, "Refused.") }
    @now += HostNotice::REPEAT_SECONDS
    HostNotice.show(@session, "Refused.")

    assert_equal ["Refused.", "Refused."], shown
    assert_equal 3, @notices.length
  end

  def test_a_different_message_shows_at_once
    HostNotice.show(@session, "One.")
    HostNotice.show(@session, "Two.")

    assert_equal %w[One. Two.], shown
  end

  def test_a_notification_that_fails_is_logged_and_does_not_break_the_action
    UI::Notification.stub(:new, ->(*) { raise ArgumentError, "no notification" }) do
      HostNotice.show(@session, "Still answered.")
    end

    assert_equal "Still answered.", Sketchup.status_texts.last
    assert_equal 1, @notices.length
    assert(PhComposer::Diagnostics.tail.any? { |line| line.include?('"host_notice"') })

    HostNotice.show(@session, "Still answered.")
    assert_equal ["Still answered."], shown, "a box that failed does not count as shown"
  end
end
