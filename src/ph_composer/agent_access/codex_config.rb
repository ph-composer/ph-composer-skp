# frozen_string_literal: true

module PhComposer
  module AgentAccess
    # Reading and editing one PH-Composer entry in Codex's `config.toml`, as text: Codex has no command that
    # sets a header helper (0.167.0 `codex mcp add` takes `--url` and `--bearer-token-env-var` only), and a
    # TOML library would rewrite the whole file. Pure: ClientSetup reads and writes the file.
    #
    # An entry is the plain `[mcp_servers.<name>]` table. PH-Composer changes only its `url` line and its
    # token line, a helper or one inline Authorization bearer, and keeps every other byte of the file, so
    # settings the user added (`startup_timeout_sec`, `enabled`) stay. Anything it cannot read for certain
    # (a token given another way, a quoted key that could spell `url`, a multi-line value in the table, the
    # server defined with dotted keys or inline) is `other`: the user edits it, from the token-free block.
    #
    # Lines are read with their TOML context (`statement_starts`): a header or key counts only on a line that
    # starts outside any string, array or inline table, so table-like text inside another setting's
    # multi-line string or array is never taken for a table. A file whose strings or brackets do not close is
    # never edited.
    module CodexConfig
      SERVER_PREFIX = ClientConfig::SERVER_NAME
      SERVER_TABLE_HEADER = /\A\s*\[\s*mcp_servers\s*\.[^\[\]]+\]\s*(?:#.*)?\z/.freeze
      # Every PH-Composer entry named by a plain table header, default or profile.
      PROFILE_HEADER =
        /\A\s*\[\s*mcp_servers\s*\.\s*(["']?)(#{SERVER_PREFIX}(?:-[a-z0-9-]+)?)\1\s*\]\s*(?:#.*)?\z/.freeze
      STRING = /"(?:[^"\\]|\\.)*"/.freeze
      KEY_LINE = /\A(\s*)([A-Za-z0-9_-]+)\s*=\s*(.*?)\s*\z/.freeze
      VALUE = /\A(#{STRING})\s*(?:#.*)?\z/.freeze
      INLINE_BEARER = /\A\{\s*Authorization\s*=\s*"Bearer (\h{48})"\s*\}\s*(?:#.*)?\z/.freeze
      TOKEN_KEYS = %w[http_headers_helper http_headers].freeze
      # Keys that give a token or start a program another way: an entry holding one is the user's to edit.
      OTHER_KEYS = %w[bearer_token_env_var env_http_headers headers command args env cwd].freeze

      # One entry as read: where its table runs, its url, its token line and whether PH-Composer can edit it.
      Entry = Struct.new(:start, :stop, :url, :helper, :inline_token, :editable, keyword_init: true)

      module_function

      # The PH-Composer entries the file names by a plain table header.
      def server_names(text)
        statements(lines(text)).filter_map { |line| line.match(PROFILE_HEADER)&.[](2) }.uniq
      end

      # `"absent"`, `"configured"` (its url and helper are the ones given), `"outdated"` (PH-Composer's form
      # with another url or helper), `"inline"` (a token in the file) or `"other"`.
      def state(text, name, url_line, helper_line)
        return "other" unless utf8?(text) && balanced?(lines(text))

        all = lines(text)
        entry = entry(all, name)
        return names_server?(all, name) ? "other" : "absent" unless entry
        return "other" unless entry.editable
        return "inline" if entry.inline_token

        entry.url == value_of(url_line) && entry.helper == value_of(helper_line) ? "configured" : "outdated"
      end

      # The inline bearer token the entry carries, or nil. Only its digest leaves ClientSetup.
      def inline_token(text, name)
        entry(lines(text), name)&.inline_token
      end

      # The file with the entry's url and token lines replaced, or nil when it cannot be edited for certain.
      def edit(text, name, url_line, helper_line)
        return nil unless utf8?(text) && balanced?(lines(text))

        all = lines(text)
        entry = entry(all, name)
        return nil unless entry&.editable

        body = all[(entry.start + 1)...entry.stop].reject do |line|
          key = key_of(line)
          key == "url" || TOKEN_KEYS.include?(key)
        end
        header = all[entry.start]
        header = "#{header}\n" unless header.end_with?("\n")
        indent = header[/\A\s*/]
        (all[0...entry.start] + [header, "#{indent}#{url_line}\n", "#{indent}#{helper_line}\n"] + body +
          all[entry.stop..]).join
      end

      # The file with the block added after a blank line, or nil when a new table cannot follow what it has.
      def append(text, name, block)
        return nil unless utf8?(text) && balanced?(lines(text))

        all = lines(text)
        return nil if names_server?(all, name) || !appendable?(all)

        separator = text.empty? ? "" : (text.end_with?("\n") ? "\n" : "\n\n")
        "#{text.dup.force_encoding(Encoding::UTF_8)}#{separator}#{block}\n"
      end

      # The file's lines as text. A file that is not valid UTF-8, which TOML requires, is never edited, so
      # no byte of it is replaced; reading it scrubs what cannot be read.
      def lines(text)
        text.dup.force_encoding(Encoding::UTF_8).scrub.lines
      end

      def utf8?(text)
        text.dup.force_encoding(Encoding::UTF_8).valid_encoding?
      end

      # For each line, whether it starts outside every string, array and inline table, so a header or a key
      # on it is one; and, as one more element, whether the file ends that way. A table header line is not
      # scanned for brackets.
      def statement_starts(all)
        state = { :string => nil, :depth => 0, :broken => false }
        starts = all.map do |line|
          top = state[:string].nil? && state[:depth].zero?
          scan(line, state) unless top && line.lstrip.start_with?("[")
          top
        end
        starts << (state[:string].nil? && state[:depth].zero? && !state[:broken])
      end

      # Moves `state` through one line: an open multi-line string (three double or single quotes), the
      # bracket depth of a value, and whether a one-line string failed to close.
      def scan(line, state)
        index = 0
        while index < line.length
          if state[:string]
            close = string_end(line, index, state[:string])
            return unless close

            index = close + 3
            state[:string] = nil
            next
          end
          index = scan_value(line, index, state)
          return if index.nil?
        end
      end

      # One character outside a multi-line string; answers where to continue, or nil at a comment or a
      # one-line string that does not close.
      def scan_value(line, index, state)
        char = line[index]
        case char
        when "#" then return nil
        when '"', "'"
          if line[index, 3] == char * 3
            state[:string] = char * 3
            return index + 3
          end
          close = char == '"' ? string_end(line, index + 1, '"') : line.index("'", index + 1)
          unless close
            state[:broken] = true
            return nil
          end
          return close + 1
        when "[", "{" then state[:depth] += 1
        when "]", "}"
          state[:depth] -= 1
          state[:broken] = true if state[:depth].negative?
        end
        index + 1
      end

      # Where `quote` closes from `from`, skipping one a backslash escapes in a basic string.
      def string_end(line, from, quote)
        at = line.index(quote, from)
        at = line.index(quote, at + 1) while at && quote.start_with?('"') && line[0...at][/\\*\z/].length.odd?
        at
      end

      def balanced?(all)
        statement_starts(all).last
      end

      # The lines that start a statement: a table header or a key, never the rest of a longer value.
      def statements(all)
        starts = statement_starts(all)
        all.select.with_index { |_line, index| starts[index] }
      end

      # The plain table and what it holds. Its body runs to the next header of any table, its own sub-tables
      # included, which are left as they are.
      def entry(all, name)
        header = table_header(name)
        starts = statement_starts(all)
        start = all.each_index.find { |index| starts[index] && all[index].match?(header) }
        return nil unless start

        stop = ((start + 1)...all.length).find { |index| starts[index] && all[index].lstrip.start_with?("[") }
        stop ||= all.length
        # Every line of the table must start a statement: a value that runs onto the next line is not read.
        whole = ((start + 1)...stop).all? { |index| starts[index] }
        read_entry(all[(start + 1)...stop], start, stop, whole && defined_once?(all, name, start))
      end

      # Whether the plain table at `start` is the server's only definition: no second header, dotted key or
      # inline table names it, and none of its own sub-tables sets its url or a token, which would read as
      # set up while the file gives a token another way.
      def defined_once?(all, name, start)
        escaped = Regexp.escape(name)
        own = /\A\s*\[\s*mcp_servers\s*\.\s*(?:#{escaped}|"#{escaped}"|'#{escaped}')\s*\.\s*/
        sub_table = /#{own}("[^"]*"|'[^']*'|[A-Za-z0-9_-]+)/
        names = /(?:\A|[\s.\[{,])["']?#{escaped}["']?\s*[.=\]]/
        starts = statement_starts(all)
        all.each_with_index.none? do |line, index|
          next false if index == start || !starts[index] || !syntax(line).match?(names)

          segment = line[sub_table, 1]
          # A quoted segment with an escape could spell http_headers unseen, so it is not read as harmless.
          next true if segment.nil? || segment.include?("\\")

          segment = segment.delete("\"'")
          segment == "url" || (TOKEN_KEYS + OTHER_KEYS).include?(segment)
        end
      end

      # A statement line as TOML syntax: its comment cut and every string that is a value, not a key, emptied,
      # so a server name in a note or a comment is not taken for a definition.
      def syntax(line)
        line.gsub(/"(?:[^"\\]|\\.)*"|'[^']*'/) { |literal| $~.post_match.match?(/\A\s*[=.\]]/) ? literal : '""' }
            .sub(/#.*/m, "")
      end

      # The server's plain table header, its name bare or quoted.
      def table_header(name)
        escaped = Regexp.escape(name)
        /\A\s*\[\s*mcp_servers\s*\.\s*(?:#{escaped}|"#{escaped}"|'#{escaped}')\s*\]\s*(?:#.*)?\z/
      end

      # Editable only when every line is blank, a comment or one bare `key = value` (the caller has checked
      # that no value runs onto the next line): a dotted key such as `http_headers.Authorization` or a quoted
      # key could hide a url or a token.
      def read_entry(body, start, stop, single)
        found = Hash.new { |hash, key| hash[key] = [] }
        editable = single && body.all? do |line|
          text = line.strip
          text.empty? || text.start_with?("#") || line.match?(KEY_LINE)
        end
        body.each do |line|
          key = key_of(line)
          found[key] << line.match(KEY_LINE)[3] if key
        end
        editable &&= OTHER_KEYS.none? { |key| found.key?(key) } && found["url"].length <= 1 &&
                     TOKEN_KEYS.sum { |key| found[key].length } <= 1
        url = found["url"].first
        helper = found["http_headers_helper"].first
        inline = found["http_headers"].first
        editable &&= (url.nil? || url.match?(VALUE)) && (helper.nil? || helper.match?(VALUE)) &&
                     (inline.nil? || inline.match?(INLINE_BEARER))
        Entry.new(:start => start, :stop => stop, :url => url && url[VALUE, 1], :helper => helper && helper[VALUE, 1],
                  :inline_token => inline && inline[INLINE_BEARER, 1], :editable => editable ? true : false)
      end

      # The bare key a line sets, or nil for a blank line, a comment or a value line of a longer one.
      def key_of(line)
        return nil if line.lstrip.start_with?("#")

        line.match(KEY_LINE)&.[](2)
      end

      # The value of one `key = value` line PH-Composer writes.
      def value_of(line)
        line.split("=", 2).last.strip
      end

      # Whether any line that is not a comment has the server's name as a key, in whatever TOML form: a
      # table, a dotted key or an inline table. A config that does is never appended to, since a second
      # definition would make the whole file invalid for Codex. A path that merely contains the name, such
      # as a project folder, is not a key.
      def names_server?(all, name)
        key = /(?:\A|[\s.\[{,])["']?#{Regexp.escape(name)}["']?\s*[.=\]]/
        statements(all).any? { |line| syntax(line).match?(key) }
      end

      # Whether a new `[mcp_servers.<name>]` table can follow what the file has: no key or header holds an
      # escape, which could spell mcp_servers or the server's name unseen, and the root mcp_servers table,
      # if any, is opened only by plain headers of other servers' tables. An inline or dotted root
      # mcp_servers or an `[mcp_servers]` table cannot be extended this way, so the user adds the block
      # instead. Another table's own mcp_servers, as a plugin's, is not the root one.
      def appendable?(all)
        table = nil
        statements(all).none? do |line|
          text = line.lstrip
          next false if text.empty? || text.start_with?("#")

          if text.start_with?("[")
            table = text
            text.include?("\\") || (root_servers?(text.sub(/\A\[+/, "")) && !text.match?(SERVER_TABLE_HEADER))
          else
            key = text.split("=", 2).first
            key.include?("\\") || (table.nil? && root_servers?(key))
          end
        end
      end

      # Whether a key path starts at the root mcp_servers table.
      def root_servers?(path)
        path.lstrip.match?(/\A["']?mcp_servers["']?\s*(?:[.=\]]|\z)/)
      end
    end
  end
end
