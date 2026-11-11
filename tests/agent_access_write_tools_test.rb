# frozen_string_literal: true

require "tmpdir"
require_relative "test_helper"
require_relative "support/test_feature"

# The write tools of the agent connection (context/AGENT_INTERFACE.md, "User-controlled local access"):
# each needs the capability dispatch enforces, `invoke` takes the sequence the connection assigns and an
# optional idempotency key, and a lost reply is recovered by reading state, never by applying twice.
class AgentAccessWriteToolsTest < PhComposerTestCase
  AgentAccess = PhComposer::AgentAccess
  CREATE = "test.fixture.create"
  PARTS = { "parts" => [{ "label" => "Sill", "length_mm" => 1200.0 }] }.freeze

  def setup
    super
    PhComposer::Registry.install([TestFeature])
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @executor = AgentAccess::Executor.new(:tools => AgentAccess::Tools::TABLE)
    @writer = token(%w[read view model_write setup export])
  end

  def token(capabilities)
    issued = AgentAccess::Tokens.issue(:capabilities => capabilities)
    AgentAccess::Tokens.snapshot.fetch(AgentAccess::Tokens.digest(issued.fetch("token")))
  end

  def call(name, arguments = {}, row = @writer)
    result = @executor.call(row, name, { "session" => @session.id }.merge(arguments))
    refute result["isError"], result.inspect
    result.fetch("structuredContent")
  end

  def invoke(arguments = {})
    call("invoke", { "name" => CREATE, "params" => PARTS, "expected_revision" => @session.revision }.merge(arguments))
  end

  def test_each_tool_needs_its_capability_and_tools_list_shows_only_those_held
    reader = token(%w[read])
    listed = ->(row) { AgentAccess::MCP.tools_for(row).map { |tool| tool.fetch("name") } }

    assert_equal %w[discover describe query preview context export_preflight], listed.call(reader)
    assert_equal AgentAccess::Tools::TABLE.keys, listed.call(@writer)
    assert @executor.call(reader, "invoke", "session" => @session.id)["isError"]
    assert_equal({ "invoke" => "model_write", "outcome" => "model_write", "view" => %w[view capture],
                   "setup" => "setup",
                   "export_file" => "export", "start_export" => "export", "latest_export" => "export" },
                 AgentAccess::Tools::TABLE.slice(*%w[invoke outcome view setup export_file start_export
                                                     latest_export]).transform_values(&:capability))
  end

  def test_a_capture_token_reaches_the_view_tool_and_capture_needs_its_grant
    capturer = token(%w[read capture])
    viewer = token(%w[read view])
    captured = call("view", { "name" => "ph_composer.view.capture", "params" => {} }, capturer)
    denied = call("view", { "name" => "ph_composer.view.capture", "params" => {} }, viewer)

    assert_includes AgentAccess::MCP.tools_for(capturer).map { |tool| tool.fetch("name") }, "view"
    assert_equal ["completed", "not_included"], [captured["status"], captured.dig("value", "overlays")]
    assert File.file?(captured.dig("value", "path"))
    assert_equal "request.capability_denied", denied["code"]
  end

  def test_invoke_assigns_the_next_sequence_and_every_result_carries_it
    first = invoke
    second = invoke

    assert_equal [1, 2], [first, second].map { |outcome| outcome["sequence"] }
    assert_equal %w[committed committed], [first, second].map { |outcome| outcome["effect"] }
    assert_equal [], PhComposer::JsonSchema.validate(first, PhComposer::Outcome::SCHEMA)
  end

  def test_a_repeated_key_replays_its_first_outcome_and_another_request_under_it_conflicts
    before = @model.operations.length
    first = invoke("idempotency_key" => "add-sill")
    again = invoke("idempotency_key" => "add-sill", "expected_revision" => first["revision"] - 1)
    other = invoke("idempotency_key" => "add-sill", "params" => { "parts" => [] })

    assert_equal 1, @model.operations.length - before, "applied once"
    assert_equal first.fetch("value"), again.fetch("value")
    assert_equal [1, 1, 1], [first, again, other].map { |outcome| outcome["sequence"] }
    assert_equal "request.sequence_conflict", other["code"]
    assert_equal 2, invoke["sequence"]
  end

  def test_a_lost_invoke_reply_is_read_back_by_key_or_sequence_and_an_expired_one_is_unavailable
    sent = invoke("idempotency_key" => "add-sill")

    by_key = call("outcome", "idempotency_key" => "add-sill")
    by_sequence = call("outcome", "sequence" => sent["sequence"])
    unknown = call("outcome", "idempotency_key" => "never-sent")
    @session.outcomes.clock = -> { Float::INFINITY }
    expired = call("outcome", "idempotency_key" => "add-sill")
    resent = invoke("idempotency_key" => "add-sill")

    assert_equal [sent.fetch("value")] * 2, [by_key, by_sequence].map { |outcome| outcome["value"] }
    assert_equal [1, 1], [by_key, by_sequence].map { |outcome| outcome["sequence"] }
    assert_equal %w[request.outcome_unavailable] * 3, [unknown, expired, resent].map { |outcome| outcome["code"] }
    assert_equal 1, resent["sequence"], "an expired key is never given a new sequence"
  end

  # A refusal before acceptance ran nothing and took no sequence, so the key it bound is free: after another
  # change has run, the same key sent again runs once rather than answering request.outcome_unavailable.
  # session.busy is covered in gesture_guard_test; the executor refuses an unknown session and the API version
  # is fixed by API.connect before an invoke reaches dispatch, so neither binds a key on this route.
  def test_a_key_refused_as_an_unknown_operation_runs_once_when_sent_again
    refused = invoke("idempotency_key" => "k", "name" => "test.fixture.total_length")
    invoke
    sent = invoke("idempotency_key" => "k")
    replay = invoke("idempotency_key" => "k", "expected_revision" => sent["revision"] - 1)

    assert_equal %w[refused request.unknown_operation none], refused.values_at("status", "code", "effect")
    assert_equal %w[completed committed], sent.values_at("status", "effect"), sent.inspect
    assert_equal [3, sent["value"]], [replay["sequence"], replay["value"]]
    assert_equal 2, @model.operations.length
  end

  def test_a_key_refused_for_params_that_are_not_plain_json_is_released
    refused = invoke("idempotency_key" => "k", "params" => { "parts" => ["\xFF".dup.force_encoding("UTF-8")] })

    assert_equal %w[refused request.malformed], refused.values_at("status", "code")
    assert_nil binding_sequencer.lookup("k")
  end

  def test_a_key_refused_because_its_caller_handle_ended_is_released
    invoke
    @session.callers.revoke(AgentAccess.bindings.fetch([@writer.fetch("id"), @session.id]).context.caller)
    refused = invoke("idempotency_key" => "k")

    assert_equal %w[refused access.revoked none], refused.values_at("status", "code", "effect")
    assert_nil binding_sequencer.lookup("k")
  end

  def test_a_key_refused_for_a_missing_capability_is_released
    reader = token(%w[read])
    loose = AgentAccess::Executor::Tool.new(**AgentAccess::Tools::TABLE["invoke"].to_h.merge(:capability => "read"))
    executor = AgentAccess::Executor.new(:tools => AgentAccess::Tools::TABLE.merge("invoke" => loose))
    refused = executor.call(reader, "invoke", "session" => @session.id, "name" => CREATE, "params" => PARTS,
                                              "expected_revision" => @session.revision, "idempotency_key" => "k")
                      .fetch("structuredContent")

    assert_equal %w[refused request.capability_denied], refused.values_at("status", "code")
    assert_nil binding_sequencer(reader).lookup("k")
  end

  # A refusal after acceptance is retained, so its key keeps the sequence and replays it.
  def test_a_key_refused_as_stale_after_acceptance_replays_the_refusal
    stale = invoke("idempotency_key" => "k", "expected_revision" => @session.revision - 1)
    invoke
    again = invoke("idempotency_key" => "k", "expected_revision" => stale["revision"] - 1)

    assert_equal "revision.stale", stale["code"]
    assert_equal [1, "revision.stale"], again.values_at("sequence", "code")
    assert_equal 1, @model.operations.length
  end

  # A handler may refuse after acceptance with a code dispatch also answers before it; that outcome is retained,
  # so its key keeps the sequence and replays it rather than running the handler again.
  module LateRefusal
    module_function

    def install(registry)
      feature = registry.feature("test.late", :contract_version => 1)
      feature.action("test.late.refuse", :description => "Refuse after acceptance.", :params => { "type" => "object" },
                                         :result => { "type" => "object" }, :refuses => [], :undo_name => "Refuse",
                                         :side_effects => "None.") do |_request, _proposal|
        LateRefusal.runs += 1
        raise PhComposer::CodedError.new("request.malformed", "Refused by the handler.")
      end
    end

    class << self
      attr_accessor :runs
    end
  end

  def test_a_key_refused_by_its_handler_after_acceptance_replays_the_refusal
    PhComposer::Registry.install([LateRefusal])
    LateRefusal.runs = 0
    revision = @session.revision
    refused = invoke("idempotency_key" => "k", "name" => "test.late.refuse", "params" => {})
    invoke
    again = invoke("idempotency_key" => "k", "name" => "test.late.refuse", "params" => {},
                   "expected_revision" => revision)

    assert_equal [1, "request.malformed"], refused.values_at("sequence", "code")
    assert_equal [1, "request.malformed"], again.values_at("sequence", "code")
    assert_equal 1, LateRefusal.runs
  end

  # A key bound by an earlier, accepted send keeps its sequence whatever a later send under it is refused,
  # so the change it made is never run twice.
  def test_a_key_already_accepted_keeps_its_sequence_through_a_later_refusal
    first = invoke("idempotency_key" => "k")
    refused = invoke("idempotency_key" => "k", "name" => "test.fixture.total_length")
    replay = invoke("idempotency_key" => "k", "expected_revision" => first["revision"] - 1)

    assert_equal "request.unknown_operation", refused["code"]
    assert_equal [1, first["value"]], [replay["sequence"], replay["value"]]
    assert_equal 1, @model.operations.length
  end

  def binding_sequencer(row = @writer)
    AgentAccess.bindings.fetch([row.fetch("id"), @session.id]).sequencer
  end

  def test_a_committed_change_too_large_to_answer_whole_still_says_it_committed
    parts = Array.new(400) { |index| { "label" => "Part #{index} #{'x' * 40}", "length_mm" => 1.0 } }
    sent = invoke("idempotency_key" => "big", "params" => { "parts" => parts })
    read = call("outcome", "idempotency_key" => "big")

    [sent, read].each do |outcome|
      assert_equal %w[completed committed], outcome.values_at("status", "effect"), outcome.inspect
      assert_equal [1, nil, %w[value affected findings]],
                   [outcome["sequence"], outcome["value"], outcome.dig("detail", "omitted")]
    end
  end

  def test_an_oversized_refusal_keeps_its_sequence_through_invoke_and_outcome
    edits = Array.new(1000) { |index| { "part_id" => "missing_#{index}", "values" => { "label" => "x" * 20 } } }
    sent = call("invoke", "name" => "test.fixture.update_parts", "params" => { "edits" => edits },
                          "expected_revision" => @session.revision)
    read = call("outcome", "sequence" => sent.fetch("sequence"))

    [sent, read].each do |outcome|
      assert_equal [1, "none"], outcome.values_at("sequence", "effect"), outcome.inspect
      assert_equal %w[value affected findings], outcome.dig("detail", "omitted")
    end
  end

  def test_keys_and_sequences_survive_a_listener_restart_and_a_revoke_drops_the_bindings
    first = invoke("idempotency_key" => "k")
    restarted = AgentAccess::Executor.new(:tools => AgentAccess::Tools::TABLE)
    replay = restarted.call(@writer, "invoke", "session" => @session.id, "name" => CREATE, "params" => PARTS,
                                               "expected_revision" => first["revision"] - 1,
                                               "idempotency_key" => "k").fetch("structuredContent")
    AgentAccess::Tokens.revoke(@writer.fetch("id"))
    refused = restarted.call(@writer, "invoke", "session" => @session.id, "name" => CREATE, "params" => PARTS,
                                                "expected_revision" => @session.revision)

    assert_equal [first["value"], 1], [replay["value"], replay["sequence"]]
    assert_equal "access.revoked", refused.dig("structuredContent", "code")
    refute(AgentAccess.bindings.keys.any? { |token_id, _session| token_id == @writer.fetch("id") })
  end

  def test_view_and_setup_run_their_commands_and_a_lost_setup_reply_is_read_back_from_its_state
    Dir.mktmpdir("phc-agent-") do |directory|
      path = File.join(directory, "tags.json")
      File.write(path, "{}")
      PhComposer::Library::Setup.add_file(:id => "synthetic.file", :label => "Synthetic", :path => path)
      looked = call("view", "name" => "test.fixture.look", "params" => { "count" => 1 })
      removed = call("setup", "name" => "ph_composer.library.providers.remove",
                              "params" => { "provider_id" => "synthetic.file" })
      providers = call("query", "name" => "ph_composer.library.providers", "params" => {})

      assert_equal %w[completed completed], [looked, removed].map { |outcome| outcome["status"] }
      refute_includes JSON.generate(providers.fetch("value")), "synthetic.file"
    end
  end

  def test_revoking_in_the_dialog_ends_the_tokens_callers_and_acknowledges_its_exports
    invoke
    dialog = AgentAccess::Dialog.show
    dialog.fire(AgentAccess::Dialog::CALLBACK, JSON.generate("type" => "access.revoke",
                                                             "payload" => { "id" => @writer.fetch("id") }))
    acknowledged = dialog.scripts.map { |script|
      script[/receive\((.*)\)\z/, 1]
    }.compact.map { |json| JSON.parse(json) }
     .find { |message| message["type"] == "access.revoked" }
    refused = @executor.call(@writer, "invoke", "session" => @session.id, "name" => CREATE, "params" => PARTS,
                                                "expected_revision" => @session.revision)

    assert_equal({ "exports_completed" => 0, "exports_stopped" => 0, "changes_committed" => 1, "calls_refused" => 0 },
                 acknowledged.dig("payload", "summary"))
    assert refused["isError"]
    assert_equal "access.revoked", refused.dig("structuredContent", "code")
  end

  def test_resetting_an_unreadable_store_ends_every_tokens_callers
    invoke
    handle = AgentAccess.bindings.values.first.context.caller
    Sketchup.write_default(AgentAccess::Tokens::SECTION, AgentAccess::Tokens::KEY, ["not json"].pack("m0"))
    AgentAccess::Tokens.reset

    assert @session.callers.revoked?(handle)
    assert_empty AgentAccess.bindings
  end

  def test_a_token_revoked_while_its_first_call_waited_is_acknowledged_with_that_refusal
    queued = AgentAccess::Tokens.issue(:capabilities => %w[read]).dig("row", "id")
    waiting = StubAgentServer.new(46_110)
    waiting.define_singleton_method(:refuse_revoked) { |live| live.include?(queued) ? {} : { queued => 1 } }
    AgentAccess::Listener.instance_variable_set(:@server, waiting)

    AgentAccess::Tokens.revoke(queued)

    assert_equal 1, AgentAccess.acknowledgment(queued).fetch("calls_refused")
  end

  def test_a_closed_models_caller_is_not_kept_by_a_live_token
    invoke
    other = Sketchup::Model.new
    closed = PhComposer::Sessions.for(other)
    call("context", { "session" => closed.id })
    other.close
    invoke

    assert_equal [@session], AgentAccess.handles.fetch(@writer.fetch("id")).map(&:first)
  end

  def test_an_export_status_too_large_to_send_keeps_its_artifacts
    artifacts = { "hbjson" => { "path" => "/x/house.hbjson", "sha256" => "a" * 64, "bytes" => 10 } }
    status = { "task_id" => "export_1", "stage" => "finished", "count" => 3, "cancellable" => false,
               "outcome" => { "status" => "completed", "code" => "export.complete", "message" => "Done.",
                              "effect" => "none", "revision" => 1,
                              "value" => { "artifacts" => artifacts, "result" => { "rows" => ["x" * 100] * 400 } } } }
    answer = @executor.send(:result, PhComposer::Outcome.completed(:revision => 1, :value => status), :acted => true)
    value = answer.fetch("structuredContent").fetch("value")

    assert_equal %w[export_1 export.complete], [value["task_id"], value.dig("outcome", "code")]
    assert_equal artifacts, value.dig("outcome", "value", "artifacts")
    refute value.dig("outcome", "value").key?("result")
  end

  def test_a_lost_start_export_reply_is_found_with_latest_export
    Dir.mktmpdir("phc-agent-") do |directory|
      PhComposer::ApprovedLocations.approve(:kind => "save_file", :path => File.join(directory, "model.hbjson"))
      location = call("query", "name" => "ph_composer.locations.list", "params" => {})
                 .dig("value", "locations").find { |row| row["kind"] == "save_file" }
      started = call("start_export", "location" => { "id" => location.fetch("id") })
      latest = call("latest_export")
      status = call("export_status", "task_id" => started.dig("value", "task_id"))
      cancelled = call("cancel_export", "task_id" => started.dig("value", "task_id"))

      assert_equal started.dig("value", "task_id"), latest.dig("value", "task_id")
      assert_equal %w[completed completed], [status, cancelled].map { |outcome| outcome["status"] }
    end
  end
end
