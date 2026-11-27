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

  def test_unique_and_copy_name_compare_accented_letters_without_case_alike
    rows = [{ "id" => "a", "name" => "ÉRV" }, { "id" => "b", "name" => "érv (copy)" }]
    error = assert_raises(PhComposer::CodedError) { NAMES.unique!("érv", rows) }
    assert_equal "validation.failed", error.code
    assert_raises(PhComposer::CodedError) { NAMES.unique!("ÉRV (COPY)", rows) }
    assert_equal "ÉRV (copy 2)", NAMES.copy_name("ÉRV", rows)
  end

  # A numbered name takes the first free number, compared as names are, and a kind may fold names its own way; a
  # name quoted after its kind word, or the kind and its id with no name.
  def test_numbered_takes_the_first_free_number_and_titled_quotes_a_name
    assert_equal "Piping group 2", NAMES.numbered("Piping group", ["piping GROUP 1", "Piping group 3", "Riser"])
    assert_equal "Zone 3", NAMES.numbered("Zone", ["zone 1"], :from => 3)
    assert_equal "Zone 2", NAMES.numbered("Zone", ["Zone 1", "zone 2"], :compare => :itself.to_proc)
    assert_equal ["Zone \u201CZone A\u201D", "Zone zon_1"],
                 [NAMES.titled("Zone", "Zone A"), NAMES.titled("Zone", nil, "zon_1")]
  end

  def test_names_compare_by_case_fold_not_by_lowercase
    rows = [{ "id" => "a", "name" => "Maße" }, { "id" => "b", "name" => "MASSE (copy)" }]
    assert_raises(PhComposer::CodedError) { NAMES.unique!("MASSE", rows) }
    assert_equal "Maße (copy 2)", NAMES.copy_name("Maße", rows)
  end
end
