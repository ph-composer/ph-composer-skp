# frozen_string_literal: true

require "json"
require_relative "test_helper"

class UnitsTest < PhComposerTestCase
  Units = PhComposer::Units

  # The Ruby mirror carries only the report quantities; the rest belong to html/units.js.
  def test_shared_conversion_vectors
    rows = vectors.select { |row| Units::DEFINITIONS.key?(row.fetch("quantity")) }
    assert_equal Units::DEFINITIONS.keys.sort, rows.map { |row| row.fetch("quantity") }.sort
    rows.each do |row|
      actual = Units.to_display(row.fetch("canonical_value"), :quantity => row.fetch("quantity"), :system => "IP",
                                                              :unit => row.fetch("canonical_unit"))
      assert_in_delta row.fetch("expected_ip_value"), actual, row.fetch("tolerance"), row.fetch("quantity")
      assert_equal row.fetch("canonical_value"),
                   Units.to_display(row.fetch("canonical_value"), :quantity => row.fetch("quantity"), :system => "SI",
                                                                  :unit => row.fetch("canonical_unit"))
    end
  end

  def test_from_display_inverts_to_display_for_every_quantity
    vectors.select { |row| Units::DEFINITIONS.key?(row.fetch("quantity")) }.each do |row|
      quantity, canonical = row.values_at("quantity", "canonical_value")
      %w[IP SI].each do |system|
        shown = Units.to_display(canonical, :quantity => quantity, :system => system)
        assert_in_delta canonical, Units.from_display(shown, :quantity => quantity, :system => system), 1e-9,
                        "#{quantity} #{system}"
      end
    end
  end

  def test_from_display_reads_the_display_unit_into_the_canonical_one
    assert_in_delta 304.8, Units.from_display("12", :quantity => "length_mm", :system => "IP"), 1e-9
    assert_equal 125.0, Units.from_display("125", :quantity => "length_mm", :system => "SI")
    assert_in_delta 0.3048, Units.from_display(12, :quantity => "length_mm", :system => "IP", :unit => "m"), 1e-12
    assert_in_delta 100.0, Units.from_display(58.857777869, :quantity => "airflow", :system => "IP"), 1e-6
    assert_raises(ArgumentError) { Units.from_display("twelve", :quantity => "length_mm", :system => "IP") }
    assert_raises(TypeError) { Units.from_display(nil, :quantity => "length_mm", :system => "IP") }
  end

  def test_a_caller_can_move_or_turn_off_the_grouping
    assert_equal "2,083 m²", Units.format(2083.4, :quantity => "area", :system => "SI", :precision => 0,
                                                  :group_from => 1_000)
    assert_equal "999 m²", Units.format(999.4, :quantity => "area", :system => "SI", :precision => 0,
                                               :group_from => 1_000)
    assert_equal "12345.7", Units.format(12_345.67, :quantity => "length_mm", :system => "SI", :show_unit => false,
                                                    :group_from => nil)
  end

  def test_formats_export_quantities_in_both_systems
    [
      [0.5, "length", "0.5 m", "1.64 ft"],
      [25.4, "length_mm", "25.4 mm", "1 in"],
      [1, "area", "1 m²", "10.76 ft²"],
      [1, "volume", "1 m³", "35.31 ft³"],
      [1, "u_value", "1 W/(m² K)", "0.1761 Btu/(h ft² °F)"],
      [1, "thermal_resistance", "1 m² K/W", "5.68 h ft² °F/Btu"],
      [1, "conductivity", "1 W/(m K)", "0.578 Btu/(h ft °F)"],
      [0.1, "linear_psi", "0.1 W/(m K)", "0.058 Btu/(h ft °F)"],
      [1, "heat_loss_rate", "1 W/K", "1.896 Btu/(h °F)"],
      [100, "airflow", "100 m³/h", "58.9 cfm"]
    ].each do |value, quantity, si, ip|
      assert_equal si, Units.format(value, :quantity => quantity, :system => "SI")
      assert_equal ip, Units.format(value, :quantity => quantity, :system => "IP")
    end
  end

  def test_length_fields_can_store_another_canonical_unit
    assert_equal "76.2 mm", Units.format(0.0762, :quantity => "length_mm", :system => "SI", :unit => "m")
    assert_equal "3 in", Units.format(0.0762, :quantity => "length_mm", :system => "IP", :unit => "m")
  end

  def test_grouping_starts_at_ten_thousand_and_can_omit_units
    assert_equal "9999.5", Units.format(9999.5, :quantity => "length_mm", :system => "SI", :show_unit => false)
    assert_equal "10,000 mm", Units.format(9999.96, :quantity => "length_mm", :system => "SI")
    assert_equal "10,000.5 mm", Units.format(10_000.5, :quantity => "length_mm", :system => "SI")
  end

  private

  def vectors
    JSON.parse(File.read(File.join(__dir__, "support", "units_vectors.json")))
  end
end
