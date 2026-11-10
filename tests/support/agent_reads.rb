# frozen_string_literal: true

require "digest"

# Reads through the real agent executor, each reply asserted within its budget, and the two ways a large read
# comes back: pages followed to the end, and fragments joined and checked. The includer sets @executor,
# @token and @session.
module AgentReads
  BUDGET = PhComposer::AgentAccess::Executor::MAX_RESULT_BYTES

  # The structuredContent of one tool call through the real executor, which must fit the budget.
  def agent(tool, arguments)
    answer = @executor.call(@token, tool, { "session" => @session.id }.merge(arguments))
    content = answer.fetch("structuredContent")
    assert_operator JSON.generate(content).bytesize, :<=, BUDGET
    content
  end

  def query(name, params)
    agent("query", "name" => name, "params" => params)
  end

  def completed(outcome)
    assert_equal "completed", outcome.fetch("status"), outcome.inspect
    outcome.fetch("value")
  end

  # Every page of a paged read, following next_cursor; each page has rows and every reply fits.
  def pages_of(name, params, rows)
    pages = [completed(query(name, params))]
    while (cursor = pages.last.fetch("next_cursor"))
      pages << completed(query(name, params.merge("cursor" => cursor)))
    end
    assert pages.all? { |page| !page.fetch(rows).empty? }
    assert_equal pages.first.fetch("total"), pages.sum { |page| page.fetch(rows).length }
    pages
  end

  # Every row of a paged read, in order, over at least `pages` pages.
  def rows_of(name, params, rows, pages: 1)
    read = pages_of(name, params, rows)
    assert_operator read.length, :>=, pages
    read.flat_map { |page| page.fetch(rows) }
  end

  # The value a fragment read answers for `params`, every fragment joined.
  def fragments_of(name, params, summary = nil)
    joined(->(cursor) { completed(query(name, params.merge(cursor ? { "cursor" => cursor } : {}))) }, summary)
  end

  # The value whose fragments `read` answers, joined in order and checked against the size and digest every
  # fragment repeats (and `summary`, when given).
  def joined(read, summary = nil)
    text = +""
    cursor = nil
    loop do
      value = read.call(cursor)
      fragment = value.fetch("fragment")
      assert_equal text.bytesize, fragment.fetch("offset")
      assert fragment.fetch("text").valid_encoding?
      assert_equal fragment.fetch("bytes"), fragment.fetch("text").bytesize
      text << fragment.fetch("text")
      cursor = value.fetch("next_cursor")
      next if cursor

      assert_equal [fragment.fetch("total_bytes"), fragment.fetch("sha256")],
                   [text.bytesize, Digest::SHA256.hexdigest(text)]
      assert_equal summary.slice("bytes", "sha256"),
                   { "bytes" => text.bytesize, "sha256" => fragment.fetch("sha256") } if summary
      return JSON.parse(text, :quirks_mode => true)
    end
  end
end
