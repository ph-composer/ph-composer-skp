# frozen_string_literal: true

require_relative "test_helper"

class RecordNamesTest < PhComposerTestCase
  NAMES = PhComposer::Records::Names
  ROWS = [{ "id" => "a", "name" => " Wall " }, { "id" => "b", "name" => "Roof" }].freeze

  def test_unique_refuses_a_blank_name_and_a_name_another_record_holds_regardless_of_case_and_outer_space
    ["  ", "wall", " ROOF "].each do |name|
      error = assert_raises(PhComposer::CodedError) { NAMES.unique!(name, ROWS) }
      assert_equal "validation.failed", error.code
    end
    NAMES.unique!("Floor", ROWS)
    NAMES.unique!("WALL", ROWS, :except => "a")
  end

  def test_copy_name_takes_the_first_free_copy_compared_trimmed_and_without_case
    records = [{ "name" => " TRIMMED (copy) " }, { "name" => " Trimmed (copy 2) " }]
    assert_equal "Trimmed (copy 3)", NAMES.copy_name(" Trimmed ", records)
    assert_equal "Wall (copy)", NAMES.copy_name("Wall", ROWS)
  end
end
