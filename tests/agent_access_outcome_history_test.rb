# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/test_feature"

# The operation history (context/AGENT_INTERFACE.md, "Writes with observable outcomes"): the `outcome` tool
# with neither sequence nor idempotency_key lists this connection's own retained change outcomes, newest
# first, in bounded pages, and says what the session still retains. No value or params ever appear.
class AgentAccessOutcomeHistoryTest < PhComposerTestCase
  AgentAccess = PhComposer::AgentAccess
  CREATE = "test.fixture.create"
  PARTS = { "parts" => [{ "label" => "Sill", "length_mm" => 1200.0 }] }.freeze
  ROW_KEYS = %w[sequence idempotency_key operation status effect code revision recorded_at affected
                affected_total].freeze

  def setup
    super
    PhComposer::Registry.install([TestFeature])
    @session = PhComposer::Sessions.for(Sketchup.active_model)
    @executor = AgentAccess::Executor.new(:tools => AgentAccess::Tools::TABLE)
    @writer = token
  end

  def token
    issued = AgentAccess::Tokens.issue(:capabilities => %w[read model_write])
    AgentAccess::Tokens.snapshot.fetch(AgentAccess::Tokens.digest(issued.fetch("token")))
  end

  def call(name, arguments = {}, row = @writer)
    result = @executor.call(row, name, { "session" => @session.id }.merge(arguments))
    refute result["isError"], result.inspect
    result.fetch("structuredContent")
  end

  def invoke(arguments = {}, row = @writer)
    call("invoke", { "name" => CREATE, "params" => PARTS, "expected_revision" => @session.revision }.merge(arguments),
         row)
  end

  def history(arguments = {}, row = @writer)
    call("outcome", arguments, row)
  end

  def handle(row = @writer)
    AgentAccess.bindings.fetch([row.fetch("id"), @session.id]).context.caller
  end

  def test_each_connection_lists_only_its_own_changes_newest_first_without_values_or_params
    other = token
    invoke("idempotency_key" => "add-sill")
    stale = invoke("expected_revision" => -1)
    theirs_parts = { "parts" => [{ "label" => "Theirs", "length_mm" => 1.0 }] }
    invoke({ "idempotency_key" => "theirs", "params" => theirs_parts }, other)

    mine = history
    theirs = history({}, other)

    assert_equal %w[completed ok], mine.values_at("status", "code")
    rows = mine.dig("value", "outcomes")
    assert_equal [[2, nil, "revision.stale", "none"], [1, "add-sill", "ok", "committed"]],
                 rows.map { |row| row.values_at("sequence", "idempotency_key", "code", "effect") }
    assert_equal [ROW_KEYS] * 2, rows.map(&:keys)
    assert_equal [CREATE] * 2, rows.map { |row| row["operation"] }
    assert_equal stale["revision"], rows.first["revision"]
    assert_match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/, rows.last["recorded_at"])
    assert_equal([[1, "theirs"]],
                 theirs.dig("value", "outcomes").map { |row| row.values_at("sequence", "idempotency_key") })
    text = JSON.generate([mine, theirs])
    leaks = %w[Sill Theirs length_mm part_ids "params" "value":{"definition_id] + [stale.fetch("message")]
    leaks.each { |leak| refute_includes text, leak }
  end

  def test_the_reply_states_the_bound_and_affected_references_are_capped_with_a_total
    parts = Array.new(14) { |index| { "label" => "Part #{index}", "length_mm" => 1.0 } }
    sent = invoke("params" => { "parts" => parts })

    listed = history
    row = listed.dig("value", "outcomes").first

    assert_equal 15, sent["affected"].length
    assert_equal [sent["affected"].first(PhComposer::OutcomeHistory::MAX_AFFECTED), 15],
                 row.values_at("affected", "affected_total")
    assert_equal [256, 900], listed.dig("value", "retention").values_at("capacity", "lifetime_seconds")
    assert_includes listed["message"], "up to 256 outcomes across every caller, each for 15 minutes"
  end

  def test_pages_follow_next_cursor_and_a_cursor_is_stale_once_a_newer_change_was_accepted
    3.times { invoke }

    first = history("limit" => 2)
    second = history("limit" => 2, "cursor" => first.dig("value", "next_cursor"))
    again = history("limit" => 1)
    invoke
    stale = history("limit" => 1, "cursor" => again.dig("value", "next_cursor"))

    sequences = [first, second].map { |page| page.dig("value", "outcomes").map { |row| row["sequence"] } }
    assert_equal [[3, 2], [1]], sequences
    assert_equal [3, 3], [first, second].map { |page| page.dig("value", "total") }
    assert_nil second.dig("value", "next_cursor")
    assert_equal "query.cursor_expired", stale["code"]
  end

  def test_a_full_page_stays_within_one_reply_and_the_next_page_continues_without_a_gap
    parts = Array.new(14) { |index| { "label" => "Part #{index}", "length_mm" => 1.0 } }
    30.times { |index| invoke("idempotency_key" => format("%064d", index), "params" => { "parts" => parts }) }

    pages = [@executor.call(@writer, "outcome", "session" => @session.id, "limit" => 500)]
    while (cursor = pages.last.dig("structuredContent", "value", "next_cursor"))
      pages << @executor.call(@writer, "outcome", "session" => @session.id, "limit" => 500, "cursor" => cursor)
    end

    assert_operator pages.length, :>, 1
    pages.each do |page|
      refute page["isError"], page.inspect
      assert_operator JSON.generate(page["structuredContent"]).bytesize, :<=, AgentAccess::Executor::MAX_RESULT_BYTES
    end
    rows = pages.flat_map { |page| page.dig("structuredContent", "value", "outcomes") }
    assert_equal (1..30).to_a.reverse, rows.map { |row| row["sequence"] }
    assert_equal format("%064d", 29), rows.first["idempotency_key"]
  end

  def test_a_cursor_answers_only_the_connection_it_was_issued_to
    other = token
    2.times { invoke }
    2.times { invoke({}, other) }

    mine = history("limit" => 1)
    borrowed = history({ "limit" => 1, "cursor" => mine.dig("value", "next_cursor") }, other)

    assert_equal "params.invalid", borrowed["code"]
  end

  def test_a_running_change_is_not_listed
    invoke
    @session.outcomes.begin(handle, 2, "digest", :name => CREATE)

    assert_equal [1], history.dig("value", "outcomes").map { |row| row["sequence"] }
  end

  def test_an_evicted_or_expired_outcome_is_no_longer_listed
    invoke
    store = @session.outcomes
    (2..PhComposer::OutcomeStore::CAPACITY + 1).each do |sequence|
      store.begin(handle, sequence, "digest", :name => CREATE)
      store.finish(handle, sequence, PhComposer::Outcome.completed(:revision => 0))
    end

    evicted = history("limit" => 1)
    store.clock = -> { Float::INFINITY }
    expired = history

    assert_equal [PhComposer::OutcomeStore::CAPACITY, PhComposer::OutcomeStore::CAPACITY + 1],
                 [evicted.dig("value", "total"), evicted.dig("value", "outcomes", 0, "sequence")]
    refute(store.history(handle).any? { |entry| entry.sequence == 1 })
    assert_equal [[], 0], [expired.dig("value", "outcomes"), expired.dig("value", "total")]
  end

  def test_paging_arguments_belong_to_the_list_alone
    sent = invoke
    refused = history("sequence" => sent["sequence"], "limit" => 5)
    bad_cursor = history("cursor" => "not a cursor")

    assert_equal %w[params.invalid params.invalid], [refused, bad_cursor].map { |outcome| outcome["code"] }
  end

  def test_the_ruby_interface_lists_with_the_change_grant_and_names_no_keys
    writer = PhComposer::API.connect(:session_id => @session.id)
    reader = PhComposer::API.connect(:session_id => @session.id, :capabilities => %w[read])
    PhComposer::API.invoke(:context => writer, :name => CREATE, :params => PARTS,
                           :request => { "sequence" => 1, "expected_revision" => @session.revision })

    listed = PhComposer::API.outcomes(:context => writer)
    denied = PhComposer::API.outcomes(:context => reader)

    assert_equal [[1, nil, CREATE]],
                 listed.dig("value", "outcomes").map { |row| row.values_at("sequence", "idempotency_key", "operation") }
    assert_equal "request.capability_denied", denied["code"]
  end
end
