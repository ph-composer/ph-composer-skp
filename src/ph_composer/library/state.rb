# frozen_string_literal: true

require_relative "admission"
require_relative "catalog"

module PhComposer
  module Library
    # Session-only catalog generations. Provider factories receive no host objects; private setup
    # stays in the configured provider. No row is fetched or copied during metadata discovery.
    class State
      V1_METHODS = %i[id provider_kind label kinds list freshness].freeze
      V2_METHODS = (%i[id provider_kind label kinds] + Declarations::LIBRARY_PROVIDER_CALLBACKS).freeze

      def self.for(session)
        session.feature_state("ph_composer.library.catalogs") { new(session) }
      end

      def initialize(session)
        @session = session
        @catalog = Catalog.new
        @copy_times = {}
        @loads = {}
      end

      # A preview and its guarded invocation share the gesture's copy timestamp. Revision-bound,
      # bounded session memory keeps it out of semantic fingerprints and the Model until commit.
      def copy_time(revision, identity)
        key = [revision, identity]
        @copy_times.delete_if { |(stored_revision, _identity), _time| stored_revision != revision }
        @copy_times.shift while @copy_times.length >= 128 && !@copy_times.key?(key)
        @copy_times[key] ||= Time.now.utc.iso8601(6)
      end

      def providers(registry)
        rows = registry.library_providers.values.flat_map do |declaration|
          instances = factory_instances(declaration, registry)
          valid = instances.is_a?(Array) &&
                  instances.all? { |provider| valid_provider?(provider, declaration, registry) }
          unless valid
            raise Error.new("library.provider_invalid", "The registered provider factory returned invalid metadata.")
          end

          instances
        end
        if rows.map(&:id).uniq.length != rows.length
          raise Error.new("library.provider_ambiguous", "Configured provider ids are ambiguous.")
        end

        rows
      end

      def provider(id, registry)
        providers(registry).find { |row| row.id == id } ||
          raise(Error.new("library.provider_unavailable", "The configured provider is unavailable."))
      end

      def metadata(registry)
        providers(registry).map do |provider|
          catalogs = provider.kinds.map do |kind|
            @catalog.fetch(provider.id, kind).slice(
              "kind", "generation", "state", "failure", "age_seconds", "freshness"
            )
          end
          row = { "id" => provider.id, "provider_kind" => provider.provider_kind, "label" => provider.label,
                  "kinds" => provider.kinds, "catalogs" => catalogs }
          connection = self.class.connection_declaration(provider.provider_kind, registry)
          row["connection"] = Connection::Manager.status(connection).slice("state", "label") if connection
          row
        end
      end

      def remove(provider_id)
        drop_loads { |(id, _kind), _load| id == provider_id }
        @catalog.remove(provider_id)
        @copy_times.clear
        nil
      end

      # Version 1 reads the catalog now. Version 2 starts a Load and answers `loading`; a load already
      # running for the same catalog is cancelled first, so its answer is never published.
      def refresh(id, kind, registry)
        selected = provider(id, registry)
        unless selected.kinds.include?(kind)
          raise Error.new("library.kind_unavailable", "This provider does not serve the requested kind.")
        end

        declaration = self.class.kind(kind, registry)
        connection = self.class.connection_declaration(selected.provider_kind, registry)
        return start_load(selected, connection, declaration.adapter, kind) if connection

        @catalog.refresh(selected, :kind => kind) do |batch|
          Admission.call(batch, :kind => kind, :adapter => declaration.adapter)
        end
      end

      # Cancels the running version 2 load of one catalog; false when none is running.
      def cancel_load(id, kind)
        load = @loads.delete([id, kind])
        load ? load.cancel : false
      end

      # A connection's generation moved on (Connection::Manager): its loads end unpublished and, when
      # `clear`, everything it loaded is dropped. Local copies are not touched.
      def connection_changed(provider_kind, clear:)
        drop_loads { |_key, load| load.provider_kind == provider_kind }
        @catalog.loaded_by(provider_kind).each { |id| @catalog.remove(id) } if clear
        nil
      end

      # What a published version 2 generation was read from (Catalog#transport), or nil.
      def transport(id, kind)
        @catalog.transport(id, kind)
      end

      # The session closed: no load may publish into it.
      def detach
        drop_loads { true }
      end

      def fetch(id, kind, registry, generation: nil)
        selected = provider(id, registry)
        unless selected.kinds.include?(kind)
          raise Error.new("library.kind_unavailable", "This provider does not serve the requested kind.")
        end

        @catalog.fetch(id, kind, :generation => generation)
      end

      def self.kind(wire_kind, registry)
        registry.library_kinds.values.find { |row| row.adapter.wire_kind == wire_kind } ||
          raise(Error.new("library.kind_unavailable", "The library kind is unavailable."))
      end

      # The version 2 declaration a provider kind names, or nil for a version 1 provider.
      def self.connection_declaration(provider_kind, registry)
        declaration = registry.library_providers[provider_kind]
        declaration if declaration&.contract_version == 2
      end

      private

      def start_load(provider, connection, adapter, kind)
        cancel_load(provider.id, kind)
        load = Connection::Load.new(:session => @session, :catalog => @catalog, :provider => provider,
                                    :declaration => connection, :adapter => adapter, :kind => kind)
        entry = load.start
        @loads[[provider.id, kind]] = load
        entry
      end

      def drop_loads
        @loads.select { |key, load| yield(key, load) }.each do |key, load|
          load.drop
          @loads.delete(key)
        end
      end

      def factory_instances(declaration, registry)
        declaration.factory.call(registry)
      rescue StandardError
        raise Error.new("library.provider_failed", "Provider metadata is unavailable."), :cause => nil
      end

      def valid_provider?(provider, declaration, registry)
        methods = declaration.contract_version == 2 ? V2_METHODS : V1_METHODS
        return false unless methods.all? { |name| provider.respond_to?(name) }
        return false unless provider.provider_kind == declaration.name
        return false unless provider.id.is_a?(String) && /\A[a-zA-Z0-9_.-]+\z/.match?(provider.id)
        return false unless provider.label.is_a?(String) && !provider.label.strip.empty?

        known = registry.library_kinds.values.map { |row| row.adapter.wire_kind }
        served = declaration.kinds == ["*"] ? known : declaration.kinds
        kinds = provider.kinds
        kinds.is_a?(Array) && !kinds.empty? && kinds.uniq == kinds && (kinds - served).empty?
      rescue StandardError
        false
      end
    end
  end
end
