# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/box_zone_fixtures"
require_relative "support/construction_export_fixtures"
require_relative "support/space_fixtures"
require_relative "support/zone_options"

# The ducting export over ACCEPTANCE's reference model and its ERV ducting case: Zones A and B, 3 m boxes in one
# Building Segment, each with its detailed Space; the base case serves A with ERV-1 and B with ERV-2, the shared case
# both with ERV-1. Ducting groups DG-1 (ERV-1) and DG-2 (ERV-2) at the Model root, identity transforms, hold the case's
# six ducts: DG-1's Outdoor air and Exhaust air runs of DT-1 (round), DG-2's Outdoor air run of DT-2 (rectangular) and
# its Exhaust air run of DT-2 at quantity 2. The goldens feed the Python section and the PHX round trip
# (tests/python/test_ducting_sections.py, test_ducting_phx_round_trip.py).
class DuctingExportTest < PhComposerTestCase
  include BoxZoneFixtures
  include ConstructionExportFixtures
  include FixtureFiles
  include SpaceFixtures
  include ZoneOptionsSupport

  API = PhComposer::API
  D = PhComposer::Ducting
  X = D::ExportProjection
  STORE = D::Assignment::STORE
  SERVES = "ph_composer.mechanical.serves"
  VENTILATORS = "ph_composer.mechanical.ventilators"
  FIXTURES = File.join(TESTS_ROOT, "fixtures", "ducting")
  BASE = File.join(FIXTURES, "extraction.json")
  SHARED = File.join(FIXTURES, "shared_extraction.json")
  # The result fields the contributor declares, for the Python section's test to hold its rows to.
  RESULT_FIELDS = File.join(FIXTURES, "result_fields.json")
  INCHES = 1 / 0.0254
  DT1 = "dct_DT1000000001"
  DT2 = "dct_DT2000000002"
  DG1 = "dcg_DG1000000001"
  DG2 = "dcg_DG2000000002"
  TYPES = {
    DT1 => { "name" => "DT-1" },
    DT2 => { "name" => "DT-2", "shape" => "rectangular", "width_mm" => 200.0, "height_mm" => 100.0,
             "insulation_thickness_mm" => 50.8, "insulation_conductivity_w_mk" => 0.035,
             "insulation_reflective" => false }
  }.freeze
  # Each run of the case by name: its group, direction, Duct Type, quantity and points in metres.
  CASE = {
    "DG-1 outdoor" => ["DG-1", "outdoor_air", DT1, 1, [[1, 0.5, 2.8], [1, 2, 2.8], [2, 2, 2.8]]],
    "DG-1 exhaust" => ["DG-1", "exhaust_air", DT1, 1, [[1.5, 0.5, 2.8], [1.5, 1.5, 2.8], [2.3, 1.5, 2.8]]],
    "DG-2 outdoor" => ["DG-2", "outdoor_air", DT2, 1, [[6, 0.5, 2.8], [6, 3, 2.8]]],
    "DG-2 exhaust" => ["DG-2", "exhaust_air", DT2, 2, [[7, 0.5, 2.8], [7, 2, 2.8]]]
  }.freeze

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @assembly_id = seed_export_construction
    @ducts = {}
    TYPES.each { |id, values| duct_type(id, values) }
  end

  # ---------------------------------------------------------------- the records

  def test_the_case_exports_one_record_per_ventilator_in_metres_and_owns_the_goldens
    reference
    base = extract
    erv1, erv2 = by_ventilator(base).values_at(@erv1, @erv2)
    runs = schedule_runs.to_h { |row| [[row.fetch("ventilator_name"), row.fetch("direction")], row] }
    assert_equal [@erv1, @erv1, @erv2, @erv2], [*erv1.values_at("id", "ventilator_id"),
                                                *erv2.values_at("id", "ventilator_id")]
    assert_equal [[2.5, 1.8], [2.5, 3.0]], [erv1, erv2].map { |record|
      record.values_at("supply_length_m", "exhaust_length_m").map { |value| value.round(3) }
    }

    supply, = erv1.fetch("supply")
    assert_equal [runs.fetch(%w[ERV-1 outdoor_air]).fetch("identifier"), "Outdoor air 1", 1, 2],
                 [*supply.values_at("identifier", "display_name", "duct_type"), supply.fetch("segments").length]
    segment = supply.fetch("segments").first
    assert_equal [0.16, nil, nil, 0.0254, 0.04, true, {}],
                 segment.values_at("diameter_m", "width_m", "height_m", "insulation_thickness_m",
                                   "insulation_conductivity", "insulation_reflective", "user_data")
    assert_equal segment.fetch("identifier"), segment.fetch("display_name"), "honeybee-ph's default, never a random one"
    assert_equal [[1.0, 0.5, 2.8], [1.0, 2.0, 2.8]], segment.fetch("points_m").map { |at| at.map { |v| v.round(6) } }
    assert_equal [[runs.fetch(%w[ERV-1 exhaust_air]).fetch("identifier"), 2, 1.8]], erv1.fetch("exhaust").map { |part|
      [part.fetch("identifier"), part.fetch("duct_type"), length(part)]
    }

    rectangular, = erv2.fetch("supply")
    assert_equal [0.16, 0.2, 0.1, 0.0508, 0.035, false],
                 rectangular.dig("segments", 0).values_at("diameter_m", "width_m", "height_m", "insulation_thickness_m",
                                                          "insulation_conductivity", "insulation_reflective")
    assert_quantity_copies(erv2.fetch("exhaust"), runs.fetch(%w[ERV-2 exhaust_air]).fetch("identifier"))

    assert_empty notes(base)
    assert_empty preflight_rows
    write_or_compare(BASE, stable(base.document))
    assert_shared_case
    write_or_compare(RESULT_FIELDS, X::RESULT_FIELDS)
  end

  # ERV-1 serving both Zones: both Ventilators' records are written, ERV-2's going nowhere with a note the preflight
  # gives too.
  def assert_shared_case
    completed(serve(%w[B], @erv1, :replace => true))
    shared = extract
    assert_equal [@erv1, @erv2].sort, ducting(shared).map { |record| record.fetch("ventilator_id") }
    assert_equal [["ducting.ventilator_unexported", @erv2]], notes(shared)
    rows = preflight_rows
    assert_equal [["ducting.ventilator_unexported", @erv2, false]],
                 rows.map { |row| row.values_at("code", "object_id", "blocks_export") }
    assert_equal notes_with_messages(shared), rows.map { |row| row.values_at("code", "object_id", "message") }
    assert_equal({ "ventilator_ids" => [@erv2] }, rows.first.dig("locate", "params"))
    assert_equal [@erv1, @erv1], ventilation(shared).map { |row| row.fetch("item_id") }, "ERV-2 has no pair"
    write_or_compare(SHARED, stable(shared.document))
  end

  # A run of quantity 2 is two elements: the run's identifier and name, then `-2` and "(2 of 2)", segments alike.
  def assert_quantity_copies(elements, identifier)
    assert_equal [[identifier, "Exhaust air 1"], ["#{identifier}-2", "Exhaust air 1 (2 of 2)"]],
                 elements.map { |part| part.values_at("identifier", "display_name") }
    first, second = elements.map { |part| part.fetch("segments").map { |segment| segment.fetch("identifier") } }
    assert_equal first.map { |name| "#{name}-2" }, second
    assert_equal [1.5, 1.5], elements.map { |part| length(part) }
  end

  # Each blocking finding refuses the section, so no canonical pair is written, and the preflight lists it under the
  # same code and section, blocking, with the ducts it locates.
  BLOCKING = {
    "ducting.type_missing" => ->(test) { test.rewrite("DG-1 exhaust", "duct_type_id" => "dct_DELETED00001") },
    "ducting.group_unlinked" => ->(test) { test.relink("DG-2", nil) },
    "ducting.insulation_conductivity_missing" => lambda do |test|
      test.duct_type(DT2, TYPES.fetch(DT2).merge("insulation_conductivity_w_mk" => nil))
    end,
    "ducting.group_in_zone" => ->(test) { test.move_into_zone("DG-1") },
    "record.unreadable" => lambda do |test|
      edge = test.ducts_of("DG-2 outdoor").first
      edge.set_attribute(STORE.dictionary, STORE.key, "{\"id\":\"dce_BROKEN000001\",\"schema_version\":1}")
    end
  }.freeze

  BLOCKING.each do |code, change|
    define_method("test_#{code.tr('.', '_')}_refuses_the_section_and_blocks_the_preflight") do
      reference
      change.call(self)
      error = assert_raises(PhComposer::Export::Blocked) { extract }
      assert_equal code, error.code
      rows = preflight_rows.select { |row| row.fetch("code") == code }
      refute_empty rows, "the preflight lists #{code}"
      assert(rows.all? { |row| row.fetch("blocks_export") && row.fetch("section") == X::SECTION })
      locates = rows.filter_map { |row| row.dig("locate", "params", "edge_paths") }
      refute_empty locates, "a #{code} row locates its ducts"
      objects = rows.map { |row| row.fetch("object_id") }
      if code == "record.unreadable"
        assert_equal [nil], objects.uniq, "an unreadable duct is in no run"
      else
        assert_empty objects - schedule_runs.map { |row| row.fetch("identifier") }, "each row names its run"
        assert_includes rows.map { |row| row.fetch("message") }, error.message, "the export's reason is a row's"
      end
    end
  end

  # ACCEPTANCE's "Delete ERV-2 with null": DG-2 is unlinked, the export refuses, and the preflight's Locate opens DG-2
  # and selects that run's ducts, as piping's group findings do.
  def test_deleting_a_ventilator_with_null_unlinks_its_group_and_the_locate_selects_that_runs_ducts
    reference
    completed(invoke("#{VENTILATORS}.delete", "id" => @erv2, "replacement_id" => nil))
    assert_equal "ducting.group_unlinked", assert_raises(PhComposer::Export::Blocked) { extract }.code
    rows = preflight_rows.select { |row| row.fetch("code") == "ducting.group_unlinked" }
    paths = ["DG-2 outdoor", "DG-2 exhaust"].map { |name| ducts_of(name).map { |edge| [700, edge.persistent_id] } }
    assert_equal paths.sort, rows.map { |row| row.dig("locate", "params", "edge_paths") }.sort
    assert_equal [D::ScheduleRegistration::LOCATE], rows.map { |row| row.dig("locate", "name") }.uniq
  end

  # The warnings the export notes are the preflight's, code, object and message: clearing DG-1's Exhaust air lines
  # leaves ERV-1, which serves Zone A, with no Exhaust air run, and a pasted DG-1 counts both placements.
  def test_the_exports_warnings_are_the_preflights_rows
    reference
    ducts_of("DG-1 exhaust").each { |edge| edge.delete_attribute(STORE.dictionary) }
    extraction = extract
    assert_equal [["ducting.run_missing", @erv1]], notes(extraction)
    assert_equal notes_with_messages(extraction),
                 preflight_rows.map { |row| row.values_at("code", "object_id", "message") }
    assert_equal({ "ventilator_ids" => [@erv1] }, preflight_rows.first.dig("locate", "params"))
    erv1 = by_ventilator(extraction).fetch(@erv1)
    assert_equal [1, 0, 0.0], [erv1.fetch("supply").length, erv1.fetch("exhaust").length, erv1["exhaust_length_m"]]

    copy = Sketchup::Group.new(601, @groups.fetch("DG-1").entities,
                               :transformation => Geom::Transformation.translation([20 * INCHES, 0, 0]))
    D::Group::STORE.write(copy, D::Group::STORE.read(@groups.fetch("DG-1")))
    @model.entities << copy
    extraction = extract
    shared = notes(extraction).select { |code, _id| code == "ducting.shared_definition" }
    refute_empty shared
    assert_equal notes_with_messages(extraction).sort,
                 preflight_rows.map { |row| row.values_at("code", "object_id", "message") }.sort
    erv1 = by_ventilator(extraction).fetch(@erv1)
    assert_equal 2, erv1.fetch("supply").map { |part| part.fetch("identifier") }.uniq.length
    assert_equal 5.0, erv1.fetch("supply_length_m").round(3), "both placements count"
  end

  # A bare Duct Type needs no conductivity; its segments carry honeybee-ph's default, 0.04 W/(m K), never a null.
  def test_a_bare_duct_type_with_no_conductivity_exports_honeybee_phs_default
    reference
    duct_type(DT1, "name" => "DT-1", "insulation_thickness_mm" => 0, "insulation_conductivity_w_mk" => nil)
    erv1 = by_ventilator(extract).fetch(@erv1)
    segments = (erv1.fetch("supply") + erv1.fetch("exhaust")).flat_map { |part| part.fetch("segments") }
    assert_equal [[0.0, 0.04]],
                 segments.map { |part| part.values_at("insulation_thickness_m", "insulation_conductivity") }.uniq
  end

  # A duct's user_data rides on its segment, every copy's; a Ducting group's and a Duct Type's are left out with a
  # note; a reserved key on a duct refuses the section, in the export and the preflight alike.
  def test_a_ducts_user_data_rides_its_segment_and_a_groups_and_a_types_are_left_out
    reference
    rewrite("DG-2 exhaust", "user_data" => { "maker_ref" => "DX-1" })
    D::Group::STORE.write(@groups.fetch("DG-1"),
                          D::Group::STORE.read(@groups.fetch("DG-1")).merge("user_data" => { "tag" => "riser" }))
    duct_type(DT2, TYPES.fetch(DT2), { "sku" => "R-200" })
    extraction = extract
    erv2 = by_ventilator(extraction).fetch(@erv2)
    data = erv2.fetch("exhaust").flat_map { |part| part.fetch("segments") }.map { |part| part.fetch("user_data") }
    assert_equal [{ "maker_ref" => "DX-1" }] * 2, data
    refute data.first.equal?(data.last), "each copy its own map"
    assert_equal [{}], erv2.fetch("supply").flat_map { |part| part.fetch("segments") }.map { |part| part["user_data"] }
    omitted = extraction.findings.select { |row| row.fetch("code") == "export.metadata_omitted" }
    assert_equal [[X::SECTION, DG1], [X::SECTION, DT2]].sort,
                 omitted.map { |row| row.values_at("section", "object_id") }.sort

    rewrite("DG-2 exhaust", "user_data" => { "ph_composer" => { "x" => 1 } })
    assert_equal "export.blocked", assert_raises(PhComposer::Export::Blocked) { extract }.code
    assert_includes preflight_rows.map { |row| row.values_at("code", "blocks_export") }, ["export.blocked", true]
  end

  def test_a_model_with_no_ducts_writes_no_record_and_notes_nothing
    reference(:ducts => false)
    extraction = extract
    assert_equal [[], []], [ducting(extraction), notes(extraction)]
    assert_empty preflight_rows
  end

  def test_the_privacy_allowlist_admits_only_the_declared_rows
    rows = X::RESULT_FIELDS.transform_values { |keys| [keys.to_h { |key| [key, "x"] }] }
    result = { "schema_version" => 1, "run_id" => "r", "state" => "complete",
               "summary" => { "objects" => 1, "unavailable" => 0, "findings" => 0, "publishable" => true },
               "sections" => [], "findings" => [], X::SECTION => rows }
    assert PhComposer::Export::Privacy.validate!(result)
    error = assert_raises(PhComposer::CodedError) do
      PhComposer::Export::Privacy.validate!(result.merge(X::SECTION => rows.merge("elements" => [{ "points" => 1 }])))
    end
    assert_equal "export.privacy_undeclared", error.code
  end

  # ---------------------------------------------------------------- what the cases change

  def duct_type(id, values, user_data = {})
    D::DuctType::KIND.store.write(@model, D::DuctType::DEFAULTS.merge(
      "id" => id, "schema_version" => 1, "notes" => "", "datasheet_links" => [], "source" => { "kind" => "manual" },
      "user_data" => user_data, "extension_data" => {}
    ).merge(values["shape"] == "rectangular" ? {} : D::DuctType::ROUND_DEFAULTS).merge(values).compact)
  end

  # Rewrites every duct of `name`, dropping each value set to nil.
  def rewrite(name, values)
    ducts_of(name).each { |edge| STORE.write(edge, STORE.read(edge).merge(values).compact) }
  end

  def relink(group, ventilator_id)
    entity = @groups.fetch(group)
    D::Group::STORE.write(entity, D::Group::STORE.read(entity).merge("ventilator_id" => ventilator_id))
  end

  def move_into_zone(group)
    box_group("Zone A").entities << @groups.fetch(group)
  end

  def ducts_of(name)
    @ducts.fetch(name)
  end

  private

  def reference(ducts: true)
    @model.entities << box(1000, "A", "Zone A", "Main", [0, 5, 0, 4]) << box(2000, "B", "Zone B", "Main", [6, 10, 0, 4])
    adopt_zone_options
    @erv1, @erv2 = %w[ERV-1 ERV-2].map do |name|
      completed(invoke("#{VENTILATORS}.create", "values" => { "name" => name })).fetch("id")
    end
    completed(serve(%w[A], @erv1))
    completed(serve(%w[B], @erv2))
    return unless ducts

    vertices = {}
    next_id = 5000
    members = Hash.new { |hash, key| hash[key] = [] }
    CASE.each do |name, (group, direction, type, quantity, points)|
      @ducts[name] = points.each_cons(2).map do |from, to|
        ends = [from, to].map { |at| vertices[at] ||= Sketchup::Vertex.new(point(at)) }
        edge = Sketchup::Edge.new(next_id += 1, *ends)
        STORE.write(edge, { "id" => "dce_#{format('%012d', edge.persistent_id)}", "schema_version" => 1,
                            "duct_type_id" => type, "direction" => direction, "quantity" => quantity,
                            "user_data" => {}, "extension_data" => {} })
        members[group] << edge
        edge
      end
    end
    @groups = { "DG-1" => [600, DG1, @erv1], "DG-2" => [700, DG2, @erv2] }.to_h do |name, (persistent_id, id, link)|
      group = Sketchup::Group.new(persistent_id, Sketchup::Entities.new(members.fetch(name)), :name => name)
      D::Group::STORE.write(group, D::Group.new_record(id, link))
      @model.entities << group
      [name, group]
    end
  end

  def point(at)
    Geom::Point3d.new(*at.map { |value| value * INCHES })
  end

  def length(element)
    element.fetch("segments").sum { |part| Math.sqrt(part.fetch("points_m").transpose.sum { |a, b| (b - a)**2 }) }
           .round(3)
  end

  def serve(letters, item, replace: nil)
    params = { "zones" => letters.map { |letter| target(letter) }, "slot" => "ventilator_id", "item_id" => item }
    params["replace"] = replace unless replace.nil?
    invoke("#{SERVES}.assign", params)
  end

  def target(letter)
    row = query("#{SERVES}.all").fetch("zones").find { |zone| zone.fetch("zone_id") == "zon_#{letter * 12}" }
    { "reference" => row.fetch("reference"), "expected_values" => row.fetch("slots") }
  end

  def extract
    PhComposer::Export::Collection.build(@model, :run_id => "ducting-export")
  end

  def ducting(extraction)
    extraction.document.dig("sections", X::SECTION, "records")
  end

  def by_ventilator(extraction)
    ducting(extraction).to_h { |record| [record.fetch("ventilator_id"), record] }
  end

  def ventilation(extraction)
    extraction.document.dig("sections", PhComposer::Mechanical::VentilationExport::SECTION, "records")
  end

  # This section's notes, as `[code, object_id]`.
  def notes(extraction)
    notes_with_messages(extraction).map { |code, id, _message| [code, id] }
  end

  def notes_with_messages(extraction)
    extraction.findings.select { |row| row.fetch("section") == X::SECTION && row.fetch("code").start_with?("ducting.") }
              .map { |row| row.values_at("code", "object_id", "message") }
  end

  def preflight_rows
    completed(API.query(:context => @context, :name => X::PREFLIGHT, :params => {})).fetch("findings")
  end

  def schedule_runs
    query("ph_composer.ducting.schedule").fetch("runs")
  end

  # The document with the ids each run mints renumbered by name: Building Segments and Ventilators.
  def stable(document)
    segments = query("ph_composer.zones.options.all").fetch("building_segments").map { |row| row.fetch("id") }
    fixed = (segments + [@erv1, @erv2]).each_with_index.to_h do |id, index|
      [id, format("#{id[0, 3]}_FIXED%<number>07d", :number => index + 1)]
    end
    pattern = /(?<![A-Za-z0-9])(?:bsg|vnt)_[A-Za-z0-9]{12}(?![A-Za-z0-9])/
    stable = JSON.parse(JSON.generate(document).gsub(pattern) { |id| fixed.fetch(id, id) })
    stable.fetch("sections").each_value { |section| section.fetch("records").sort_by! { |row| row.fetch("id").to_s } }
    stable
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
