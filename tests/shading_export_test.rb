# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/construction_export_fixtures"

# The Shades export section and its preflight over ACCEPTANCE's synthetic reference model: Zone A, a classified
# box holding a tagged overhang Face and a tagged Group "Fin" of two Faces; at the root two loose Faces sharing an
# edge, a tagged Group "Neighbour" of five Faces and a nested unnamed Group of one, three tagged placements of a
# component "Louvre" of two Faces, and one tagged Face with a hole. 18 Shades in five components. The extraction
# this writes is the one the Python section's tests translate (tests/fixtures/shading/extraction.json).
class ShadingExportTest < PhComposerTestCase
  include ConstructionExportFixtures
  include FixtureFiles

  API = PhComposer::API
  SH = PhComposer::Shading
  X = SH::ExportSection
  MARK = SH::Mark::STORE
  FACE_STORE = PhComposer::Zones::Faces::FACE_STORE
  FIXTURE = File.join(TESTS_ROOT, "fixtures", "shading", "extraction.json")
  # The result fields the contributor declares, for the Python section's test to hold its rows to.
  RESULT_FIELDS = File.join(TESTS_ROOT, "fixtures", "shading", "result_fields.json")
  INCHES = 1 / 0.0254
  EXPECTED = { "Fin" => 2, "Louvre" => 6, "Neighbour" => 6, "Shading" => 3, "Zone A Shading" => 1 }.freeze

  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?(SH::FEATURE_ID)
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @assembly_id = seed_export_construction
  end

  def names
    [PhComposer::Zones::Faces::ExportProjection::SECTION, PhComposer::Zones::ExportProjection::SECTION,
     PhComposer::Assemblies::ExportProjection::SECTION, PhComposer::Assemblies::SourceReport::SECTION,
     PhComposer::Spaces::ExportProjection::SECTION, PhComposer::ThermalBridges::ExportProjection::SECTION,
     PhComposer::ModelMetadata::SECTION, PhComposer::Climate::SiteExport::SECTION,
     PhComposer::Certification::SegmentExport::SECTION, X::SECTION]
  end

  def point(xyz)
    Geom::Point3d.new(*xyz.map { |value| value * INCHES })
  end

  def face(id, loop, holes: [])
    Sketchup::Face.new(id, {}, :points => loop.map { |xyz| point(xyz) },
                               :holes => holes.map { |hole| hole.map { |xyz| point(xyz) } })
  end

  def mark(entity, record = { "schema_version" => 1 })
    MARK.write(entity, record)
    entity
  end

  # ACCEPTANCE's reference model, every mark set as Set as Shading would set it.
  def reference
    @overhang = mark(face(1010, [[0, -1, 2.5], [5, -1, 2.5], [5, 0, 2.5], [0, 0, 2.5]]))
    fins = [face(1021, [[0, -1, 0], [0, -1, 2], [0, 0, 2], [0, 0, 0]]),
            face(1022, [[5, -1, 0], [5, -1, 2], [5, 0, 2], [5, 0, 0]])]
    @fin = mark(Sketchup::Group.new(1020, Sketchup::Entities.new(fins), :name => "Fin"))
    @zone = zone_box(1000, "A", [@overhang, @fin])
    walls = box_loops(20, 25, 0, 5, 0, 6).drop(1).each_with_index.map { |loop, index| face(3001 + index, loop) }
    nested = Sketchup::Group.new(3010, Sketchup::Entities.new([face(3011, [[26, 0, 0], [27, 0, 0], [27, 0, 1],
                                                                           [26, 0, 1]])]))
    neighbour = mark(Sketchup::Group.new(3000, Sketchup::Entities.new(walls + [nested]), :name => "Neighbour"))
    slats = [face(4001, [[0, 0, 0], [1, 0, 0], [1, 0, 0.2], [0, 0, 0.2]]),
             face(4002, [[0, 0, 0.5], [1, 0, 0.5], [1, 0, 0.7], [0, 0, 0.7]])]
    louvre = Sketchup::ComponentDefinition.new(Sketchup::Entities.new(slats), :name => "Louvre")
    placements = [4100, 4200, 4300].each_with_index.map do |id, index|
      offset = [index * 2, -2, 1].map { |value| value * INCHES }
      mark(Sketchup::ComponentInstance.new(id, louvre, :transformation => Geom::Transformation.translation(offset)))
    end
    holed = mark(face(5000, [[30, 0, 0], [36, 0, 0], [36, 6, 0], [30, 6, 0]],
                      :holes => [[[32, 2, 0], [32, 4, 0], [34, 4, 0], [34, 2, 0]]]))
    loose = [mark(face(2001, [[10, 0, 0], [12, 0, 0], [12, 2, 0], [10, 2, 0]])),
             mark(face(2002, [[12, 0, 0], [14, 0, 0], [14, 2, 0], [12, 2, 0]]))]
    ([@zone, neighbour, holed] + loose + placements).each { |entity| @model.entities << entity }
  end

  # The six loops of an axis-aligned box, floor first, each wound outward.
  def box_loops(x_min, x_max, y_min, y_max, z_min, z_max)
    [[[x_min, y_min, z_min], [x_min, y_max, z_min], [x_max, y_max, z_min], [x_max, y_min, z_min]],
     [[x_min, y_min, z_max], [x_max, y_min, z_max], [x_max, y_max, z_max], [x_min, y_max, z_max]],
     [[x_min, y_min, z_min], [x_min, y_min, z_max], [x_min, y_max, z_max], [x_min, y_max, z_min]],
     [[x_max, y_min, z_min], [x_max, y_max, z_min], [x_max, y_max, z_max], [x_max, y_min, z_max]],
     [[x_min, y_min, z_min], [x_max, y_min, z_min], [x_max, y_min, z_max], [x_min, y_min, z_max]],
     [[x_min, y_max, z_min], [x_min, y_max, z_max], [x_max, y_max, z_max], [x_max, y_max, z_min]]]
  end

  # A classified 5 x 5 x 3 m Zone box, its Faces 1001 to 1006, holding `extra` as well.
  def zone_box(base, letter, extra)
    specs = [%w[Floor Ground], %w[RoofCeiling Outdoors]] + [%w[Wall Outdoors]] * 4
    faces = box_loops(0, 5, 0, 5, 0, 3).zip(specs).each_with_index.map do |(loop, (type, condition)), index|
      classified = face(base + index + 1, loop)
      FACE_STORE.write(classified, "id" => format("fac_%<letter>s%<number>011d", :letter => letter,
                                                                                 :number => index + 1),
                                   "schema_version" => 1, "face_type" => type, "boundary_condition" => condition,
                                   "assembly_id" => @assembly_id, "user_data" => {}, "extension_data" => {})
      classified
    end
    group = Sketchup::Group.new(base, Sketchup::Entities.new(faces + extra))
    zone = { "id" => "zon_#{letter * 12}", "schema_version" => 1, "name" => "Zone #{letter}",
             "building_segment" => "Main_Building", "level" => "L1", "ground_depth_mm" => 0.0,
             "user_data" => {}, "extension_data" => {} }
    PhComposer::Zones::ZONE_STORE.write(group, zone)
    stamp = PhComposer::Zones::Schema.stamp(zone)
    faces.each { |classified| PhComposer::Zones::STAMP_STORE.write(classified, stamp) }
    group
  end

  def extract(contributors = names)
    PhComposer::Export::Collection.build(@model, :run_id => "run-shading", :contributors => contributors)
  end

  def shades(extraction)
    extraction.document.dig("sections", X::SECTION, "records")
  end

  def query(name)
    API.query(:context => @context, :name => name, :params => {}).fetch("value")
  end

  def preflight
    query(X::PREFLIGHT).fetch("findings")
  end

  def counts(records)
    records.group_by { |record| record.fetch("display_name") }.transform_values(&:length)
  end

  def test_the_reference_exports_eighteen_shades_in_five_components_and_owns_the_golden
    reference
    extraction = extract
    records = shades(extraction)

    assert_empty extraction.findings
    assert_equal EXPECTED, counts(records)
    assert_equal records.length, records.map { |record| record.fetch("id") }.uniq.length
    assert(records.all? { |record| record.keys.sort == %w[boundary display_name holes id] })
    holed = records.find { |record| record.fetch("id") == X.identifier([5000]) }
    assert_equal [4, [4]], [holed.fetch("boundary").length, holed.fetch("holes").map(&:length)]
    assert_in_delta 36.0, holed.dig("boundary", 1, 0), 1e-9
    zone = extraction.document.dig("sections", PhComposer::Zones::ExportProjection::SECTION, "records").first
    assert_equal 6, zone.fetch("face_ids").length, "the overhang and the Fin are not the Room's"
    write_or_compare(FIXTURE, extraction.document)
    write_or_compare(RESULT_FIELDS, X::COMPONENT_FIELDS)
  end

  # What export writes is what shading.list counts live: the same components, Face counts and areas.
  def test_the_export_and_shading_list_agree_on_every_component
    reference
    listed = query("#{SH::FEATURE_ID}.list").fetch("components")
    exported = shades(extract).group_by { |record| record.fetch("display_name") }

    assert_equal EXPECTED, listed.to_h { |row| [row.fetch("display_name"), row.fetch("face_count")] }
    listed.each do |row|
      area = exported.fetch(row.fetch("display_name")).sum do |record|
        PhComposer::FaceGeometry.build(:loops_m => [record.fetch("boundary")] + record.fetch("holes"),
                                       :normal => [0.0, 0.0, 1.0]).area_m2
      end
      assert_in_delta row.fetch("area_m2"), area, 1e-9, row.fetch("display_name")
    end
  end

  # One Face in a component placed three times is three Shades, and a second run gives the same ids.
  def test_identifiers_are_unique_per_placement_and_stable_across_runs
    reference
    first = shades(extract)
    louvres = first.select { |record| record.fetch("display_name") == "Louvre" }.map { |record| record.fetch("id") }

    assert_equal 6, louvres.uniq.length
    assert_equal [4100, 4200, 4300].flat_map { |id| [X.identifier([id, 4001]), X.identifier([id, 4002])] }.sort,
                 louvres.sort
    assert_match(/\Ashd_[0-9a-f]{12}\z/, louvres.first)
    assert_equal first, shades(extract)
  end

  # An instance's own name before its definition's; a Zone's name and " Shading"; a name that reads as a
  # local file path counts as none, so the artifact guard never refuses the export over a Group's name.
  def test_names_follow_the_nearest_named_container
    reference
    @model.entities.to_a.find { |entity| entity.persistent_id == 4200 }.name = "Louvre East"
    @model.entities.to_a.find { |entity| entity.persistent_id == 3000 }.name = "/site/north"

    assert_equal({ "Fin" => 2, "Louvre" => 4, "Louvre East" => 2, "Shading" => 9, "Zone A Shading" => 1 },
                 counts(shades(extract)))
  end

  # A Face classified after its Group was marked stays in the Room and is no Shade; the preflight says so.
  def test_a_face_classified_under_a_marked_group_stays_in_the_room
    reference
    classified = @fin.entities.to_a.first
    FACE_STORE.write(classified, "id" => "fac_FIN000000001", "schema_version" => 1, "face_type" => "Wall",
                                 "boundary_condition" => "Outdoors", "assembly_id" => @assembly_id,
                                 "user_data" => {}, "extension_data" => {})
    stamp = PhComposer::Zones::Schema.stamp(PhComposer::Zones::ZONE_STORE.read(@zone))
    PhComposer::Zones::STAMP_STORE.write(classified, stamp)
    extraction = extract

    assert_equal 1, counts(shades(extraction)).fetch("Fin")
    zone = extraction.document.dig("sections", PhComposer::Zones::ExportProjection::SECTION, "records").first
    assert_includes zone.fetch("face_ids"), "fac_FIN000000001"
    row = preflight.find { |finding| finding.fetch("code") == "shading.classified_inside" }
    assert_equal [false, X.identifier([1000, 1020])], row.values_at("blocks_export", "object_id")
  end

  # A Face that carries the mark itself leaves the envelope even when it is classified: it is a Shade and no
  # Room's.
  def test_a_classified_face_with_its_own_mark_is_a_shade_and_not_the_rooms
    reference
    FACE_STORE.write(@overhang, "id" => "fac_OVERHANG0001", "schema_version" => 1, "face_type" => "Wall",
                                "boundary_condition" => "Outdoors", "assembly_id" => @assembly_id,
                                "user_data" => {}, "extension_data" => {})
    extraction = extract

    assert_equal 1, counts(shades(extraction)).fetch("Zone A Shading")
    zone = extraction.document.dig("sections", PhComposer::Zones::ExportProjection::SECTION, "records").first
    refute_includes zone.fetch("face_ids"), "fac_OVERHANG0001"
  end

  # Two Shading Faces with one path cannot be told apart, so neither becomes a Shade; one note, one preflight row.
  def test_two_faces_at_one_path_are_left_out_with_one_note
    reference
    2.times { @model.entities << mark(face(9001, [[50, 0, 0], [51, 0, 0], [51, 1, 0]])) }
    extraction = extract

    refute_includes shades(extraction).map { |record| record.fetch("id") }, X.identifier([9001])
    assert_equal 18, shades(extraction).length
    assert_equal [["target.ambiguous", X.identifier([9001])]],
                 extraction.findings.map { |row| row.values_at("code", "object_id") }.uniq
    assert_equal [["target.ambiguous", X.identifier([9001]), false]],
                 preflight.map { |row| row.values_at("code", "object_id", "blocks_export") }
  end

  # A Zone made inside a marked Group keeps its Faces; the note now reaches every export's warnings, one
  # per Group however many there are.
  def test_a_zone_inside_a_marked_group_keeps_its_faces_and_each_note_reaches_the_export
    reference
    holders = [6000, 7000].map do |id|
      inner = zone_box(id + 100, id == 6000 ? "B" : "C", [])
      mark(Sketchup::Group.new(id, Sketchup::Entities.new([inner, face(id + 1, [[0, 9, 0], [1, 9, 0], [1, 9, 1]])])))
    end
    holders.each { |holder| @model.entities << holder }
    records = shades(extract)

    assert_equal 20, records.length, "each holder's own loose Face is shading"
    warnings = PhComposer::Export.preflight_warnings(@session).select { |row| row["code"] == "shading.zone_inside" }
    assert_equal [X.identifier([6000]), X.identifier([7000])].sort, warnings.map { |row| row.fetch("object_id") }.sort

    # A Group named like a file location is named in no warning, so the artifact guard passes them all.
    holders.first.name = "/site/north"
    warnings = PhComposer::Export.preflight_warnings(@session)
    assert PhComposer::Export::ArtifactHygiene.validate!("findings" => warnings)
    assert_match(/\AAn unnamed Group/, warnings.find { |row| row["object_id"] == X.identifier([6000]) }["message"])
  end

  # Shading never blocks: a degenerate Face is left out with a note, and an unreadable mark still marks its Face,
  # each with the preflight row of the same code and object id, so the export lists each once.
  def test_a_face_that_cannot_become_a_shade_is_a_note_and_an_unreadable_mark_still_marks
    reference
    sliver = mark(face(8001, [[40, 0, 0], [41, 0, 0], [42, 0, 0]]))
    damaged = face(8002, [[40, 2, 0], [41, 2, 0], [41, 3, 0]])
    damaged.set_attribute(MARK.dictionary, MARK.key, "{not json")
    @model.entities << sliver << damaged
    extraction = extract

    ids = shades(extraction).map { |record| record.fetch("id") }
    refute_includes ids, X.identifier([8001])
    assert_includes ids, X.identifier([8002])
    expected = [["record.unreadable", X.identifier([8002])], ["shading.geometry_invalid", X.identifier([8001])]]
    assert_equal expected, extraction.findings.map { |row| row.values_at("code", "object_id") }.sort
    assert_equal expected, preflight.map { |row| row.values_at("code", "object_id") }.sort
    assert(preflight.none? { |row| row.fetch("blocks_export") })
  end

  # The mark's user_data stays in the Model with one note; an extension envelope follows the left-out rules, as on
  # every entity record, and its preflight row is the same refusal.
  def test_a_marks_metadata_stays_in_the_model
    reference
    loose = @model.entities.to_a.find { |entity| entity.persistent_id == 2001 }
    mark(loose, "schema_version" => 1, "user_data" => { "firm.note" => "kept" })
    extraction = extract

    assert_equal [["export.metadata_omitted", X.identifier([2001])]],
                 extraction.findings.map { |row| row.values_at("code", "object_id") }
    refute_includes JSON.generate(extraction.document), "firm.note"

    mark(loose, "schema_version" => 1, "extension_data" => { "acme.shade" => { "schema_version" => 1 } })
    assert_equal "export.relevance_unknown", assert_raises(PhComposer::Export::Blocked) { extract }.code
    assert_equal [["export.relevance_unknown", X.identifier([2001]), true]],
                 preflight.map { |row| row.values_at("code", "object_id", "blocks_export") }

    # A malformed user_data beside the envelope is noted and never hides it.
    envelope = { "acme.shade" => { "schema_version" => 1 } }
    mark(loose, "schema_version" => 1, "user_data" => [], "extension_data" => envelope)
    assert_equal "export.relevance_unknown", assert_raises(PhComposer::Export::Blocked) { extract }.code
    assert_equal [["export.relevance_unknown", true], ["record.unreadable", false]],
                 preflight.map { |row| row.values_at("code", "blocks_export") }.sort
  end

  def test_a_model_with_no_shading_writes_an_empty_section_and_no_finding
    @model.entities << zone_box(1000, "A", [])
    extraction = extract

    assert_equal [], shades(extraction)
    assert_empty extraction.findings
    assert_empty preflight
  end

  def test_the_report_lists_each_component_and_the_totals_and_is_absent_with_none
    contributor = PhComposer::Registry.current.export_contributors.fetch(X::SECTION)
    rows = [{ "display_name" => "<Fin>", "face_count" => 2, "area_m2" => 4.0 },
            { "display_name" => "Neighbour", "face_count" => 6, "area_m2" => 10.0 }]
    view = PhComposer::Export::ResultView.new({ X::SECTION => { "shading_components" => rows, "shade_count" => 8,
                                                                "area_m2" => 14.0 } }, contributor)
    html = X.report(view, "si").join

    assert_includes html, "<td>&lt;Fin&gt;</td><td>2</td><td>4.00</td>"
    assert_includes html, "8 Shades in 2 shading components, 14.00"
    assert_includes X.report(view, "ip").join, "150.69"
    assert_empty X.report(PhComposer::Export::ResultView.new({}, contributor), "si")
  end
end
