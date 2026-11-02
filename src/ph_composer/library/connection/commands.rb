# frozen_string_literal: true

module PhComposer
  module Library
    module Connection
      # The public face of hosted connections: what each version 2 declaration's connection reports,
      # the lifecycle actions the Libraries dialog and a script share, and cancelling a running load.
      # Results carry the connection's state and label, never a credential, address or provider body.
      module Commands
        PREFIX = "ph_composer.library.connections"
        ACTIONS = { "connect" => "Start signing in to a hosted library.",
                    "reauthorize" => "Sign in to a hosted library again, keeping its connection.",
                    "disconnect" => "Sign out of a hosted library and clear what it loaded. Local copies stay.",
                    "settings" => "Open a hosted library's own settings." }.freeze
        # Each lifecycle command's own refusals; the declaration's codes for the callback are added
        # (Refuses.callback_codes).
        REFUSES = %w[library.lifecycle_unavailable library.provider_failed library.provider_unavailable].freeze
        REMOVE_REFUSES = (REFUSES + %w[library.credential_store_failed
                                       library.credential_store_unavailable]).freeze

        module_function

        def install(feature)
          feature.query(PREFIX, :description => "Hosted library connections: each one's label, state and the " \
                                                "actions it offers. No credential or address.",
                                :refuses => [], :params => Library.object({}), :result => list,
                                :examples => [{}]) do |request|
            read(request.registry)
          end
          feature.snapshot_section("ph_composer.library.connection_states", :query => PREFIX)
          ACTIONS.each do |action, description|
            lifecycle(feature, "#{PREFIX}.#{action}", description, REFUSES) do |declaration|
              Manager.act(declaration, action.to_sym)
            end
          end
          lifecycle(feature, "#{PREFIX}.remove",
                    "Disconnect a hosted library and erase its stored credential. Local copies stay.",
                    REMOVE_REFUSES) do |declaration|
            Manager.remove(declaration)
          end
          install_cancel(feature)
        end

        def read(registry)
          registry.library_providers.values.select { |row| row.contract_version == 2 }.map do |declaration|
            Manager.status(declaration).slice("state", "label")
                   .merge("provider_kind" => declaration.name, "lifecycle" => declaration.lifecycle.map(&:to_s))
          end
        end

        def lifecycle(feature, name, description, refuses)
          params = Library.object({ "provider_kind" => Library.described(
            Library::TEXT, "The hosted library's provider kind, as ph_composer.library.connections lists it."
          ) })
          feature.setup_command(name, :description => description, :refuses => refuses, :params => params,
                                      :result => connection,
                                      :examples => [{ "provider_kind" => "example.library.hosted" }]) do |request|
            declaration = Manager.declaration(request.params.fetch("provider_kind"), request.registry)
            value = yield(declaration)
            Sessions.all.each(&:request_refresh)
            value.slice("state", "label").merge("provider_kind" => declaration.name,
                                                "lifecycle" => declaration.lifecycle.map(&:to_s))
          end
        end

        def install_cancel(feature)
          params = Library.object(Library.selected_params.fetch("properties").slice("provider_id", "kind"))
          feature.setup_command("ph_composer.library.cancel_load",
                                :description => "Cancel a hosted library load that is still running. The " \
                                                "catalog it would have replaced stays as it was.",
                                :refuses => [], :params => params,
                                :result => Library.object({ "cancelled" => Schemas::BOOLEAN }),
                                :examples => [{ "provider_id" => "example", "kind" => "materials" }]) do |request|
            cancelled = State.for(request.session).cancel_load(request.params.fetch("provider_id"),
                                                               request.params.fetch("kind"))
            { "cancelled" => cancelled }
          end
        end

        def connection
          Library.object({ "provider_kind" => Schemas::TEXT, "label" => Schemas::TEXT,
                           "state" => { "type" => "string", "enum" => STATES },
                           "lifecycle" => Schemas.list({ "type" => "string",
                                                         "enum" => Declarations::LIBRARY_LIFECYCLE.map(&:to_s) }) })
        end

        def list
          Schemas.list(connection)
        end
        private_class_method :lifecycle, :install_cancel, :connection, :list
      end
    end
  end
end
