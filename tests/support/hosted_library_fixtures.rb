# frozen_string_literal: true

# A version 2 hosted library with no network: a connection the test signs in by hand and a provider
# whose loads and use checks answer from `HostedLibraryFixtures.server`. It serves synthetic Materials.
module HostedLibraryFixtures
  PROVIDER_KIND = "test.hosted.library"
  PROVIDER_ID = "hosted.firm"
  LIFECYCLE = %i[connect disconnect reauthorize settings].freeze
  # Each callback declares one code of its own, so tests can tell a declared code from an undeclared one.
  REFUSES = { :begin_load => ["library.hosted_busy"], :poll_load => ["library.hosted_snapshot_gone"],
              :cancel_load => [], :authorize_use => ["library.hosted_entitlement_ended"],
              :connect => ["library.hosted_sign_in_refused"], :disconnect => [], :reauthorize => [],
              :settings => [] }.freeze

  # What the fake service answers. `use_answer` may be a callable, run inside `authorize_use`.
  class Server
    attr_accessor :response, :use_answer, :failures
    attr_reader :begun, :polled, :cancelled, :uses

    def initialize
      @response = nil
      @use_answer = "allowed"
      @failures = {}
      @begun = []
      @polled = []
      @cancelled = []
      @uses = []
    end

    def fail(callback)
      error = failures[callback]
      raise error if error
    end
  end

  class FakeConnection
    attr_reader :context, :calls

    def initialize(context)
      @context = context
      @state = "disconnected"
      @connection_id = nil
      @calls = []
    end

    def status
      { "state" => @state, "label" => @connection_id ? "Hosted test library: Synthetic firm" : "Hosted test library",
        "connection_id" => @connection_id }
    end

    def connect
      @calls << :connect
      HostedLibraryFixtures.server.fail(:connect)
      @state = "authorizing"
    end

    # What the extension's own sign-in does when its browser flow finishes.
    def finish_sign_in(connection_id = "connection-1")
      context.credentials.write(context.provider_kind, connection_id, "synthetic-refresh-#{connection_id}")
      @connection_id = connection_id
      @state = "connected"
      context.changed.call
    end

    def lose_authorization
      @state = "reauthorization_required"
      context.changed.call
    end

    def disconnect
      @calls << :disconnect
      context.credentials.delete(context.provider_kind, @connection_id) if @connection_id
      @state = "disconnected"
      @connection_id = nil
    end

    def reauthorize
      @calls << :reauthorize
      @state = "authorizing"
    end

    def settings
      @calls << :settings
    end
  end

  class FakeProvider
    def id
      PROVIDER_ID
    end

    def provider_kind
      PROVIDER_KIND
    end

    def label
      "Hosted test library"
    end

    def kinds
      ["materials"]
    end

    def begin_load(kind, connection:, operation:)
      server = HostedLibraryFixtures.server
      server.fail(:begin_load)
      server.begun << [kind, connection, operation]
    end

    def poll_load(operation)
      server = HostedLibraryFixtures.server
      server.polled << operation.id
      server.fail(:poll_load)
      server.response
    end

    def cancel_load(operation)
      HostedLibraryFixtures.server.cancelled << operation.id
    end

    def authorize_use(operation_id:, snapshot_id:, selection:)
      server = HostedLibraryFixtures.server
      server.uses << { "operation_id" => operation_id, "snapshot_id" => snapshot_id, "selection" => selection }
      server.fail(:authorize_use)
      answer = server.use_answer
      answer.respond_to?(:call) ? answer.call : answer
    end
  end

  # The extension's feature, installed the way a separate extension installs (Registry.install).
  module Feature
    def self.install(registry)
      feature = registry.feature("test.hosted", :contract_version => 1, :requires => ["ph_composer.library"])
      feature.library_provider(PROVIDER_KIND, :contract_version => 2, :kinds => ["materials"],
                                              :lifecycle => LIFECYCLE, :refuses => REFUSES,
                                              :connection => ->(context) { FakeConnection.new(context) }) do |_registry|
        [FakeProvider.new]
      end
    end
  end

  # A credential backend held in memory, keyed as the OS one is.
  class MemoryCredentials
    attr_reader :items

    def initialize
      @items = {}
    end

    def write(provider_id, connection_id, value)
      @items[[provider_id, connection_id]] = value
    end

    def read(provider_id, connection_id)
      @items[[provider_id, connection_id]]
    end

    def delete(provider_id, connection_id)
      !@items.delete([provider_id, connection_id]).nil?
    end
  end

  def self.server
    @server ||= Server.new
  end

  def self.reset
    @server = Server.new
  end

  def material(id, name: "Hosted insulation", conductivity: 0.035)
    { "id" => id, "name" => name, "conductivity_w_mk" => conductivity }
  end

  def hosted_response(rows: [material("rec-1")], revisions: nil, snapshot: "snap-1", library_revision: 7)
    batch_rows = rows.map do |snapshot_row|
      { "library_id" => "firm-lib", "library_name" => "Synthetic firm library",
        "record_id" => snapshot_row.fetch("id"), "snapshot" => snapshot_row, "wire_schema_version" => 1 }
    end
    revisions ||= batch_rows.to_h { |row| ["materials/firm-lib/#{row.fetch('record_id')}", 3] }
    batch = PhComposer::Library::Provider::Batch.new(:rows => batch_rows, :warnings => [], :unavailable => [],
                                                     :freshness => {})
    PhComposer::Library::Provider::RevisionedBatch.new(
      :batch => batch, :source_revisions => revisions,
      :snapshot => { "id" => snapshot, "library_revision" => library_revision, "projection_schema_version" => 1 }
    )
  end
end
