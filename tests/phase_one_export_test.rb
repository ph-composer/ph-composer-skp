# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/construction_export_fixtures"

class PhaseOneExportTest < PhComposerTestCase
  include ConstructionExportFixtures
  include FixtureFiles

  FIXTURE = File.join(TESTS_ROOT, "fixtures", "phase_one", "two_zones_extraction.json")

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = PhComposer::API.connect(:session_id => @session.id)
    @sequence = 0
  end

  # Face area per Assembly is the Zones report's; it names each Assembly from the Assemblies section it
  # declares, and the Assemblies report never sees Face usage.
  def test_construction_usage_report_names_assemblies_through_the_declared_section
    zones = "ph_composer.zones.export.zones"
    definitions = [{ "assembly_id" => "asm_Single000001", "name" => "<Synthetic>", "thermal_layer_count" => 2,
                     "membrane_names" => [], "defaulted_material_ids" => [] }]
    result = { "ph_composer.assemblies.export.constructions" => { "construction_definitions" => definitions },
               zones => { "construction_usage" => [
                 { "assembly_id" => "asm_Single000001", "face_count" => 2, "gross_area_m2" => 10.0 }
               ] } }
    contributor = PhComposer::Registry.current.export_contributors.fetch(zones)
    view = PhComposer::Export::ResultView.new(result, contributor)

    assert_includes PhComposer::Zones::ExportProjection.report(view, "si").join,
                    "<td>&lt;Synthetic&gt;</td><td>2</td><td>10.00</td>"
    assert_includes PhComposer::Zones::ExportProjection.report(view, "ip").join, "107.64"
    assert_empty PhComposer::Zones::ExportProjection.report(PhComposer::Export::ResultView.new({}, contributor), "si")
  end

  def test_two_zone_extraction_uses_one_snapshot_and_owns_the_golden
    zones = seed_two_boxes
    invoke("ph_composer.zones.solve_adjacency", "zones" => zones)
    names = contributor_names
    before = @model.entities.each_count

    extraction = PhComposer::Export::Collection.build(
      @model, :run_id => "run-phase-one-two-zones", :contributors => names
    )

    assert_equal before + 1, @model.entities.each_count
    assert_empty extraction.findings
    assert_equal [6, 6], extraction.document.dig("sections", PhComposer::Zones::ExportProjection::SECTION, "records")
                                   .map { |zone| zone.fetch("face_ids").length }
    faces = extraction.document.dig("sections", PhComposer::Zones::Faces::ExportProjection::SECTION, "records")
    assert_equal 12, faces.length
    assert_equal 2, faces.count { |face| face["boundary_condition"] == "Surface" }
    write_or_compare(FIXTURE, extraction.document)
  end

  def test_managed_extraction_resolves_names_and_preserves_adopted_segment_export_identity_through_rename
    seed_two_boxes
    sources = PhComposer::API.query(:context => @context, :name => "ph_composer.zones.options.adoption_preview")
                             .dig("value", "sources")
    original_segment = sources.find { |source| source.fetch("collection") == "building_segment" }
    adopted = invoke("ph_composer.zones.options.adopt", "mappings" => sources.map { |source|
      { "source" => source.fetch("key"), "target_id" => nil,
        "name" => source.fetch("name"), "colour" => source.fetch("colour") }
    })
    assert_equal "completed", adopted.fetch("status"), adopted.inspect
    options = PhComposer::API.query(:context => @context, :name => "ph_composer.zones.options.all").fetch("value")
    segment = options.fetch("building_segments").first
    renamed = invoke("ph_composer.zones.options.update", {
      "collection" => "building_segment", "id" => segment.fetch("id"),
      "values" => { "name" => "Renamed", "colour" => "#123456" },
      "expected_values" => segment.fetch("values").slice("name", "colour")
    })
    assert_equal "completed", renamed.fetch("status"), renamed.inspect
    extraction = PhComposer::Export::Collection.build(@model, :run_id => "managed", :contributors => contributor_names)
    section = extraction.document.fetch("sections").fetch(PhComposer::Zones::ExportProjection::SECTION)
    assert_equal 2, section.fetch("version")
    records = section.fetch("records")
    assert_equal [segment.fetch("id")], records.map { |record| record.fetch("building_segment_id") }.uniq
    assert_equal [original_segment.fetch("export_identifier")], records.map { |record|
      record.fetch("building_segment_export_identifier")
    }.uniq
    assert_equal ["Renamed"], records.map { |record| record.fetch("building_segment") }.uniq
    assert records.all? { |record| record.fetch("face_ids").length == 6 }
  end

  def test_stale_surface_geometry_is_accounted_without_repair
    zones = seed_two_boxes
    invoke("ph_composer.zones.solve_adjacency", "zones" => zones)
    right = @model.entities.to_a.find { |entity| entity.persistent_id == 2000 }
    right.transformation = Geom::Transformation.translation([1, 0, 0])
    names = contributor_names

    extraction = PhComposer::Export::Collection.build(@model, :run_id => "stale", :contributors => names)
    faces = extraction.document.dig("sections", names.first, "records")
    omitted = faces.select { |face| face["omission"] }
    assert_equal 2, omitted.length
    assert_equal ["adjacency.stale"], omitted.map { |face| face.dig("omission", "code") }.uniq
    assert omitted.all? { |face| face.dig("omission", "area_m2") > 0 }
    assert_equal omitted.map { |face| face.fetch("zone_id") }, omitted.map { |face| face.dig("omission", "zone_id") }
    records = right.entities.to_a.map { |face| PhComposer::Zones::Faces::FACE_STORE.read(face) }
    assert_equal 1, records.count { |record| record["boundary_condition"] == "Surface" }
  end

  def test_face_stamp_must_agree_with_detached_zone_containment
    seed_two_boxes
    face = @model.entities.to_a.first.entities.to_a.first
    stamp = PhComposer::Zones::STAMP_STORE.read(face).merge("zone_id" => "zon_#{'Z' * 12}")
    PhComposer::Zones::STAMP_STORE.write(face, stamp)

    error = assert_raises(PhComposer::Export::Blocked) do
      PhComposer::Export::Collection.build(@model, :run_id => "wrong-zone", :contributors => contributor_names)
    end

    assert_equal "face.wrong_zone", error.code
  end

  def test_classified_face_outside_every_zone_blocks_collection
    seed_two_boxes
    face = Sketchup::Face.new(9001, {}, :points => box_faces(10, 11).first.fetch(3),
                                        :normal => Geom::Vector3d.new(0, 0, -1))
    record = {
      "id" => "fac_Z00000000001", "schema_version" => 1, "face_type" => "Floor",
      "boundary_condition" => "Ground", "user_data" => {}, "extension_data" => {}
    }
    PhComposer::Zones::Faces::FACE_STORE.write(face, record)
    PhComposer::Zones::STAMP_STORE.write(
      face, "schema_version" => 1, "zone_id" => "zon_#{'A' * 12}",
            "building_segment" => "Main Building", "level" => "L1"
    )
    @model.entities << face

    error = assert_raises(PhComposer::Export::Blocked) do
      PhComposer::Export::Collection.build(@model, :run_id => "orphan", :contributors => contributor_names)
    end

    assert_equal "face.wrong_zone", error.code
  end

  def test_deleted_surface_counterpart_is_an_accounted_omission
    zones = seed_two_boxes
    invoke("ph_composer.zones.solve_adjacency", "zones" => zones)
    right = @model.entities.to_a.find { |entity| entity.persistent_id == 2000 }
    counterpart = right.entities.to_a.find do |face|
      PhComposer::Zones::Faces::FACE_STORE.read(face)["boundary_condition"] == "Surface"
    end
    right.entities.delete(counterpart)

    extraction = PhComposer::Export::Collection.build(@model, :run_id => "deleted", :contributors => contributor_names)
    faces = extraction.document.dig("sections", contributor_names.first, "records")
    assert_equal 11, faces.length
    omitted = faces.select { |face| face["omission"] }
    assert_equal 1, omitted.length
    assert_equal "adjacency.unresolved", omitted.first.dig("omission", "code")
  end

  def test_a_surface_face_whose_counterpart_moved_into_a_container_exports_as_unresolved
    zones = seed_two_boxes
    right = @model.entities.to_a.find { |entity| entity.persistent_id == 2000 }
    wall = right.entities.to_a.find { |entity| entity.persistent_id == 2003 }
    container = right.entities.add_group([wall])
    result = invoke("ph_composer.zones.solve_adjacency", "zones" => zones)
    assert_equal "completed", result["status"], result.inspect
    paired = PhComposer::Zones::Faces::FACE_STORE.read(wall)
    assert_equal "Surface", paired["boundary_condition"]
    PhComposer::Zones::STAMP_STORE.write(container,
                                         PhComposer::Zones::Schema.stamp(PhComposer::Zones::ZONE_STORE.read(right)))

    extraction = PhComposer::Export::Collection.build(@model, :run_id => "run-container-counterpart",
                                                              :contributors => contributor_names)

    faces = extraction.document.dig("sections", PhComposer::Zones::Faces::ExportProjection::SECTION, "records")
    assert_equal 11, faces.length
    assert_equal ["adjacency.unresolved"], faces.select { |face| face["boundary_condition"] == "Surface" }
                                                .map { |face| face.dig("omission", "code") }
  end

  private

  def contributor_names
    [PhComposer::Zones::Faces::ExportProjection::SECTION, PhComposer::Zones::ExportProjection::SECTION,
     PhComposer::Assemblies::ExportProjection::SECTION, PhComposer::Assemblies::SourceReport::SECTION,
     PhComposer::Spaces::ExportProjection::SECTION, PhComposer::ThermalBridges::ExportProjection::SECTION]
  end

  def seed_two_boxes
    @assembly_id = seed_export_construction
    left = box_group(1000, 0, 5, "A")
    right = box_group(2000, 5, 9, "B")
    @model.entities << left << right
    [left, right].map do |group|
      zone = PhComposer::Zones::ZONE_STORE.read(group)
      { "zone_id" => zone.fetch("id"), "zone_path" => [group.persistent_id] }
    end
  end

  def box_group(base, x_min, x_max, letter)
    points = box_faces(x_min, x_max)
    faces = points.each_with_index.map do |(face_type, boundary, normal, loop), index|
      face_id = format("fac_%<letter>s%<number>011d", :letter => letter, :number => index + 1)
      face = Sketchup::Face.new(base + index + 1, {}, :points => loop, :normal => Geom::Vector3d.new(*normal))
      record = {
        "id" => face_id, "schema_version" => 1, "face_type" => face_type,
        "boundary_condition" => boundary, "assembly_id" => @assembly_id, "user_data" => {}, "extension_data" => {}
      }
      PhComposer::Zones::Faces::FACE_STORE.write(face, record)
      face
    end
    group = Sketchup::Group.new(base, Sketchup::Entities.new(faces))
    zone = {
      "id" => "zon_#{letter * 12}", "schema_version" => 1, "name" => "Zone #{letter}",
      "building_segment" => "Main Building", "level" => "L1", "ground_depth_mm" => 0.0,
      "user_data" => {}, "extension_data" => {}
    }
    PhComposer::Zones::ZONE_STORE.write(group, zone)
    stamp = PhComposer::Zones::Schema.stamp(zone)
    faces.each { |face| PhComposer::Zones::STAMP_STORE.write(face, stamp) }
    group
  end

  def box_faces(x_min, x_max)
    m = 1.0 / 0.0254
    x0, x1, y0, y1, z0, z1 = [x_min, x_max, 0, 4, 0, 3].map { |value| value * m }
    [
      ["Floor", "Ground", [0, 0, -1], [point(x0, y0, z0), point(x0, y1, z0), point(x1, y1, z0), point(x1, y0, z0)]],
      ["RoofCeiling", "Outdoors", [0, 0, 1],
       [point(x0, y0, z1), point(x1, y0, z1), point(x1, y1, z1), point(x0, y1, z1)]],
      ["Wall", "Outdoors", [-1, 0, 0], [point(x0, y0, z0), point(x0, y0, z1), point(x0, y1, z1), point(x0, y1, z0)]],
      ["Wall", "Outdoors", [1, 0, 0], [point(x1, y0, z0), point(x1, y1, z0), point(x1, y1, z1), point(x1, y0, z1)]],
      ["Wall", "Outdoors", [0, -1, 0], [point(x0, y0, z0), point(x1, y0, z0), point(x1, y0, z1), point(x0, y0, z1)]],
      ["Wall", "Outdoors", [0, 1, 0], [point(x0, y1, z0), point(x0, y1, z1), point(x1, y1, z1), point(x1, y1, z0)]]
    ]
  end

  def point(x, y, z)
    Geom::Point3d.new(x, y, z)
  end

  def invoke(name, params)
    PhComposer::API.invoke(
      :context => @context, :name => name, :params => params,
      :request => { "sequence" => @sequence += 1, "expected_revision" => @session.revision }
    )
  end
end
