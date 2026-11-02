# frozen_string_literal: true

require_relative "../provider"

module PhComposer
  module Library
    # The hosted side of the library seam (`library_provider(..., contract_version: 2)`). Core owns
    # when things happen: lifecycle actions, the connection generation, loads and the use check.
    # The extension owns how: its transport, its sign-in and what its connection object holds.
    module Connection
      # What a connection reports through `status`. Catalog loads add `loading`, `ready`, `stale`,
      # `cancelled` and `unavailable` per provider and kind (Catalog#mark).
      STATES = %w[disconnected authorizing connected reauthorization_required unavailable].freeze
      PUBLIC_ID = /\A[A-Za-z0-9_.-]{1,128}\z/.freeze

      # What a connection factory is called with: the declaration's name, which keys its credentials;
      # the credential store; and `changed`, which the extension calls on the main thread whenever its
      # status changed outside a lifecycle action (a finished browser sign-in, a lost refresh).
      Context = Struct.new(:provider_kind, :credentials, :changed, keyword_init: true)

      # What extension code may raise that core turns into a coded refusal: an abstract stub's
      # NotImplementedError is a ScriptError, not a StandardError.
      EXTENSION_ERRORS = [StandardError, NotImplementedError].freeze

      # A provider failure as the refusal it may become: its own code when the callback declared it,
      # `library.provider_failed` otherwise. Text, details and the cause are never kept.
      def self.refusal(error, declaration, callback)
        code = error.is_a?(CodedError) ? error.code : nil
        declared = Array(declaration.refuses && declaration.refuses[callback])
        code = "library.provider_failed" unless code && declared.include?(code)
        Error.new(code, "The library connection refused the request.")
      end

      # One per SketchUp process, outside every ModelSession and provider instance. It calls each
      # version 2 declaration's connection factory once, keeps the connection object it returns, and
      # counts that connection's generation. The generation moves with every lifecycle action except
      # `settings` and whenever the connection reports a different connection id; work started under
      # an older generation is dropped (Load, Use).
      module Manager
        Record = Struct.new(:connection, :generation, :connection_id, :observed, keyword_init: true)

        module_function

        def records
          @records ||= {}
        end

        def credentials
          @credentials ||= CredentialStore
        end

        def credentials=(store)
          @credentials = store
        end

        # Seconds on a monotonic clock; Load and Use measure their bounds with it.
        def clock
          @clock ||= -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        end

        def clock=(value)
          @clock = value
        end

        def reset
          @records = {}
          @credentials = nil
          @clock = nil
        end

        def declaration(name, registry)
          found = registry.library_providers[name]
          return found if found&.contract_version == 2

          raise Error.new("library.provider_unavailable", "The library connection is unavailable.")
        end

        # The extension's connection object, made on first use. A factory that raises, or returns
        # nothing, leaves no record, so the next use tries again.
        def connection(declaration)
          record(declaration).connection
        end

        # Reads the status first, so a connection id the extension changed without calling `changed`
        # still moves the generation before anyone compares it.
        def generation(declaration)
          status(declaration).fetch("generation")
        end

        # The connection's public status: `state`, `label` and `connection_id`, never a credential. A
        # status that does not read as one is `unavailable`, under the declaration's name.
        def status(declaration)
          entry = record(declaration)
          value = public_status(entry.connection, declaration.name)
          observe(declaration, entry, value.fetch("connection_id"))
          value.merge("generation" => entry.generation)
        rescue Error
          { "state" => "unavailable", "label" => declaration.name, "connection_id" => nil,
            "generation" => records[declaration.name]&.generation || 0 }
        end

        # Runs a declared lifecycle action. Everything but `settings` starts a new generation, so loads
        # and use checks begun before it are dropped; `disconnect` also clears the catalogs it loaded.
        def act(declaration, action)
          unless Array(declaration.lifecycle).include?(action)
            raise Error.new("library.lifecycle_unavailable", "This library connection does not offer that action.")
          end

          entry = record(declaration)
          begin
            entry.connection.public_send(action)
          rescue *EXTENSION_ERRORS => error
            raise Connection.refusal(error, declaration, action), :cause => nil
          ensure
            advance(declaration, entry, :clear => action == :disconnect) unless action == :settings
          end
          status(declaration)
        end

        # Disconnects (every version 2 connection declares it), erases the credential core can name, and
        # clears what the connection loaded. Local copies in any Model are untouched.
        # A refused disconnect still erases the credential; the refusal is reported afterwards.
        def remove(declaration)
          entry = record(declaration)
          connection_id = public_status(entry.connection, declaration.name)["connection_id"]
          refused = nil
          begin
            entry.connection.disconnect
          rescue *EXTENSION_ERRORS => error
            refused = Connection.refusal(error, declaration, :disconnect)
          end
          begin
            credentials.delete(declaration.name, connection_id) if connection_id
          ensure
            advance(declaration, entry, :clear => true)
          end
          raise refused if refused

          status(declaration)
        end

        # The extension's `changed`: read the status again and show it.
        def changed(declaration)
          status(declaration)
          Sessions.all.each(&:request_refresh)
        end

        def record(declaration)
          records[declaration.name] ||= begin
            # A `changed` from inside the factory, before the record exists, has nothing to re-read.
            context = Context.new(:provider_kind => declaration.name, :credentials => credentials,
                                  :changed => -> { changed(declaration) if records.key?(declaration.name) })
            made = begin
              declaration.connection.call(context)
            rescue *EXTENSION_ERRORS
              # Even a coded error keeps nothing: its code, text and details are the extension's.
              nil
            end
            raise Error.new("library.provider_failed", "The library connection could not start.") if made.nil?

            Record.new(:connection => made, :generation => 1, :connection_id => nil, :observed => false)
          end
        end

        def public_status(connection, fallback)
          value = connection.status
          valid = value.is_a?(Hash) && STATES.include?(value["state"]) &&
                  value["label"].is_a?(String) && !value["label"].strip.empty? && value["label"].length <= 200 &&
                  (value["connection_id"].nil? || (value["connection_id"].is_a?(String) &&
                                                   PUBLIC_ID.match?(value["connection_id"])))
          return { "state" => "unavailable", "label" => fallback, "connection_id" => nil } unless valid

          { "state" => value["state"], "label" => value["label"].strip, "connection_id" => value["connection_id"] }
        rescue *EXTENSION_ERRORS
          { "state" => "unavailable", "label" => fallback, "connection_id" => nil }
        end

        # A different connection id is a different connection: its generation moves on and what the
        # old one loaded is cleared. The first status read only records the id.
        def observe(declaration, entry, connection_id)
          observed = entry.observed
          entry.observed = true
          return if entry.connection_id == connection_id

          entry.connection_id = connection_id
          advance(declaration, entry, :clear => true) if observed
        end

        def advance(declaration, entry, clear:)
          entry.generation += 1
          Sessions.all.each { |session| State.for(session).connection_changed(declaration.name, :clear => clear) }
        end
        private_class_method :record, :public_status, :observe, :advance
      end

      PhComposer.on_reset("connection manager") { Manager.reset }
    end
  end
end
