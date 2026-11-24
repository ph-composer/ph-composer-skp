# frozen_string_literal: true

require_relative "test_helper"

# The blended heat pump in pure Ruby: the Phius estimator's arithmetic over synthetic outdoor
# models, each expected value worked by hand from the estimator's published method, and the plan that picks each
# Building Segment's models and reports what it leaves out. The comparison with real estimator workbooks is private
# (tests/heat_pump_estimator_private_test.rb).
class MechanicalHeatPumpBlendTest < Minitest::Test
  M = PhComposer::Mechanical
  BLEND = M::HeatPumps::Blend
  PLAN = M::HeatPumpPlan
  ZONE = M::ExportZones::Zone
  CODES = M::Codes
  # 14 F heating and 95 F cooling design temperatures; months of 10 F, 40 F and 60 F means.
  CLIMATE = BLEND::Climate.new(:monthly_air_c => ([-12.2222] * 2) + ([4.4444] * 4) + ([15.5556] * 6),
                               :heating_99_c => -10.0, :cooling_1_c => 35.0)

  def equipment(values = {})
    { "name" => "ODU", "heating_rating_mode" => "cop_pair", "hspf_version" => "hspf2", "seer_version" => "seer2",
      "heating_cap_17f_kw" => 5.0, "heating_cap_47f_kw" => 6.0, "cop_17f" => 2.0, "cop_47f" => 3.0,
      "cooling_rating_mode" => nil }.merge(values)
  end

  def row(id, quantity, values)
    BLEND::Row.new(:id => id, :name => id, :quantity => quantity, :equipment => equipment(values))
  end

  def test_cop_pairs_weigh_by_heating_capacity_at_each_temperature
    result = BLEND.call([row("a", 2, {}), row("b", 1, { "heating_cap_17f_kw" => 10.0, "heating_cap_47f_kw" => 12.0,
                                                        "cop_17f" => 3.0, "cop_47f" => 4.0 })], CLIMATE)
    export = result.fetch("export")
    # 2 x 5 kW and 1 x 10 kW at 17 F: half each, so (2.0 + 3.0) / 2; at 47 F 2 x 6 and 12, (3.0 + 4.0) / 2.
    assert_in_delta 2.5, export.fetch("cop_1"), 1e-12
    assert_in_delta 3.5, export.fetch("cop_2"), 1e-12
    assert_equal [-8.333, 8.333], export.values_at("ambient_temp_1_c", "ambient_temp_2_c")
    assert_in_delta 1.0, export.fetch("percent_coverage")
    refute export.fetch("cooling").fetch("used"), "a heating-only blend writes no cooling"
  end

  def test_hspf2_converts_and_derates_for_the_heating_design_temperature
    hspf = row("a", 1, { "heating_rating_mode" => "hspf", "hspf_value" => 9.0, "cooling_rating_mode" => "eer_seer",
                         "cooling_cap_95f_kw" => 10.0, "eer" => 12.0, "seer" => 18.0, "seer_version" => "seer" })
    result = BLEND.call([hspf], CLIMATE)
    weighted = result.fetch("weighted").first
    # HSPF2 9.0 x 1.1236 = 10.1 to one decimal. At 14 F and HSPF >= 8.5:
    # (1 - (0.1041 - 0.008862 x 14 - 0.0001153 x 14 + 0.02817 x 10.1)) x 10.1 = 7.44435852, over 3.412.
    assert_in_delta 10.1, weighted.fetch("hspf"), 1e-12
    assert_in_delta 7.44435852, weighted.fetch("derated_hspf"), 1e-9
    assert_in_delta 2.1818166822977725, result.fetch("export").fetch("cop_1"), 1e-9
    assert_in_delta 2.1818166822977725, result.fetch("export").fetch("cop_2"), 1e-9, "one value for both COPs"
    # SEER 18 at 95 F: (1 - (-0.5864 + 0.005668 x 95 + 0.01029 x 18)) x 18 = 15.52896; (12 + 15.52896) / 2 / 3.412.
    assert_in_delta 15.52896, weighted.fetch("derated_seer"), 1e-9
    assert_in_delta 4.0341383352872215, result.fetch("export").fetch("cooling").fetch("annual_cop"), 1e-9
  end

  def test_an_hspf_model_is_weighted_by_its_share_of_cooling_as_the_estimator_does
    heating_only = row("a", 1, { "heating_rating_mode" => "hspf", "hspf_value" => 9.0 })
    result = BLEND.call([heating_only], CLIMATE)
    assert_in_delta 0.0, result.fetch("export").fetch("cop_1"), 1e-12, "no cooling share, no heating COP"
  end

  def test_eer2_and_seer2_convert_to_one_decimal_and_ieer_is_weighted_undrated
    seer2 = row("a", 1, { "cooling_rating_mode" => "eer_seer", "cooling_cap_95f_kw" => 3.0, "eer" => 11.0,
                          "seer" => 19.5 })
    ieer = row("b", 1, { "cooling_rating_mode" => "ieer", "cooling_cap_95f_kw" => 1.0, "ieer" => 20.0 })
    weighted = BLEND.call([seer2, ieer], CLIMATE).fetch("weighted")
    # EER2 11.0 x 1.0432 - 0.0018 = 11.5; SEER2 19.5 x 1.047 - 0.0004 = 20.4; each by a 0.75 share of cooling.
    assert_in_delta 11.5 * 0.75, weighted.first.fetch("eer"), 1e-12
    assert_in_delta 20.4 * 0.75, weighted.first.fetch("seer"), 1e-12
    assert_in_delta 20.0 * 0.25, weighted.last.fetch("ieer"), 1e-12
    assert_in_delta 0.0, weighted.last.fetch("derated_seer"), 1e-12
    assert_in_delta 5.0 / 3.412, weighted.last.fetch("cop"), 1e-12
  end

  def test_recirculation_airflow_and_capacity_follow_the_estimator
    cooled = row("a", 4, { "cooling_rating_mode" => "ieer", "cooling_cap_95f_kw" => 10.0, "ieer" => 20.0 })
    result = BLEND.call([cooled], CLIMATE)
    cooling = result.fetch("export").fetch("cooling")
    kbtuh = 40.0 * BLEND::KBTUH_PER_KW
    assert_in_delta 40.0, cooling.fetch("capacity_kw"), 1e-9
    # 300 cfm per ton of 12 kBtu/h, written in m3/h.
    assert_in_delta kbtuh / 12.0 * 300.0, result.fetch("energy_model").fetch("flow_rate_cfm"), 1e-9
    assert_in_delta kbtuh / 12.0 * 300.0 * 1.6990108, cooling.fetch("flow_rate_m3_hr"), 1e-3
    assert_equal [12.0, false, true, true], cooling.values_at("min_coil_temp_c", "single_speed",
                                                              "flow_rate_variable", "used")
    assert_equal 1, result.fetch("energy_model").fetch("systems_needed")
  end

  def test_the_climate_information_counts_heating_months
    climate = BLEND.call([row("a", 1, {})], CLIMATE).fetch("climate")
    assert_in_delta 14.0, climate.fetch("heating_99_f"), 1e-9
    assert_in_delta 95.0, climate.fetch("cooling_1_f"), 1e-9
    # Two months at 10 F, four at 40 F, six at 60 F.
    assert_equal 6, climate.fetch("heating_months")
    assert_in_delta 2.0 / 6, climate.fetch("share_below_17f"), 1e-12
    assert_in_delta 4.0 / 6, climate.fetch("share_below_47f"), 1e-12
  end

  # ---------------------------------------------------------------- the plan

  def zone(id, segment, units, exported: true)
    ZONE.new(:id => id, :name => id, :segment => segment, :exported => exported,
             :values => { "hp_indoor_unit_ids" => units })
  end

  def records(**rows)
    rows.to_h { |id, values| [id.to_s, values.merge("id" => id.to_s, "name" => values.fetch("name", id.to_s))] }
  end

  def plan(zones, outdoor_equipment: records(hpo_a: equipment), climate: CLIMATE, outdoor_units: nil,
           indoor_units: nil)
    outdoor_units ||= records(hou_1: { "outdoor_equipment_id" => "hpo_a", "quantity" => 1 })
    indoor_units ||= records(hiu_1: { "outdoor_unit_id" => "hou_1" })
    PLAN.call(:zones => zones, :outdoor_equipment => outdoor_equipment, :outdoor_units => outdoor_units,
              :indoor_units => indoor_units, :climate => climate)
  end

  def codes(found)
    found.findings.map(&:code)
  end

  def test_one_blend_per_segment_on_every_served_room
    found = plan([zone("z1", "A", ["hiu_1"]), zone("z2", "A", ["hiu_1"]), zone("z3", "A", [])])
    assert_equal 1, found.blends.length
    assert_equal %w[z1 z2], found.pairs.map { |pair| pair.fetch("zone_id") }
    assert_equal 1, found.pairs.map { |pair| pair.fetch("system_identifier") }.uniq.length
    assert_equal found.pairs.first.reject { |key, _| %w[id zone_id].include?(key) },
                 found.pairs.last.reject { |key, _| %w[id zone_id].include?(key) }
  end

  def test_two_units_of_one_model_blend_as_one_row_with_their_summed_quantity
    units = records(hou_1: { "outdoor_equipment_id" => "hpo_a", "quantity" => 2 },
                    hou_2: { "outdoor_equipment_id" => "hpo_a", "quantity" => 3 })
    indoor = records(hiu_1: { "outdoor_unit_id" => "hou_1" }, hiu_2: { "outdoor_unit_id" => "hou_2" })
    found = plan([zone("z1", "A", %w[hiu_1 hiu_2])], :outdoor_units => units, :indoor_units => indoor)
    devices = found.blends.first.fetch("result").fetch("devices")
    assert_equal [5], devices.map { |device| device.fetch("quantity") }
  end

  def test_segments_blend_apart_and_an_outdoor_unit_across_them_is_noted
    found = plan([zone("z1", "A", ["hiu_1"]), zone("z2", "B", ["hiu_1"])])
    assert_equal %w[A B], found.blends.map { |blend| blend.fetch("segment") }
    refute_equal(*found.blends.map { |blend| blend.fetch("identifier") })
    across = found.findings.select { |finding| finding.code == CODES::ITEM_ACROSS_SEGMENTS }
    assert_equal ["hou_1"], across.map(&:record_id)
  end

  def test_missing_climate_leaves_the_blend_out_with_a_finding
    reason = PLAN.climate(nil, -10.0, 35.0)
    assert_kind_of String, reason
    assert_kind_of String, PLAN.climate([1.0] * 12, nil, 35.0)
    found = plan([zone("z1", "A", ["hiu_1"])], :climate => reason)
    assert_empty found.blends
    assert_empty found.pairs
    assert_includes codes(found), CODES::HP_CLIMATE_MISSING
    refute found.findings.any?(&:blocks)
  end

  def test_cooling_over_200_kw_is_one_unsplit_system_with_a_note
    big = records(hpo_a: equipment("cooling_rating_mode" => "ieer", "cooling_cap_95f_kw" => 70.0, "ieer" => 20.0))
    units = records(hou_1: { "outdoor_equipment_id" => "hpo_a", "quantity" => 3 })
    found = plan([zone("z1", "A", ["hiu_1"])], :outdoor_equipment => big, :outdoor_units => units)
    assert_equal 1, found.blends.length
    assert_in_delta 210.0, found.pairs.first.fetch("cooling").fetch("capacity_kw"), 1e-9
    assert_equal 2, found.blends.first.fetch("result").fetch("energy_model").fetch("systems_needed")
    assert_includes codes(found), CODES::HP_COOLING_OVER_200KW
  end

  def test_unpaired_units_are_left_out_with_a_finding
    indoor = records(hiu_1: { "outdoor_unit_id" => "hou_1" }, hiu_2: { "outdoor_unit_id" => "hou_1" })
    units = records(hou_1: { "outdoor_equipment_id" => "hpo_a", "quantity" => 1 },
                    hou_2: { "outdoor_equipment_id" => "hpo_a", "quantity" => 1 })
    found = plan([zone("z1", "A", ["hiu_1"])], :outdoor_units => units, :indoor_units => indoor)
    unpaired = found.findings.select { |finding| finding.code == CODES::HP_UNIT_UNPAIRED }.map(&:record_id)
    assert_equal %w[hiu_2 hou_2], unpaired.sort
    assert_equal [1], found.blends.first.fetch("result").fetch("devices").map { |device| device.fetch("quantity") }
    refute_includes codes(found), CODES::ITEM_UNSERVED
  end

  def test_an_incomplete_model_is_left_out_with_a_finding
    found = plan([zone("z1", "A", ["hiu_1"])], :outdoor_equipment => records(hpo_a: equipment("cop_17f" => nil)))
    assert_empty found.blends
    incomplete = found.findings.find { |finding| finding.code == CODES::HP_EQUIPMENT_INCOMPLETE }
    assert_equal "hpo_a", incomplete.record_id
    assert_match(/COP at 17 F/, incomplete.message)
  end

  def test_an_hspf_model_with_no_cooling_share_is_noted_and_a_blend_of_only_such_models_is_left_out
    models = records(hpo_a: equipment, hpo_h: equipment("heating_rating_mode" => "hspf", "hspf_value" => 9.0))
    units = records(hou_1: { "outdoor_equipment_id" => "hpo_a", "quantity" => 1 },
                    hou_2: { "outdoor_equipment_id" => "hpo_h", "quantity" => 1 })
    indoor = records(hiu_1: { "outdoor_unit_id" => "hou_1" }, hiu_2: { "outdoor_unit_id" => "hou_2" })
    found = plan([zone("z1", "A", %w[hiu_1 hiu_2])], :outdoor_equipment => models, :outdoor_units => units,
                                                     :indoor_units => indoor)
    assert_equal 1, found.blends.length, "the COP model still heats"
    noted = found.findings.select { |finding| finding.code == CODES::HP_EQUIPMENT_INCOMPLETE }
    assert_equal ["hpo_h"], noted.map(&:record_id)
    assert_match(/adds no heating COP/, noted.first.message)

    alone = plan([zone("z1", "A", ["hiu_2"])], :outdoor_equipment => models, :outdoor_units => units,
                                               :indoor_units => indoor)
    assert_empty alone.blends
    assert_match(/left out/, alone.findings.find { |finding| finding.record_id == "hpo_h" }.message)
  end

  def test_a_zone_naming_an_indoor_unit_not_in_the_model_blocks
    found = plan([zone("z1", "A", ["hiu_Ab12Cd34Ef56"])])
    missing = found.findings.find { |finding| finding.code == CODES::ITEM_MISSING }
    assert missing.blocks
    assert_equal "z1", missing.record_id
  end

  def test_a_served_unit_naming_a_missing_parent_blocks
    lost_unit = plan([zone("z1", "A", ["hiu_1"])], :indoor_units => records(hiu_1: { "outdoor_unit_id" => "hou_9" }))
    assert_equal [["hiu_1", true]], lost_unit.findings.select { |finding| finding.code == CODES::ITEM_MISSING }
                                             .map { |finding| [finding.record_id, finding.blocks] }
    lost_model = plan([zone("z1", "A", ["hiu_1"])],
                      :outdoor_units => records(hou_1: { "outdoor_equipment_id" => "hpo_9", "quantity" => 1 }))
    assert_equal [["hou_1", true]], lost_model.findings.select { |finding| finding.code == CODES::ITEM_MISSING }
                                              .map { |finding| [finding.record_id, finding.blocks] }
    assert_empty lost_model.pairs
  end

  def test_a_zone_left_out_gives_no_pair_and_a_note
    found = plan([zone("z1", nil, ["hiu_1"], :exported => false)])
    assert_empty found.pairs
    assert_includes codes(found), CODES::ZONE_LEFT_OUT
  end
end
