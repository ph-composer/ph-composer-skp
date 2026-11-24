# frozen_string_literal: true

require_relative "test_helper"

# The chain rule in core over generic facts: pure Ruby, no Model. These are Phase 3b's chain-rule cases, moved here
# from the thermal-bridge runs suite when hot water piping became the rule's second user.
class EdgeRunsTest < Minitest::Test
  RUNS = PhComposer::EdgeRuns
  KEY = "a key"

  def setup
    @vertices = {}
    @next_id = 1000
  end

  # One fact from world points in metres. Vertex ids are minted per container from the point, as SketchUp merges
  # coincident endpoints inside one collection; a `vertex_ids:` override stands in for a component whose placements
  # share ids.
  def fact(from, to, key: KEY, container: [100], vertex_ids: nil, item: nil)
    @next_id += 1
    ids = vertex_ids || [from, to].map { |point| @vertices[[container, point]] ||= (@next_id += 1) }
    RUNS::Fact.new(:path => container + [@next_id], :key => key, :vertex_ids => ids, :points_m => [from, to],
                   :item => item)
  end

  def chain(points, **options)
    points.each_cons(2).map { |from, to| fact(from, to, **options) }
  end

  def test_a_u_is_one_open_run_a_square_one_closed_run_and_a_t_three_runs
    u = RUNS.build(chain([[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]]))
    assert_equal [[false, 4]], u.map { |run| [run.closed, run.points_m.length] }

    square = RUNS.build(chain([[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0], [0, 0, 0]]))
    assert_equal [[true, 5]], square.map { |run| [run.closed, run.points_m.length] }
    assert_equal square.first.points_m.first, square.first.points_m.last
    assert_in_delta 4.0, square.first.length_m, 1e-9

    t = RUNS.build([fact([0, 0, 0], [1, 0, 0]), fact([1, 0, 0], [2, 0, 0]), fact([1, 0, 0], [1, 1, 0])])
    assert_equal [2, 2, 2], t.map { |run| run.points_m.length }
  end

  def test_edges_join_by_vertex_within_one_container_and_never_across_containers
    assert_equal 1, RUNS.build(chain([[0, 0, 0], [1, 0, 0], [2, 0, 0]])).length

    nested = [fact([0, 0, 0], [1, 0, 0]), fact([1, 0, 0], [2, 0, 0], :container => [100, 300])]
    assert_equal 2, RUNS.build(nested).length

    # Two placements of one component: the same vertex ids, the same points, two containers.
    placed = [140, 141].map { |placement|
      fact([0, 0, 1.5], [4, 0, 1.5], :container => [100, placement], :vertex_ids => [7, 8])
    }
    runs = RUNS.build(placed)
    assert_equal [[100, 140], [100, 141]], runs.map(&:container_path).sort
  end

  def test_edges_of_two_keys_never_join_and_a_t_of_one_key_passes_straight_through_another
    # A line of key "a" crossing a vertex where a line of key "b" ends: "a" passes through, "b" ends there.
    facts = [fact([0, 0, 0], [1, 0, 0], :key => "a"), fact([1, 0, 0], [2, 0, 0], :key => "a"),
             fact([1, 0, 0], [1, 1, 0], :key => "b")]
    runs = RUNS.build(facts)
    assert_equal [["a", 3], ["b", 2]], runs.map { |run| [run.key, run.points_m.length] }
  end

  def test_a_facts_item_comes_back_on_its_run_in_run_order
    facts = [fact([1, 0, 0], [2, 0, 0], :item => :second), fact([0, 0, 0], [1, 0, 0], :item => :first)]
    run = RUNS.build(facts).first
    assert_equal %i[first second], run.items
    assert_equal [[0, 0, 0], [1, 0, 0], [2, 0, 0]], run.points_m
    assert_equal run.facts.map(&:path), run.edge_paths
    assert_in_delta 2.0, run.length_m, 1e-9
  end

  def test_runs_read_the_same_in_any_order_including_a_loop_hung_from_a_junction
    t = [fact([0, 0, 0], [1, 0, 0]), fact([0, 0, 0], [0, 1, 0]), fact([0, 0, 0], [0, 0, 1])]
    hung = chain([[5, 5, 5], [6, 5, 5], [6, 6, 5], [5, 5, 5]]) + [fact([5, 5, 5], [4, 5, 5])]
    facts = t + hung
    reads = [facts, facts.reverse, facts.rotate(2), facts.rotate(4)].map do |order|
      RUNS.build(order).map { |run| [run.points_m, run.edge_paths, run.closed] }.sort_by(&:to_s)
    end
    assert_equal [reads.first] * 4, reads
  end

  def test_points_compare_at_a_micrometre_and_minus_zero_reads_as_zero
    assert_equal [0.0, 1.000001, 2.0], RUNS.point_key([-0.0000001, 1.0000011, 2.0])
    assert RUNS.before?([0, 0, 0], [0, 0, 0.000002])
    refute RUNS.before?([0, 0, 0.0000004], [0, 0, 0])
  end

  # The chain rule is the foundation's: it names no feature, Zone, psi-value or identifier prefix.
  def test_the_chain_rule_names_no_feature
    source = File.read(File.join(SOURCE_ROOT, "ph_composer", "core", "edge_runs.rb"), :encoding => "UTF-8")
    pattern = /ThermalBridges|Piping|Zones|thermal_bridge|piping|zone|psi|tb_|pipe_/i
    ["ThermalBridges::Runs", "Piping::Runs", "zone_path", "psi_w_mk", "tb_1234", "pipe_abc"].each do |text|
      assert_match pattern, text
    end
    assert_empty source.scan(pattern)
  end
end
