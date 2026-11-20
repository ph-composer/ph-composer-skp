# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/construction_export_fixtures"
require_relative "support/zone_options"

# Phius certification on Building Segments, over a synthetic model of three separate box Zones, Living and
# Kitchen in House and Annex in ADU, and a third Segment, Spare, that no Zone names. The settings are the
# certification feature's extension on each Segment record, saved through Zones' settings Save; a Segment's
# settings go with it on delete and a merge keeps the survivor's only. At export the feature claims them on the
# Segment kind: Zones' section hands over those of the Segments an exported Zone names, so a required extension
# exports instead of blocking, and each exported Segment gets one record with the defaults applied. The golden
# feeds the PHX round trip (tests/python/test_certification_phx_round_trip.py).
class SegmentCertificationTest < PhComposerTestCase
  include ConstructionExportFixtures
  include FixtureFiles
  include ZoneOptionsSupport

  API = PhComposer::API
  Z = PhComposer::Zones
  O = Z::Options
  C = PhComposer::Certification
  NAMESPACE = C::Segment::NAMESPACE
  SECTION = C::SegmentExport::SECTION
  ZONES = Z::ExportProjection::SECTION
  FIXTURE = File.join(TESTS_ROOT, "fixtures", "segments", "certification_extraction.json")
  CHOICES = File.join(TESTS_ROOT, "fixtures", "segments", "certification_choices.json")
  HOUSE = { "category" => "residential", "program" => "phius_2018_zero", "use" => "other", "status" => "complete",
            "type" => "mixed" }.freeze
  ADU = { "category" => "non_residential", "program" => "phius_2021_zero", "use" => "school",
          "status" => "under_construction", "type" => "retrofit" }.freeze
  SPARE = { "category" => "non_residential", "program" => "phius_2015", "use" => "office_administrative",
            "status" => "complete", "type" => "retrofit" }.freeze

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @assembly_id = seed_export_construction
  end

  # ---------------------------------------------------------------- the extension

  def test_the_choices_the_translation_and_the_section_map_are_these
    write_or_compare(CHOICES, { "choices" => C::Segment::CHOICES, "defaults" => C::Segment::DEFAULTS })
    assert_equal C::Segment::FIELDS, C::Segment::DEFAULTS.keys
    assert(C::Segment::DEFAULTS.all? { |field, value| C::Segment::CHOICES.fetch(field).include?(value) })
  end

  def test_a_segment_reads_the_defaults_until_saved_then_its_values_in_one_undo_step
    reference
    house = segment_id("House")
    assert_equal({ "id" => house, "values" => C::Segment::DEFAULTS, "stored" => false, "extension_status" => nil },
                 query(C::READ, "id" => house))
    operations = @model.operations.length

    assert_equal [NAMESPACE], completed(save(house, HOUSE)).fetch("namespaces")

    assert_equal operations + 1, @model.operations.length
    assert_equal({ "id" => house, "values" => HOUSE, "stored" => true, "extension_status" => "understood" },
                 query(C::READ, "id" => house))
    rename(house, "Main")
    assert_equal HOUSE, query(C::READ, "id" => house).fetch("values"), "a rename keeps the settings"
    @model.undo
    @model.undo
    assert_equal false, query(C::READ, "id" => house).fetch("stored")
  end

  def test_a_partial_or_unknown_payload_refuses_and_writes_nothing
    reference
    house = segment_id("House")
    revision = @session.revision
    [HOUSE.merge("program" => "phius_2024_core"), HOUSE.reject { |field, _| field == "type" },
     HOUSE.merge("note" => "x")].each do |payload|
      outcome = save(house, payload)
      assert_equal %w[refused validation.failed], outcome.values_at("status", "code"), outcome.inspect
    end
    assert_equal revision, @session.revision
    assert_equal false, query(C::READ, "id" => house).fetch("stored")
    assert_equal "target.not_found", API.query(:context => @context, :name => C::READ,
                                               :params => { "id" => "bsg_Ab12Cd34Ef56" }).fetch("code")
  end

  def test_the_settings_go_with_a_deleted_segment_and_a_merge_keeps_the_survivors_only
    reference
    house, adu, spare = %w[House ADU Spare].map { |name| segment_id(name) }
    completed(save(house, HOUSE))
    completed(save(adu, ADU))
    completed(save(spare, SPARE))

    removed = completed(invoke("#{O::PREFIX}.remove", "collection" => "building_segment", "id" => spare))
    assert_equal [{ "id" => spare, "namespaces" => [NAMESPACE] }], removed.fetch("removed_extensions")
    @model.undo
    assert_equal SPARE, query(C::READ, "id" => spare).fetch("values"), "Undo restores them"

    merged = completed(invoke("#{O::PREFIX}.merge", "collection" => "building_segment", "id" => adu,
                                                    "target_id" => house))
    assert_equal [{ "id" => adu, "namespaces" => [NAMESPACE] }], merged.fetch("removed_extensions")
    assert_equal HOUSE, query(C::READ, "id" => house).fetch("values")
    refute_includes O::SEGMENTS.store.ids(@model), adu
  end

  # ---------------------------------------------------------------- export

  def test_export_writes_each_exported_segment_and_leaves_an_empty_segments_settings_home
    reference
    completed(save(segment_id("House"), HOUSE))
    completed(save(segment_id("Spare"), SPARE))

    findings = preflight
    assert_empty findings.select { |row| row.fetch("blocks_export") }, findings.inspect

    extraction = extract
    records = extraction.document.dig("sections", SECTION, "records")
    by_name = records.to_h { |row| [segment_name(row.fetch("id")), row] }
    assert_equal %w[ADU House], by_name.keys.sort, "one record per Segment, two Zones in House"
    assert_equal 2, records.length
    assert_equal HOUSE, by_name.fetch("House").slice(*C::Segment::FIELDS)
    assert_equal C::Segment::DEFAULTS, by_name.fetch("ADU").slice(*C::Segment::FIELDS), "no settings, the defaults"
    zones = extraction.document.dig("sections", ZONES, "records")
    assert_equal zones.map { |row| row.fetch("building_segment_export_identifier") }.uniq.sort,
                 records.map { |row| row.fetch("export_identifier") }.sort
    refute_includes JSON.generate(extraction.document), "phius_2015", "Spare's settings stay in the Model"
    completed(save(segment_id("ADU"), ADU))
    write_or_compare(FIXTURE, stable(extract.document))
  end

  def test_an_invalid_stored_payload_blocks_the_preflight_and_the_export_on_any_segment
    reference
    %w[House Spare].each do |name|
      id = segment_id(name)
      stored = O::SEGMENTS.store.read(@model, id)
      envelope = C::Segment::EXTENSION.envelope(HOUSE.merge("use" => "hotel"))
      O::SEGMENTS.store.write(@model, stored.merge("extension_data" => { NAMESPACE => envelope }))
      assert_equal({ "id" => id, "values" => C::Segment::DEFAULTS, "stored" => false,
                     "extension_status" => "invalid" }, query(C::READ, "id" => id))

      blocking = preflight.select { |row| row.fetch("blocks_export") }
      assert_equal [[id, "extension.invalid"]], blocking.map { |row| row.values_at("object_id", "code") }, name
      assert_equal "extension.invalid", assert_raises(PhComposer::Export::Blocked) { extract }.code
      O::SEGMENTS.store.write(@model, stored)
    end
  end

  def test_legacy_zones_name_no_segment_record_so_the_section_writes_no_record
    @model.entities << box(1000, "L", "Living", "House", [0, 5, 0, 4])

    extraction = extract
    assert_empty extraction.document.dig("sections", SECTION, "records")
    assert_nil extraction.document.dig("sections", ZONES, "records", 0)["building_segment_id"]
  end

  # ---------------------------------------------------------------- the claim on a catalog record kind

  def test_a_required_segment_extension_with_no_claim_blocks_the_preflight_and_the_export
    install_development_namespace(:claims => [])
    reference
    write_development_note("House")

    assert_includes preflight.select { |row| row.fetch("blocks_export") }.map { |row| row.fetch("code") },
                    "extension.unavailable"
    assert_equal "extension.unavailable", assert_raises(PhComposer::Export::Blocked) { extract }.code
  end

  def test_a_claimed_required_segment_extension_exports_with_a_null_path_for_named_segments_only
    install_development_namespace
    reference
    write_development_note("House")
    write_development_note("Spare")

    assert_empty preflight.select { |row| row.fetch("blocks_export") }
    rows = extract.document.dig("sections", "test.note.export", "records")
    assert_equal [{ "id" => segment_id("House"), "path" => nil, "payload" => { "text" => "north" } }], rows
  end

  def test_a_claim_on_a_record_kind_its_feature_does_not_require_refuses
    error = assert_raises(PhComposer::RegistrationError) do
      install_development_namespace(:requires => [])
    end
    assert_match(/entity target or record kind its feature must own or require/,
                 error.diagnostics.map(&:message).join("\n"))
  end

  private

  DEVELOPMENT = "test.note.segment"

  def install_development_namespace(claims: nil, requires: [Z::FEATURE_ID])
    extension = PhComposer::Records::Extension.new(
      :namespace => DEVELOPMENT, :schema_version => 1, :export_relevance => "required",
      :validate => ->(payload) { payload["text"].is_a?(String) ? [] : ["text must be a string"] }
    )
    claims ||= [{ "namespace" => DEVELOPMENT, "target_kind" => O::SEGMENT_KIND, "source_section" => ZONES,
                  "fields" => ["text"] }]
    fixture = Module.new do
      define_singleton_method(:install) do |registry|
        feature = registry.feature("test.note", :contract_version => 1, :requires => requires)
        feature.extension(extension)
        feature.export_contributor("test.note.export", :section_version => 1, :requires => [ZONES],
                                                       :entity_projections => claims) do |reader|
          claims.empty? ? [] : reader.entity_projection(DEVELOPMENT, O::SEGMENT_KIND)
        end
      end
    end
    PhComposer::Registry.install([fixture])
  end

  def write_development_note(name)
    id = segment_id(name)
    stored = query("ph_composer.records.list", "kind" => O::SEGMENT_KIND, "ids" => [id]).fetch("records").first
    completed(invoke("ph_composer.records.update_metadata", "updates" => [{
      "reference" => { "kind" => O::SEGMENT_KIND, "id" => id },
      "extension_payloads" => { DEVELOPMENT => { "text" => "north" } },
      "expected_metadata" => stored.slice("user_data", "extension_data")
    }]))
  end

  # Living (x 0 to 5 m, y 0 to 4 m) and Kitchen (y 10 to 14 m) in House and Annex (x 10 to 14 m) in ADU, each
  # 3 m high with every Face classified and sharing none, then Spare, a third Segment no Zone names. Segment
  # names hold no space, which PHX's merge of a Segment's Rooms refuses.
  def reference
    @model.entities << box(1000, "L", "Living", "House", [0, 5, 0, 4]) <<
      box(3000, "K", "Kitchen", "House", [0, 5, 10, 14]) << box(2000, "A", "Annex", "ADU", [10, 14, 0, 4])
    adopt_zone_options
    create_zone_option("building_segment", "Spare")
  end

  def box(base, letter, name, segment, (x0, x1, y0, y1))
    loops = [["Floor", [0, 0, -1], [[x0, y0, 0], [x0, y1, 0], [x1, y1, 0], [x1, y0, 0]]],
             ["RoofCeiling", [0, 0, 1], [[x0, y0, 3], [x1, y0, 3], [x1, y1, 3], [x0, y1, 3]]],
             ["Wall", [-1, 0, 0], [[x0, y0, 0], [x0, y0, 3], [x0, y1, 3], [x0, y1, 0]]],
             ["Wall", [1, 0, 0], [[x1, y0, 0], [x1, y1, 0], [x1, y1, 3], [x1, y0, 3]]],
             ["Wall", [0, -1, 0], [[x0, y0, 0], [x1, y0, 0], [x1, y0, 3], [x0, y0, 3]]],
             ["Wall", [0, 1, 0], [[x0, y1, 0], [x0, y1, 3], [x1, y1, 3], [x1, y1, 0]]]]
    faces = loops.each_with_index.map do |(type, normal, loop), index|
      face = Sketchup::Face.new(base + index + 1, {}, :points => loop.map { |xyz| metres(xyz) },
                                                      :normal => Geom::Vector3d.new(*normal))
      Z::Faces::FACE_STORE.write(face, "id" => format("fac_%<letter>s%<number>011d", :letter => letter,
                                                                                     :number => index + 1),
                                       "schema_version" => 1, "face_type" => type,
                                       "boundary_condition" => type == "Floor" ? "Ground" : "Outdoors",
                                       "assembly_id" => @assembly_id, "user_data" => {}, "extension_data" => {})
      face
    end
    group = Sketchup::Group.new(base, Sketchup::Entities.new(faces), :name => name)
    zone = { "id" => "zon_#{letter * 12}", "schema_version" => 1, "name" => name, "building_segment" => segment,
             "level" => "L1", "ground_depth_mm" => 0.0, "user_data" => {}, "extension_data" => {} }
    Z::ZONE_STORE.write(group, zone)
    stamp = Z::Schema.stamp(zone)
    faces.each { |face| Z::STAMP_STORE.write(face, stamp) }
    group
  end

  def metres(xyz)
    Geom::Point3d.new(*xyz.map { |value| value / 0.0254 })
  end

  # The document with the Building Segment ids adoption and create mint, which differ each run, renumbered by
  # Segment name, and the section's records, which follow those ids, in the renumbered order, so the golden
  # compares.
  def stable(document)
    names = query("#{O::PREFIX}.all").fetch("building_segments").map do |row|
      [row.dig("values", "name"), row.fetch("id")]
    end
    fixed = names.sort.each_with_index.to_h do |(_name, id), index|
      [id, format("bsg_FIXED%<number>07d", :number => index + 1)]
    end
    stable = JSON.parse(JSON.generate(document).gsub(/\bbsg_[A-Za-z0-9]{12}\b/) { |id| fixed.fetch(id) })
    stable.dig("sections", SECTION, "records").sort_by! { |row| row.fetch("id") }
    stable
  end

  def save(id, payload)
    segment = query("#{O::PREFIX}.all").then do |all|
      [all.fetch("building_segments").find { |row| row.fetch("id") == id }, all.fetch("default_segment_id")]
    end
    row, default_id = segment
    values = row.fetch("values").slice("name", "colour")
    invoke(O::SegmentSettings::SAVE, "id" => id, "values" => values, "expected_values" => values,
                                     "default" => default_id == id, "expected_default_segment_id" => default_id,
                                     "extension_payloads" => { NAMESPACE => payload },
                                     "expected_extension_data" => row.fetch("extension_data", {}))
  end

  def rename(id, name)
    all = query("#{O::PREFIX}.all")
    row = all.fetch("building_segments").find { |candidate| candidate.fetch("id") == id }
    values = row.fetch("values").slice("name", "colour")
    completed(invoke(O::SegmentSettings::SAVE, "id" => id, "values" => values.merge("name" => name),
                                               "expected_values" => values,
                                               "default" => all.fetch("default_segment_id") == id,
                                               "expected_default_segment_id" => all.fetch("default_segment_id"),
                                               "extension_payloads" => {},
                                               "expected_extension_data" => row.fetch("extension_data", {})))
  end

  def segment_id(name)
    query("#{O::PREFIX}.all").fetch("building_segments").find { |row| row.dig("values", "name") == name }.fetch("id")
  end

  def segment_name(id)
    query("#{O::PREFIX}.all").fetch("building_segments").find { |row| row.fetch("id") == id }.dig("values", "name")
  end

  def preflight
    completed(API.export_preflight(:context => @context)).fetch("findings")
  end

  def extract
    PhComposer::Export::Collection.build(@model, :run_id => "segment-certification")
  end

  def query(name, params = {})
    completed(API.query(:context => @context, :name => name, :params => params))
  end

  def completed(outcome)
    assert_equal "completed", outcome.fetch("status"), outcome.inspect
    outcome.fetch("value")
  end

  def invoke(name, params)
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence += 1, "expected_revision" => @session.revision })
  end
end
