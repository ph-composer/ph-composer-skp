# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/window_record_fixtures"
require_relative "../src/ph_composer/features/windows/export"

class WindowExportTest < PhComposerTestCase
  include WindowRecordFixtures

  X = PhComposer::Windows::ExportProjection
  U = PhComposer::Windows::Units

  def setup
    super
    @model = Sketchup.active_model
    @type = window_record
    @type["elements"].first.merge!("glazing_id" => "glz_AAAAAAAAAAAA",
                                   "frames" => W::Types::SIDES.to_h { |side|
                                                 [side, "frm_AAAAAAAAAAAA"]
                                               },
                                   "operation" => { "type" => "fixed",
                                                    "directions" => [] })
    @products = { "frames" => { "frm_AAAAAAAAAAAA" => { "id" => "frm_AAAAAAAAAAAA", "name" => "Frame",
                                                        "width_m" => 0.1, "uf_w_m2k" => 1.0, "psi_g_w_mk" => 0.03 } },
                  "glazings" => { "glz_AAAAAAAAAAAA" => { "id" => "glz_AAAAAAAAAAAA", "name" => "Glazing",
                                                          "ug_w_m2k" => 0.6, "g_value" => 0.5 } },
                  "psi_install_types" => { "psi_AAAAAAAAAAAA" => { "id" => "psi_AAAAAAAAAAAA", "name" => "Standard",
                                                                   "psi_w_mk" => 0.04 } } }
    @settings = W::Settings::DEFAULTS.merge("default_psi_install_id" => "psi_AAAAAAAAAAAA")
    @group = @model.entities.add_group
    @face = @group.entities.add_face([[0, 0, 0], [8, 0, 0], [8, 0, 6], [0, 0, 6]].map { |p|
      Geom::Point3d.new(*p.map { |v| v / 0.0254 })
    })
    @plan = U::DefinitionPlan.build(@type)
    @definition = U::DefinitionWriter.create(:model => @model, :type => @type, :plan => @plan)
    U::DefinitionIndex.write(@model, { @type["id"] => @definition.persistent_id }, :expected => {})
    plane = W::Placement::Plane.new(PhComposer::FaceCapture.call(@face, Geom::Transformation.new))
    axes = [plane.x_axis, plane.y_axis, plane.normal]
    # Local top-left is at x=1.5,z=2.5; +Z points out of the host plane.
    transform = Geom::Transformation.new(axes.flat_map { |a| a + [0] } + [1.5 / 0.0254, 0, 2.5 / 0.0254, 1])
    @unit = @group.entities.add_instance(@definition, transform)
    @unit.glued_to = @face
    U.write(@unit, { "id" => "wun_AAAAAAAAAAAA", "schema_version" => 1,
                     "window_type_id" => @type["id"], "anchor" => "sill_center" })
  end

  def assess(face_values: {}, types: { @type["id"] => @type })
    snapshot = PhComposer::Export::GeometrySnapshot.capture(@model, :revision => 0)
    face = snapshot.entries.find { |e| e.kind == "face" }
    X.assess(:snapshot => snapshot, :types => types, :products => @products, :settings => @settings,
             :faces => [{ "path" => face.path, "geometry" => face.geometry, "zone_id" => "zon_AAAAAAAAAAAA",
                          "record" => { "id" => "fac_AAAAAAAAAAAA", "face_type" => "Wall",
                                        "boundary_condition" => "Outdoors" }.merge(face_values) }])
  end

  def codes
    assess.findings.map { |f| f["code"] }
  end

  def test_valid_aperture_is_detached_si_and_resolves_perimeter_defaults
    result = assess
    assert_empty result.findings
    row = result.apertures.fetch(0)
    assert_equal "fac_AAAAAAAAAAAA", row["host_face_id"]
    assert_equal "zon_AAAAAAAAAAAA", row["zone_id"]
    assert_in_delta 1.5, @plan.width_m * @plan.height_m, 1e-10
    assert_equal [[1.5, 0.0, 1.0], [2.5, 0.0, 1.0], [2.5, 0.0, 2.5], [1.5, 0.0, 2.5]], row["polygon_m"]
    construction = result.constructions.fetch(0)
    assert_equal 0.04, construction.dig("sides", "top", "psi_install_w_mk")
    assert_in_delta W::Thermal.calculate(@type, @products, @settings["default_psi_install_id"])
                              .fetch("elements").first.fetch("uw_w_m2k"), construction["uw_w_m2k"], 1e-12
    refute row["is_operable"]
    # The outline the Apertures projection gives other sections: the whole Unit, here its single pane.
    assert_equal [[row["unit_id"], row["polygon_m"]]],
                 result.outlines.map { |outline| outline.values_at("unit_id", "outline_m") }
    assert_empty @model.operation_starts
  end

  def test_native_snapshot_caches_detached_definition_facts_and_never_uses_face_area
    @face.define_singleton_method(:area) { raise "Face.area is not gross export geometry" }
    copy = @group.entities.add_instance(@definition, @unit.transformation)
    snapshot = PhComposer::Export::GeometrySnapshot.capture(@model, :revision => 7)
    entries = snapshot.entries.select { |entry| entry.kind == "component_instance" }
    assert_same entries[0].native.fetch("definition"), entries[1].native.fetch("definition")
    assert_equal @face.persistent_id, entries[0].native.fetch("glued_to_id")
    assert_equal 48.0, snapshot.entries.find { |entry| entry.kind == "face" }.geometry.area_m2
    @definition.entities.clear!
    assert_equal 1, entries[0].native.fetch("definition").fetch("entities").count { |row| row["kind"] == "face" }
    assert_equal 7, snapshot.revision
    @group.entities.erase_entities(copy)
  end

  def test_host_holes_moves_overlap_and_non_outdoors_have_distinct_blocking_rows
    assert_includes assess(:face_values => { "boundary_condition" => "Surface" }).findings.map { |f| f["code"] },
                    "window.surface_host"
    assert_includes assess(:face_values => { "boundary_condition" => "Ground" }).findings.map { |f| f["code"] },
                    "window.host_boundary_unsupported"
    assert_includes assess(:face_values => { "face_type" => nil }).findings.map { |f| f["code"] },
                    "window.host_unclassified"
    assert_includes assess(:types => {}).findings.map { |f| f["code"] }, "window.unknown_type"
    assert_includes assess(:face_values => { "face_type" => "Floor" }).findings.map { |f| f["code"] },
                    "window.host_type_unsupported"
    @face.add_hole!([[1.8, 0, 1.2], [2.2, 0, 1.2], [2.2, 0, 1.4], [1.8, 0, 1.4]].map { |p|
      Geom::Point3d.new(*p.map { |v| v / 0.0254 })
    })
    assert_includes codes, "window.overhang"
    @face.loops.pop
    copy = @group.entities.add_instance(@definition, @unit.transformation)
    copy.glued_to = @face
    U.write(copy, U.read(@unit).merge("id" => "wun_BBBBBBBBBBBB"))
    result = assess
    assert_equal 2, result.findings.count { |row| row["code"] == "window.overlap" }
    assert_empty result.apertures
    @group.entities.erase_entities(copy)
    @face.transform!(Geom::Transformation.translation([0, 1, 0]))
    assert_includes codes, "geometry.invalid"
  end

  def test_detached_definition_geometry_and_extra_edges_refuse_before_emission
    detached = U::DefinitionWriter.create(:model => @model, :type => @type, :plan => @plan)
    @unit.definition = detached
    assert_includes codes, "window.definition_detached"
    @unit.definition = @definition
    @definition.entities.first.replace_outline!([[0, 0, 0], [100, 0, 0], [100, -100, 0], [0, -100, 0]]
      .map { |p| Geom::Point3d.new(*p) })
    assert_includes codes, "window.geometry_differs"
    @definition.set_attribute(U::DEFINITION_STORE.dictionary, U::DEFINITION_STORE.key, "not JSON")
    assert_includes codes, "record.unreadable"
  end

  def test_a_type_condition_on_two_elements_is_two_rows_each_naming_its_element
    first = @type.fetch("elements").first
    @type["columns_m"] = [1.0, 1.0]
    @type["elements"] = [first.merge("name" => "Left", "column_span" => [0, 0]),
                         PhComposer::DeepCopy.call(first).merge("id" => "wel_BBBBBBBBBBBB", "name" => "Right",
                                                                "column_span" => [1, 1])]
    U::DefinitionWriter.rewrite(:model => @model, :definition => @definition,
                                :type => @type, :plan => U::DefinitionPlan.build(@type))
    @products["glazings"].values.first.delete("g_value")
    rows = assess.findings.select { |row| row.fetch("code") == "window_type.g_value_missing" }
    assert_equal ["Test type, Left: Missing g-value.", "Test type, Right: Missing g-value."],
                 rows.map { |row| row.fetch("message") }.sort
  end

  def test_mulled_empty_and_merged_elements_keep_ids_and_shared_install_zero
    first = @type.fetch("elements").first
    @type["columns_m"] = [0.5, 0.5, 0.5]
    @type["rows_m"] = [0.75, 0.75]
    empty = W::Types.blank(0, 1, :identity => window_allocator).merge("kind" => "empty")
    @type["elements"] = [first.merge("row_span" => [0, 1]), empty.merge("row_span" => [0, 1]),
                         PhComposer::DeepCopy.call(first).merge("id" => "wel_BBBBBBBBBBBB", "row_span" => [0, 1],
                                                                "column_span" => [2,
                                                                                  2])]
    U::DefinitionWriter.rewrite(:model => @model, :definition => @definition,
                                :type => @type, :plan => U::DefinitionPlan.build(@type))
    result = assess
    assert_empty result.findings
    assert_equal [first["id"], "wel_BBBBBBBBBBBB"].sort, result.apertures.map { |row| row["element_id"] }.sort
    @type["elements"] = [first.merge("row_span" => [0, 1]),
                         PhComposer::DeepCopy.call(first).merge("id" => "wel_BBBBBBBBBBBB", "row_span" => [0, 1],
                                                                "column_span" => [1, 2])]
    U::DefinitionWriter.rewrite(:model => @model, :definition => @definition,
                                :type => @type, :plan => U::DefinitionPlan.build(@type))
    shared = assess.constructions.flat_map { |row| row["sides"].values }.select { |side| side["install_id"].nil? }
    assert_equal 2, shared.length
    assert shared.all? { |side| side["psi_install_w_mk"] == 0.0 && side["install_name"].nil? }
  end

  def seed_export_records
    W::Types::KIND.store.write(@model, @type)
    @products.each do |collection, rows|
      kind = W::Products::KINDS.fetch(collection)
      rows.each_value { |row| kind.store.write(@model, row.merge("schema_version" => 1)) }
    end
    W::Settings::SERVICE.store.write(@model, @settings)
    PhComposer::Zones::ZONE_STORE.write(@group,
                                        "id" => "zon_AAAAAAAAAAAA", "schema_version" => 1,
                                        "name" => "Room", "building_segment" => "Main", "level" => "Ground",
                                        "ground_depth_mm" => 0)
    PhComposer::Zones::Faces::FACE_STORE.write(@face, "id" => "fac_AAAAAAAAAAAA", "schema_version" => 1,
                                                      "face_type" => "Wall", "boundary_condition" => "Outdoors")
  end

  def test_public_preflight_and_two_contributors_share_projection_and_omit_local_metadata
    seed_export_records
    @type["user_data"] = { "private" => "local-only" }
    W::Types::KIND.store.write(@model, @type)
    U.write(@unit, U.read(@unit).merge("user_data" => { "private" => "local-only" }))
    session = PhComposer::Sessions.for(@model)
    context = PhComposer::API.connect(:session_id => session.id)
    request = PhComposer::HandlerRequest.new(:model => @model, :session => session,
                                             :registry => PhComposer::Registry.current,
                                             :engine => PhComposer::Records::Engine.new(
                                               @model, PhComposer::Registry.current.catalog
                                             ))
    assert_empty X.preflight(request).fetch("findings")
    result = PhComposer::API.query(:context => context, :name => X::PREFLIGHT)
    assert_equal "completed", result["status"], result.inspect
    assert_empty result.dig("value", "findings")
    extracted = PhComposer::Export::Collection.build(@model, :run_id => "test",
                                                             :contributors => [X::CONSTRUCTIONS, X::APERTURES])
    sections = extracted.document.fetch("sections")
    assert_equal 1, sections.fetch(X::CONSTRUCTIONS).fetch("records").length
    assert_equal 1, sections.fetch(X::APERTURES).fetch("records").length
    # The Type's user_data stays local; the Unit's passes through to its Aperture.
    assert_equal 1, extracted.findings.count { |row| row["code"] == "export.metadata_omitted" }
    assert_equal({ "private" => "local-only" }, sections.fetch(X::APERTURES).fetch("records").first["user_data"])
    wire = JSON.generate(sections.fetch(X::CONSTRUCTIONS))
    %w[user_data extension_data source entity_path provider private shading].each { |key| refute_includes wire, key }
    @unit.transformation *= Geom::Transformation.scaling(2, 1, 1)
    refusal = PhComposer::API.query(:context => context, :name => X::PREFLIGHT)
    assert_equal "completed", refusal["status"], refusal.inspect
    assert refusal.dig("value", "findings").any? { |row| row["blocks_export"] }
    repair = refusal.dig("value", "repairs").find { |row| row["action"].end_with?("reset_to_type") }
    assert_equal [{ "unit_id" => U.read(@unit)["id"], "entity_path" => [@group.persistent_id, @unit.persistent_id] }],
                 repair.dig("params", "units")
    assert_raises(PhComposer::Export::Blocked) do
      PhComposer::Export::Collection.build(@model, :run_id => "blocked", :contributors => [X::APERTURES])
    end
    assert_empty @model.operation_starts
  end

  def test_empty_model_has_empty_window_sections_and_no_window_findings
    @model.entities.clear!
    extracted = PhComposer::Export::Collection.build(@model, :run_id => "none",
                                                             :contributors => [X::APERTURES, X::CONSTRUCTIONS])
    assert extracted.document["sections"].values.all? { |section| section["records"].empty? }
    assert_empty extracted.findings
  end

  def test_malformed_unit_records_and_definition_index_are_reported_not_silently_skipped
    seed_export_records
    session = PhComposer::Sessions.for(@model)
    context = PhComposer::API.connect(:session_id => session.id)
    @unit.set_attribute(U::STORE.dictionary, U::STORE.key, "null")
    result = PhComposer::API.query(:context => context, :name => X::PREFLIGHT)
    assert_equal "completed", result["status"], result.inspect
    assert_equal ["record.unreadable"], result.dig("value", "findings").map { |row| row["code"] }
    assert_nil result.dig("value", "findings").first["object_id"]
    @unit.set_attribute(U::STORE.dictionary, U::STORE.key, JSON.generate("id" => 5, "schema_version" => 1))
    invalid = PhComposer::API.query(:context => context, :name => X::PREFLIGHT)
    assert_equal "completed", invalid["status"], invalid.inspect
    assert invalid.dig("value", "findings").all? { |row| row["blocks_export"] }
    U.write(@unit, "id" => "wun_AAAAAAAAAAAA", "schema_version" => 1,
                   "window_type_id" => @type["id"], "anchor" => "sill_center")
    U::DefinitionIndex::STORE.write(@model, "schema_version" => 1, "definitions" => {}, "unexpected" => true)
    assert_includes codes, "record.unreadable"
  end

  UNIT_TAG = PhComposer::Records::Extension.new(:namespace => "test.unit_tag.data", :schema_version => 1,
                                                :export_relevance => "required")

  def install_unit_claim
    extension = UNIT_TAG
    PhComposer::Registry.install([Module.new do
      define_singleton_method(:install) do |registry|
        scope = registry.feature("test.unit_tag", :contract_version => 1, :requires => ["ph_composer.windows"])
        scope.extension(extension)
        scope.export_contributor("test.unit_tag.export", :section_version => 1, :requires => [X::APERTURES],
                                                         :entity_projections => [{
                                                           "namespace" => extension.namespace,
                                                           "target_kind" => U::REFERENCE_KIND,
                                                           "source_section" => X::APERTURES, "fields" => ["tag"]
                                                         }]) do |reader|
          reader.entity_projection(extension.namespace, U::REFERENCE_KIND)
        end
      end
    end])
    seed_export_records
    U.write(@unit, U.read(@unit).merge("extension_data" => { UNIT_TAG.namespace => UNIT_TAG.envelope("tag" => "N1") }))
  end

  def test_public_preflight_accepts_a_required_unit_envelope_an_installed_claim_exports
    install_unit_claim
    session = PhComposer::Sessions.for(@model)
    request = PhComposer::HandlerRequest.new(:model => @model, :session => session,
                                             :registry => PhComposer::Registry.current,
                                             :engine => PhComposer::Records::Engine.new(
                                               @model, PhComposer::Registry.current.catalog
                                             ))

    assert_empty X.preflight(request).fetch("findings")
  end

  # A section that runs Window constructions first must not make the shared assessment capture Unit
  # rows under the wrong section.
  def test_unit_claims_are_captured_by_apertures_even_when_constructions_run_first
    install_unit_claim
    PhComposer::Registry.install([Module.new do
      define_singleton_method(:install) do |registry|
        registry.feature("aaa.probe", :contract_version => 1, :requires => ["ph_composer.windows"])
                .export_contributor("aaa.probe.export", :section_version => 1, :requires => [X::CONSTRUCTIONS]) do |_r|
          []
        end
      end
    end])

    extraction = PhComposer::Export::Collection.build(
      @model, :run_id => "order", :contributors => ["aaa.probe.export", X::CONSTRUCTIONS, X::APERTURES,
                                                    "test.unit_tag.export"]
    )

    rows = extraction.document.dig("sections", "test.unit_tag.export", "records")
    assert_equal [{ "tag" => "N1" }], rows.map { |row| row["payload"] }
  end

  def test_non_json_native_attributes_and_missing_unit_fields_return_completed_blocking_preflight
    seed_export_records
    context = PhComposer::API.connect(:session_id => PhComposer::Sessions.for(@model).id)
    [123, [], "[]", "{}", JSON.generate("id" => "wun_AAAAAAAAAAAA", "user_data" => [])].each do |value|
      @unit.set_attribute(U::STORE.dictionary, U::STORE.key, value)
      result = PhComposer::API.query(:context => context, :name => X::PREFLIGHT)
      assert_equal "completed", result["status"], result.inspect
      assert result.dig("value", "findings").all? { |row| row["blocks_export"] }
      assert_includes %w[record.unreadable validation.failed], result.dig("value", "findings").first["code"]
    end
    U.write(@unit, "id" => "wun_AAAAAAAAAAAA", "schema_version" => 1,
                   "window_type_id" => @type["id"], "anchor" => "sill_center")
    [U::DEFINITION_STORE, U::PANE_STORE].each do |store|
      entity = store == U::DEFINITION_STORE ? @definition : @definition.entities.first
      before = entity.get_attribute(store.dictionary, store.key)
      entity.set_attribute(store.dictionary, store.key, 123)
      result = PhComposer::API.query(:context => context, :name => X::PREFLIGHT)
      assert_equal "completed", result["status"], result.inspect
      assert_equal "record.unreadable", result.dig("value", "findings").first["code"]
      entity.set_attribute(store.dictionary, store.key, before)
    end
  end

  def test_foreign_cutting_container_never_hides_an_authored_unit_from_assessment
    foreign = @model.definitions.add("Foreign cutting component")
    foreign.behavior.cuts_opening = true
    nested = foreign.entities.add_instance(@definition, Geom::Transformation.new)
    U.write(nested, U.read(@unit).merge("id" => "wun_BBBBBBBBBBBB"))
    @group.entities.add_instance(foreign, Geom::Transformation.new)
    snapshot = PhComposer::Export::GeometrySnapshot.capture(@model, :revision => 0)
    assert_equal 2, snapshot.records(U::STORE.dictionary).length
    assert_equal 1, snapshot.entries.count { |entry| entry.kind == "face" }
    result = assess
    unhosted = result.findings.find { |row| row["object_id"] == "wun_BBBBBBBBBBBB" }
    assert_equal "window.unhosted", unhosted["code"]
    assert unhosted["blocks_export"]
  end

  def test_definition_facts_respect_cursor_slice_and_are_captured_once_per_definition
    foreign = @model.definitions.add("Many imported faces")
    foreign.behavior.cuts_opening = true
    25.times do |index|
      foreign.entities.add_face([[index, 0, 0], [index + 1, 0, 0], [index + 1, 1, 0], [index, 1, 0]]
        .map { |point| Geom::Point3d.new(*point) })
    end
    @model.entities.clear!
    2.times { @model.entities.add_instance(foreign, Geom::Transformation.new) }
    captures = 0
    capture = PhComposer::FaceCapture.method(:call)
    counter = lambda do |*args|
      captures += 1
      capture.call(*args)
    end
    PhComposer::FaceCapture.stub(:call, counter) do
      cursor = PhComposer::Export::GeometrySnapshot::Cursor.new(@model)
      cursor.advance(:limit => 1, :budget_seconds => 0)
      assert_equal 1, cursor.count
      assert_equal 1, captures
      cursor.advance(:limit => 1, :budget_seconds => 0) until cursor.done?
      assert_equal 25, captures
      assert_equal 2, cursor.entries.length
      assert_same cursor.entries[0].native["definition"], cursor.entries[1].native["definition"]
    end
  end

  def test_required_extension_data_refuses_and_public_face_context_is_detached_and_metadata_safe
    seed_export_records
    snapshot = PhComposer::Export::GeometrySnapshot.capture(@model, :revision => 0)
    records = PhComposer::Export::RecordReader.new(
      PhComposer::Records::Engine.new(@model,
                                      PhComposer::Registry.current.catalog), PhComposer::Registry.current.catalog
    )
    reader = PhComposer::Export::SnapshotReader.new(records, snapshot)
    stored = PhComposer::Zones::Faces::FACE_STORE.read(@face)
    PhComposer::Zones::Faces::FACE_STORE.write(@face, stored.merge("boundary_condition" => "Ground"))
    context = PhComposer::Zones::Faces::ExportProjection.contexts(reader).first
    assert_equal "Outdoors", context.dig("record", "boundary_condition")
    assert_equal [@group.persistent_id, @face.persistent_id], context["path"]
    assert_equal "zon_AAAAAAAAAAAA", context["zone_id"]
    assert_equal %w[assembly_id adjacency boundary_condition face_type id] & stored.keys,
                 context.fetch("record").keys.sort
    PhComposer::Zones::Faces::FACE_STORE.write(@face, stored)
    U.write(@unit, U.read(@unit).merge("extension_data" => { "synthetic.required" => {
      "schema_version" => 1, "export_relevance" => "required", "payload" => { "secret" => "local" }
    } }))
    error = assert_raises(PhComposer::Export::Blocked) do
      PhComposer::Export::Collection.build(@model, :run_id => "private", :contributors => [X::APERTURES])
    end
    assert_equal "extension.unavailable", error.code
    assert_empty @model.operation_starts
  end

  def test_repeated_sliced_collection_captures_model_defaults_and_returns_same_contract
    seed_export_records
    builder = PhComposer::Export::Collection::Builder.new(@model, :run_id => "slice")
    # Ignore other contributors for this isolated geometry/data propagation check.
    declarations = PhComposer::Registry.current.export_contributors
    builder.instance_variable_set(:@contributors,
                                  [declarations.fetch(X::CONSTRUCTIONS), declarations.fetch(X::APERTURES)])
    loop { break if builder.advance }
    rows = builder.extraction.document.fetch("sections").fetch(X::CONSTRUCTIONS).fetch("records")
    assert_equal "Standard", rows.first.dig("sides", "top", "install_name")
    assert_equal 0.04, rows.first.dig("sides", "top", "psi_install_w_mk")
  end

  def test_report_uses_translated_counts_names_areas_and_explicit_schema_exceptions
    result = { "window_usage" => [{ "type_id" => @type["id"], "type_name" => "<Window>",
                                    "zone_id" => "Room", "unit_count" => 2, "aperture_count" => 4,
                                    "install_names" => ["Standard"] }],
               "window_face_areas" => [{ "face_id" => "Host", "zone_id" => "Room", "gross_area_m2" => 10,
                                         "glazed_area_m2" => 3, "net_area_m2" => 7 }],
               "window_schema_exceptions" => [{ "construction_id" => "Construction", "g_value" => 0 }] }
    html = X.report(result, "si").join
    assert_includes html, "&lt;Window&gt;"
    assert_includes html, "Standard"
    assert_includes html, "7.00"
    assert_includes html, "authors no Window shading"
    assert_includes html, "authored g-value 0 is retained exactly"
    hostile = result.merge("window_schema_exceptions" => [{ "construction_id" => "<b>x</b>", "g_value" => "<i>0</i>" }])
    assert_includes X.report(hostile, "si").join, "<p>&lt;b&gt;x&lt;/b&gt;: authored g-value &lt;i&gt;0&lt;/i&gt; is"
    assert_includes X.report(result, "ip").join, "75.35"
    assert_empty X.report({}, "si")
  end

  # Python reads this same extraction. Build real native definitions/occurrences from its product
  # values and rectangles, then compare every thermal value, side and aperture join after mapping
  # fixture identities to legal SKP record ids. Labels are presentation, excluded from deduplication.
  def test_shared_python_fixture_matches_actual_native_projection_and_thermal_references
    fixture = JSON.parse(File.read(File.join(TESTS_ROOT, "fixtures", "windows", "aperture_export_section.json")))
    sections = fixture.fetch("sections")
    construction_inputs = sections.fetch(X::CONSTRUCTIONS).fetch("records").to_h { |row| [row["id"], row] }
    types, expected = build_fixture_apertures(sections.fetch(X::APERTURES).fetch("records"), construction_inputs)
    result = assess(:types => types)
    assert_empty result.findings
    actual_constructions = result.constructions.to_h { |row| [row.fetch("id"), row] }
    assert_equal expected.keys.sort, result.apertures.map { |row| row.fetch("unit_id") }.sort
    result.apertures.each do |actual|
      assert_fixture_aperture(actual, expected.fetch(actual.fetch("unit_id")), actual_constructions)
    end
    small = result.apertures.select { |row| row["variant_type"] == "Synthetic small" }
    assert_equal 2, small.length
    assert_equal small[0]["construction_id"], small[1]["construction_id"]
    assert_equal 4, result.constructions.length
  end

  def build_fixture_apertures(inputs, constructions)
    @fixture_matrix = @unit.transformation.to_a
    @group.entities.erase_entities(@unit)
    @products = { "frames" => {}, "glazings" => {}, "psi_install_types" => {} }
    @settings = W::Settings::DEFAULTS
    types, expected = {}, {}
    index = U::DefinitionIndex.read(@model)
    inputs.each do |input|
      source = constructions.fetch(input.fetch("construction_id"))
      type_id = fixture_identity("wnt", input.fetch("type_id"))
      type = fixture_type(input, source, type_id)
      unless types.key?(type_id)
        types[type_id] = type
        definition = U::DefinitionWriter.create(:model => @model, :type => type,
                                                :plan => U::DefinitionPlan.build(type))
        index[type_id] = definition.persistent_id
      end
      definition = @model.definitions.find { |item| item.persistent_id == index.fetch(type_id) }
      unit_id = fixture_unit(input, definition, type_id)
      expected[unit_id] = [input, source]
    end
    U::DefinitionIndex.write(@model, index, :expected => U::DefinitionIndex.read(@model))
    [types, expected]
  end

  def fixture_type(input, source, type_id)
    width = input.fetch("polygon_m")[1][0] - input.fetch("polygon_m")[0][0]
    height = input.fetch("polygon_m")[2][2] - input.fetch("polygon_m")[1][2]
    glazing = source.fetch("glazing").merge("id" => fixture_identity("glz", source.dig("glazing", "id")))
    @products["glazings"][glazing["id"]] = glazing
    frames, installs = {}, {}
    source.fetch("sides").each do |side, values|
      frame = values.fetch("frame").merge("id" => fixture_identity("frm", values.dig("frame", "id")))
      @products["frames"][frame["id"]] = frame
      frames[side] = frame["id"]
      installs[side] = fixture_identity("psi", values.fetch("install_id"))
      @products["psi_install_types"][installs[side]] = { "id" => installs[side], "name" => values.fetch("install_name"),
                                                         "psi_w_mk" => values.fetch("psi_install_w_mk") }
    end
    cell = @type.fetch("elements").first.merge("id" => fixture_identity("wel", input.fetch("element_id")),
                                               "glazing_id" => glazing["id"], "frames" => frames,
                                               "installs" => installs)
    @type.merge("id" => type_id, "name" => input.fetch("variant_type"), "rows_m" => [height],
                "columns_m" => [width], "elements" => [cell], "install_depth_m" => input.fetch("install_depth_m"))
  end

  def fixture_unit(input, definition, type_id)
    matrix = @fixture_matrix.dup
    matrix[12] = input.fetch("polygon_m")[0][0] / 0.0254
    matrix[14] = input.fetch("polygon_m")[2][2] / 0.0254
    unit = @group.entities.add_instance(definition, Geom::Transformation.new(matrix))
    unit.glued_to = @face
    unit_id = fixture_identity("wun", input.fetch("unit_id"))
    U.write(unit, "id" => unit_id, "schema_version" => 1, "window_type_id" => type_id, "anchor" => "sill_center")
    unit_id
  end

  def assert_fixture_aperture(actual, expected, constructions)
    input, source = expected
    construction = constructions.fetch(actual.fetch("construction_id"))
    assert_equal fixture_identity("wnt", input.fetch("type_id")), actual.fetch("type_id")
    assert_equal fixture_identity("wel", input.fetch("element_id")), actual.fetch("element_id")
    assert_equal input.fetch("variant_type"), actual.fetch("variant_type")
    assert_equal input.fetch("install_depth_m"), actual.fetch("install_depth_m")
    assert_equal input.fetch("is_operable"), actual.fetch("is_operable")
    assert_equal "fac_AAAAAAAAAAAA", actual.fetch("host_face_id")
    assert_equal "zon_AAAAAAAAAAAA", actual.fetch("zone_id")
    input.fetch("polygon_m").zip(actual.fetch("polygon_m")).each do |left, right|
      left.zip(right).each { |a, b| assert_in_delta a, b, 1e-12 }
    end
    assert_in_delta source.fetch("uw_w_m2k"), construction.fetch("uw_w_m2k"), 1e-12
    assert_equal source.fetch("glazing").merge("id" => fixture_identity("glz", source.dig("glazing", "id"))),
                 construction.fetch("glazing")
    source.fetch("sides").each do |side, values|
      expected_side = values.merge("install_id" => fixture_identity("psi", values.fetch("install_id")),
                                   "frame" => values.fetch("frame").merge("id" => fixture_identity(
                                     "frm", values.dig("frame", "id")
                                   )))
      assert_equal expected_side, construction.fetch("sides").fetch(side)
    end
  end

  def fixture_identity(prefix, id)
    "#{prefix}_#{PhComposer::CanonicalJson.digest(id)[0, 12]}"
  end

  def test_shared_ids_unhosted_detached_scaled_mirrored_and_native_geometry_changes_block
    copy = @group.entities.add_instance(@definition, @unit.transformation)
    copy.glued_to = @face
    U.write(copy, U.read(@unit))
    assert_includes codes, "window.copy_id_pending"
    @group.entities.erase_entities(copy)
    @unit.glued_to = nil
    assert_includes codes, "window.unhosted"
    @unit.glued_to = @face
    @unit.transformation = @unit.transformation * Geom::Transformation.scaling(2, 1, 1)
    assert_includes codes, "window.scaled"
    @unit.transformation = @unit.transformation * Geom::Transformation.scaling(-1, 1, 1)
    assert_includes codes, "window.mirrored"
    actions = assess.repairs.map { |row| row.fetch("action") }
    assert_equal ["ph_composer.windows.units.new_flipped_type"], actions, "Reset to Type refuses a mirrored Window"
  end

  def test_missing_product_and_thermal_values_block_without_zero_placeholders
    @products["glazings"].clear
    assert_includes codes, "window_type.product_dangling"
    assert_empty assess.apertures
    @products["glazings"]["glz_AAAAAAAAAAAA"] = { "id" => "glz_AAAAAAAAAAAA", "name" => "Incomplete" }
    assert_includes codes, "window_type.g_value_missing"
    assert_includes codes, "window_type.construction_unresolved"
    assert_empty assess.constructions
  end

  def test_g_value_endpoints_and_size_dependent_construction_signature
    @products["glazings"].values.first["g_value"] = 0
    zero = assess.constructions.first
    assert_equal 0, zero.dig("glazing", "g_value")
    @products["glazings"].values.first["g_value"] = 1
    one = assess.constructions.first
    assert_equal 1, one.dig("glazing", "g_value")
    refute_equal zero["id"], one["id"]
    @type["columns_m"] = [2.0]
    U::DefinitionWriter.rewrite(:model => @model, :definition => @definition,
                                :type => @type, :plan => U::DefinitionPlan.build(@type))
    resized = assess.constructions.first
    refute_equal one["id"], resized["id"]
    refute_equal one["uw_w_m2k"], resized["uw_w_m2k"]
  end

  def test_roof_opening_operability_and_frame_operation_mismatch_are_not_blocking
    @group.entities.erase_entities(@face)
    @face = @group.entities.add_face([[0, 0, 0], [8, 0, 0], [8, 6, 0], [0, 6, 0]].map { |point|
      Geom::Point3d.new(*point.map { |v| v / 0.0254 })
    })
    @unit.glued_to = @face
    @unit.transformation = Geom::Transformation.translation([1.5 / 0.0254, 2.5 / 0.0254, 0])
    @type["elements"].first["operation"] = { "type" => "swing", "directions" => ["left"] }
    @products["frames"].values.first["operation"] = "fixed"
    result = assess(:face_values => { "face_type" => "RoofCeiling" })
    assert result.findings.all? { |row| !row["blocks_export"] }
    assert_equal ["window_type.frame_operation_mismatch"], result.findings.map { |row| row["code"] }.uniq
    assert result.apertures.first["is_operable"]
    assert result.apertures.first["polygon_m"].all? { |point| point[2].zero? }
  end

  def test_dimension_drafts_missing_perimeter_install_and_shear_never_emit_partial_values
    @type["rows_m"] = [nil]
    assert_includes codes, "window_type.dimensions_incomplete"
    assert_empty assess.apertures
    @type["rows_m"] = [1.5]
    @settings["default_psi_install_id"] = nil
    result = assess
    install = result.findings.find { |row| row["code"] == "window_type.install_unresolved" }
    assert_includes install["message"], "Psi-Install Type"
    assert install["blocks_export"]
    @settings["default_psi_install_id"] = "psi_AAAAAAAAAAAA"
    matrix = [1, 0, 0, 0, 0.2, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    @unit.transformation *= Geom::Transformation.new(matrix)
    assert_includes codes, "window.sheared"
    assert_empty assess.apertures
  end

  def test_honeybee_uw_translation_limits_block_assigned_units_without_rewriting_products
    @products["glazings"].values.first["ug_w_m2k"] = 0
    @products["frames"].values.first.merge!("uf_w_m2k" => 0, "psi_g_w_mk" => 0)
    result = assess
    assert_includes result.findings.map { |row| row["code"] }, "window_type.construction_unavailable"
    assert_empty result.apertures
    assert_equal 0, @products["glazings"].values.first["ug_w_m2k"]
    @products["glazings"].values.first["ug_w_m2k"] = 100
    assert_includes codes, "window_type.construction_unavailable"
    assert_empty assess.constructions
  end

  def test_primary_and_pane_stamps_native_behavior_and_id_layout_changes_are_checked
    @definition.behavior.cuts_opening = false
    assert_includes codes, "window.geometry_differs"
    @definition.behavior.cuts_opening = true
    pane = @definition.entities.first
    U::PANE_STORE.write(pane, "window_type_id" => @type["id"], "element_id" => "wel_DDDDDDDDDDDD")
    assert_includes codes, "window.geometry_differs"
    U::DefinitionWriter.rewrite(:model => @model, :definition => @definition, :type => @type, :plan => @plan)
    @type["elements"].first["id"] = "wel_DDDDDDDDDDDD"
    assert_includes codes, "window.geometry_differs"
    U::DefinitionWriter.rewrite(:model => @model, :definition => @definition,
                                :type => @type, :plan => U::DefinitionPlan.build(@type))
    @definition.entities << Sketchup::Edge.new(900009, Geom::Point3d.new(1000, 0, 0),
                                               Geom::Point3d.new(1100, 0, 0))
    assert_includes codes, "window.geometry_differs"
  end

  def test_presentation_changes_retain_construction_and_aperture_identifiers
    before = assess
    @type["name"] = "Renamed Type"
    @type["elements"].first["name"] = "Renamed pane"
    @products["frames"].values.first["name"] = "Renamed Frame"
    @products["glazings"].values.first["name"] = "Renamed Glazing"
    @products["psi_install_types"].values.first["name"] = "Renamed Install"
    after = assess
    assert_equal before.constructions.first["id"], after.constructions.first["id"]
    assert_equal before.apertures.first["id"], after.apertures.first["id"]
    assert_equal "Renamed Type", after.apertures.first["variant_type"]
    assert_equal "Renamed Install", after.constructions.first.dig("sides", "top", "install_name")
  end
end
