# frozen_string_literal: true

module PhComposer
  module AgentAccess
    # The connection's `discover` beyond its compact index (context/AGENT_INTERFACE.md, "Discover before
    # acting"): bounded sections of what `API.discover` answers in process, each page small enough for one
    # reply however many features are installed. Every row comes from the registry through
    # `API.discover`, so an outside feature's kinds, extensions and library kinds appear here with no
    # change to this file. A list cursor is bound to its section, its owner filter and the registry
    # identity, a digest of everything registered: a cursor read after an install changed what is
    # registered is refused rather than mixing two registries.
    module Discovery
      OPERATION_KINDS = {
        "queries" => "query", "view_commands" => "view_command", "setup_commands" => "setup_command",
        "file_exports" => "file_export", "actions" => "action"
      }.freeze
      LISTS = %w[operations features record_kinds reference_targets extensions library_kinds].freeze
      SECTIONS = (LISTS + %w[refusals contracts guide]).freeze
      # The compact index lists every operation's name while it fits under this; past it, counts by owner;
      # past that too, totals only, with the features and operations left to their sections.
      INDEX_BYTES = 20 * 1024
      # A row's text longer than this is cut in a list page, and the row names it in `truncated`, so one
      # registration with a long description cannot make a page larger than a reply.
      ROW_TEXT_BYTES = 1024
      PAGE_KEYS = %w[limit cursor].freeze

      module_function

      # What the registry holds, apart from the open sessions: equal while nothing is installed or removed.
      def registry_identity(document)
        CanonicalJson.digest(document.reject { |key, _value| key == "sessions" })
      end

      # The compact index: `document` with its sessions already filtered for the caller's token.
      def index(document, keys)
        operations = operation_index(document)
        page = document.slice(*keys).merge("registry" => registry_identity(document),
                                           "sections" => sections(document), "guide" => guide_pointer,
                                           "operations" => operations, "next" => index_next)
        return page if JSON.generate(page).bytesize <= INDEX_BYTES

        page = page.reject { |key, _value| key == "operations" }.merge(
          "operation_counts" => operations.transform_values { |owners| owners.transform_values(&:length) },
          "next" => "#{index_next} Too many operations are installed to name here; page them with section " \
                    "operations."
        )
        return page if JSON.generate(page).bytesize <= INDEX_BYTES

        page.reject { |key, _value| %w[operation_counts features].include?(key) }.merge(
          "next" => "#{index_next} Too many features are installed to list here; page them with section " \
                    "features, and their operations with section operations."
        )
      end

      def index_next
        "Read the operating guide first: discover with section guide, then with its topic. Page an " \
          "owner's operations with section operations and owner, then describe one by name for its params " \
          "and result. Sections: #{SECTIONS.join(', ')}."
      end

      def guide_pointer
        Guide.version.merge("topics" => Guide::TOPICS.length,
                            "read" => { "tool" => "discover", "arguments" => { "section" => "guide" } })
      end

      def sections(document)
        LISTS.map { |name| { "name" => name, "total" => rows(document, name, nil).length } } +
          %w[refusals contracts guide].map { |name| { "name" => name } }
      end

      def operation_index(document)
        OPERATION_KINDS.keys.to_h do |kind|
          [kind, document.fetch(kind).group_by { |entry| entry["owner"] }
                         .transform_values { |entries| entries.map { |entry| entry["name"] } }]
        end
      end

      # Section arguments sent without a section would otherwise be ignored and answered with the index.
      def check_unsectioned(arguments)
        stray = %w[topic limit cursor] & arguments.keys
        return if stray.empty?

        raise CodedError.new("params.invalid", "#{stray.join(' and ')} needs section; discover lists the sections.")
      end

      # One section page. `arguments` are the tool's, already checked against its input schema.
      def section(document, arguments)
        name = arguments.fetch("section")
        check_arguments(name, arguments)
        identity = registry_identity(document)
        case name
        when "refusals" then refusals(document)
        when "contracts" then contracts(document)
        when "guide" then arguments["topic"] ? Guide.topic(arguments["topic"]) : Guide.index
        else list(document, name, arguments, identity)
        end.merge("section" => name, "registry" => identity)
      end

      def check_arguments(name, arguments)
        stray = []
        stray << "topic" if arguments.key?("topic") && name != "guide"
        stray << "owner" if arguments.key?("owner") && name != "operations"
        stray.concat(PAGE_KEYS & arguments.keys) unless LISTS.include?(name)
        return if stray.empty?

        raise CodedError.new("params.invalid", "Section #{name} takes no #{stray.join(' or ')}.")
      end

      def rows(document, name, owner)
        found = case name
                when "operations"
                  OPERATION_KINDS.flat_map do |key, kind|
                    document.fetch(key).select { |entry| owner.nil? || entry["owner"] == owner }
                            .map { |entry| { "kind" => kind }.merge(entry) }
                  end
                else document.fetch(name)
                end
        found.map { |row| bounded_row(row) }
      end

      # `row` with each text value over ROW_TEXT_BYTES cut there; `describe` answers the whole declaration.
      def bounded_row(row)
        long = row.select { |_key, value| value.is_a?(String) && value.bytesize > ROW_TEXT_BYTES }.keys
        return row if long.empty?

        cut = long.to_h { |key| [key, row.fetch(key).byteslice(0, ROW_TEXT_BYTES).scrub("")] }
        row.merge(cut).merge("truncated" => long)
      end

      def list(document, name, arguments, identity)
        owner = arguments["owner"]
        if owner && document.fetch("features").none? { |feature| feature["id"] == owner }
          raise CodedError.new("params.invalid", "There is no feature #{owner[0, 80].inspect}; discover lists them.")
        end

        all = rows(document, name, owner)
        binding = { "section" => name, "owner" => owner, "registry" => identity }
        start = position(binding, arguments["cursor"], all.length)
        limit = Pages.limit(arguments)
        page = fitted(all.drop(start).first(limit))
        after = start + page.length
        result = { "rows" => page, "total" => all.length,
                   "next_cursor" => after < all.length ? cursor(binding, after) : nil }
        result["owner"] = owner if owner
        result["statuses"] = Records::Extension::STATUS_MEANINGS if name == "extensions"
        result
      end

      # The longest run of whole rows under the page budget; one row larger than it comes alone.
      def fitted(rows)
        total = 2
        rows.take_while.with_index do |row, index|
          total += JSON.generate(row).bytesize + 1
          index.zero? || total <= Pages::MAX_PAGE_BYTES
        end
      end

      def cursor(binding, after)
        [JSON.generate(binding.merge("after" => after))].pack("m0")
      end

      # The row a cursor resumes at. Only a cursor this section issued for the same registry is taken.
      def position(binding, cursor, total)
        return 0 if cursor.nil?

        decoded = JSON.parse(cursor.unpack1("m0"))
        after = decoded.is_a?(Hash) ? decoded["after"] : nil
        raise ArgumentError, "not a cursor" unless after.is_a?(Integer) && after.positive?

        unless decoded["section"] == binding["section"] && decoded["owner"] == binding["owner"]
          raise CodedError.new("params.invalid", "That cursor belongs to another section or owner.")
        end
        unless decoded["registry"] == binding["registry"]
          raise CodedError.new("query.cursor_expired", "What is installed changed since that page; start again " \
                                                       "from the first page.")
        end
        raise ArgumentError, "past the end" unless after < total

        after
      rescue JSON::ParserError, ArgumentError
        raise CodedError.new("params.invalid", "That cursor is not one discover issued.")
      end

      # The common refusal sets, what each of their codes means, and the authority they follow.
      def refusals(document)
        codes = document.fetch("common_refusals").values.flatten.uniq.sort
        { "sets" => document.fetch("common_refusals"),
          "codes" => codes.map { |code| { "code" => code, "description" => Refusals::MEANINGS[code] } },
          "documentation" => document.fetch("refusal_documentation") }
      end

      def contracts(document)
        document.slice("api", "extension", "contract_versions", "capabilities", "tasks", "schemas")
      end
    end
  end
end
