# frozen_string_literal: true

require_relative "test_helper"

# The run builder, the schedule and its findings over detached facts: pure Ruby, no Model. The reference
# facts are ACCEPTANCE's synthetic reference model, and its hand calculation is the expected schedule.
class ThermalBridgeRunsTest < Minitest::Test
  RUNS = PhComposer::ThermalBridges::Runs
  ZONE_A = { "zone_id" => "zon_AAAAAAAAAAAA", "zone_path" => [100], "name" => "Zone A",
             "building_segment" => "Segment" }.freeze
  ZONE_B = { "zone_id" => "zon_BBBBBBBBBBBB", "zone_path" => [200], "name" => "Zone B",
             "building_segment" => "Segment" }.freeze
  TYPES = {
    "tbt_PARAPET00001" => { "name" => "Parapet", "psi_w_mk" => 0.05, "group" => "15-Ambient" },
    "tbt_SLABEDGE0001" => { "name" => "Slab edge", "psi_w_mk" => 0.12, "group" => "16-Perimeter" },
    "tbt_FOOTING00001" => { "name" => "Footing", "psi_w_mk" => -0.02, "group" => "17-FS/BC" },
    "tbt_BALCONY00001" => { "name" => "Balcony", "psi_w_mk" => 0.25, "group" => "15-Ambient" },
    "tbt_DRAFT0000001" => { "name" => "Draft", "psi_w_mk" => nil, "group" => "15-Ambient" }
  }.freeze
  PARAPET = "tbt_PARAPET00001"
  OUTDOOR = [{ "face_type" => "Wall", "boundary_condition" => "Outdoors" }] * 2
  SURFACE = { "face_type" => "Wall", "boundary_condition" => "Surface" }.freeze

  def setup
    @vertices = {}
    @next_id = 1000
  end

  # One fact from world points in metres. Vertex ids are minted per container from the point, as SketchUp
  # merges coincident endpoints inside one collection; a `vertex_ids:` override stands in for a component
  # whose placements share ids.
  def fact(zone, type, from, to, container: zone.fetch("zone_path"), quantity: 1, faces: OUTDOOR, shared: false,
           vertex_ids: nil)
    @next_id += 1
    ids = vertex_ids || [from, to].map { |point| @vertices[[container, point]] ||= (@next_id += 1) }
    RUNS::Fact.new(:path => container + [@next_id], :zone => zone, :reason => nil, :type_id => type,
                   :quantity => quantity, :points_m => [from, to], :vertex_ids => ids, :faces => faces,
                   :shared => shared)
  end

  def chain(zone, type, points, **options)
    points.each_cons(2).map { |from, to| fact(zone, type, from, to, **options) }
  end

  def reference
    chain(ZONE_A, PARAPET, [[5, 0, 3], [0, 0, 3], [0, 4, 3], [5, 4, 3]]) +
      chain(ZONE_B, PARAPET, [[5, 0, 3], [9, 0, 3], [9, 4, 3], [5, 4, 3]]) +
      chain(ZONE_A, "tbt_SLABEDGE0001", [[5, 0, 0], [0, 0, 0], [0, 4, 0], [5, 4, 0]]) +
      chain(ZONE_B, "tbt_FOOTING00001", [[5, 0, 0], [9, 0, 0], [9, 4, 0], [5, 4, 0]]) +
      [fact(ZONE_B, "tbt_BALCONY00001", [5, 0, 1.5], [9, 0, 1.5], :quantity => 2)]
  end

  def schedule(facts)
    RUNS::Schedule.call(facts, :types => TYPES)
  end

  def build(facts)
    RUNS::Chains.build(facts, :type_names => { PARAPET => "Parapet" })
  end

  def test_a_u_is_one_open_run_a_square_one_closed_run_and_a_t_three_runs
    u = build(chain(ZONE_A, PARAPET, [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]]))
    assert_equal [[false, 4]], u.map { |run| [run.closed, run.points_m.length] }

    square = build(chain(ZONE_A, PARAPET, [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0], [0, 0, 0]]))
    assert_equal [[true, 5]], square.map { |run| [run.closed, run.points_m.length] }
    assert_equal square.first.points_m.first, square.first.points_m.last
    assert_in_delta 4.0, square.first.length_m, 1e-9

    t = build([fact(ZONE_A, PARAPET, [0, 0, 0], [1, 0, 0]), fact(ZONE_A, PARAPET, [1, 0, 0], [2, 0, 0]),
               fact(ZONE_A, PARAPET, [1, 0, 0], [1, 1, 0])])
    assert_equal [2, 2, 2], t.map { |run| run.points_m.length }
  end

  def test_edges_join_by_vertex_within_one_container_and_never_across_containers
    joined = build(chain(ZONE_A, PARAPET, [[0, 0, 0], [1, 0, 0], [2, 0, 0]]))
    assert_equal 1, joined.length

    nested = [fact(ZONE_A, PARAPET, [0, 0, 0], [1, 0, 0]),
              fact(ZONE_A, PARAPET, [1, 0, 0], [2, 0, 0], :container => [100, 300])]
    assert_equal 2, build(nested).length

    # Two placements of one component in one Zone: the same vertex ids, the same points, two containers.
    placed = [140, 141].map do |placement|
      fact(ZONE_A, PARAPET, [0, 0, 1.5], [4, 0, 1.5], :container => [100, placement], :vertex_ids => [7, 8])
    end
    runs = build(placed)
    assert_equal 2, runs.length
    assert_equal 2, runs.map(&:identifier).uniq.length
  end

  def test_two_quantities_on_one_chain_are_two_runs
    facts = [fact(ZONE_A, PARAPET, [0, 0, 0], [1, 0, 0]), fact(ZONE_A, PARAPET, [1, 0, 0], [2, 0, 0], :quantity => 2)]
    assert_equal [1, 2], build(facts).map(&:quantity).sort
  end

  def test_the_reference_schedule_equals_the_hand_calculation
    result = schedule(reference)
    runs = result.fetch("runs").to_h { |row| [row.fetch("display_name"), row] }
    expected = { "Parapet 1" => [14.0, 1, 0.7, 4], "Parapet 2" => [12.0, 1, 0.6, 4],
                 "Slab edge 1" => [14.0, 1, 1.68, 4], "Footing 1" => [12.0, 1, -0.24, 4],
                 "Balcony 1" => [4.0, 2, 2.0, 2] }
    assert_equal expected.keys.sort, runs.keys.sort
    expected.each do |name, (length, quantity, loss, points)|
      row = runs.fetch(name)
      assert_in_delta length, row.fetch("length_m"), 0.001, name
      assert_in_delta loss, row.fetch("heat_loss_w_k"), 0.001, name
      shape = [row.fetch("quantity"), row.fetch("points_m").length, row.fetch("closed")]
      assert_equal [quantity, points, false], shape, name
    end
    assert_equal "Zone A", runs.fetch("Parapet 1").dig("zone", "name")

    totals = result.fetch("totals")
    by_type = totals.fetch("by_type").to_h { |row|
      [row.fetch("type_name"), row.values_at("length_m", "heat_loss_w_k")]
    }
    { "Parapet" => [26.0, 1.3], "Slab edge" => [14.0, 1.68], "Footing" => [12.0, -0.24],
      "Balcony" => [4.0, 2.0] }.each do |name, (length, loss)|
      assert_in_delta length, by_type.fetch(name).first, 0.001, name
      assert_in_delta loss, by_type.fetch(name).last, 0.001, name
    end
    by_group = totals.fetch("by_group").to_h { |row| row.values_at("group", "heat_loss_w_k") }
    { "15-Ambient" => 3.3, "16-Perimeter" => 1.68, "17-FS/BC" => -0.24 }.each do |group, loss|
      assert_in_delta loss, by_group.fetch(group), 0.001, group
    end
    assert_equal 5, totals.fetch("run_count")
    assert_in_delta 4.74, totals.fetch("heat_loss_w_k"), 0.001
    assert(result.fetch("runs").all? { |row| row.fetch("findings").empty? })
  end

  def test_names_and_identifiers_are_deterministic_and_change_only_with_geometry
    first = schedule(reference).fetch("runs").map { |row| row.values_at("display_name", "identifier", "points_m") }
    setup
    again = schedule(reference.reverse).fetch("runs").map { |row|
      row.values_at("display_name", "identifier", "points_m")
    }
    assert_equal first, again
    assert(first.all? { |_name, id, _points| id.match?(/\Atb_[0-9a-f]{16}\z/) })

    setup
    moved = reference
    balcony = moved.pop
    moved << fact(ZONE_B, "tbt_BALCONY00001", [5, 0, 1.6], [9, 0, 1.6], :quantity => balcony.quantity)
    ids = schedule(moved).fetch("runs").to_h { |row| row.values_at("display_name", "identifier") }
    assert_equal first.to_h { |name, id, _| [name, id] }.reject { |name, _| name == "Balcony 1" },
                 ids.reject { |name, _| name == "Balcony 1" }
    refute_equal first.to_h { |name, id, _| [name, id] }.fetch("Balcony 1"), ids.fetch("Balcony 1")
  end

  # ACCEPTANCE's case: each roof Edge at x = 5 m bounds its Zone's Outdoors roof as well as the shared wall,
  # so it is counted twice but is no interior junction, which needs every Zone Face interior.
  def test_closing_the_shared_wall_makes_closed_runs_counted_twice
    shared_wall = [{ "face_type" => "RoofCeiling", "boundary_condition" => "Outdoors" }, SURFACE]
    facts = reference + [fact(ZONE_A, PARAPET, [5, 4, 3], [5, 0, 3], :faces => shared_wall),
                         fact(ZONE_B, PARAPET, [5, 0, 3], [5, 4, 3], :faces => shared_wall)]
    runs = schedule(facts).fetch("runs").to_h { |row| [row.fetch("display_name"), row] }
    assert_equal [true, true], runs.values_at("Parapet 1", "Parapet 2").map { |row| row.fetch("closed") }
    assert_in_delta 18.0, runs.fetch("Parapet 1").fetch("length_m"), 0.001
    assert_in_delta 16.0, runs.fetch("Parapet 2").fetch("length_m"), 0.001
    %w[Parapet\ 1 Parapet\ 2].each do |name|
      findings = runs.fetch(name).fetch("findings")
      assert_equal %w[thermal_bridge.counted_twice], findings.map { |finding| finding.fetch("code") }, name
      assert_equal 1, findings.first.dig("locate", "edge_paths").length
    end
    others = runs.reject { |name, _| name.start_with?("Parapet") }
    assert(others.values.all? { |row| row.fetch("findings").empty? })
  end

  def test_each_finding_fires_on_its_case_and_no_other
    cases = {
      "thermal_bridge.type_missing" => [fact(ZONE_A, "tbt_GONE00000001", [0, 0, 9], [1, 0, 9])],
      "thermal_bridge.psi_missing" => [fact(ZONE_A, "tbt_DRAFT0000001", [0, 0, 9], [1, 0, 9])],
      "thermal_bridge.no_envelope_face" => [fact(ZONE_A, PARAPET, [0, 0, 9], [1, 0, 9], :faces => [{}])],
      "thermal_bridge.interior_junction" => [fact(ZONE_A, PARAPET, [0, 0, 9], [1, 0, 9],
                                                  :faces => [{ "boundary_condition" => "Adiabatic" }, {}])],
      "thermal_bridge.shared_definition" => [fact(ZONE_A, PARAPET, [0, 0, 9], [1, 0, 9], :shared => true)],
      "thermal_bridge.counted_twice" => [fact(ZONE_A, PARAPET, [0, 0, 9], [1, 0, 9]),
                                         fact(ZONE_B, PARAPET, [1, 0, 9 + 0.00002], [0, 0, 9])]
    }
    cases.each do |code, facts|
      setup
      codes = schedule(reference + facts).fetch("runs").flat_map { |row| row.fetch("findings") }
                                         .map { |finding| finding.fetch("code") }.uniq
      assert_equal [code], codes, code
      blocking = schedule(facts).fetch("runs").flat_map { |row| row.fetch("findings") }.map { |f| f["blocks_export"] }
      assert_equal [%w[thermal_bridge.type_missing thermal_bridge.psi_missing].include?(code)], blocking.uniq, code
    end

    setup
    apart = [fact(ZONE_A, PARAPET, [0, 0, 9], [1, 0, 9]), fact(ZONE_B, PARAPET, [0, 0, 9.0001], [1, 0, 9.0001])]
    assert(schedule(apart).fetch("runs").all? { |row| row.fetch("findings").empty? })

    outside = RUNS::Fact.new(:path => [5], :zone => nil, :reason => "outside_zone", :type_id => PARAPET,
                             :quantity => 1, :points_m => [[0, 0, 0], [1, 0, 0]], :vertex_ids => [1, 2], :faces => [],
                             :shared => false)
    result = schedule(reference + [outside])
    assert_equal 5, result.fetch("runs").length
    assert_equal [["thermal_bridge.outside_zone", [5], false]],
                 result.fetch("edge_findings").map { |finding| finding.values_at("code", "path", "blocks_export") }
  end

  def test_runs_tied_on_every_key_but_their_points_and_a_loop_hung_from_a_junction_read_the_same_in_any_order
    t = [fact(ZONE_A, PARAPET, [0, 0, 0], [1, 0, 0]), fact(ZONE_A, PARAPET, [0, 0, 0], [0, 1, 0]),
         fact(ZONE_A, PARAPET, [0, 0, 0], [0, 0, 1])]
    hung = chain(ZONE_A, PARAPET, [[5, 5, 5], [6, 5, 5], [6, 6, 5], [5, 5, 5]]) +
           [fact(ZONE_A, PARAPET, [5, 5, 5], [4, 5, 5])]
    facts = t + hung
    reads = [facts, facts.reverse, facts.rotate(2), facts.rotate(4)].map do |order|
      build(order).map { |run| [run.display_name, run.identifier, run.points_m] }
    end
    assert_equal [reads.first] * 4, reads
  end

  def test_a_quantity_of_one_and_one_point_zero_is_one_run
    facts = [fact(ZONE_A, PARAPET, [0, 0, 0], [1, 0, 0], :quantity => 1),
             fact(ZONE_A, PARAPET, [1, 0, 0], [2, 0, 0], :quantity => 1.0)]
    assert_equal 1, build(facts).length
  end

  def test_coincidence_is_found_across_a_lookup_cell_boundary_and_not_past_the_tolerance
    edge = ->(zone, offset) { fact(zone, PARAPET, [0.002 - offset, 0, 9], [1, 0, 9]) }
    across = schedule([edge.call(ZONE_A, 0.0), edge.call(ZONE_B, 0.00002)]).fetch("runs")
    assert(across.all? { |row| row.fetch("findings").map { |f| f.fetch("code") } == %w[thermal_bridge.counted_twice] })
    setup
    apart = schedule([edge.call(ZONE_A, 0.0), edge.call(ZONE_B, 0.00003)]).fetch("runs")
    assert(apart.all? { |row| row.fetch("findings").empty? })
  end

  def test_totals_leave_out_a_run_without_a_psi_value_and_its_type_reads_no_heat_loss
    totals = schedule(reference + [fact(ZONE_A, "tbt_DRAFT0000001", [0, 0, 9], [1, 0, 9])]).fetch("totals")
    draft = totals.fetch("by_type").find { |row| row.fetch("type_name") == "Draft" }
    assert_equal [1, nil], draft.values_at("run_count", "heat_loss_w_k")
    assert_in_delta 1.0, draft.fetch("length_m"), 0.001
    assert_in_delta 3.3, totals.fetch("by_group").find { |row| row.fetch("group") == "15-Ambient" }
                               .fetch("heat_loss_w_k"), 0.001
    assert_in_delta 4.74, totals.fetch("heat_loss_w_k"), 0.001
  end

  def test_a_tag_in_a_component_placed_twice_gives_two_shared_runs
    placed = [140, 141].map do |placement|
      fact(ZONE_B, "tbt_BALCONY00001", [5, 0, 1.5], [9, 0, 1.5], :container => [200, placement], :quantity => 2,
                                                                 :vertex_ids => [7, 8], :shared => true)
    end
    rows = schedule(placed).fetch("runs")
    assert_equal 2, rows.length
    assert(rows.all? { |row| row.fetch("shared") })
    assert_equal [["thermal_bridge.shared_definition"]] * 2,
                 rows.map { |row| row.fetch("findings").map { |finding| finding.fetch("code") } }
    assert_in_delta 4.0, schedule(placed).dig("totals", "by_type", 0, "heat_loss_w_k"), 0.001
  end
end
