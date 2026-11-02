# frozen_string_literal: true

require "securerandom"

module PhComposer
  module Library
    module Connection
      # The check a version 2 source passes before a copy or a library update stages any write. The
      # coordinator asks the provider's `authorize_use` about the exact row and source revision, then
      # proposes the write in the same handler; the action's native transaction follows (Dispatch#run),
      # so preview and invoke, panel and script, take the same path. The answer is good for
      # WINDOW_SECONDS from the moment the request began, on the monotonic clock, so time spent on the
      # network counts against it. `confirm!` checks it again, with the destination Model, the selected
      # snapshot and the connection generation, once on the answer and once after the writes are staged.
      class Use
        WINDOW_SECONDS = 5.0
        ANSWERS = { "allowed" => nil, "reload_required" => "library.reload_required",
                    "reauthorization_required" => "library.reauthorization_required",
                    "unavailable" => "library.provider_unavailable" }.freeze

        attr_reader :source_revision

        # The checked use of `row`, or nil when `provider` is version 1 and no check applies.
        def self.authorize(request, provider, entry, row)
          declaration = State.connection_declaration(provider.provider_kind, request.registry)
          return unless declaration

          use = new(request, provider, declaration, entry, row)
          use.request!
          use
        end

        def initialize(request, provider, declaration, entry, row)
          @session = request.session
          @model = @session.model
          @provider = provider
          @declaration = declaration
          @kind = entry.fetch("kind")
          @row = row
          @state = State.for(@session)
          @transport = @state.transport(provider.id, @kind)
          unless @transport && @transport.fetch("generation") == entry.fetch("generation")
            raise Error.new("library.row_unavailable", "The selected library record is unavailable.")
          end

          @source_revision = @transport.fetch("source_revisions")[Provider.source_key(@kind, row)]
          return if @source_revision

          raise Error.new("library.row_unavailable", "The selected library record is unavailable.")
        end

        def request!
          @started = Manager.clock.call
          @generation = Manager.generation(@declaration)
          unless @transport.fetch("connection_generation") == @generation
            raise Error.new("library.reload_required", "The library connection changed; load the library again.")
          end

          answer = ask
          code = ANSWERS.fetch(answer) do
            raise Error.new("library.provider_invalid", "The library returned an invalid use answer.")
          end
          raise Error.new(code, "The library did not allow this record to be used.") if code

          confirm!
        end

        def confirm!
          if Manager.clock.call - @started > WINDOW_SECONDS
            raise Error.new("library.use_expired", "The library's permission expired before the copy was made.")
          end
          unless Manager.generation(@declaration) == @generation
            raise Error.new("library.connection_changed", "The library connection changed during the copy.")
          end
          unless @session.valid? && @session.model.equal?(@model)
            raise Error.new("library.model_changed", "The destination Model changed during the copy.")
          end
          return if @state.transport(@provider.id, @kind).equal?(@transport)

          raise Error.new("library.selection_changed", "The library was reloaded during the copy.")
        end

        private

        def ask
          selection = [{ "kind" => @kind, "library_id" => @row.fetch("library_id"),
                         "record_id" => @row.fetch("record_id"), "source_revision" => @source_revision }]
          answer = @provider.authorize_use(:operation_id => "use_#{SecureRandom.hex(12)}",
                                           :snapshot_id => @transport.dig("snapshot", "id"),
                                           :selection => Provider.immutable(selection))
          answer.is_a?(Symbol) ? answer.to_s : answer
        rescue *EXTENSION_ERRORS => error
          raise Connection.refusal(error, @declaration, :authorize_use), :cause => nil
        end
      end
    end
  end
end
