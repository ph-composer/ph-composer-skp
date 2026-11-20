# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/construction_export_fixtures"
require_relative "support/space_fixtures"
require_relative "support/zone_options"

# What export does with Building Segments, over a synthetic two-Segment reference: Living and Kitchen in House,
# and one ADU Zone in ADU whose west wall is two Faces, one shared with each House Zone. A Zone in no Building
# Segment is left out with its Faces, Spaces, Edges and the Windows on its Faces; a Building Segment no Zone
# names is left out; a Surface pair across the boundary refuses until the Zone moved out is made the Attached
# zone of those Faces, which the offer read names and the Attached zone actions apply in one Undo step.
class SegmentExportRulesTest < PhComposerTestCase
  include ConstructionExportFixtures
  include FixtureFiles
  include SpaceFixtures
  include ZoneOptionsSupport

  API = PhComposer::API
  Z = PhComposer::Zones
  TB = PhComposer::ThermalBridges
  FIXTURE = File.join(TESTS_ROOT, "fixtures", "segments", "extraction.json")
  ZONES = Z::ExportProjection::SECTION
  FACES = Z::Faces::ExportProjection::SECTION
  OFFER = "ph_composer.zones.faces.attached_zone.offer"
  PARAPET = "tbt_PARAPET00001"

  def setup
    super
    @model = Sketchup.active_model
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @assembly_id = seed_export_construction
    TB::Type::KIND.store.write(@model, "id" => PARAPET, "schema_version" => 1, "name" => "Parapet", "notes" => "",
                                       "datasheet_links" => [], "source" => { "kind" => "manual" },
                                       "psi_w_mk" => 0.05, "group" => "15-Ambient")
  end

  # ---------------------------------------------------------------- the export minimum

  def test_with_no_zone_in_a_building_segment_export_refuses
    reference
    move(%w[Living Kitchen ADU], nil)

    blocking = preflight.select { |row| row.fetch("blocks_export") }
    assert_equal ["zone.no_segment"], blocking.map { |row| row.fetch("code") }
    assert_equal "zone.no_segment", assert_raises(PhComposer::Export::Blocked) { extract }.code
  end

  # ---------------------------------------------------------------- leaving out

  def test_a_zone_in_no_segment_leaves_with_its_faces_spaces_and_edges_and_owns_the_golden
    reference
    move(%w[ADU], nil)
    make_attached_zone("ADU")

    findings = preflight
    assert_empty findings.select { |row| row.fetch("blocks_export") }, findings.inspect
    info = findings.to_h { |row| [row.fetch("code"), row] }
    assert_includes info.fetch("zone.left_out").fetch("message"), "ADU (8 Faces)"
    assert_equal zone_id("ADU"), info.fetch("space.zone_left_out").fetch("object_id")
    assert_includes info.fetch("thermal_bridge.zone_left_out").fetch("message"), "1 assigned Edge in Zone ADU"
    assert_equal segment_id("ADU"), info.fetch("zone.segment_empty").fetch("object_id")

    extraction = extract
    sections = extraction.document.fetch("sections")
    assert_equal %w[Kitchen Living], sections.fetch(ZONES).fetch("records").map { |row| row.fetch("name") }.sort
    faces = sections.fetch(FACES).fetch("records")
    assert_equal 12, faces.length
    refute(faces.any? { |row| row.fetch("zone_id") == zone_id("ADU") })
    attached = faces.select { |row| row["boundary_condition"] == "AttachedZone" }
    assert_equal [["ADU", 0.95]], attached.map { |row|
      row.fetch("attached_zone").values_at("name", "temperature_reduction_factor")
    }.uniq
    assert_equal 2, attached.map { |row| row.fetch("zone_id") }.uniq.length, "one Attached zone on two Rooms"
    assert_empty sections.fetch("ph_composer.spaces.export.spaces").fetch("records")
    runs = sections.fetch("ph_composer.thermal_bridges.export.thermal_bridges").fetch("records")
    assert_equal [zone_id("Living")], runs.map { |row| row.fetch("zone_id") }
    notes = extraction.findings.map { |row| row.fetch("code") }
    assert_equal 1, notes.count("zone.left_out")
    assert_includes notes, "zone.segment_empty"
    assert_includes notes, "space.zone_left_out"
    assert_includes notes, "thermal_bridge.zone_left_out"
    write_or_compare(FIXTURE, stable(extraction.document))
  end

  def test_a_surface_face_paired_with_a_left_out_zone_refuses_naming_the_face
    reference
    move(%w[ADU], nil)

    partner = preflight.select { |row| row.fetch("code") == "face.partner_left_out" }
    assert_equal %w[fac_K00000000004 fac_L00000000004], partner.map { |row| row.fetch("object_id") }.sort
    assert(partner.all? { |row| row.fetch("blocks_export") && row.fetch("message").include?("Zone ADU") })
    error = assert_raises(PhComposer::Export::Blocked) { extract }
    assert_equal "face.partner_left_out", error.code
    assert_match(/Face fac_[KL]00000000004 /, error.message)
  end

  # ---------------------------------------------------------------- the offer

  def test_the_offer_reclassifies_both_sides_in_one_undo_step_and_reuses_a_named_attached_zone
    reference
    move(%w[ADU], nil)
    offer = query(OFFER, "zone" => zone_reference("ADU"))
    assert_equal ["ADU", nil, %w[Kitchen Living], 0],
                 offer.values_at("name", "attached_zone_id", "shared_with", "attached_face_count")
    assert_equal %w[fac_A00000000003 fac_A00000000004 fac_K00000000004 fac_L00000000004],
                 offer.fetch("faces").map { |face| face.fetch("entity_id") }.sort
    operations = @model.operations.length

    created = completed(invoke("ph_composer.zones.faces.attached_zone.create_and_assign",
                               "faces" => offer.fetch("faces"), "values" => { "name" => "ADU", "kind" => "other" },
                               "expected_values" => { "boundary_condition" => "Surface" }))

    assert_equal operations + 1, @model.operations.length
    after = face_records(offer)
    assert(after.all? { |record|
      record.values_at("boundary_condition", "attached_zone_id") == ["AttachedZone", created.fetch("id")]
    })
    assert(after.none? { |record| record.key?("adjacency") || record.key?("assembly_reversed") })
    @model.undo
    assert(face_records(offer).all? { |record| record["boundary_condition"] == "Surface" && record["adjacency"] })
    assert_nil Z::Faces::AttachedZone::STORE.read(@model, created.fetch("id"))

    # An Attached zone already named for the Zone is reused, through classify.
    saved = completed(invoke("ph_composer.zones.faces.attached_zone.save",
                             "values" => { "name" => "ADU", "kind" => "garage" }))
    offer = query(OFFER, "zone" => zone_reference("ADU"))
    assert_equal saved.fetch("id"), offer.fetch("attached_zone_id")
    completed(invoke("ph_composer.zones.faces.classify", "faces" => offer.fetch("faces"),
                                                         "expected_values" => { "boundary_condition" => "Surface" },
                                                         "intent" => {
                                                           "boundary_condition" => { "mode" => "set",
                                                                                     "value" => "AttachedZone" },
                                                           "attached_zone_id" => { "mode" => "set",
                                                                                   "value" => saved.fetch("id") }
                                                         }))
    assert_equal [saved.fetch("id")], face_records(offer).map { |record| record["attached_zone_id"] }.uniq

    # Moved back, the Faces stay Attached zone, and the read counts them for the notice.
    move(%w[ADU], "ADU")
    moved_back = query(OFFER, "zone" => zone_reference("ADU"))
    assert_equal [2, []], moved_back.values_at("attached_face_count", "faces")
  end

  # Solve pairs coincident Faces whatever their boundary, so while a Zone is left out the preflight's Solve
  # repair is unchecked: run by default, it would pair again the Faces the offer made an Attached zone.
  def test_the_solve_repair_is_unchecked_while_a_zone_is_left_out
    reference
    solve = ->(rows) { rows.find { |row| row.fetch("id").end_with?("solve_all") } }
    assert solve.call(completed(API.export_preflight(:context => @context)).fetch("repairs")).fetch("checked")
    move(%w[ADU], nil)
    make_attached_zone("ADU")

    repair = solve.call(completed(API.export_preflight(:context => @context)).fetch("repairs"))

    refute repair.fetch("checked")
    assert_includes repair.fetch("label"), "Attached zone of a Zone in no Building Segment"
  end

  # What sits inside a left-out Zone is not read: a reserved metadata key on its Volume or Edge and a copied
  # Space identity there block neither the preflight nor the extraction.
  def test_records_inside_a_left_out_zone_are_neither_validated_nor_read
    reference
    move(%w[ADU], nil)
    make_attached_zone("ADU")
    adu = @model.entities.to_a.find { |entity| entity.persistent_id == 3000 }
    volume = adu.entities.to_a.find { |entity| entity.persistent_id == 3050 }.entities.to_a.first
    PhComposer::Spaces::VOLUME_STORE.write(volume, PhComposer::Spaces::VOLUME_STORE.read(volume)
                                                     .merge("user_data" => { "ph_composer" => { "x" => 1 } }))
    edge = adu.entities.to_a.find { |entity| entity.persistent_id == 3090 }
    TB::Assignment::STORE.write(edge, TB::Assignment::STORE.read(edge).merge("user_data" => { "ph_composer" => 1 }))
    copy = space_group(3150, space_record("A", :number => "2", :name => "Copy"),
                       [volume_group(3160, volume_record("C"), [floor_face(3170, rectangle(6, 5, 1, 1),
                                                                           segment_record("C"))])])
    adu.entities << copy
    UI.run_timers

    assert_empty preflight.select { |row| row.fetch("blocks_export") }
    assert_empty extract.document.dig("sections", "ph_composer.spaces.export.spaces", "records")
  end

  # ---------------------------------------------------------------- shading and the Site

  def test_a_marked_face_in_a_left_out_zone_still_exports_as_its_zones_shade
    reference(:overhang => true)
    move(%w[ADU], nil)
    make_attached_zone("ADU")

    shades = extract.document.dig("sections", "ph_composer.shading.export.shades", "records")
    assert_equal ["ADU Shading"], shades.map { |row| row.fetch("display_name") }
  end

  def test_a_mark_above_a_left_out_zone_reaches_none_of_its_faces
    reference(:wrapped => true)
    move(%w[ADU], nil)
    make_attached_zone("ADU")

    assert_empty extract.document.dig("sections", "ph_composer.shading.export.shades", "records")
  end

  private

  # The reference: Living (x 0 to 5 m, y 0 to 4 m) and Kitchen (y 4 to 8 m) in House, ADU (x 5 to 9 m) in ADU,
  # each 3 m high, adjacencies solved and each interior pair's Assembly assigned from its first side. Living and
  # ADU each hold one assigned Edge, and ADU one Space, whose Floor Segment counts among the Zone's Faces.
  # `overhang` adds a marked Face inside ADU; `wrapped` puts ADU inside a marked Group.
  def reference(overhang: false, wrapped: false)
    living = box(1000, "L", "Living", "House", [0, 5, 0, 4], :edge => 1090)
    kitchen = box(2000, "K", "Kitchen", "House", [0, 5, 4, 8])
    adu = box(3000, "A", "ADU", "ADU", [5, 9, 0, 8], :split_west => true, :space => true, :edge => 3090,
                                                     :overhang => overhang)
    if wrapped
      site = Sketchup::Group.new(3900, Sketchup::Entities.new([adu]), :name => "Site")
      PhComposer::Shading::Mark::STORE.write(site, "schema_version" => 1)
      adu = site
    end
    @model.entities << living << kitchen << adu
    adopt_zone_options
    completed(invoke("ph_composer.zones.solve_adjacency", "zones" => zone_rows.map { |row| row.fetch("reference") }))
    assign_pair_assemblies
  end

  def box(base, letter, name, segment, (x_min, x_max, y_min, y_max), split_west: false, space: false, edge: nil,
          overhang: false)
    children = box_faces(x_min, x_max, y_min, y_max, split_west).each_with_index.map do |(type, normal, loop), index|
      face = Sketchup::Face.new(base + index + 1, {}, :points => loop.map { |xyz| metres(xyz) },
                                                      :normal => Geom::Vector3d.new(*normal))
      Z::Faces::FACE_STORE.write(face, "id" => format("fac_%<letter>s%<number>011d", :letter => letter,
                                                                                     :number => index + 1),
                                       "schema_version" => 1, "face_type" => type,
                                       "boundary_condition" => type == "Floor" ? "Ground" : "Outdoors",
                                       "assembly_id" => @assembly_id, "user_data" => {}, "extension_data" => {})
      face
    end
    faces = children.dup
    if overhang
      shade = Sketchup::Face.new(base + 80, {}, :points => [[x_max, y_min, 3], [x_max + 1, y_min, 3],
                                                            [x_max + 1, y_max, 3]].map { |xyz| metres(xyz) })
      PhComposer::Shading::Mark::STORE.write(shade, "schema_version" => 1)
      children << shade
    end
    if space
      children << space_group(base + 50, space_record(letter, :number => "1", :name => name),
                              [volume_group(base + 60, volume_record(letter),
                                            [floor_face(base + 70, rectangle(x_min + 1, y_min + 1, 2, 2),
                                                        segment_record(letter))])])
    end
    if edge
      line = Sketchup::Edge.new(edge, metres([x_min, y_min, 3]), metres([x_min + 1, y_min, 3]))
      TB::Assignment::STORE.write(line, "id" => "tbe_#{format('%012d', edge)}", "schema_version" => 1,
                                        "thermal_bridge_type_id" => PARAPET, "quantity" => 1, "user_data" => {},
                                        "extension_data" => {})
      children << line
    end
    group = Sketchup::Group.new(base, Sketchup::Entities.new(children), :name => name)
    zone = { "id" => "zon_#{letter * 12}", "schema_version" => 1, "name" => name, "building_segment" => segment,
             "level" => "L1", "ground_depth_mm" => 0.0, "user_data" => {}, "extension_data" => {} }
    Z::ZONE_STORE.write(group, zone)
    stamp = Z::Schema.stamp(zone)
    faces.each { |face| Z::STAMP_STORE.write(face, stamp) }
    host_children(children, zone.fetch("id"))
    group
  end

  # Floor, roof, then the walls west, east, south and north, outward normals; with `split_west` the west wall
  # is two Faces, split at y = 4 m.
  def box_faces(x0, x1, y0, y1, split_west)
    west = if split_west
             [[x0, y0, 0], [x0, y0, 3], [x0, 4, 3], [x0, 4, 0]].then do |south|
               [south, [[x0, 4, 0], [x0, 4, 3], [x0, y1, 3], [x0, y1, 0]]]
             end
           else
             [[[x0, y0, 0], [x0, y0, 3], [x0, y1, 3], [x0, y1, 0]]]
           end
    [["Floor", [0, 0, -1], [[x0, y0, 0], [x0, y1, 0], [x1, y1, 0], [x1, y0, 0]]],
     ["RoofCeiling", [0, 0, 1], [[x0, y0, 3], [x1, y0, 3], [x1, y1, 3], [x0, y1, 3]]]] +
      west.map { |loop| ["Wall", [-1, 0, 0], loop] } +
      [["Wall", [1, 0, 0], [[x1, y0, 0], [x1, y1, 0], [x1, y1, 3], [x1, y0, 3]]],
       ["Wall", [0, -1, 0], [[x0, y0, 0], [x1, y0, 0], [x1, y0, 3], [x0, y0, 3]]],
       ["Wall", [0, 1, 0], [[x0, y1, 0], [x0, y1, 3], [x1, y1, 3], [x1, y1, 0]]]]
  end

  def metres(xyz)
    Geom::Point3d.new(*xyz.map { |value| value * INCHES })
  end

  # Each Surface pair's Assembly from its first side by id, so the other side holds it reversed.
  def assign_pair_assemblies
    rows = query("ph_composer.zones.faces.all", {}).fetch("faces")
    pairs = rows.select { |row| row.dig("values", "boundary_condition") == "Surface" }
    pairs.group_by { |row|
      [row.dig("reference", "entity_id"), row.dig("values", "adjacency", "counterpart", "entity_id")].sort
    }
         .each_value do |sides|
      side = sides.min_by { |row| row.dig("reference", "entity_id") }
      completed(invoke("ph_composer.zones.faces.assign_assembly",
                       "assembly_id" => @assembly_id,
                       "targets" => [{ "reference" => side.fetch("reference"),
                                       "expected_values" => side.fetch("values") }]))
    end
  end

  # The document with the Building Segment and Attached zone ids adoption and create mint, which differ each
  # run, renumbered in order of first appearance, so the golden compares.
  def stable(document)
    seen = {}
    text = JSON.generate(document).gsub(/\b(bsg|atz)_[A-Za-z0-9]{12}\b/) do |id|
      seen[id] ||= format("%<prefix>s_FIXED%<number>07d", :prefix => Regexp.last_match(1), :number => seen.length + 1)
    end
    JSON.parse(text)
  end

  def make_attached_zone(name)
    offer = query(OFFER, "zone" => zone_reference(name))
    completed(invoke("ph_composer.zones.faces.attached_zone.create_and_assign",
                     "faces" => offer.fetch("faces"), "values" => { "name" => name, "kind" => "other" },
                     "expected_values" => { "boundary_condition" => "Surface" }))
  end

  def move(names, segment)
    targets = zone_rows.select { |row| names.include?(row.dig("values", "name")) }.map do |row|
      { "reference" => row.fetch("reference"), "expected_values" => row.fetch("values") }
    end
    completed(invoke("ph_composer.zones.update_field", "field" => "building_segment", "value" => segment,
                                                       "targets" => targets))
  end

  def zone_rows
    query("ph_composer.zones.all", {}).fetch("zones")
  end

  def zone_reference(name)
    zone_rows.find { |row| row.dig("values", "name") == name }.fetch("reference")
  end

  def zone_id(name)
    zone_reference(name).fetch("zone_id")
  end

  def segment_id(name)
    query("ph_composer.zones.options.all", {}).fetch("building_segments")
                                              .find { |row| row.dig("values", "name") == name }.fetch("id")
  end

  def face_records(offer)
    offer.fetch("faces").map do |reference|
      Z::Faces::FACE_STORE.read(Z::Occurrences.resolve_face(@model, reference).entity)
    end
  end

  def preflight
    completed(API.export_preflight(:context => @context)).fetch("findings")
  end

  def extract
    PhComposer::Export::Collection.build(@model, :run_id => "segment-export-rules")
  end

  def query(name, params)
    completed(API.query(:context => @context, :name => name, :params => params))
  end

  def completed(outcome)
    assert_equal "completed", outcome.fetch("status"), outcome.inspect
    outcome.fetch("value")
  end

  def invoke(name, params)
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence += 1, "expected_revision" => @session.revision })
  end
end
