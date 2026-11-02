# frozen_string_literal: true

require "securerandom"
require_relative "../admission"

module PhComposer
  module Library
    module Connection
      # What `begin_load`, `poll_load` and `cancel_load` are given: the operation's id, the wire kind
      # and the connection generation it began under.
      Operation = Struct.new(:id, :kind, :generation, keyword_init: true)

      # One version 2 catalog load for one session, provider and kind, polled on the main thread like an
      # export task (export/task.rb): `begin_load` starts it, a one-shot timer calls `poll_load` until it
      # answers, and nothing runs on another Ruby thread. The provider does its network work behind
      # those calls. A load publishes only a complete admitted snapshot; a failure, a cancel or the
      # timeout leaves the published generation as it was (Catalog#mark). A poll that finds the session
      # closed, the connection generation moved on or a newer load for the same catalog drops the
      # answer without publishing it.
      class Load
        POLL_SECONDS = 0.25
        TIMEOUT_SECONDS = 120

        attr_reader :operation

        def provider_kind
          @declaration.name
        end

        def initialize(session:, catalog:, provider:, declaration:, adapter:, kind:)
          @session = session
          @model = session.model
          @catalog = catalog
          @provider = provider
          @declaration = declaration
          @adapter = adapter
          @kind = kind
          @timer = CoalescedTimer.new
        end

        # The catalog entry, now `loading`. Refused unless the connection is connected.
        def start
          status = Manager.status(@declaration)
          unless status.fetch("state") == "connected"
            raise Error.new(status.fetch("state") == "reauthorization_required" ? "library.reauthorization_required" :
                              "library.connection_required", "Connect this library before loading it.")
          end

          @operation = Operation.new(:id => "load_#{SecureRandom.hex(12)}", :kind => @kind,
                                     :generation => status.fetch("generation")).freeze
          @started = Manager.clock.call
          begin
            call(:begin_load) do
              @provider.begin_load(@kind, :connection => Manager.connection(@declaration), :operation => @operation)
            end
          rescue Error => error
            # Every reader sees the failed refresh, not only the command that asked for it.
            fail_load(error)
            raise
          end
          schedule
          @catalog.mark(@provider.id, @kind, "loading")
        end

        def finished?
          !@finished.nil?
        end

        # Stops polling and tells the provider; the published generation stays, marked `cancelled`. A
        # load the connection or session moved on from (`drop`) ends the same way.
        def cancel
          return false if finished?

          finish
          stop_provider
          @catalog.mark(@provider.id, @kind, "cancelled")
          @session.request_refresh
          true
        end
        alias drop cancel

        private

        def schedule
          @timer.schedule(:delay => POLL_SECONDS) { tick }
        end

        def tick
          return if finished?
          return drop unless current?

          response = call(:poll_load) { @provider.poll_load(@operation) }
          # The poll itself may have cancelled or replaced this load, or moved the connection on.
          return if finished?
          return drop unless current?
          # An answer after the deadline is not accepted, however complete.
          if Manager.clock.call - @started > TIMEOUT_SECONDS
            raise Error.new("library.load_timeout", "The library did not finish loading in time.")
          end
          return publish(response) unless response.nil?

          schedule
        rescue Error => error
          fail_load(error)
        rescue *EXTENSION_ERRORS
          # An adapter or admission fault: the load ends `stale` or `unavailable`, never stuck `loading`.
          fail_load(Error.new("library.provider_failed", "The library could not be loaded."))
        end

        def publish(response)
          batch, revisions = Admission.revisioned(response, :kind => @kind, :adapter => @adapter)
          finish
          @catalog.publish_revisioned(@provider.id, @kind, batch, :snapshot => response.snapshot,
                                                                  :source_revisions => revisions,
                                                                  :connection_generation => @operation.generation,
                                                                  :provider_kind => @declaration.name)
          @session.request_refresh
        end

        def fail_load(error)
          finish
          stop_provider
          @catalog.mark(@provider.id, @kind, "failed",
                        :failure => { "code" => error.code, "message" => "The library could not be loaded." })
          @session.request_refresh
        end

        def finish
          @finished = true
          @timer.cancel
        end

        # Best effort: the provider's own failure to stop changes nothing here.
        def stop_provider
          @provider.cancel_load(@operation)
        rescue *EXTENSION_ERRORS
          nil
        end

        # The session that asked is still open on the same Model, and the connection is the one the load
        # began under.
        def current?
          @session.valid? && @session.model.equal?(@model) &&
            Manager.generation(@declaration) == @operation.generation
        end

        # A provider failure keeps its code only when the callback declares it.
        def call(callback)
          yield
        rescue *EXTENSION_ERRORS => error
          raise Connection.refusal(error, @declaration, callback), :cause => nil
        end
      end
    end
  end
end
