# frozen_string_literal: true

require "json"
require_relative "test_helper"

# The blend against the Phius Heat Pump Performance Estimator itself: each case is one filled-in estimator
# workbook's air-source inputs and cached results, extracted into the gitignored _private/heat_pumps/ folder, which
# its MANIFEST.md describes. The workbook is licensed and stays out of the repository, so this test skips when the
# extraction is absent. The coil temperature is not compared: PH-Composer writes 12.0 C, the estimator 45 F.
# The blend follows v25.1.2, whose SEER derating picks its branch by the SEER as entered; v25.1.1 picked it by the
# weighted SEER, so a v25.1.1 case compares everything but the derated SEER and what it feeds.
class HeatPumpEstimatorPrivateTest < PhComposerTestCase
  BLEND = PhComposer::Mechanical::HeatPumps::Blend
  CASES = File.expand_path("../_private/heat_pumps/estimator_cases.json", __dir__)
  HEATING = { "COPs" => %w[cop_pair hspf2], "HSPF" => %w[hspf hspf], "HSPF2" => %w[hspf hspf2] }.freeze
  COOLING = { "EER/SEER" => %w[eer_seer seer], "EER2/SEER2" => %w[eer_seer seer2], "IEER" => ["ieer", "seer2"],
              nil => [nil, "seer2"] }.freeze
  WEIGHTED = { "recirc" => "recirc", "share_17" => "capacity_17f", "share_47" => "capacity_47f",
               "cop_17" => "cop_17f", "cop_47" => "cop_47f", "derated_hspf" => "derated_hspf", "eer" => "eer",
               "seer" => "seer", "derated_seer" => "derated_seer", "ieer" => "ieer", "cop" => "cop" }.freeze
  # What a cooling capacity entered with no cooling type changes: the estimator counts it in every row's share of
  # cooling, and a record cannot hold it, since a model with no cooling rating has no cooling.
  COOLING_SHARES = %w[recirc eer seer derated_seer ieer cop derated_hspf].freeze
  # What v25.1.1's SEER branch changes.
  SEER_BRANCH = %w[derated_seer cop].freeze
  CURRENT = "v25.1.2"

  def test_blend_matches_the_estimator_workbooks
    skip "No estimator cases: see _private/heat_pumps/MANIFEST.md (licensed, never committed)." unless
      File.exist?(CASES)

    cases = JSON.parse(File.read(CASES)).reject { |entry| entry.fetch("rows").empty? }
    skip "The estimator cases hold no air-source rows." if cases.empty?

    cases.each { |entry| assert_case(entry) }
  end

  private

  def assert_case(entry)
    result = BLEND.call(entry.fetch("rows").map { |row| row(row) }, climate(entry))
    label = entry.fetch("digest")
    expected = entry.fetch("expected")
    fans = entry.fetch("fans_kbtuh").any?(&:positive?)
    current = entry.fetch("version").start_with?(CURRENT)
    untyped = entry.fetch("rows").any? { |row| row.fetch("cooling_type").nil? && row.fetch("cap_95_kbtuh") }
    climate = result.fetch("climate")
    assert_near expected.fetch("heating_months"), climate.fetch("heating_months"), "#{label} heating months"
    assert_near expected.fetch("share_below_17f"), climate.fetch("share_below_17f"), "#{label} below 17 F"
    assert_near expected.fetch("share_below_47f"), climate.fetch("share_below_47f"), "#{label} below 47 F"
    entry.fetch("rows").zip(result.fetch("weighted")).each do |row, weighted|
      WEIGHTED.each do |workbook, key|
        next if !current && SEER_BRANCH.include?(key)
        next if untyped && COOLING_SHARES.include?(key)

        assert_near row.fetch("expected").fetch(workbook) || 0.0, weighted.fetch(key) || 0.0,
                    "#{label} row #{row.fetch('row')} #{key}"
      end
    end
    model = result.fetch("energy_model")
    if untyped
      # A COP pair's weights are heating shares alone, so the heating COPs still compare.
      cop_pairs = entry.fetch("rows").all? { |row| row.fetch("heating_type") == "COPs" }
      if cop_pairs && !fans
        assert_near expected.fetch("cop_1"), model.fetch("cop_1"), "#{label} COP 1"
        assert_near expected.fetch("cop_2"), model.fetch("cop_2"), "#{label} COP 2"
      end
      return
    end

    assert_near expected.fetch("cooling_kbtuh"), model.fetch("cooling_capacity_kbtuh"), "#{label} cooling capacity"
    return if fans # The estimator's fan and pump terms are left out of this version.

    assert_near expected.fetch("cop_1"), model.fetch("cop_1"), "#{label} COP 1"
    assert_near expected.fetch("cop_2"), model.fetch("cop_2"), "#{label} COP 2"
    if current && expected.fetch("cooling_cop")
      assert_near expected.fetch("cooling_cop"), model.fetch("cooling_cop"), "#{label} cooling COP"
    end
    systems = expected.fetch("systems")
    # The estimator counts systems over every source; ground- and water-source are outside this version.
    return unless systems && expected.fetch("other_cooling_kbtuh").zero?

    assert_equal systems.to_i, model.fetch("systems_needed"), "#{label} systems"
    assert_near expected.fetch("flow_cfm_per_system") * systems, model.fetch("flow_rate_cfm"), "#{label} airflow"
  end

  def row(row)
    heating, hspf_version = HEATING.fetch(row.fetch("heating_type"))
    cooling, seer_version = COOLING.fetch(row.fetch("cooling_type"))
    kw = ->(kbtuh) { kbtuh && kbtuh / BLEND::KBTUH_PER_KW }
    equipment = {
      "heating_rating_mode" => heating, "hspf_version" => hspf_version, "seer_version" => seer_version,
      "cooling_rating_mode" => cooling, "heating_cap_17f_kw" => kw.call(row.fetch("cap_17_kbtuh")),
      "heating_cap_47f_kw" => kw.call(row.fetch("cap_47_kbtuh")), "cop_17f" => row.fetch("cop_17"),
      "cop_47f" => row.fetch("cop_47"), "hspf_value" => row.fetch("hspf"),
      "cooling_cap_95f_kw" => kw.call(row.fetch("cap_95_kbtuh")), "eer" => row.fetch("eer"),
      "seer" => row.fetch("seer"), "ieer" => row.fetch("ieer")
    }
    BLEND::Row.new(:id => "row_#{row.fetch('row')}", :name => "Row #{row.fetch('row')}",
                   :quantity => row.fetch("quantity"), :equipment => equipment)
  end

  def climate(entry)
    celsius = ->(fahrenheit) { (fahrenheit - 32.0) / 1.8 }
    BLEND::Climate.new(:monthly_air_c => entry.fetch("monthly_f").map(&celsius),
                       :heating_99_c => celsius.call(entry.fetch("heating_99_f")),
                       :cooling_1_c => celsius.call(entry.fetch("cooling_1_f")))
  end

  def assert_near(expected, actual, message)
    assert_in_delta expected, actual, 1e-9 + (1e-9 * expected.abs), message
  end
end
