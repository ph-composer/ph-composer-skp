# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/window_record_fixtures"
require_relative "support/assembly_assignment_fixtures"
require_relative "support/window_convert_fixtures"

class WindowConvertTest < PhComposerTestCase
  include WindowRecordFixtures
  include AssemblyAssignmentFixtures
  include WindowConvertFixtures

  QUERY = "ph_composer.windows.units.convert_review"
  ACTION = "ph_composer.windows.units.convert"

  def setup
    super
    assignment_setup
    PhComposer::Registry.install([W]) unless PhComposer::Registry.installed?(W::FEATURE_ID)
    @next_id = 5000
  end

  def review(*paths)
    assignment_query(QUERY, "paths" => paths)
  end

  def source_of(group)
    group.fetch("sources").map { |row| row.slice("path", "digest") }
  end

  # The request a review's groups become, each group optionally carrying `extra`.
  def groups_from(result, extra = {})
    result.fetch("groups").map { |group| { "sources" => source_of(group) }.merge(extra) }
  end

  def convert(groups)
    assignment_invoke(ACTION, "groups" => groups)
  end

  def converted(groups)
    outcome = convert(groups)
    assert_equal "completed", outcome.fetch("status"), outcome.inspect
    outcome.fetch("value")
  end

  def type(id)
    assignment_query("ph_composer.windows.types.list", "ids" => [id]).fetch("records").first.fetch("values")
  end

  def types
    assignment_query("ph_composer.windows.types.list").fetch("records")
  end

  def units
    assignment_query("ph_composer.windows.units.list").fetch("units")
  end

  # The Zone Group as the Model holds it now: a native Undo restores a copy of the entities.
  def zone_group
    @model.entities.to_a.find { |entity| entity.persistent_id == @group.persistent_id }
  end

  def live_faces
    zone_group.entities.to_a.grep(Sketchup::Face)
  end

  def edge_ids(entities = zone_group.entities)
    entities.to_a.grep(Sketchup::Edge).map(&:persistent_id)
  end

  def live_host
    live_faces.find { |face| face.persistent_id == @host.persistent_id }
  end

  def test_one_rectangle_becomes_a_type_a_unit_on_its_outline_and_a_healed_host
    face = zone_with([ring(2, 1, 1.2, 1.5)]).first
    review_result = review(path(face))
    value = converted(groups_from(review_result))
    type_id = value.fetch("units").first.fetch("type_id")
    assert_equal [type_id], value.fetch("created_type_ids")
    record = type(type_id)
    assert_equal [[1.2], [1.5]], record.values_at("columns_m", "rows_m")
    assert_equal "Window 1200 x 1500", record.fetch("name")
    assert_equal [@host.persistent_id], live_faces.map(&:persistent_id)
    assert_equal 1, live_host.loops.length
    refute_includes live_faces.map(&:persistent_id), face.persistent_id
    assert_empty edge_ids & face.edges.map(&:persistent_id)
    unit = units.first
    assert_equal type_id, unit.dig("values", "window_type_id")
    assert_equal host_reference, unit.fetch("host")
    polygon = assignment_query(PhComposer::Windows::Units::Outlines::QUERY).fetch("units").first.fetch("outline_m")
    expected = ring(2, 1, 1.2, 1.5).map { |x, z| [x, 0.0, z] }
    expected.each do |point|
      assert polygon.any? { |corner| corner.zip(point).all? { |a, b| (a - b).abs < 1e-5 } }, point.inspect
    end
  end

  def test_three_rectangles_in_a_row_give_one_type_of_three_columns
    faces = zone_with([ring(1, 1, 0.6, 1.5), ring(1.6, 1, 1.2, 1.5), ring(2.8, 1, 0.6, 1.5)],
                      :holes => [ring(1, 1, 2.4, 1.5)])
    value = converted(groups_from(review(*faces.map { |face| path(face) })))
    record = type(value.fetch("units").first.fetch("type_id"))
    assert_equal [[0.6, 1.2, 0.6], [1.5]], record.values_at("columns_m", "rows_m")
    assert_equal 3, record.fetch("elements").length
    assert_equal 1, live_host.loops.length
  end

  def test_a_t_junction_gives_a_two_by_two_type_whose_tall_element_spans_both_rows
    faces = zone_with([[[1, 1], [2, 1], [2, 2], [2, 3], [1, 3]], ring(2, 1, 0.5, 1), ring(2, 2, 0.5, 1)],
                      :holes => [ring(1, 1, 1.5, 2)])
    value = converted(groups_from(review(*faces.map { |face| path(face) })))
    record = type(value.fetch("units").first.fetch("type_id"))
    assert_equal [[1.0, 0.5], [1.0, 1.0]], record.values_at("columns_m", "rows_m")
    assert_includes record.fetch("elements").map { |element| element.fetch("row_span") }, [0, 1]
    assert_equal 1, live_host.loops.length
  end

  def test_a_rectangle_outside_every_zone_converts_and_a_moved_one_is_refused_writing_nothing
    zone_with([], :holes => [])
    points = ring(5, 1, 1, 1).map { |point| inches(*point) }
    edges = points.each_with_index.map do |point, index|
      Sketchup::Edge.new(next_id, point, points[(index + 1) % points.length])
    end
    outside = Sketchup::Face.new(next_id, {}, :points => points, :edges => edges)
    neighbour = Sketchup::Face.new(next_id, {}, :points => ring(6, 1, 1, 1).map { |point| inches(*point) },
                                                :edges => [edges[1]])
    edges.each { |edge| @model.entities << edge }
    @model.entities << outside << neighbour
    review_result = review([outside.persistent_id])
    assert_empty review_result.fetch("left_out")
    groups = groups_from(review_result)
    before = @model.operations.length
    outside.transform!(Geom::Transformation.new([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 39.37, 0, 0, 1]))
    assert_equal "target.changed", convert(groups).fetch("code")
    assert_equal before, @model.operations.length
    outside.transform!(Geom::Transformation.new([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -39.37, 0, 0, 1]))
    value = converted(groups)
    assert_equal 1, value.fetch("units").length
    assert_empty @model.entities.to_a.grep(Sketchup::Face).map(&:persistent_id) & [outside.persistent_id]
    # The Edge it shares with an unconverted loose Face stays; its other three go.
    assert_equal [edges[1].persistent_id], edge_ids(@model.entities) & edges.map(&:persistent_id)
    assert_equal host_reference, units.first.fetch("host")
    assert_equal 1, live_host.loops.length
  end

  def test_four_same_size_rectangles_share_one_new_type_and_become_four_units
    faces = zone_with([ring(1, 1, 1, 1), ring(3, 1, 1, 1), ring(5, 1, 1, 1), ring(1, 3, 1, 1)],
                      :holes => [ring(1, 1, 1, 1), ring(3, 1, 1, 1), ring(5, 1, 1, 1), ring(1, 3, 1, 1)])
    value = converted(groups_from(review(*faces.map { |face| path(face) })))
    assert_equal 1, value.fetch("created_type_ids").length
    assert_equal 4, value.fetch("units").map { |unit| unit.fetch("unit_id") }.uniq.length
    assert_equal 1, value.fetch("units").map { |unit| unit.fetch("type_id") }.uniq.length
    assert_equal 4, units.length
    assert_equal 1, live_host.loops.length
    assert_equal [@host.persistent_id], live_faces.map(&:persistent_id)
  end

  def test_keeping_a_preselected_existing_type_writes_no_new_type
    faces = zone_with([ring(1, 1, 1.2, 1.5), ring(4, 1, 1.2, 1.5)],
                      :holes => [ring(1, 1, 1.2, 1.5), ring(4, 1, 1.2, 1.5)])
    existing = window_record("columns_m" => [1.2], "rows_m" => [1.5], "name" => "Existing Type")
    W::Types::KIND.store.write(@model, existing)
    result = review(*faces.map { |face| path(face) })
    value = converted(groups_from(result, "type_id" => existing.fetch("id")))
    assert_empty value.fetch("created_type_ids")
    assert_equal [existing.fetch("id")] * 2, value.fetch("units").map { |unit| unit.fetch("type_id") }
    assert_equal [@host.persistent_id], live_faces.map(&:persistent_id)
  end

  def test_an_unknown_type_id_is_refused_with_a_declared_code
    face = zone_with([ring(2, 1, 1.2, 1.5)]).first
    outcome = convert(groups_from(review(path(face)), "type_id" => "wnt_AAAAAAAAAAAB"))
    assert_equal "refused", outcome.fetch("status"), outcome.inspect
    assert_includes PhComposer::Windows::Refuses::CONVERT, outcome.fetch("code")
  end

  def test_a_chosen_type_of_another_size_or_with_a_name_is_refused
    face = zone_with([ring(2, 1, 1.2, 1.5)]).first
    other = window_record("columns_m" => [0.9], "rows_m" => [1.5], "name" => "Other")
    W::Types::KIND.store.write(@model, other)
    groups = groups_from(review(path(face)), "type_id" => other.fetch("id"))
    assert_equal "validation.failed", convert(groups).fetch("code")
    groups = groups_from(review(path(face)), "type_id" => other.fetch("id"), "name" => "Named")
    assert_equal "params.invalid", convert(groups).fetch("code")
  end

  def test_a_new_type_takes_a_given_name_and_a_taken_size_name_gets_a_suffix
    faces = zone_with([ring(1, 1, 1.2, 1.5), ring(4, 1, 1.2, 1.5)],
                      :holes => [ring(1, 1, 1.2, 1.5), ring(4, 1, 1.2, 1.5)])
    taken = window_record("columns_m" => [0.9], "rows_m" => [1.1], "name" => "Window 1200 x 1500")
    W::Types::KIND.store.write(@model, taken)
    result = review(*faces.map { |face| path(face) })
    value = converted(groups_from(result))
    assert_equal "Window 1200 x 1500 (2)", type(value.fetch("units").first.fetch("type_id")).fetch("name")
    faces = zone_with([ring(6, 3, 1, 1)])
    named = groups_from(review(path(faces.first)), "name" => "Bedroom Window")
    assert_equal "Bedroom Window", type(converted(named).fetch("units").first.fetch("type_id")).fetch("name")
  end

  def test_imperial_display_units_name_the_new_type_in_inches
    face = zone_with([ring(2, 1, 1.2, 1.5)]).first
    PhComposer::Preferences.stub(:unit_system, "IP") do
      value = converted(groups_from(review(path(face))))
      assert_equal "Window 47.2 x 59.1", type(value.fetch("units").first.fetch("type_id")).fetch("name")
    end
  end

  def test_a_group_the_review_would_not_form_is_refused_as_changed
    faces = zone_with([ring(1, 1, 0.6, 1.5), ring(1.6, 1, 1.2, 1.5)], :holes => [ring(1, 1, 1.8, 1.5)])
    result = review(*faces.map { |face| path(face) })
    sources = result.fetch("groups").first.fetch("sources").map { |row| row.slice("path", "digest") }
    assert_equal "target.changed", convert(sources.map { |source| { "sources" => [source] } }).fetch("code")
  end

  def test_a_rectangle_refused_after_the_review_refuses_with_its_own_code
    face = zone_with([ring(2, 1, 1.2, 1.5)]).first
    groups = groups_from(review(path(face)))
    @group.locked = true
    assert_equal "target.locked", convert(groups).fetch("code")
  end

  def test_a_rectangle_edge_another_face_uses_is_refused_as_touching_the_boundary
    face = zone_with([ring(2, 1, 1, 1)]).first
    shared = face.edges.first
    other = Sketchup::Face.new(next_id, {}, :points => [inches(2, 1), inches(3, 1), inches(3, 1, 1), inches(2, 1, 1)],
                                            :edges => [shared])
    @group.entities << other
    result = review(path(face))
    assert_equal %w[window.convert_on_boundary], result.fetch("left_out").map { |row| row.fetch("code") }
  end

  def test_a_preview_digest_is_accepted_when_the_conversion_is_applied
    face = zone_with([ring(2, 1, 1.2, 1.5)]).first
    groups = groups_from(review(path(face)))
    preview = API.preview(:context => @context, :name => ACTION, :params => { "groups" => groups })
    assert_equal "completed", preview.fetch("status"), preview.inspect
    assert_includes live_faces.map(&:persistent_id), face.persistent_id
    assert_equal 2, live_host.loops.length
    assert_empty units
    assert_empty types
    outcome = assignment_invoke(ACTION, { "groups" => groups }, preview.fetch("proposal_digest"))
    assert_equal "completed", outcome.fetch("status"), outcome.inspect
  end

  # H3: a rectangle drawn on an assigned Face carries a copy of the host's Face record.
  def copy_host_record_onto(*faces)
    record = { "id" => "fac_000000000099", "schema_version" => 1, "face_type" => "Wall",
               "boundary_condition" => "Outdoors", "user_data" => {}, "extension_data" => {} }
    ([@host] + faces).each { |face| AssemblyAssignmentFixtures::STORE.write(face, record) }
  end

  def test_converting_one_of_two_rectangles_each_with_the_hosts_copied_record_succeeds
    faces = zone_with([ring(1, 1, 1, 1), ring(4, 1, 1, 1)], :holes => [ring(1, 1, 1, 1), ring(4, 1, 1, 1)])
    copy_host_record_onto(*faces)
    value = converted(groups_from(review(path(faces.first))))
    assert_equal 1, value.fetch("units").length
    assert_equal 2, live_host.loops.length
    assert_includes live_faces.map(&:persistent_id), faces.last.persistent_id
    refute_includes live_faces.map(&:persistent_id), faces.first.persistent_id
    assert_equal host_reference, units.first.fetch("host")
  end

  # Faces in different Groups share no Edge, so two overlapping rectangles stay separate groups.
  def overlapping_group(left)
    points = ring(left, 1, 1.5, 1).map { |point| inches(*point) }
    edges = points.each_with_index.map do |point, index|
      Sketchup::Edge.new(next_id, point, points[(index + 1) % points.length])
    end
    face = Sketchup::Face.new(next_id, {}, :points => points, :edges => edges)
    group = Sketchup::Group.new(next_id, Sketchup::Entities.new([face] + edges))
    @model.entities << group
    [group.persistent_id, face.persistent_id]
  end

  def test_overlapping_rectangles_in_separate_groups_are_refused_and_nothing_changes
    zone_with([], :holes => [])
    paths = [overlapping_group(2), overlapping_group(3)]
    result = review(*paths)
    assert_empty result.fetch("groups"), "neither overlapping rectangle is offered"
    assert_equal [["window.overlap", [paths[0]]], ["window.overlap", [paths[1]]]],
                 result.fetch("left_out").map { |row| row.values_at("code", "paths") }
    before = @model.operations.length
    assert_equal "window.overlap", convert(paths.flat_map { |one| groups_from(review(one)) }).fetch("code")
    assert_equal before, @model.operations.length
    assert_empty units
    assert_empty types
  end

  def test_review_offers_each_size_a_default_name_and_gives_the_same_size_one
    rings = [ring(1, 1, 1.2, 1.5), ring(3, 1, 1.2, 1.5), ring(5, 1, 0.6, 1.5)]
    faces = zone_with(rings, :holes => rings)
    names = review(*faces.map { |face| path(face) }).fetch("groups").map { |group| group.fetch("default_name") }
    assert_equal ["Window 1200 x 1500", "Window 1200 x 1500", "Window 600 x 1500"], names
  end

  def test_a_second_layout_of_one_size_is_named_with_a_suffix_and_converts_under_it
    tiled = [ring(1, 1, 0.6, 1.5), ring(1.6, 1, 0.6, 1.5)]
    rings = tiled + [ring(4, 1, 1.2, 1.5)]
    faces = zone_with(rings, :holes => [ring(1, 1, 1.2, 1.5), ring(4, 1, 1.2, 1.5)])
    result = review(*faces.map { |face| path(face) })
    assert_equal ["Window 1200 x 1500", "Window 1200 x 1500 (2)"],
                 result.fetch("groups").map { |group| group.fetch("default_name") }
    names = converted(groups_from(result)).fetch("units").map { |row| type(row.fetch("type_id")).fetch("name") }
    assert_equal ["Window 1200 x 1500", "Window 1200 x 1500 (2)"], names
  end

  # A clear group keeps its place beside an overlapping pair; a rectangle on a parallel plane overlaps nothing.
  def test_only_the_overlapping_groups_are_left_out
    zone_with([], :holes => [])
    crossing = [overlapping_group(2), overlapping_group(3)]
    clear = overlapping_group(6)
    result = review(*crossing, clear)
    assert_equal [[clear]],
                 result.fetch("groups").map { |group| group.fetch("sources").map { |row| row.fetch("path") } }
    assert_equal crossing.map { |one| [one] }, result.fetch("left_out").map { |row| row.fetch("paths") }
  end

  # A stored Window Type to Copy from: its one element's kind and operation as given.
  def copy_type(name, kind: "glazed", operation: nil)
    id = assignment_invoke("ph_composer.windows.types.create", "values" => { "name" => name })
         .fetch("value").fetch("id")
    return id if kind == "glazed" && operation.nil?

    update_type(id, "elements" => [type(id).fetch("elements").first.merge("kind" => kind, "operation" => operation)])
    id
  end

  def update_type(id, values)
    updated = assignment_invoke("ph_composer.windows.types.update", "id" => id, "values" => values,
                                                                    "expected_values" => type(id))
    assert_equal "completed", updated.fetch("status"), updated.inspect
  end

  def product(kind, name)
    assignment_invoke("ph_composer.windows.#{kind}.create", "values" => { "name" => name }).fetch("value").fetch("id")
  end

  # A Type of two columns, the first element empty and the second glazed with `properties`.
  def template_type(properties)
    id = assignment_invoke("ph_composer.windows.types.create", "values" => { "name" => "Template" })
         .fetch("value").fetch("id")
    first = type(id).fetch("elements").first.merge("kind" => "empty")
    second = W::Types.blank(0, 1).merge(properties)
    update_type(id, "columns_m" => [0.5, 0.5], "elements" => [first, second])
    id
  end

  def test_copy_from_gives_every_element_the_first_glazed_elements_properties
    sides = W::Types::SIDES
    properties = { "glazing_id" => product("glazings", "Triple"),
                   "frames" => sides.to_h { |side| [side, product("frames", "Frame #{side}")] },
                   "installs" => sides.to_h { |side| [side, product("psi_install_types", "Install #{side}")] },
                   "operation" => { "type" => "swing", "directions" => ["left"] } }
    source = template_type(properties)
    before = type(source)
    faces = zone_with([ring(1, 1, 0.6, 1.5), ring(1.6, 1, 0.6, 1.5)], :holes => [ring(1, 1, 1.2, 1.5)])
    value = converted(groups_from(review(*faces.map { |face| path(face) }), "copy_from_type_id" => source))
    elements = type(value.fetch("units").first.fetch("type_id")).fetch("elements")
    assert_equal 2, elements.length
    elements.each do |element|
      copied = properties.reject { |key, _value| key == "installs" }
      assert_equal copied, element.slice(*copied.keys)
      assert_equal "glazed", element.fetch("kind")
    end
    assert_equal elements.map { |element| element.fetch("id") }.uniq, elements.map { |element| element.fetch("id") }
    assert_equal before, type(source), "Copy from leaves its source as it was"
  end

  # A mull's sides interior to the group are not installs, across both a mullion and a transom.
  def test_copy_from_puts_installs_on_a_mulls_perimeter_sides_only
    sides = W::Types::SIDES
    installs = sides.to_h { |side| [side, product("psi_install_types", "Install #{side}")] }
    frames = sides.to_h { |side| [side, product("frames", "Frame #{side}")] }
    source = template_type("glazing_id" => product("glazings", "Triple"), "frames" => frames, "installs" => installs)
    faces = zone_with([[[1, 1], [2, 1], [2, 2], [2, 3], [1, 3]], ring(2, 1, 0.5, 1), ring(2, 2, 0.5, 1)],
                      :holes => [ring(1, 1, 1.5, 2)])
    value = converted(groups_from(review(*faces.map { |face| path(face) }), "copy_from_type_id" => source))
    elements = type(value.fetch("units").first.fetch("type_id")).fetch("elements")
    perimeter = { [[0, 1], [0, 0]] => %w[top bottom left], [[0, 0], [1, 1]] => %w[top right],
                  [[1, 1], [1, 1]] => %w[right bottom] }
    assert_equal perimeter.keys.sort, elements.map { |element| element.values_at("row_span", "column_span") }.sort
    elements.each do |element|
      kept = perimeter.fetch(element.values_at("row_span", "column_span"))
      assert_equal sides.to_h { |side| [side, kept.include?(side) ? installs.fetch(side) : nil] },
                   element.fetch("installs")
      assert_equal frames, element.fetch("frames"), "frames still copy to every side"
    end
  end

  def test_copy_from_without_a_glazed_element_or_beside_a_chosen_type_is_refused
    empty = copy_type("Empty", :kind => "empty")
    face = zone_with([ring(2, 1, 1.2, 1.5)]).first
    groups = groups_from(review(path(face)), "copy_from_type_id" => empty)
    assert_equal "validation.failed", convert(groups).fetch("code")
    glazed = copy_type("Glazed", :operation => nil)
    groups = groups_from(review(path(face)), "copy_from_type_id" => glazed, "type_id" => glazed)
    assert_equal "params.invalid", convert(groups).fetch("code")
    assert_equal "target.not_found",
                 convert(groups_from(review(path(face)), "copy_from_type_id" => "wnt_#{"Z" * 12}")).fetch("code")
  end

  def test_groups_sharing_a_new_type_take_one_copy_from
    first = copy_type("First", :operation => nil)
    second = copy_type("Second", :operation => nil)
    rings = [ring(1, 1, 1.2, 1.5), ring(3, 1, 1.2, 1.5)]
    faces = zone_with(rings, :holes => rings)
    groups = groups_from(review(*faces.map { |face| path(face) }))
    groups[0]["copy_from_type_id"] = first
    groups[1]["copy_from_type_id"] = second
    assert_equal "params.invalid", convert(groups).fetch("code")
  end

  # A failure after the rectangles are erased: the operation aborts, so nothing of the conversion remains.
  def test_a_failure_between_erase_and_placement_aborts_and_leaves_the_model_as_it_was
    rings = [ring(1, 1, 1.2, 1.5), ring(3, 1, 1.2, 1.5)]
    faces = zone_with(rings, :holes => rings)
    result = review(*faces.map { |face| path(face) })
    placed = 0
    add_glued = W::Units::NativeUnit.method(:add_glued!)
    failing = lambda do |*args|
      placed += 1
      raise PhComposer::CodedError.new("geometry.failed", "The Window could not be placed.") if placed == 2

      add_glued.call(*args)
    end
    outcome = W::Units::NativeUnit.stub(:add_glued!, failing) { convert(groups_from(result)) }
    assert_equal "rolled_back", outcome.fetch("effect"), outcome.inspect
    assert_equal "geometry.failed", outcome.dig("detail", "cause")
    assert_equal 2, placed, "it fails on the second placement, after the erase and a first Unit"
    assert_equal :aborted, @model.operations.last[2]
    assert_equal faces.map(&:persistent_id).sort, (live_faces.map(&:persistent_id) - [@host.persistent_id]).sort
    assert_equal 3, live_host.loops.length
    assert_empty units
    assert_empty types
    assert_empty(@model.definitions.to_a.select { |item| item.name.start_with?("PhComposer_Window_") })
    assert_empty W::Units::DefinitionIndex.read(@model)
  end

  def test_one_native_undo_restores_every_rectangle_and_removes_each_new_type_and_unit_then_redo_converts_again
    face = zone_with([ring(2, 1, 1.2, 1.5)]).first
    converted(groups_from(review(path(face))))
    assert_equal 1, @model.operations.count { |row| row[2] == :committed && row[0] == "Convert to Window Type" }
    assert @model.undo
    assert_includes live_faces.map(&:persistent_id), face.persistent_id
    assert_equal 2, live_host.loops.length
    assert_empty units
    assert_empty types
    assert_equal [], @model.definitions.to_a.select { |item| item.name.start_with?("PhComposer_Window_") }
    assert @model.redo
    assert_equal 1, units.length
    assert_equal 1, types.length
    assert_equal 1, live_host.loops.length
  end
end
