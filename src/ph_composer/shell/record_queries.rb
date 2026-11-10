# frozen_string_literal: true

module PhComposer
  # The foundation's own read of stored records, registered through the same interface a feature uses.
  # It serves every record kind, so a new kind is readable by every client without adding a query.
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
    # The parts of a record's view `detail` reaches; kind, id and schema_version are in every list row.
    PARTS = %w[values user_data extension_data extension_status].freeze
    MAX_PATH = 32
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
      "path" => { "type" => "array", "minItems" => 1, "maxItems" => MAX_PATH,
                  "items" => { "type" => %w[string integer] },
                  "description" => "Keys and array indexes into the record as #{LIST} answers it, starting at " \
                                   "#{PARTS.join(', ')}: [\"user_data\", \"notes\"], [\"values\", \"layers\", 0]." },
      "cursor" => Pages::CURSOR
    }, :optional => %w[cursor]).freeze

    DETAIL_RESULT = SchemaShapes.object({
      "kind" => { "type" => "string" }, "id" => { "type" => "string" },
      "type" => { "type" => "string", "enum" => %w[object array string number boolean null],
                  "description" => "The JSON type of the value at path; a stored null or false is a value." },
      "fragment" => Fragments::FRAGMENT, "next_cursor" => Pages::NEXT_CURSOR
    }).freeze

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
      path = params.fetch("path")
      unless PARTS.include?(path.first)
        raise CodedError.new("params.invalid", "A path starts at #{PARTS.join(', ')}.")
      end

      value = at(request.engine.view(kind.id, request.engine.find(kind.id, params.fetch("id"))), path)
      fragment, next_cursor = Fragments.read(request, DETAIL, value)
      { "kind" => kind.id, "id" => params.fetch("id"), "type" => json_type(value), "fragment" => fragment,
        "next_cursor" => next_cursor }
    end

    # The value `path` names in `view`; a key or index naming nothing refuses, so absent is never null.
    def at(view, path)
      path.each_with_index.reduce(view) do |value, (step, index)|
        found = value.is_a?(Hash) && step.is_a?(String) && value.key?(step)
        found ||= value.is_a?(Array) && step.is_a?(Integer) && step.between?(0, value.length - 1)
        unless found
          raise CodedError.new("target.not_found", "Nothing is stored at #{JSON.generate(path[0..index])[0, 200]}.")
        end

        value[step]
      end
    end

    def json_type(value)
      case value
      when Hash then "object"
      when Array then "array"
      when String then "string"
      when Numeric then "number"
      when true, false then "boolean"
      else "null"
      end
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
      return view unless summary

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
