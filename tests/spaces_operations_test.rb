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

  def face_reference(face)
    @zone.merge("entity_path" => [face.persistent_id], "entity_id" => nil)
  end

  def create(faces, **extra)
    invoke("ph_composer.spaces.create", { "zone" => @zone, "faces" => faces.map { |face| face_reference(face) } }
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
    space_group = @zone_group.entities.to_a.find { |entity| PhComposer::Spaces::SPACE_STORE.read(entity) }
    zone_record = PhComposer::Zones::ZONE_STORE.read(@zone_group)
    assert_equal PhComposer::Zones::Schema.stamp(zone_record), PhComposer::Zones::STAMP_STORE.read(space_group)
    assert_equal "1 Living", space_group.name
    faces = query("ph_composer.zones.faces.list").fetch("faces").map { |face| face.dig("reference", "entity_path") }
    assert_equal [[102]], faces, "the Floor Segment is no longer a Zone Face"
    second = create([@bath])
    assert_equal "completed", second["status"], second.inspect
    assert_equal %w[1 2], spaces.map { |space| space.dig("values", "number") }
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
    params = { "zone" => @zone,
               "faces" => [face_reference(@living), face_reference(left),
                           face_reference(classified).merge("entity_id" => "fac_CCCCCCCCCCCC"),
                           @zone.merge("entity_path" => [104, 105], "entity_id" => nil),
                           { "zone_id" => "zon_OTHER0000001", "zone_path" => [1], "entity_path" => [1],
                             "entity_id" => nil }] }
    preview = query("ph_composer.spaces.create_preview", params)
    assert_equal [[101]], preview.fetch("accepted").map { |face| face["entity_path"] }
    assert_equal %w[shares_edge classified not_in_zone_context other_zone].sort,
                 preview.fetch("left_out").map { |row| row["reason"] }.sort
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
    space_group = @zone_group.entities.to_a.find { |entity| PhComposer::Spaces::SPACE_STORE.read(entity) }
    hall = floor_face(109, rectangle(0, 4, 1, 2))
    space_group.entities << hall
    @model.active_path = [@wrapper, @zone_group, space_group]
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
    volume_group = @zone_group.entities.to_a.find { |entity| PhComposer::Spaces::SPACE_STORE.read(entity) }
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
    space_group = @zone_group.entities.to_a.find { |entity| PhComposer::Spaces::SPACE_STORE.read(entity) }
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
    space_group = entity_path([90, 100, space_id]).last
    space_group.entities.to_a.find { |entity| entity.persistent_id == volume_id }.locked = false
    [[], [90, 100], [90, 100, space_id], [90, 100, space_id, volume_id]].each do |open|
      @model.active_path = open.empty? ? nil : entity_path(open)
      before = @model.operations.length
      deleted = invoke("ph_composer.spaces.delete", "space" => spaces.first.fetch("reference"))
      assert_equal "completed", deleted["status"], "open #{open}: #{deleted.inspect}"
      assert_equal before + 1, @model.operations.length
      assert_empty @model.nested_starts, "Volume protection joins the Delete instead of splitting it"
      assert_empty spaces
      assert_equal open.first(2), Array(@model.active_path).map(&:persistent_id)
      Sketchup.undo
      assert_equal 1, spaces.length
    end
  end

  def test_removing_an_identity_another_record_still_names_refuses_with_nothing_written
    zone_with_outlines
    create([@living])
    create([@bath])
    first, second = spaces
    segment = first.dig("volumes", 0, "floor_segments", 0)
    group = @zone_group.entities.to_a.find do |entity|
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
    preview = query("ph_composer.spaces.create_preview", "zone" => @zone,
                                                         "faces" => [face_reference(a), face_reference(b)])
    assert_empty preview.fetch("accepted")
    assert_equal %w[shares_edge shares_edge], preview.fetch("left_out").map { |row| row["reason"] }
    assert_match(/Undo the outline, then draw it just below the floor or inset from the walls/,
                 preview.dig("left_out", 0, "message"), "the refusal says how to recover")
  end

  def test_a_new_volume_refuses_faces_that_share_an_edge_with_an_unselected_face
    zone_with_outlines
    create([@living])
    space_group = @zone_group.entities.to_a.find { |entity| PhComposer::Spaces::SPACE_STORE.read(entity) }
    edge = Sketchup::Edge.new(300, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(0, INCHES, 0))
    left, right = [130, 131].map do |id|
      points = rectangle(id - 125, 0, 1, 1).map { |x, y, z| Geom::Point3d.new(x * INCHES, y * INCHES, z * INCHES) }
      Sketchup::Face.new(id, {}, :points => points, :edges => [edge])
    end
    space_group.entities << left << right
    @model.active_path = [@wrapper, @zone_group, space_group]
    space = spaces.first.fetch("reference")
    result = invoke("ph_composer.spaces.volumes.create", "space" => space,
                                                         "faces" => [space.fetch("entity_path") + [130]])
    assert_equal %w[refused space.shares_edge], result.values_at("status", "code")
  end

  def test_marking_a_face_whose_floor_segment_id_is_copied_refuses
    zone_with_outlines
    create([@living])
    volume = spaces.first.dig("volumes", 0)
    volume_group = @zone_group.entities.to_a.find { |entity| PhComposer::Spaces::SPACE_STORE.read(entity) }
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
    first_group, second_group = @zone_group.entities.to_a.select { |entity|
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
    space_group = @zone_group.entities.to_a.find { |entity| PhComposer::Spaces::SPACE_STORE.read(entity) }
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
    copy = volume_group(160, PhComposer::Spaces::VOLUME_STORE.read(@zone_group.entities.to_a.find do |entity|
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
    volume_group = @zone_group.entities.to_a.find { |entity| PhComposer::Spaces::SPACE_STORE.read(entity) }
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
