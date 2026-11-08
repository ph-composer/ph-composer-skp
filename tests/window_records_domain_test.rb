# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/window_record_fixtures"

class WindowRecordsDomainTest < PhComposerTestCase
  include WindowRecordFixtures

  def test_thermal_proof_exact_and_missing_terms_are_withheld
    record, input = thermal_proof
    calc = W::Thermal.calculate(record, input, input.fetch("default_install_id"))
    assert_in_delta 6.92448, calc["h_construction_w_k"], 1e-10
    assert_in_delta 1.0134, calc["u_effective_w_m2k"], 1e-10
    assert_in_delta 0.9617333333333333, calc["uw_w_m2k"], 1e-10
    assert calc["complete"]
    input["frames"]["left"]["uf_w_m2k"] = nil
    calc = W::Thermal.calculate(record, input, input.fetch("default_install_id"))
    assert_nil calc["uw_w_m2k"]
    assert_nil calc["u_effective_w_m2k"]
    assert_in_delta 0.372, calc["h_install_w_k"], 1e-10
    refute calc["complete"]
    assert calc["elements"].all? { |element| !element["complete"] }
  end

  def test_shared_partial_and_empty_edges_preserve_construction_value
    record, input = thermal_proof
    top = record["elements"][0]
    top["column_span"] = [0, 1]
    record["elements"].delete_at(1)
    assert_equal [:perimeter, :perimeter, :shared, :perimeter], W::Grid.new(record).classify(top)
    calc = W::Thermal.calculate(record, input, input["default_install_id"])
    assert_in_delta 7.2, calc["area_m2"], 1e-10
    refute_nil calc["uw_w_m2k"]
    record["elements"].last["kind"] = "empty"
    assert_equal :partial, W::Grid.new(record).classify(top)[2]
    calc = W::Thermal.calculate(record, input, input["default_install_id"])
    assert_nil calc["u_effective_w_m2k"]
    refute_nil calc["uw_w_m2k"]
    assert_operator calc["empty_area_m2"], :>, 0
  end

  def test_edge_resolution_painted_default_zero_missing_and_partial
    cell = window_values["elements"].first
    cell["installs"]["left"] = "psi_painted"
    assert_equal [:assigned, "psi_painted"], W::EdgeResolution.resolve(cell, "left", :perimeter, "psi_default")
                                                              .to_h.values_at(:source, :effective_id)
    assert_equal [:default, "psi_default"], W::EdgeResolution.resolve(cell, "right", :perimeter, "psi_default")
                                                             .to_h.values_at(:source, :effective_id)
    assert_nil W::EdgeResolution.resolve(cell, "right", :perimeter, nil).effective_id
    assert_equal [:shared, nil], W::EdgeResolution.resolve(cell, "left", :shared, "psi_default")
                                                  .to_h.values_at(:source, :effective_id)
    assert_equal [:partial, nil], W::EdgeResolution.resolve(cell, "left", :partial, "psi_default")
                                                   .to_h.values_at(:source, :effective_id)
  end

  def test_grid_insert_merge_split_remove_and_flip_are_detached
    record = window_values
    original = PhComposer::DeepCopy.call(record)
    added = W::GridOperations.insert(record, { "axis" => "rows_m", "index" => 1, "value" => 1.5 },
                                     window_allocator)
    assert_equal original, record
    assert_equal 2, added["elements"].length
    merged = W::GridOperations.merge(added, { "ids" => added["elements"].map { |cell| cell["id"] } },
                                     window_allocator)
    assert_equal [0, 1], merged["elements"].first["row_span"]
    split = W::GridOperations.split(merged, { "element_id" => merged["elements"].first["id"] },
                                    window_allocator)
    assert_equal 2, split["elements"].length
    removed = W::GridOperations.remove(split, { "axis" => "rows_m", "index" => 0 })
    assert_equal [0, 0], removed["elements"].first["row_span"]
    assert_raises(PhComposer::CodedError) do
      W::GridOperations.remove(removed, { "axis" => "rows_m", "index" => 0 })
    end
    removed["elements"][0]["operation"] = { "type" => "swing", "directions" => %w[left up] }
    flipped = W::GridOperations.flip(removed)
    assert_equal %w[right up], flipped["elements"][0]["operation"]["directions"]
    assert_equal removed, W::GridOperations.flip(flipped)
  end

  def test_insert_clear_only_new_shared_edges_and_merge_refuses_install_loss
    record = window_values
    cell = record["elements"].first
    cell["installs"].merge!("top" => "psi_top", "right" => "psi_right")
    added = W::GridOperations.insert(record, { "axis" => "rows_m", "index" => 0, "value" => 0.5 },
                                     window_allocator)
    original = added["elements"].find { |entry| entry["id"] == cell["id"] }
    assert_nil original["installs"]["top"]
    assert_equal "psi_right", original["installs"]["right"]
    assert_raises(PhComposer::CodedError) do
      W::GridOperations.merge(added, { "ids" => added["elements"].map { |entry| entry["id"] } },
                              window_allocator)
    end
  end

  def test_installs_paint_apply_copy_guard_topology_and_shared_slots
    source = window_values
    added = W::GridOperations.insert(source, { "axis" => "columns_m", "index" => 1, "value" => 1 },
                                     window_allocator)
    painted = W::Installs.apply_all(added, "psi_test")
    assert_nil painted["elements"][0]["installs"]["right"]
    assert_equal "psi_test", painted["elements"][0]["installs"]["left"]
    assert_raises(PhComposer::CodedError) { W::Installs.paint(added, added["elements"][0]["id"], "right", "psi_test") }
    copy = W::Installs.copy(painted, added)
    assert_equal painted["elements"].map { |entry| entry["installs"] }, copy["elements"].map { |entry|
                                                                          entry["installs"]
                                                                        }
    assert_raises(PhComposer::CodedError) { W::Installs.copy(painted, source) }
    assert_empty W::Types::KIND.problems(copy.merge("id" => "wnt_AAAAAAAAAAAA", "schema_version" => 1))
  end

  def side_by_side_elements
    added = W::GridOperations.insert(window_values, { "axis" => "columns_m", "index" => 1, "value" => 1 },
                                     window_allocator)
    source, target = added["elements"].sort_by { |cell| cell["column_span"] }
    source.merge!("glazing_id" => "glz_AAAAAAAAAAAA", "operation" => { "type" => "slide", "directions" => ["right"] })
    source["frames"]["top"] = "frm_AAAAAAAAAAAA"
    [added, source, target]
  end

  def paste(record, source, target)
    pasted = W::GridOperations.paste(record, { "source_id" => source["id"], "ids" => [target["id"]] })
    pasted["elements"].find { |cell| cell["id"] == target["id"] }
  end

  def test_paste_between_mulled_elements_copies_installs_only_to_edges_outer_on_both
    record, source, target = side_by_side_elements
    source["installs"].merge!("top" => "psi_AAAAAAAAAAAA", "bottom" => "psi_BBBBBBBBBBBB", "left" => "psi_CCCCCCCCCCCC")
    target["installs"]["right"] = "psi_DDDDDDDDDDDD"

    pasted = paste(record, source, target)

    assert_equal source["glazing_id"], pasted["glazing_id"]
    assert_equal source["frames"], pasted["frames"]
    assert_equal source["operation"], pasted["operation"]
    assert_equal({ "top" => "psi_AAAAAAAAAAAA", "right" => "psi_DDDDDDDDDDDD", "bottom" => "psi_BBBBBBBBBBBB",
                   "left" => nil }, pasted["installs"])
  end

  def test_paste_clears_a_matching_outer_edge_the_source_leaves_unassigned
    record, source, target = side_by_side_elements
    target["installs"]["top"] = "psi_DDDDDDDDDDDD"

    assert_nil paste(record, source, target)["installs"]["top"]
  end

  def test_paste_leaves_a_partly_shared_edge_alone
    wide = W::GridOperations.insert(window_values, { "axis" => "columns_m", "index" => 1, "value" => 1 },
                                    window_allocator)
    grid = W::GridOperations.insert(wide, { "axis" => "rows_m", "index" => 1, "value" => 1 }, window_allocator)
    left = grid["elements"].select { |cell| cell["column_span"] == [0, 0] }.map { |cell| cell["id"] }
    merged = W::GridOperations.merge(grid, { "ids" => left }, window_allocator)
    lower_right = merged["elements"].find { |cell| cell["row_span"] == [1, 1] && cell["column_span"] == [1, 1] }
    shaped = W::GridOperations.kind(merged, { "ids" => [lower_right["id"]], "kind" => "empty" })
    tall = shaped["elements"].find { |cell| cell["row_span"] == [0, 1] }
    source = shaped["elements"].find { |cell| cell["row_span"] == [0, 0] && cell["column_span"] == [1, 1] }
    source["installs"].merge!("top" => "psi_AAAAAAAAAAAA", "right" => "psi_BBBBBBBBBBBB")
    assert_equal :partial, W::Grid.new(shaped).classify(tall)[1]

    pasted = paste(shaped, source, tall)

    assert_equal "psi_AAAAAAAAAAAA", pasted["installs"]["top"]
    assert_nil pasted["installs"]["right"]
  end

  def test_setting_an_element_empty_clears_all_its_assignments
    record, source, = side_by_side_elements
    source["installs"]["left"] = "psi_AAAAAAAAAAAA"
    empty = W::GridOperations.kind(record, { "ids" => [source["id"]], "kind" => "empty" })
    cell = empty["elements"].find { |entry| entry["id"] == source["id"] }
    assert_nil cell["glazing_id"]
    assert_nil cell["operation"]
    assert cell["frames"].values.none?
    assert cell["installs"].values.none?
  end

  def test_frame_operation_mismatch_is_informational_and_missing_default_is_not_zero
    record, input = thermal_proof
    input["frames"].each_value { |frame| frame["operation"] = "swing" }
    calculated = W::Thermal.calculate(record, input, input.fetch("default_install_id"))
    assert calculated.fetch("complete")
    assert calculated.fetch("elements").first.fetch("findings").any? do |finding|
      finding.fetch("code") == "window_type.frame_operation_mismatch"
    end
    missing = W::Thermal.calculate(record, input, nil)
    assert_nil missing["u_effective_w_m2k"]
    refute_nil missing["uw_w_m2k"]
    refute missing.fetch("complete")
  end

  def test_an_unassigned_edge_takes_the_model_value_only_when_no_type_is_the_default
    record, input = thermal_proof
    record["elements"].each { |cell| cell["installs"].transform_values! { nil } }
    by_value = W::Thermal.calculate(record, input, nil, :default_psi_w_mk => 0.05)
    install = by_value.fetch("elements").first.fetch("edges").first.fetch("install")
    assert_equal({ "source" => "default", "id" => nil, "psi_w_mk" => 0.05 }, install)
    assert by_value.fetch("complete")
    named = input.fetch("default_install_id")
    by_type = W::Thermal.calculate(record, input, named, :default_psi_w_mk => 0.05)
    assert_equal named, by_type.fetch("elements").first.fetch("edges").first.fetch("install").fetch("id")
    refute_in_delta 0.05, by_type.fetch("elements").first.fetch("edges").first.fetch("install").fetch("psi_w_mk"), 1e-9
    dangling = W::Thermal.calculate(record, input, "psi_GONE00000000", :default_psi_w_mk => 0.05)
    assert_nil dangling.fetch("elements").first.fetch("edges").first.fetch("install").fetch("psi_w_mk")
    refute dangling.fetch("complete")
  end
end
