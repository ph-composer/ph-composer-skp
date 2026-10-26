# frozen_string_literal: true

require_relative "test_helper"

# The live schedule over a stub Model: one walk for assigned Edges, Zones' containment and Face reads for
# their paths, and runs.locate. The arithmetic is the pure runs suite's; this proves what the scan hands it.
class ThermalBridgeScheduleTest < PhComposerTestCase
  API = PhComposer::API
  TB = PhComposer::ThermalBridges
  STORE = TB::Assignment::STORE
  FACE_STORE = PhComposer::Zones::Faces::FACE_STORE
  INCHES = 1 / 0.0254

  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?(TB::FEATURE_ID)
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @next_id = 1000
    @parapet = create_type("Parapet", 0.05)
    @balcony = create_type("Balcony", 0.25)
  end

  # Zone A (100) holds a Parapet chain along its roof's south, west and north sides, each Edge on an
  # Outdoors wall; Zone B (200), inside a wrapper (20) moved 5 m along x, holds a Balcony line of quantity 2.
  def reference
    @roof = chain([[5, 0, 3], [0, 0, 3], [0, 4, 3], [5, 4, 3]], @parapet)
    @zone_a = zone("zon_AAAAAAAAAAAA", 100, @roof.flat_map { |edge| [edge] + edge.faces })
    @line = chain([[0, 0, 1.5], [4, 0, 1.5]], @balcony, :quantity => 2).first
    @zone_b = zone("zon_BBBBBBBBBBBB", 200, [@line] + @line.faces)
    @wrapper = Sketchup::Group.new(20, Sketchup::Entities.new([@zone_b]),
                                   :transformation => Geom::Transformation.translation([5 * INCHES, 0, 0]))
    @model.entities << @zone_a
    @model.entities << @wrapper
  end

  def chain(points, type_id, quantity: 1, condition: "Outdoors")
    vertices = points.map { |point| Sketchup::Vertex.new(Geom::Point3d.new(*point.map { |value| value * INCHES })) }
    vertices.each_cons(2).map do |from, to|
      edge = Sketchup::Edge.new(next_id, from, to)
      face = Sketchup::Face.new(next_id, :edges => [edge])
      FACE_STORE.write(face, "id" => "fac_#{format('%012d', face.persistent_id)}", "schema_version" => 1,
                             "face_type" => "Wall", "boundary_condition" => condition)
      tag(edge, type_id, quantity)
    end
  end

  def tag(edge, type_id, quantity = 1)
    STORE.write(edge, "id" => "tbe_#{format('%012d', edge.persistent_id)}", "schema_version" => 1,
                      "thermal_bridge_type_id" => type_id, "quantity" => quantity, "user_data" => {},
                      "extension_data" => {})
    edge
  end

  def next_id
    @next_id += 1
  end

  def test_the_schedule_reads_runs_in_world_metres_with_zones_and_totals
    reference
    result = schedule
    rows = result.fetch("runs").to_h { |row| [row.fetch("display_name"), row] }
    assert_equal ["Balcony 1", "Parapet 1"], rows.keys.sort
    parapet = rows.fetch("Parapet 1")
    assert_in_delta 14.0, parapet.fetch("length_m"), 0.001
    assert_in_delta 0.7, parapet.fetch("heat_loss_w_k"), 0.001
    assert_equal({ "zone_id" => "zon_AAAAAAAAAAAA", "zone_path" => [100], "name" => "Zone 100",
                   "building_segment" => "Building" }, parapet.fetch("zone"))
    assert_equal @roof.map { |edge| [100, edge.persistent_id] }, parapet.fetch("edge_paths")
    balcony = rows.fetch("Balcony 1")
    assert_equal [[5.0, 0.0, 1.5], [9.0, 0.0, 1.5]], balcony.fetch("points_m").map { |point|
      point.map { |v|
        v.round(6)
      }
    }
    assert_in_delta 2.0, balcony.fetch("heat_loss_w_k"), 0.001
    assert_equal [20, 200], balcony.dig("zone", "zone_path")
    assert(result.fetch("runs").all? { |row| row.fetch("findings").empty? })
    assert_in_delta 2.7, result.dig("totals", "heat_loss_w_k"), 0.001
    assert_equal({ "length_m" => "m", "psi_w_mk" => "W/mK", "heat_loss_w_k" => "W/K" }, result.fetch("units"))
  end

  def test_unclassified_faces_outside_edges_shared_storage_and_bad_records_report_without_stopping_the_read
    reference
    FACE_STORE.delete(@line.faces.first)
    loose = tag(Sketchup::Edge.new(5, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(10, 0, 0)), @parapet)
    inside = tag(Sketchup::Edge.new(141, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(10, 0, 0)), @balcony)
    definition = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([inside]))
    @zone_a.entities << Sketchup::ComponentInstance.new(140, definition)
    @zone_a.entities << Sketchup::ComponentInstance.new(142, definition)
    broken = Sketchup::Edge.new(6, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(20, 0, 0))
    broken.set_attribute(STORE.dictionary, STORE.key, "{not json")
    @model.entities << loose
    @model.entities << broken

    result = schedule
    codes = result.fetch("runs").to_h do |row|
      [row.fetch("edge_paths").first, row.fetch("findings").map { |finding| finding.fetch("code") }]
    end
    assert_equal %w[thermal_bridge.no_envelope_face], codes.fetch([20, 200, @line.persistent_id])
    assert_equal [%w[thermal_bridge.no_envelope_face thermal_bridge.shared_definition]] * 2,
                 [codes.fetch([100, 140, 141]), codes.fetch([100, 142, 141])]
    assert_equal [["thermal_bridge.outside_zone", [5]]],
                 result.fetch("edge_findings").map { |finding| finding.values_at("code", "path") }
    assert_equal [[[6], "record.unreadable"]], result.fetch("unreadable").map { |row| row.values_at("path", "code") }
  end

  def test_a_turned_wrapper_and_a_shared_group_read_in_world_metres_and_an_invalid_record_is_unreadable
    reference
    # A quarter turn about z, then 5 m along x: the Balcony line runs along y in the world.
    @wrapper.transformation = Geom::Transformation.new([0.0, 1.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0,
                                                        5 * INCHES, 0.0, 0.0, 1.0])
    # Two Groups placing one definition, as a native copy of a Group leaves them until one is opened.
    storage = Sketchup::Entities.new([tag(Sketchup::Edge.new(301, Geom::Point3d.new(0, 0, 0),
                                                             Geom::Point3d.new(10, 0, 0)), @parapet)])
    @zone_a.entities << Sketchup::Group.new(310, storage)
    @zone_a.entities << Sketchup::Group.new(320, storage)
    STORE.write(@roof.first, STORE.read(@roof.first).merge("quantity" => -1))

    result = schedule
    balcony = result.fetch("runs").find { |row| row.fetch("display_name") == "Balcony 1" }
    assert_equal [[5.0, 0.0, 1.5], [5.0, 4.0, 1.5]],
                 balcony.fetch("points_m").map { |point| point.map { |value| value.round(6) + 0.0 } }.sort
    assert_equal [[[100, @roof.first.persistent_id], "validation.failed"]],
                 result.fetch("unreadable").map { |row| row.values_at("path", "code") }
    placed = result.fetch("runs").select { |row| row.fetch("edge_paths").first[1].between?(310, 320) }
    assert_equal [true, true], placed.map { |row| row.fetch("shared") }
  end

  # More Edges than one Zones read takes (500), in one run: the scan pages its reads and the schedule still
  # reads, with the run's paths whole.
  def test_a_run_longer_than_one_page_of_paths_reads_whole
    long = chain((0..600).map { |step| [step * 0.01, 0, 3] }, @parapet)
    @model.entities << zone("zon_AAAAAAAAAAAA", 100, long.flat_map { |edge| [edge] + edge.faces })
    rows = schedule.fetch("runs")
    assert_equal [[600, false]], rows.map { |row| [row.fetch("edge_paths").length, row.fetch("closed")] }
    assert_in_delta 6.0, rows.first.fetch("length_m"), 0.001
    page = query("schedule.list")
    assert_equal [1, nil], [page.fetch("runs").length, page.fetch("next_cursor")]
    located = command("runs.locate", "edge_paths" => rows.first.fetch("edge_paths"))
    assert_equal ["completed", 600], [located["status"], located.dig("value", "selected")], located.inspect
    assert_equal long.sort_by(&:persistent_id), @model.selection.to_a.sort_by(&:persistent_id)
  end

  def test_the_scan_opens_no_operation_and_writes_nothing
    reference
    revision = @session.revision
    starts = @model.operation_starts.length
    stored = @roof.map { |edge| STORE.read(edge) }
    schedule
    query("schedule.list")
    assert_equal [revision, starts], [@session.revision, @model.operation_starts.length]
    assert_equal stored, @roof.map { |edge| STORE.read(edge) }
  end

  def test_the_bounded_list_pages_runs_and_keeps_totals_over_every_run
    reference
    first = query("schedule.list", "limit" => 1)
    assert_equal [1, 2], [first.fetch("runs").length, first.fetch("total")]
    assert_equal 2, first.dig("totals", "run_count")
    second = query("schedule.list", "limit" => 1, "cursor" => first.fetch("next_cursor"))
    assert_nil second.fetch("next_cursor")
    assert_equal schedule.fetch("runs").map { |row| row.fetch("identifier") },
                 (first.fetch("runs") + second.fetch("runs")).map { |row| row.fetch("identifier") }
  end

  def test_locate_opens_the_runs_container_selects_its_edges_and_refuses_hidden_or_mixed_paths
    reference
    balcony = schedule.fetch("runs").find { |row| row.fetch("display_name") == "Balcony 1" }
    result = command("runs.locate", "edge_paths" => balcony.fetch("edge_paths"))
    assert_equal "completed", result["status"], result.inspect
    assert_equal [20, 200], result.dig("value", "path")
    assert_equal [@line], @model.selection.to_a

    # A hidden ancestor or a hidden tag on the Edge refuses before anything moves.
    @model.active_path = nil
    @model.selection.clear
    @wrapper.hidden = true
    hidden = command("runs.locate", "edge_paths" => balcony.fetch("edge_paths"))
    assert_equal %w[refused thermal_bridge.hidden], hidden.values_at("status", "code")
    assert_equal [[], []], [Array(@model.active_path), @model.selection.to_a]
    @wrapper.hidden = false
    @line.layer = Sketchup::Tag.new("Hidden", false)
    tagged = command("runs.locate", "edge_paths" => balcony.fetch("edge_paths"))
    assert_equal %w[refused thermal_bridge.hidden], tagged.values_at("status", "code")
    assert_equal [[], []], [Array(@model.active_path), @model.selection.to_a]

    mixed = command("runs.locate", "edge_paths" => [[100, @roof.first.persistent_id], [20, 200, @line.persistent_id]])
    assert_equal %w[refused params.invalid], mixed.values_at("status", "code")
    gone = command("runs.locate", "edge_paths" => [[100, 999_999]])
    assert_equal %w[refused target.not_found], gone.values_at("status", "code")
  end

  def schedule
    query("schedule.all")
  end

  def query(name, params = {})
    result = API.query(:context => @context, :name => "#{TB::FEATURE_ID}.#{name}", :params => params)
    assert_equal "completed", result["status"], result.inspect
    result.fetch("value")
  end

  def command(name, params)
    API.view(:context => @context, :name => "#{TB::FEATURE_ID}.#{name}", :params => params)
  end

  def zone(id, persistent_id, children)
    group = Sketchup::Group.new(persistent_id, Sketchup::Entities.new(children))
    PhComposer::Zones::ZONE_STORE.write(group,
                                        "id" => id, "schema_version" => 1, "name" => "Zone #{persistent_id}",
                                        "building_segment" => "Building", "level" => nil, "ground_depth_mm" => 0.0,
                                        "user_data" => {}, "extension_data" => {})
    group
  end

  def create_type(name, psi)
    @sequence += 1
    API.invoke(:context => @context, :name => "#{TB::FEATURE_ID}.types.create",
               :params => { "values" => { "name" => name, "psi_w_mk" => psi } },
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision }).dig("value", "id")
  end
end
