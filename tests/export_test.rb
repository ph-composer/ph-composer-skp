# frozen_string_literal: true

require_relative "test_helper"

# The export contributor contract (context/CONTRACTS.md, "Translation sections and artifacts"),
# driven by the development example: what the extraction carries, what it leaves out or refuses, the
# composed privacy allowlist and the report that embeds the translator's result unchanged.
class ExportTest < PhComposerTestCase
  API = PhComposer::API
  Export = PhComposer::Export
  FIXTURES = File.join(TESTS_ROOT, "fixtures", "foundation")
  PART = "example.foundation.part"
  REVIEW = "example.foundation.review"

  def setup
    super
    load File.expand_path("../tools/examples/foundation/load.rb", __dir__)
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
  end

  # ------------------------------------------------------------------ registration

  def test_the_example_adds_its_sections_through_the_registry_alone
    registry = PhComposer::Registry.current

    names = registry.export_contributors.values.select { |item| item.owner == "example.foundation" }.map(&:name)
    assert_equal %w[example.foundation.export.definitions example.foundation.export.face_reviews
                    example.foundation.export.parts], names.sort
    assert_equal "example.foundation", registry.owner_of("example.foundation.export.parts")
    assert_includes Export::Privacy.schema(registry).keys, "example.foundation.export.parts"
  end

  def test_a_contributor_with_a_bad_declaration_is_refused_with_every_problem
    feature = feature_declaring do |scope|
      scope.export_contributor("test.export.bad", :section_version => 0, :result => { "state" => nil, "x" => 3 })
      scope.export_contributor("test.export.odd", :section_version => 1, :result => nil) { [] }
    end

    error = assert_raises(PhComposer::RegistrationError) { PhComposer::Registry.install([feature]) }

    messages = error.diagnostics.map(&:message)
    assert_includes messages, "test.export.bad needs a contract block and a positive section version."
    assert_includes messages, "test.export.bad result: result.x: Integer is not a schema."
    assert_includes messages, "test.export.odd result: result must be an object schema."
    refute PhComposer::Registry.current.export_contributors.key?("test.export.odd"), "nothing in the batch publishes"
  end

  # The `request.query` rule: a contributor reads only sections of its own feature or one it requires.
  def test_a_section_read_from_a_feature_not_required_is_refused
    feature = feature_declaring do |scope|
      scope.export_contributor("test.export.reader",
                               :section_version => 1,
                               :requires => ["example.foundation.export.parts",
                                             "test.export.nowhere"]) { [] }
    end

    error = assert_raises(PhComposer::RegistrationError) { PhComposer::Registry.install([feature]) }

    assert_equal [["registration.missing_dependency", "example.foundation.export.parts",
                   "test.export.reader reads example.foundation.export.parts, so test.export must require " \
                   "example.foundation."],
                  ["registration.missing_dependency", "test.export.nowhere",
                   "test.export.reader reads test.export.nowhere, which is not a registered export contributor."]],
                 error.diagnostics.map { |item| [item.code, item.dependency, item.message] }
  end

  def test_a_contributor_reads_a_declared_projection_once_and_nothing_undeclared
    calls = []
    feature = feature_declaring do |scope|
      scope.export_contributor("test.export.hosts", :section_version => 1,
                                                    :projection => lambda { |_reader|
                                                                     calls << :projected
                                                                     %w[h1]
                                                                   }) { [] }
      scope.export_contributor("test.export.reader", :section_version => 1, :requires => ["test.export.hosts"]) { [] }
      scope.export_contributor("test.export.other", :section_version => 1) { [] }
    end
    PhComposer::Registry.install([feature])
    records = Export::RecordReader.new(PhComposer::Records::Engine.new(@model, PhComposer::Registry.current.catalog),
                                       PhComposer::Registry.current.catalog)
    reader = Export::SnapshotReader.new(records, Export::GeometrySnapshot.new([], 0))

    hosts = "test.export.hosts"
    read = reader.within("test.export.reader") { [reader.section(hosts), reader.section(hosts)] }

    assert_equal [%w[h1], %w[h1]], read
    assert_equal 1, calls.length, "a projection is computed once per export"
    assert_raises(PhComposer::InternalError) { reader.within("test.export.other") { reader.section(hosts) } }
    assert_raises(PhComposer::InternalError) { reader.section(hosts) }
  end

  def test_a_report_reads_only_its_own_fields_and_declared_sections
    contributor = PhComposer::Declarations::ExportContributor.new(:name => "a.export.own",
                                                                  :requires => %w[b.export.x d.export.z])
    view = Export::ResultView.new({ "a.export.own" => { "n" => 1 }, "b.export.x" => { "m" => 2 }, "c.export.y" => {} },
                                  contributor)

    assert_equal [1, 2, {}], [view.fetch("n"), view.section("b.export.x").fetch("m"), view.section("d.export.z")]
    assert_raises(KeyError) { view.fetch("m") }
    assert_raises(PhComposer::InternalError) { view.section("c.export.y") }
  end

  # ------------------------------------------------------------------ collection

  # The Ruby half of the shared fixture: the same records produce tests/fixtures/foundation/extraction.json,
  # which tests/python/test_example_translation.py translates.
  def test_the_example_model_collects_to_the_shared_extraction
    seed_example

    extraction = example_collection("run-example-1")

    assert_equal JSON.parse(File.read(File.join(FIXTURES, "extraction.json"))), extraction.document
    assert_equal [{ "code" => "export.metadata_omitted", "section" => "example.foundation.export.parts",
                    "object_id" => "exp_000000000002",
                    "message" => "User data is local to this Model and was not exported." }], extraction.findings
  end

  def test_collection_reads_without_writing
    seed_example
    revision = @session.revision

    example_collection("r")

    assert_equal revision, @session.revision
    refute @model.modified_since_mark? if @model.respond_to?(:modified_since_mark?)
  end

  def test_a_local_only_envelope_is_left_out_with_a_finding
    id = store_part("extension_data" => { "other.org.notes" => envelope("local_only") })

    extraction = example_collection("r")

    part = extraction.document.dig("sections", "example.foundation.export.parts", "records", 0)
    refute part.key?("extensions")
    assert_equal [["export.metadata_omitted", id]], extraction.findings.map { |row| row.values_at("code", "object_id") }
  end

  # EC-04: the example claims its review on Zones' Faces. The claimed fields reach its section; an
  # unclaimed local-only note is left out of the extraction and is still on the Face after reopen.
  def test_the_example_face_review_claim_exports_its_field_and_local_data_survives_reopen
    review = ExampleFoundation::FACE_REVIEW_EXTENSION.envelope("review_status" => "checked", "site" => "north")
    face = seed_reviewed_face(ExampleFoundation::FACE_REVIEW => review,
                              "other.org.notes" => envelope("local_only"))
    before = PhComposer::Zones::Faces::FACE_STORE.read(face)

    extraction = Export::Collection.build(@model, :run_id => "reviews", :contributors => [
      PhComposer::Zones::Faces::ExportProjection::SECTION,
      "example.foundation.export.face_reviews"
    ])

    rows = extraction.document.dig("sections", "example.foundation.export.face_reviews", "records")
    assert_equal [{ "id" => "fac_A00000000001", "review_status" => "checked" }], rows
    text = JSON.generate(extraction.document)
    refute_includes text, "north"
    refute_includes text, "other.org.notes"
    assert(extraction.findings.any? { |row| row["code"] == "export.metadata_omitted" })
    Sketchup.store_model("/tmp/ph-composer-ec04.skp", @model)
    Sketchup.open_file("/tmp/ph-composer-ec04.skp")
    reopened = Sketchup.active_model.entities.to_a.grep(Sketchup::Group).first.entities.to_a.first
    assert_equal before, PhComposer::Zones::Faces::FACE_STORE.read(reopened)
  end

  def test_data_whose_relevance_is_unknown_blocks_the_export
    assert_blocked("unknown", "export.relevance_unknown")
  end

  def test_required_data_nothing_exports_blocks_the_export
    assert_blocked("required", "extension.unavailable")
  end

  def test_an_exported_extension_stored_at_an_older_version_blocks_until_migrated
    store_part("extension_data" => { REVIEW => { "schema_version" => 1, "payload" => { "status" => "draft" },
                                                 "references" => [], "export_relevance" => "required" } })

    error = assert_raises(Export::Blocked) { example_collection("r") }

    assert_equal "extension.schema_unsupported", error.code
    assert_includes error.message, "is outdated"
  end

  def test_an_exported_extension_failing_its_installed_validator_blocks_the_export
    store_part("extension_data" => { REVIEW => { "schema_version" => 2, "payload" => {}, "references" => [
      { "path" => "$.checked_against", "target_kind" => PART, "cardinality" => "one" }
    ], "export_relevance" => "required" } })

    error = assert_raises(Export::Blocked) { example_collection("r") }

    assert_equal "extension.invalid", error.code
    assert_includes error.message, "is invalid"
  end

  # ------------------------------------------------------------------ privacy and report

  def test_the_shared_result_passes_the_composed_allowlist_and_is_embedded_unchanged
    result = shared_result

    html = Export::Report.render(result, :notes => [note("<b>Sill</b> & co")], :display_units => "IP")

    embedded = html[%r{<script id="phc-export-result" type="application/json">(.*)</script>}m, 1]
    assert_equal result, JSON.parse(embedded)
    assert_includes html, "<h2>Example parts</h2>"
    assert_includes html, "95.74 in"
    assert_includes html, "&lt;b&gt;Sill&lt;/b&gt; &amp; co"
    refute_includes html, "<b>Sill</b>"
  end

  def test_a_result_field_no_contributor_declares_is_refused
    PhComposer.reset_for_test # The example, and its declaration of example_parts, is gone.

    error = assert_raises(PhComposer::CodedError) { Export::Report.render(shared_result) }

    assert_equal "export.privacy_undeclared", error.code
    assert_equal "result contains undeclared fields: example.foundation.export.parts.", error.message
  end

  def test_undeclared_nested_fields_local_paths_and_metadata_cannot_pass
    parts = "example.foundation.export.parts"
    nested = shared_result.tap { |result| result[parts]["example_parts"]["label"] = "Sill" }
    path = shared_result.tap { |result| result["findings"] = [finding("/Users/someone/model.skp")] }
    metadata = shared_result.tap { |result| result[parts]["example_parts"]["user_data"] = {} }
    hidden = shared_result.tap { |result| result["run_id"] = { "designer_note" => "client pricing" } }
    listed = shared_result.tap { |result| result["summary"]["objects"] = [{ "anything" => "goes" }] }

    {
      nested => "result.#{parts}.example_parts contains undeclared fields: label.",
      path => "The artifact contains a local file path.",
      metadata => "result.#{parts}.example_parts contains undeclared fields: user_data.",
      hidden => "result.run_id must be a value, not an object.",
      listed => "result.summary.objects must be a value, not an object."
    }.each do |result, message|
      error = assert_raises(PhComposer::CodedError) { Export::Privacy.validate!(result) }
      assert_equal ["export.privacy_undeclared", message], [error.code, error.message]
    end
  end

  def test_the_hygiene_check_refuses_metadata_keys_wherever_they_sit
    error = assert_raises(PhComposer::CodedError) { Export::ArtifactHygiene.validate!("a" => [{ "user_data" => 1 }]) }

    assert_equal "Artifact field user_data is never exported.", error.message
  end

  def test_privacy_schemas_are_checked_for_shape
    assert_empty Export::Privacy.schema_problems("a" => nil, "b" => { "c" => nil }, "d" => [{ "e" => nil }])
    assert_equal ["result must be an object schema"], Export::Privacy.schema_problems([])
    assert_equal ["result.d: a list names one row"], Export::Privacy.schema_problems("d" => [{}, {}])
    assert_equal ["result.o.p: String is not a schema"],
                 Export::Privacy.schema_problems("o" => Export::Privacy::Optional.new({ "p" => "x" }))
  end

  private

  def example_collection(run_id)
    names = PhComposer::Registry.current.export_contributors.values
                                .select { |contributor| contributor.owner == "example.foundation" }.map(&:name)
    Export::Collection.build(@model, :run_id => run_id, :contributors => names)
  end

  # Two parts under one definition, as a script would create them, with the fixture's ids. The Sill
  # carries user data and a checked review.
  def seed_example
    counter = 0
    fixed_ids = ->(prefix) { format("%<prefix>s_%<n>012d", :prefix => prefix, :n => counter += 1) }
    PhComposer::HandlerRequest.stub(:proposal_ids, ->(_session, _name, _params) { fixed_ids }) do
      created = invoke("example.foundation.create_parts",
                       "definition_label" => "Frame",
                       "parts" => [{ "label" => "Sill", "length_mm" => 1200 },
                                   { "label" => "Head", "length_mm" => 1231.9 }])
      sill = created.dig("value", "part_ids", 0)
      invoke("example.foundation.update_parts",
             "edits" => [{ "id" => sill, "user_data" => { "site" => "north" },
                           "review" => { "review_status" => "checked" } }])
    end
  end

  def invoke(name, params)
    outcome = API.invoke(:context => @context, :name => name, :params => params,
                         :request => { "sequence" => @sequence += 1, "expected_revision" => @session.revision })
    assert_equal "completed", outcome.fetch("status"), outcome.inspect
    outcome
  end

  # One classified Wall in a Zone; the Face carries `extension_data`.
  def seed_reviewed_face(extension_data)
    m = 1.0 / 0.0254
    points = [[0, 0, 0], [0, 4, 0], [0, 4, 3], [0, 0, 3]].map { |x, y, z| Geom::Point3d.new(x * m, y * m, z * m) }
    face = Sketchup::Face.new(101, {}, :points => points, :normal => Geom::Vector3d.new(-1, 0, 0))
    PhComposer::Zones::Faces::FACE_STORE.write(face, "id" => "fac_A00000000001", "schema_version" => 1,
                                                     "face_type" => "Wall", "boundary_condition" => "Adiabatic",
                                                     "extension_data" => extension_data)
    group = Sketchup::Group.new(100, Sketchup::Entities.new([face]))
    zone = { "id" => "zon_AAAAAAAAAAAA", "schema_version" => 1, "name" => "Zone A", "building_segment" => "Main",
             "level" => "L1", "ground_depth_mm" => 0.0 }
    PhComposer::Zones::ZONE_STORE.write(group, zone)
    PhComposer::Zones::STAMP_STORE.write(face, PhComposer::Zones::Schema.stamp(zone))
    @model.entities << group
    face
  end

  def store_part(extra)
    definition = invoke("example.foundation.create_parts", "definition_label" => "Frame",
                                                           "parts" => [{ "label" => "Sill", "length_mm" => 1 }])
    id = definition.dig("value", "part_ids", 0)
    store = PhComposer::Records::DictionaryStore.new(PART)
    store.write(@model, store.read(@model, id).merge(extra))
    id
  end

  def assert_blocked(relevance, code)
    store_part("extension_data" => { "other.org.review" => envelope(relevance) })

    error = assert_raises(Export::Blocked) { example_collection("r") }

    assert_equal code, error.code
    assert_equal({ "section" => "example.foundation.export.parts" }, error.detail)
  end

  def envelope(relevance)
    { "schema_version" => 1, "payload" => { "note" => "x" }, "references" => [], "export_relevance" => relevance }
  end

  def shared_result
    JSON.parse(File.read(File.join(FIXTURES, "result.json")))
  end

  def note(message)
    { "code" => "export.metadata_omitted", "section" => "s", "object_id" => "exp_1", "message" => message }
  end

  def finding(message)
    { "code" => "object.unavailable", "section" => "s", "object_id" => "o", "message" => message,
      "blocks_export" => true }
  end

  def feature_declaring(&block)
    Module.new do
      define_singleton_method(:name) { "TestExportFeature" }
      define_singleton_method(:install) do |registry|
        block.call(registry.feature("test.export", :contract_version => 1))
      end
    end
  end
end
