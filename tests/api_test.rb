# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/test_feature"

# The public interface with no panel: discovery, reads, validated writes, retries and lifecycle
# (context/CONTRACTS.md, "Public interface" to "Retries").
class ApiTest < PhComposerTestCase
  API = PhComposer::API
  PART = "test.fixture.part"

  def setup
    super
    PhComposer::Registry.install([TestFeature])
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
  end

  def teardown
    RecordFixtures::FailingStore.writes_before_failure = nil
    TestFeature.reentry = nil
    super
  end

  # ------------------------------------------------------------------ discovery and reads

  def test_discovery_lists_the_session_and_every_registration_by_name
    found = API.discover

    assert_equal({ "major" => 1, "minor" => 10 }, found.fetch("api"))
    assert_equal [@session.id], found.fetch("sessions").map { |session| session.fetch("id") }
    assert_includes found.fetch("actions").map { |action| action.fetch("name") }, "test.fixture.update_parts"
    assert_includes found.fetch("queries").map { |query| query.fetch("name") }, "ph_composer.records.list"
    assert_equal ["test.fixture.review"], found.fetch("extensions").map { |extension| extension.fetch("namespace") }
    assert_equal "mm", API.describe(:name => PART).dig("values", "properties", "length_mm", "x-unit")
    assert_equal "action", API.describe(:name => "test.fixture.update_parts").fetch("kind")
  end

  def test_a_script_creates_edits_and_reads_back_with_the_panel_closed
    created = create_parts(2)
    first = created.dig("value", "part_ids", 0)

    updated = invoke("test.fixture.update_parts", edit(first, 950.0), 2, created.fetch("revision"))
    read = records(:ids => [first])

    assert_equal %w[completed committed], [updated.fetch("status"), updated.fetch("effect")]
    assert_equal "Done: Edit Test Parts.", updated.fetch("message"), "a confirmation names what completed"
    assert_equal [{ "kind" => PART, "id" => first, "change" => "updated" }], updated.fetch("affected")
    assert_equal updated.fetch("revision"), read.fetch("revision")
    assert_equal 950.0, read.dig("value", "records", 0, "values", "length_mm")
    assert_equal({ "length_mm" => "mm" }, read.dig("value", "units"))
  end

  def test_reads_do_not_write_allocate_identities_or_mark_the_model_modified
    create_parts(1)
    @model.instance_variable_set(:@modified, false)
    operations = @model.operations.length
    revision = @session.revision

    records
    API.query(:context => @context, :name => "test.fixture.total_length")
    API.preview(:context => @context, :name => "test.fixture.create", :params => { "parts" => [part_values] })

    refute @model.modified?
    assert_equal [operations, revision], [@model.operations.length, @session.revision]
  end

  def test_pages_are_bounded_and_bound_to_their_revision
    create_parts(101)

    first = records.fetch("value")
    second = records(:cursor => first.fetch("next_cursor")).fetch("value")
    assert_equal [100, 1, 101], [first.fetch("records").length, second.fetch("records").length, first.fetch("total")]
    assert_nil second.fetch("next_cursor")
    assert_equal 101, records(:limit => 500).dig("value", "records").length

    [0, 501, 2.5].each { |limit| assert_equal "query.limit_invalid", records(:limit => limit).fetch("code") }
    create_parts(1, 2)
    assert_equal "query.cursor_expired", records(:cursor => first.fetch("next_cursor")).fetch("code")
  end

  def test_a_projection_returns_only_the_named_values_and_reports_unreadable_records
    create_parts(1)
    PART_KIND.store.write(@model, "id" => "tpt_BROKENBROKEN", "schema_version" => 1)

    page = records(:fields => ["length_mm"]).fetch("value")

    assert_equal [{ "length_mm" => 1200.0 }], page.fetch("records").map { |record| record.fetch("values") }
    unreadable = page.fetch("unreadable").map { |row| row.values_at("id", "code") }
    assert_equal [%w[tpt_BROKENBROKEN record.unreadable]], unreadable
  end

  # A script that adapts a discovered schema must not change what the next write accepts.
  def test_discovery_and_descriptions_are_detached_from_what_validation_uses
    part = create_parts(1).dig("value", "part_ids", 0)
    described = API.describe(:name => PART)
    described.dig("values", "properties", "length_mm")["exclusiveMinimum"] = -1000
    described.dig("values", "required") << "extra"
    API.describe(:name => "test.fixture.update_parts").fetch("params")["properties"].clear
    API.discover.fetch("features").first.fetch("requires") << "mutated"

    refused = invoke("test.fixture.update_parts", edit(part, -5.0), 2)

    assert_equal %w[refused validation.failed], refused.values_at("status", "code")
    assert_equal 0, API.describe(:name => PART).dig("values", "properties", "length_mm", "exclusiveMinimum")
    refute_includes API.describe(:name => PART).dig("values", "required"), "extra"
    refute_empty API.describe(:name => "test.fixture.update_parts").dig("params", "properties")
    refute_includes API.discover.fetch("features").first.fetch("requires"), "mutated"
  end

  # A cursor answers only the query and filter it came from; a limit change is still the same filter.
  def test_a_cursor_is_refused_for_another_filter_or_query
    create_parts(3)
    first = records(:limit => 1).fetch("value")

    assert_equal 2, records(:limit => 2, :cursor => first.fetch("next_cursor")).dig("value", "records").length
    assert_equal "params.invalid", records(:limit => 1, :fields => ["label"],
                                           :cursor => first.fetch("next_cursor")).fetch("code")
  end

  # A cursor whose binding matches but whose position is the wrong kind of key is still one this
  # query did not issue: it refuses rather than failing inside the comparison.
  def test_a_cursor_with_a_foreign_position_refuses
    create_parts(3)
    first = records(:limit => 1).fetch("value")
    decoded = JSON.parse(first.fetch("next_cursor").unpack1("m0")).merge("after" => [1, 2])
    forged = [JSON.generate(decoded)].pack("m0")

    assert_equal %w[refused params.invalid], records(:limit => 1, :cursor => forged).values_at("status", "code")
  end

  # A cursor from another Model's session is refused, even at the same revision number.
  def test_a_cursor_from_another_session_refuses
    create_parts(2)
    first = records(:limit => 1).fetch("value")
    other = PhComposer::Sessions.for(Sketchup::Model.new)
    context = API.connect(:session_id => other.id)
    params = { "kind" => PART, "limit" => 1, "cursor" => first.fetch("next_cursor") }

    assert_equal "params.invalid", API.query(:context => context, :name => "ph_composer.records.list",
                                             :params => params).fetch("code")
  end

  def test_a_malformed_cursor_is_refused_as_an_outcome
    create_parts(2)
    forged = [JSON.generate("revision" => @session.revision, "after" => 7)].pack("m0")

    [forged, [JSON.generate("revision" => @session.revision)].pack("m0"), "not base64 json"].each do |cursor|
      refused = records(:cursor => cursor)
      assert_equal %w[refused params.invalid], refused.values_at("status", "code"), cursor
    end
  end

  # Scripts get the same failure envelope the panel's snapshot relies on, with nothing written.
  def test_an_unexpected_query_or_preview_failure_is_a_failed_outcome
    install_mismatched_results
    operations = @model.operations.length

    failed_query = API.query(:context => @context, :name => "test.mismatch.read")
    failed_preview = API.preview(:context => @context, :name => "test.mismatch.create",
                                 :params => { "parts" => [part_values] })

    [failed_query, failed_preview].each do |outcome|
      assert_equal %w[failed operation.failed none], outcome.values_at("status", "code", "effect")
    end
    assert_equal operations, @model.operations.length
  end

  # ------------------------------------------------------------------ refusals and staleness

  def test_a_second_caller_with_an_old_revision_is_refused_without_writing
    first = create_parts(1)
    part = first.dig("value", "part_ids", 0)
    other = API.connect(:session_id => @session.id)
    read_revision = first.fetch("revision")
    invoke("test.fixture.update_parts", edit(part, 900.0), 2, read_revision)
    operations = @model.operations.length

    stale = API.invoke(:context => other, :name => "test.fixture.update_parts", :params => edit(part, 800.0),
                       :request => { "sequence" => 1, "expected_revision" => read_revision })

    assert_equal %w[refused revision.stale none], stale.values_at("status", "code", "effect")
    assert stale.fetch("message").end_with?("Nothing was written.")
    assert_equal operations, @model.operations.length
    assert_equal 900.0, stored(part).fetch("length_mm")
  end

  def test_a_failure_on_the_last_target_leaves_every_target_unchanged
    parts = create_parts(3).dig("value", "part_ids")
    edits = parts.map { |id| { "id" => id, "values" => { "length_mm" => 500.0 } } }
    edits.last["values"]["length_mm"] = -1

    refused = invoke("test.fixture.update_parts", { "edits" => edits }, 2, @session.revision)

    assert_equal %w[refused validation.failed none], refused.values_at("status", "code", "effect")
    assert_equal [1200.0] * 3, parts.map { |id| stored(id).fetch("length_mm") }
  end

  def test_a_write_failure_after_the_first_write_rolls_back_and_reports_it
    parts = create_parts(3).dig("value", "part_ids")
    revision = @session.revision
    undo_steps = @model.instance_variable_get(:@undo_stack).length
    RecordFixtures::FailingStore.writes_before_failure = 1

    failed = invoke("test.fixture.update_parts", { "edits" => parts.map { |id| edit(id, 400.0)["edits"].first } },
                    2, revision)

    assert_equal %w[failed operation.failed rolled_back], failed.values_at("status", "code", "effect")
    assert_equal PhComposer::Outcome::ROLLED_BACK, failed.fetch("message")
    assert_equal ["incident"], failed.fetch("detail").keys,
                 "unexpected exceptions disclose only the log's incident reference, never their messages"
    logged = JSON.parse(PhComposer::Diagnostics.tail.last)
    assert_equal [failed.dig("detail", "incident"), "operation_failed", "rolled_back"],
                 logged.values_at("incident", "event", "effect")
    assert_equal [1200.0] * 3, parts.map { |id| stored(id).fetch("length_mm") }
    assert_equal [revision, undo_steps], [@session.revision, @model.instance_variable_get(:@undo_stack).length]
    assert_nil @session.busy_reason, "no mutation or suppression is left behind"
  end

  # A host abort that leaves the first write in place: the dispatcher must not claim a rollback.
  def test_an_abort_that_cannot_be_verified_is_reported_as_unknown
    parts = create_parts(2).dig("value", "part_ids")
    RecordFixtures::FailingStore.writes_before_failure = 1
    @model.define_singleton_method(:abort_operation) { true }

    edits = parts.map { |id| edit(id, 400.0)["edits"].first }
    failed = invoke("test.fixture.update_parts", { "edits" => edits }, 2, @session.revision)

    assert_equal %w[failed operation.rollback_unverified unknown], failed.values_at("status", "code", "effect")
  end

  def test_a_no_change_edit_completes_with_no_operation
    part = create_parts(1).dig("value", "part_ids", 0)
    operations = @model.operations.length

    result = invoke("test.fixture.update_parts", edit(part, 1200.0), 2, @session.revision)

    assert_equal %w[completed ok none], result.values_at("status", "code", "effect")
    assert_equal operations, @model.operations.length
  end

  def test_envelope_problems_are_refused_before_anything_runs
    reader = API.connect(:session_id => @session.id, :capabilities => ["read"])
    wrong_major = PhComposer::OperationContext.new(:api_major => 2, :session_id => @session.id,
                                                   :caller => @context.caller)

    assert_equal "request.capability_denied", API.invoke(:context => reader, :name => "test.fixture.create",
                                                         :params => {}, :request => request(1)).fetch("code")
    assert_equal "request.api_version",
                 API.query(:context => wrong_major, :name => "test.fixture.total_length").fetch("code")
    assert_equal "request.unknown_operation",
                 API.query(:context => @context, :name => "test.fixture.absent").fetch("code")
    assert_equal "request.malformed", API.invoke(:context => @context, :name => "test.fixture.create",
                                                 :params => { "parts" => [] },
                                                 :request => request(1).merge("preview" => true)).fetch("code")
    assert_equal "params.invalid", invoke("test.fixture.create", { "parts" => "none" }, 1).fetch("code")
  end

  # Params that are not plain JSON are refused before acceptance. The sequence is not consumed, so no
  # outcome is retained and the same sequence carries the corrected request.
  def test_non_json_params_are_refused_without_consuming_the_sequence
    cyclic = { "parts" => [] }
    cyclic["self"] = cyclic
    [{ "parts" => [], "extra" => Float::NAN }, { "parts" => [], :extra => 1 },
     { "parts" => [], "extra" => Object.new }, { "parts" => [], "extra" => "\xFF".dup.force_encoding("UTF-8") },
     cyclic].each do |params|
      context = API.connect(:session_id => @session.id)
      caller = @session.callers.fetch(context.caller)
      operations = @model.operations.length
      revision = @session.revision

      refused = API.invoke(:context => context, :name => "test.fixture.create", :params => params,
                           :request => request(1))

      assert_equal %w[refused request.malformed none], refused.values_at("status", "code", "effect")
      assert_equal [0, revision, operations], [caller.highest_sequence, @session.revision, @model.operations.length]
      assert_equal "request.outcome_unavailable",
                   API.outcome(:context => context, :request => { "sequence" => 1 }).fetch("code")
      accepted = API.invoke(:context => context, :name => "test.fixture.create",
                            :params => { "parts" => [part_values] }, :request => request(1))
      assert_equal %w[completed committed], accepted.values_at("status", "effect")
    end
  end

  def test_a_lost_response_retry_writes_once
    first = create_parts(1, 1, 1)
    operations = @model.operations.length
    undo_steps = @model.instance_variable_get(:@undo_stack).length

    again = create_parts(1, 1, 1)

    assert_equal first, again
    assert_equal [operations, undo_steps], [@model.operations.length, @model.instance_variable_get(:@undo_stack).length]
  end

  # ------------------------------------------------------------------ connection authority

  def test_changing_the_capabilities_passed_to_connect_changes_no_grant
    granted = [String.new("read")]
    reader = API.connect(:session_id => @session.id, :capabilities => granted)
    granted.first.replace("model_write")
    granted << "model_write"

    result = API.invoke(:context => reader, :name => "test.fixture.create",
                        :params => { "parts" => [part_values] }, :request => request(1))

    assert_equal "request.capability_denied", result.fetch("code")
    assert_equal %w[read], @session.callers.fetch(reader.caller).capabilities
  end

  def test_the_connection_values_cannot_be_edited_in_place
    assert_raises(FrozenError) { @context.session_id.replace("edited") }
    assert_raises(FrozenError) { @context.caller.replace("edited") }
    assert_raises(FrozenError) { @session.callers.fetch(@context.caller).capabilities.first.replace("export") }

    assert_same @session, PhComposer::Sessions.find(@context.session_id)
    assert_equal "completed", create_parts(1).fetch("status")
  end

  # ------------------------------------------------------------------ retries

  def test_a_retry_with_the_same_payload_returns_the_first_outcome_without_running_again
    first = create_parts(1, 1, 1)
    operations = @model.operations.length

    again = create_parts(1, 1, 1)

    assert_equal first, again
    assert_equal operations, @model.operations.length
    assert_equal 1, records.dig("value", "total")
  end

  def test_a_reused_sequence_with_a_different_payload_is_refused
    create_parts(1, 1, 1)

    assert_equal "request.sequence_conflict", create_parts(2, 1, 1).fetch("code")
  end

  def test_an_expired_or_lower_sequence_is_never_treated_as_new_work
    now = 0.0
    @session.outcomes.clock = -> { now }
    create_parts(1)
    now = PhComposer::OutcomeStore::LIFETIME_SECONDS + 1

    expired = create_parts(1)

    assert_equal "request.outcome_unavailable", expired.fetch("code")
    assert_equal "request.outcome_unavailable",
                 API.outcome(:context => @context, :request => { "sequence" => 1 }).fetch("code")
    assert_equal 1, records.dig("value", "total")
  end

  def test_a_retry_while_the_first_attempt_runs_is_pending
    TestFeature.reentry = { :context => @context, :name => "test.fixture.reenter", :params => {},
                            :request => request(1) }

    result = invoke("test.fixture.reenter", {}, 1)

    assert_equal %w[pending request.pending], result.dig("value", "inner").values_at("status", "code")
  end

  def test_a_different_request_while_the_first_attempt_runs_conflicts
    variants = [["test.fixture.create", {}, {}], ["test.fixture.reenter", { "different" => true }, {}],
                ["test.fixture.reenter", {}, { "expected_revision" => @session.revision + 1 }],
                ["test.fixture.reenter", {}, { "proposal_digest" => "other" }]]

    codes = variants.each_with_index.map do |(name, params, changed), index|
      TestFeature.reentry = { :context => @context, :name => name, :params => params,
                              :request => request(index + 1).merge(changed) }
      invoke("test.fixture.reenter", {}, index + 1).dig("value", "inner", "code")
    end

    assert_equal ["request.sequence_conflict"] * variants.length, codes
  end

  # A handler that starts another change, even through another caller, finds the session busy.
  def test_a_second_change_cannot_start_while_one_is_running
    part = create_parts(1).dig("value", "part_ids", 0)
    other = API.connect(:session_id => @session.id)
    TestFeature.reentry = { :context => other, :name => "test.fixture.update_parts", :params => edit(part, 10.0),
                            :request => request(1) }

    result = invoke("test.fixture.reenter", {}, 2)

    assert_equal %w[busy session.busy], result.dig("value", "inner").values_at("status", "code")
    assert_equal 1200.0, stored(part).fetch("length_mm")
  end

  def test_a_handler_that_rescues_a_refusal_commits_nothing
    parts = create_parts(2).dig("value", "part_ids")
    { parts.first => "draft", parts.last => "lost" }.each do |id, status|
      review = { "schema_version" => 1, "payload" => { "status" => status } }
      PART_KIND.store.write(@model, stored(id).merge("extension_data" => { "test.fixture.review" => review }))
    end
    operations = @model.operations.length

    result = invoke("test.fixture.swallow_refusal", { "ids" => parts }, 2)

    assert_equal %w[refused extension.migration_failed none], result.values_at("status", "code", "effect")
    assert_equal operations, @model.operations.length
    assert_equal 1, stored(parts.first).dig("extension_data", "test.fixture.review", "schema_version")
  end

  # A retry returns the original outcome, whatever a caller did to its copy.
  def test_a_retained_outcome_is_isolated_from_every_returned_copy
    created = create_parts(2, 1, 1)
    part_ids = created.dig("value", "part_ids").dup
    created.dig("value", "part_ids").clear
    created["status"] = "refused"

    retried = create_parts(2, 1, 1)
    retried.dig("value", "part_ids").clear
    retried["effect"] = "none"
    looked_up = API.outcome(:context => @context, :request => { "sequence" => 1 })

    assert_equal part_ids, looked_up.dig("value", "part_ids")
    assert_equal %w[completed committed], looked_up.values_at("status", "effect")
    assert_equal part_ids, create_parts(2, 1, 1).dig("value", "part_ids")
  end

  def test_a_retained_outcome_is_retrievable_by_sequence
    created = create_parts(1)

    assert_equal created, API.outcome(:context => @context, :request => { "sequence" => 1 })
  end

  def test_a_busy_session_refuses_without_consuming_the_sequence
    work = Struct.new(:pending?).new(true)
    @session.feature_state(:api_test) { work }

    busy = create_parts(1)
    work.define_singleton_method(:pending?) { false }

    assert_equal %w[busy session.busy], busy.values_at("status", "code")
    assert_equal "completed", create_parts(1).fetch("status")
  end

  # ------------------------------------------------------------------ view commands

  # A view command changes what the host shows and nothing else, so it carries no sequence, opens no
  # operation and leaves the revision where it was: there is nothing for an Undo to take back.
  def test_a_view_command_moves_the_view_without_a_sequence_or_a_revision
    before = @session.revision

    outcome = API.view(:context => @context, :name => "test.fixture.look", :params => { "count" => 2 })

    assert_equal "completed", outcome.fetch("status")
    assert_equal 2, outcome.dig("value", "selected")
    assert_equal before, @session.revision
    assert_equal before, outcome.fetch("revision")
    refute @model.modified?
  end

  def test_a_view_command_says_why_it_refused
    outcome = API.view(:context => @context, :name => "test.fixture.look", :params => { "count" => 0 })

    assert_equal %w[refused validation.failed], outcome.values_at("status", "code")
    assert_equal "There is nothing to look at.", outcome.fetch("message")
  end

  # `effect` is a statement about the Model, which nothing here touched. The viewport may be half
  # moved, which is why a client re-reads what it shows rather than assuming.
  def test_a_view_command_that_fails_after_moving_the_view_still_reports_the_model_unchanged
    outcome = API.view(:context => @context, :name => "test.fixture.look", :params => { "count" => -1 })

    assert_equal %w[failed operation.failed none], outcome.values_at("status", "code", "effect")
    refute @model.modified?
  end

  def test_a_query_name_is_not_a_view_command
    outcome = API.view(:context => @context, :name => "test.fixture.total_length", :params => {})

    assert_equal %w[refused request.unknown_operation], outcome.values_at("status", "code")
  end

  def test_a_caller_without_view_access_cannot_move_the_view
    reader = API.connect(:session_id => @session.id, :capabilities => ["read"])

    outcome = API.view(:context => reader, :name => "test.fixture.look", :params => { "count" => 1 })

    assert_equal %w[refused request.capability_denied], outcome.values_at("status", "code")
  end

  def test_a_view_command_refuses_while_the_session_is_busy
    work = Struct.new(:pending?).new(true)
    @session.feature_state(:api_test) { work }

    outcome = API.view(:context => @context, :name => "test.fixture.look", :params => { "count" => 1 })

    assert_equal %w[busy session.busy], outcome.values_at("status", "code")
  end

  def test_an_action_name_is_not_a_view_command
    outcome = API.view(:context => @context, :name => "test.fixture.create", :params => {})

    assert_equal %w[refused request.unknown_operation], outcome.values_at("status", "code")
  end

  # The offline suite fails a test whose operation refuses with a code it did not declare, naming both,
  # whichever way the operation is called.
  def test_a_refusal_outside_the_declared_codes_is_reported_by_operation_and_code
    PhComposer::Registry.install([undeclared_refusals_probe])
    context = API.connect(:session_id => @session.id, :capabilities => %w[read view model_write setup export])
    request = { "sequence" => 1, "expected_revision" => @session.revision }

    outcomes = [API.query(:context => context, :name => "probe.audit.read"),
                API.view(:context => context, :name => "probe.audit.look"),
                API.setup(:context => context, :name => "probe.audit.configure"),
                API.export_file(:context => context, :name => "probe.audit.write"),
                API.preview(:context => context, :name => "probe.audit.change"),
                API.invoke(:context => context, :name => "probe.audit.change", :params => {}, :request => request)]

    assert_equal ["target.not_found"], outcomes.map { |outcome| outcome.fetch("code") }.uniq
    expected = %w[read look configure write change change].map do |verb|
      "probe.audit.#{verb} refused with target.not_found"
    end
    assert_equal expected, @undeclared_refusals.slice!(0..)
  end

  def test_a_user_error_refuses_preview_and_invoke_with_the_same_validation_message
    feature = Module.new do
      def self.install(registry)
        scope = registry.feature("probe.validation", :contract_version => 1)
        scope.action("probe.validation.change", :description => "Validate a change.",
                                                :params => { "type" => "object" }, :result => { "type" => "object" },
                                                :refuses => ["validation.failed"], :undo_name => "Change",
                                                :side_effects => "None.") do
          raise PhComposer::UserError, "Choose a valid value."
        end
      end
    end
    PhComposer::Registry.install([feature])

    preview = API.preview(:context => @context, :name => "probe.validation.change")
    invoked = invoke("probe.validation.change", {}, 1)

    [preview, invoked].each do |outcome|
      assert_equal %w[refused validation.failed none], outcome.values_at("status", "code", "effect")
      assert_equal @session.revision, outcome.fetch("revision")
      assert_includes outcome.fetch("message"), "Choose a valid value."
    end
    assert_empty @model.operations
    assert_empty @undeclared_refusals
  end

  # ------------------------------------------------------------------ Models and lifecycle

  def test_two_models_with_identical_record_ids_stay_isolated
    other_model = Sketchup::Model.new
    other_session = PhComposer::Sessions.for(other_model)
    part = create_parts(1).dig("value", "part_ids", 0)
    other_model.attribute_dictionary(PART_KIND.store.dictionary, true)[part] =
      @model.attribute_dictionary(PART_KIND.store.dictionary)[part]
    other_context = API.connect(:session_id => other_session.id)

    invoke("test.fixture.update_parts", edit(part, 300.0), 2, @session.revision)

    other_page = API.query(:context => other_context, :name => "ph_composer.records.list",
                           :params => { "kind" => PART })
    assert_equal 1200.0, other_page.dig("value", "records", 0, "values", "length_mm")
    assert_equal 300.0, stored(part).fetch("length_mm")
  end

  def test_a_closed_or_reopened_model_refuses_its_old_context
    create_parts(1)
    @model.save("/tmp/ph-composer-api.skp")

    Sketchup.open_file("/tmp/ph-composer-api.skp")
    reopened = PhComposer::Sessions.for(Sketchup.active_model)
    @model.close

    assert_equal "session.unknown", records.fetch("code")
    refute_equal @session.id, reopened.id
    fresh = API.connect(:session_id => reopened.id)
    assert_equal 1, API.query(:context => fresh, :name => "ph_composer.records.list",
                              :params => { "kind" => PART }).dig("value", "total")
  end

  def test_undo_and_redo_restore_values_and_advance_the_revision
    part = create_parts(1).dig("value", "part_ids", 0)
    invoke("test.fixture.update_parts", edit(part, 700.0), 2, @session.revision)
    revision = @session.revision

    @model.undo
    assert_equal [1200.0, revision + 1], [stored(part).fetch("length_mm"), @session.revision]
    @model.redo
    assert_equal [700.0, revision + 2], [stored(part).fetch("length_mm"), @session.revision]
  end

  def test_duplicate_preview_and_snapshot_use_the_same_operations
    parts = create_parts(2).dig("value", "part_ids")

    preview = API.preview(:context => @context, :name => "test.fixture.duplicate_parts", :params => { "ids" => parts })
    assert_equal [%w[created] * 2, 2], [preview.fetch("affected").map { |row|
                                          row.fetch("change")
                                        }, records.dig("value", "total")]

    duplicated = invoke("test.fixture.duplicate_parts", { "ids" => parts }, 2, @session.revision)
    assert_equal 4, records.dig("value", "total")
    assert_equal parts.sort, duplicated.dig("value", "mapping").keys.sort

    snapshot = PhComposer::Snapshot.build(@context)
    assert_equal 4, snapshot.dig("sections", "test.fixture.parts", "value", "total")
  end

  def test_a_preview_digest_revalidates_a_create_without_retaining_its_random_ids
    params = { "parts" => [part_values] }
    preview = API.preview(:context => @context, :name => "test.fixture.create", :params => params)

    created = API.invoke(
      :context => @context, :name => "test.fixture.create", :params => params,
      :request => request(1).merge("proposal_digest" => preview.fetch("proposal_digest"))
    )

    assert_equal %w[completed committed], created.values_at("status", "effect")
  end

  def test_a_mismatched_preview_digest_refuses_before_opening_an_operation
    params = { "parts" => [part_values] }
    operations = @model.operations.length

    result = API.invoke(
      :context => @context, :name => "test.fixture.create", :params => params,
      :request => request(1).merge("proposal_digest" => "not-the-preview")
    )

    assert_equal %w[refused proposal.changed none], result.values_at("status", "code", "effect")
    assert_equal operations, @model.operations.length
  end

  def test_a_handler_result_outside_its_schema_fails_before_anything_is_written
    install_mismatched_results

    failed = invoke("test.mismatch.create", { "parts" => [part_values] }, 1)

    assert_equal %w[failed operation.failed none], failed.values_at("status", "code", "effect")
    assert_equal 0, records(:kind => "test.fixture.definition").dig("value", "total")
  end

  private

  PART_KIND = RecordFixtures::PART

  # One operation of each kind, each refusing with a code it does not declare.
  def undeclared_refusals_probe
    Module.new do
      def self.install(registry)
        scope = registry.feature("probe.audit", :contract_version => 1)
        refuse = ->(*) { raise PhComposer::CodedError.new("target.not_found", "Gone.") }
        closed = { "type" => "object", "properties" => {}, "additionalProperties" => false }
        common = { :description => "Refuses with a code it does not declare.", :params => closed,
                   :result => closed, :refuses => [] }
        scope.query("probe.audit.read", **common, &refuse)
        scope.view_command("probe.audit.look", **common, &refuse)
        scope.setup_command("probe.audit.configure", **common, &refuse)
        scope.file_export("probe.audit.write", **common, &refuse)
        scope.action("probe.audit.change", **common, :undo_name => "Change", :side_effects => "None.", &refuse)
      end
    end
  end

  # A read and a write whose handlers return an object while each declares an array. Published
  # declarations are frozen, so the mismatch is registered rather than patched in.
  def install_mismatched_results
    array = { "type" => "array" }
    parts = { "type" => "object", "required" => ["parts"], "properties" => { "parts" => { "type" => "array" } } }
    feature = Module.new do
      define_singleton_method(:install) do |registry|
        scope = registry.feature("test.mismatch", :contract_version => 1)
        scope.query("test.mismatch.read", :description => "Read.", :params => { "type" => "object" },
                                          :result => array, :refuses => []) { {} }
        scope.action("test.mismatch.create", :description => "Create parts.", :params => parts, :result => array,
                                             :refuses => [], :undo_name => "Create",
                                             :side_effects => "Creates records.",
                                             :examples => [{ "parts" => [] }]) do |request, changes|
          request.engine.propose_create("test.fixture.definition", changes, :values => { "label" => "Frame" })
          {}
        end
      end
    end
    PhComposer::Registry.install([feature])
  end

  def part_values(length = 1200.0)
    { "label" => "Sill", "length_mm" => length }
  end

  # A retry repeats the whole request, so a test that retries passes the revision it first read.
  def create_parts(count, sequence = 1, revision = @session.revision)
    invoke("test.fixture.create", { "parts" => Array.new(count) { part_values } }, sequence, revision)
  end

  def edit(id, length)
    { "edits" => [{ "id" => id, "values" => { "length_mm" => length } }] }
  end

  def request(sequence, revision = @session.revision)
    { "sequence" => sequence, "expected_revision" => revision }
  end

  def invoke(name, params, sequence, revision = @session.revision)
    API.invoke(:context => @context, :name => name, :params => params, :request => request(sequence, revision))
  end

  def records(**params)
    API.query(:context => @context, :name => "ph_composer.records.list",
              :params => { "kind" => PART }.merge(params.transform_keys(&:to_s)))
  end

  def stored(id)
    PhComposer::Records::Engine.new(@model, PhComposer::Registry.current.catalog).find(PART, id)
  end
end
