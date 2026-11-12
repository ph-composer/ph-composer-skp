# frozen_string_literal: true

module PhComposer
  # Retained mutation outcomes for one Model session, so a retried request returns its first result
  # instead of running again (context/CONTRACTS.md, "Retries"). Bounded: at most CAPACITY entries
  # across every caller, each kept for at most LIFETIME_SECONDS, the oldest evicted first. An evicted
  # or expired entry is gone; the caller registry still remembers that its sequence was used.
  class OutcomeStore
    CAPACITY = 256
    LIFETIME_SECONDS = 15 * 60

    # `outcome` is nil while the request is still running. `name` is the operation it ran. `recorded_at` is the
    # store's own clock, for expiry; `recorded_utc` is the wall time it was accepted, for a caller to read.
    Entry = Struct.new(:caller, :sequence, :digest, :name, :outcome, :recorded_at, :recorded_utc,
                       keyword_init: true) do
      def pending?
        outcome.nil?
      end
    end

    attr_writer :clock

    def initialize(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @clock = clock
      @entries = {}
    end

    def lookup(caller, sequence)
      expire
      @entries[[caller, sequence]]
    end

    def begin(caller, sequence, digest, name: nil)
      expire
      @entries.delete(@entries.keys.first) while @entries.length >= CAPACITY
      @entries[[caller, sequence]] = Entry.new(
        :caller => caller, :sequence => sequence, :digest => digest, :name => name, :outcome => nil,
        :recorded_at => @clock.call, :recorded_utc => Time.now.utc.iso8601
      )
    end

    # Keeps its own copy, so nothing a caller does to the returned outcome reaches a later retry.
    def finish(caller, sequence, outcome)
      entry = @entries[[caller, sequence]]
      entry.outcome = DeepCopy.call(outcome) if entry
      outcome
    end

    # A copy of the retained outcome for `caller` and `sequence`, or nil.
    def retained(caller, sequence)
      outcome = lookup(caller, sequence)&.outcome
      outcome && DeepCopy.call(outcome)
    end

    # Copies of `caller`'s finished entries still retained, newest first. Nobody else's are ever among them.
    def history(caller)
      expire
      own = @entries.values.select { |entry| entry.caller == caller && !entry.pending? }
      own.sort_by { |entry| -entry.sequence }.map do |entry|
        entry.dup.tap do |copy|
          copy.outcome = DeepCopy.call(entry.outcome)
          copy.name = entry.name&.dup
          copy.recorded_utc = entry.recorded_utc.dup
        end
      end
    end

    def count
      expire
      @entries.length
    end

    private

    # Entries are kept in insertion order, so the expired ones are always at the front.
    def expire
      cutoff = @clock.call - LIFETIME_SECONDS
      @entries.shift while !@entries.empty? && @entries.first[1].recorded_at <= cutoff && !@entries.first[1].pending?
    end
  end
end
