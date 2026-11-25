# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

# The live ducting schedule over a stub Model: the shared walk for Ducting groups and their ducts, Zones' containment
# for the group paths, Mechanical's Ventilators read for which Ventilators serve a Zone, the Ventilators' lengths, the
# used length on Duct Types, and runs.locate. The arithmetic is the pure runs suite's; this proves what the scan hands
# it.
class DuctingScheduleTest < PhComposerTestCase
  include SpaceFixtures

  API = PhComposer::API
  D = PhComposer::Ducting
  STORE = D::Assignment::STORE
  PREFIX = "ph_composer.ducting"

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @next_id = 1000
    @erv1 = create("ph_composer.mechanical.ventilators.create", "name" => "ERV-1")
    @erv2 = create("ph_composer.mechanical.ventilators.create", "name" => "ERV-2")
    @dt1 = create("#{PREFIX}.duct_types.create", "name" => "DT-1")
    @dt2 = create("#{PREFIX}.duct_types.create", "name" => "DT-2", "shape" => "rectangular", "width_mm" => 200.0,
                                                 "height_mm" => 100.0, "insulation_thickness_mm" => 50.8,
                                                 "insulation_conductivity_w_mk" => 0.035,
                                                 "insulation_reflective" => false)
  end

  # The ERV ducting case: DG-1 (600) inside wrapper 20 moved 2 m along x, with one unassigned line beside its ducts,
  # and DG-2 (700) at the root.
  def the_case
    @vertices = {}
    dg1 = line("outdoor_air", @dt1, [[1, 0.5, 2.8], [1, 2, 2.8], [2, 2, 2.8]]) +
          line("exhaust_air", @dt1, [[1.5, 0.5, 2.8], [1.5, 1.5, 2.8], [2.3, 1.5, 2.8]])
    @group = ducting_group(600, "dcg_DG1000000001", @erv1,
                           dg1 + [Sketchup::Edge.new(next_id, point([0, 0, 0]), point([0, 0, 1]))])
    @wrapper = Sketchup::Group.new(20, Sketchup::Entities.new([@group]),
                                   :transformation => Geom::Transformation.translation([2 * INCHES, 0, 0]))
    dg2 = line("outdoor_air", @dt2, [[6, 0.5, 2.8], [6, 3, 2.8]]) +
          line("exhaust_air", @dt2, [[7, 0.5, 2.8], [7, 2, 2.8]], 2)
    @model.entities << @wrapper << ducting_group(700, "dcg_DG2000000002", @erv2, dg2)
    dg1 + dg2
  end

  def line(direction, type_id, points, quantity = 1)
    vertices = points.map { |at| @vertices[at] ||= Sketchup::Vertex.new(point(at)) }
    vertices.each_cons(2).map do |from, to|
      edge = Sketchup::Edge.new(next_id, from, to)
      STORE.write(edge, { "id" => "dce_#{format('%012d', edge.persistent_id)}", "schema_version" => 1,
                          "duct_type_id" => type_id, "direction" => direction, "quantity" => quantity,
                          "user_data" => {}, "extension_data" => {} })
      edge
    end
  end

  def point(at)
    Geom::Point3d.new(*at.map { |value| value * INCHES })
  end

  def ducting_group(persistent_id, id, ventilator_id, children)
    group = Sketchup::Group.new(persistent_id, Sketchup::Entities.new(children))
    D::Group::STORE.write(group, D::Group.new_record(id, ventilator_id))
    group
  end

  def next_id
    @next_id += 1
  end

  # Each Ventilator row's two lengths to a millimetre, by name.
  def lengths(rows)
    rows.to_h do |row|
      [row.fetch("name"), row.values_at("outdoor_air_length_m", "exhaust_air_length_m").map { |value| value.round(3) }]
    end
  end

  # Each Duct Type row's used length to a millimetre, by id, from one of the two Duct Type reads.
  def used(read)
    query(read).fetch("records").to_h { |row| [row.fetch("id"), row.fetch("used_length_m").round(3)] }
  end

  def test_the_schedule_reads_the_case_in_world_metres_with_each_ventilators_lengths_and_used_lengths
    the_case
    result = query("schedule")
    rows = result.fetch("runs").sort_by { |row| row.fetch("ventilator_name") }
    assert_equal [[2.5, 1, 2, "ERV-1"], [1.8, 1, 2, "ERV-1"], [2.5, 1, 1, "ERV-2"], [1.5, 2, 1, "ERV-2"]],
                 rows.map { |row|
                   [row.fetch("length_m").round(3), *row.values_at("quantity", "line_count", "ventilator_name")]
                 }
    assert_equal({ "group_id" => "dcg_DG1000000001", "group_path" => [20, 600], "name" => "" },
                 rows.first.fetch("group"))
    assert(rows.first(2).all? { |row| row.fetch("edge_paths").all? { |path| path[0, 2] == [20, 600] } })
    assert_empty rows.flat_map { |row| row.fetch("findings") }
    assert_equal [4, 0, [], nil], result.values_at("total", "unreadable_total", "unreadable", "next_cursor")
    assert_equal({ "ERV-1" => [2.5, 1.8], "ERV-2" => [2.5, 3.0] }, lengths(result.fetch("ventilators")))
    assert_equal result.fetch("ventilators").map { |row| row.reject { |key, _value| key == "findings" } },
                 query("ventilators").fetch("ventilators")
    assert_equal [{ @dt1 => 4.3, @dt2 => 5.5 }] * 2, [used("duct_types.all"), used("duct_types.list")]

    locate = API.view(:context => @context, :name => "#{PREFIX}.runs.locate",
                      :params => { "edge_paths" => rows.first.fetch("edge_paths") })
    assert_equal ["completed", [20, 600], 2], [locate["status"], *locate["value"].values_at("path", "selected")]
  end

  def test_a_served_ventilator_missing_a_run_is_noted_and_an_unserved_one_is_not
    edges = the_case
    zone = zone_group(100, "A", [space_group(110, space_record("A", :number => "1", :name => "Zone A"),
                                             [volume_group(120, volume_record("A"),
                                                           [floor_face(130, rectangle(10, 10, 5, 5),
                                                                       segment_record("A"))])])])
    @model.entities << zone
    exhaust = edges[2, 2].map { |edge| [edge, STORE.read(edge)] }
    exhaust.each { |edge, _record| edge.delete_attribute(STORE.dictionary) }
    assert_empty query("schedule").fetch("ventilators").flat_map { |row| row.fetch("findings") }, "ERV-1 serves no Zone"
    exhaust.each { |edge, record| STORE.write(edge, record) }
    serve(@erv1)
    assert_empty query("schedule").fetch("ventilators").flat_map { |row| row.fetch("findings") }

    exhaust.each { |edge, _record| edge.delete_attribute(STORE.dictionary) }
    erv1, erv2 = query("schedule").fetch("ventilators").sort_by { |row| row.fetch("name") }
    finding = erv1.fetch("findings").first
    assert_equal [1, "ducting.run_missing", false],
                 [erv1.fetch("findings").length, *finding.values_at("code", "blocks_export")]
    assert_match(/no Exhaust air run/, finding.fetch("message"))
    assert_empty erv2.fetch("findings"), "ERV-2 serves no Zone"
    assert_equal [2.5, 0.0], lengths([erv1]).fetch("ERV-1")
  end

  def test_the_scan_writes_nothing_opens_no_operation_and_reports_unreadable_records_as_rows
    edges = the_case
    edges[0].set_attribute(STORE.dictionary, STORE.key, "{not json")
    STORE.write(edges[1], STORE.read(edges[1]).reject { |key, _value| key == "direction" })
    STORE.write(edges[4], STORE.read(edges[4]).merge("quantity" => D::Assignment::QUANTITY_LIMIT + 1))
    broken = ducting_group(710, "dcg_BROKEN000001", @erv2, line("exhaust_air", @dt2, [[9, 9, 9], [9, 9, 10]]))
    broken.set_attribute(D::Group::STORE.dictionary, D::Group::STORE.key, "[]")
    @model.entities << broken
    revision = @session.revision
    starts = @model.operation_starts.length

    result = query("schedule")
    assert_equal [[20, 600, edges[0].persistent_id], [20, 600, edges[1].persistent_id], [700, edges[4].persistent_id],
                  [710]], result.fetch("unreadable").map { |row| row.fetch("path") }
    assert_equal [["record.unreadable"], 4], [result.fetch("unreadable").map { |row| row.fetch("code") }.uniq,
                                              result.fetch("unreadable_total")]
    assert_equal [revision, starts], [@session.revision, @model.operation_starts.length]
  end

  def test_a_group_a_zone_holds_and_a_pasted_copy_raise_their_findings
    the_case
    copy = Sketchup::Group.new(601, @group.entities)
    D::Group::STORE.write(copy, D::Group::STORE.read(@group))
    @wrapper.entities << copy
    rows = query("schedule").fetch("runs").select { |row| row.fetch("ventilator_id") == @erv1 }
    assert_equal [4, 4], [rows.length, rows.map { |row| row.fetch("identifier") }.uniq.length]
    assert(rows.all? { |row| row.fetch("findings").map { |f| f.fetch("code") } == ["ducting.shared_definition"] })
    assert_equal [5.0, 3.6], lengths(query("ventilators").fetch("ventilators")).fetch("ERV-1")

    held = ducting_group(720, "dcg_INZONE000001", @erv2, line("outdoor_air", @dt2, [[8, 8, 8], [9, 8, 8]]))
    @model.entities << zone_group(100, "B", [held])
    held_rows = query("schedule").fetch("runs").select { |row| row.dig("group", "group_path") == [100, 720] }
    assert_equal [["ducting.group_in_zone"]], held_rows.map { |row| row.fetch("findings").map { |f| f.fetch("code") } }
  end

  def test_locate_refuses_hidden_and_mixed_paths_and_moves_nothing
    the_case
    run = query("schedule").fetch("runs").find { |row| row.fetch("ventilator_id") == @erv1 }
    @wrapper.hidden = true
    hidden = locate(run.fetch("edge_paths"))
    assert_equal %w[refused ducting.hidden], hidden.values_at("status", "code")
    assert_equal [[], []], [Array(@model.active_path), @model.selection.to_a]
    @wrapper.hidden = false
    assert_equal %w[refused params.invalid], locate([run.dig("edge_paths", 0), [700, 1]]).values_at("status", "code")
    loose = @group.entities.to_a.find { |entity| entity.is_a?(Sketchup::Edge) && !STORE.marks?(entity) }
    [[20, 600, loose.persistent_id], [20, 600]].each do |path|
      assert_equal %w[refused target.wrong_kind], locate([path]).values_at("status", "code"), path.inspect
    end
    assert_equal [[], []], [Array(@model.active_path), @model.selection.to_a]
  end

  def test_a_compact_page_counts_and_its_paged_reads_page_runs_details_and_refuse_a_bad_cursor_before_the_walk
    the_case
    compact = query("schedule", "compact" => true, "limit" => 1)
    run = compact.fetch("runs").first
    full = query("schedule").fetch("runs")
    assert_equal [false, full.first.fetch("line_count"), 0, 2, 2, 4],
                 [run.key?("edge_paths"), *run.values_at("edge_count", "index"),
                  *compact.values_at("ventilator_count", "type_count", "total")]
    refute(%w[ventilators types unreadable].any? { |key| compact.key?(key) })
    rest = query("schedule", "compact" => true, "cursor" => compact.fetch("next_cursor"))
    assert_equal [1, 2, 3], rest.fetch("runs").map { |row| row.fetch("index") }

    long = full.find { |row| row.fetch("line_count") == 2 }
    first = query("runs.members", "identifier" => long.fetch("identifier"), "limit" => 1)
    second = query("runs.members", "identifier" => long.fetch("identifier"), "cursor" => first.fetch("next_cursor"))
    members = first.fetch("members") + second.fetch("members")
    assert_equal long.fetch("edge_paths"), members.map { |row| row.fetch("path") }

    page = query("schedule.details", "part" => "ventilators", "limit" => 1)
    more = query("schedule.details", "part" => "ventilators", "cursor" => page.fetch("next_cursor"))
    paged = page.fetch("ventilators") + more.fetch("ventilators")
    assert_equal [@erv1, @erv2].sort, paged.map { |row| row.fetch("ventilator_id") }
    invoke("ph_composer.mechanical.ventilators.update", "id" => @erv1, "values" => { "name" => "E" * 5_000 },
                                                        "expected_values" => {})
    named = query("ventilators").fetch("ventilators").find { |row| row.fetch("ventilator_id") == @erv1 }
    assert_equal [256, ["name"]], [named.fetch("name").length, named.fetch("truncated")]

    # Each read's cursor names its own query, so another read's refuses before the Model is walked.
    foreign = { "schedule" => page.fetch("next_cursor"), "runs.members" => page.fetch("next_cursor"),
                "schedule.details" => compact.fetch("next_cursor") }
    params = { "schedule" => {}, "schedule.details" => { "part" => "ventilators" },
               "runs.members" => { "identifier" => run.fetch("identifier") } }
    PhComposer::LineGroups::Scan.stub(:walk, ->(*) { flunk "walked the Model" }) do
      foreign.each do |name, cursor|
        refused = API.query(:context => @context, :name => "#{PREFIX}.#{name}",
                            :params => params.fetch(name).merge("cursor" => cursor))
        assert_equal %w[refused params.invalid], refused.values_at("status", "code"), name
      end
    end
  end

  def test_a_quantity_past_the_limit_refuses_and_writes_nothing
    edges = the_case
    exhaust = edges[5]
    target = { "reference" => { "group_path" => [700], "entity_path" => [700, exhaust.persistent_id],
                                "entity_id" => STORE.read(exhaust).fetch("id") },
               "expected_values" => D::Assignment.values(STORE.read(exhaust)) }
    result = API.invoke(:context => @context, :name => "#{PREFIX}.ducts.assign",
                        :params => { "targets" => [target], "quantity" => D::Assignment::QUANTITY_LIMIT + 1 },
                        :request => { "sequence" => @sequence += 1, "expected_revision" => @session.revision })
    assert_equal %w[refused params.invalid], result.values_at("status", "code")
    assert_equal 2, STORE.read(exhaust).fetch("quantity")
    target["expected_values"] = D::Assignment.values(STORE.read(exhaust))
    at_limit = API.invoke(:context => @context, :name => "#{PREFIX}.ducts.assign",
                          :params => { "targets" => [target], "quantity" => D::Assignment::QUANTITY_LIMIT },
                          :request => { "sequence" => @sequence += 1, "expected_revision" => @session.revision })
    assert_equal "committed", at_limit["effect"], at_limit.inspect
    exhausts = query("ventilators").fetch("ventilators").map { |row| row.fetch("exhaust_air_length_m") }
    assert_equal 15_001.8, exhausts.sum.round(3)
  end

  private

  def serve(ventilator_id)
    row = API.query(:context => @context, :name => "ph_composer.mechanical.serves.all").dig("value", "zones").first
    result = invoke("ph_composer.mechanical.serves.assign",
                    "zones" => [{ "reference" => row.fetch("reference"), "expected_values" => row.fetch("slots") }],
                    "slot" => "ventilator_id", "item_id" => ventilator_id)
    assert_equal "committed", result["effect"], result.inspect
  end

  def locate(edge_paths)
    API.view(:context => @context, :name => "#{PREFIX}.runs.locate", :params => { "edge_paths" => edge_paths })
  end

  def query(name, params = {})
    result = API.query(:context => @context, :name => "#{PREFIX}.#{name}", :params => params)
    assert_equal "completed", result["status"], result.inspect
    result.fetch("value")
  end

  def create(name, values)
    invoke(name, "values" => values).dig("value", "id")
  end

  def invoke(name, params)
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence += 1, "expected_revision" => @session.revision })
  end
end
