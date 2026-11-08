# frozen_string_literal: true

require "net/http"
require_relative "test_helper"
require_relative "support/test_feature"

# The agent listener through a real loopback socket under the stub: every refusal of the pipeline, the
# MCP methods, tool calls run by the pump on the main thread, and the busy answer when the pump starves
# (context/AGENT_INTERFACE.md, "User-controlled local access"). The stub raises when Sketchup or UI is
# called off the main thread, so a worker that touched either would answer 500.
class AgentAccessServerTest < PhComposerTestCase
  AgentAccess = PhComposer::AgentAccess
  # Records the pump timer without running it: each test pumps by hand while its request waits.
  Timers = Struct.new(:started) do
    def start_timer(_delay, _repeat = false)
      self.started += 1
    end

    def stop_timer(_timer); end
  end

  def setup
    super
    PhComposer::Registry.install([TestFeature])
    @session = PhComposer::Sessions.for(Sketchup.active_model)
    issued = AgentAccess::Tokens.issue(:label => "Test agent")
    @token = issued.fetch("token")
    @row = issued.fetch("row")
    @executor = AgentAccess::Executor.new(:tools => AgentAccess::Tools::TABLE)
    @server = server
  end

  def teardown
    @server&.stop
    super
  end

  # ------------------------------------------------------------------ refusals before anything runs

  def test_every_wire_refusal_answers_before_the_main_thread
    assert_equal "401", post(rpc("ping"), :token => nil).code
    assert_equal "401", post(rpc("ping"), :token => "f" * 48).code
    assert_equal "403", post(rpc("ping"), :headers => { "Origin" => "http://example.com" }).code
    assert_equal "403", post(rpc("ping"), :headers => { "Host" => "evil.test:#{@server.port}" }).code
    assert_equal "415", post(rpc("ping"), :headers => { "Content-Type" => "text/plain" }).code
    assert_equal "404", post(rpc("ping"), :path => "/other").code
    assert_equal "405", http { |client| client.request(Net::HTTP::Get.new("/mcp")) }.code
    assert_equal "413", declared_length(AgentAccess::Server::MAX_BODY_BYTES + 1)
    assert_equal "401", http { |client| client.request(request_for(rpc("ping"), "Authorization" => "Basic x")) }.code
  end

  def test_a_revoked_token_is_refused_from_the_next_snapshot_on
    AgentAccess::Tokens.revoke(@row.fetch("id"))
    @server.tokens = AgentAccess::Tokens.snapshot

    assert_equal "401", post(rpc("ping")).code
  end

  def test_json_rpc_envelope_errors
    assert_equal [-32_700, "400"], error_of(post("{not json"))
    assert_equal [-32_600, "200"], error_of(post(JSON.generate([JSON.parse(rpc("ping"))])))
    assert_equal [-32_600, "200"], error_of(post(JSON.generate("id" => 1, "method" => "ping")))
    assert_equal [-32_601, "200"], error_of(post(rpc("sampling/createMessage")))
    assert_equal [-32_602, "200"], error_of(post(rpc("tools/call", "arguments" => {})))
    [{}, [1], true, 1.5, nil].each do |id|
      message = { "jsonrpc" => "2.0", "id" => id, "method" => "ping" }
      assert_equal [-32_600, "200"], error_of(post(JSON.generate(message))), id.inspect
    end
  end

  def test_the_body_must_be_json_utf8_and_the_media_type_exactly_json
    assert_equal [-32_700, "400"], error_of(post("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"p\xFF\"}".b))
    assert_equal "415", post(rpc("ping"), :headers => { "Content-Type" => "application/jsonp" }).code
    assert_equal({}, result_of(post(rpc("ping"), :headers => { "Content-Type" => "Application/JSON; charset=utf-8" })))
  end

  # ------------------------------------------------------------------ protocol methods

  def test_initialize_answers_the_revision_asked_for_when_known
    known = body(post(rpc("initialize", "protocolVersion" => "2025-06-18"))).fetch("result")
    newer = body(post(rpc("initialize", "protocolVersion" => "2026-07-28"))).fetch("result")

    assert_equal "2025-06-18", known.fetch("protocolVersion")
    assert_equal AgentAccess::MCP::PROTOCOL_VERSIONS.first, newer.fetch("protocolVersion")
    assert_equal({ "major" => 1, "minor" => PhComposer::API::MINOR }, known.dig("_meta", "ph_composer/api"))
    assert_equal PhComposer::VERSION, known.dig("serverInfo", "version")
  end

  def test_a_notification_is_accepted_and_the_lists_answer
    assert_equal "202", post(JSON.generate("jsonrpc" => "2.0", "method" => "notifications/initialized")).code
    assert_equal({}, result_of(post(rpc("ping"))))
    assert_equal({ "resources" => [] }, result_of(post(rpc("resources/list"))))
    assert_equal({ "prompts" => [] }, result_of(post(rpc("prompts/list"))))
    tools = result_of(post(rpc("tools/list"))).fetch("tools")
    read_tools = AgentAccess::Tools::TABLE.values.select { |tool| tool.capability == "read" }.map(&:name)
    assert_equal read_tools, tools.map { |tool| tool.fetch("name") }
    assert(tools.all? { |tool| tool.dig("annotations", "readOnlyHint") })
  end

  # ------------------------------------------------------------------ tool calls on the main thread

  def test_discover_is_a_compact_index_and_an_owner_page_adds_descriptions
    index = call_tool("discover")
    owner = call_tool("discover", "owner" => TestFeature::ID)

    assert_equal [@session.id], index.dig("structuredContent", "sessions").map { |session| session.fetch("id") }
    assert_includes index.dig("structuredContent", "operations", "queries", TestFeature::ID),
                    "test.fixture.total_length"
    assert_equal @row.slice("id", "label", "capabilities"), index.dig("structuredContent", "connection")
    assert_equal "test.fixture.total_length",
                 owner.dig("structuredContent", "queries").first.fetch("name")
    refute_nil owner.dig("structuredContent", "queries").first["description"]
    assert JSON.generate(index["structuredContent"]).bytesize < AgentAccess::Executor::MAX_RESULT_BYTES
  end

  def test_describe_and_query_reach_an_outside_feature_with_no_adapter_change
    described = call_tool("describe", "name" => "test.fixture.total_length")
    queried = call_tool("query", "session" => @session.id, "name" => "test.fixture.total_length")

    assert_equal PhComposer::API.describe(:name => "test.fixture.total_length"), described.fetch("structuredContent")
    assert_equal ["completed", false], [queried.dig("structuredContent", "status"), queried.fetch("isError")]
    assert_equal "completed: ok", queried.dig("content", 0, "text")[/\A[a-z]+: [a-z]+/]
  end

  def test_a_refusal_is_an_ordinary_result_and_bad_arguments_are_a_tool_error
    unknown = call_tool("query", "session" => @session.id, "name" => "nope.missing")
    closed = call_tool("query", "session" => "closed-session", "name" => "test.fixture.total_length")
    stray = call_tool("query", "session" => @session.id, "name" => "x", "eval" => "1")
    hidden = call_tool("invoke", "session" => @session.id)

    assert_equal [false, "request.unknown_operation"], [unknown["isError"], unknown.dig("structuredContent", "code")]
    assert_equal [false, "session.unknown"], [closed["isError"], closed.dig("structuredContent", "code")]
    assert_equal [true, true], [stray["isError"], hidden["isError"]]
  end

  def test_preview_export_preflight_and_a_paged_query_answer_as_the_api_does
    writer = PhComposer::API.connect(:session_id => @session.id)
    create = { "parts" => Array.new(2) { |index| { "label" => "Sill #{index}", "length_mm" => 1200.0 } } }
    PhComposer::API.invoke(:context => writer, :name => "test.fixture.create", :params => create,
                           :request => { "sequence" => 1, "expected_revision" => @session.revision })
    page = { "kind" => "test.fixture.part", "limit" => 1 }

    preview = call_tool("preview", "session" => @session.id, "name" => "test.fixture.create", "params" => create)
    preflight = call_tool("export_preflight", "session" => @session.id)
    first = call_tool("query", "session" => @session.id, "name" => "ph_composer.records.list", "params" => page)
    cursor = first.dig("structuredContent", "value", "next_cursor")
    second = call_tool("query", "session" => @session.id, "name" => "ph_composer.records.list",
                                "params" => page.merge("cursor" => cursor))

    assert_equal PhComposer::API.preview(:context => writer, :name => "test.fixture.create", :params => create)
                                .values_at("status", "proposal_digest"),
                 preview.fetch("structuredContent").values_at("status", "proposal_digest")
    assert_equal PhComposer::API.export_preflight(:context => writer).values_at("status", "code"),
                 preflight.fetch("structuredContent").values_at("status", "code")
    ids = [first, second].map { |answer| answer.dig("structuredContent", "value", "records", 0, "id") }
    assert_equal 2, ids.compact.uniq.length
  end

  def test_every_error_stays_within_the_budget_and_a_raising_call_never_stops_the_pump
    long = call_tool("discover", "x" * 30_000 => 1)
    timers = Struct.new(:blocks) do
      def start_timer(_delay, _repeat = false, &block)
        blocks << block
        blocks.length
      end

      def stop_timer(_timer); end
    end.new([])
    @server.stop
    @server = AgentAccess::Server.new(:port => 0, :protocol => AgentAccess::MCP, :executor => @executor,
                                      :timer_api => timers).start
    @server.tokens = AgentAccess::Tokens.snapshot
    @executor.define_singleton_method(:call) { |*_arguments| raise JSON::GeneratorError, "bad bytes" }
    request = Thread.new { post(rpc("tools/call", "name" => "discover", "arguments" => {})) }
    sleep 0.01 until @server.snapshot.fetch("pending") == 1
    timers.blocks.last.call

    assert long.fetch("isError")
    assert_operator JSON.generate(long.fetch("structuredContent")).bytesize, :<, AgentAccess::Executor::MAX_RESULT_BYTES
    assert_equal "failed", result_of(request.value).dig("structuredContent", "status")
    assert_equal 2, timers.blocks.length
  end

  def test_a_running_call_is_answered_with_its_result_and_unrun_calls_keep_counting
    @server.stop
    @server = server(:starvation_seconds => 0.3)
    admitted = []
    gate = Queue.new
    @executor.define_singleton_method(:call) do |_token, _tool, arguments|
      gate.pop if arguments["slow"]
      busy("finished") # any ordinary result
    end
    first = Thread.new { post(rpc("tools/call", "name" => "discover", "arguments" => { "slow" => true })) }
    sleep 0.01 until @server.snapshot.fetch("pending") == 1
    Array.new(AgentAccess::Server::MAX_PENDING_PER_TOKEN - 1) do
      admitted << Thread.new { post(rpc("tools/call", "name" => "discover", "arguments" => {})) }
    end
    sleep 0.01 until @server.snapshot.fetch("pending") == AgentAccess::Server::MAX_PENDING_PER_TOKEN
    pump = Thread.new { @server.send(:take_next).tap { |entry| @server.send(:run, entry) } }
    sleep 0.05 until @server.snapshot.fetch("pending") == AgentAccess::Server::MAX_PENDING_PER_TOKEN - 1
    sleep 0.5 # past the starvation bound while the first call runs

    extra = result_of(post(rpc("tools/call", "name" => "discover", "arguments" => {})))
    gate << :go
    pump.join

    assert_equal "session.busy", extra.dig("structuredContent", "code")
    assert_equal "finished", result_of(first.value).dig("structuredContent", "message")
    admitted.each(&:kill)
  end

  def test_a_result_at_the_budget_passes_whole_and_one_over_is_refused
    sized = lambda do |bytes|
      tool = AgentAccess::Executor::Tool.new(:name => "sized", :capability => "read", :session => false,
                                             :input_schema => { "type" => "object" },
                                             :run => ->(*) { { "text" => "x" * (bytes - 11) } })
      AgentAccess::Executor.new(:tools => { "sized" => tool }).call(@row, "sized", {})
    end

    whole = sized.call(AgentAccess::Executor::MAX_RESULT_BYTES)
    over = sized.call(AgentAccess::Executor::MAX_RESULT_BYTES + 1)

    assert_equal [false, AgentAccess::Executor::MAX_RESULT_BYTES],
                 [whole["isError"], JSON.generate(whole["structuredContent"]).bytesize]
    assert_equal [true, "request.response_too_large"], [over["isError"], over.dig("structuredContent", "code")]
  end

  def test_the_context_tool_reads_where_a_session_stands
    answer = call_tool("context", "session" => @session.id)

    assert_equal [false, "completed"], [answer["isError"], answer.dig("structuredContent", "status")]
    assert_equal @session.id, answer.dig("structuredContent", "value", "session", "id")
    assert_includes result_of(post(rpc("tools/list"))).fetch("tools").map { |tool| tool["name"] }, "context"
  end

  def test_a_model_only_token_sees_and_reaches_only_its_own_model
    @session.model.path = "/projects/a/house.skp"
    other = Sketchup::Model.new
    other.path = "/projects/b/house.skp"
    second = PhComposer::Sessions.for(other)
    issued = AgentAccess::Tokens.issue(:model_file => "/projects/a/house.skp")
    row = AgentAccess::Tokens.snapshot.fetch(AgentAccess::Tokens.digest(issued.fetch("token")))

    found = @executor.call(row, "discover", {}).fetch("structuredContent")
    refused = @executor.call(row, "context", "session" => second.id).fetch("structuredContent")
    read = @executor.call(row, "context", "session" => @session.id).fetch("structuredContent")

    assert_equal [@session.id], found.fetch("sessions").map { |session| session["id"] }
    assert_equal "house.skp", found.dig("connection", "model_name")
    refute_includes JSON.generate(found), "/projects/"
    assert_equal "session.unknown", refused["code"]
    assert_equal "completed", read["status"]
    assert_equal 2, @executor.call(@row, "discover", {}).dig("structuredContent", "sessions").length
  end

  # #345: Save As is how a stage copy is made, so the binding follows the Model to its new file; a save at
  # the same path (an autosave) or a copy leaves the store untouched.
  def test_a_model_only_token_follows_its_model_through_save_as
    model = Sketchup::Model.new
    model.path = "/projects/a/02_working.skp"
    session = PhComposer::Sessions.for(model)
    issued = AgentAccess::Tokens.issue(:model_file => "/projects/a/02_working.skp")
    digest = AgentAccess::Tokens.digest(issued.fetch("token"))

    model.save("/projects/a/03_spaces.skp")

    row = AgentAccess::Tokens.snapshot.fetch(digest)
    found = @executor.call(row, "discover", {}).fetch("structuredContent")
    assert_equal [session.id], found.fetch("sessions").map { |served| served["id"] }
    assert_equal "03_spaces.skp", found.dig("connection", "model_name")
    assert_equal "completed", @executor.call(row, "context", "session" => session.id).dig("structuredContent", "status")
  end

  def test_a_same_path_save_or_a_copy_leaves_the_token_store_untouched
    model = Sketchup::Model.new
    model.path = "/projects/a/02_working.skp"
    PhComposer::Sessions.for(model)
    AgentAccess::Tokens.issue(:model_file => "/projects/a/02_working.skp")
    Sketchup.clear_default_writes

    model.save
    model.save_copy("/projects/a/copy.skp")

    assert_empty(Sketchup.default_writes.select { |section, _key, _value| section == AgentAccess::Tokens::SECTION })
  end

  # The follow runs inside SketchUp's save: a store it cannot write is logged, the save goes on, and the
  # next save tries again.
  def test_a_failed_follow_never_raises_into_the_save_and_is_retried
    model = Sketchup::Model.new
    model.path = "/projects/a/02_working.skp"
    PhComposer::Sessions.for(model)
    issued = AgentAccess::Tokens.issue(:model_file => "/projects/a/02_working.skp")
    digest = AgentAccess::Tokens.digest(issued.fetch("token"))

    Sketchup.refuse_default_writes = true
    assert model.save("/projects/a/03_spaces.skp")
    Sketchup.refuse_default_writes = false
    logged = PhComposer::Diagnostics.tail.join
    model.save

    assert_includes logged, "agent_access_follow_failed"
    assert_equal "03_spaces.skp", AgentAccess::Tokens.snapshot.fetch(digest).fetch("model_name")
  end

  # A failed move from A to B, a token issued at B, then Save As to C: both tokens reach C.
  def test_a_token_issued_after_a_failed_follow_moves_with_the_next_save_as
    model = Sketchup::Model.new
    model.path = "/projects/a/02_working.skp"
    PhComposer::Sessions.for(model)
    first = AgentAccess::Tokens.digest(AgentAccess::Tokens.issue(:model_file => model.path).fetch("token"))
    Sketchup.refuse_default_writes = true
    model.save("/projects/a/03_spaces.skp")
    Sketchup.refuse_default_writes = false
    second = AgentAccess::Tokens.digest(AgentAccess::Tokens.issue(:model_file => model.path).fetch("token"))

    model.save("/projects/a/04_windows.skp")

    snapshot = AgentAccess::Tokens.snapshot
    assert_equal ["04_windows.skp"] * 2, [first, second].map { |digest| snapshot.fetch(digest).fetch("model_name") }
  end

  # The retry moves only the tokens the failed move left behind: a token issued afterwards for the original
  # file, reopened, stays on it.
  def test_a_retried_follow_never_takes_a_token_issued_later_for_the_original_file
    model = Sketchup::Model.new
    model.path = "/projects/a/02_working.skp"
    PhComposer::Sessions.for(model)
    first = AgentAccess::Tokens.digest(AgentAccess::Tokens.issue(:model_file => model.path).fetch("token"))
    Sketchup.refuse_default_writes = true
    model.save("/projects/a/03_spaces.skp")
    Sketchup.refuse_default_writes = false
    original = Sketchup::Model.new
    original.path = "/projects/a/02_working.skp"
    PhComposer::Sessions.for(original)
    later = AgentAccess::Tokens.digest(AgentAccess::Tokens.issue(:model_file => original.path).fetch("token"))

    model.save

    snapshot = AgentAccess::Tokens.snapshot
    names = [first, later].map { |digest| snapshot.fetch(digest).fetch("model_name") }
    assert_equal %w[03_spaces.skp 02_working.skp], names
  end

  # A file opened into the same Model (one window per document on Windows) starts afresh: a token a failed
  # Save As left behind never moves onto it.
  def test_a_file_opened_into_the_model_takes_no_token_a_failed_follow_left_behind
    model = Sketchup::Model.new
    model.path = "/projects/a/02_working.skp"
    session = PhComposer::Sessions.for(model)
    digest = AgentAccess::Tokens.digest(AgentAccess::Tokens.issue(:model_file => model.path).fetch("token"))
    Sketchup.refuse_default_writes = true
    model.save("/projects/a/03_spaces.skp")
    Sketchup.refuse_default_writes = false
    model.path = "/projects/other/house.skp"
    session.host_event(:model_opened)

    model.save

    assert_equal "02_working.skp", AgentAccess::Tokens.snapshot.fetch(digest).fetch("model_name")
  end

  def test_discover_says_why_a_model_only_token_sees_no_session
    @session.model.path = "/projects/b/03_spaces.skp"
    issued = AgentAccess::Tokens.issue(:model_file => "/projects/a/02_working.skp")
    row = AgentAccess::Tokens.snapshot.fetch(AgentAccess::Tokens.digest(issued.fetch("token")))

    found = @executor.call(row, "discover", {}).fetch("structuredContent")
    refused = @executor.call(row, "context", "session" => @session.id).fetch("structuredContent")

    assert_empty found.fetch("sessions")
    reason = found.dig("connection", "reason")
    assert_includes reason, "02_working.skp"
    assert_includes reason, "03_spaces.skp"
    assert_includes refused.fetch("message"), "02_working.skp"
    refute_includes JSON.generate([found, refused]), "/projects/"
  end

  def test_one_token_keeps_one_caller_per_session
    2.times { call_tool("query", "session" => @session.id, "name" => "test.fixture.total_length") }

    assert_equal 1, @session.callers.count
  end

  # ------------------------------------------------------------------ the handoff

  def test_a_starved_pump_answers_busy_and_the_entry_never_runs
    @server.stop
    @server = server(:starvation_seconds => 0.2)
    ran = []
    @executor.define_singleton_method(:call) { |*arguments| ran << arguments }

    answer = result_of(post(rpc("tools/call", "name" => "discover", "arguments" => {})))

    assert_equal ["busy", "session.busy"], answer.fetch("structuredContent").values_at("status", "code")
    @server.pump
    assert_empty ran
  end

  def test_a_full_queue_answers_busy_at_once
    @server.stop
    @server = server(:starvation_seconds => 5.0)
    waiting = Array.new(AgentAccess::Server::MAX_PENDING_PER_TOKEN) do
      Thread.new { post(rpc("tools/call", "name" => "discover", "arguments" => {})) }
    end
    sleep 0.05 until @server.snapshot.fetch("pending") == AgentAccess::Server::MAX_PENDING_PER_TOKEN

    refused = result_of(post(rpc("tools/call", "name" => "discover", "arguments" => {})))

    assert_equal "session.busy", refused.dig("structuredContent", "code")
    pump_until { waiting.none?(&:alive?) }
    assert(waiting.all? { |thread| result_of(thread.value).fetch("isError") == false })
  end

  def test_an_entry_past_its_handoff_deadline_is_dropped_unrun
    now = 0.0
    @server.stop
    @server = server(:clock => -> { now })
    ran = []
    @executor.define_singleton_method(:call) { |*arguments| ran << arguments }
    entry = AgentAccess::Server::Entry.new(:token => @row, :tool => "discover", :arguments => {},
                                           :deadline => 1.0, :state => :waiting)
    @server.instance_variable_get(:@queue) << entry

    now = 2.0
    @server.pump

    assert_empty ran
  end

  # Activation and close between enqueue and execution: the call names its session, so a Model that
  # became active meanwhile is never the target, and a closed one answers session.unknown unrun.
  def test_a_queued_call_runs_on_the_session_it_named_or_refuses_once_that_model_closed
    other = Sketchup::Model.new
    other_session = PhComposer::Sessions.for(other)
    arguments = { "session" => @session.id, "name" => "test.fixture.total_length" }
    targeted = queue_tool("query", arguments)
    Sketchup.instance_variable_set(:@active_model, other)
    pump_until { !targeted.alive? }
    closing = queue_tool("query", arguments.merge("session" => other_session.id))
    other.close
    pump_until { !closing.alive? }

    assert_equal "completed", result_of(targeted.value).dig("structuredContent", "status")
    assert_equal 1, @session.callers.count
    assert_equal "session.unknown", result_of(closing.value).dig("structuredContent", "code")
  end

  # A client's cancellation is accepted and changes nothing: the waiting invoke still runs whole, and
  # its outcome is the committed one, never a rollback.
  def test_a_cancelled_waiting_invoke_runs_whole_and_its_outcome_is_retained
    writer = AgentAccess::Tokens.issue(:capabilities => %w[read model_write]).fetch("token")
    @server.tokens = AgentAccess::Tokens.snapshot
    arguments = { "session" => @session.id, "name" => "test.fixture.create", "idempotency_key" => "k",
                  "params" => { "parts" => [] }, "expected_revision" => @session.revision }
    pending = @server.snapshot.fetch("pending")
    request = Thread.new { post(rpc("tools/call", "name" => "invoke", "arguments" => arguments), :token => writer) }
    sleep 0.01 until @server.snapshot.fetch("pending") > pending
    cancelled = post(JSON.generate("jsonrpc" => "2.0", "method" => "notifications/cancelled",
                                   "params" => { "requestId" => 7 }), :token => writer)
    pump_until { !request.alive? }

    assert_equal "202", cancelled.code
    assert_equal %w[completed committed],
                 result_of(request.value).dig("structuredContent").values_at("status", "effect")
    assert_equal 1, @session.model.operations.count { |operation| operation.last == :committed }
  end

  # Revoking a token answers its waiting call as revoked, and revoking the last stops the listener only
  # once that answer is written.
  def test_a_revoke_answers_the_waiting_call_and_the_last_one_stops_after_it
    writer = AgentAccess::Tokens.issue(:capabilities => %w[read model_write])
    @server.tokens = AgentAccess::Tokens.snapshot
    arguments = { "session" => @session.id, "name" => "test.fixture.create", "params" => { "parts" => [] },
                  "expected_revision" => @session.revision }
    pending = @server.snapshot.fetch("pending")
    request = Thread.new do
      post(rpc("tools/call", "name" => "invoke", "arguments" => arguments), :token => writer.fetch("token"))
    end
    sleep 0.01 until @server.snapshot.fetch("pending") > pending
    [@row, writer.fetch("row")].each { |row| AgentAccess::Tokens.revoke(row.fetch("id")) }

    assert_equal({ writer.dig("row", "id") => 1 }, @server.refuse_revoked([]))
    @server.stop_soon
    answer = request.value
    @server.pump

    assert_equal "access.revoked", result_of(answer).dig("structuredContent", "code")
    assert @server.stopped?
    assert_empty @session.model.operations
  end

  def test_a_token_issued_before_the_pending_stop_keeps_the_listener_running
    @server.stop_soon
    @server.tokens = AgentAccess::Tokens.snapshot
    @server.pump

    refute @server.stopped?
  end

  def test_the_call_ring_never_holds_a_disclosed_artifact_path
    log = AgentAccess::CallLog.new
    result = { "structuredContent" => { "status" => "completed", "code" => "ok", "value" => {
      "outcome" => { "value" => { "artifacts" => { "hbjson" => { "path" => "/projects/secret/house.hbjson" } } } }
    } }, "isError" => false }

    log.add(@row, "export_status", { "session" => @session.id, "task_id" => "export_1" }, result, 3)

    refute_includes JSON.generate(log.recent), "/projects/secret"
  end

  def test_the_diagnostics_hold_no_token_or_params
    call_tool("query", "session" => @session.id, "name" => "test.fixture.total_length",
                       "params" => { "secret" => "value-in-params" })

    recent = JSON.generate(@server.snapshot.fetch("recent"))
    refute_includes recent, @token
    refute_includes recent, "value-in-params"
    assert_includes recent, "test.fixture.total_length"
  end

  # An operation name the agent made up is its own text; the log names only declared operations.
  def test_the_log_names_only_declared_operations
    call_tool("query", "session" => @session.id, "name" => "secret_client_model", "params" => {})
    call_tool("query", "session" => @session.id, "name" => "test.fixture.total_length", "params" => {})
    @server.snapshot

    logged = PhComposer::Diagnostics.tail.join
    refute_includes logged, "secret_client_model"
    assert_includes logged, '"operation":"query.test.fixture.total_length"'
  end

  # ------------------------------------------------------------------ lifecycle

  def test_the_listener_runs_while_a_token_is_live_and_reports_a_taken_port
    AgentAccess::Listener.stop
    AgentAccess::Listener.server_factory = AgentAccess::Listener::DEFAULT_FACTORY
    blocker = TCPServer.new("127.0.0.1", 0)
    port = blocker.addr[1]
    Sketchup.write_default(PhComposer::Preferences::SECTION, AgentAccess::Listener::PORT_KEY, port)

    AgentAccess::Listener.refresh
    taken = AgentAccess::Listener.status
    probe = TCPServer.new("127.0.0.1", 0)
    free = probe.addr[1]
    probe.close
    AgentAccess::Listener.port = free
    listening = AgentAccess::Listener.status
    error = assert_raises(PhComposer::CodedError) { AgentAccess::Listener.port = 80 }
    AgentAccess::Tokens.revoke(@row.fetch("id"))

    assert_equal %w[unavailable listening stopped],
                 [taken, listening, AgentAccess::Listener.status].map { |status| status.fetch("state") }
    assert_includes taken.fetch("message"), port.to_s
    assert_equal [free, "params.invalid"], [listening.fetch("port"), error.code]
  ensure
    blocker&.close
    AgentAccess::Listener.stop
  end

  def test_a_tokens_latest_call_reaches_an_open_dialog_and_outlives_the_ring_and_a_port_change
    @server.stop
    @server = server(:on_calls => ->(rows) { AgentAccess::Listener.calls_made(rows) })
    dialog = AgentAccess::Dialog.show
    call_tool("discover")
    discovered = AgentAccess::Listener.last_calls.fetch(@row.fetch("id"))
    call_tool("query", "session" => @session.id, "name" => "test.fixture.total_length", "params" => { "p" => "secret" })
    other = AgentAccess::Tokens.issue(:label => "Other").fetch("row")
    AgentAccess::Listener.calls_made(Array.new(AgentAccess::CallLog::SIZE + 1) do
      { "token" => other.fetch("id"), "at" => "2026-10-18T12:00:00Z", "status" => "completed", "error" => false }
    end)
    AgentAccess::Listener.stop

    calls = AgentAccess::Listener.last_calls
    shown = JSON.parse(dialog.scripts.last[/receive\((.*)\)\z/m, 1]).dig("payload", "tokens")

    assert_equal "completed", discovered.fetch("status")
    assert_equal "completed", calls.dig(@row.fetch("id"), "status")
    refute_includes JSON.generate(calls), "secret"
    assert(shown.any? { |row| row["id"] == @row.fetch("id") && row.dig("last_call", "status") == "completed" })
  end

  def test_a_busy_answer_counts_as_the_tokens_latest_call_and_a_listed_token_is_never_evicted
    @server.stop
    @server = server(:starvation_seconds => 0.2, :on_calls => ->(rows) { AgentAccess::Listener.calls_made(rows) })
    result_of(post(rpc("tools/call", "name" => "discover", "arguments" => {})))
    @server.pump
    rotated = Array.new(70) { |index| { "token" => "token_ROTATED#{index}", "at" => "t", "status" => "completed" } }
    AgentAccess::Listener.calls_made(rotated)

    assert_equal "busy", AgentAccess::Listener.last_calls.dig(@row.fetch("id"), "status")
    assert_equal [@row.fetch("id")], AgentAccess::Listener.last_calls.keys
  end

  def test_a_taken_port_shows_before_any_token_is_issued
    AgentAccess::Tokens.revoke(@row.fetch("id"))
    blocker = TCPServer.new("127.0.0.1", 0)
    Sketchup.write_default(PhComposer::Preferences::SECTION, AgentAccess::Listener::PORT_KEY, blocker.addr[1])

    status = AgentAccess::Listener.status

    assert_equal "unavailable", status.fetch("state")
    assert_includes status.fetch("message"), blocker.addr[1].to_s
  ensure
    blocker&.close
  end

  def test_the_stub_refuses_host_calls_off_the_main_thread
    error = Thread.new do
      Sketchup.active_model
    rescue ThreadError => refused
      refused
    end.value

    assert_kind_of ThreadError, error
  end

  private

  def server(starvation_seconds: AgentAccess::Server::STARVATION_SECONDS, clock: nil, on_calls: nil)
    options = { :port => 0, :protocol => AgentAccess::MCP, :executor => @executor, :timer_api => Timers.new(0),
                :starvation_seconds => starvation_seconds, :on_calls => on_calls }
    options[:clock] = clock if clock
    AgentAccess::Server.new(**options).start.tap { |started| started.tokens = AgentAccess::Tokens.snapshot }
  end

  # The tool result, with the pump run on this (main) thread until the reply arrives.
  def call_tool(name, arguments = {})
    request = Thread.new { post(rpc("tools/call", "name" => name, "arguments" => arguments)) }
    pump_until { !request.alive? }
    result_of(request.value)
  end

  # The request in flight, waiting in the server's queue for a pump this test runs itself.
  def queue_tool(name, arguments)
    pending = @server.snapshot.fetch("pending")
    request = Thread.new { post(rpc("tools/call", "name" => name, "arguments" => arguments)) }
    sleep 0.01 until @server.snapshot.fetch("pending") > pending
    request
  end

  def pump_until
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    until yield
      raise "no reply within 10 s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      @server.pump
      sleep 0.01
    end
  end

  # The status for a request that declares a body over the budget, refused before any body is sent.
  def declared_length(bytes)
    socket = TCPSocket.new("127.0.0.1", @server.port)
    socket.write("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:#{@server.port}\r\nAuthorization: Bearer #{@token}\r\n" \
                 "Content-Type: application/json\r\nContent-Length: #{bytes}\r\n\r\n")
    socket.gets.to_s.split(" ")[1]
  ensure
    socket&.close
  end

  def rpc(method, params = nil)
    message = { "jsonrpc" => "2.0", "id" => 7, "method" => method }
    message["params"] = params if params
    JSON.generate(message)
  end

  def post(text, token: @token, path: "/mcp", headers: {})
    http do |client|
      extra = { "Content-Type" => "application/json" }
      extra["Authorization"] = "Bearer #{token}" if token
      client.request(request_for(text, extra.merge(headers), path))
    end
  end

  def request_for(text, headers, path = "/mcp")
    Net::HTTP::Post.new(path).tap do |request|
      headers.each { |name, value| request[name] = value }
      request.body = text
    end
  end

  def http(&block)
    Net::HTTP.start("127.0.0.1", @server.port, :read_timeout => 15, &block)
  end

  def body(response)
    JSON.parse(response.body)
  end

  def result_of(response)
    body(response).fetch("result")
  end

  def error_of(response)
    [body(response).dig("error", "code"), response.code]
  end
end
