# frozen_string_literal: true

require "ripper"
require_relative "test_helper"

# A report value reaches HTML only through Export::ReportHtml, which escapes every value it is given.
# So in the report and every feature's report code, a string literal that holds markup (`<`) may
# interpolate only one ReportHtml call each time, and may not be joined to anything else with `+` or `%`
# or handed to `format`. The report's own page heredoc is the one exception: it assembles the sections
# ReportHtml already built and embeds the result as JSON.
class ReportEscapingTest < PhComposerTestCase
  EXTENSION_ROOT = File.join(SOURCE_ROOT, "ph_composer")
  REPORT_FILES = ["export/report.rb", *Dir.glob("features/**/export.rb", :base => EXTENSION_ROOT),
                  *Dir.glob("features/**/*_report.rb", :base => EXTENSION_ROOT)].freeze
  ALLOWED = [["export/report.rb", "<<~HTML"]].freeze
  OPENERS = %i[on_tstring_beg on_heredoc_beg on_regexp_beg on_qwords_beg on_words_beg on_qsymbols_beg
               on_symbols_beg on_backtick].freeze
  CLOSERS = %i[on_tstring_end on_heredoc_end on_regexp_end on_label_end].freeze
  STRINGS = %i[string_literal string_concat].freeze

  Literal = Struct.new(:opener, :line, :text, :embeds)

  def test_every_file_that_builds_report_html_is_read
    users = Dir.glob("**/*.rb", :base => EXTENSION_ROOT).select do |file|
      file != "export/report_html.rb" && File.read(File.join(EXTENSION_ROOT, file)).include?("ReportHtml")
    end
    assert_empty users - REPORT_FILES
    assert_includes REPORT_FILES, "features/windows/export.rb"
  end

  def test_markup_interpolates_only_report_html_calls
    offences = REPORT_FILES.flat_map do |file|
      literals(read(file)).filter_map do |literal|
        next if ALLOWED.include?([file, literal.opener]) || !literal.text.include?("<")

        raw = literal.embeds.reject { |code| helper_call?(code) }
        "#{file}:#{literal.line} interpolates #{raw.join(', ')}" unless raw.empty?
      end
    end
    assert_empty offences
  end

  def test_markup_is_never_joined_or_formatted_with_a_raw_value
    offences = REPORT_FILES.flat_map { |file| joins(Ripper.sexp(read(file))).map { |line| "#{file}:#{line}" } }
    assert_empty offences
  end

  def test_the_guard_catches_each_way_a_raw_value_reaches_markup
    source = %q(html = "<p>#{row.fetch('g_value')}</p>" + "<p>#{ReportHtml.h(x)}</p>" + "<p>" \\
                  "#{raw} is kept</p>" + "<p>#{ReportHtml.h(a) + b}</p>")
    markup = literals(source).select { |literal| literal.text.include?("<") }
    assert_equal [false, true, false, false], markup.map { |literal| literal.embeds.all? { |code| helper_call?(code) } }
    joined = %q(a = "<p>" + raw; b = "<p>%s</p>" % raw; c = format("<p>%s</p>", raw); d = ReportHtml.h(x) + raw)
    assert_equal 3, joins(Ripper.sexp(joined)).length
  end

  private

  def read(file)
    File.read(File.join(EXTENSION_ROOT, file))
  end

  # Every string-like literal in `source` with its text and the code of each interpolation, read from
  # the lexer so heredocs and nested strings are handled as Ruby reads them. Adjacent string literals,
  # `"<p>" \ "#{value}</p>"`, are one string to Ruby and one literal here.
  def literals(source)
    found = []
    open = []
    embeds = []
    adjacent = false
    Ripper.lex(source).each do |(position, type, token, _state)|
      embeds.each { |embed| embed[:code] << token } unless type == :on_embexpr_end && embeds.last[:depth] == open.length
      if adjacent && type != :on_sp
        adjacent = false
        next open.push(found.pop) if type == :on_tstring_beg
      end
      case type
      when *OPENERS
        open.push(Literal.new(token.strip, position.first, +"", []))
      when :on_symbeg
        open.push(Literal.new(token, position.first, +"", [])) if token.length > 1
      when :on_tstring_content
        open.last.text << token if open.any? && (embeds.empty? || embeds.last[:depth] < open.length)
      when :on_embexpr_beg
        embeds.push(:depth => open.length, :code => +"")
      when :on_embexpr_end
        embed = embeds.pop
        open.last.embeds << embed[:code].delete_prefix("\#{")
      when *CLOSERS
        next if open.empty?

        found << open.pop
        adjacent = type == :on_tstring_end
      end
    end
    found
  end

  # Whether `code` is exactly one call on ReportHtml, such as `Export::ReportHtml.h(name)`.
  def helper_call?(code)
    statements = Ripper.sexp(code)&.dig(1)
    statements&.length == 1 && helper_node?(statements.first)
  end

  def helper_node?(node)
    node = node[1] if node.first == :method_add_arg
    node.first == :call && report_html?(node[1])
  end

  def report_html?(node)
    case node.first
    when :var_ref then node.dig(1, 1) == "ReportHtml"
    when :const_path_ref then node.dig(1, 1, 1) == "Export" && node.dig(2, 1) == "ReportHtml"
    else false
    end
  end

  # The lines where a markup literal meets a value other than a ReportHtml call through `+` or `%`, or is
  # the format string of `format` or `sprintf`.
  def joins(tree, found = [])
    return found unless tree.is_a?(Array)

    if tree.first == :binary && %i[+ %].include?(tree[2]) && [tree[1], tree[3]].any? { |side| markup?(side) }
      other = markup?(tree[1]) ? tree[3] : tree[1]
      found << line(tree) unless STRINGS.include?(other.first) || helper_node?(other)
    elsif tree.first == :method_add_arg && %w[format sprintf].include?(tree.dig(1, 1, 1))
      found << line(tree) if markup?(tree.dig(2, 1, 1, 0) || tree.dig(2, 1, 0))
    end
    tree.each { |child| joins(child, found) }
    found
  end

  def markup?(node)
    node.is_a?(Array) && STRINGS.include?(node.first) && text(node).include?("<")
  end

  def text(node)
    return node[1] if node.first == :@tstring_content

    node.select { |child| child.is_a?(Array) }.map { |child| text(child) }.join
  end

  def line(node)
    return node[2].first if node.first.is_a?(Symbol) && node.first.to_s.start_with?("@")

    node.each { |child| (found = child.is_a?(Array) && line(child)) && (return found) }
    nil
  end
end
