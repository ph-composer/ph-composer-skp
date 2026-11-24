# frozen_string_literal: true

require_relative "test_helper"

# Runs, the tree, the recirculation sum, the findings and the schedule over detached facts: pure Ruby, no Model. The
# facts are ACCEPTANCE's hot water piping case, and its hand measurement is the expected schedule.
class PipingRunsTest < Minitest::Test
  RUNS = PhComposer::Piping::Runs
  PT1 = "ppt_PT1000000001"
  PT2 = "ppt_PT2000000002"
  HWS = "hws_HWS100000001"
  TYPES = {
    PT1 => { "id" => PT1, "name" => "PT-1", "material" => 6, "diameter_mm" => 19.05, "insulation_thickness_mm" => 12.7,
             "insulation_conductivity_w_mk" => 0.04, "insulation_reflective" => true, "insulation_quality" => 1 },
    PT2 => { "id" => PT2, "name" => "PT-2", "material" => 6, "diameter_mm" => 12.7, "insulation_thickness_mm" => 0,
             "insulation_conductivity_w_mk" => 0.04, "insulation_reflective" => true, "insulation_quality" => 1 }
  }.freeze
  SYSTEMS = { HWS => { "id" => HWS, "name" => "HWS-1" } }.freeze
  PG1 = { "group_id" => "ppg_PG1000000001", "group_path" => [500], "name" => "PG-1", "hot_water_system_id" => HWS,
          "in_zone" => false }.freeze
  TRUNK = { "multiplier" => 12, "demand_recirculation" => false }.freeze

  def setup
    @vertices = {}
    @next_id = 1000
  end

  # One pipe from world points in metres in Piping group `group`. Vertex ids are minted per container from the point,
  # as SketchUp merges coincident endpoints inside one collection; `vertex_ids:` stands in for a second placement.
  def pipe(role, type, from, to, values: {}, group: PG1, container: group.fetch("group_path"), vertex_ids: nil,
           shared: false, record_id: nil)
    @next_id += 1
    ids = vertex_ids || [from, to].map { |point| @vertices[[container, point]] ||= (@next_id += 1) }
    RUNS::Fact.new(:path => container + [@next_id], :group => group, :record_id => record_id || "ppe_#{@next_id}",
                   :pipe_type_id => type, :role => role, :values => values, :points_m => [from, to],
                   :vertex_ids => ids, :shared => shared)
  end

  def line(role, type, points, **options)
    points.each_cons(2).map { |from, to| pipe(role, type, from, to, **options) }
  end

  def riser(**options)
    line("trunk", PT1, [[1, 1, 0], [1, 1, 3], [1, 1, 6], [1, 1, 9]], :values => TRUNK, **options)
  end

  def floors(**options)
    line("branch", PT2, [[1, 1, 3], [3, 1, 3], [5, 1, 3]], **options) +
      line("branch", PT2, [[1, 1, 6], [3, 1, 6], [5, 1, 6]], **options) +
      line("branch", PT2, [[1, 1, 9], [2.5, 1, 9], [4, 1, 9]], **options)
  end

  def twigs(**options)
    [[[3, 1, 3], [3, 2, 3]], [[5, 1, 3], [5, 2.5, 3]], [[3, 1, 6], [3, 2, 6]], [[5, 1, 6], [5, 2.5, 6]],
     [[2.5, 1, 9], [2.5, 2, 9]], [[4, 1, 9], [4, 2, 9]]].map { |from, to| pipe("twig", PT2, from, to, **options) }
  end

  def loop_pipes(**options)
    [pipe("recirculation", PT1, [1.2, 1, 0], [1.2, 1, 9],
          :values => { "water_temp_c" => 55.0, "daily_period" => 18 }, **options),
     pipe("recirculation", PT1, [1.2, 1, 9], [1.2, 3, 9],
          :values => { "water_temp_c" => 50.0, "daily_period" => 24 }, **options)]
  end

  def the_case(**options)
    riser(**options) + floors(**options) + twigs(**options) + loop_pipes(**options)
  end

  def recirculating(temperature = 60.0, hours = 24)
    { "water_temp_c" => temperature, "daily_period" => hours }
  end

  def schedule(facts, types: TYPES, systems: SYSTEMS)
    RUNS::Schedule.call(facts, :types => types, :systems => systems)
  end

  def codes(rows)
    rows.to_h { |row| [row.fetch("display_name"), row.fetch("findings").map { |finding| finding.fetch("code") }] }
        .reject { |_name, found| found.empty? }
  end

  def test_the_piping_case_is_one_trunk_three_branches_six_twigs_and_two_recirculation_runs_as_measured
    result = schedule(the_case)
    rows = result.fetch("runs")
    by_role = rows.group_by { |row| row.fetch("role") }
    assert_equal({ "trunk" => 1, "branch" => 3, "twig" => 6, "recirculation" => 2 }, by_role.transform_values(&:length))
    trunk = by_role.fetch("trunk").first
    assert_in_delta 9.0, trunk.fetch("length_m"), 0.001
    assert_equal [3, TRUNK, "Trunk 1", nil], trunk.values_at("line_count", "values", "display_name", "parent")
    branches = by_role.fetch("branch")
    assert_equal [4.0, 4.0, 3.0], branches.map { |row| row.fetch("length_m").round(3) }
    assert_equal [trunk.fetch("identifier")] * 3, branches.map { |row| row.fetch("parent") }
    twigs = by_role.fetch("twig")
    under = twigs.group_by { |row| row.fetch("parent") }
    assert_equal branches.map { |row| row.fetch("identifier") }.sort, under.keys.sort
    assert_equal [[1.0, 1.5], [1.0, 1.5], [1.0, 1.0]],
                 branches.map { |row|
                   under.fetch(row.fetch("identifier")).map { |twig|
                     twig.fetch("length_m").round(3)
                   }.sort
                 }
    assert_equal %w[Branch\ 1 Branch\ 2 Branch\ 3], branches.map { |row| row.fetch("display_name") }
    assert_equal [9.0, 2.0], by_role.fetch("recirculation").map { |row| row.fetch("length_m").round(3) }
    assert_empty codes(rows)

    totals = result.fetch("totals")
    assert_equal({ "trunk" => 9.0, "branch" => 11.0, "twig" => 7.0, "recirculation" => 11.0 },
                 totals.fetch("by_role").to_h { |row| [row.fetch("role"), row.fetch("length_m").round(3)] })
    assert_equal [12, 17], totals.values_at("run_count", "line_count")
    assert_in_delta 27.0, totals.fetch("distribution_length_m"), 0.001
    assert_in_delta 11.0, totals.fetch("recirculation_length_m"), 0.001

    system = result.fetch("systems").first
    assert_equal [HWS, "HWS-1", 19, true],
                 system.values_at("hot_water_system_id", "name", "recirculation_hours", "from_piping")
    assert_in_delta 54.09, system.fetch("recirculation_temperature_c"), 0.005
    assert_equal({ "trunk" => 9.0, "branch" => 11.0, "twig" => 7.0 },
                 system.fetch("distribution_length_m").transform_values { |value| value.round(3) })
    assert_equal({ PT1 => 20.0, PT2 => 18.0 },
                 result.fetch("types").to_h { |row| [row.fetch("pipe_type_id"), row.fetch("used_length_m").round(3)] })
  end

  def test_a_trunk_changing_pipe_type_is_two_trunks_and_a_branch_through_a_tee_is_one_branch
    riser = [pipe("trunk", PT1, [1, 1, 0], [1, 1, 3], :values => TRUNK),
             pipe("trunk", PT2, [1, 1, 3], [1, 1, 6], :values => TRUNK)]
    through = line("branch", PT2, [[0, 1, 3], [1, 1, 3], [2, 1, 3]])
    rows = schedule(riser + through).fetch("runs")
    assert_equal 2, rows.count { |row| row.fetch("role") == "trunk" }
    branch = rows.select { |row| row.fetch("role") == "branch" }
    assert_equal [[2, 2.0]], branch.map { |row| [row.fetch("line_count"), row.fetch("length_m").round(3)] }
    # The branch touches both trunks at the type change: it takes the first identifier and warns.
    first = rows.select { |row| row.fetch("role") == "trunk" }.map { |row| row.fetch("identifier") }.min
    assert_equal first, branch.first.fetch("parent")
    assert_equal({ branch.first.fetch("display_name") => ["piping.parent_ambiguous"] }, codes(rows))
  end

  def test_a_multiplier_written_as_a_float_or_past_a_floats_range_keys_and_identifies
    as_float = [pipe("trunk", PT1, [0, 0, 0], [1, 0, 0], :values => TRUNK),
                pipe("trunk", PT1, [1, 0, 0], [2, 0, 0], :values => TRUNK.merge("multiplier" => 12.0))]
    assert_equal 1, RUNS::Tree.call(as_float).length
    huge = pipe("trunk", PT1, [5, 0, 0], [6, 0, 0], :values => TRUNK.merge("multiplier" => 10**309))
    assert_match(/\Apipe_[0-9a-f]{16}\z/, RUNS::Tree.call([huge]).first.identifier)
  end

  # A branch touching its trunk at both ends has one parent, not two.
  def test_a_branch_touching_its_trunk_twice_has_one_parent
    trunk = line("trunk", PT1, [[0, 0, 0], [1, 0, 0], [2, 0, 0]], :values => TRUNK)
    loop_branch = line("branch", PT2, [[0, 0, 0], [0, 1, 0], [2, 1, 0], [2, 0, 0]])
    rows = schedule(trunk + loop_branch).fetch("runs")
    branch = rows.find { |row| row.fetch("role") == "branch" }
    assert_equal rows.first.fetch("identifier"), branch.fetch("parent")
    assert_empty codes(rows)
  end

  def test_a_branch_broken_from_its_trunk_is_unconnected_and_keeps_its_twigs
    facts = riser + line("branch", PT2, [[1, 1, 3], [3, 1, 3], [5, 1, 3]]) +
            line("branch", PT2, [[1.05, 1, 6], [3, 1, 6], [5, 1, 6]]) +
            line("branch", PT2, [[1, 1, 9], [2.5, 1, 9], [4, 1, 9]]) + twigs + loop_pipes
    rows = schedule(facts).fetch("runs")
    broken = rows.find { |row| row.fetch("role") == "branch" && row.fetch("parent").nil? }
    assert_equal({ broken.fetch("display_name") => ["piping.branch_unconnected"] }, codes(rows))
    assert(broken.fetch("findings").first.fetch("blocks_export"))
    assert_equal 2, rows.count { |row| row.fetch("parent") == broken.fetch("identifier") }
    assert_equal broken.fetch("edge_paths"), broken.dig("findings", 0, "locate", "edge_paths")
  end

  def test_a_twig_on_a_trunk_or_with_its_branch_cleared_is_unconnected
    on_trunk = pipe("twig", PT2, [1, 1, 3], [1, 2, 3])
    rows = schedule(riser + line("branch", PT2, [[1, 1, 6], [2, 1, 6]]) + [on_trunk]).fetch("runs")
    twig = rows.find { |row| row.fetch("role") == "twig" }
    assert_equal({ twig.fetch("display_name") => ["piping.twig_unconnected"] }, codes(rows))

    setup
    cleared = riser + line("branch", PT2, [[1, 1, 3], [3, 1, 3], [5, 1, 3]]) +
              line("branch", PT2, [[1, 1, 6], [3, 1, 6], [5, 1, 6]]) + twigs
    found = codes(schedule(cleared).fetch("runs"))
    assert_equal [["piping.twig_unconnected"]] * 2, found.values
  end

  def test_a_riser_split_by_multiplier_gives_two_trunks_and_the_middle_branch_takes_the_first
    facts = line("trunk", PT1, [[1, 1, 0], [1, 1, 3], [1, 1, 6]], :values => TRUNK) +
            [pipe("trunk", PT1, [1, 1, 6], [1, 1, 9],
                  :values => { "multiplier" => 6, "demand_recirculation" => false })] +
            floors + twigs + loop_pipes
    rows = schedule(facts).fetch("runs")
    trunks = rows.select { |row| row.fetch("role") == "trunk" }
    assert_equal [[3.0, 6], [6.0, 12]], trunks.map { |row|
      [row.fetch("length_m").round(3), row.dig("values", "multiplier")]
    }.sort
    floor_two = rows.find { |row| row.fetch("role") == "branch" && row.fetch("findings").any? }
    assert_equal ["piping.parent_ambiguous"], floor_two.fetch("findings").map { |finding| finding.fetch("code") }
    refute floor_two.dig("findings", 0, "blocks_export")
    assert_equal trunks.map { |row| row.fetch("identifier") }.min, floor_two.fetch("parent")
    assert_equal 1, codes(rows).length
  end

  def test_two_placements_of_one_group_give_two_trunks_with_distinct_identifiers_and_count_both
    placed = [[500], [501]].flat_map do |container|
      group = PG1.merge("group_path" => container)
      @vertices = {}
      riser(:group => group, :shared => true) + floors(:group => group, :shared => true)
    end
    rows = schedule(placed).fetch("runs")
    trunks = rows.select { |row| row.fetch("role") == "trunk" }
    assert_equal 2, trunks.map { |row| row.fetch("identifier") }.uniq.length
    assert(rows.all? { |row|
      row.fetch("findings").map { |finding|
        finding.fetch("code")
      } == ["piping.shared_definition"]
    })
    assert_equal ["Trunk 1", "Trunk 2"], trunks.map { |row| row.fetch("display_name") }
    assert_in_delta 18.0, schedule(placed).dig("totals", "by_role", 0, "length_m"), 0.001
  end

  def test_identifiers_and_names_hold_across_scans_and_a_reassignment_and_a_split_edge_is_two_segments
    first = RUNS::Tree.call(the_case).map { |run| [run.display_name, run.identifier, run.segments] }
    setup
    again = RUNS::Tree.call(the_case(:record_id => "ppe_REASSIGNED01").reverse)
                      .map { |run| [run.display_name, run.identifier, run.segments] }
    assert_equal first, again
    assert(first.all? { |_name, id, segments|
      id.match?(/\Apipe_[0-9a-f]{16}\z/) && segments.all? { |segment|
        segment.match?(/\Apipe_seg_[0-9a-f]{16}\z/)
      }
    })

    setup
    split = line("branch", PT2, [[0, 0, 0], [1, 0, 0], [2, 0, 0]], :record_id => "ppe_SPLITSPLIT01")
    run = RUNS::Tree.call(split).first
    assert_equal 2, run.segments.uniq.length
  end

  def test_the_recirculation_sum_nests_as_honeybee_ph_does
    sum = ->(*runs) { RUNS::Recirculation.call(runs.map { |pipes| Struct.new(:facts).new(pipes) }) }
    recirculation = lambda do |length, temperature, hours, y = 0|
      pipe("recirculation", PT1, [0, y, 0], [length, y, 0],
           :values => { "water_temp_c" => temperature, "daily_period" => hours })
    end
    two = sum.call([recirculation.call(10, 60.0, 18)], [recirculation.call(5, 50.0, 23, 1)])
    assert_equal [15.0, 19, true], two.values_at("recirculation_length_m", "recirculation_hours", "from_piping")
    assert_in_delta 56.67, two.fetch("recirculation_temperature_c"), 0.005

    # 3.3 m and 1.7 m at 24 h in one run, and runs of 0.1, 0.2 and 0.7 m: 24. honeybee-ph's arithmetic gives 23 for
    # 3.3 m and 1.7 m as two runs (79.19999999999999 / 3.3), and so does this read, since it must equal the export.
    one_run = [recirculation.call(3.3, 60.0, 24), pipe("recirculation", PT1, [3.3, 0, 0], [5.0, 0, 0],
                                                       :values => { "water_temp_c" => 60.0, "daily_period" => 24 })]
    assert_equal 24, sum.call(one_run).fetch("recirculation_hours")
    short = sum.call([recirculation.call(0.1, 60.0, 24, 1)], [recirculation.call(0.2, 60.0, 24, 2)],
                     [recirculation.call(0.7, 60.0, 24, 3)])
    assert_equal 24, short.fetch("recirculation_hours")
    split = sum.call([recirculation.call(3.3, 60.0, 24, 4)], [recirculation.call(1.7, 60.0, 24, 5)])
    assert_equal 23, split.fetch("recirculation_hours")

    assert_equal({ "recirculation_length_m" => 0.0, "recirculation_temperature_c" => 60.0, "recirculation_hours" => 24,
                   "from_piping" => false }, sum.call)
  end

  def test_both_loop_lines_at_24_hours_read_24
    loop = [pipe("recirculation", PT1, [1.2, 1, 0], [1.2, 1, 9], :values => recirculating(55.0)),
            pipe("recirculation", PT1, [1.2, 1, 9], [1.2, 3, 9], :values => recirculating(50.0))]
    assert_equal 24, schedule(loop).dig("systems", 0, "recirculation_hours")
  end

  def test_each_finding_fires_on_its_case_and_no_other
    gone = PG1.merge("hot_water_system_id" => "hws_GONEGONEGONE")
    unlinked = PG1.merge("group_path" => [510], "hot_water_system_id" => nil)
    in_zone = PG1.merge("group_path" => [520], "in_zone" => true)
    bare = TYPES.merge(PT1 => TYPES.fetch(PT1).merge("insulation_conductivity_w_mk" => nil))
    cases = {
      "piping.type_missing" => [[pipe("twig", nil, [1, 1, 3], [1, 2, 3])] + riser + floors, TYPES],
      "piping.type_missing " => [[pipe("twig", "ppt_DELETED00001", [3, 1, 3], [3, 2, 3])] + riser + floors, TYPES],
      "piping.group_unlinked" => [[pipe("recirculation", PT1, [0, 0, 0], [1, 0, 0], :group => gone,
                                                                                    :values => recirculating)], TYPES],
      "piping.group_unlinked " => [[pipe("recirculation", PT1, [0, 0, 0], [1, 0, 0], :group => unlinked,
                                                                                     :values => recirculating)], TYPES],
      "piping.group_in_zone" => [[pipe("recirculation", PT1, [0, 0, 0], [1, 0, 0], :group => in_zone,
                                                                                   :values => recirculating)], TYPES],
      "piping.insulation_conductivity_missing" => [[pipe("recirculation", PT1, [0, 0, 0], [1, 0, 0],
                                                         :values => recirculating)],
                                                   bare],
      "piping.trunk_without_branches" => [riser, TYPES]
    }
    cases.each do |code, (facts, types)|
      rows = schedule(facts, :types => types).fetch("runs")
      found = rows.flat_map { |row| row.fetch("findings") }
      assert_equal [code.strip], found.map { |finding| finding.fetch("code") }, code
      assert_equal !code.start_with?("piping.trunk"), found.first.fetch("blocks_export"), code
    end
    assert_empty codes(schedule(the_case).fetch("runs"))
  end

  def test_a_group_linked_to_no_existing_system_adds_to_no_system_row
    facts = loop_pipes(:group => PG1.merge("hot_water_system_id" => nil))
    system = schedule(facts).fetch("systems").first
    assert_equal [0.0, false, 60.0, 24],
                 system.values_at("recirculation_length_m", "from_piping", "recirculation_temperature_c",
                                  "recirculation_hours")
  end
end
