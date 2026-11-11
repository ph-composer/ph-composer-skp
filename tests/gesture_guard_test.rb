# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/test_feature"

# A change's commit cancels a native Move partway through (context/SKETCHUP_HOST_BEHAVIOR.md), so a change
# request refuses `session.busy` while the user is mid-Move, before it takes a sequence; reads, context and
# the Line tool are unaffected (context/AGENT_INTERFACE.md, "Model context").
class GestureGuardTest < PhComposerTestCase
  API = PhComposer::API
  AgentAccess = PhComposer::AgentAccess
  CREATE = "test.fixture.create"
  PARTS = { "parts" => [{ "label" => "Sill", "length_mm" => 1200.0 }] }.freeze

  def setup
    super
    PhComposer::Registry.install([TestFeature])
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @writer = API.connect(:session_id => @session.id, :capabilities => %w[read model_write])
  end

  def test_the_session_follows_the_active_tool_and_its_state
    tools = @model.tools

    tools.use_native_tool("MoveTool", 1)
    moving = @session.gesture_reason
    tools.use_native_tool("MoveTool", 0)
    idle = @session.gesture_reason
    tools.use_native_tool("MoveTool", 1)
    tools.use_native_tool("SketchTool")
    switched = @session.gesture_reason
    tools.use_native_tool("MoveTool", 1)
    tools.observers.each { |observer| observer.onActiveToolChanged(tools, "MoveTool", 1) }
    chosen_again = @session.gesture_reason

    assert_includes moving, "MoveTool"
    assert_nil idle
    assert_nil switched
    assert_nil chosen_again
  end

  def test_a_recorded_move_does_not_hold_writes_once_the_host_names_another_tool
    @model.tools.use_native_tool("MoveTool", 1)
    @model.select_tool(Object.new.tap { |tool| tool.define_singleton_method(:activate) { nil } })

    assert_equal "RubyTool", @model.tools.active_tool_name
    assert_nil @session.gesture_reason
  end

  def test_a_write_during_a_move_is_refused_busy_writes_nothing_and_runs_after_a_cancelled_move
    @model.tools.use_native_tool("MoveTool", 1)
    revision = @session.revision

    refused = invoke(1)
    @model.tools.use_native_tool("MoveTool", 0)
    later = invoke(1)

    assert_equal %w[busy session.busy none], refused.values_at("status", "code", "effect")
    assert_includes refused["message"], "MoveTool"
    assert_equal ["completed", "committed", revision + 1], later.values_at("status", "effect", "revision")
    assert_equal 1, @model.operations.length
  end

  # The user's finished Move is a commit of its own, so the held request is stale and its caller decides again.
  def test_after_a_finished_move_the_held_request_is_stale_and_a_new_one_runs
    @model.tools.use_native_tool("MoveTool", 1)
    revision = @session.revision
    refused = invoke(1, revision)
    @model.tools.use_native_tool("MoveTool", 0)
    @session.host_event(:transaction_committed)

    stale = invoke(1, revision)
    fresh = invoke(2)

    assert_equal "session.busy", refused["code"]
    assert_equal "revision.stale", stale["code"]
    assert_equal %w[completed committed], fresh.values_at("status", "effect")
  end

  def test_a_retry_of_a_change_that_already_ran_answers_its_outcome_during_a_move
    revision = @session.revision
    first = invoke(1, revision)
    @model.tools.use_native_tool("MoveTool", 1)

    assert_equal first, invoke(1, revision)
    assert_equal 1, @model.operations.length
  end

  def test_an_agent_invoke_during_a_move_answers_busy
    row = token(%w[read model_write])
    executor = AgentAccess::Executor.new(:tools => AgentAccess::Tools::TABLE)
    @model.tools.use_native_tool("MoveTool", 1)

    answer = executor.call(row, "invoke", "session" => @session.id, "name" => CREATE, "params" => PARTS,
                                          "expected_revision" => @session.revision).fetch("structuredContent")

    assert_equal %w[busy session.busy none], answer.values_at("status", "code", "effect")
    assert_empty @model.operations
  end

  # A busy invoke took no sequence in dispatch, so its key is free: two keys refused during a Move both run
  # afterwards, in either order, each once.
  def test_agent_keys_refused_during_a_move_run_once_each_afterwards_in_any_order
    row = token(%w[read model_write])
    executor = AgentAccess::Executor.new(:tools => AgentAccess::Tools::TABLE)
    send = lambda do |key, revision = @session.revision|
      executor.call(row, "invoke", "session" => @session.id, "name" => CREATE, "params" => PARTS,
                                   "expected_revision" => revision, "idempotency_key" => key)
              .fetch("structuredContent")
    end
    @model.tools.use_native_tool("MoveTool", 1)
    refused = [send.call("a"), send.call("b")]
    @model.tools.use_native_tool("MoveTool", 0)

    later = [send.call("b"), send.call("a", (revision = @session.revision))]
    replay = send.call("a", revision)

    assert_equal %w[session.busy session.busy], refused.map { |answer| answer["code"] }
    assert_equal %w[completed completed], later.map { |answer| answer["status"] }
    assert_equal later.last["value"], replay["value"]
    assert_equal 2, @model.operations.length
  end

  def test_writes_run_with_move_idle_and_with_the_line_tool_partway
    @model.tools.use_native_tool("MoveTool", 0)
    idle = invoke(1)
    @model.tools.use_native_tool("SketchTool", 1)
    drawing = invoke(2)

    assert_equal %w[completed completed], [idle["status"], drawing["status"]]
  end

  def test_reads_previews_and_context_answer_during_a_move_and_context_says_why
    @model.tools.use_native_tool("MoveTool", 1)

    read = API.query(:context => @writer, :name => "test.fixture.total_length", :params => {})
    preview = API.preview(:context => @writer, :name => CREATE, :params => PARTS)
    readiness = API.query(:context => @writer, :name => PhComposer::ContextCommands::READ,
                          :params => {}).dig("value", "readiness")

    assert_equal %w[completed completed], [read["status"], preview["status"]]
    assert_equal [true, @session.gesture_reason, "MoveTool"], readiness.values_at("busy", "reason", "active_tool")
    assert API.discover.fetch("sessions").find { |row| row["id"] == @session.id }.fetch("busy")
  end

  def test_detaching_the_session_removes_its_tools_observer
    model = Sketchup::Model.new
    session = PhComposer::Sessions.for(model)
    _tools, observer = session.observers.tools

    PhComposer::Sessions.detach(model)

    refute_includes model.tools.observers, observer
  end

  private

  def invoke(sequence, revision = @session.revision)
    API.invoke(:context => @writer, :name => CREATE, :params => PARTS,
               :request => { "sequence" => sequence, "expected_revision" => revision })
  end

  def token(capabilities)
    issued = AgentAccess::Tokens.issue(:capabilities => capabilities)
    AgentAccess::Tokens.snapshot.fetch(AgentAccess::Tokens.digest(issued.fetch("token")))
  end
end
