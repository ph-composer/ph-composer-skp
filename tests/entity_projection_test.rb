# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/construction_export_fixtures"

# An export contributor claims structured extension data its feature owns on another feature's
# entities (`entity_projections:`). The entity owner's section hands over only the declared fields of
# an understood envelope; everything else follows the existing metadata rules.
class EntityProjectionTest < PhComposerTestCase
  include ConstructionExportFixtures

  Export = PhComposer::Export
  FACES = PhComposer::Zones::Faces::ExportProjection::SECTION
  FACE_KIND = PhComposer::Zones::Faces::REFERENCE_KIND
  NAMESPACE = "test.review.status"
  EXTENSION = PhComposer::Records::Extension.new(
    :namespace => NAMESPACE, :schema_version => 2, :export_relevance => "required",
    :validate => ->(payload) { %w[draft checked].include?(payload["review_status"]) ? [] : ["bad status"] }
  )
  CLAIM = { "namespace" => NAMESPACE, "target_kind" => FACE_KIND, "source_section" => FACES,
            "fields" => ["review_status"] }.freeze

  def setup
    super
    @model = Sketchup.active_model
    @admitted = 0
  end

  def review_feature(claims: [CLAIM], requires: ["ph_composer.zones"], sections: [FACES], extension: EXTENSION,
                     read: true)
    admitted = -> { @admitted += 1 }
    Module.new do
      define_singleton_method(:install) do |registry|
        scope = registry.feature("test.review", :contract_version => 1, :requires => requires)
        scope.extension(extension) if extension
        scope.export_contributor("test.review.export", :section_version => 1, :requires => sections,
                                                       :entity_projections => claims) do |reader|
          admitted.call
          read ? reader.entity_projection(NAMESPACE, FACE_KIND) : []
        end
      end
    end
  end

  def refused(feature)
    error = assert_raises(PhComposer::RegistrationError) { PhComposer::Registry.install([feature]) }
    refute PhComposer::Registry.installed?("test.review")
    error.diagnostics.map(&:message).join("\n")
  end

  # One classified box Zone; the first Face carries `envelope` when given.
  def seed(envelope = nil, user_data: {})
    assembly = seed_export_construction
    m = 1.0 / 0.0254
    points = [[0, 0, 0], [0, 4, 0], [0, 4, 3], [0, 0, 3]].map { |x, y, z| Geom::Point3d.new(x * m, y * m, z * m) }
    face = Sketchup::Face.new(101, {}, :points => points, :normal => Geom::Vector3d.new(-1, 0, 0))
    record = { "id" => "fac_A00000000001", "schema_version" => 1, "face_type" => "Wall",
               "boundary_condition" => "Outdoors", "assembly_id" => assembly, "user_data" => user_data,
               "extension_data" => envelope ? { NAMESPACE => envelope } : {} }
    PhComposer::Zones::Faces::FACE_STORE.write(face, record)
    group = Sketchup::Group.new(100, Sketchup::Entities.new([face]))
    zone = { "id" => "zon_AAAAAAAAAAAA", "schema_version" => 1, "name" => "Zone A", "building_segment" => "Main",
             "level" => "L1", "ground_depth_mm" => 0.0, "user_data" => {}, "extension_data" => {} }
    PhComposer::Zones::ZONE_STORE.write(group, zone)
    PhComposer::Zones::STAMP_STORE.write(face, PhComposer::Zones::Schema.stamp(zone))
    @model.entities << group
  end

  def collect(names = [FACES, "test.review.export"])
    Export::Collection.build(@model, :run_id => "claims", :contributors => names)
  end

  def payload(extra = {})
    EXTENSION.envelope({ "review_status" => "draft", "site_note" => "kept local" }.merge(extra))
  end

  def test_a_valid_claim_registers_without_running_its_contract
    PhComposer::Registry.install([review_feature])

    assert_equal [CLAIM], PhComposer::Registry.current.export_contributors.fetch("test.review.export")
                                              .entity_projections
    assert_equal 0, @admitted
  end

  def test_claims_refuse_a_foreign_namespace_an_unrequired_target_a_missing_source_overlaps_and_empty_fields
    assert_match(/not an extension test.review declares/, refused(review_feature(:extension => nil)))
    assert_match(/entity target or record kind its feature must own or require/,
                 refused(review_feature(:requires => [])))
    assert_match(/must list in requires/, refused(review_feature(:sections => [])))
    assert_match(/already projects/, refused(review_feature(:claims => [CLAIM, CLAIM])))
    assert_match(/non-empty list/, refused(review_feature(:claims => [CLAIM.merge("fields" => [])])))
  end

  def test_a_claimed_understood_payload_projects_only_its_declared_fields
    PhComposer::Registry.install([review_feature])
    seed(payload)

    extraction = collect

    rows = extraction.document.dig("sections", "test.review.export", "records")
    assert_equal [{ "id" => "fac_A00000000001", "path" => [100, 101], "payload" => { "review_status" => "draft" } }],
                 rows
    refute_includes JSON.generate(extraction.document), "kept local"
  end

  def test_the_same_payload_without_a_claim_still_blocks_as_unexported
    PhComposer::Registry.install([review_feature(:claims => [], :read => false)])
    seed(payload)

    assert_equal "extension.unavailable", assert_raises(Export::Blocked) { collect }.code
  end

  def test_an_invalid_or_unsupported_claimed_payload_still_blocks_with_its_code
    PhComposer::Registry.install([review_feature])
    seed(payload("review_status" => "maybe"))
    assert_equal "extension.invalid", assert_raises(Export::Blocked) { collect }.code

    @model.entities.clear!
    seed(payload.merge("schema_version" => 1))
    assert_equal "extension.schema_unsupported", assert_raises(Export::Blocked) { collect }.code
  end

  def test_a_local_only_payload_without_a_claim_is_omitted_with_a_finding
    PhComposer::Registry.install([review_feature(:claims => [], :read => false)])
    seed(payload.merge("export_relevance" => "local_only"))

    findings = collect.findings

    assert(findings.any? { |row| row["code"] == "export.metadata_omitted" && row["object_id"] == "fac_A00000000001" })
  end

  def test_a_claimed_row_its_contributor_never_reads_blocks_the_export
    PhComposer::Registry.install([review_feature(:read => false)])
    seed(payload)

    error = assert_raises(Export::Blocked) { collect }

    assert_equal "export.blocked", error.code
    assert_includes error.message, NAMESPACE
  end

  def test_a_faces_user_data_passes_through_beside_a_claim
    PhComposer::Registry.install([review_feature])
    seed(payload, :user_data => { "firm" => { "note" => "kept" } })

    extraction = collect

    face = extraction.document.dig("sections", FACES, "records", 0)
    assert_equal({ "firm" => { "note" => "kept" } }, face["user_data"])
    assert(extraction.findings.none? { |row| row["code"] == "export.metadata_omitted" })
  end

  def test_user_data_under_a_contributors_declared_namespace_blocks_the_export
    PhComposer::Registry.install([review_feature, Module.new do
      define_singleton_method(:install) do |registry|
        registry.feature("outside.tags", :contract_version => 1)
                .export_contributor("outside.tags.export", :section_version => 1,
                                                           :user_data_keys => ["outside.tag"]) { |_reader| [] }
      end
    end])
    seed(payload, :user_data => { "outside" => { "tag" => "mine" } })

    error = assert_raises(Export::Blocked) { collect }

    assert_includes error.message, "reserved key outside"
  end

  def test_user_data_under_the_reserved_key_blocks_the_export
    PhComposer::Registry.install([review_feature])
    seed(payload, :user_data => { "ph_composer" => { "level" => "mine" } })

    error = assert_raises(Export::Blocked) { collect }

    assert_equal "export.blocked", error.code
    assert_includes error.message, "reserved key"
  end

  def test_a_claim_survives_full_collection_shared_reads_and_the_incremental_builder
    PhComposer::Registry.install([review_feature])
    seed(payload)

    full = collect(nil).document.dig("sections", "test.review.export", "records")
    builder = Export::Collection::Builder.new(@model, :run_id => "slices")
    nil until builder.advance
    sliced = builder.extraction.document.dig("sections", "test.review.export", "records")

    assert_equal [{ "review_status" => "draft" }], full.map { |row| row["payload"] }
    assert_equal full, sliced
  end

  def test_a_row_captured_by_a_section_other_than_the_declared_source_is_refused
    zone_claim = CLAIM.merge("target_kind" => PhComposer::Zones::REFERENCE_KIND)
    feature = review_feature(:claims => [zone_claim], :read => false)
    PhComposer::Registry.install([feature])
    seed
    group = @model.entities.to_a.grep(Sketchup::Group).first
    zone = PhComposer::Zones::ZONE_STORE.read(group)
    PhComposer::Zones::ZONE_STORE.write(group, zone.merge("extension_data" => { NAMESPACE => payload }))

    error = assert_raises(PhComposer::InternalError) do
      collect([FACES, PhComposer::Zones::ExportProjection::SECTION, "test.review.export"])
    end
    assert_includes error.message, "its claim names"
  end

  def test_export_sections_that_require_each_other_or_themselves_refuse_registration
    cyclic = lambda do |pairs|
      Module.new do
        define_singleton_method(:install) do |registry|
          scope = registry.feature("test.review", :contract_version => 1)
          pairs.each do |name, requires|
            scope.export_contributor(name, :section_version => 1, :requires => requires) { |_reader| [] }
          end
        end
      end
    end
    both = { "test.review.a" => ["test.review.b"], "test.review.b" => ["test.review.a"] }
    assert_match(/require each other/, refused(cyclic.call(both)))
    assert_match(/require each other/, refused(cyclic.call("test.review.a" => ["test.review.a"])))
  end

  def test_a_claim_with_a_symbol_key_is_a_named_diagnostic
    malformed = CLAIM.reject { |key, _value| key == "fields" }.merge(:fields => ["review_status"])

    assert_match(/entity_projections must be a list of claims/, refused(review_feature(:claims => [malformed])))
  end

  def test_section_cycle_validation_stays_linear_on_a_dense_acyclic_graph
    names = 24.times.map { |index| format("test.review.s%02d", index) }
    dense = Module.new do
      define_singleton_method(:install) do |registry|
        scope = registry.feature("test.review", :contract_version => 1)
        names.each_with_index do |name, index|
          scope.export_contributor(name, :section_version => 1, :requires => names.first(index)) { |_reader| [] }
        end
      end
    end
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    PhComposer::Registry.install([dense])

    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 2.0
  end
end
