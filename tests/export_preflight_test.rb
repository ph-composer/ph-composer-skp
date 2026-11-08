# frozen_string_literal: true

require_relative "test_helper"

class ExportPreflightTest < PhComposerTestCase
  API = PhComposer::API

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id, :capabilities => ["read"])
  end

  def test_read_only_preflight_reports_empty_model_without_a_task_or_destination
    outcome = API.export_preflight(:context => @context)
    assert_equal "completed", outcome.fetch("status")
    assert_equal ["zone.none"], outcome.dig("value", "findings").map { |finding| finding.fetch("code") }
    assert_empty outcome.dig("value", "repairs")
    assert_empty @model.operations
    assert_nil UI.last_savepanel
  end

  def test_unclassified_faces_have_public_locate_and_all_zone_solve_is_explicit_and_checked
    group = seed_zone
    outcome = API.export_preflight(:context => @context)
    assert_equal "completed", outcome.fetch("status")
    finding = outcome.dig("value", "findings").first
    assert_equal "face.unclassified", finding.fetch("code")
    assert_equal "ph_composer.zones.faces.locate", finding.dig("locate", "name")
    reference = finding.dig("locate", "params", "faces", 0)
    assert_equal [100], reference.fetch("zone_path")
    assert_equal [101], reference.fetch("entity_path")
    repair = outcome.dig("value", "repairs").first
    assert_equal "Re-solve adjacencies before export", repair.fetch("label")
    assert_equal true, repair.fetch("checked")
    assert_equal "ph_composer.zones.solve_adjacency", repair.fetch("action")
    assert_equal [{ "zone_id" => "zon_#{'A' * 12}", "zone_path" => [100] }], repair.dig("params", "zones")
    assert_nil PhComposer::Zones::Faces::FACE_STORE.read(group.entities.to_a.first)
    assert_empty @model.operations
  end

  def test_normal_preflight_never_activates_a_synthetic_or_unavailable_construction
    group = seed_zone
    face = group.entities.to_a.first
    record = { "id" => "fac_#{'A' * 12}", "schema_version" => 1, "face_type" => "Wall",
               "boundary_condition" => "Outdoors", "user_data" => {}, "extension_data" => {} }
    PhComposer::Zones::Faces::FACE_STORE.write(face, record)
    first = API.export_preflight(:context => @context)
    assert_equal "construction.missing", first.dig("value", "findings", 0, "code")
    PhComposer::Zones::Faces::FACE_STORE.write(face, record.merge("assembly_id" => "asm_#{'A' * 12}"))
    second = API.export_preflight(:context => @context)
    assert_equal "construction.dangling", second.dig("value", "findings", 0, "code")
    assert second.dig("value", "findings").all? { |finding| finding.fetch("blocks_export") }
    assert_empty @model.operations
  end

  def test_preflight_values_are_detached_and_copied_zone_identities_are_blocking
    group = seed_zone
    duplicate = Sketchup::Group.new(200, Sketchup::Entities.new([]))
    @model.entities << duplicate
    PhComposer::Zones::ZONE_STORE.write(duplicate, PhComposer::Zones::ZONE_STORE.read(group))
    first = API.export_preflight(:context => @context)
    ambiguous = first.dig("value", "findings").select { |finding| finding["code"] == "target.ambiguous" }
    assert_equal 2, ambiguous.length
    first.dig("value", "repairs", 0, "params", "zones", 0)["zone_path"] << 999
    second = API.export_preflight(:context => @context)
    assert_equal [100], second.dig("value", "repairs", 0, "params", "zones", 0, "zone_path")
  end

  def test_missing_type_and_attached_zone_states_remain_distinct
    face = seed_zone.entities.to_a.first
    record = { "id" => "fac_#{'A' * 12}", "schema_version" => 1,
               "boundary_condition" => "AttachedZone", "user_data" => {}, "extension_data" => {} }
    PhComposer::Zones::Faces::FACE_STORE.write(face, record)
    codes = preflight_codes
    assert_includes codes, "face.type_missing"
    assert_includes codes, "attached_zone.absent"
    record["attached_zone_id"] = "atz_#{'A' * 12}"
    PhComposer::Zones::Faces::FACE_STORE.write(face, record)
    assert_includes preflight_codes, "attached_zone.dangling"
    kind = PhComposer::Zones::Faces::AttachedZone::RECORD_KIND
    attached = { "id" => record.fetch("attached_zone_id"), "schema_version" => 1, "name" => "Garage",
                 "kind" => "garage", "temperature_reduction_factor" => 2.0 }
    kind.store.write(@model, attached)
    assert_includes preflight_codes, "attached_zone.invalid"
    kind.store.write(@model, attached.merge("schema_version" => 2))
    assert_includes preflight_codes, "attached_zone.unavailable"
    kind.store.write(@model, attached.merge("temperature_reduction_factor" => 0.95))
    refute preflight_codes.any? { |code| code.start_with?("attached_zone.") }
    assert_empty @model.operations
  end

  def test_unassigned_boundary_is_an_omission_without_a_construction_requirement
    face = seed_zone.entities.to_a.first
    PhComposer::Zones::Faces::FACE_STORE.write(face, {
      "id" => "fac_#{'A' * 12}", "schema_version" => 1, "face_type" => "Wall",
      "user_data" => {}, "extension_data" => {}
    })
    findings = API.export_preflight(:context => @context).dig("value", "findings")
    assert_equal ["face.boundary_unassigned"], findings.map { |finding| finding.fetch("code") }
    refute findings.first.fetch("blocks_export")
    assert_empty @model.operations
  end

  private

  def preflight_codes
    API.export_preflight(:context => @context).dig("value", "findings").map { |finding| finding.fetch("code") }
  end

  def seed_zone
    group = Sketchup::Group.new(100, Sketchup::Entities.new([Sketchup::Face.new(101)]))
    @model.entities << group
    PhComposer::Zones::ZONE_STORE.write(group, {
      "id" => "zon_#{'A' * 12}", "schema_version" => 1, "name" => "Fixture",
      "building_segment" => "Main", "level" => nil, "ground_depth_mm" => 0.0,
      "user_data" => {}, "extension_data" => {}
    })
    group
  end
end
