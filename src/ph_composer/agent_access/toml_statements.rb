# frozen_string_literal: true

module PhComposer
  module AgentAccess
    # The statements of a TOML file, read for CodexConfig: each table header, array-of-tables header and
    # key/value pair, with its key decoded and the lines it spans. It reads the TOML subset a Codex config is
    # written in, and reads it with certainty: bare, basic and literal keys (basic-string escapes decoded),
    # dotted keys, table and array-of-tables headers, basic, literal and multi-line strings, arrays and inline
    # tables, which may hold newlines and comments, and comments. Any other value (a number, boolean or date)
    # is read as one bare word. Values are read only as far as where they end, so an escape inside a value
    # string is not checked, and nothing else is: two tables or keys of one name read without complaint.
    #
    # The read stops at the first thing outside that subset, such as a string that does not close or a key
    # escape TOML does not define, and the reading is then not `complete`: the caller treats the file as one it
    # cannot read for certain. No gem is needed, so the shipped extension installs none.
    module TomlStatements
      # One statement. `kind` is `:table`, `:array_table` or `:key_value`. `table` is the path of the table
      # a key/value pair sits in (empty at the root), `path` the key the statement writes, decoded. `bare` is
      # true when every segment of that key is a bare word, `escaped` when one is a basic string holding an
      # escape. A key/value pair also carries its value's source text, its `value_kind` (`:basic`, `:literal`,
      # `:multiline_basic`, `:multiline_literal`, `:array`, `:inline_table` or `:scalar`) and `inner_keys`,
      # every key segment an inline table inside the value sets, decoded. Lines count from zero.
      Statement = Struct.new(:kind, :table, :path, :bare, :escaped, :first_line, :last_line, :value, :value_kind,
                             :inner_keys, keyword_init: true)
      # The statements read, whether the read reached the end of the file, and how many lines the file has.
      Reading = Struct.new(:statements, :complete, :line_count, keyword_init: true)

      module_function

      # Reads `text` as UTF-8; bytes that are not valid UTF-8 are read as replacement characters.
      def read(text)
        Reader.new(text.dup.force_encoding(Encoding::UTF_8).scrub).read
      end

      # Reads one file, byte by byte: every character TOML syntax uses is ASCII, so a multi-byte character can
      # only sit inside a string or a comment.
      class Reader
        # One segment of a key: its name decoded, its `form` (`:bare`, `:basic` or `:literal`) and whether a
        # basic string spelled it with an escape.
        Segment = Struct.new(:name, :form, :escaped, keyword_init: true)

        BARE_KEY = /\G[A-Za-z0-9_-]+/.freeze
        # A number, boolean or date, with the space TOML allows between a date and its time.
        SCALAR = /\G(?:\d{4}-\d{2}-\d{2} (?=\d{2}:))?[A-Za-z0-9_+.:-]+/.freeze
        ESCAPES = { "b" => "\b", "t" => "\t", "n" => "\n", "f" => "\f", "r" => "\r", '"' => '"', "\\" => "\\" }.freeze
        UNICODE_DIGITS = { "u" => 4, "U" => 8 }.freeze
        # Arrays and inline tables are read by recursion, so a value nested deeper than this ends the read
        # rather than the Ruby stack. A Codex config nests a few levels.
        MAX_DEPTH = 64

        def initialize(text)
          @text = text.b
          @at = 0
          @newlines = []
          @text.each_byte.with_index { |byte, index| @newlines << index if byte == 10 }
          @table = []
          @statements = []
          @depth = 0
        end

        def read
          # `unreadable` throws at the first thing outside the subset, and the read ends there.
          complete = catch(:unreadable) do
            read_statements
            true
          end
          line_count = @newlines.length + (@text.empty? || @text.end_with?("\n") ? 0 : 1)
          Reading.new(:statements => @statements, :complete => complete, :line_count => line_count)
        end

        private

        def read_statements
          loop do
            skip_blank
            break if @at >= @text.length

            @statements << (char == "[" ? header : key_value)
            end_of_line
          end
        end

        def header
          line = line_at(@at)
          kind = @text[@at, 2] == "[[" ? :array_table : :table
          @at += kind == :array_table ? 2 : 1
          segments = key
          expect(kind == :array_table ? "]]" : "]")
          @table = segments.map(&:name)
          statement(kind, [], segments, line, line)
        end

        def key_value
          line = line_at(@at)
          segments = key
          expect("=")
          skip_space
          from = @at
          @inner_keys = []
          value_kind = value
          statement(:key_value, @table, segments, line, line_at(@at - 1),
                    :value => decode(@text[from...@at]), :value_kind => value_kind, :inner_keys => @inner_keys)
        end

        def statement(kind, table, segments, first_line, last_line, extra = {})
          fields = { :kind => kind, :table => table, :path => segments.map(&:name),
                     :bare => segments.all? { |segment| segment.form == :bare },
                     :escaped => segments.any?(&:escaped), :first_line => first_line, :last_line => last_line,
                     :inner_keys => [] }
          Statement.new(**fields.merge(extra))
        end

        # A dotted key, as its segments: spaces may stand around each dot.
        def key
          segments = [key_segment]
          loop do
            skip_space
            break unless char == "."

            @at += 1
            segments << key_segment
          end
          skip_space
          segments
        end

        def key_segment
          skip_space
          case char
          when '"'
            unreadable if @text[@at, 3] == '"""'
            basic_key
          when "'"
            unreadable if @text[@at, 3] == "'''"
            close = close_on_line("'", @at + 1)
            name = decode(@text[(@at + 1)...close])
            @at = close + 1
            Segment.new(:name => name, :form => :literal, :escaped => false)
          else
            match = @text.match(BARE_KEY, @at) || unreadable
            @at = match.end(0)
            Segment.new(:name => decode(match[0]), :form => :bare, :escaped => false)
          end
        end

        # A basic-string key, its escapes decoded. An escape TOML does not define ends the read.
        def basic_key
          @at += 1
          name = String.new
          escaped = false
          loop do
            found = char
            unreadable if found.nil? || found == "\n"
            @at += 1
            break if found == '"'

            escaped ||= found == "\\"
            name << (found == "\\" ? escape : found)
          end
          Segment.new(:name => decode(name), :form => :basic, :escaped => escaped)
        end

        def escape
          found = char
          @at += 1
          return ESCAPES[found] if ESCAPES.key?(found)

          digits = UNICODE_DIGITS[found] || unreadable
          hex = @text[@at, digits].to_s
          unreadable unless hex.match?(/\A\h{#{digits}}\z/)
          @at += digits
          code = hex.to_i(16)
          unreadable if code > 0x10FFFF || (0xD800..0xDFFF).cover?(code)
          [code].pack("U").b
        end

        # Reads one value and answers its kind. Values are not decoded: only the keys an inline table sets are.
        def value
          case char
          when '"' then @text[@at, 3] == '"""' ? multiline_string('"') : basic_string
          when "'" then @text[@at, 3] == "'''" ? multiline_string("'") : literal_string
          when "[" then array
          when "{" then inline_table
          else
            match = @text.match(SCALAR, @at) || unreadable
            @at = match.end(0)
            :scalar
          end
        end

        # A one-line basic string: a backslash escapes the character after it, unless that ends the line.
        def basic_string
          @at += 1
          loop do
            found = char
            unreadable if found.nil? || found == "\n"
            @at += 1
            return :basic if found == '"'

            @at += 1 if found == "\\" && char != "\n"
          end
        end

        def literal_string
          @at = close_on_line("'", @at + 1) + 1
          :literal
        end

        # A multi-line string: it closes at the first three quotes a backslash does not escape, and up to two
        # more quotes after them still belong to the string.
        def multiline_string(quote)
          @at += 3
          until @text[@at, 3] == quote * 3
            found = char || unreadable
            @at += found == "\\" && quote == '"' ? 2 : 1
          end
          @at += 3
          2.times { @at += 1 if char == quote }
          quote == '"' ? :multiline_basic : :multiline_literal
        end

        def array
          @at += 1
          items("]") { value }
          :array
        end

        def inline_table
          @at += 1
          items("}") do
            @inner_keys.concat(key.map(&:name))
            expect("=")
            skip_space
            value
          end
          :inline_table
        end

        # The items of an array or inline table up to `close`, comma separated with an optional trailing comma.
        # Newlines and comments may stand between them.
        def items(close)
          @depth += 1
          unreadable if @depth > MAX_DEPTH
          loop do
            skip_blank
            break if char == close

            yield
            skip_blank
            break unless char == ","

            @at += 1
          end
          expect(close)
          @depth -= 1
        end

        # After a statement, only spaces and a comment may stand before the line ends.
        def end_of_line
          skip_space
          skip_comment
          return if @at >= @text.length

          @at += 1 if @text[@at, 2] == "\r\n"
          expect("\n")
        end

        def skip_blank
          loop do
            skip_space
            skip_comment
            break unless @text[@at] == "\n" || @text[@at, 2] == "\r\n"

            @at += @text[@at] == "\n" ? 1 : 2
          end
        end

        def skip_space
          @at += 1 while char == " " || char == "\t"
        end

        def skip_comment
          return unless char == "#"

          @at = @text.index("\n", @at) || @text.length
          @at -= 1 if @text[@at - 1] == "\r"
        end

        # Where `quote` closes a one-line string that starts at `from`.
        def close_on_line(quote, from)
          close = @text.index(quote, from) || unreadable
          newline = @text.index("\n", from)
          unreadable if newline && newline < close
          close
        end

        def expect(text)
          unreadable unless @text[@at, text.length] == text
          @at += text.length
        end

        def char
          @text[@at]
        end

        # The line, from zero, that holds byte `index`.
        def line_at(index)
          @newlines.bsearch_index { |newline| newline >= index } || @newlines.length
        end

        def decode(bytes)
          bytes.dup.force_encoding(Encoding::UTF_8)
        end

        def unreadable
          throw :unreadable, false
        end
      end
    end
  end
end
