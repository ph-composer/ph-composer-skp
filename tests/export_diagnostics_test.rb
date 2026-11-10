# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/assembly_assignment_fixtures"
require "tmpdir"

# Complete export QA over the agent connection: the current preflight compact and paged by owner, code,
# severity and target; a blocked or failed run's own findings, report and result read back after the Model
# changed; and the metadata extraction refuses reported before a run starts. Every reply fits the budget.
class ExportDiagnosticsTest < PhComposerTestCase
  include AssemblyAssignmentFixtures

  A = PhComposer::AgentAccess
  BUDGET = A::Executor::MAX_RESULT_BYTES

  # A runtime that answers every translation with 240 distinct blocking findings, or closes before answering.
  class Runtime
    def initialize(session_id:, on_message:)
      @session_id = session_id
      @on_message = on_message
    end

    def start; end

    def stop; end

    def translate(id, _document)
      return @on_message.call("runtime.closed", {}) if Runtime.closing

      findings = Array.new(240) do |index|
        { "code" => index.even? ? "object.unavailable" : "object.invalid", "section" => "synthetic",
          "object_id" => "fixture_#{index}", "message" => "Runtime finding #{index}: #{'detail ' * 20}",
          "blocks_export" => index != 7 }
      end
      if Runtime.long_id
        findings << { "code" => "object.long", "section" => "synthetic", "object_id" => Runtime.long_id,
                      "message" => "One finding about a record with a long id.", "blocks_export" => true }
      end
      @on_message.call("runtime.translation", "request_id" => id, "result" => {
        "schema_version" => 1, "run_id" => id, "state" => "complete_with_findings", "sections" => [],
        "failure" => nil, "findings" => findings,
        "summary" => { "objects" => 0, "unavailable" => 240, "findings" => 240, "publishable" => false }
      })
    end

    class << self
      attr_accessor :closing, :long_id
    end
  end

  def setup
    super
    assignment_setup
    Runtime.closing = false
    @directory = Dir.mktmpdir("phc-export-diagnostics-")
    @executor = A::Executor.new(:tools => A::Tools::TABLE)
    @token = token(%w[read model_write export])
  end

  def teardown
    PhComposer::Export::Tasks.for(@session).detach
    FileUtils.remove_entry(@directory)
    super
  end

  def test_an_oversized_preflight_is_counted_and_paged_completely_by_owner_code_and_severity
    assignment_zone(1000, 180)
    whole = PhComposer::API.export_preflight(:context => @context).fetch("value")
    assert_operator JSON.generate(whole).bytesize, :>, BUDGET
    compact = agent("export_preflight", "compact" => true).fetch("value")
    zones = compact.fetch("by_owner").find { |row| row["owner"] == "ph_composer.zones" }
    assert_equal [false, whole.fetch("findings").length],
                 [compact.fetch("ready"), compact.dig("totals", "findings")]
    assert_operator zones.fetch("findings"), :>=, 180
    assert_equal whole.fetch("findings").count { |row| row["blocks_export"] }, compact.dig("totals", "blocking")
    assert_equal 180, compact.fetch("by_code").find { |row| row["code"] == "face.unclassified" }.fetch("findings")

    rows = pages("export_preflight", { "part" => "findings", "limit" => 500 }, "findings")
    assert_operator rows.length, :>, 0
    assert_equal whole.fetch("findings"), rows.map { |row| row.reject { |key, _value| %w[owner row].include?(key) } }
    blocking = pages("export_preflight", { "part" => "findings", "blocks_export" => true,
                                           "codes" => ["face.unclassified"], "owner" => "ph_composer.zones" },
                     "findings")
    assert_equal 180, blocking.length
    first = agent("export_preflight", "part" => "findings", "codes" => ["face.unclassified"], "limit" => 1)
    assert_equal [1, 180, whole.fetch("findings").length],
                 [first.dig("value", "findings").length, first.dig("value", "total"),
                  first.dig("value", "unfiltered_total")]
    target = blocking.first
    by_target = agent("export_preflight", "part" => "findings", "object_id" => target.fetch("object_id") || "none")
    assert_operator by_target.dig("value", "total"), :<=, 180
    whole_row = joined("export_preflight", "part" => "findings", "row" => target.fetch("row"))
    assert_equal whole.fetch("findings")[whole_row_index(whole, target)], whole_row.reject { |key, _value|
      key == "owner"
    }

    repairs = pages("export_preflight", { "part" => "repairs" }, "repairs")
    assert_equal whole.fetch("repairs"), repairs.map { |row| row.reject { |key, _value| %w[owner row].include?(key) } }

    cursor = first.dig("value", "next_cursor")
    assignment_assembly("A change")
    expired = agent("export_preflight", "part" => "findings", "codes" => ["face.unclassified"], "limit" => 1,
                                        "cursor" => cursor)
    assert_equal "query.cursor_expired", expired.fetch("code")
    assert_equal "params.invalid", agent("export_preflight", "limit" => 1).fetch("code")
    assert_equal "params.invalid", agent("export_preflight", "part" => "repairs", "codes" => ["x"]).fetch("code")
    assert_equal "params.invalid", agent("export_preflight", "part" => "findings", "compact" => true).fetch("code")
  end

  def test_a_blocked_run_keeps_its_own_findings_report_and_result_after_the_model_changes
    task = blocked_run
    status = agent("export_status", "task_id" => task, "compact" => true).fetch("value")
    diagnostics = status.fetch("diagnostics")
    assert_equal [240, 239, nil], diagnostics.values_at("findings", "blocking", "report_absent")
    assert_equal "export.blocked", status.dig("outcome", "code")
    refute status.fetch("outcome").key?("findings")
    assert_equal %w[export_generation revision], status.fetch("source").keys.sort
    assert_empty Dir.children(@directory), "a blocked run writes no pair"

    whole = PhComposer::API.export_status(:context => binding_context, :task_id => task).dig("value", "outcome")
    assignment_zone(3000, 2)
    findings = pages("export_status", { "task_id" => task, "part" => "findings" }, "findings")
    assert_equal whole.fetch("findings"), findings.map { |row| row.reject { |key, _value| key == "row" } }
    assert_equal (0...240).map { |index| [index] }, findings.map { |row| row.fetch("row") }
    warnings = pages("export_status", { "task_id" => task, "part" => "findings", "blocks_export" => false }, "findings")
    assert_equal ["fixture_7"], warnings.map { |row| row.fetch("object_id") }
    report = joined("export_status", "task_id" => task, "part" => "report")
    assert_equal whole.dig("value", "report_html"), report
    assert_includes report, "Runtime finding 239"
    assert_equal whole.dig("value", "result"), joined("export_status", "task_id" => task, "part" => "result")
    assert_equal whole.dig("findings", 3),
                 joined("export_status", "task_id" => task, "part" => "findings", "row" => [3])
    agent("latest_export", "compact" => true).fetch("value").then do |latest|
      assert_equal [task, diagnostics], latest.values_at("task_id", "diagnostics")
    end
  end

  def test_task_reads_honour_the_owner_running_expiry_revocation_and_early_failure
    Runtime.closing = true
    task = blocked_run
    status = agent("export_status", "task_id" => task, "compact" => true).fetch("value")
    assert_equal ["runtime.closed", "no_translation", nil],
                 [status.dig("outcome", "code"), status.dig("diagnostics", "report_absent"),
                  status.dig("diagnostics", "report")]
    absent = agent("export_status", "task_id" => task, "part" => "report")
    assert_equal "target.not_found", absent.fetch("code")
    assert_includes absent.fetch("message"), "before translation"
    assert_equal 0, agent("export_status", "task_id" => task, "part" => "findings").dig("value", "total")

    other = token(%w[read export])
    foreign = @executor.call(other, "export_status", "session" => @session.id, "task_id" => task, "part" => "findings")
    assert_equal "task.foreign", foreign.dig("structuredContent", "code")

    Runtime.closing = false
    running = agent("start_export", "location" => { "id" => approved }).dig("value", "task_id")
    assert_equal "task.running", agent("export_status", "task_id" => running, "part" => "findings").fetch("code")
    PhComposer::RuntimeHost.stub(:new, ->(**args) { Runtime.new(**args) }) { UI.run_timers }
    cursor = agent("export_status", "task_id" => running, "part" => "findings", "limit" => 10).dig("value",
                                                                                                   "next_cursor")
    assert cursor
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.stub(:clock_gettime, ->(*) { now + PhComposer::Export::Tasks::RETENTION_SECONDS + 1 }) do
      expired = agent("export_status", "task_id" => running, "part" => "findings", "limit" => 10, "cursor" => cursor)
      assert_equal "task.expired", expired.fetch("code")
    end

    A::Tokens.revoke(@token.fetch("id"))
    revoked = @executor.call(@token, "export_status", "session" => @session.id, "task_id" => task, "part" => "report")
    assert_equal "access.revoked", revoked.dig("structuredContent", "code")
  end

  def test_an_oversized_kept_row_is_refused_by_page_and_read_whole_by_row
    Runtime.long_id = "x" * 30_000
    task = blocked_run
    page = @executor.call(@token, "export_status", "session" => @session.id, "task_id" => task, "part" => "findings",
                                                   "codes" => ["object.long"])
    assert_equal "request.response_too_large", page.dig("structuredContent", "code")
    row = joined("export_status", "task_id" => task, "part" => "findings", "row" => [240])
    assert_equal "x" * 30_000, row.fetch("object_id")
  ensure
    Runtime.long_id = nil
  end

  def test_a_failure_message_over_the_budget_keeps_the_task_and_reads_whole
    ready_model
    face = PhComposer::Zones::Faces::FACE_STORE
    entity = assignment_entity
    namespace = "test.#{'n' * 30_000}"
    face.write(entity, face.read(entity).merge("extension_data" => { namespace => envelope("unknown") }))
    task = blocked_run
    status = agent("export_status", "task_id" => task, "compact" => true).fetch("value")
    assert_equal [task, "export.relevance_unknown", ["message"]],
                 [status.fetch("task_id"), status.dig("outcome", "code"), status.dig("outcome", "truncated")]
    whole = agent("export_status", "task_id" => task).fetch("value")
    assert_equal [task, "export.relevance_unknown"], [whole.fetch("task_id"), whole.dig("outcome", "code")]
    outcome = joined("export_status", "task_id" => task, "part" => "outcome")
    assert_includes outcome.fetch("message"), namespace
  end

  def test_a_closed_session_drops_its_tasks
    task = blocked_run
    PhComposer::Export::Tasks.for(@session).detach
    assert_equal "task.expired", agent("export_status", "task_id" => task, "part" => "findings").fetch("code")
  end

  def test_preflight_reports_the_metadata_extraction_refuses_on_an_otherwise_ready_model
    ready_model
    assert_empty blocking_codes
    assert agent("export_preflight", "compact" => true).dig("value", "ready")
    face = PhComposer::Zones::Faces::FACE_STORE
    entity = assignment_entity
    stored = face.read(entity)
    { "local_only" => [], "required" => ["extension.unavailable"] }.each do |relevance, codes|
      face.write(entity, stored.merge("extension_data" => { "test.other" => envelope(relevance) }))
      assert_equal codes, blocking_codes.uniq, relevance
    end
    face.write(entity, stored.merge("extension_data" => { "test.one" => envelope("required"),
                                                          "test.two" => envelope("required") }))
    named = PhComposer::API.export_preflight(:context => @context).dig("value", "findings")
                           .select { |row| row["object_id"] == stored.fetch("id") }.map { |row| row.fetch("message") }
    assert_equal 2, named.count { |message| message.include?("test.one") || message.include?("test.two") }
    face.write(entity, stored)
    assembly = PhComposer::Assemblies::Assembly::Schema::KIND.store
    record = assembly.read(@model, "asm_Single000001")
    assembly.write(@model, record.merge("user_data" => { "ph_composer" => "reserved", "kept" => 1 }))
    face.write(entity, face.read(entity).merge("extension_data" => { "test.unknown" => { "payload" => {} } }))
    rows = PhComposer::API.export_preflight(:context => @context).dig("value", "findings").select { |row|
      row["blocks_export"]
    }
    named = rows.select { |row| row["object_id"] }.map { |row| row.values_at("code", "object_id") }
    assert_equal [["export.blocked", "asm_Single000001"], ["export.relevance_unknown", face.read(entity).fetch("id")]],
                 named.sort_by(&:first)
    # Windows' projection reads the Faces section through extraction's reader, which stops at the same problem.
    assert_equal %w[export.blocked export.relevance_unknown], rows.map { |row| row.fetch("code") }.uniq.sort
    assert_equal({ "ph_composer" => "reserved", "kept" => 1 }, assembly.read(@model, "asm_Single000001")["user_data"],
                 "nothing is sanitized")

    outcome = agent("export_status", "task_id" => blocked_run, "compact" => true).dig("value", "outcome")
    assert_includes rows.map { |row| row.values_at("code", "message") }, outcome.values_at("code", "message")
    assert_empty Dir.children(@directory)
  end

  private

  def token(capabilities)
    issued = A::Tokens.issue(:capabilities => capabilities)
    A::Tokens.snapshot.fetch(A::Tokens.digest(issued.fetch("token")))
  end

  # The structuredContent of one tool call, after checking it fits the reply budget.
  def agent(tool, params)
    answer = @executor.call(@token, tool, { "session" => @session.id }.merge(params))
    assert_operator JSON.generate(answer.fetch("structuredContent")).bytesize, :<=, BUDGET
    answer.fetch("structuredContent")
  end

  def pages(tool, params, list)
    rows = []
    cursor = nil
    loop do
      answer = agent(tool, cursor ? params.merge("cursor" => cursor) : params)
      assert_equal "completed", answer["status"], answer.inspect
      rows.concat(answer.dig("value", list))
      cursor = answer.dig("value", "next_cursor")
      break unless cursor
    end
    rows
  end

  # The value whose fragments a part or row read answers, joined, checked and parsed.
  def joined(tool, params)
    text = +""
    cursor = nil
    sha = nil
    loop do
      answer = agent(tool, cursor ? params.merge("cursor" => cursor) : params)
      assert_equal "completed", answer["status"], answer.inspect
      fragment = answer.dig("value", "fragment")
      text << fragment.fetch("text")
      sha = fragment.fetch("sha256")
      cursor = answer.dig("value", "next_cursor")
      break unless cursor
    end
    assert_equal sha, Digest::SHA256.hexdigest(text)
    JSON.parse(text)
  end

  def whole_row_index(whole, row)
    whole.fetch("findings").index { |finding|
      finding == row.reject { |key, _value|
        %w[owner row truncated].include?(key)
      }
    }
  end

  def binding_context
    A.bindings.fetch([@token.fetch("id"), @session.id]).context
  end

  def approved
    PhComposer::ApprovedLocations.approve(:kind => "save_file",
                                          :path => File.join(@directory,
                                                             "test.hbjson")).fetch("id")
  end

  def blocked_run
    PhComposer::RuntimeHost.stub(:new, ->(**args) { Runtime.new(**args) }) do
      started = agent("start_export", "location" => { "id" => approved })
      UI.run_timers
      started.dig("value", "task_id")
    end
  end

  # One Zone with one Wall Face on a complete Assembly: nothing the preflight checks blocks.
  def ready_model
    fixture = JSON.parse(File.read(File.join(TESTS_ROOT, "fixtures", "assemblies", "authoring.json")))
    fixture.fetch("materials").each { |row| PhComposer::Assemblies::Materials::Schema::KIND.store.write(@model, row) }
    row = fixture.fetch("assemblies").find { |entry| entry["id"] == "asm_Single000001" }
    PhComposer::Assemblies::Assembly::Schema::KIND.store.write(@model, row)
    assignment_zone(800)
    assignment_classify(assignment_faces, "face_type" => { "mode" => "set", "value" => "Wall" },
                                          "boundary_condition" => { "mode" => "set", "value" => "Outdoors" })
    assignment_invoke("#{FACE_PREFIX}.assign_assembly", assignment_params(assignment_faces, row.fetch("id")))
  end

  def assignment_entity
    @model.entities.to_a.find { |entity| entity.persistent_id == 800 }.entities.to_a.find do |entity|
      entity.is_a?(Sketchup::Face)
    end
  end

  def envelope(relevance)
    { "schema_version" => 1, "payload" => { "note" => "x" }, "references" => [], "export_relevance" => relevance }
  end

  def blocking_codes
    PhComposer::API.export_preflight(:context => @context).dig("value", "findings")
                   .select { |row| row["blocks_export"] }.map { |row| row.fetch("code") }
  end
end
