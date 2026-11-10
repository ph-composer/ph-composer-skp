# frozen_string_literal: true

# Review-only baseline reproductions using the offline host stub.
require_relative "../../../../tests/test_helper"
require File.join(TESTS_ROOT, "support/space_fixtures")

class FeatureProbe < PhComposerTestCase
  include SpaceFixtures
  API = PhComposer::API

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(session_id: @session.id)
    @sequence = 0
  end

  def read(name, params = {})
    API.query(context: @context, name: "ph_composer.#{name}", params: params)
  end

  def write(name, params = {})
    @sequence += 1
    API.invoke(context: @context, name: "ph_composer.#{name}", params: params,
               request: { "sequence" => @sequence, "expected_revision" => @session.revision })
  end

  def display(label, result)
    fields = result.slice("status", "effect", "code", "value")
    puts "#{label}: #{JSON.generate(fields)}"
    result
  end

  def status(expected, result)
    assert_equal expected.split, result.values_at("status", "effect", "code"), result.inspect
  end

  def test_space_group_also_becomes_zone
    floor = floor_face(101, rectangle(0, 0, 3, 4))
    @model.entities << floor
    status("completed committed ok", display("create Space", write("spaces.create", "faces" => [[101]], "name" => "Living")))
    row = read("spaces.list").dig("value", "spaces", 0)
    ref = row.fetch("reference")
    made = display("Make Zone on that Space Group", write("zones.make", "parent_path" => [], "entity_ids" => ref.fetch("entity_path")))
    status("completed committed ok", made)
    readback = display("Zone faces now includes Floor Segment", read("zones.faces.list"))
    status("completed none ok", readback)
    assert_equal 1, readback.dig("value", "total")
    assert_equal 101, readback.dig("value", "faces", 0, "reference", "entity_path").last
    assert_equal made.dig("value", "zone_id"), readback.dig("value", "faces", 0, "reference", "zone_id")
    status("completed committed ok", display("delete Space with same Group", write("spaces.delete", "space" => ref)))
    after = display("Zone inventory after delete Space", read("zones.list"))
    assert_equal 0, after.dig("value", "total")
    assert_empty after.dig("value", "restorable")
  end

  def test_plain_wrapper_can_put_a_space_inside_a_zone
    floor = floor_face(101, rectangle(0, 0, 3, 4))
    wrapper = Sketchup::Group.new(100, Sketchup::Entities.new([floor]))
    @model.entities << wrapper
    opened = API.view(context: @context, name: "ph_composer.context.open", params: { "path" => [100] })
    status("completed none ok", opened)
    status("completed committed ok", write("spaces.create", "faces" => [[100, 101]], "name" => "Living"))
    closed = API.view(context: @context, name: "ph_composer.context.root", params: { "expected_path" => [100] })
    status("completed none ok", closed)
    made = display("Make Zone on plain wrapper holding a Space", write("zones.make", "parent_path" => [], "entity_ids" => [100]))
    status("completed committed ok", made)
    before = read("spaces.list").dig("value", "spaces", 0)
    assert_equal [100], before.dig("reference", "entity_path")[0...-1]
    assert_nil before["zone"]
    rows = read("zones.faces.list").dig("value", "faces")
    assert_equal 1, rows.length
    assert_equal 101, rows[0].dig("reference", "entity_path").last
    assert_equal made.dig("value", "zone_id"), rows[0].dig("reference", "zone_id")
  end

  def test_copied_face_null_id_bypasses_guard
    face1 = floor_face(101, rectangle(0, 0, 3, 4))
    face2 = floor_face(102, rectangle(4, 0, 3, 4))
    @model.entities << zone_group(100, "Z", [face1, face2])
    store = PhComposer::Zones::Faces::FACE_STORE
    record = { "id" => "fac_AAAAAAAAAAAA", "schema_version" => 1, "face_type" => "Floor",
               "boundary_condition" => "Ground" }
    store.write(face1, record)
    store.write(face2, record)
    ref = read("zones.faces.list").dig("value", "faces", 0, "reference")
    params = { "faces" => [ref], "intent" => { "boundary_condition" => { "mode" => "set", "value" => "Outdoors" } } }
    status("refused none target.ambiguous", display("classify exact copied Face id", write("zones.faces.classify", params)))
    masked = params.merge("faces" => [ref.merge("entity_id" => nil)])
    preview = API.preview(context: @context, name: "ph_composer.zones.faces.classify", params: masked)
    assert_equal "completed", preview["status"], preview.inspect
    status("failed rolled_back operation.failed", display("classify same path, null id", write("zones.faces.classify", masked)))
    assert_equal [record, record], [store.read(face1), store.read(face2)]
    puts "stored after null id: #{[store.read(face1), store.read(face2)].inspect}"
  end

  def test_null_id_reuses_stale_unassigned_face
    face = floor_face(101, rectangle(0, 0, 3, 4))
    @model.entities << zone_group(100, "Z", [face])
    ref = read("zones.faces.list").dig("value", "faces", 0, "reference")
    params = { "faces" => [ref], "intent" => { "boundary_condition" => { "mode" => "set", "value" => "Outdoors" } } }
    assert_nil ref["entity_id"]
    status("completed committed ok", display("classify previously unclassified", write("zones.faces.classify", params)))
    status("completed committed ok", display("classify again using the old null id on current revision", write("zones.faces.classify",
       params.merge("intent" => { "boundary_condition" => { "mode" => "set", "value" => "Ground" } }))))
    assert_equal "Ground", read("zones.faces.list").dig("value", "faces", 0, "values", "boundary_condition")
    status("completed committed ok", display("reverse using old null id on current revision", write("zones.faces.reverse", "face" => ref)))
  end

  def test_locked_zone_edit_variants
    face = floor_face(101, rectangle(0, 0, 3, 4))
    @model.entities << (group = zone_group(100, "Z", [face]))
    row = read("zones.list").dig("value", "zones", 0)
    ref, before = row.values_at("reference", "values")
    group.locked = true
    status("refused none target.locked", display("locked zone batch edit", write("zones.update_field", "field" => "name", "value" => "Changed",
      "targets" => [{"reference" => ref, "expected_values" => before}])))
    status("completed committed ok", display("locked zone single edit", write("zones.update", "reference" => ref, "values" => before.merge("name" => "Changed"),
      "expected_values" => before)))
    assert_equal "Changed", read("zones.list").dig("value", "zones", 0, "values", "name")
  end

  def test_multiple_legacy_restore_targets_break_zones_list_budget
    450.times do |i|
      face = floor_face(2000 + i, rectangle(0, 0, 3, 4))
      PhComposer::Zones::STAMP_STORE.write(face, { "schema_version" => 1, "zone_id" => "zon_#{format('%012d', i)}",
        "building_segment" => "Main Building", "level" => "Level 1" })
      @model.entities << face
    end
    readback = read("zones.list", "limit" => 1, "fields" => [])
    status("completed none ok", readback)
    assert_equal 450, readback.dig("value", "restorable").size
    assert_operator JSON.generate(readback).bytesize, :>, PhComposer::AgentAccess::Executor::MAX_RESULT_BYTES
    puts "zones.list limit 1 plus 450 restore targets, #{JSON.generate(readback).bytesize} bytes; #{readback.dig('value', 'restorable')&.size} restore targets"
  end

  def test_one_thermal_run_exceeds_mcp_budget
    tb = PhComposer::ThermalBridges
    created = write("thermal_bridges.types.create", "values" => { "name" => "Test", "psi_w_mk" => 0.05, "group" => "15-Ambient" })
    type_id = created.dig("value", "id")
    vertices = 800.times.map { |i| Sketchup::Vertex.new(Geom::Point3d.new(i * 0.33, 0, 0)) }
    edges = vertices.each_cons(2).with_index.map do |(from, to), i|
      edge = Sketchup::Edge.new(1000 + i, from, to)
      tb::Assignment::STORE.write(edge, "id" => "tbe_#{format('%012d', i)}", "schema_version" => 1,
        "thermal_bridge_type_id" => type_id, "quantity" => 1, "user_data" => {}, "extension_data" => {})
      edge
    end
    @model.entities << zone_group(100, "Z", edges)
    answer = read("thermal_bridges.schedule.list", "limit" => 1)
    status("completed none ok", answer)
    assert_equal 1, answer.dig("value", "runs").size
    assert_equal 799, answer.dig("value", "runs", 0, "edge_paths").size
    assert_operator JSON.generate(answer).bytesize, :>, PhComposer::AgentAccess::Executor::MAX_RESULT_BYTES
    puts "schedule.list limit 1, #{JSON.generate(answer).bytesize} bytes; #{answer.dig('value', 'runs')&.size} run; #{answer.dig('value', 'runs', 0, 'edge_paths')&.size} edge paths"
  end

  def test_create_accepts_subset
    floor = floor_face(101, rectangle(0, 0, 3, 4))
    @model.entities << floor
    preview = display("create preview with missing path", read("spaces.create_preview", "faces" => [[101], [102]]))
    status("completed none ok", preview)
    assert_equal [[101]], preview.dig("value", "accepted")
    assert_equal [[102], "not_found"], preview.dig("value", "left_out", 0).values_at("path", "reason")
    created = display("direct create with missing path", write("spaces.create", "faces" => [[101], [102]]))
    status("completed committed ok", created)
    assert_equal 1, created.dig("value", "floor_segment_ids").size
    assert_empty created["findings"]
    refute created.fetch("value").key?("left_out")
  end

  def test_unreadable_edge_cannot_be_cleared
    edge = Sketchup::Edge.new(101, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(10, 0, 0))
    group = zone_group(100, "Z", [edge])
    @model.entities << group
    store = PhComposer::ThermalBridges::Assignment::STORE
    edge.set_attribute(store.dictionary, store.key, "{broken")
    @model.active_path = [group]
    @model.selection.add(edge)
    schedule = display("unreadable edge in schedule", read("thermal_bridges.schedule.list", "limit" => 1))
    assert_equal [[100, 101], "record.unreadable"], schedule.dig("value", "unreadable", 0).values_at("path", "code")
    preflight = read("thermal_bridges.export_preflight")
    assert_equal ["record.unreadable", true], preflight.dig("value", "findings", 0).values_at("code", "blocks_export")
    status("refused none record.unreadable", display("selection of unreadable edge", read("thermal_bridges.edges.selection")))
    ref = { "zone_id" => "zon_ZZZZZZZZZZZZ", "zone_path" => [100], "entity_path" => [101], "entity_id" => nil }
    status("refused none record.unreadable", display("clear unreadable edge via explicit path", write("thermal_bridges.edges.clear", "targets" => [{"reference" => ref}])))
    assert_equal "{broken", edge.get_attribute(store.dictionary, store.key)
  end
end
