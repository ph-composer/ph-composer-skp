# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/construction_export_fixtures"

# The thermal-bridge export section and its preflight over ACCEPTANCE's synthetic reference model: two boxes
# whose Faces share their Edges, the five types and the five runs. The extraction this writes is the one the
# Python section's tests translate (tests/fixtures/thermal_bridges/extraction.json).
class ThermalBridgeExportTest < PhComposerTestCase
  include ConstructionExportFixtures
  include FixtureFiles

  API = PhComposer::API
  TB = PhComposer::ThermalBridges
  X = TB::ExportProjection
  STORE = TB::Assignment::STORE
  FACE_STORE = PhComposer::Zones::Faces::FACE_STORE
  FIXTURE = File.join(TESTS_ROOT, "fixtures", "thermal_bridges", "extraction.json")
  # The result fields the contributor declares, for the Python section's test to hold its rows to.
  RESULT_FIELDS = File.join(TESTS_ROOT, "fixtures", "thermal_bridges", "result_fields.json")
  INCHES = 1 / 0.0254
  PARAPET = "tbt_PARAPET00001"
  SLAB_EDGE = "tbt_SLABEDGE0001"
  FOOTING = "tbt_FOOTING00001"
  BALCONY = "tbt_BALCONY00001"
  DRAFT = "tbt_DRAFT0000001"
  TYPES = { PARAPET => ["Parapet", 0.05, "15-Ambient"], SLAB_EDGE => ["Slab edge", 0.12, "16-Perimeter"],
            FOOTING => ["Footing", -0.02, "17-FS/BC"], BALCONY => ["Balcony", 0.25, "15-Ambient"],
            DRAFT => ["Draft", nil, "15-Ambient"] }.freeze

  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?(TB::FEATURE_ID)
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @assembly_id = seed_export_construction
    @edges = {}
    TYPES.each do |id, (name, psi, group)|
      TB::Type::KIND.store.write(@model, "id" => id, "schema_version" => 1, "name" => name, "notes" => "",
                                         "datasheet_links" => [], "source" => { "kind" => "manual" },
                                         "psi_w_mk" => psi, "group" => group)
    end
  end

  def names
    [PhComposer::Zones::Faces::ExportProjection::SECTION, PhComposer::Zones::ExportProjection::SECTION,
     PhComposer::Assemblies::ExportProjection::SECTION, PhComposer::Assemblies::SourceReport::SECTION,
     PhComposer::Spaces::ExportProjection::SECTION, X::SECTION]
  end

  # ACCEPTANCE's reference: Zone A spans x 0 to 5 m and Zone B x 5 to 9 m, each 4 m deep and 3 m high, each
  # holding its own Edges, and the five runs assigned. The Balcony line crosses Zone B's south wall.
  def reference
    @zone_a = box(1000, 0, 5, "A")
    @zone_b = box(2000, 5, 9, "B", :balcony => true)
    @model.entities << @zone_a << @zone_b
    assign("A", PARAPET, [[5, 0, 3], [0, 0, 3], [0, 4, 3], [5, 4, 3]])
    assign("B", PARAPET, [[5, 0, 3], [9, 0, 3], [9, 4, 3], [5, 4, 3]])
    assign("A", SLAB_EDGE, [[5, 0, 0], [0, 0, 0], [0, 4, 0], [5, 4, 0]])
    assign("B", FOOTING, [[5, 0, 0], [9, 0, 0], [9, 4, 0], [5, 4, 0]])
    assign("B", BALCONY, [[5, 0, 1.5], [9, 0, 1.5]], :quantity => 2)
  end

  def box(base, x_min, x_max, letter, balcony: false)
    corners = [x_min, x_max].product([0, 4], [0, 3]).to_h do |x, y, z|
      [[x, y, z], Sketchup::Vertex.new(point_at([x, y, z]))]
    end
    next_id = base + 100
    edge = lambda do |from, to|
      @edges[[letter, [from, to].sort]] ||= Sketchup::Edge.new(next_id += 1, corners.fetch(from), corners.fetch(to))
    end
    floor = [[x_min, 0, 0], [x_min, 4, 0], [x_max, 4, 0], [x_max, 0, 0]]
    roof = [[x_min, 0, 3], [x_max, 0, 3], [x_max, 4, 3], [x_min, 4, 3]]
    south = [[x_min, 0, 0], [x_max, 0, 0], [x_max, 0, 3], [x_min, 0, 3]]
    walls = [[[x_min, 0, 0], [x_min, 0, 3], [x_min, 4, 3], [x_min, 4, 0]],
             [[x_max, 0, 0], [x_max, 4, 0], [x_max, 4, 3], [x_max, 0, 3]], south,
             [[x_min, 4, 0], [x_min, 4, 3], [x_max, 4, 3], [x_max, 4, 0]]]
    specs = [["Floor", "Ground", floor], ["RoofCeiling", "Outdoors", roof]] +
            walls.map { |loop| ["Wall", "Outdoors", loop] }
    faces = specs.each_with_index.map do |(face_type, condition, loop), index|
      edges = loop.zip(loop.rotate).map { |from, to| edge.call(from, to) }
      edges << line(letter, [x_min, 0, 1.5], [x_max, 0, 1.5], next_id += 1) if balcony && loop == south
      points = loop.map { |point| point_at(point) }
      face = Sketchup::Face.new(base + index + 1, {}, :points => points, :edges => edges)
      FACE_STORE.write(face, "id" => format("fac_%<letter>s%<number>011d", :letter => letter, :number => index + 1),
                             "schema_version" => 1, "face_type" => face_type, "boundary_condition" => condition,
                             "assembly_id" => @assembly_id, "user_data" => {}, "extension_data" => {})
      face
    end
    edges = @edges.select { |key, _| key[0] == letter }.values
    group = Sketchup::Group.new(base, Sketchup::Entities.new(faces + edges))
    zone = { "id" => "zon_#{letter * 12}", "schema_version" => 1, "name" => "Zone #{letter}",
             "building_segment" => "Main Building", "level" => "L1", "ground_depth_mm" => 0.0,
             "user_data" => {}, "extension_data" => {} }
    PhComposer::Zones::ZONE_STORE.write(group, zone)
    stamp = PhComposer::Zones::Schema.stamp(zone)
    faces.each { |face| PhComposer::Zones::STAMP_STORE.write(face, stamp) }
    group
  end

  # A loose Edge in the Zone `letter`, by itself or bounding a Face, kept for `assign`.
  def line(letter, from, to, persistent_id)
    @edges[[letter, [from, to].sort]] = Sketchup::Edge.new(persistent_id, point_at(from), point_at(to))
  end

  def point_at(point)
    Geom::Point3d.new(*point.map { |value| value * INCHES })
  end

  def assign(letter, type_id, points, quantity: 1)
    points.each_cons(2) do |from, to|
      edge = @edges.fetch([letter, [from, to].sort])
      STORE.write(edge, "id" => "tbe_#{format('%012d', edge.persistent_id)}", "schema_version" => 1,
                        "thermal_bridge_type_id" => type_id, "quantity" => quantity, "user_data" => {},
                        "extension_data" => {})
    end
  end

  def extract
    PhComposer::Export::Collection.build(@model, :run_id => "run-thermal-bridges", :contributors => names)
  end

  def runs(extraction)
    extraction.document.dig("sections", X::SECTION, "records")
  end

  def length(record)
    record.fetch("points_m").each_cons(2).sum { |a, b| TB::Runs::Chains.distance(a, b) }
  end

  def query(name)
    API.query(:context => @context, :name => name, :params => {}).fetch("value")
  end

  def test_the_reference_exports_five_runs_by_the_hand_calculation_and_owns_the_golden
    reference
    extraction = extract
    records = runs(extraction).to_h { |record| [record.fetch("display_name"), record] }

    assert_empty extraction.findings, "an unused Draft type with no psi-value does not block or warn"
    expected = { "Parapet 1" => [14.0, 4, "zon_AAAAAAAAAAAA"], "Parapet 2" => [12.0, 4, "zon_BBBBBBBBBBBB"],
                 "Slab edge 1" => [14.0, 4, "zon_AAAAAAAAAAAA"], "Footing 1" => [12.0, 4, "zon_BBBBBBBBBBBB"],
                 "Balcony 1" => [4.0, 2, "zon_BBBBBBBBBBBB"] }
    assert_equal expected.keys.sort, records.keys.sort
    expected.each do |name, (metres, points, zone)|
      record = records.fetch(name)
      assert_in_delta metres, length(record), 0.001, name
      assert_equal [points, zone, false], [record.fetch("points_m").length, record.fetch("zone_id"), record["closed"]]
    end
    assert_equal [-0.02, "17-FS/BC", "Footing"], records.fetch("Footing 1").values_at("psi_w_mk", "group", "type_name")
    assert_equal 2, records.fetch("Balcony 1").fetch("quantity")
    write_or_compare(FIXTURE, extraction.document)
    write_or_compare(RESULT_FIELDS, X::RUN_FIELDS)
  end

  def test_the_export_and_the_schedule_build_the_same_runs_from_one_model
    reference
    exported = runs(extract).to_h { |record| [record.fetch("id"), record] }
    scheduled = query("#{TB::FEATURE_ID}.schedule.all").fetch("runs").to_h { |row| [row.fetch("identifier"), row] }

    assert_equal scheduled.keys.sort, exported.keys.sort
    scheduled.each do |id, row|
      record = exported.fetch(id)
      assert_equal row.values_at("display_name", "type_id", "quantity", "closed", "points_m"),
                   record.values_at("display_name", "type_id", "quantity", "closed", "points_m")
      assert_equal row.dig("zone", "zone_id"), record.fetch("zone_id")
    end
  end

  def test_only_tagged_edges_leave_and_one_outside_every_zone_is_left_out_with_its_note
    reference
    loose = Sketchup::Edge.new(9001, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(10 * INCHES, 0, 0))
    STORE.write(loose, "id" => "tbe_LOOSE0000001", "schema_version" => 1, "thermal_bridge_type_id" => BALCONY,
                       "quantity" => 1, "user_data" => {}, "extension_data" => {})
    @model.entities << loose << Sketchup::Edge.new(9002, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(1, 0, 0))
    extraction = extract

    assert_equal 5, runs(extraction).length
    assert_equal [["thermal_bridge.outside_zone", X::SECTION, "tbe_LOOSE0000001"]],
                 extraction.findings.map { |row| row.values_at("code", "section", "object_id") }
    preflight = query(X::PREFLIGHT).fetch("findings")
    row = preflight.find { |finding| finding["code"] == "thermal_bridge.outside_zone" }
    assert_equal [false, "tbe_LOOSE0000001", { "edge_paths" => [[9001]] }],
                 [row.fetch("blocks_export"), row.fetch("object_id"), row.dig("locate", "params")]
    assert_equal TB::ScheduleRegistration::LOCATE, row.dig("locate", "name")
  end

  def test_a_missing_psi_value_or_type_blocks_the_section_and_its_preflight
    reference
    TB::Type::KIND.store.write(@model, "id" => PARAPET, "schema_version" => 1, "name" => "Parapet", "notes" => "",
                                       "datasheet_links" => [], "source" => { "kind" => "manual" },
                                       "psi_w_mk" => nil, "group" => "15-Ambient")
    error = assert_raises(PhComposer::Export::Blocked) { extract }
    assert_equal "thermal_bridge.psi_missing", error.code
    blocking = query(X::PREFLIGHT).fetch("findings").select { |row| row["blocks_export"] }
    assert_equal %w[thermal_bridge.psi_missing] * 2, blocking.map { |row| row.fetch("code") }

    TB::Type::KIND.store.delete(@model, PARAPET)
    error = assert_raises(PhComposer::Export::Blocked) { extract }
    assert_equal "thermal_bridge.type_missing", error.code
  end

  def test_an_invalid_or_unreadable_assignment_blocks_the_section_and_its_preflight
    reference
    edge = @edges.fetch(["A", [[0, 0, 3], [5, 0, 3]]])
    STORE.write(edge, STORE.read(edge).merge("quantity" => 0))
    assert_equal "validation.failed", assert_raises(PhComposer::Export::Blocked) { extract }.code
    edge.set_attribute(STORE.dictionary, STORE.key, "{not json")
    assert_equal "record.unreadable", assert_raises(PhComposer::Export::Blocked) { extract }.code
    row = query(X::PREFLIGHT).fetch("findings").find { |finding| finding["blocks_export"] }
    assert_equal ["record.unreadable", { "edge_paths" => [[1000, edge.persistent_id]] }],
                 [row.fetch("code"), row.dig("locate", "params")]
  end

  # Windows' outlines in as many pages as it takes; a Windows read that refuses skips the perimeter check with a
  # non-blocking row instead of replacing the thermal-bridge findings.
  def test_the_preflight_reads_every_outline_page_and_survives_a_windows_refusal
    pages = { nil => { "units" => [{ "outline_m" => [[0, 0, 0]] }], "next_cursor" => "c2" },
              "c2" => { "units" => [{ "outline_m" => [[1, 0, 0]] }], "next_cursor" => nil } }
    paged = Object.new
    paged.define_singleton_method(:query) { |_name, params| pages.fetch(params["cursor"]) }
    assert_equal [[[[0, 0, 0]], [[1, 0, 0]]], nil], X.outlines(paged)

    refusing = Object.new
    refusing.define_singleton_method(:query) { |*| raise PhComposer::CodedError.new("record.unreadable", "Bad Type.") }
    outlines, row = X.outlines(refusing)
    assert_equal [[], "record.unreadable", false], [outlines, row.fetch("code"), row.fetch("blocks_export")]
  end

  def test_warnings_are_notes_beside_the_runs_they_name_and_the_runs_still_export
    reference
    @zone_a.entities << line("A", [1, 1, 1], [2, 1, 1], 9100)
    assign("A", BALCONY, [[1, 1, 1], [2, 1, 1]])
    assign("B", PARAPET, [[5, 0, 3], [5, 4, 3]])
    assign("A", PARAPET, [[5, 0, 3], [5, 4, 3]])
    extraction = extract

    codes = extraction.findings.map { |row| row.fetch("code") }.sort
    assert_equal %w[thermal_bridge.counted_twice thermal_bridge.counted_twice thermal_bridge.no_envelope_face], codes
    assert_equal 6, runs(extraction).length
    assert(extraction.findings.all? { |row| row.fetch("object_id").start_with?("tb_") })
    preflight = query(X::PREFLIGHT).fetch("findings")
    assert_equal codes, preflight.map { |row| row.fetch("code") }.sort
    assert(preflight.none? { |row| row.fetch("blocks_export") })
  end

  def test_the_metadata_guard_admits_the_declared_type_id_and_refuses_an_undeclared_key
    declared = PhComposer::Export::Privacy.user_data_keys(PhComposer::Registry.current)
    assert_includes declared, "ph_composer.thermal_bridge_type_id"
    owned = { "thermal_bridge_type_id" => PARAPET }
    bridge = { "type" => "PhThermalBridge", "user_data" => { "ph_composer" => owned } }
    assert PhComposer::Export::HbjsonMetadata.validate!(JSON.generate(bridge), declared)
    bridge["user_data"]["ph_composer"]["thermal_bridge_note"] = "x"
    error = assert_raises(PhComposer::CodedError) do
      PhComposer::Export::HbjsonMetadata.validate!(JSON.generate(bridge), declared)
    end
    assert_equal "export.privacy_undeclared", error.code
  end

  def test_the_report_totals_the_exported_runs_by_type_and_group
    rows = [
      { "identifier" => "tb_1", "display_name" => "Parapet 1", "zone_id" => "zon_A", "type_id" => PARAPET,
        "type_name" => "<Parapet>", "group" => "15-Ambient", "psi_w_mk" => 0.05, "quantity" => 1.0,
        "length_m" => 14.0, "heat_loss_w_k" => 0.7 },
      { "identifier" => "tb_2", "display_name" => "Parapet 2", "zone_id" => "zon_B", "type_id" => PARAPET,
        "type_name" => "<Parapet>", "group" => "15-Ambient", "psi_w_mk" => 0.05, "quantity" => 1.0,
        "length_m" => 12.0, "heat_loss_w_k" => 0.6 },
      { "identifier" => "tb_3", "display_name" => "Footing 1", "zone_id" => "zon_B", "type_id" => FOOTING,
        "type_name" => "Footing", "group" => "17-FS/BC", "psi_w_mk" => -0.02, "quantity" => 1.0,
        "length_m" => 12.0, "heat_loss_w_k" => -0.24 }
    ]
    contributor = PhComposer::Registry.current.export_contributors.fetch(X::SECTION)
    view = PhComposer::Export::ResultView.new({ X::SECTION => { "thermal_bridge_runs" => rows } }, contributor)
    html = X.report(view, "si").join

    assert_includes html, "<td>&lt;Parapet&gt;</td><td>Ambient</td><td>2</td><td>26.000</td><td>1.300</td>"
    assert_includes html, "<td>Basement floor</td><td>-0.240</td>"
    assert_includes html, "<td>Perimeter</td><td>0.000</td>"
    assert_includes X.report(view, "ip").join, "<td>85.302</td><td>2.464</td>"
    assert_empty X.report(PhComposer::Export::ResultView.new({}, contributor), "si")
  end
end
