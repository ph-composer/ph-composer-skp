# frozen_string_literal: true

module PhComposer
  module AgentAccess
    # Reading and editing one PH-Composer entry in Codex's `config.toml`, as text: Codex has no command that
    # sets a header helper (0.167.0 `codex mcp add` takes `--url` and `--bearer-token-env-var` only), and a
    # TOML library would rewrite the whole file. Pure: ClientSetup reads and writes the file.
    #
    # An entry is the plain `[mcp_servers.<name>]` table, its header written without an escape. PH-Composer
    # changes only its `url` line and its token line, a helper or one inline Authorization bearer, adds the
    # tool approval line when the table sets no approval of its own, and keeps every other byte of the file,
    # so settings the user added (`startup_timeout_sec`, `enabled`, another approval) stay. Anything it cannot
    # read for certain (a token given another way, a quoted key that could spell `url`, a multi-line value in
    # the table, the server named again by any other key, header or inline table) is `other`: the user edits
    # it, from the token-free block.
    #
    # The file is read as TOML statements (TomlStatements), keys decoded, so a header or key inside another
    # setting's string or array is never taken for a table, and a key that spells the server's name through
    # an escape is read as that name. A file outside the TOML subset TomlStatements reads is never edited.
    module CodexConfig
      SERVER_PREFIX = ClientConfig::SERVER_NAME
      # Every PH-Composer entry name, default or profile.
      PROFILE_NAME = /\A#{SERVER_PREFIX}(?:-[a-z0-9-]+)?\z/.freeze
      INLINE_BEARER = /\A\{\s*Authorization\s*=\s*"Bearer (\h{48})"\s*\}\z/.freeze
      TOKEN_KEYS = %w[http_headers_helper http_headers].freeze
      # Keys that give a token or start a program another way: an entry holding one is the user's to edit.
      OTHER_KEYS = %w[bearer_token_env_var env_http_headers headers command args env cwd].freeze

      # One entry as read: where its table runs (header line, and the line after its last), its url, its
      # token line, the lines PH-Composer replaces and whether PH-Composer can edit it.
      Entry = Struct.new(:start, :stop, :url, :helper, :inline_token, :approval, :owned_lines, :editable,
                         keyword_init: true)

      module_function

      # The PH-Composer entries the file names by a plain table header.
      def server_names(text)
        TomlStatements.read(text).statements.filter_map do |statement|
          name = statement.path.last
          name if plain_server_table?(statement) && name.match?(PROFILE_NAME)
        end.uniq
      end

      # `"absent"`, `"configured"` (its url and helper are the ones given and it sets a tool approval),
      # `"outdated"` (PH-Composer's form with another url or helper, or no approval), `"inline"` (a token in
      # the file) or `"other"`.
      def state(text, name, url_line, helper_line)
        reading = certain_reading(text)
        return "other" unless reading

        entry = entry(reading, name)
        return names_server?(reading.statements, name) ? "other" : "absent" unless entry
        return "other" unless entry.editable
        return "inline" if entry.inline_token

        current = entry.url == value_of(url_line) && entry.helper == value_of(helper_line) && entry.approval
        current ? "configured" : "outdated"
      end

      # The inline bearer token the entry carries, or nil. Only its digest leaves ClientSetup.
      def inline_token(text, name)
        entry(TomlStatements.read(text), name)&.inline_token
      end

      # The file with the entry's url and token lines replaced and, when it sets none, the approval line
      # added, or nil when it cannot be edited for certain.
      def edit(text, name, url_line, helper_line)
        reading = certain_reading(text)
        entry = reading && entry(reading, name)
        return nil unless entry&.editable

        all = lines(text)
        kept = ((entry.start + 1)...entry.stop).reject { |index| entry.owned_lines.include?(index) }
        body = kept.map { |index| all[index] }
        header = all[entry.start]
        header = "#{header}\n" unless header.end_with?("\n")
        indent = header[/\A\s*/]
        approval = entry.approval ? [] : ["#{indent}#{ClientConfig::CODEX_APPROVAL_LINE}\n"]
        (all[0...entry.start] + [header, "#{indent}#{url_line}\n"] + approval + ["#{indent}#{helper_line}\n"] +
          body + all[entry.stop..]).join
      end

      # The file with the block added after a blank line, or nil when a new table cannot follow what it has.
      def append(text, name, block)
        reading = certain_reading(text)
        return nil if reading.nil? || names_server?(reading.statements, name) || !appendable?(reading.statements)

        separator = text.empty? ? "" : (text.end_with?("\n") ? "\n" : "\n\n")
        "#{text.dup.force_encoding(Encoding::UTF_8)}#{separator}#{block}\n"
      end

      # The file's lines as text. A file that is not valid UTF-8, which TOML requires, is never edited, so
      # no byte of it is replaced; reading it scrubs what cannot be read.
      def lines(text)
        text.dup.force_encoding(Encoding::UTF_8).scrub.lines
      end

      # The file's statements when it is valid UTF-8 and read to its end, otherwise nil: such a file is never
      # edited and its entry reads `other`.
      def certain_reading(text)
        return nil unless text.dup.force_encoding(Encoding::UTF_8).valid_encoding?

        reading = TomlStatements.read(text)
        reading if reading.complete
      end

      # Whether a statement is a plain `[mcp_servers.<name>]` header: a server's own table, no escape in it.
      def plain_server_table?(statement)
        statement.kind == :table && !statement.escaped && statement.path.length == 2 &&
          statement.path.first == "mcp_servers"
      end

      # The plain table and what it holds. Its body runs to the next header of any table, its own sub-tables
      # included, which are left as they are.
      def entry(reading, name)
        statements = reading.statements
        at = statements.index { |statement| plain_server_table?(statement) && statement.path.last == name }
        return nil unless at

        header = statements[at]
        body = statements[(at + 1)..].take_while { |statement| statement.kind == :key_value }
        stop = statements[at + 1 + body.length]&.first_line || reading.line_count
        # Every statement of the table must be one bare `key = value` on one line: a dotted key such as
        # `http_headers.Authorization`, a quoted key or a value that runs onto the next line is not read.
        simple = body.all? { |statement| one_line_bare_key?(statement) }
        read_entry(body, header.first_line, stop, simple && defined_once?(statements, name, header))
      end

      def one_line_bare_key?(statement)
        statement.bare && statement.path.length == 1 && statement.first_line == statement.last_line
      end

      # Whether the plain table `header` is the server's only definition: no other header, key or inline table
      # names it, except its own sub-tables (`[mcp_servers.<name>.tools.x]`), and none of those sets its url or
      # a token, which would read as set up while the file gives a token another way.
      def defined_once?(statements, name, header)
        statements.none? do |statement|
          next false if statement.equal?(header) || own_sub_table?(statement, name)

          names?(statement, name)
        end
      end

      def own_sub_table?(statement, name)
        statement.kind == :table && statement.path.length > 2 && statement.path[0, 2] == ["mcp_servers", name] &&
          !(["url"] + TOKEN_KEYS + OTHER_KEYS).include?(statement.path[2])
      end

      # Whether a statement writes the server's name as a key, in whatever TOML form: in a header, a dotted
      # key or an inline table, bare, quoted or escaped. A value that merely holds the name, such as an array
      # item or a project folder, is not a key.
      def names?(statement, name)
        statement.path.include?(name) || statement.inner_keys.include?(name)
      end

      # Editable only when `simple` (the caller has checked that every statement is one bare `key = value` on
      # one line and the table is the server's only definition), no key gives a token or a program another way,
      # and the url and token values are in the form PH-Composer writes.
      def read_entry(body, start, stop, simple)
        found = body.select { |statement| statement.bare && statement.path.length == 1 }
                    .group_by { |statement| statement.path.first }
        url, helper, inline = %w[url http_headers_helper http_headers].map { |key| found.fetch(key, []).first }
        editable = simple && OTHER_KEYS.none? { |key| found.key?(key) } && found.fetch("url", []).length <= 1 &&
                   TOKEN_KEYS.sum { |key| found.fetch(key, []).length } <= 1
        editable &&= [url, helper].all? { |statement| statement.nil? || statement.value_kind == :basic } &&
                     (inline.nil? || inline.value.match?(INLINE_BEARER))
        Entry.new(:start => start, :stop => stop, :url => url&.value, :helper => helper&.value,
                  :inline_token => inline && inline.value[INLINE_BEARER, 1],
                  :approval => found.fetch(ClientConfig::CODEX_APPROVAL_KEY, []).first&.value,
                  :owned_lines => [url, helper, inline].compact.map(&:first_line), :editable => editable ? true : false)
      end

      # The value of one `key = value` line PH-Composer writes.
      def value_of(line)
        line.split("=", 2).last.strip
      end

      # Whether any statement names the server as a key (`names?`). A config that does is never appended to,
      # since a second definition would make the whole file invalid for Codex.
      def names_server?(statements, name)
        statements.any? { |statement| names?(statement, name) }
      end

      # Whether a new `[mcp_servers.<name>]` table can follow what the file has: the root mcp_servers table,
      # if any, is opened only by headers of other servers' tables. An inline or dotted root mcp_servers, an
      # `[mcp_servers]` table or an `[[mcp_servers...]]` array cannot be extended this way, so the user adds
      # the block instead. Another table's own mcp_servers, as a plugin's, is not the root one.
      def appendable?(statements)
        statements.none? do |statement|
          next false unless statement.path.first == "mcp_servers"

          case statement.kind
          when :table then statement.path.length == 1
          when :array_table then true
          else statement.table.empty?
          end
        end
      end
    end
  end
end
