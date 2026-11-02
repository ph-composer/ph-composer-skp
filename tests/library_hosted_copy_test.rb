# frozen_string_literal: true

require_relative "test_helper"

# A version 2 source's use check before any write, and the exact source revision a copy keeps through
# local edits, keep-local, library updates, Undo, Redo and save and reopen.
class LibraryHostedCopyTest < PhComposerTestCase
  include HostedLibraryFixtures

  API = PhComposer::API
  Manager = PhComposer::Library::Connection::Manager
  PREFIX = "ph_composer.library"
  MATERIALS = "ph_composer.assemblies.materials"
  SELECTED = { "provider_id" => PROVIDER_ID, "kind" => "materials" }.freeze

  def setup
    super
    PhComposer::Registry.install([HostedLibraryFixtures::Feature])
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id, :capabilities => %w[read view model_write setup])
    @server = HostedLibraryFixtures.server
    @now = 100.0
    Manager.clock = -> { @now }
    @sequence = 0
    connection.finish_sign_in
    @generation = load(hosted_response)
  end

  def connection
    Manager.connection(PhComposer::Registry.current.library_providers.fetch(PROVIDER_KIND))
  end

  def load(response)
    API.setup(:context => @context, :name => "#{PREFIX}.load", :params => SELECTED)
    @server.response = response
    UI.run_timers
    API.query(:context => @context, :name => "#{PREFIX}.catalog", :params => SELECTED).dig("value", "generation")
  end

  def params(choice = "create", **extra)
    SELECTED.merge("generation" => @generation, "library_id" => "firm-lib", "record_id" => "rec-1",
                   "choice" => choice).merge(extra.transform_keys(&:to_s))
  end

  def invoke(name, values)
    @sequence += 1
    API.invoke(:context => @context, :name => name, :params => values,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end

  def materials
    API.query(:context => @context, :name => "#{MATERIALS}.all").dig("value", "records")
  end

  def source
    materials.first.dig("values", "source")
  end

  def candidate
    API.query(:context => @context, :name => "#{PREFIX}.in_file",
              :params => SELECTED.merge("generation" => @generation))
       .dig("value", "rows").first.dig("resolution", "candidates").first
  end

  def refuses_without_writing(code)
    refused = invoke("#{PREFIX}.copy", params)
    assert_equal ["refused", code, "none"], refused.values_at("status", "code", "effect"), refused.inspect
    assert_empty materials
  end

  def test_a_copy_asks_about_the_exact_row_before_writing_and_keeps_its_source_revision
    copied = invoke("#{PREFIX}.copy", params)
    assert_equal "committed", copied.fetch("effect"), copied.inspect
    use = @server.uses.last
    assert_equal "snap-1", use.fetch("snapshot_id")
    selected = { "kind" => "materials", "library_id" => "firm-lib", "record_id" => "rec-1", "source_revision" => 3 }
    assert_equal [selected], use.fetch("selection")
    assert_match(/\Ause_\h{24}\z/, use.fetch("operation_id"))
    assert_equal [3, 1, PROVIDER_KIND], source.values_at("source_revision", "source_revision_schema_version",
                                                         "provider_kind")
  end

  def test_each_refusing_answer_and_a_declared_or_undeclared_failure_writes_nothing
    { "reload_required" => "library.reload_required",
      "reauthorization_required" => "library.reauthorization_required",
      :unavailable => "library.provider_unavailable", "maybe" => "library.provider_invalid" }.each do |answer, code|
      @server.use_answer = answer
      refuses_without_writing(code)
    end
    @server.use_answer = "allowed"
    @server.failures[:authorize_use] = PhComposer::Library::Error.new("library.hosted_entitlement_ended", "ended")
    refuses_without_writing("library.hosted_entitlement_ended")
    @server.failures[:authorize_use] = PhComposer::Library::Error.new("library.hosted_busy", "not declared here")
    refuses_without_writing("library.provider_failed")
  end

  def test_an_answer_that_outlasts_its_window_is_refused_as_expired
    @server.use_answer = lambda do
      @now += PhComposer::Library::Connection::Use::WINDOW_SECONDS + 0.5
      "allowed"
    end
    refuses_without_writing("library.use_expired")
  end

  def test_a_connection_reload_or_closed_model_during_the_check_refuses_the_copy
    # The extension's sign-in finished for another connection while the check ran.
    @server.use_answer = lambda do
      connection.finish_sign_in("connection-2")
      "allowed"
    end
    refuses_without_writing("library.connection_changed")
    @server.use_answer = "allowed"
    @generation = load(hosted_response)
    # The catalog the row came from was dropped while the check ran.
    @server.use_answer = lambda do
      PhComposer::Library::State.for(@session).remove(PROVIDER_ID)
      "allowed"
    end
    refuses_without_writing("library.selection_changed")
    @generation = load(hosted_response)
    @server.use_answer = lambda do
      @model.define_singleton_method(:valid?) { false }
      "allowed"
    end
    refused = invoke("#{PREFIX}.copy", params)
    assert_equal "library.model_changed", refused.fetch("code")
    assert_equal "none", refused.fetch("effect")
  end

  # The window is checked again after the writes are staged, just before the action commits them.
  def test_a_window_that_expires_while_the_writes_are_staged_refuses_with_no_write
    readings = [100.0, 101.0, 100.0 + PhComposer::Library::Connection::Use::WINDOW_SECONDS + 1]
    Manager.clock = -> { readings.length > 1 ? readings.shift : readings.first }
    refuses_without_writing("library.use_expired")
    assert_equal 1, @server.uses.length
  end

  def test_a_catalog_loaded_under_an_older_connection_must_be_loaded_again
    API.setup(:context => @context, :name => "#{PREFIX}.connections.reauthorize",
              :params => { "provider_kind" => PROVIDER_KIND })
    refuses_without_writing("library.reload_required")
    assert_empty @server.uses
  end

  def test_keep_local_takes_nothing_from_the_library_and_needs_no_check
    invoke("#{PREFIX}.copy", params)
    uses = @server.uses.length
    kept = invoke("#{PREFIX}.copy", params("keep_local"))
    assert_equal %w[completed none], kept.values_at("status", "effect")
    assert_equal uses, @server.uses.length
    assert_equal 3, source.fetch("source_revision")
  end

  # Revision 4 has the same content as 3: the fingerprint matches, yet the copy keeps 3 until an
  # explicit library update adopts 4. Each step undoes and redoes, and the result survives reopening.
  def test_source_revision_survives_edit_keep_local_and_moves_only_through_a_guarded_update
    invoke("#{PREFIX}.copy", params)
    id = materials.first.fetch("id")
    @model.undo
    assert_empty materials
    @model.redo
    assert_equal 3, source.fetch("source_revision")
    invoke("#{MATERIALS}.update", "id" => id, "values" => { "name" => "Edited locally" },
                                  "expected_values" => { "name" => "Hosted insulation" })
    assert_equal [3, "Edited locally"], [source.fetch("source_revision"), materials.first.dig("values", "name")]
    @model.undo
    @model.redo
    assert_equal 3, source.fetch("source_revision")
    revisions = { "materials/firm-lib/rec-1" => 4 }
    @generation = load(hosted_response(:revisions => revisions, :snapshot => "snap-2", :library_revision => 8))
    assert_equal [false, true], candidate.values_at("source_changed", "comparison_available")
    invoke("#{PREFIX}.copy", params("keep_local"))
    assert_equal 3, source.fetch("source_revision")
    updated = invoke("#{PREFIX}.copy", params("use_library", :local_id => id,
                                                             :expected_values => candidate.fetch("expected_values")))
    assert_equal "committed", updated.fetch("effect"), updated.inspect
    assert_equal [4, "Hosted insulation"], [source.fetch("source_revision"), materials.first.dig("values", "name")]
    @model.undo
    assert_equal [3, "Edited locally"], [source.fetch("source_revision"), materials.first.dig("values", "name")]
    @model.redo
    assert_equal 4, source.fetch("source_revision")
    path = File.join(Dir.tmpdir, "ph-composer-hosted-revision.skp")
    @model.save(path)
    Sketchup.open_file(path)
    @session = PhComposer::Sessions.for(Sketchup.active_model)
    @context = API.connect(:session_id => @session.id)
    assert_equal [4, 1], source.values_at("source_revision", "source_revision_schema_version")
  ensure
    FileUtils.rm_f(path) if path
  end

  def test_a_revision_without_its_schema_version_or_a_non_positive_one_is_invalid_provenance
    invoke("#{PREFIX}.copy", params)
    id = materials.first.fetch("id")
    { "missing schema version" => source.reject { |key, _value| key == "source_revision_schema_version" },
      "zero" => source.merge("source_revision" => 0) }.each do |label, value|
      refused = invoke("#{MATERIALS}.update", "id" => id, "values" => { "source" => value },
                                              "expected_values" => {})
      assert_equal "refused", refused.fetch("status"), label
    end
    assert_equal 3, source.fetch("source_revision")
  end
end
