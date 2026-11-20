# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/construction_export_fixtures"

# A Face inside a Zone whose own entity, or a Group or component between it and the Zone, carries the record of
# a store built with `excludes_from_envelope: true` leaves the Zone's envelope at every Zones call site
# (context/CONTRACTS.md, "Zones geometry rules"). The Zones-side tests use a neutral excluding store, so they
# show the rule names no feature; the last tests drive the same Model through Shading. Each call-site test runs
# with the record set on the Face itself and on a Group above another Face, then with both cleared.
class ZonesEnvelopeExclusionTest < PhComposerTestCase
  include ConstructionExportFixtures

  API = PhComposer::API
  Zones = PhComposer::Zones
  FACE_STORE = Zones::Faces::FACE_STORE
  EXCLUDING = PhComposer::Records::EntityStore.new("ph_composer.test_envelope_exclusion",
                                                   :excludes_from_envelope => true)
  SPACE_STORE = PhComposer::Spaces::SPACE_STORE
  EXCLUDED = [[1000, 1010], [1000, 1020, 1021]].freeze
  M = 1.0 / 0.0254

  def setup
    super
    PhComposer.compose unless PhComposer::Registry.installed?(PhComposer::Shading::FEATURE_ID)
    @model = Sketchup.active_model
    settings = Zones::Faces::Settings
    settings::STORE.write(@model, settings::DEFAULTS.merge("suggest_on_make" => false))
    @session = PhComposer::Sessions.for(@model)
    @context = API.connect(:session_id => @session.id)
    @sequence = 0
    @assembly_id = seed_export_construction
    @zone_a = box_group(1000, 0, 5, "A")
    @zone_b = box_group(2000, 5, 9, "B")
    # Zone A also holds an overhang Face 1010 and a Group "Fin" (1020) of Face 1021, neither classified.
    up = Geom::Vector3d.new(0, 0, 1)
    @overhang = Sketchup::Face.new(1010, {}, :points => rectangle_z(0, 5, -2, 0, 3), :normal => up)
    @fin_face = Sketchup::Face.new(1021, {}, :points => rectangle_z(0, 5, 4, 6, 3), :normal => up)
    @fin = Sketchup::Group.new(1020, Sketchup::Entities.new([@fin_face]), :name => "Fin")
    stamp = Zones::Schema.stamp(Zones::ZONE_STORE.read(@zone_a))
    [@overhang, @fin_face].each { |face| Zones::STAMP_STORE.write(face, stamp) }
    @zone_a.entities << @overhang << @fin
    @model.entities << @zone_a << @zone_b
  end

  # Funnel A, behind faces.list and faces.all (and every reader of Index#faces, such as Window Unit host Faces).
  def test_face_reads_leave_out_an_excluded_face
    each_state do |excluded|
      listed = query("ph_composer.zones.faces.list").dig("value", "faces").map { |row| path_of(row) }
      all = query("ph_composer.zones.faces.all").dig("value", "faces").map { |row| path_of(row) }
      assert_equal !excluded, EXCLUDED.all? { |path| listed.include?(path) }, listed.inspect
      assert_equal !excluded, EXCLUDED.all? { |path| all.include?(path) }, all.inspect
      assert_equal 12, listed.length - (excluded ? 0 : 2)
    end
  end

  def test_zone_view_counts_leave_out_an_excluded_face
    each_state do |excluded|
      zone = zone_row("Zone A")
      assert_equal excluded ? 6 : 8, zone.fetch("face_count")
      assert_equal excluded, zone.fetch("unclassified_face_area_m2").zero?
    end
  end

  def test_suggest_classification_leaves_an_excluded_face_without_a_record
    mark
    result = invoke("ph_composer.zones.faces.auto_classify", "zone" => zone_reference(@zone_a))
    assert_equal "completed", result["status"], result.inspect
    assert_equal 0, result.dig("value", "classified")
    assert_nil FACE_STORE.read(@overhang)
    assert_nil FACE_STORE.read(@fin_face)
    clear
    result = invoke("ph_composer.zones.faces.auto_classify", "zone" => zone_reference(@zone_a))
    assert_equal 2, result.dig("value", "classified")
  end

  def test_the_unclassified_preflight_row_leaves_out_an_excluded_face
    each_state do |excluded|
      findings = query("ph_composer.zones.faces.export_preflight").dig("value", "findings")
      assert_equal excluded ? 0 : 2, findings.count { |row| row.fetch("code") == "face.unclassified" }
    end
  end

  def test_face_colour_modes_leave_out_an_excluded_face
    each_state do |excluded|
      paths = Zones::Faces::ColourModes.entries(@model, "face_type", {}).map(&:path)
      assert_equal !excluded, EXCLUDED.all? { |path| paths.include?(path) }
      assert_equal excluded ? 12 : 14, paths.length
    end
  end

  # Attached zone references and Assembly retargets list referencing Faces through funnel A.
  def test_attached_zone_references_leave_out_an_excluded_face
    record = FACE_STORE.read(face_at(@zone_a, 1003)).merge("boundary_condition" => "AttachedZone",
                                                           "attached_zone_id" => "atz_AAAAAAAAAAAA")
    FACE_STORE.write(@overhang, record.merge("id" => "fac_F00000000001"))
    each_state do |excluded|
      found = Zones::Faces.referencing_faces(@model, "atz_AAAAAAAAAAAA").map { |occurrence, _| occurrence.entity }
      assert_equal(excluded ? [] : [@overhang], found)
    end
  end

  # A classified Face carrying the excluding record itself is in no Face inventory, so an Assembly replacement or
  # an Attached zone delete cannot reach it: each refuses and says to clear what took it out of the envelope.
  def test_stranded_records_inside_the_envelope_name_the_exclusion
    record = FACE_STORE.read(face_at(@zone_a, 1003)).merge("id" => "fac_F00000000001",
                                                           "boundary_condition" => "AttachedZone",
                                                           "attached_zone_id" => "atz_AAAAAAAAAAAA")
    FACE_STORE.write(@overhang, record)
    EXCLUDING.write(@overhang, "schema_version" => 1)
    request = PhComposer::HandlerRequest.for(@session, :owner => Zones::FEATURE_ID, :name => "test",
                                                       :registry => PhComposer::Registry.current)
    retarget = assert_raises(PhComposer::CodedError) do
      Zones::Faces::AssemblyAssignment.retarget(request, PhComposer::Operations::Proposal.new,
                                                :from => @assembly_id, :to => "asm_Other0000001")
    end
    delete = assert_raises(PhComposer::CodedError) do
      Zones::Faces.send(:reassignable_faces, @model, "atz_AAAAAAAAAAAA")
    end
    errors = [retarget, delete]
    errors.each do |error|
      assert_equal "reference.in_use", error.code
      assert_includes error.message, "clear what takes it out of its Zone's envelope"
    end
  end

  # Funnel B, behind the Classify tool's hover and click, the selection read and faces.host_context.
  def test_point_reads_find_no_zone_face_for_an_excluded_face
    each_state do |excluded|
      [[@zone_a, @overhang], [@zone_a, @fin, @fin_face]].each do |entities|
        occurrence = Zones::Occurrences.occurrence_for_path(entities)
        assert_equal excluded, occurrence.nil?
        found = Zones::Occurrences.containment(@model, entities.map(&:persistent_id))
        assert_equal(excluded ? "outside_envelope" : nil, found.reason)
      end
      rows = query("ph_composer.zones.faces.host_context", "paths" => EXCLUDED).dig("value", "faces")
      assert_equal excluded ? [] : EXCLUDED, rows.map { |row| row.fetch("path") }
    end
  end

  def test_an_edge_beside_an_excluded_face_still_reads_its_zone
    mark
    edge = Sketchup::Edge.new(1030, Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(1, 0, 0))
    @fin.entities << edge
    found = Zones::Occurrences.containment(@model, [1000, 1020, 1030])
    assert_nil found.reason
    assert_equal [1020, 1030], found.entity_path
    reference = zone_reference(@zone_a).merge("entity_path" => [1020, 1030])
    assert_same edge, Zones::Occurrences.resolve_element(@model, reference, :noun => "Edge").entity
  end

  def test_the_classify_tool_and_the_selection_menu_leave_an_excluded_face_alone
    mark
    tool = Zones::Faces.classify_tool(@session)
    tool.choose("face_type", "Wall")
    view = @model.active_view
    view.picks[[10, 10]] = [@zone_a, @overhang]
    before = @model.operations.length
    tool.onLButtonDown(0, 10, 10, view)
    tool.onLButtonUp(0, 10, 10, view)
    assert_equal before, @model.operations.length
    assert_nil FACE_STORE.read(@overhang)
    @model.active_path = [@zone_a]
    @model.selection.add(@overhang)
    refute Zones::Faces::ClassifyMenu.classifiable?(@session)
    clear
    assert Zones::Faces::ClassifyMenu.classifiable?(@session)
  end

  # Funnel C: an explicit reference to an excluded Face, read or written.
  def test_an_explicit_reference_to_an_excluded_face_refuses_outside_envelope
    mark
    EXCLUDED.each do |path|
      reference = zone_reference(@zone_a).merge("entity_path" => path[1..-1], "entity_id" => nil)
      error = assert_raises(PhComposer::CodedError) do
        Zones::Occurrences.resolve_face(@model, reference, :allow_unassigned => true)
      end
      assert_equal "face.outside_envelope", error.code
      refute_match(/shading|mark/i, error.message)
      result = invoke("ph_composer.zones.faces.classify",
                      "faces" => [reference], "intent" => { "face_type" => { "mode" => "set", "value" => "Wall" } })
      assert_equal %w[refused face.outside_envelope none], result.values_at("status", "code", "effect")
      result = invoke("ph_composer.zones.faces.reverse", "face" => reference)
      assert_equal %w[refused face.outside_envelope], result.values_at("status", "code")
    end
    clear
    reference = zone_reference(@zone_a).merge("entity_path" => [1010], "entity_id" => nil)
    result = invoke("ph_composer.zones.faces.classify",
                    "faces" => [reference], "intent" => { "face_type" => { "mode" => "set", "value" => "Wall" } })
    assert_equal "completed", result["status"], result.inspect
  end

  # Solve's candidates come from funnel A, so an excluded wall makes no Surface pair and is never cut.
  def test_solve_adjacencies_does_not_pair_an_excluded_face
    shared = face_at(@zone_a, 1004)
    EXCLUDING.write(shared, "schema_version" => 1)
    result = invoke("ph_composer.zones.solve_adjacency", "zones" => [zone_reference(@zone_a), zone_reference(@zone_b)])
    assert_equal "completed", result["status"], result.inspect
    assert_equal "Outdoors", FACE_STORE.read(shared)["boundary_condition"]
    assert_equal "Outdoors", FACE_STORE.read(face_at(@zone_b, 2003))["boundary_condition"]
    EXCLUDING.delete(shared)
    invoke("ph_composer.zones.solve_adjacency", "zones" => [zone_reference(@zone_a), zone_reference(@zone_b)])
    assert_equal "Surface", FACE_STORE.read(shared)["boundary_condition"]
  end

  # A partial overlap cuts the shared wall when it is in the envelope and leaves it whole when it is not.
  def test_solve_does_not_split_an_excluded_face
    @model.entities.delete(@zone_b)
    @zone_b = box_group(2000, 5, 9, "B", 2)
    @model.entities << @zone_b
    shared = face_at(@zone_a, 1004)
    EXCLUDING.write(shared, "schema_version" => 1)
    zones = [zone_reference(@zone_a), zone_reference(@zone_b)]
    assert_equal "completed", invoke("ph_composer.zones.solve_adjacency", "zones" => zones)["status"]
    assert_equal 1, faces_in(@zone_a).length
    EXCLUDING.delete(shared)
    result = invoke("ph_composer.zones.solve_adjacency", "zones" => zones)
    assert_equal "completed", result["status"], result.inspect
    assert_equal 2, faces_in(zone_group(1000)).length
  end

  # Identity maintenance is no envelope read: the stamp writer and Zone copy repair keep every member Face,
  # excluded or not, in step with its Zone, so clearing the mark returns a Face that still names it.
  def test_zone_stamp_writer_and_copy_repair_keep_an_excluded_member_in_step
    mark
    zone = Zones::Occurrences.zones(@model).find { |row| row.path == [1000] }
    members = Zones::Repair.send(:member_entries, zone).map { |entry| entry.fetch(:occurrence).path }
    assert_equal EXCLUDED.map { |path| path[1..-1] }, EXCLUDED.map { |path| path[1..-1] } & members
    before = Zones::ZONE_STORE.read(@zone_a)
    Zones::UpdateZoneStep.new(:reference => zone_reference(@zone_a), :before => before,
                              :after => before.merge("level" => "L2")).apply(@model, {})
    assert_equal "L2", Zones::STAMP_STORE.read(face_at(@zone_a, 1001))["level"]
    assert_equal "L2", Zones::STAMP_STORE.read(@overhang)["level"]
    assert_equal "L2", Zones::STAMP_STORE.read(@fin_face)["level"]
    assert_same @overhang, Zones::Occurrences.face_at(zone, [1010], :envelope => false).entity
  end

  # Funnel D: the Zones section's Room and its blocking face.unclassified, and the Faces section's projection.
  def test_export_leaves_an_excluded_face_out_of_the_room_and_the_faces_section
    mark
    extraction = collect
    assert_empty extraction.findings.select { |row| row.fetch("code") == "face.unclassified" }
    room = zone_record(extraction, "zon_AAAAAAAAAAAA")
    assert_equal 6, room.fetch("face_ids").length
    projected = Zones::Faces::ExportProjection.send(:zone_faces, reader).map(&:path)
    assert_empty EXCLUDED & projected
    assert_equal 12, projected.length
    clear
    error = assert_raises(PhComposer::Export::Blocked) { collect }
    assert_equal "face.unclassified", error.code
  end

  # A classified Face can leave the envelope (a Group above it marked after it was classified): its record
  # stays in the Model but leaves the export, and its Surface partner is omitted as having no other side.
  def test_an_excluded_face_with_a_record_leaves_the_export_and_its_surface_partner_omits
    invoke("ph_composer.zones.solve_adjacency", "zones" => [zone_reference(@zone_a), zone_reference(@zone_b)])
    [@overhang, @fin_face].each { |face| EXCLUDING.write(face, "schema_version" => 1) }
    shared = face_at(@zone_a, 1004)
    EXCLUDING.write(shared, "schema_version" => 1)
    faces = collect.document.dig("sections", Zones::Faces::ExportProjection::SECTION, "records")
    refute(faces.any? { |row| row.fetch("id") == FACE_STORE.read(shared).fetch("id") })
    partner = faces.find { |row| row.fetch("id") == FACE_STORE.read(face_at(@zone_b, 2003)).fetch("id") }
    assert_equal "adjacency.unresolved", partner.dig("omission", "code")
    EXCLUDING.delete(shared)
    faces = collect.document.dig("sections", Zones::Faces::ExportProjection::SECTION, "records")
    assert_nil faces.find { |row| row.fetch("id") == FACE_STORE.read(face_at(@zone_b, 2003)).fetch("id") }["omission"]
  end

  # Classify and Solve retire the visible side of a pair whose other side has left the envelope, alone.
  # The excluded side carries the record itself and sits in a Group locked after Solve: the lock does not stop
  # the visible side.
  def test_retiring_a_pair_leaves_an_excluded_counterpart_unwritten
    partner = face_at(@zone_b, 2003)
    @zone_b.entities.delete(partner)
    holder = Sketchup::Group.new(2040, Sketchup::Entities.new([partner]))
    @zone_b.entities << holder
    zones = [zone_reference(@zone_a), zone_reference(@zone_b)]
    invoke("ph_composer.zones.solve_adjacency", "zones" => zones)
    [@overhang, @fin_face].each { |face| EXCLUDING.write(face, "schema_version" => 1) }
    shared = face_at(@zone_a, 1004)
    assert_equal "Surface", FACE_STORE.read(partner)["boundary_condition"]
    EXCLUDING.write(partner, "schema_version" => 1)
    holder.locked = true
    kept = FACE_STORE.read(partner)
    reference = zone_reference(@zone_a).merge("entity_path" => [1004], "entity_id" => FACE_STORE.read(shared)["id"])
    result = invoke("ph_composer.zones.faces.classify",
                    "faces" => [reference],
                    "intent" => { "boundary_condition" => { "mode" => "set", "value" => "Outdoors" } })
    assert_equal "completed", result["status"], result.inspect
    assert_equal "Outdoors", FACE_STORE.read(shared)["boundary_condition"]
    assert_equal kept, FACE_STORE.read(partner)
    @model.undo
    result = invoke("ph_composer.zones.solve_adjacency", "zones" => [zone_reference(@zone_a)])
    assert_equal "completed", result["status"], result.inspect
    retired = FACE_STORE.read(face_at(zone_group(1000), 1004))
    assert_nil retired["adjacency"]
    refute_equal "Surface", retired["boundary_condition"]
    assert_equal kept, FACE_STORE.read(face_at(face_at(zone_group(2000), 2040), 2003))
  end

  # The rule's edges, live and in the snapshot: a component's record excludes as a Group's does; a record on
  # the Zone Group itself never reaches its Faces; a claimed container between wins over a record above it.
  def test_a_component_excludes_a_zone_group_does_not_and_a_claim_wins
    louvre = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([Sketchup::Face.new(1061)]))
    placed = Sketchup::ComponentInstance.new(1060, louvre)
    space = Sketchup::Group.new(1071, Sketchup::Entities.new([Sketchup::Face.new(1072)]))
    SPACE_STORE.write(space, "id" => "spc_AAAAAAAAAAAA")
    holder = Sketchup::Group.new(1070, Sketchup::Entities.new([space]))
    @zone_a.entities << placed << holder
    [placed, holder, @zone_a].each { |entity| EXCLUDING.write(entity, "schema_version" => 1) }
    zone = Zones::Occurrences.zones(@model).find { |row| row.path == [1000] }
    live = Zones::Occurrences.faces(zone).map(&:path)
    snapshot = reader.then do |read|
      entry = read.snapshot.entry_at([1000], :kind => "group")
      Zones::ExportProjection.zone_faces(read, entry).map { |face| face.path[1..-1] }
    end
    [live, snapshot].each do |paths|
      refute_includes paths, [1060, 1061]
      assert_includes paths, [1070, 1071, 1072]
      assert_includes paths, [1001]
    end
  end

  # Classification wins over a record above it: a classified Face inside a marked Group stays envelope, live
  # and in the snapshot; an unclassified one beside it leaves.
  def test_a_classified_face_under_a_marked_group_stays_in_the_envelope
    classified = Sketchup::Face.new(1022, {}, :points => rectangle_z(0, 5, 6, 8, 3),
                                              :normal => Geom::Vector3d.new(0, 0, 1))
    FACE_STORE.write(classified, FACE_STORE.read(face_at(@zone_a, 1002)).merge("id" => "fac_F00000000002"))
    Zones::STAMP_STORE.write(classified, Zones::STAMP_STORE.read(@overhang))
    @fin.entities << classified
    EXCLUDING.write(@fin, "schema_version" => 1)
    zone = Zones::Occurrences.zones(@model).find { |row| row.path == [1000] }
    live = Zones::Occurrences.faces(zone).map(&:path)
    snapshot = reader.then do |read|
      Zones::ExportProjection.zone_faces(read, read.snapshot.entry_at([1000], :kind => "group")).map { |f|
        f.path[1..-1]
      }
    end
    [live, snapshot].each do |paths|
      assert_includes paths, [1020, 1022]
      refute_includes paths, [1020, 1021]
    end
  end

  # Spaces: Create Space's candidate Faces read the check themselves; the offset preflight reads funnels A and D.
  def test_spaces_candidate_faces_leave_out_an_excluded_face
    mark
    row = { "reference" => zone_reference(@zone_a) }
    request = PhComposer::HandlerRequest.for(@session, :owner => PhComposer::Spaces::FEATURE_ID, :name => "test",
                                                       :registry => PhComposer::Registry.current)
    loops = PhComposer::Spaces::CreateFaces.send(:candidate, request, row).faces
    assert_equal 6, loops.length
    clear
    assert_equal 8, PhComposer::Spaces::CreateFaces.send(:candidate, request, row).faces.length
  end

  # Shading drives the same Model: the tagged overhang raises no unclassified finding, clearing the mark brings
  # it back, and a classified Face refuses the tag until Clear classification removes its record.
  def test_shading_tags_the_overhang_out_of_the_envelope_and_clear_brings_it_back
    result = shading("assign", [[1000, 1010], [1000, 1020]])
    assert_equal "completed", result["status"], result.inspect
    findings = query("ph_composer.zones.faces.export_preflight").dig("value", "findings")
    assert_empty(findings.select { |row| row.fetch("code") == "face.unclassified" })
    shading("clear", [[1000, 1010]])
    findings = query("ph_composer.zones.faces.export_preflight").dig("value", "findings")
    assert_equal 1, findings.count { |row| row.fetch("code") == "face.unclassified" }
  end

  def test_a_classified_face_takes_the_tag_after_clear_classification
    wall = face_at(@zone_a, 1003)
    refused = shading("assign", [[1000, 1003]])
    assert_equal %w[refused shading.face_classified], refused.values_at("status", "code")
    assert_includes refused.fetch("message"), "ph_composer.zones.faces.clear_classification"
    reference = zone_reference(@zone_a).merge("entity_path" => [1003], "entity_id" => FACE_STORE.read(wall).fetch("id"))
    stamp = Zones::STAMP_STORE.read(wall)
    cleared = invoke("ph_composer.zones.faces.clear_classification", "faces" => [reference])
    assert_equal "completed", cleared["status"], cleared.inspect
    assert_equal [reference.fetch("entity_id")], cleared.dig("value", "face_ids")
    assert_nil FACE_STORE.read(wall)
    assert_equal stamp, Zones::STAMP_STORE.read(wall)
    row = query("ph_composer.zones.faces.list").dig("value", "faces").find { |face| path_of(face) == [1000, 1003] }
    assert_equal "unclassified", row.fetch("state")
    assert_equal "completed", shading("assign", [[1000, 1003]])["status"]
    @model.undo
    @model.undo
    assert_equal reference.fetch("entity_id"), FACE_STORE.read(face_at(zone_group(1000), 1003))&.fetch("id")
  end

  # Assign refuses a Group inside a Zone when the mark would reach a classified Face, naming the count, and
  # takes it once the classification is cleared.
  def test_assign_refuses_a_group_holding_classified_faces
    FACE_STORE.write(@fin_face, FACE_STORE.read(face_at(@zone_a, 1002)).merge("id" => "fac_F00000000003"))
    refused = shading("assign", [[1000, 1020]])
    assert_equal %w[refused shading.face_classified], refused.values_at("status", "code")
    assert_includes refused.fetch("message"), "holds 1 classified Zone Face(s)"
    FACE_STORE.delete(@fin_face)
    assert_equal "completed", shading("assign", [[1000, 1020]])["status"]
  end

  # A Face classified after the Group above it was marked stays envelope; the preflight notes it.
  def test_a_face_classified_under_a_marked_group_is_noted_by_the_preflight
    assert_equal "completed", shading("assign", [[1000, 1020]])["status"]
    FACE_STORE.write(@fin_face, FACE_STORE.read(face_at(@zone_a, 1002)).merge("id" => "fac_F00000000004"))
    findings = query("ph_composer.shading.export_preflight").dig("value", "findings")
    assert_equal ["shading.classified_inside"], findings.map { |row| row.fetch("code") }
    assert_includes findings.first.fetch("message"), "\"Fin\" at path [1000, 1020]"
    refute findings.first.fetch("blocks_export")
    names = query("ph_composer.shading.list").dig("value", "components").map { |row| row.fetch("display_name") }
    refute_includes names, "Fin"
    unchanged = shading("assign", [[1000, 1020]]).dig("value", "unchanged")
    assert_equal [[1000, 1020]], unchanged.map { |row| row.fetch("entity_path") }
    cleared = shading("clear", [[1000, 1020, 1021]])
    assert_equal [[1000, 1020, 1021]], cleared.dig("value", "unchanged").map { |row| row.fetch("entity_path") }
  end

  def test_clear_classification_refuses_a_surface_pair_an_aperture_host_and_an_excluded_face
    invoke("ph_composer.zones.solve_adjacency", "zones" => [zone_reference(@zone_a), zone_reference(@zone_b)])
    surface = face_at(@zone_a, 1004)
    assert_refused_clear("face.surface_paired", 1004, surface)
    host = face_at(@zone_a, 1003)
    cutting = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([Sketchup::Face.new(1051)]))
    cutting.behavior.cuts_opening = true
    @zone_a.entities << Sketchup::ComponentInstance.new(1050, cutting, :glued_to => host)
    assert_refused_clear("face.aperture_host", 1003, host)
    floor = face_at(@zone_a, 1001)
    EXCLUDING.write(floor, "schema_version" => 1)
    assert_refused_clear("face.outside_envelope", 1001, floor)
  end

  # A mark above a Zone Group never reaches its Faces; Shading's preflight names the Group.
  def test_a_zone_made_inside_a_marked_group_keeps_its_faces_and_raises_zone_inside
    @model.entities.delete(@zone_b)
    wrapper = Sketchup::Group.new(3000, Sketchup::Entities.new([@zone_b]), :name => "Neighbour")
    @model.entities << wrapper
    PhComposer::Shading::Mark::STORE.write(wrapper, "schema_version" => 1)
    zone = zone_row("Zone B")
    assert_equal 6, zone.fetch("face_count")
    findings = query("ph_composer.shading.export_preflight").dig("value", "findings")
    assert_equal ["shading.zone_inside"], findings.map { |row| row.fetch("code") }
    assert_includes findings.first.fetch("message"), "\"Neighbour\" at path [3000]"
    refute(findings.first.fetch("blocks_export"))
    cutting = Sketchup::ComponentDefinition.new(Sketchup::Entities.new([Sketchup::Face.new(3101)]))
    cutting.behavior.cuts_opening = true
    rack = Sketchup::Group.new(3100, Sketchup::Entities.new([Sketchup::ComponentInstance.new(3102, cutting)]))
    @model.entities << rack
    PhComposer::Shading::Mark::STORE.write(rack, "schema_version" => 1)
    findings = query("ph_composer.shading.export_preflight").dig("value", "findings")
    assert_equal 2, findings.length
    assert_includes findings.last.fetch("message"), "a cutting component, such as a Window"
  end

  private

  # Runs the block with both records set (`true`), then cleared (`false`).
  def each_state
    mark
    yield true
    clear
    yield false
  end

  def mark
    EXCLUDING.write(@overhang, "schema_version" => 1)
    EXCLUDING.write(@fin, "schema_version" => 1)
  end

  def clear
    EXCLUDING.delete(@overhang)
    EXCLUDING.delete(@fin)
  end

  def assert_refused_clear(code, persistent_id, face)
    reference = zone_reference(@zone_a).merge("entity_path" => [persistent_id],
                                              "entity_id" => FACE_STORE.read(face).fetch("id"))
    result = invoke("ph_composer.zones.faces.clear_classification", "faces" => [reference])
    assert_equal ["refused", code, "none"], result.values_at("status", "code", "effect")
    refute_nil FACE_STORE.read(face)
  end

  def shading(name, paths)
    invoke("ph_composer.shading.#{name}", "targets" => paths.map { |path| { "entity_path" => path } })
  end

  def collect
    names = [Zones::Faces::ExportProjection::SECTION, Zones::ExportProjection::SECTION,
             PhComposer::Assemblies::ExportProjection::SECTION]
    PhComposer::Export::Collection.build(@model, :run_id => "envelope-#{@sequence += 1}", :contributors => names)
  end

  def reader
    PhComposer::Export::SnapshotReader.new(nil, PhComposer::Export::GeometrySnapshot.capture(@model, :revision => 0))
  end

  def zone_record(extraction, id)
    extraction.document.dig("sections", Zones::ExportProjection::SECTION, "records").find { |row| row["id"] == id }
  end

  def zone_row(name)
    query("ph_composer.zones.list").dig("value", "zones").find { |row| row.dig("values", "name") == name }
  end

  def zone_group(persistent_id)
    @model.entities.to_a.find { |entity| entity.persistent_id == persistent_id }
  end

  def path_of(row)
    row.dig("reference", "zone_path") + row.dig("reference", "entity_path")
  end

  # The Faces of `group` on the x = 5 m plane, facing +x: Zone A's shared wall and any piece cut from it.
  def faces_in(group)
    group.entities.grep(Sketchup::Face).select do |face|
      FACE_STORE.read(face)&.fetch("face_type", nil) == "Wall" && face.normal.x.positive?
    end
  end

  def face_at(group, persistent_id)
    group.entities.to_a.find { |entity| entity.persistent_id == persistent_id }
  end

  def zone_reference(group)
    { "zone_id" => Zones::ZONE_STORE.read(group).fetch("id"), "zone_path" => [group.persistent_id] }
  end

  def box_group(base, x_min, x_max, letter, y_max = 4)
    faces = box_faces(x_min, x_max, y_max).each_with_index.map do |(face_type, normal, loop), index|
      face = Sketchup::Face.new(base + index + 1, {}, :points => loop, :normal => Geom::Vector3d.new(*normal))
      FACE_STORE.write(face, "id" => format("fac_%<letter>s%<number>011d", :letter => letter, :number => index + 1),
                             "schema_version" => 1, "face_type" => face_type, "boundary_condition" => "Outdoors",
                             "assembly_id" => @assembly_id, "user_data" => {}, "extension_data" => {})
      face
    end
    group = Sketchup::Group.new(base, Sketchup::Entities.new(faces))
    zone = { "id" => "zon_#{letter * 12}", "schema_version" => 1, "name" => "Zone #{letter}",
             "building_segment" => "Main Building", "level" => "L1", "ground_depth_mm" => 0.0,
             "user_data" => {}, "extension_data" => {} }
    Zones::ZONE_STORE.write(group, zone)
    faces.each { |face| Zones::STAMP_STORE.write(face, Zones::Schema.stamp(zone)) }
    group
  end

  # Floor, roof and four walls, as 1..6 after `base`: x-min wall third, x-max wall fourth.
  def box_faces(x_min, x_max, y_max = 4)
    x0, x1, y0, y1, z0, z1 = [x_min, x_max, 0, y_max, 0, 3].map { |value| value * M }
    [["Floor", [0, 0, -1], [pt(x0, y0, z0), pt(x0, y1, z0), pt(x1, y1, z0), pt(x1, y0, z0)]],
     ["RoofCeiling", [0, 0, 1], [pt(x0, y0, z1), pt(x1, y0, z1), pt(x1, y1, z1), pt(x0, y1, z1)]],
     ["Wall", [-1, 0, 0], [pt(x0, y0, z0), pt(x0, y0, z1), pt(x0, y1, z1), pt(x0, y1, z0)]],
     ["Wall", [1, 0, 0], [pt(x1, y0, z0), pt(x1, y1, z0), pt(x1, y1, z1), pt(x1, y0, z1)]],
     ["Wall", [0, -1, 0], [pt(x0, y0, z0), pt(x1, y0, z0), pt(x1, y0, z1), pt(x0, y0, z1)]],
     ["Wall", [0, 1, 0], [pt(x0, y1, z0), pt(x0, y1, z1), pt(x1, y1, z1), pt(x1, y1, z0)]]]
  end

  # A horizontal rectangle at height `z` metres.
  def rectangle_z(x_min, x_max, y_min, y_max, z)
    x0, x1, y0, y1, height = [x_min, x_max, y_min, y_max, z].map { |value| value * M }
    [pt(x0, y0, height), pt(x1, y0, height), pt(x1, y1, height), pt(x0, y1, height)]
  end

  def pt(x, y, z)
    Geom::Point3d.new(x, y, z)
  end

  def query(name, params = {})
    API.query(:context => @context, :name => name, :params => params)
  end

  def invoke(name, params)
    @sequence += 1
    API.invoke(:context => @context, :name => name, :params => params,
               :request => { "sequence" => @sequence, "expected_revision" => @session.revision })
  end
end
