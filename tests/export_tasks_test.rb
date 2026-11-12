# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "digest"

class ExportTasksTest < PhComposerTestCase
  OWNER = PhComposer::Export::Tasks::Owner.new("test-owner", -> { true })
  class Runtime
    attr_reader :document, :stopped

    def initialize(&callback)
      @callback = callback
    end

    def start; end

    def translate(id, document)
      @id = id
      @document = document
    end

    def stop
      @stopped = true
    end

    def blocked(canonical: nil)
      result = {
        "schema_version" => 1, "run_id" => @id, "state" => "complete_with_findings",
        "summary" => { "objects" => 0, "unavailable" => 1, "findings" => 1, "publishable" => false },
        "sections" => [], "failure" => nil,
        "findings" => [{ "code" => "object.unavailable", "section" => "fixture",
                         "object_id" => "zone", "message" => "Choose an authored construction.",
                         "blocks_export" => true }]
      }
      result["canonical_model"] = canonical if canonical
      @callback.call("runtime.translation", "request_id" => @id, "result" => result)
    end

    def close
      @callback.call("runtime.closed", {})
    end

    def ready
      @callback.call("runtime.ready", {})
    end

    def failure(error)
      @callback.call("runtime.translation", "request_id" => @id, "error" => error)
    end

    def success
      success_with({ "type" => "Model", "rooms" => [] })
    end

    def success_with(model, findings: [])
      @callback.call("runtime.translation", "request_id" => @id, "result" => {
        "schema_version" => 1, "run_id" => @id, "state" => "complete",
        "summary" => { "objects" => 0, "unavailable" => 0, "findings" => findings.length, "publishable" => true },
        "sections" => [], "failure" => nil, "findings" => findings,
        "canonical_model" => { "hbjson" => JSON.generate(model),
                               "rooms" => 0, "faces" => 0, "surface_pairs" => 0 }
      })
    end
  end

  # Deferred feature work that commits once when the session settles, as deferred protection does.
  class DeferredCommit
    def initialize(session)
      @session = session
      @pending = true
    end

    def settle
      @session.outside_commit if @pending
      @pending = false
    end
  end

  def setup
    super
    @directory = Dir.mktmpdir("phc-export-task-")
    @session = PhComposer::Sessions.for(Sketchup.active_model)
    @tasks = PhComposer::Export::Tasks.for(@session)
    @factory = ->(&callback) { @runtime = Runtime.new(&callback) }
    @destination = File.join(@directory, "test.hbjson")
  end

  def teardown
    @tasks.detach
    FileUtils.remove_entry(@directory)
    super
  end

  def test_tasks_are_pollable_detached_and_can_cancel_before_collection_without_boot
    task = start
    task["stage"] = "tampered"
    assert_equal "queued", @tasks.status(task.fetch("task_id"), OWNER).fetch("stage")
    result = @tasks.cancel(task.fetch("task_id"), OWNER)
    drain

    assert_equal "cancelled", result.dig("outcome", "status")
    assert_nil @runtime
    assert_empty Dir.children(@directory)
  end

  def test_edit_context_and_selection_do_not_invalidate_but_content_changes_do
    task = start
    @session.model.active_path = []
    @session.model.selection.add(Sketchup::Face.new(99))
    drain
    assert_equal "translating", @tasks.status(task.fetch("task_id"), OWNER).fetch("stage")

    @session.model.start_operation("External edit")
    @session.model.set_attribute("test", "value", 1)
    @session.model.commit_operation
    @runtime.blocked
    assert_equal "export.model_changed", @tasks.status(task.fetch("task_id"), OWNER).dig("outcome", "code")
    assert @runtime.stopped
    assert_empty Dir.children(@directory)
  end

  def test_native_edit_path_commit_is_navigation_but_the_preceding_content_commit_is_not
    group = Sketchup::Group.new(900, Sketchup::Entities.new([]))
    @session.model.entities << group
    initial = @session.export_generation
    @session.host_event(:transaction_committed)
    assert_equal initial + 1, @session.export_generation
    @session.model.instance_variable_set(:@active_path, [group])
    @session.host_event(:transaction_committed)
    @session.host_event(:active_path_changed)
    assert_equal initial + 1, @session.export_generation
    @session.host_event(:transaction_committed)
    assert_equal initial + 2, @session.export_generation
  end

  # A warning the preflight showed is in the report and the run summary's count too, once even when the
  # translation reports the same condition on the same object (W-119: preflight listed four, the report none).
  def test_preflight_warnings_reach_the_report_and_the_findings_count
    context = PhComposer::API.connect(:session_id => @session.id, :capabilities => %w[read model_write export])
    material = PhComposer::API.invoke(
      :context => context, :name => "ph_composer.assemblies.materials.create",
      :params => { "values" => { "name" => "Mineral wool", "conductivity_w_mk" => 0.035 } },
      :request => { "sequence" => 1, "expected_revision" => @session.revision }
    ).dig("value", "id")
    warning = PhComposer::API.export_preflight(:context => context).dig("value", "findings").first
    assert_equal ["material.thermal_mass_defaulted", material, false],
                 warning.values_at("code", "object_id", "blocks_export")

    task = start
    drain
    @runtime.success
    drain
    result = @tasks.status(task.fetch("task_id"), OWNER).dig("outcome", "value", "result")
    assert_equal ["complete_with_findings", 1], [result.fetch("state"), result.dig("summary", "findings")]
    assert_equal [warning.slice("code", "section", "object_id", "message", "blocks_export")], result.fetch("findings")
    report = File.read(PhComposer::Export::ArtifactPair.report_path(@destination))
    assert_includes report, PhComposer::Export::ReportHtml.h(warning.fetch("message"))

    reported = warning.slice("code", "section", "object_id").merge("message" => "Translated.", "blocks_export" => false)
    task = start(:replace => true)
    drain
    @runtime.success_with({ "type" => "Model", "rooms" => [] }, :findings => [reported])
    drain
    assert_equal [reported], @tasks.status(task.fetch("task_id"), OWNER).dig("outcome", "value", "result", "findings")
  end

  # A preflight lists a repeated condition once per part (one row per unassigned Layer-Segment of an
  # Assembly); the report lists it once per code and object.
  def test_repeated_preflight_warnings_for_one_object_are_listed_once
    warning = { "code" => "assembly.segment_unassigned", "section" => "fixture", "object_id" => "asm_1",
                "message" => "A Layer-Segment has no Material.", "blocks_export" => false }
    task = start
    PhComposer::Export.stub(:preflight_warnings, [warning, warning.dup]) { drain }
    @runtime.success
    drain

    assert_equal [warning], @tasks.status(task.fetch("task_id"), OWNER).dig("outcome", "value", "result", "findings")
  end

  # Leaving a preflight's warnings out is the defect above, so a preflight that cannot answer fails the run
  # before translation and nothing is written.
  def test_a_preflight_that_raises_fails_the_run_and_writes_nothing
    task = start
    broken = ->(*) { raise PhComposer::InternalError, "Preflight broke." }
    PhComposer::Export.stub(:preflight_warnings, broken) { drain }

    outcome = @tasks.status(task.fetch("task_id"), OWNER).fetch("outcome")
    assert_equal %w[failed export.failed], outcome.values_at("status", "code")
    assert_nil @runtime
    assert_empty Dir.children(@directory)
  end

  def test_blocking_results_keep_findings_and_write_no_pair
    task = start
    drain
    @runtime.blocked
    outcome = @tasks.status(task.fetch("task_id"), OWNER).fetch("outcome")

    assert_equal %w[refused export.blocked none], outcome.values_at("status", "code", "effect")
    assert_equal "Choose an authored construction.", outcome.dig("findings", 0, "message")
    assert @runtime.stopped
    assert_empty Dir.children(@directory)
    assert_empty @session.model.operations
  end

  def test_a_blocked_run_with_partial_output_carries_no_hbjson_in_its_report
    task = start
    drain
    @runtime.blocked(:canonical => { "hbjson" => JSON.generate("type" => "Model", "rooms" => [],
                                                               "identifier" => "PARTIAL-MODEL-BYTES"),
                                     "rooms" => 1, "faces" => 0, "surface_pairs" => 0 })
    html = @tasks.status(task.fetch("task_id"), OWNER).dig("outcome", "value", "report_html")
    refute_includes html, "PARTIAL-MODEL-BYTES"
  end

  def test_a_publishable_result_with_no_model_is_reported_as_not_created
    result = { "schema_version" => 1, "run_id" => "run", "state" => "complete",
               "summary" => { "objects" => 0, "unavailable" => 0, "findings" => 0, "publishable" => true },
               "sections" => [], "findings" => [], "failure" => nil }
    html = PhComposer::Export::Report.render(result)
    assert_includes html, "<h1>Export not created</h1>"
    assert_includes html, PhComposer::Export::Report::BLOCKED_LINE
  end

  def test_a_blocked_run_carries_its_report_labelled_as_writing_no_model
    task = start
    drain
    @runtime.blocked
    html = @tasks.status(task.fetch("task_id"), OWNER).dig("outcome", "value", "report_html")
    assert_includes html, "<h1>Export not created</h1>"
    assert_includes html, PhComposer::Export::Report::BLOCKED_LINE
    assert_empty Dir.children(@directory), "nothing is written beside the destination"
  end

  def test_a_blocked_run_with_partial_canonical_output_never_returns_bytes_in_status
    task = start
    drain
    @runtime.blocked(:canonical => { "hbjson" => JSON.generate("type" => "Model", "rooms" => []),
                                     "rooms" => 1, "faces" => 6, "surface_pairs" => 0 })
    outcome = @tasks.status(task.fetch("task_id"), OWNER).fetch("outcome")
    refute outcome.dig("value", "result", "canonical_model").key?("hbjson")
    assert_equal 1, outcome.dig("value", "result", "canonical_model", "rooms")
    assert_equal outcome, @tasks.latest(OWNER).fetch("outcome")
    assert_equal 1, outcome.fetch("findings").length
    assert_empty Dir.children(@directory)
  end

  def test_runtime_close_finishes_and_model_close_cancels_and_tears_down
    task = start
    drain
    @runtime.close
    assert_equal "runtime.closed", @tasks.status(task.fetch("task_id"), OWNER).dig("outcome", "code")
    assert @runtime.stopped

    start
    drain
    @session.model.close
    UI.run_timer(UI.timer_intervals.find { |_id, interval| interval == 0.2 }.first)
    drain
    assert @runtime.stopped
    assert_nil @tasks.latest(OWNER)
    assert_empty Dir.children(@directory)
  end

  # REVIEW F05: a runtime that never answered stayed translating, cancellable, with no outcome, after an hour.
  def test_a_runtime_that_never_starts_ends_the_run_after_its_boot_deadline
    task = start
    drain
    deadline = (PhComposer::RuntimeGate.fetch("boot_deadline_ms") / 1000.0) +
               PhComposer::Export::Task::STARTUP_GRACE_SECONDS

    watch_after(deadline - 1)
    assert_equal "translating", @tasks.status(task.fetch("task_id"), OWNER).fetch("stage")
    watch_after(deadline + 1)

    outcome = @tasks.status(task.fetch("task_id"), OWNER).fetch("outcome")
    assert_equal %w[failed runtime.boot_timeout none], outcome.values_at("status", "code", "effect")
    logged = JSON.parse(PhComposer::Diagnostics.tail.last)
    assert_equal ["export_runtime_failed", "boot", "runtime.boot_timeout", task.fetch("task_id")],
                 logged.values_at("event", "stage", "code", "run_id")
    assert @runtime.stopped
    @runtime.success
    assert_equal "runtime.boot_timeout", @tasks.status(task.fetch("task_id"), OWNER).dig("outcome", "code"),
                 "a late answer applies nothing"
    assert_empty Dir.children(@directory)
  end

  def test_a_ready_runtime_that_stops_answering_ends_the_run_after_its_silence_deadline
    task = start
    drain
    watch_after(10)
    Process.stub(:clock_gettime, ->(*) { @clock_origin + 10 }) { @runtime.ready }
    silence = PhComposer::Export::Task::TRANSLATION_SILENCE_SECONDS

    watch_after(10 + silence - 1)
    assert_equal "translating", @tasks.status(task.fetch("task_id"), OWNER).fetch("stage"),
                 "the translation clock starts when the page is ready"
    watch_after(10 + silence + 1)

    outcome = @tasks.status(task.fetch("task_id"), OWNER).fetch("outcome")
    assert_equal %w[failed runtime.unresponsive none], outcome.values_at("status", "code", "effect")
    assert @runtime.stopped
    assert_empty Dir.children(@directory)
  end

  # REVIEW F03: the task replaced every runtime code with runtime.translation_failed.
  def test_a_runtime_failure_keeps_its_stage_and_code_in_the_log_and_a_fixed_message
    frames = [{ "file" => "ph_composer_translation/conformance.py", "line" => 40, "method" => "check" }]
    { "runtime.conformance_failed" => "conformance", "runtime.boot_failed" => "boot",
      "runtime.undeclared" => "translation" }.each do |code, stage|
      task = start
      drain
      @runtime.failure("code" => code, "stage" => stage, "error_class" => "ConformanceError", "frames" => frames,
                       "message" => "Zone North /Users/example/model.skp")
      outcome = @tasks.status(task.fetch("task_id"), OWNER).fetch("outcome")
      logged = JSON.parse(PhComposer::Diagnostics.tail.last)

      expected = code == "runtime.undeclared" ? "runtime.translation_failed" : code
      assert_equal expected, outcome.fetch("code")
      refute_includes outcome.fetch("message"), "Zone North"
      assert_equal [task.fetch("task_id"), stage, code, frames], logged.values_at("run_id", "stage", "code", "frames")
      refute_includes PhComposer::Diagnostics.tail.join, "Zone North"
    end
  end

  # A runtime answer arrives after the panel request that started the run has returned; its log lines still
  # name that request and the run.
  def test_a_late_runtime_failure_is_logged_under_the_request_that_started_the_run
    request = "#{@session.id}:export:1"
    task = PhComposer::Diagnostics.with_context("session" => @session.id, "request" => request) { start }
    drain
    @runtime.failure("code" => "runtime.translation_failed", "stage" => "translation")

    logged = JSON.parse(PhComposer::Diagnostics.tail.last)
    assert_equal [@session.id, "#{@session.id}:export:1", task.fetch("task_id")],
                 logged.values_at("session", "request", "run_id")
  end

  # Half a prior pair is refused whatever the consent; a whole one needs consent to replace it.
  def test_destination_replacement_and_one_active_task_are_explicit
    File.write(@destination, "prior")
    assert_equal "export.refused", assert_raises(PhComposer::CodedError) { start(:replace => true) }.code
    File.write(PhComposer::Export::ArtifactPair.report_path(@destination), "prior report")
    error = assert_raises(PhComposer::CodedError) { start }
    assert_equal "export.replace_required", error.code
    assert_equal "prior", File.read(@destination)
    File.delete(@destination)
    File.delete(PhComposer::Export::ArtifactPair.report_path(@destination))
    start
    error = assert_raises(PhComposer::CodedError) { start }
    assert_equal "export.busy", error.code
  end

  def test_cancel_between_translation_and_commit_discards_the_result
    task = start
    drain
    @runtime.success
    assert_equal "checking", @tasks.status(task.fetch("task_id"), OWNER).fetch("stage")
    @tasks.cancel(task.fetch("task_id"), OWNER)
    drain

    assert_empty Dir.children(@directory)
    assert @runtime.stopped
  end

  def test_success_commits_one_pair_and_polling_does_not_write_or_change_the_model
    task = start
    drain
    @runtime.success
    drain
    result = @tasks.status(task.fetch("task_id"), OWNER)
    contents = Dir.children(@directory).sort.to_h { |name| [name, File.binread(File.join(@directory, name))] }

    assert_equal %w[completed export.complete none], result.fetch("outcome").values_at("status", "code", "effect")
    assert_equal ["test-export-report.html", "test.hbjson"], contents.keys
    assert_equal result, @tasks.status(task.fetch("task_id"), OWNER)
    assert_equal result, @tasks.latest(OWNER)
    refute result.dig("outcome", "value", "result", "canonical_model").key?("hbjson")
    assert_equal 0, result.dig("outcome", "value", "result", "canonical_model", "rooms")
    after = Dir.children(@directory).sort.to_h { |name| [name, File.binread(File.join(@directory, name))] }
    assert_equal contents, after
    assert_empty @session.model.operations
    refute @session.model.modified?
    assert @runtime.stopped
  end

  # A written run keeps the report it rendered and its result for its caller, read in fragments that join to
  # the written report's bytes; a run stopped after translation keeps its findings and says it rendered none.
  # Each task's cursors are its own.
  def test_a_written_or_stopped_run_keeps_what_it_generated_and_cursors_stay_with_their_task
    written = start.fetch("task_id")
    drain
    @runtime.success_with({ "type" => "Model", "rooms" => [] },
                          :findings => %w[zone wall].map do |id|
                            { "code" => "fixture.note", "section" => "fixture", "object_id" => id,
                              "message" => "A note.", "blocks_export" => false }
                          end)
    drain
    diagnostics = @tasks.status(written, OWNER, "compact" => true).fetch("diagnostics")
    assert_equal [2, 0, nil], diagnostics.values_at("findings", "blocking", "report_absent")
    report = read_fragments(written, "report")
    assert_equal File.read(File.join(@directory, "test-export-report.html")), report
    assert_equal diagnostics.dig("report", "sha256"),
                 Digest::SHA256.hexdigest(PhComposer::CanonicalJson.generate(report))
    assert_equal @tasks.status(written, OWNER).dig("outcome", "value", "result"), read_fragments(written, "result")

    stopped = start(:replace => true).fetch("task_id")
    drain
    @runtime.success
    @tasks.cancel(stopped, OWNER)
    drain
    kept = @tasks.status(stopped, OWNER, "compact" => true).fetch("diagnostics")
    assert_equal [0, nil, "not_rendered"], kept.values_at("findings", "report", "report_absent")
    refute_nil kept.fetch("result")

    page = @tasks.status(written, OWNER, "part" => "findings", "limit" => 1)
    assert_equal [["zone"], 2], [page.fetch("findings").map { |row| row.fetch("object_id") }, page.fetch("total")]
    error = assert_raises(PhComposer::CodedError) do
      @tasks.status(stopped, OWNER, "part" => "findings", "limit" => 1, "cursor" => page.fetch("next_cursor"))
    end
    assert_equal "params.invalid", error.code
  end

  # A write the filesystem refuses fails in fixed words: neither the status nor the latest task names
  # the destination folder or file.
  def test_a_failed_pair_write_names_no_path
    task = start
    drain
    @runtime.success
    File.chmod(0o555, @directory)
    drain
    [@tasks.status(task.fetch("task_id"), OWNER), @tasks.latest(OWNER)].each do |status|
      assert_equal %w[failed export.failed], status.fetch("outcome").values_at("status", "code")
      assert_equal PhComposer::Export::Task::PAIR_FAILED, status.dig("outcome", "message")
      ["test.hbjson", @directory].each { |secret| refute_includes JSON.generate(status), secret }
    end
  ensure
    File.chmod(0o755, @directory)
  end

  def test_content_and_destination_changes_after_translation_prevent_commit
    task = start
    drain
    @runtime.success
    File.write(@destination, "another writer")
    drain

    assert_equal "export.destination_changed", @tasks.status(task.fetch("task_id"), OWNER).dig("outcome", "code")
    assert_equal "another writer", File.read(@destination)
    refute File.exist?(PhComposer::Export::ArtifactPair.report_path(@destination))
  end

  def test_public_tasks_require_export_access_and_old_or_cross_model_handles_expire
    api = PhComposer::API
    read = api.connect(:session_id => @session.id, :capabilities => ["read", "model_write"])
    location = { "id" => approved_destination }
    refused = api.start_export(:context => read, :location => location)
    assert_equal "request.capability_denied", refused.fetch("code")
    context = api.connect(:session_id => @session.id, :capabilities => ["export"])
    assert_raises(ArgumentError) { api.start_export(:context => context, :destination => @destination) }
    started = api.start_export(:context => context, :location => location)
    id = started.dig("value", "task_id")
    assert_equal "completed", started.fetch("status")
    assert_equal started.fetch("value"), api.export_status(:context => context, :task_id => id).fetch("value")
    cancelled = api.cancel_export(:context => context, :task_id => id)
    assert_equal "cancelled", cancelled.dig("value", "outcome", "status")

    other = PhComposer::Sessions.for(Sketchup::Model.new)
    second = api.connect(:session_id => other.id, :capabilities => ["export"])
    assert_equal "task.expired", api.export_status(:context => second, :task_id => id).fetch("code")
    assert_equal "request.capability_denied", api.export_status(:context => read, :task_id => id).fetch("code")
    assert_empty Dir.children(@directory)
  end

  def test_a_task_answers_only_the_caller_that_started_it
    api = PhComposer::API
    location = { "id" => approved_destination }
    mine = api.connect(:session_id => @session.id, :capabilities => ["export"])
    theirs = api.connect(:session_id => @session.id, :capabilities => ["export"])
    id = api.start_export(:context => mine, :location => location).dig("value", "task_id")

    assert_equal %w[task.foreign task.foreign], [api.export_status(:context => theirs, :task_id => id),
                                                 api.cancel_export(:context => theirs,
                                                                   :task_id => id)].map { |o| o["code"] }
    assert_nil api.latest_export(:context => theirs).fetch("value")
    assert_equal id, api.latest_export(:context => mine).dig("value", "task_id")
    assert_equal "cancelled", api.cancel_export(:context => mine, :task_id => id).dig("value", "outcome", "status")
  end

  def test_a_revoke_before_commit_writes_nothing_and_after_commit_keeps_the_pair
    live = true
    owner = PhComposer::Export::Tasks::Owner.new("agent", -> { live })
    approval = PhComposer::NativeApproval::Granted.new(:path => @destination, :replace => false)
    task = @tasks.start(:owner => owner, :approval => approval, :runtime_factory => @factory)
    drain
    live = false
    @runtime.success
    drain
    refused = @tasks.status(task.fetch("task_id"), owner).fetch("outcome")

    assert_equal %w[refused export.revoked none], refused.values_at("status", "code", "effect")
    assert_empty Dir.children(@directory)
    live = true
    second = @tasks.start(:owner => owner, :approval => approval, :runtime_factory => @factory)
    drain
    @runtime.success
    drain
    live = false
    assert_equal "export.complete", @tasks.status(second.fetch("task_id"), owner).dig("outcome", "code")
    assert_equal ["test-export-report.html", "test.hbjson"], Dir.children(@directory).sort
  end

  def test_a_location_revoked_before_commit_refuses_and_writes_nothing
    location = approved_destination
    task = @tasks.start(:owner => OWNER, :location => { "id" => location }, :runtime_factory => @factory)
    drain
    PhComposer::ApprovedLocations.revoke(location)
    @runtime.success
    drain

    assert_equal %w[refused location.revoked], @tasks.status(task.fetch("task_id"), OWNER)
                                                     .fetch("outcome").values_at("status", "code")
    assert_empty Dir.children(@directory)
  end

  def test_a_revoked_caller_is_refused_from_its_next_call
    api = PhComposer::API
    context = api.connect(:session_id => @session.id, :capabilities => ["export"])
    @session.callers.revoke(context.caller)

    assert_equal "access.revoked", api.latest_export(:context => context).fetch("code")
  end

  def test_the_owner_alone_learns_where_the_written_pair_is_and_what_it_hashes_to
    other = PhComposer::Export::Tasks::Owner.new("someone-else", -> { true })
    task = start
    assert_nil @tasks.status(task.fetch("task_id"), OWNER).fetch("outcome")
    drain
    @runtime.success
    drain
    disclosed = @tasks.status(task.fetch("task_id"), OWNER).dig("outcome", "value", "artifacts")

    assert_equal @destination, disclosed.dig("hbjson", "path")
    %w[hbjson report].each do |file|
      bytes = File.binread(disclosed.dig(file, "path"))
      assert_equal [Digest::SHA256.hexdigest(bytes), bytes.bytesize], disclosed.fetch(file).values_at("sha256", "bytes")
    end
    assert_equal disclosed, @tasks.latest(OWNER).dig("outcome", "value", "artifacts")
    assert_equal "task.foreign", assert_raises(PhComposer::CodedError) {
      @tasks.status(task.fetch("task_id"), other)
    }.code
    assert_nil @tasks.latest(other)
    refute_includes JSON.generate(@tasks.owned_by(OWNER.handle).map(&:snapshot)), @directory
    refute_includes File.read(PhComposer::Diagnostics.path),
                    @directory if File.exist?(PhComposer::Diagnostics.path.to_s)
  end

  def test_a_refused_or_cancelled_task_discloses_nothing_and_a_replacement_changes_the_hashes
    first = start
    drain
    @runtime.success
    drain
    before = @tasks.status(first.fetch("task_id"), OWNER).dig("outcome", "value", "artifacts", "hbjson", "sha256")
    second = start(:replace => true)
    @tasks.cancel(second.fetch("task_id"), OWNER)

    refute @tasks.status(second.fetch("task_id"), OWNER).dig("outcome", "value").to_h.key?("artifacts")
    third = start(:replace => true)
    drain
    @runtime.success_with({ "type" => "Model", "rooms" => [{ "identifier" => "Zone_A" }] })
    drain
    after = @tasks.status(third.fetch("task_id"), OWNER).dig("outcome", "value", "artifacts", "hbjson", "sha256")
    refute_equal before, after
    assert_equal Digest::SHA256.hexdigest(File.binread(@destination)), after
  end

  # The export task methods describe themselves, and a client built only from those descriptions
  # preflights, starts, polls, cancels and reads the latest task with the panel closed.
  def test_a_client_built_from_the_task_descriptions_runs_the_export_methods
    api = PhComposer::API
    context = api.connect(:session_id => @session.id, :capabilities => %w[read export])
    names = api.discover.dig("tasks", "export").values_at("preflight", "start", "status", "cancel", "latest")
    call = lambda do |name, params|
      description = api.describe(:name => name)
      assert_empty PhComposer::JsonSchema.validate(params, description.fetch("params")), name
      outcome = api.public_send(name.to_sym, :context => context, **params.transform_keys(&:to_sym))
      if outcome.fetch("status") == "completed"
        assert_empty PhComposer::JsonSchema.validate(outcome.fetch("value"), description.fetch("result")), name
      end
      outcome
    end

    assert_equal %w[task task task task task], names.map { |name| api.describe(:name => name).fetch("kind") }
    assert_equal "completed", call.call(names[0], {}).fetch("status")
    location = { "id" => approved_destination }
    started = call.call(names[1], "location" => location)
    id = started.dig("value", "task_id")
    call.call(names[2], "task_id" => id)
    cancelled = call.call(names[3], "task_id" => id)
    latest = call.call(names[4], {})

    assert_equal "cancelled", cancelled.dig("value", "outcome", "status")
    assert_equal id, latest.dig("value", "task_id")
    refute_includes JSON.generate(latest.fetch("value")), "hbjson"
    File.write(@destination, "{}")
    File.write(PhComposer::Export::ArtifactPair.report_path(@destination), "<html></html>")
    assert_equal "export.replace_required", call.call(names[1], "location" => location).fetch("code")
    refute PhComposer::JsonSchema.validate({ "destination" => @destination }, api.describe(:name => names[1])
                                                                                 .fetch("params")).empty?
  end

  # Replacing the pair at an approved destination is consent to the state export_preflight reported;
  # a pair that changed since is refused, and the completed outcome names the location, never a path.
  def test_replacing_an_approved_pair_is_bound_to_the_reviewed_state
    api = PhComposer::API
    context = api.connect(:session_id => @session.id, :capabilities => %w[read export])
    id = approved_destination
    File.write(@destination, "{}")
    File.write(PhComposer::Export::ArtifactPair.report_path(@destination), "<html></html>")
    reviewed = api.export_preflight(:context => context, :location => id).dig("value", "destination")
    assert_equal true, reviewed.fetch("exists")
    stale = { "id" => id, "replace" => true, "expected_destination" => "0" * 64 }
    assert_equal "export.destination_changed", api.start_export(:context => context, :location => stale)["code"]
    no_state = api.start_export(:context => context, :location => { "id" => id, "replace" => true })
    assert_equal "params.invalid", no_state["code"]
    consented = { "id" => id, "replace" => true, "expected_destination" => reviewed.fetch("state") }
    # What start_export runs, with this test's runtime in place of the translation runtime.
    task = @tasks.start(:owner => OWNER, :location => consented, :runtime_factory => @factory)
    drain
    @runtime.success
    drain
    value = @tasks.status(task.fetch("task_id"), OWNER).dig("outcome", "value")
    assert_equal({ "id" => id, "label" => "Export destination 1" }, value.fetch("location"))
    refute_includes JSON.generate(value.reject { |key, _value| key == "artifacts" }), @directory
    refute_equal "{}", File.read(@destination)
    refute_nil PhComposer::ApprovedLocations.list.first.fetch("last_used_at")
  end

  # expected_revision binds the run to the revision the caller read: the read, the source and the pair.
  def test_a_start_at_the_expected_revision_reads_and_writes_that_revision
    revision = @session.revision
    task = start(:expected_revision => revision)
    drain
    @runtime.success
    drain

    status = @tasks.status(task.fetch("task_id"), OWNER)
    assert_equal ["export.complete", revision], [status.dig("outcome", "code"), status.dig("source", "revision")]
    assert File.exist?(@destination)
  end

  # A stale start answers invoke's refusal shape and starts nothing: no task, no runtime, no file.
  def test_a_start_at_another_revision_refuses_stale_and_starts_nothing
    api = PhComposer::API
    context = api.connect(:session_id => @session.id, :capabilities => ["export"])
    read = @session.revision
    external_edit

    refused = api.start_export(:context => context, :location => { "id" => approved_destination },
                               :expected_revision => read)
    assert_equal %w[refused revision.stale none], refused.values_at("status", "code", "effect")
    assert_equal @session.revision, refused.fetch("revision")
    assert_nil api.latest_export(:context => context).fetch("value")
    assert_nil @runtime
    assert_empty Dir.children(@directory)
    invalid = api.start_export(:context => context, :location => { "id" => approved_destination },
                               :expected_revision => "1")
    assert_equal "params.invalid", invalid.fetch("code")
  end

  # Without expected_revision a start is unbound, as before: an edit after the read is the generation's concern.
  def test_a_start_without_expected_revision_is_not_bound_to_one
    revision = @session.revision
    task = start
    @session.host_event(:active_path_changed)
    drain
    assert_equal revision + 1, @session.revision
    status = @tasks.status(task.fetch("task_id"), OWNER)
    assert_equal ["translating", revision], [status.fetch("stage"), status.dig("source", "revision")]
  end

  # The check runs where the run reads, not where the request arrived: deferred work that commits when the
  # start settles the session, and an edit before the first reading slice, both leave the run stale.
  def test_an_edit_between_arrival_and_the_read_is_stale
    read = @session.revision
    @session.feature_state("test.export.deferred") { DeferredCommit.new(@session) }
    error = assert_raises(PhComposer::CodedError) { start(:expected_revision => read) }
    assert_equal "revision.stale", error.code
    assert_nil @tasks.latest(OWNER)

    task = start(:expected_revision => @session.revision)
    external_edit
    drain
    outcome = @tasks.status(task.fetch("task_id"), OWNER).fetch("outcome")
    assert_equal %w[failed revision.stale none], outcome.values_at("status", "code", "effect")

    # The watchdog can see the edit before the next reading slice does; it answers the same.
    task = start(:expected_revision => @session.revision)
    external_edit
    watch_after(0)
    assert_equal "revision.stale", @tasks.status(task.fetch("task_id"), OWNER).dig("outcome", "code")
    assert_nil @runtime
    assert_empty Dir.children(@directory)
  end

  def test_task_retention_is_bounded_and_old_handles_never_restart_a_write
    ids = 21.times.map do
      task = start
      @tasks.cancel(task.fetch("task_id"), OWNER)
      task.fetch("task_id")
    end
    error = assert_raises(PhComposer::CodedError) { @tasks.status(ids.first, OWNER) }
    assert_equal "task.expired", error.code
    assert_equal ids.last, @tasks.latest(OWNER).fetch("task_id")
    assert_empty Dir.children(@directory)
  end

  def test_terminal_task_expires_after_the_documented_retention_without_repeating_work
    task = start
    id = task.fetch("task_id")
    @tasks.cancel(id, OWNER)
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.stub(:clock_gettime, ->(*) { now + PhComposer::Export::Tasks::RETENTION_SECONDS + 1 }) do
      assert_nil @tasks.latest(OWNER)
      error = assert_raises(PhComposer::CodedError) { @tasks.status(id, OWNER) }
      assert_equal "task.expired", error.code
    end
    assert_empty Dir.children(@directory)
    assert_nil @runtime
  end

  private

  # Runs the repeating task watchdog, leaving it scheduled, as if `seconds` had passed since the first call.
  def watch_after(seconds)
    @clock_origin ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)
    id = UI.timer_intervals.find { |_id, interval| interval == 0.2 }&.first
    watchdog = UI.instance_variable_get(:@timers).find { |timer| timer.id == id }
    return unless watchdog

    Process.stub(:clock_gettime, ->(*) { @clock_origin + seconds }) { watchdog.block.call }
  end

  def drain
    100.times do
      timer = UI.instance_variable_get(:@timers).find { |item| UI.timer_intervals[item.id].zero? }
      return unless timer

      UI.run_timer(timer.id)
    end
    flunk "Collection did not settle within 100 timer slices"
  end

  def start(replace: false, expected_revision: nil)
    approval = PhComposer::NativeApproval::Granted.new(:path => @destination, :replace => replace)
    @tasks.start(:owner => OWNER, :approval => approval, :runtime_factory => @factory,
                 :expected_revision => expected_revision)
  end

  def external_edit
    @session.model.start_operation("External edit")
    @session.model.set_attribute("test", "value", @session.revision)
    @session.model.commit_operation
  end

  # A part a task kept, its fragments joined and parsed.
  def read_fragments(id, part)
    text = +""
    cursor = nil
    loop do
      answer = @tasks.status(id, OWNER, { "part" => part, "cursor" => cursor }.compact)
      text << answer.dig("fragment", "text")
      cursor = answer.fetch("next_cursor")
      break unless cursor
    end
    JSON.parse(text)
  end

  def approved_destination
    PhComposer::ApprovedLocations.approve(:kind => "save_file", :path => @destination).fetch("id")
  end
end
