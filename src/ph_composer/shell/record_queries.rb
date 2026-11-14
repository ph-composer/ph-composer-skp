# frozen_string_literal: true

module PhComposer
  # The foundation's own read of stored records, and its one metadata write for them, registered through
  # the same interface a feature uses. Both serve every record kind, so a new kind is readable, and its
  # metadata writable, by every client without adding an operation; a kind whose owner writes its own
  # metadata (RecordKind#owner_writes_metadata?) is readable only.
  #
  # Pages are bound to the revision they were read at (context/CONTRACTS.md, "Public interface"), and
  # to the session, query and filter (shell/pages.rb): a cursor from anything else is refused. A page is
  # cut by size too, so a list reply fits the reply budget unless one row alone does not. Such a row reads
  # past with `fields` and `metadata` "summary", and `detail` reads any one of its values exactly, in
  # fragments (shell/fragments.rb), from the same public view the list answers and nothing else.
  module RecordQueries
    FEATURE_ID = "ph_composer.records"
    LIST = "#{FEATURE_ID}.list"
    DETAIL = "#{FEATURE_ID}.detail"
    UPDATE_METADATA = "#{FEATURE_ID}.update_metadata"
    # The parts of a record's view `detail` reaches; kind, id and schema_version are in every list row.
    PARTS = %w[values user_data extension_data extension_status].freeze
    # An unreadable row's message names what is wrong, which can quote stored text of any length; the row is
    # cut here so it never crowds out the page. records.detail on the record refuses with the whole message.
    MAX_MESSAGE = 512

    PARAMS = {
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["kind"],
      "properties" => {
        "kind" => { "type" => "string", "description" => "Record kind id, as listed by discovery." },
        "ids" => { "type" => "array", "items" => { "type" => "string" }, "maxItems" => Pages::MAXIMUM_LIMIT,
                   "description" => "Only these records." },
        "fields" => { "type" => "array", "items" => { "type" => "string" },
                      "description" => "Only these values of each record; all when absent." },
        "metadata" => { "type" => "string", "enum" => %w[full summary],
                        "description" => "full (the default): user_data, extension_data and extension_status as " \
                                         "stored. summary: none of them, but their sizes, digests and status " \
                                         "counts in metadata and each value's size in value_bytes; read any of " \
                                         "them whole with #{DETAIL}." },
        "limit" => Pages::LIMIT, "cursor" => Pages::CURSOR
      }
    }.freeze

    SIZE = { "type" => "integer", "minimum" => 0 }.freeze
    STATUSES = { "type" => "object", "additionalProperties" => SIZE,
                 "description" => "How many envelopes read each status, such as unavailable." }.freeze
    METADATA = SchemaShapes.object({
      "user_data" => SchemaShapes.with(Fragments::SUMMARY, "keys" => SIZE),
      "extension_data" => SchemaShapes.with(Fragments::SUMMARY, "namespaces" => SIZE, "statuses" => STATUSES)
    }, :description => "With metadata summary: what user_data, extension_data and extension_status hold, in " \
                       "place of them; read any of them whole with #{DETAIL}.").freeze

    RESULT = {
      "type" => "object",
      "required" => %w[records next_cursor unreadable units total],
      "properties" => {
        "records" => { "type" => "array", "items" => { "type" => "object" },
                       "description" => "Each record's kind, id, schema_version, values, and user_data, " \
                                        "extension_data and extension_status or, with metadata summary, " \
                                        "metadata and value_bytes." },
        "next_cursor" => Pages::NEXT_CURSOR,
        "unreadable" => { "type" => "array", "items" => { "type" => "object" } },
        "units" => { "type" => "object", "description" => "The SI unit of each numeric value, by field key." },
        "total" => Pages::TOTAL
      }
    }.freeze

    DETAIL_PARAMS = SchemaShapes.object({
      "kind" => { "type" => "string", "description" => "Record kind id, as listed by discovery." },
      "id" => { "type" => "string", "description" => "The record's id." },
      "path" => Fragments.path_param(PARTS, "[\"user_data\", \"notes\"], [\"values\", \"layers\", 0]"),
      "cursor" => Pages::CURSOR
    }, :optional => %w[cursor]).freeze

    DETAIL_RESULT = SchemaShapes.object({
      "kind" => { "type" => "string" }, "id" => { "type" => "string" },
      "type" => Fragments::TYPE,
      "fragment" => Fragments::FRAGMENT, "next_cursor" => Pages::NEXT_CURSOR
    }).freeze

    # One record of a registered catalog kind, as records.list names it.
    REFERENCE = SchemaShapes.object({
      "kind" => { "type" => "string", "description" => "Record kind id, as listed by discovery." },
      "id" => { "type" => "string", "description" => "The record's id." }
    }).freeze
    EXAMPLE_REFERENCE = { "kind" => "example.foundation.part", "id" => "prt_Ab12Cd34Ef56" }.freeze
    # A target's resolution and the Records::Metadata rules for its pre-image and payloads.
    UPDATE_REFUSES = %w[extension.invalid extension.migration_required extension.schema_unsupported
                        extension.unavailable record.unreadable reference.invalid target.changed
                        target.not_found target.wrong_kind validation.failed].freeze

    module_function

    def install(registry)
      feature = registry.feature(FEATURE_ID, :contract_version => Declarations::CONTRACT_VERSION)
      feature.query(LIST, :description => "Stored records of one kind, in id order, a bounded page at a time.",
                          :refuses => %w[query.cursor_expired query.limit_invalid],
                          :params => PARAMS, :result => RESULT,
                          :examples => [{ "kind" => "example.foundation.part", "limit" => 20 },
                                        { "kind" => "example.foundation.part", "fields" => [],
                                          "metadata" => "summary" }]) do |request|
        list(request)
      end
      feature.query(DETAIL, :description => "One value of one stored record, exactly, as canonical JSON text in " \
                                            "fragments: join every fragment's text in order, check its sha256 " \
                                            "and parse it. Pass next_cursor back for the next fragment.",
                            :refuses => %w[target.not_found record.unreadable query.cursor_expired],
                            :params => DETAIL_PARAMS, :result => DETAIL_RESULT,
                            :examples => [{ "kind" => "example.foundation.part", "id" => "prt_Ab12Cd34Ef56",
                                            "path" => %w[user_data] }]) do |request|
        detail(request)
      end
      feature.action(UPDATE_METADATA,
                     :description => "Replace the user_data and installed extension payloads of stored records of " \
                                     "any kind #{LIST} reads, guarded by the metadata last read. Values are not " \
                                     "changed; a kind's own update action edits them. A kind whose owner writes " \
                                     "its metadata itself refuses as target.wrong_kind.",
                     :refuses => UPDATE_REFUSES,
                     :params => SchemaShapes.metadata_updates(REFERENCE, Pages::MAXIMUM_LIMIT, :target => "record"),
                     :result => SchemaShapes.metadata_result(REFERENCE, :target => "record"),
                     :undo_name => "Edit Record Metadata",
                     :examples => [{ "updates" => [{ "reference" => EXAMPLE_REFERENCE,
                                                     "user_data" => { "example_org" => { "status" => "checked" } },
                                                     "expected_metadata" => { "user_data" => {},
                                                                              "extension_data" => {} } }] }],
                     :side_effects => "Rewrites only the named records' metadata.") do |request, proposal|
        update_metadata(request, proposal, request.params.fetch("updates"))
      end
    end

    def list(request)
      params = request.params
      kind = request.engine.kind(params.fetch("kind"))
      check_fields!(kind, params["fields"])
      ids = request.engine.ids(kind.id).sort
      ids &= params["ids"] if params.key?("ids")
      summary = params["metadata"] == "summary"
      entries = Hash.new { |built, id| built[id] = entry(request.engine, kind, id, params["fields"], summary) }
      size = ->(id) { JSON.generate(entries[id].last).bytesize + 1 }
      page, next_cursor = Pages.bounded(request, LIST, ids, :key => ->(id) { id }, :size => size)
      records, unreadable = page.map { |id| entries[id] }.partition(&:first)
      { "records" => records.map(&:last), "unreadable" => unreadable.map(&:last), "next_cursor" => next_cursor,
        "units" => units(kind), "total" => ids.length }
    end

    def detail(request)
      params = request.params
      kind = request.engine.kind(params.fetch("kind"))
      Fragments.check_start!(params.fetch("path"), PARTS)
      view = request.engine.view(kind.id, request.engine.find(kind.id, params.fetch("id")))
      { "kind" => kind.id, "id" => params.fetch("id") }
        .merge(Fragments.detail(request, DETAIL, view, params.fetch("path"), :parts => PARTS))
    end

    # Every target resolves before any is staged, so a missing record or an owner-written kind refuses
    # before anything is planned. The batch is one proposal and so one Undo entry; a refusal while staging
    # refuses the whole proposal, and an entry writing what is stored stages nothing, so a batch of them
    # commits nothing (context/CONTRACTS.md, "Records and extension data").
    def update_metadata(request, proposal, updates)
      engine = request.engine
      catalog = request.registry.catalog
      entries = Records::Metadata.distinct_updates(updates)
      entries.each do |update|
        kind_id, id = update.fetch("reference").values_at("kind", "id")
        check_owner!(engine.kind(kind_id))
        engine.find(kind_id, id)
      end
      rows = entries.map do |update|
        reference = update.fetch("reference")
        after = engine.propose_metadata_update(reference.fetch("kind"), reference.fetch("id"), proposal, update)
        { "reference" => reference, "extension_status" => Records::Metadata.status_map(after, catalog) }
      end
      { "updates" => rows }
    end

    def check_owner!(kind)
      return unless kind.owner_writes_metadata?

      raise CodedError.new("target.wrong_kind", "#{kind.label} metadata is written by its owner's own actions, " \
                                                "not #{UPDATE_METADATA}. Nothing was written.")
    end

    def check_fields!(kind, fields)
      unknown = Array(fields) - kind.fields.map(&:key)
      raise CodedError.new("params.invalid", "#{kind.label} has no field #{unknown.first}.") unless unknown.empty?
    end

    # [readable, row]: one record's view, projected, or why the engine cannot read it.
    def entry(engine, kind, id, fields, summary)
      view = engine.view(kind.id, engine.find(kind.id, id))
    rescue CodedError => error
      [false, { "id" => id, "code" => error.code, "message" => error.message[0, MAX_MESSAGE] }]
    else
      [true, row(view, fields, summary)]
    end

    def row(view, fields, summary)
      values = view.fetch("values")
      view["values"] = values.slice(*fields) if fields
      summary ? summarize(view, values) : view
    end

    # `view` without user_data, extension_data and extension_status, and with what they hold in `metadata`
    # and each of `values`' stored size in `value_bytes`: the summary row of any record view that carries
    # those three, a catalog record's or an entity record's.
    def summarize(view, values)
      user_data = view.delete("user_data")
      extensions = view.delete("extension_data")
      statuses = view.delete("extension_status").values.tally
      envelopes = Fragments.summary(extensions).merge("namespaces" => extensions.length, "statuses" => statuses)
      view.merge("metadata" => { "user_data" => Fragments.summary(user_data).merge("keys" => user_data.length),
                                 "extension_data" => envelopes },
                 "value_bytes" => values.transform_values { |value| CanonicalJson.generate(value).bytesize })
    end

    def units(kind)
      kind.fields.each_with_object({}) do |field, units|
        unit = field.schema["x-unit"]
        units[field.key] = unit if unit
      end
    end
  end
end
