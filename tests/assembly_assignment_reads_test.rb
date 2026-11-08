# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/assembly_assignment_fixtures"

class AssemblyAssignmentReadsTest < PhComposerTestCase
  include AssemblyAssignmentFixtures

  def setup
    super
    assignment_setup
  end

  def test_usage_includes_nested_and_repeated_definition_occurrences_with_gross_area
    id = assignment_assembly("Usage")
    assignment_zone(100, 2)
    group, entities = assignment_zone(200, 1, :nested => true)
    assignment_invoke("#{FACE_PREFIX}.assign_assembly", assignment_params(assignment_faces, id))
    group.entities << Sketchup::Group.new(250, group.entities.to_a.first.entities,
                                          :transformation => Geom::Transformation.scaling(2))
    read = assignment_query("#{FACE_PREFIX}.all")
    rows = read.fetch("faces")
    usage = read.fetch("assembly_usage").first
    assert_equal 4, usage.fetch("face_count")
    assert_in_delta rows.sum { |row| row.fetch("area_m2") }, usage.fetch("gross_area_m2"), 1.0e-9
    assert_in_delta 7 * 0.5 * 100 * 100 * 0.0254**2, usage.fetch("gross_area_m2"), 1.0e-9
    assert_equal rows.map { |row| row.fetch("reference") }, usage.fetch("faces")
    assert_equal read.fetch("assembly_usage"), assignment_query("#{FACE_PREFIX}.assembly_usage").fetch("assemblies")
    refute_nil STORE.read(entities.first)
  end

  def test_hint_mismatches_name_only_the_authored_side_and_a_broken_pair_is_named_on_both
    rows = assignment_pair(300)
    first = assignment_assembly("First", "type" => "Floor", "exterior_condition" => "Ground")
    second = assignment_assembly("Second", "type" => "Wall", "exterior_condition" => "Outdoors")
    assignment_invoke("#{FACE_PREFIX}.assign_assembly", assignment_params([rows.first], first))
    rows = assignment_faces
    assert_equal %w[face.assembly_type_mismatch face.assembly_exterior_condition_mismatch],
                 rows.first.fetch("findings").map { |finding| finding.fetch("code") }
    assert_empty rows.last.fetch("findings"), "the reversed side holds the Assembly from the other Zone"
    entity = assignment_entity(rows.last)
    STORE.write(entity, STORE.read(entity).merge("assembly_id" => second).tap { |row| row.delete("assembly_reversed") })
    rows = assignment_faces
    assert_includes rows.first.fetch("findings").map { |finding| finding.fetch("code") }, "face.assembly_pair_mismatch"
    assert_equal %w[face.assembly_exterior_condition_mismatch face.assembly_pair_mismatch],
                 rows.last.fetch("findings").map { |finding| finding.fetch("code") }
    assert rows.all? { |row| row.fetch("adjacency_state") == "current" }

    result = assignment_invoke("#{FACE_PREFIX}.assign_assembly", assignment_params([rows.first], first))
    assert_equal "completed", result.fetch("status"), result.inspect
    assert_equal [[first, nil], [first, true]], pair_values, "assigning the same Assembly again repairs the pair"
  end

  def test_assigning_one_side_of_a_pair_gives_the_other_side_the_assembly_reversed
    rows = assignment_pair(350)
    id = assignment_assembly("One side")
    result = assignment_invoke("#{FACE_PREFIX}.assign_assembly", assignment_params([rows.first], id))
    assert_equal "completed", result.fetch("status"), result.inspect
    assert_equal [[id, nil], [id, true]], pair_values
    assert(assignment_faces.all? { |row| row.fetch("findings").empty? })

    assignment_invoke("#{FACE_PREFIX}.assign_assembly", assignment_params([assignment_faces.last], id))
    assert_equal [[id, true], [id, nil]], pair_values, "the side a gesture names becomes the authored side"

    assignment_invoke("#{FACE_PREFIX}.assign_assembly", assignment_params([assignment_faces.first], nil))
    assert_equal [[nil, nil], [nil, nil]], pair_values, "clearing one side clears the pair"
  end

  def test_classify_and_both_sides_in_one_gesture_keep_one_authored_side
    assignment_pair(370)
    id = assignment_assembly("Classified")
    assignment_classify(assignment_faces.reverse, assembly_intent(id))
    assert_equal [[id, true], [id, nil]], pair_values, "the first Face named is the authored side"
  end

  def test_solving_a_pair_whose_sides_share_an_assembly_settles_it_reversed_on_one_side
    rows = assignment_pair(380)
    id = assignment_assembly("Shared before solving")
    assignment_invoke("#{FACE_PREFIX}.assign_assembly", assignment_params([rows.first], id))
    outdoors = { "boundary_condition" => { "mode" => "set", "value" => "Outdoors" } }
    assert_equal "completed", assignment_classify(assignment_faces, outdoors).fetch("status")
    assert_equal [[id, nil], [id, nil]], pair_values, "retiring a pair keeps each side's Assembly"
    zones = assignment_query("ph_composer.zones.list").fetch("zones")
    solved = assignment_invoke("ph_composer.zones.solve_adjacency",
                               "zones" => zones.map { |zone| zone.fetch("reference") })
    assert_equal "completed", solved.fetch("status"), solved.inspect
    assert_equal [id, id], pair_values.map(&:first)
    assert_equal 1, pair_values.count { |_id, reversed| reversed }
    assert(assignment_faces.all? { |row| row.fetch("findings").empty? })
  end

  def pair_values
    assignment_faces.map { |row| row.fetch("values").values_at("assembly_id", "assembly_reversed") }
  end

  def assignment_entity(row)
    group = @model.entities.to_a.find { |entity| entity.persistent_id == row.dig("reference", "zone_path").last }
    group.entities.to_a.find { |entity| entity.persistent_id == row.dig("reference", "entity_path").last }
  end

  def test_colour_mode_uses_effective_read_colour_and_marks_absent_and_dangling
    _group, entities = assignment_zone(400, 3)
    id = assignment_assembly("Colour", "color" => "#123456")
    assignment_invoke("#{FACE_PREFIX}.assign_assembly", assignment_params([assignment_faces.first], id))
    STORE.write(entities.last, "id" => "fac_000000000099", "schema_version" => 1,
                               "assembly_id" => "asm_000000000099")
    declaration = PhComposer::Registry.current.colour_modes.fetch("#{FACE_PREFIX}.by_assembly")
    entries = declaration.projection.call(read(declaration))
    assert_equal "Colour", entries.first.label
    assert_equal [18, 52, 86], entries.first.colour
    assert_equal id, entries.first.value, "the legend's key is the Assembly id"
    assert_nil entries[1].value
    assert_nil entries[1].state
    assert_equal :incomplete, entries.last.state
  end

  def test_choose_accepts_assembly_with_null_keep_and_missing_choice_refuses
    id = assignment_assembly("Paint")
    chosen = API.view(:context => @context, :name => "#{FACE_PREFIX}.choose",
                      :params => { "field" => "assembly_id", "value" => id })
    assert_equal "completed", chosen.fetch("status"), chosen.inspect
    assert_equal id, chosen.dig("value", "palette", "assembly_id")
    missing = API.view(:context => @context, :name => "#{FACE_PREFIX}.choose",
                       :params => { "field" => "assembly_id", "value" => "asm_000000000099" })
    assert_equal %w[refused reference.invalid], missing.values_at("status", "code")
    kept = API.view(:context => @context, :name => "#{FACE_PREFIX}.choose",
                    :params => { "field" => "assembly_id", "value" => nil })
    refute kept.fetch("value").fetch("palette").key?("assembly_id")
  end

  def test_selection_menu_reads_targets_and_matching_type_first_then_calls_reassignment
    group, entities = assignment_zone(500)
    assignment_classify(assignment_faces, "face_type" => { "mode" => "set", "value" => "Wall" })
    assignment_assembly("A floor", "type" => "Floor")
    wall = assignment_assembly("Z wall", "type" => "Wall")
    @model.active_path = [group]
    @model.selection.add(entities.first)
    selection = assignment_query("#{FACE_PREFIX}.selection")
    assert_equal assignment_faces.first.fetch("values"), selection.fetch("targets").first.fetch("expected_values")
    menu = PhComposer::Registry.current.menu_items.fetch("#{FACE_PREFIX}.assembly_menu")
    entries = menu.entries.call(read(menu))
    assert_equal "Z wall", entries.first.label
    entries.first.handler.call(@session)
    assert_equal wall, STORE.read(entities.first).fetch("assembly_id")
    assert_equal "Wall", STORE.read(entities.first).fetch("face_type")
    refute STORE.read(entities.first).key?("boundary_condition")
  end

  private

  def read(declaration)
    PhComposer::HandlerRequest.for(@session, :owner => declaration.owner, :name => declaration.name)
  end
end
