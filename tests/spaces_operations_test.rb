# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/space_fixtures"

class SpacesOperationsTest < PhComposerTestCase
  include SpaceFixtures

  API = PhComposer::API
  ROTATION = Geom::Transformation.new([0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 5, 0, 0, 1])

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
  end

  # Zone Z under a rotated wrapper, holding two loose floor outlines and one classified wall.
  def zone_with_outlines
    @living = floor_face(101, rectangle(0, 0, 3, 4))
    @bath = floor_face(102, rectangle(3, 0, 2, 2))
    @zone_group = zone_group(100, "Z", [@living, @bath])
    @wrapper = Sketchup::Group.new(90, Sketchup::Entities.new([@zone_group]), :transformation => ROTATION)
    @model.entities << @wrapper
    @zone = query("ph_composer.zones.list").dig("zones", 0, "reference")
    @model.active_path = [@wrapper, @zone_group]
  end

  def face_path(face)
    @zone.fetch("zone_path") + [face.persistent_id]
  end

  def create(faces, **extra)
    invoke("ph_composer.spaces.create", { "zone" => @zone, "faces" => faces.map { |face| face_path(face) } }
      .merge(extra))
  end

  def spaces
    query("ph_composer.spaces.all").fetch("spaces")
  end

  def test_create_groups_faces_into_a_space_under_a_rotated_wrapper_in_one_undo_step
    zone_with_outlines
    before = @model.operations.length
    result = create([@living], "name" => "Living")
    assert_equal "completed", result["status"], result.inspect
    assert_equal before + 1, @model.operations.length
    row = spaces.first
    assert_equal({ "zone_id" => "zon_ZZZZZZZZZZZZ", "zone_path" => [90, 100] }, row["zone"])
    assert_equal %w[1 Living 2.5], [row.dig("values", "number"), row.dig("values", "name"),
                                    row.dig("values", "default_height_m").to_s]
    assert_in_delta 12.0, row.dig("metrics", "floor_area_m2"), 1e-9
    assert_in_delta 30.0, row.dig("metrics", "net_volume_m3"), 1e-9
    segment = row.dig("volumes", 0, "floor_segments", 0)
    assert_equal 101, segment.dig("reference", "entity_path").last
    space_group = space_groups_in(@wrapper).first
    assert_nil PhComposer::Zones::STAMP_STORE.read(space_group), "hosted by its record alone"
    assert_equal "1 Living", space_group.name
    faces = query("ph_composer.zones.faces.list").fetch("faces").map { |face| face.dig("reference", "entity_path") }
    assert_equal [[102]], faces, "the Floor Segment is no longer a Zone Face"
    second = create([@bath])
    assert_equal "completed", second["status"], second.inspect
    assert_equal %w[1 2], spaces.map { |space| space.dig("values", "number") }
  end

  def space_groups_in(container)
    container.entities.to_a.select { |entity| PhComposer::Spaces::SPACE_STORE.read(entity) }
  end

  # W6-2: at the same world position, in the Zone's parent, one Undo step, the Zone's other Faces untouched.
  def test_create_in_an_open_zone_places_the_space_outside_it_at_the_same_world_position
    zone_with_outlines
    @zone_group.transformation = Geom::Transformation.translation([2, 3, 4])
    operations = @model.operations.length
    result = create([@living])
    assert_equal "completed", result["status"], result.inspect
    assert_equal operations + 1, @model.operations.length
    assert_empty space_groups_in(@zone_group), "nothing nests"
    placed = space_groups_in(@wrapper).first
    assert_equal @zone_group.transformation.to_a, placed.transformation.to_a
    row = spaces.first
    assert_equal [90, placed.persistent_id], row.dig("reference", "entity_path")
    assert_equal({ "zone_id" => "zon_ZZZZZZZZZZZZ", "zone_path" => [90, 100] }, row["zone"])
    assert_equal [102], @zone_group.entities.to_a.grep(Sketchup::Face).map(&:persistent_id), "the other Face stays"
    assert_equal [90, 100], Array(@model.active_path).map(&:persistent_id), "the Zone stays open"
    assert @model.undo
    assert_empty spaces, "one Undo takes the Space back"
    faces = query("ph_composer.zones.faces.list").fetch("faces").map { |face| face.dig("reference", "entity_path") }
    assert_equal [[101], [102]], faces.sort, "and the outline is a loose Face of the Zone again"
  end

  # The open Zone is only preselected: the Space stands outside it whichever Zone, or none, the review picks.
  def test_create_in_an_open_zone_hosts_the_space_in_whichever_zone_is_named
    zone_with_outlines
    @wrapper.entities << zone_group(200, "O", [])
    other = { "zone_id" => "zon_OOOOOOOOOOOO", "zone_path" => [90, 200] }
    assert_equal "completed", create([@living], "zone" => other)["status"]
    assert_equal "completed", create([@bath], "zone" => nil)["status"]
    assert_equal [other, nil], spaces.map { |row| row["zone"] }
    assert_equal 2, space_groups_in(@wrapper).length
  end

  def test_create_at_the_root_stays_at_the_root_hosted_in_the_zone_named_or_in_none
    zone_with_outlines
    @model.active_path = nil
    root_face = floor_face(801, rectangle(20, 0, 2, 2))
    other_face = floor_face(802, rectangle(30, 0, 2, 2))
    @model.entities << root_face << other_face
    hosted = invoke("ph_composer.spaces.create", "faces" => [[801]], "zone" => @zone)
    assert_equal "completed", hosted["status"], hosted.inspect
    unhosted = invoke("ph_composer.spaces.create", "faces" => [[802]], "zone" => nil)
    assert_equal "completed", unhosted["status"], unhosted.inspect
    rows = spaces.sort_by { |row| row.dig("reference", "entity_path") }
    assert(rows.all? { |row| row.dig("reference", "entity_path").length == 1 }, "both at the root")
    assert_equal [{ "zone_id" => "zon_ZZZZZZZZZZZZ", "zone_path" => [90, 100] }, nil], rows.map { |row| row["zone"] }
    assert_equal %w[1 1], rows.map { |row| row.dig("values", "number") }, "numbered within each host"
  end

  def test_create_in_an_open_plain_group_stays_in_that_group
    storey_face = floor_face(801, rectangle(0, 0, 2, 2))
    storey = Sketchup::Group.new(700, Sketchup::Entities.new([storey_face]))
    @model.entities << storey
    @model.active_path = [storey]
    result = invoke("ph_composer.spaces.create", "faces" => [[700, 801]])
    assert_equal "completed", result["status"], result.inspect
    assert_equal 1, space_groups_in(storey).length
    assert_nil spaces.first["zone"]
  end

  # W6-4: the user's active tag and the Model's tags are not Create Space's business.
  def test_a_new_space_and_its_volume_are_untagged_and_no_tag_is_created
    zone_with_outlines
    @model.active_layer = @model.layers.add("01_GEOM")
    count = @model.layers.count
    assert_equal "completed", create([@living])["status"]
    space = space_groups_in(@wrapper).first
    assert_equal "Layer0", space.layer.name
    assert_equal ["Layer0"], space.entities.to_a.map { |volume| volume.layer.name }
    assert_equal count, @model.layers.count
  end

  # Every route that makes or moves a Space leaves its Group outside every Zone Group.
  def test_no_route_leaves_a_space_inside_a_zone
    zone_with_outlines
    other = zone_group(200, "O", [])
    @wrapper.entities << other
    assert_equal "completed", create([@living])["status"]
    moved = invoke("ph_composer.spaces.move_to_zone",
                   "space" => spaces.first.fetch("reference"),
                   "zone" => { "zone_id" => "zon_OOOOOOOOOOOO", "zone_path" => [90, 200] })
    assert_equal "completed", moved["status"], moved.inspect
    assert_empty space_groups_in(@zone_group)
    assert_empty space_groups_in(other)
    plain = Sketchup::Group.new(104, Sketchup::Entities.new([floor_face(105, rectangle(0, 7, 1, 1))]))
    @zone_group.entities << plain
    @model.active_path = [@wrapper, @zone_group, plain]
    result = invoke("ph_composer.spaces.create", "faces" => [[90, 100, 104, 105]])
    assert_equal %w[refused space.nothing_to_create], result.values_at("status", "code"), "a Group within a Zone"
    zones = query("ph_composer.zones.list").fetch("zones").map { |row| row.dig("reference", "zone_path") }
    spaces.each do |row|
      path = row.dig("reference", "entity_path")
      refute(zones.any? { |zone_path| path[0, zone_path.length] == zone_path }, "#{path} is inside a Zone")
    end
  end

  def test_create_refuses_inside_a_space_and_through_a_lock_or_shared_storage
    zone_with_outlines
    assert_equal "completed", create([@living])["status"]
    space = space_groups_in(@wrapper).first
    loose = floor_face(801, rectangle(9, 9, 1, 1))
    space.entities << loose
    @model.active_path = [@wrapper, space]
    preview = query("ph_composer.spaces.create_preview", "faces" => [[90, space.persistent_id, 801]])
    assert_equal %w[in_space], preview.fetch("left_out").map { |row| row["reason"] }
    @model.active_path = [@wrapper]
    @wrapper.locked = true
    loose_here = floor_face(802, rectangle(9, 9, 1, 1))
    @wrapper.entities << loose_here
    preview = query("ph_composer.spaces.create_preview", "faces" => [[90, 802]])
    assert_equal %w[locked], preview.fetch("left_out").map { |row| row["reason"] }
  end

  def test_create_in_a_zone_at_the_root_places_the_space_at_the_root
    @model.entities << zone_group(100, "Z", [floor_face(101, rectangle(0, 0, 2, 2)),
                                             floor_face(102, rectangle(3, 0, 1, 1))])
    zone = @model.entities.to_a.first
    zone.transformation = Geom::Transformation.translation([2, 3, 4])
    @model.active_path = [zone]
    result = invoke("ph_composer.spaces.create", "faces" => [[100, 101]],
                                                 "zone" => { "zone_id" => "zon_ZZZZZZZZZZZZ", "zone_path" => [100] })
    assert_equal "completed", result["status"], result.inspect
    placed = space_groups_in(@model).first
    assert_equal zone.transformation.to_a, placed.transformation.to_a
    assert_empty space_groups_in(zone)
  end

  def test_create_preview_preselects_through_a_rotated_parent_and_a_translated_zone
    faces = [floor_face(101, rectangle(0, 0, 4, 4)), floor_face(102, rectangle(0, 0, 4, 4, 3))]
    zone = zone_group(100, "Z", faces, :transformation => Geom::Transformation.translation([1, 0, 0]))
    wrapper = Sketchup::Group.new(90, Sketchup::Entities.new([zone]), :transformation => ROTATION)
    # ROTATION turns plan (x, y) to (-y, x), so this Zone stands at about x -4 to 0 and y 0 to 4 in world metres.
    inside = floor_face(801, rectangle(-3, 2, 1, 1, 1))
    outside = floor_face(802, rectangle(2, 2, 1, 1, 1))
    @model.entities << wrapper << inside << outside
    zone_reference = { "zone_id" => "zon_ZZZZZZZZZZZZ", "zone_path" => [90, 100] }
    assert_equal zone_reference, query("ph_composer.spaces.create_preview", "faces" => [[801]]).fetch("zone")
    assert_nil query("ph_composer.spaces.create_preview", "faces" => [[802]]).fetch("zone")
  end

  # A Zone's envelope may stand in a plain component; a cutting component's geometry is not the Zone's.
  def test_create_preview_reads_a_zones_faces_inside_a_component_but_not_a_cutting_one
    envelope = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([floor_face(111, rectangle(0, 0, 10, 10)),
                                                                         floor_face(112, rectangle(0, 0, 10, 10, 3))]))
    cutting = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([floor_face(121, rectangle(40, 0, 10, 10))]))
    cutting.behavior.cuts_opening = true
    @model.entities << zone_group(100, "Z", [Sketchup::ComponentInstance.new(110, envelope),
                                             Sketchup::ComponentInstance.new(120, cutting)])
    held = floor_face(801, rectangle(2, 2, 2, 2, 1))
    over_the_cutter = floor_face(802, rectangle(42, 2, 2, 2, 1))
    @model.entities << held << over_the_cutter
    assert_equal({ "zone_id" => "zon_ZZZZZZZZZZZZ", "zone_path" => [100] },
                 query("ph_composer.spaces.create_preview", "faces" => [[801]]).fetch("zone"))
    assert_nil query("ph_composer.spaces.create_preview", "faces" => [[802]]).fetch("zone")
  end

  # W6-3: the footprint under the outline's centroid and the height range around it decide; nothing else does.
  def test_create_preview_preselects_the_zone_holding_the_outline_or_none
    @model.entities << zone_group(100, "Z", [floor_face(101, rectangle(0, 0, 10, 10)),
                                             floor_face(102, rectangle(0, 0, 10, 10, 3))])
    inside = floor_face(801, rectangle(2, 2, 2, 2, 1))
    beside = floor_face(802, rectangle(20, 2, 2, 2, 1))
    above = floor_face(803, rectangle(2, 2, 2, 2, 5))
    @model.entities << inside << beside << above
    zone = { "zone_id" => "zon_ZZZZZZZZZZZZ", "zone_path" => [100] }
    assert_equal zone, query("ph_composer.spaces.create_preview", "faces" => [[801]]).fetch("zone")
    assert_nil query("ph_composer.spaces.create_preview", "faces" => [[802]]).fetch("zone")
    assert_nil query("ph_composer.spaces.create_preview", "faces" => [[803]]).fetch("zone")
  end

  def test_create_preview_names_each_left_out_face_and_writes_nothing
    zone_with_outlines
    classified = floor_face(103, rectangle(0, 5, 1, 1))
    PhComposer::Zones::Faces::FACE_STORE.write(classified, { "id" => "fac_CCCCCCCCCCCC", "schema_version" => 1,
                                                             "face_type" => "Floor" })
    nested = floor_face(105, rectangle(0, 7, 1, 1))
    edge = Sketchup::Edge.new(200, Geom::Point3d.new(7 * INCHES, 0, 0), Geom::Point3d.new(7 * INCHES, INCHES, 0))
    left, right = [[106, 6], [107, 7]].map do |id, x|
      points = rectangle(x, 0, 1, 1).map { |px, py, pz| Geom::Point3d.new(px * INCHES, py * INCHES, pz * INCHES) }
      Sketchup::Face.new(id, {}, :points => points, :edges => [edge])
    end
    @zone_group.entities << classified << Sketchup::Group.new(104, Sketchup::Entities.new([nested])) << left << right
    before = @model.operations.length
    params = { "faces" => [face_path(@living), face_path(left), face_path(classified), [90, 100, 104, 105], [1]] }
    preview = query("ph_composer.spaces.create_preview", params)
    assert_equal [[90, 100, 101]], preview.fetch("accepted")
    assert_equal %w[classified not_loose not_loose shares_edge],
                 preview.fetch("left_out").map { |row| row["reason"] }.sort
    assert_equal @zone, preview.fetch("zone"), "the open Zone is preselected"
    assert_in_delta 2.5, preview.fetch("height_m"), 1e-9
    assert_equal before, @model.operations.length
    assert_empty spaces
  end

  def test_create_refuses_outside_the_zone_context_and_with_nothing_to_take
    zone_with_outlines
    @model.active_path = nil
    assert_equal %w[refused space.context_required], create([@living]).values_at("status", "code")
    @model.active_path = [@wrapper, @zone_group]
    stamped = floor_face(108, rectangle(0, 9, 1, 1), segment_record("Q"))
    @zone_group.entities << stamped
    assert_equal %w[refused space.nothing_to_create], create([stamped]).values_at("status", "code")
    assert_empty spaces
  end

  def test_a_second_volume_adds_its_net_volume_and_the_space_counts_on
    zone_with_outlines
    create([@living])
    space_group = @wrapper.entities.to_a.find { |entity| PhComposer::Spaces::SPACE_STORE.read(entity) }
    hall = floor_face(109, rectangle(0, 4, 1, 2))
    space_group.entities << hall
    @model.active_path = [@wrapper, space_group]
    space = spaces.first.fetch("reference")
    result = invoke("ph_composer.spaces.volumes.create",
                    "space" => space, "faces" => [space.fetch("entity_path") + [109]], "weighting_factor" => 0.0)
    assert_equal "completed", result["status"], result.inspect
    row = spaces.first
    assert_equal [1, 2], row.fetch("volumes").map { |volume| volume.dig("values", "number") }
    assert_equal 3, row.dig("values", "next_volume_sequence")
    assert_in_delta 35.0, row.dig("metrics", "net_volume_m3"), 1e-9
    assert_in_delta 12.0, row.dig("metrics", "weighted_area_m2"), 1e-9
  end

  def test_airflows_set_clear_and_a_stale_or_unknown_edit_refuses_with_nothing_written
    zone_with_outlines
    create([@living])
    row = spaces.first
    set = edit(row, { "v_sup_m3h" => 60.0, "v_eta_m3h" => 0.0 }, {})
    assert_equal "completed", set["status"], set.inspect
    assert_equal "user_specified", spaces.first["airflow_mode"]
    clear = edit(spaces.first, { "v_sup_m3h" => nil, "v_eta_m3h" => nil },
                 { "v_sup_m3h" => 60.0, "v_eta_m3h" => 0.0 })
    assert_equal "completed", clear["status"], clear.inspect
    assert_equal "inheriting", spaces.first["airflow_mode"]
    stale = edit(spaces.first, { "name" => "Kitchen" }, { "name" => "Other" })
    assert_equal %w[refused target.changed], stale.values_at("status", "code")
    unknown = edit(spaces.first, { "next_volume_sequence" => 9 }, {})
    assert_equal %w[refused params.invalid], unknown.values_at("status", "code")
  end

  def test_a_batch_with_one_stale_target_writes_none_and_a_height_edit_records_the_last_height
    zone_with_outlines
    create([@living])
    create([@bath])
    first, second = spaces
    batch = invoke("ph_composer.spaces.batch_update", "edits" => [
      { "reference" => first.fetch("reference"), "values" => { "name" => "A" },
        "expected_values" => { "name" => "" } },
      { "reference" => second.fetch("reference"), "values" => { "name" => "B" },
        "expected_values" => { "name" => "stale" } }
    ])
    assert_equal %w[refused target.changed], batch.values_at("status", "code")
    assert_equal ["", ""], spaces.map { |row| row.dig("values", "name") }
    volume = first.dig("volumes", 0)
    height = invoke("ph_composer.spaces.update", "reference" => volume.fetch("reference"),
                                                 "values" => { "avg_ceiling_height_m" => 2.7 },
                                                 "expected_values" => { "avg_ceiling_height_m" => 2.5 })
    assert_equal "completed", height["status"], height.inspect
    assert_equal 2.7, query("ph_composer.spaces.settings.get")["last_height_m"]
    third = floor_face(110, rectangle(6, 6, 1, 1))
    @zone_group.entities << third
    create([third])
    assert_equal 2.7, spaces.last.dig("values", "default_height_m")
  end

  def test_floors_mark_update_and_unmark_keep_the_face
    zone_with_outlines
    create([@living])
    volume = spaces.first.dig("volumes", 0)
    extra = floor_face(111, rectangle(0, 4, 1, 1))
    volume_group = @wrapper.entities.to_a.find { |entity| PhComposer::Spaces::SPACE_STORE.read(entity) }
                           .entities.to_a.first
    volume_group.entities << extra
    path = volume.dig("reference", "entity_path") + [111]
    marked = invoke("ph_composer.spaces.floors.mark", "faces" => [path], "weighting_factor" => 0.6)
    assert_equal "completed", marked["status"], marked.inspect
    segment = spaces.first.dig("volumes", 0, "floor_segments").find { |row|
      row.dig("reference", "entity_path") == path
    }
    assert_equal 0.6, segment.dig("values", "weighting_factor")
    factor = invoke("ph_composer.spaces.update", "reference" => segment.fetch("reference"),
                                                 "values" => { "net_area_factor" => 0.9 },
                                                 "expected_values" => { "net_area_factor" => 1.0 })
    assert_equal "completed", factor["status"], factor.inspect
    unmarked = invoke("ph_composer.spaces.floors.unmark", "floor_segments" => [segment.fetch("reference")])
    assert_equal "completed", unmarked["status"], unmarked.inspect
    assert_nil PhComposer::Spaces::FLOOR_SEGMENT_STORE.read(extra)
    assert volume_group.entities.include?(extra)
  end

  def test_metadata_survives_edits_and_a_stale_metadata_write_refuses
    zone_with_outlines
    create([@living])
    reference = spaces.first.fetch("reference")
    written = invoke("ph_composer.spaces.update_metadata", "updates" => [{
      "reference" => reference, "user_data" => { "example" => { "note" => "kept" } },
      "expected_metadata" => { "user_data" => {}, "extension_data" => {} }
    }])
    assert_equal "completed", written["status"], written.inspect
    space_group = @wrapper.entities.to_a.find { |entity| PhComposer::Spaces::SPACE_STORE.read(entity) }
    stored = PhComposer::Spaces::SPACE_STORE.read(space_group)
    unavailable = { "schema_version" => 3, "payload" => { "kept" => true }, "export_relevance" => "local_only" }
    PhComposer::Spaces::SPACE_STORE.write(space_group,
                                          stored.merge("extension_data" => { "other.tool" => unavailable }))
    renamed = edit(spaces.first, { "name" => "Kitchen" }, { "name" => "" })
    assert_equal "completed", renamed["status"], renamed.inspect
    row = spaces.first
    assert_equal({ "example" => { "note" => "kept" } }, row["user_data"])
    assert_equal({ "other.tool" => unavailable }, row["extension_data"])
    stale = invoke("ph_composer.spaces.update_metadata", "updates" => [{
      "reference" => spaces.first.fetch("reference"), "user_data" => {},
      "expected_metadata" => { "user_data" => {}, "extension_data" => {} }
    }])
    assert_equal %w[refused target.changed], stale.values_at("status", "code")
  end

  def test_remove_volume_and_delete_space
    zone_with_outlines
    create([@living])
    volume = spaces.first.dig("volumes", 0)
    removed = invoke("ph_composer.spaces.volumes.remove", "volume" => volume.fetch("reference"))
    assert_equal "completed", removed["status"], removed.inspect
    row = spaces.first
    assert_empty row.fetch("volumes")
    assert_equal ["space.empty"], row.fetch("findings").map { |finding| finding["code"] }
    deleted = invoke("ph_composer.spaces.delete", "space" => row.fetch("reference"))
    assert_equal "completed", deleted["status"], deleted.inspect
    assert_empty spaces
  end

  # The panel opens a Space as the edit context, and SketchUp refuses to erase a Group on that path.
  def test_delete_space_works_from_any_edit_context_in_one_undo_step
    zone_with_outlines
    create([@living])
    space_id, volume_id = spaces.first.dig("volumes", 0, "reference", "entity_path").last(2)
    space_group = entity_path([90, space_id]).last
    space_group.entities.to_a.find { |entity| entity.persistent_id == volume_id }.locked = false
    [[], [90], [90, space_id], [90, space_id, volume_id]].each do |open|
      @model.active_path = open.empty? ? nil : entity_path(open)
      before = @model.operations.length
      deleted = invoke("ph_composer.spaces.delete", "space" => spaces.first.fetch("reference"))
      assert_equal "completed", deleted["status"], "open #{open}: #{deleted.inspect}"
      assert_equal before + 1, @model.operations.length
      assert_empty @model.nested_starts, "Volume protection joins the Delete instead of splitting it"
      assert_empty spaces
      assert_equal open.first(1), Array(@model.active_path).map(&:persistent_id)
      Sketchup.undo
      assert_equal 1, spaces.length
    end
  end

  OFFSET = Geom::Transformation.new([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 10, 0, 0, 1])

  # A Space Group at the Model root with two Volumes, moved off the origin.
  def space_at_root(extra = [])
    @first = floor_face(1111, rectangle(0, 0, 3, 4), segment_record("L"))
    @second = floor_face(1121, rectangle(3, 0, 2, 2), segment_record("M"))
    @space = space_group(1100, space_record("L", :number => "101"),
                         [volume_group(1110, volume_record("L"), [@first]),
                          volume_group(1120, volume_record("M", :number => 2), [@second]), *extra],
                         :transformation => OFFSET)
    @space.entities.to_a.find { |entity| entity.persistent_id == 1120 }.transformation = OFFSET
    @model.entities << @space
    spaces.first.fetch("reference")
  end

  def corners(face)
    face.outer_loop.vertices.map { |vertex| [vertex.position.x, vertex.position.y, vertex.position.z] }
  end

  def test_remove_space_leaves_its_floors_where_they_stand_as_plain_geometry_in_one_undo_step
    reference = space_at_root
    expected = [[@first, 10], [@second, 20]].map { |face, shift| corners(face).map { |x, y, z| [x + shift, y, z] } }
    before = @model.operations.length
    removed = invoke("ph_composer.spaces.remove", "space" => reference)
    assert_equal "completed", removed["status"], removed.inspect
    assert_equal "spc_LLLLLLLLLLLL", removed.dig("value", "space_id")
    assert_equal before + 1, @model.operations.length
    assert_empty spaces
    assert_equal [1111, 1121], @model.entities.to_a.map(&:persistent_id), "both Groups are exploded"
    assert_equal expected, [@first, @second].map { |face| corners(face) }
    assert([@first, @second].all? { |face| PhComposer::Spaces::FLOOR_SEGMENT_STORE.read(face).nil? })
    Sketchup.undo
    assert_equal [2], spaces.map { |row| row.fetch("volumes").length }
    assert_equal [1100], @model.entities.to_a.map(&:persistent_id)
  end

  def test_remove_space_takes_every_record_below_it_and_keeps_what_is_not_the_spaces
    plain_volume = volume_group(1130, volume_record("N", :number => 3),
                                [floor_face(1131, rectangle(6, 0, 1, 1), segment_record("N"))])
    plain = Sketchup::Group.new(1140, Sketchup::Entities.new([plain_volume]))
    stray = floor_face(1150, rectangle(8, 0, 1, 1), segment_record("S"))
    loose = floor_face(1160, rectangle(8, 3, 1, 1))
    reference = space_at_root([plain, stray, loose])
    assert_equal "completed", invoke("ph_composer.spaces.remove", "space" => reference)["status"]
    assert_empty spaces
    store = PhComposer::Spaces::FLOOR_SEGMENT_STORE
    assert_nil store.read(stray), "a Floor Segment off its Volume does not ride out on a plain Face"
    assert_nil store.read(plain.entities.to_a.first)
    assert_equal [1111, 1121, 1140, 1150, 1160], @model.entities.to_a.map(&:persistent_id).sort
    assert_equal [1131], plain.entities.to_a.map(&:persistent_id), "the plain Group stays, its Volume exploded"
  end

  def test_remove_space_works_from_any_edit_context_in_one_undo_step
    zone_with_outlines
    create([@living])
    space_id, volume_id = spaces.first.dig("volumes", 0, "reference", "entity_path").last(2)
    space_group = entity_path([90, space_id]).last
    space_group.entities.to_a.find { |entity| entity.persistent_id == volume_id }.locked = false
    [[], [90], [90, space_id], [90, space_id, volume_id]].each do |open|
      @model.active_path = open.empty? ? nil : entity_path(open)
      before = @model.operations.length
      removed = invoke("ph_composer.spaces.remove", "space" => spaces.first.fetch("reference"))
      assert_equal "completed", removed["status"], "open #{open}: #{removed.inspect}"
      assert_equal before + 1, @model.operations.length
      assert_empty @model.nested_starts, "Volume protection joins the Remove instead of splitting it"
      assert_empty spaces
      assert_equal open.first(1), Array(@model.active_path).map(&:persistent_id)
      assert_includes @wrapper.entities.to_a, @living
      Sketchup.undo
      assert_equal 1, spaces.length
    end
  end

  def test_remove_space_refuses_a_record_below_it_in_shared_storage_with_nothing_written
    definition = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([
      volume_group(1131, volume_record("N", :number => 3),
                   [floor_face(1132, rectangle(6, 0, 1, 1), segment_record("N"))])
    ]))
    reference = space_at_root([Sketchup::ComponentInstance.new(1130, definition)])
    result = invoke("ph_composer.spaces.remove", "space" => reference)
    assert_equal %w[refused target.shared_definition none], result.values_at("status", "code", "effect")
    assert_equal [1100], @model.entities.to_a.map(&:persistent_id)
    assert PhComposer::Spaces::FLOOR_SEGMENT_STORE.read(@first)
  end

  def test_remove_space_refuses_a_volume_whose_identity_a_copy_shares_with_nothing_written
    reference = space_at_root
    @model.entities << space_group(1200, space_record("C", :number => "102"),
                                   [volume_group(1210, volume_record("L"), [floor_face(1211, rectangle(9, 0, 1, 1))])])
    result = invoke("ph_composer.spaces.remove", "space" => reference)
    assert_equal %w[refused target.ambiguous none], result.values_at("status", "code", "effect")
    assert_equal [1100, 1200], @model.entities.to_a.map(&:persistent_id)
  end

  def test_remove_space_rechecks_every_record_when_it_applies
    reference = space_at_root
    path = reference.fetch("entity_path")
    records = [[PhComposer::Spaces::SPACE_KIND, path, PhComposer::Spaces::SPACE_STORE.read(@space)],
               [PhComposer::Spaces::FLOOR_SEGMENT_KIND, path + [1110, 1111], segment_record("X")]]
    step = PhComposer::Spaces::RemoveSpaceStep.new(
      :path => path, :records => records.map { |kind, at, before| { "kind" => kind, "path" => at, "before" => before } }
    )
    error = assert_raises(PhComposer::CodedError) { step.apply(@model, {}) }
    assert_equal "target.changed", error.code
    assert PhComposer::Spaces::SPACE_STORE.read(@space), "checked before anything is removed"
  end

  def test_removing_an_identity_another_record_still_names_refuses_with_nothing_written
    zone_with_outlines
    create([@living])
    create([@bath])
    first, second = spaces
    segment = first.dig("volumes", 0, "floor_segments", 0)
    group = @wrapper.entities.to_a.find do |entity|
      PhComposer::Spaces::SPACE_STORE.read(entity)&.fetch("id") == second.fetch("id")
    end
    stored = PhComposer::Spaces::SPACE_STORE.read(group)
    envelope = { "schema_version" => 1, "payload" => { "segment" => segment.fetch("id") },
                 "export_relevance" => "local_only",
                 "references" => [{ "path" => "$.segment", "target_kind" => PhComposer::Spaces::FLOOR_SEGMENT_KIND,
                                    "cardinality" => "one" }] }
    PhComposer::Spaces::SPACE_STORE.write(group, stored.merge("extension_data" => { "other.tool" => envelope }))
    [["ph_composer.spaces.floors.unmark", { "floor_segments" => [segment.fetch("reference")] }],
     ["ph_composer.spaces.volumes.remove", { "volume" => first.dig("volumes", 0, "reference") }],
     ["ph_composer.spaces.remove", { "space" => first.fetch("reference") }],
     ["ph_composer.spaces.delete", { "space" => first.fetch("reference") }]].each do |name, params|
      result = invoke(name, params)
      assert_equal %w[refused reference.in_use none], result.values_at("status", "code", "effect"), name
    end
    assert_equal 2, spaces.length
  end

  def test_a_face_whose_neighbour_is_left_out_is_left_out_too
    zone_with_outlines
    edges = [200, 201].map { |id| Sketchup::Edge.new(id, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(0, INCHES, 0)) }
    a, b, c = [[120, [edges[0]]], [121, edges], [122, [edges[1]]]].map do |id, face_edges|
      points = rectangle(id - 120, 8, 1, 1).map { |x, y, z| Geom::Point3d.new(x * INCHES, y * INCHES, z * INCHES) }
      Sketchup::Face.new(id, {}, :points => points, :edges => face_edges)
    end
    @zone_group.entities << a << b << c
    preview = query("ph_composer.spaces.create_preview", "faces" => [face_path(a), face_path(b)])
    assert_empty preview.fetch("accepted")
    assert_equal %w[shares_edge shares_edge], preview.fetch("left_out").map { |row| row["reason"] }
    assert_match(/Undo the outline, then draw it just below the floor or inset from the walls/,
                 preview.dig("left_out", 0, "message"), "the refusal says how to recover")
  end

  # A closed solid drawn loose in `entities`: walls between two rings of points in metres, then the bottom and
  # top. Its Faces share their Edges, as the host's do. Returns [bottom, top, walls].
  def closed_solid(entities, low_m, high_m, first_id)
    low, high = [low_m, high_m].map do |ring|
      ring.map { |x, y, z| Geom::Point3d.new(x * INCHES, y * INCHES, z * INCHES) }
    end
    count = low.length
    edge = ->(offset, from, to) { Sketchup::Edge.new((first_id * 10) + offset, from, to) }
    rings = [[low, 0], [high, count]].map do |points, base|
      points.each_index.map { |index| edge.call(base + index, points[index], points[(index + 1) % count]) }
    end
    posts = low.each_index.map { |index| edge.call((2 * count) + index, low[index], high[index]) }
    walls = low.each_index.map do |index|
      following = (index + 1) % count
      points = [low[index], low[following], high[following], high[index]]
      edges = [rings[0][index], rings[1][index], posts[index], posts[following]]
      Sketchup::Face.new(first_id + index, {}, :points => points, :edges => edges)
    end
    bottom = Sketchup::Face.new(first_id + count, {}, :points => low.reverse, :edges => rings[0])
    top = Sketchup::Face.new(first_id + count + 1, {}, :points => high, :edges => rings[1])
    [*walls, bottom, top].each { |face| entities << face }
    [bottom, top, walls]
  end

  # W-037 and W-045: the walkthrough's L-shaped room, 4.88 m2 in plan. Create Space once took all eight Faces,
  # walls included, and counted 9.76 m2.
  def l_shaped_solid(entities, height = 2.4)
    plan = [[0, 10], [3.2, 10], [3.2, 11.15], [1.2, 11.15], [1.2, 12.15], [0, 12.15]]
    closed_solid(entities, plan.map { |x, y| [x, y, 0] }, plan.map { |x, y| [x, y, height] }, 150)
  end

  # A solid with no vertical side: a 4 m square bottom under a 2 m square top, 2 m above it.
  def sloped_solid(entities)
    closed_solid(entities, rectangle(10, 10, 4, 4), rectangle(11, 11, 2, 2, 2), 180)
  end

  def test_create_space_on_a_solid_refuses_its_walls_and_counts_no_floor_twice
    zone_with_outlines
    bottom, top, walls = l_shaped_solid(@zone_group.entities)
    sloped = sloped_solid(@zone_group.entities).flatten
    downward = floor_face(170, rectangle(6, 10, 1, 1).reverse)
    @zone_group.entities << downward
    faces = [bottom, top, *walls, *sloped, downward].map { |face| face_path(face) }
    preview = query("ph_composer.spaces.create_preview", "faces" => faces)
    assert_equal [[90, 100, 170]], preview.fetch("accepted"),
                 "a solid's walls are not floors and its top is not a second floor; a flat outline facing down is"
    reasons = preview.fetch("left_out").to_h { |row| [row.fetch("path").last, row] }
    assert_equal %w[vertical] * 6, walls.map { |wall| reasons.dig(wall.persistent_id, "reason") }
    assert_equal %w[solid solid], [bottom, top].map { |face| reasons.dig(face.persistent_id, "reason") }
    assert_equal %w[solid] * 6, sloped.map { |face| reasons.dig(face.persistent_id, "reason") },
                 "a solid with sloped sides is refused whole, not counted top and bottom"
    message = reasons.dig(bottom.persistent_id, "message")
    assert_match(/A Space is a floor outline plus a height/, message)
    assert_match(/Height from solid/, message)
    before = @model.operations.length
    assert_equal %w[refused space.nothing_to_create], create([bottom, top, *walls]).values_at("status", "code")
    assert_equal before, @model.operations.length
    assert_empty spaces
  end

  def test_a_new_volume_refuses_a_closed_solid
    zone_with_outlines
    create([@living])
    space_group = @wrapper.entities.to_a.find { |entity| PhComposer::Spaces::SPACE_STORE.read(entity) }
    @model.active_path = [@wrapper, space_group]
    space = spaces.first.fetch("reference")
    faces = sloped_solid(space_group.entities).flatten.map { |face| space.fetch("entity_path") + [face.persistent_id] }
    result = invoke("ph_composer.spaces.volumes.create", "space" => space, "faces" => faces)
    assert_equal %w[refused target.wrong_kind], result.values_at("status", "code")
    assert_match(/A Space is a floor outline plus a height/, result.fetch("message"))
  end

  def test_a_vertical_face_is_never_a_floor_candidate_a_marked_floor_or_a_new_volume
    zone_with_outlines
    create([@living])
    space_group = @wrapper.entities.to_a.find { |entity| PhComposer::Spaces::SPACE_STORE.read(entity) }
    wall = floor_face(140, [[0, 0, 0], [1, 0, 0], [1, 0, 1], [0, 0, 1]])
    space_group.entities << wall
    space = spaces.first.fetch("reference")
    candidate = query("ph_composer.spaces.candidate_faces.list", "space" => space).fetch("candidate_faces").first
    assert_equal "target.wrong_kind", candidate.dig("refusal", "code")
    volume_group = space_group.entities.to_a.find { |entity| PhComposer::Spaces::VOLUME_STORE.read(entity) }
    volume_group.entities << floor_face(141, [[0, 1, 0], [1, 1, 0], [1, 1, 1], [0, 1, 1]])
    volume = spaces.first.dig("volumes", 0, "reference")
    marked = invoke("ph_composer.spaces.floors.mark", "faces" => [volume.fetch("entity_path") + [141]],
                                                      "weighting_factor" => 1.0)
    assert_equal %w[refused target.wrong_kind], marked.values_at("status", "code")
    @model.active_path = [@wrapper, space_group]
    result = invoke("ph_composer.spaces.volumes.create", "space" => space,
                                                         "faces" => [space.fetch("entity_path") + [140]])
    assert_equal %w[refused target.wrong_kind], result.values_at("status", "code")
  end

  def test_a_new_volume_refuses_faces_that_share_an_edge_with_an_unselected_face
    zone_with_outlines
    create([@living])
    space_group = @wrapper.entities.to_a.find { |entity| PhComposer::Spaces::SPACE_STORE.read(entity) }
    edge = Sketchup::Edge.new(300, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(0, INCHES, 0))
    left, right = [130, 131].map do |id|
      points = rectangle(id - 125, 0, 1, 1).map { |x, y, z| Geom::Point3d.new(x * INCHES, y * INCHES, z * INCHES) }
      Sketchup::Face.new(id, {}, :points => points, :edges => [edge])
    end
    space_group.entities << left << right
    @model.active_path = [@wrapper, space_group]
    space = spaces.first.fetch("reference")
    result = invoke("ph_composer.spaces.volumes.create", "space" => space,
                                                         "faces" => [space.fetch("entity_path") + [130]])
    assert_equal %w[refused space.shares_edge], result.values_at("status", "code")
  end

  def test_marking_a_face_whose_floor_segment_id_is_copied_refuses
    zone_with_outlines
    create([@living])
    volume = spaces.first.dig("volumes", 0)
    volume_group = @wrapper.entities.to_a.find { |entity| PhComposer::Spaces::SPACE_STORE.read(entity) }
                           .entities.to_a.first
    copied = floor_face(140, rectangle(0, 4, 1, 1), PhComposer::Spaces::FLOOR_SEGMENT_STORE.read(@living))
    volume_group.entities << copied
    result = invoke("ph_composer.spaces.floors.mark", "faces" => [volume.dig("reference", "entity_path") + [101]],
                                                      "weighting_factor" => 0.5)
    assert_equal %w[refused target.ambiguous], result.values_at("status", "code")
  end

  def test_deleting_a_space_checks_every_record_it_erases
    zone_with_outlines
    create([@living])
    create([@bath])
    first, second = spaces
    first_group, second_group = @wrapper.entities.to_a.select { |entity|
      PhComposer::Spaces::SPACE_STORE.read(entity)
    }
    misplaced = floor_face(150, rectangle(0, 9, 1, 1), segment_record("M"))
    first_group.entities << misplaced
    stored = PhComposer::Spaces::SPACE_STORE.read(second_group)
    envelope = { "schema_version" => 1, "payload" => { "segment" => "fsg_MMMMMMMMMMMM" },
                 "export_relevance" => "local_only",
                 "references" => [{ "path" => "$.segment", "target_kind" => PhComposer::Spaces::FLOOR_SEGMENT_KIND,
                                    "cardinality" => "one" }] }
    PhComposer::Spaces::SPACE_STORE.write(second_group, stored.merge("extension_data" => { "other.tool" => envelope }))
    result = invoke("ph_composer.spaces.delete", "space" => first.fetch("reference"))
    assert_equal %w[refused reference.in_use], result.values_at("status", "code")
    assert_equal [first.fetch("id"), second.fetch("id")], spaces.map { |row| row["id"] }
  end

  def test_a_write_rechecks_the_lock_when_it_applies
    zone_with_outlines
    create([@living])
    row = spaces.first
    space_group = @wrapper.entities.to_a.find { |entity| PhComposer::Spaces::SPACE_STORE.read(entity) }
    step = PhComposer::Spaces::RecordStep.new(:kind => PhComposer::Spaces::SPACE_KIND,
                                              :path => row.dig("reference", "entity_path"),
                                              :before => PhComposer::Spaces::SPACE_STORE.read(space_group),
                                              :after => PhComposer::Spaces::SPACE_STORE.read(space_group)
                                                                                       .merge("name" => "Late"))
    space_group.locked = true
    error = assert_raises(PhComposer::CodedError) { step.apply(@model, {}) }
    assert_equal "target.locked", error.code
    assert_equal "", PhComposer::Spaces::SPACE_STORE.read(space_group)["name"]
  end

  def test_marking_refuses_when_an_orphan_volume_copies_the_volume_id
    zone_with_outlines
    create([@living])
    volume = spaces.first.dig("volumes", 0)
    copy = volume_group(160, PhComposer::Spaces::VOLUME_STORE.read(@wrapper.entities.to_a.find do |entity|
      PhComposer::Spaces::SPACE_STORE.read(entity)
    end.entities.to_a.first), [])
    @model.entities << copy
    result = invoke("ph_composer.spaces.floors.mark", "faces" => [volume.dig("reference", "entity_path") + [101]],
                                                      "weighting_factor" => 0.5)
    assert_equal %w[refused target.ambiguous], result.values_at("status", "code")
  end

  def test_repeated_floor_targets_count_once
    zone_with_outlines
    create([@living])
    volume_group = @wrapper.entities.to_a.find { |entity| PhComposer::Spaces::SPACE_STORE.read(entity) }
                           .entities.to_a.first
    volume_group.entities << floor_face(170, rectangle(0, 4, 1, 1))
    path = spaces.first.dig("volumes", 0, "reference", "entity_path") + [170]
    marked = invoke("ph_composer.spaces.floors.mark", "faces" => [path, path], "weighting_factor" => 1.0)
    assert_equal "completed", marked["status"], marked.inspect
    segment = spaces.first.dig("volumes", 0, "floor_segments").find { |row|
      row.dig("reference", "entity_path") == path
    }
    unmarked = invoke("ph_composer.spaces.floors.unmark", "floor_segments" => [segment.fetch("reference")] * 2)
    assert_equal "completed", unmarked["status"], unmarked.inspect
  end

  def test_a_kind_specific_param_refuses_another_kinds_reference
    zone_with_outlines
    create([@living])
    result = invoke("ph_composer.spaces.volumes.remove", "volume" => spaces.first.fetch("reference"))
    assert_equal %w[refused params.invalid], result.values_at("status", "code")
  end

  private

  def edit(row, values, expected)
    invoke("ph_composer.spaces.update", "reference" => row.fetch("reference"), "values" => values,
                                        "expected_values" => expected)
  end

  def entity_path(ids)
    entities = @model.entities
    ids.map do |id|
      entities.to_a.find { |entity| entity.persistent_id == id }.tap { |found| entities = found.entities }
    end
  end

  def query(name, params = {})
    result = API.query(:context => @context, :name => name, :params => params)
    assert_equal "completed", result["status"], result.inspect
    result.fetch("value")
  end

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end
end
