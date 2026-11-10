# frozen_string_literal: true

require_relative "coordinator"
require_relative "setup"
require_relative "schemas"
require_relative "setup_commands"
require_relative "export_registration"
require_relative "copy_participant"
require_relative "refuses"
require_relative "connection/commands"
require_relative "catalog_reads"

module PhComposer
  module Library
    FEATURE_ID = "ph_composer.library"
    TEXT = { "type" => "string", "minLength" => 1 }.freeze
    OBJECT = { "type" => "object" }.freeze
    GENERATION = { "type" => "integer", "minimum" => 1 }.freeze
    PAGE_EXAMPLE = { "provider_id" => "example", "kind" => "example_parts", "limit" => 100 }.freeze

    extend SchemaShapes

    module_function

    def selected_params
      object({
        "provider_id" => described(TEXT, "A configured library, by the id ph_composer.library.providers lists."),
        "kind" => described(TEXT, "The library kind, such as materials or frames; providers lists the kinds each " \
                                  "library serves."),
        "generation" => described(GENERATION, "The catalog generation the caller read. Omit it to use the " \
                                              "current one; a stale one is refused as library.catalog_stale.")
      }, :optional => ["generation"])
    end

    def page_params
      properties = selected_params.fetch("properties").merge("compact" => CatalogReads::COMPACT,
                                                             "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR)
      object(properties, :optional => %w[generation compact limit cursor])
    end

    COPY_EXAMPLE = { "provider_id" => "example", "kind" => "example_parts", "generation" => 1,
                     "library_id" => "synthetic", "record_id" => "one", "choice" => "create" }.freeze

    # A copy names the generation it reviewed: unlike a catalog read, it never falls back to the current one.
    def copy_params
      properties = selected_params.fetch("properties").merge(
        "generation" => described(GENERATION, "The catalog generation the row was read from, as catalog and " \
                                              "in_file answer it. Required; a stale one is refused as " \
                                              "library.catalog_stale."),
        "library_id" => described(TEXT, "The library holding the row, as the catalog row gives it."),
        "record_id" => described(TEXT, "The row's record id within that library."),
        "choice" => described({ "type" => "string", "enum" => %w[create keep_local use_library] },
                              "create copies the row as a new local record; keep_local reuses a reviewed local " \
                              "candidate unchanged; use_library replaces a reviewed candidate's values with the " \
                              "library's. Read the resolution first with in_file or a preview."),
        "local_id" => described(TEXT, "The reviewed local candidate for keep_local or use_library, from the " \
                                      "resolution's candidates. May be omitted when there is exactly one."),
        "expected_values" => described(OBJECT, "For use_library: the candidate's expected_values from the " \
                                               "resolution. Refused when the local record changed since."),
        "assignment" => described(OBJECT, "Optional: where the owning feature also assigns the copied record, " \
                                          "in that kind's assignment target shape, such as one Window Type " \
                                          "element side. describe the library kind (discover's library_kinds " \
                                          "names it) for that shape and its examples.")
      )
      object(properties, :optional => %w[local_id expected_values assignment])
    end

    def install(registry)
      feature = registry.feature(FEATURE_ID, :contract_version => 1)
      feature.library_provider(FileProvider::PROVIDER_KIND, :contract_version => 1, :kinds => ["*"]) do |published|
        kinds = published.library_kinds.values.map { |row| row.adapter.wire_kind }
        adapters = ->(kind) { published.library_kinds.values.find { |row| row.adapter.wire_kind == kind }&.adapter }
        Setup.file_providers(:kinds => kinds, :adapters => adapters)
      end
      feature.query("#{FEATURE_ID}.providers", :description => "Configured libraries without transport addresses.",
                                               :refuses => Refuses::PROVIDERS,
                                               :params => object({}), :result => Schemas.providers,
                                               :examples => [{}]) do |request|
        State.for(request.session).metadata(request.registry)
      end
      install_commands(feature)
      feature.snapshot_section("#{FEATURE_ID}.provider_catalogs", :query => "#{FEATURE_ID}.providers")
      install_catalog(feature)
      feature.action("#{FEATURE_ID}.copy",
                     :description => "Copy or reuse one library record with optional assignment.",
                     :refuses => Refuses::COPY,
                     :params => copy_params, :result => Schemas.copy_result, :undo_name => "Copy Library Record",
                     :side_effects => "Copies or replaces local definitions and optional assignments in one Undo step.",
                     :examples => [COPY_EXAMPLE]) do |request, proposal|
        Coordinator.copy(request, proposal)
      end
    end

    # Reading a configured library: its catalog pages, their resolution against local definitions,
    # and the setup command that loads it into session memory.
    def install_catalog(feature)
      feature.query("#{FEATURE_ID}.catalog", :description => "A bounded page of one immutable library catalog.",
                                             :refuses => Refuses::CATALOG,
                                             :params => page_params, :result => Schemas.page,
                                             :examples => [PAGE_EXAMPLE]) do |request|
        catalog_page(request, "#{FEATURE_ID}.catalog")
      end
      feature.query("#{FEATURE_ID}.in_file", :description => "Resolve catalog rows against local definitions.",
                                             :refuses => Refuses::IN_FILE,
                                             :params => page_params, :result => Schemas.page(:resolved => true),
                                             :examples => [PAGE_EXAMPLE]) do |request|
        in_file(request)
      end
      load = selected_params.fetch("properties").slice("provider_id", "kind").merge("compact" => CatalogReads::COMPACT)
      feature.setup_command("#{FEATURE_ID}.load",
                            :description => "Read a configured library into session memory.",
                            :refuses => Refuses::LOAD_COMMAND,
                            :params => object(load, :optional => ["compact"]),
                            :result => Schemas.summary,
                            :examples => [{ "provider_id" => "example", "kind" => "example_parts" }]) do |request|
        params = request.params
        summary = State.for(request.session).refresh(params.fetch("provider_id"), params.fetch("kind"),
                                                     request.registry).reject { |key, _value| key == "rows" }
        params["compact"] ? CatalogReads.compact_entry(summary) : summary
      end
      CatalogReads.install(feature)
    end

    def install_commands(feature)
      feature.proposal_participant("#{FEATURE_ID}.copy_into_proposal",
                                   :description => "Copy or reuse one library record, with optional assignment, " \
                                                   "inside the calling action's own proposal and Undo step.",
                                   :refuses => Refuses::COPY - Refusals::COMMON.fetch("participant"),
                                   :params => copy_params, :result => Schemas.copy_result,
                                   :examples => [COPY_EXAMPLE], &CopyParticipant.method(:call))
      SetupCommands.install(feature)
      Connection::Commands.install(feature)
      ExportRegistration.install(feature)
    end
    private_class_method :install_commands

    # A catalog generation is immutable, so a row's position in it is a stable page key. The cursor
    # is bound to the generation, and, for `in_file`, whose resolution reads local definitions, to
    # the Model revision as well. A page is cut by size; `prepare` turns its catalog rows into the rows
    # it answers, so only the page's own rows are resolved, and `compact` then summarizes them.
    def catalog_page(request, query, revision: nil, prepare: ->(rows) { rows })
      params = request.params
      entry = State.for(request.session).fetch(params.fetch("provider_id"), params.fetch("kind"), request.registry,
                                               :generation => params["generation"])
      rows = entry.fetch("rows").each_with_index.to_a
      answered = lambda do |sliced|
        page = prepare.call(sliced.map(&:first))
        params["compact"] ? page.map { |row| CatalogReads.compact_row(row) } : page
      end
      page, next_cursor = Pages.bounded(request, query, rows, :key => ->((_row, index)) { [index] },
                                                              :revision => [entry.fetch("generation"), revision],
                                                              :prepare => answered)
      header = params["compact"] ? CatalogReads.compact_entry(entry) : entry
      header.merge("rows" => page, "total" => rows.length, "next_cursor" => next_cursor)
    end

    def in_file(request)
      catalog_page(request, "#{FEATURE_ID}.in_file", :revision => request.revision,
                                                     :prepare => ->(rows) { resolved(request, rows) })
    end

    # Catalog rows, each with how it resolves against the local definitions of its kind.
    def resolved(request, rows)
      declaration = State.kind(request.params.fetch("kind"), request.registry)
      locals = CallbackInvoker.call(request, declaration, declaration.adapter.local_read, {}, :readonly => true)
      provider = State.for(request.session).provider(request.params.fetch("provider_id"), request.registry)
      rows.map do |row|
        mapped = Coordinator.map(declaration.adapter, row.fetch("snapshot"))
        source = Coordinator.source_identity(provider, row, request.params.fetch("kind"))
        row.merge("resolution" => Coordinator.resolve(declaration.adapter, source, mapped, locals))
      end
    end
  end
end
