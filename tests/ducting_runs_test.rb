# frozen_string_literal: true

require_relative "test_helper"

# Duct runs, their findings and the schedule over detached facts: pure Ruby, no Model. The facts are ACCEPTANCE's ERV
# ducting case, and its hand measurement is the expected schedule.
class DuctingRunsTest < Minitest::Test
  D = PhComposer::Ducting
  DT1 = "dct_DT1000000001"
  DT2 = "dct_DT2000000002"
  ERV1 = "vnt_ERV100000001"
  ERV2 = "vnt_ERV200000002"
  TYPES = {
    DT1 => { "id" => DT1, "name" => "DT-1", "shape" => "round", "diameter_mm" => 160.0,
             "insulation_thickness_mm" => 25.4, "insulation_conductivity_w_mk" => 0.04,
             "insulation_reflective" => true },
    DT2 => { "id" => DT2, "name" => "DT-2", "shape" => "rectangular", "width_mm" => 200.0, "height_mm" => 100.0,
             "insulation_thickness_mm" => 50.8, "insulation_conductivity_w_mk" => 0.035,
             "insulation_reflective" => false }
  }.freeze
  VENTILATORS = { ERV1 => { "id" => ERV1, "name" => "ERV-1" }, ERV2 => { "id" => ERV2, "name" => "ERV-2" } }.freeze
  DG1 = { "group_id" => "dcg_DG1000000001", "group_path" => [600], "name" => "DG-1", "ventilator_id" => ERV1,
          "in_zone" => false }.freeze
  DG2 = { "group_id" => "dcg_DG2000000002", "group_path" => [700], "name" => "DG-2", "ventilator_id" => ERV2,
          "in_zone" => false }.freeze

  def setup
    @next_id = 1000
  end

  def duct(direction, type, from, to, group: DG1, quantity: 1, shared: false, record_id: nil, id: nil)
    id ||= (@next_id += 1)
    D::Runs::Fact.new(:path => group.fetch("group_path") + [id], :group => group,
                      :record_id => record_id || "dce_#{id}", :duct_type_id => type, :direction => direction,
                      :quantity => quantity, :points_m => [from, to], :shared => shared)
  end

  def line(direction, type, points, **options)
    points.each_cons(2).map { |from, to| duct(direction, type, from, to, **options) }
  end

  def dg1_outdoor(**options)
    line("outdoor_air", DT1, [[1, 0.5, 2.8], [1, 2, 2.8], [2, 2, 2.8]], **options)
  end

  def dg1_exhaust(**options)
    line("exhaust_air", DT1, [[1.5, 0.5, 2.8], [1.5, 1.5, 2.8], [2.3, 1.5, 2.8]], **options)
  end

  def dg2
    [duct("outdoor_air", DT2, [6, 0.5, 2.8], [6, 3, 2.8], :group => DG2),
     duct("exhaust_air", DT2, [7, 0.5, 2.8], [7, 2, 2.8], :group => DG2, :quantity => 2)]
  end

  def the_case
    dg1_outdoor + dg1_exhaust + dg2
  end

  def schedule(facts, types: TYPES, ventilators: VENTILATORS, served: [ERV1, ERV2])
    D::Schedule.call(facts, :types => types, :ventilators => ventilators, :served => served)
  end

  def lengths(result)
    result.fetch("ventilators").to_h do |row|
      [row.fetch("name"), row.values_at("outdoor_air_length_m", "exhaust_air_length_m").map { |value| value.round(3) }]
    end
  end

  # Each run's and Ventilator's finding codes, by group and run name or Ventilator name, those with none left out.
  def codes(result)
    named = ->(row) { row.fetch("findings").map { |finding| finding.fetch("code") } }
    runs = result.fetch("runs").to_h { |row| ["#{row.dig('group', 'name')} #{row.fetch('display_name')}", named[row]] }
    runs.merge(result.fetch("ventilators").to_h { |row| [row.fetch("name"), named[row]] })
        .reject { |_name, found| found.empty? }
  end

  # One code on both of a group's runs.
  def both(group, code)
    { "#{group} Outdoor air 1" => [code], "#{group} Exhaust air 1" => [code] }
  end

  def test_the_case_is_four_runs_as_measured_with_each_ventilators_lengths_quantity_applied
    result = schedule(the_case)
    rows = result.fetch("runs")
    assert_equal [["Outdoor air 1", "outdoor_air", ERV1, 2.5, 1, 2], ["Exhaust air 1", "exhaust_air", ERV1, 1.8, 1, 2],
                  ["Outdoor air 1", "outdoor_air", ERV2, 2.5, 1, 1], ["Exhaust air 1", "exhaust_air", ERV2, 1.5, 2, 1]],
                 rows.map { |row|
                   [row.fetch("display_name"), row.fetch("direction"), row.fetch("ventilator_id"),
                    row.fetch("length_m").round(3), row.fetch("quantity"), row.fetch("line_count")]
                 }
    assert_equal %w[ERV-1 ERV-1 ERV-2 ERV-2], rows.map { |row| row.fetch("ventilator_name") }
    assert_equal %w[DT-1 DT-1 DT-2 DT-2], rows.map { |row| row.fetch("duct_type_name") }
    assert_equal({ "ERV-1" => [2.5, 1.8], "ERV-2" => [2.5, 3.0] }, lengths(result))
    assert_empty codes(result)
    totals = result.fetch("totals")
    assert_equal [4, 6, 9.8], [*totals.values_at("run_count", "line_count"), totals.fetch("length_m").round(3)]
    assert_equal [["outdoor_air", 2, 3, 5.0], ["exhaust_air", 2, 3, 4.8]],
                 totals.fetch("by_direction").map { |row|
                   [*row.values_at("direction", "run_count", "line_count"), row.fetch("length_m").round(3)]
                 }
    assert_equal({ DT1 => [4.3, 4], DT2 => [5.5, 2] },
                 result.fetch("types").to_h { |row|
                   [row.fetch("duct_type_id"), [row.fetch("used_length_m").round(3), row.fetch("line_count")]]
                 })
    assert(rows.all? { |row| row.fetch("identifier").match?(/\Aduct_[0-9a-f]{16}\z/) })
  end

  def test_lines_of_one_key_that_do_not_touch_are_one_run_and_a_second_type_is_a_second_run
    apart = [duct("outdoor_air", DT1, [0, 0, 0], [1, 0, 0]), duct("outdoor_air", DT1, [5, 5, 5], [5, 7, 5])]
    rows = schedule(apart).fetch("runs")
    assert_equal [[3.0, 2]], rows.map { |row| [row.fetch("length_m").round(3), row.fetch("line_count")] }

    first, second = dg1_outdoor
    second.duct_type_id = DT2
    result = schedule([first, second] + dg1_exhaust + dg2)
    outdoor = result.fetch("runs").select { |row| row.fetch("display_name").start_with?("Outdoor") }.first(2)
    assert_equal [["Outdoor air 1", DT1, 1.5], ["Outdoor air 2", DT2, 1.0]],
                 outdoor.map { |row| [*row.values_at("display_name", "duct_type_id"), row.fetch("length_m").round(3)] }
    assert_equal [2.5, 1.8], lengths(result).fetch("ERV-1")
  end

  def test_a_second_quantity_is_a_second_run_and_each_total_applies_its_own
    facts = [duct("exhaust_air", DT1, [0, 0, 0], [1, 0, 0]),
             duct("exhaust_air", DT1, [0, 1, 0], [2, 1, 0], :quantity => 2)]
    result = schedule(facts)
    assert_equal [[1.0, 1], [2.0, 2]],
                 result.fetch("runs").map { |row| [row.fetch("length_m").round(3), row.fetch("quantity")] }
                       .sort_by(&:last)
    assert_equal [0.0, 5.0], lengths(result).fetch("ERV-1")
    assert_equal 5.0, result.fetch("types").find { |row| row.fetch("duct_type_id") == DT1 }.fetch("used_length_m")
  end

  def test_a_pasted_group_counts_twice_with_distinct_identifiers_and_the_shared_note
    copy = DG1.merge("group_path" => [601])
    facts = dg1_outdoor(:shared => true) + dg1_exhaust(:shared => true) +
            dg1_outdoor(:group => copy, :shared => true) + dg1_exhaust(:group => copy, :shared => true) + dg2
    result = schedule(facts)
    mine = result.fetch("runs").select { |row| row.fetch("ventilator_id") == ERV1 }
    assert_equal 4, mine.length
    assert_equal 4, mine.map { |row| row.fetch("identifier") }.uniq.length
    assert_equal ["Outdoor air 1", "Outdoor air 2", "Exhaust air 1", "Exhaust air 2"].sort,
                 mine.map { |row| row.fetch("display_name") }.sort
    assert(mine.all? { |row| row.fetch("findings").map { |f| f.fetch("code") } == ["ducting.shared_definition"] })
    assert_equal [5.0, 3.6], lengths(result).fetch("ERV-1")
  end

  def test_identifiers_and_names_hold_across_scans_and_a_reassignment_and_a_split_is_two_segments
    first = D::Runs.call(the_case)
    @next_id = 1000
    reassigned = the_case.each { |fact| fact.record_id = "dce_OTHER#{fact.path.last}" }
    reassigned.first.points_m = reassigned.first.points_m.reverse
    second = D::Runs.call(reassigned.reverse)
    assert_equal first.map { |run| [run.identifier, run.display_name, run.segments] },
                 second.map { |run| [run.identifier, run.display_name, run.segments] }

    halves = [duct("exhaust_air", DT1, [0, 0, 0], [1, 0, 0], :record_id => "dce_SPLIT0000001"),
              duct("exhaust_air", DT1, [1, 0, 0], [2, 0, 0], :record_id => "dce_SPLIT0000001")]
    run = D::Runs.call(halves).first
    assert_equal 2, run.segments.uniq.length
    assert(run.segments.all? { |id| id.match?(/\Aduct_seg_[0-9a-f]{16}\z/) })
  end

  def test_each_finding_fires_on_its_case_and_on_no_other
    exhaust_cleared = dg1_outdoor + dg2
    assert_equal({ "ERV-1" => ["ducting.run_missing"] }, codes(schedule(exhaust_cleared)))
    missing = schedule(exhaust_cleared).fetch("ventilators").first.fetch("findings").first
    assert_equal [false, { "name" => "ph_composer.mechanical.locate", "params" => { "ventilator_ids" => [ERV1] } }],
                 missing.values_at("blocks_export", "locate")
    assert_empty codes(schedule(exhaust_cleared, :served => [ERV2])), "an unserved Ventilator has no missing run"
    assert_equal({ "ERV-1" => ["ducting.run_missing"], "ERV-2" => ["ducting.run_missing"] },
                 codes(schedule([], :served => [ERV1, ERV2])))

    no_erv2 = schedule(the_case, :ventilators => VENTILATORS.slice(ERV1), :served => [ERV1])
    assert_equal both("DG-2", "ducting.group_unlinked"), codes(no_erv2)
    unlinked = no_erv2.fetch("runs")[2]
    finding = unlinked.dig("findings", 0)
    assert_equal [true, unlinked.fetch("edge_paths"),
                  "Ducting group DG-2 names Ventilator #{ERV2}, which no longer exists; link it."],
                 [finding.fetch("blocks_export"), finding.dig("locate", "edge_paths"), finding.fetch("message")]

    bare = TYPES.merge(DT2 => TYPES.fetch(DT2).reject { |key, _value| key == "insulation_conductivity_w_mk" })
    assert_equal both("DG-2", "ducting.insulation_conductivity_missing"), codes(schedule(the_case, :types => bare))

    found = schedule((dg1_outdoor + dg1_exhaust).each { |fact| fact.duct_type_id = nil } + dg2)
    assert_equal both("DG-1", "ducting.type_missing"), codes(found)
    assert_equal 4, found.fetch("runs").first(2).sum { |row| row.dig("findings", 0, "locate", "edge_paths").length }
    assert_equal both("DG-1", "ducting.type_missing"), codes(schedule(the_case, :types => TYPES.slice(DT2)))

    held = DG1.merge("in_zone" => true)
    assert_equal both("DG-1", "ducting.group_in_zone"),
                 codes(schedule(dg1_outdoor(:group => held) + dg1_exhaust(:group => held) + dg2))
  end
end
