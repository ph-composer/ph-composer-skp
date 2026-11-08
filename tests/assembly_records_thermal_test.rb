# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/assembly_record_fixtures"

class AssemblyRecordsThermalTest < PhComposerTestCase
  include AssemblyRecordFixtures

  def test_the_predecessors_three_reference_cases_match_to_six_places
    cases = [reference_layers,
             [[12, [[1000, "board"]]], [140, [[850, "wool"], [150, "wood"]]], [40, [[1000, "soft"]]]],
             [[12, [[1000, "board"]]], [140, [[850, "wool"], [150, "wood"]]],
              [40, [[900, "soft"], [100, "wood"]]]]]
    cases.zip([0.194983, 0.228508, 0.238330]).each do |layers, u_value|
      effective = Assemblies::Thermal.effective(fixture_assembly(layers), fixture_materials)
      assert_equal u_value, effective["u_effective_w_m2k"]
    end
  end

  def test_missing_material_and_conductivity_withhold_numbers_with_reasons
    missing = fixture_assembly([[100, [[1000, nil]]]])
    assert_nil Assemblies::Thermal.effective(missing, fixture_materials)
    assert_equal ["assembly.segment_unassigned"], Assemblies::Thermal.preview(missing, fixture_materials)["flags"]
    materials = fixture_materials
    materials[material_id("wool")].delete("conductivity_w_mk")
    block = Assemblies::Thermal.preview(fixture_assembly([[100, [[1000, "wool"]]]]), materials)
    assert_nil block["u_effective_w_m2k"]
    assert_equal ["material.conductivity_missing"], block["flags"]
  end

  def test_membranes_contribute_no_resistance_and_all_membranes_have_no_value
    base = fixture_assembly(reference_layers)
    with_membrane = fixture_assembly(reference_layers + [[1, [[1000, "membrane"]]]])
    assert_equal Assemblies::Thermal.effective(base, fixture_materials),
                 Assemblies::Thermal.effective(with_membrane, fixture_materials)
    block = Assemblies::Thermal.preview(fixture_assembly([[1, [[1000, "membrane"]]]]), fixture_materials)
    assert_nil block["u_effective_w_m2k"]
    assert_equal ["assembly.no_thermal_layers"], block["flags"]
  end

  def test_ventilated_cladding_applies_only_to_an_exterior_facing_outdoors
    ground = fixture_assembly(reference_layers, "ventilated_cladding" => true, "exterior_condition" => "Ground")
    outdoors = fixture_assembly(reference_layers, "ventilated_cladding" => true, "exterior_condition" => "Outdoors")
    assert_equal 0.0, Assemblies::Thermal.preview(ground, fixture_materials)["rse_m2k_w"]
    assert_equal 0.13, Assemblies::Thermal.preview(outdoors, fixture_materials)["rse_m2k_w"]
  end

  def test_ventilated_cladding_changes_only_the_with_films_value
    base = Assemblies::Thermal.preview(fixture_assembly(reference_layers), fixture_materials)
    ventilated = Assemblies::Thermal.preview(fixture_assembly(reference_layers, "ventilated_cladding" => true),
                                             fixture_materials)
    assert_equal 0.13, ventilated["rse_m2k_w"]
    assert_equal base["u_construction_w_m2k"], ventilated["u_construction_w_m2k"]
    refute_equal base["u_effective_w_m2k"], ventilated["u_effective_w_m2k"]
    { "Wall" => 0.13, "RoofCeiling" => 0.10, "Floor" => 0.17 }.each do |type, rsi|
      assert_equal rsi, Assemblies::Thermal.preview(fixture_assembly(reference_layers, "type" => type),
                                                    fixture_materials)["rsi_m2k_w"]
    end
  end

  def test_exact_calculation_accepts_the_path_budget_and_withholds_one_path_above_it
    budget = Assemblies::Thermal::PATH_BUDGET
    boundary = fixture_assembly([[100, Array.new(budget) { [1, "wool"] }]])
    assert_equal 0.374532, Assemblies::Thermal.effective(boundary, fixture_materials)["u_effective_w_m2k"]
    over = fixture_assembly([[100, Array.new(budget + 1) { [1, "wool"] }]])
    assert_empty Assemblies::Assembly::Schema::KIND.problems(over),
                 "the calculation budget does not limit authored records"
    assert_nil Assemblies::Thermal.effective(over, fixture_materials)
    block = Assemblies::Thermal.preview(over, fixture_materials)
    assert_equal ["assembly.calculation_limit"], block["flags"]
    assert_equal false, block["complete"]
    assert_nil block["r_construction_m2k_w"]
  end

  def test_cartesian_path_budget_is_checked_before_visiting_mixed_layer_combinations
    materials = fixture_materials
    mixed = [100, [[500, "wool"], [500, "wood"]]]
    boundary = fixture_assembly(Array.new(14) { mixed })
    assert_equal 16_384, Assemblies::Thermal::PATH_BUDGET
    refute_nil Assemblies::Thermal.effective(boundary, materials)
    over = fixture_assembly(Array.new(30) { mixed })
    block = Assemblies::Thermal.preview(over, materials)
    assert_equal ["assembly.calculation_limit"], block["flags"]
    assert_nil block["u_effective_w_m2k"]
  end

  def test_many_uniform_layers_collapse_into_base_resistance_without_recursion
    count = 5000
    materials = fixture_materials
    layers = Array.new(count) { [1, [[1000, "wool"]]] }
    layers << [100, [[500, "wool"], [500, "wood"]]]
    result = Assemblies::Thermal.effective(fixture_assembly(layers), materials)
    base = count * 0.001 / 0.04
    parallel = 1.0 / (0.5 / (base + 0.1 / 0.04) + 0.5 / (base + 0.1 / 0.13))
    isothermal = base + 0.1 / (0.5 * 0.04 + 0.5 * 0.13)
    assert_equal ((parallel + isothermal) / 2).round(6), result["r_construction_m2k_w"]
  end
end
