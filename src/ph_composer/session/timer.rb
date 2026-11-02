# frozen_string_literal: true

module PhComposer
  # One pending one-shot UI timer at most, zero-delay unless asked: repeated requests before it fires
  # coalesce into one run.
  class CoalescedTimer
    def initialize
      @timer = nil
    end

    def schedule(delay: 0.0, &block)
      return false if pending?

      @timer = UI.start_timer(delay, false) do
        @timer = nil
        block.call
      end
      true
    end

    def cancel
      return false unless pending?

      self.class.stop(@timer)
      @timer = nil
      true
    end

    def pending?
      !@timer.nil?
    end

    def self.stop(timer)
      UI.stop_timer(timer) if timer && UI.respond_to?(:stop_timer)
    end
  end
end
