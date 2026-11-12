# frozen_string_literal: true

require_relative "test_helper"

# The TOML statements CodexConfig reads Codex's config.toml through (context/AGENT_INTERFACE.md,
# "User-controlled local access"): keys decoded in every form, values skipped whole however they span lines,
# and a read that stops, not complete, at the first thing outside the subset. The issue cases each name the
# line-scanner finding they reproduce.
class AgentAccessTomlStatementsTest < PhComposerTestCase
  TomlStatements = PhComposer::AgentAccess::TomlStatements

  def test_keys_are_decoded_in_every_form_with_their_table_and_lines
    reading = TomlStatements.read("a = 1\n[ t . \"q\\u0062\" ]\nb.'c' = \"x\"\n[[arr]]\n\"\" = 2\n")

    assert reading.complete
    assert_equal 5, reading.line_count
    assert_equal [[:key_value, [], ["a"], true, false, 0], [:table, [], %w[t qb], false, true, 1],
                  [:key_value, %w[t qb], %w[b c], false, false, 2], [:array_table, [], ["arr"], true, false, 3],
                  [:key_value, ["arr"], [""], false, false, 4]],
                 reading.statements.map { |statement|
                   statement.to_h.values_at(:kind, :table, :path, :bare, :escaped, :first_line)
                 }
    assert_equal [["1", :scalar], ["\"x\"", :basic], ["2", :scalar]],
                 reading.statements.select(&:value).map { |statement| [statement.value, statement.value_kind] }
  end

  # #470: a sub-table that names the server quoted or through an escape decodes to the server's own path.
  def test_a_quoted_or_escaped_server_segment_decodes_to_the_server_name
    ["[mcp_servers.\"ph-composer\".http_headers]\n", "[mcp_servers.\"ph\\u002Dcomposer\".http_headers]\n",
     "[mcp_servers.'ph-composer'.http_headers]\n"].each do |text|
      statement = only_statement(text)
      assert_equal %w[mcp_servers ph-composer http_headers], statement.path, text
      assert_equal text.include?("\\"), statement.escaped, text
    end
  end

  # #471: a string in an array is a value, never a key.
  def test_a_string_in_an_array_sets_no_key
    statement = only_statement("disabled_tools = [\"ph-composer\", 'ph-composer']\n")

    assert_equal [["disabled_tools"], :array, []], [statement.path, statement.value_kind, statement.inner_keys]
  end

  # #477: a server defined only through an escaped name reads as that name, in a header, a dotted key or an
  # inline table.
  def test_an_escaped_server_name_decodes_wherever_it_is_written
    assert_equal %w[mcp_servers ph-composer], only_statement("[mcp_servers.\"ph\\u002Dcomposer\"]\n").path
    assert_equal %w[mcp_servers ph-composer url],
                 only_statement("mcp_servers.\"ph\\U0000002Dcomposer\".url = \"x\"\n").path
    assert_equal %w[other ph-composer url],
                 only_statement("mcp_servers = { other = {}, \"ph\\u002Dcomposer\" = { url = \"x\" } }\n").inner_keys
  end

  # #482: a literal string has no escapes, and a basic one's escape decodes to what it spells.
  def test_a_backslash_in_a_literal_key_is_kept_and_a_basic_escape_is_decoded
    literal = only_statement("[projects.'C:\\Users\\x']\n")
    escaped = only_statement("[profiles.\"a\\tb\"]\n")

    assert_equal [["projects", "C:\\Users\\x"], false], [literal.path, literal.escaped]
    assert_equal [["profiles", "a\tb"], true], [escaped.path, escaped.escaped]
  end

  # #489: a comment inside a multi-line array ends only its own line, so the key after it is read.
  def test_a_comment_inside_a_multi_line_array_ends_only_its_line
    text = "mcp_servers = { other = { args = [ # c\n\"x\"] }, \"ph\\u002Dcomposer\" = { url = \"x\" } }\nz = 1\n"
    reading = TomlStatements.read(text)

    assert reading.complete
    first, last = reading.statements
    assert_equal [%w[other args ph-composer url], 0, 1], [first.inner_keys, first.first_line, first.last_line]
    assert_equal [["z"], 2], [last.path, last.first_line]
  end

  def test_table_like_text_inside_strings_and_comments_is_skipped
    text = "a = \"\"\"\n[mcp_servers.ph-composer]\\\n  \"\"\"\"\nb = '''\n[x]'''''\n" \
           "c = \"say \\\"[y]\\\"\" # [z]\r\nd = 1979-05-27 07:32:00Z\ne = [\n  { k = 1 }, # [w]\n]\n"
    reading = TomlStatements.read(text)

    assert reading.complete
    assert_equal [["a", 0, 2], ["b", 3, 4], ["c", 5, 5], ["d", 6, 6], ["e", 7, 9]],
                 reading.statements.map { |line| [line.path.first, line.first_line, line.last_line] }
    assert_equal [:multiline_basic, :multiline_literal, :basic, :scalar, :array],
                 reading.statements.map(&:value_kind)
    assert_equal ["k"], reading.statements.last.inner_keys
  end

  def test_anything_outside_the_subset_ends_the_read_incomplete
    ["a = \"open\n", "a = 'open\n", "a = \"\"\"open\n", "a = [1,\n", "a = { b = 1\n", "\"\\q\" = 1\n",
     "\"\\uD800\" = 1\n", "\"\\u12\" = 1\n", "\"\"\"k\"\"\" = 1\n", "[t] x\n", "a 1\n", "a = 1 b = 2\n", "a = \n",
     "a = \"x\\\n\"\n", "[t\n", "\xEF\xBB\xBFa = 1\n", "a = 1\rb = 2\n"].each do |text|
      refute TomlStatements.read(text).complete, text.inspect
    end
    reading = TomlStatements.read("[a]\nb = 1\nc = \"open\n[d]\n")
    assert_equal [%w[a], %w[b]], reading.statements.map(&:path), "the statements before the stop are kept"
  end

  private

  def only_statement(text)
    reading = TomlStatements.read(text)
    assert reading.complete, text
    assert_equal 1, reading.statements.length, text
    reading.statements.first
  end
end
